/**
 * SQL for `queue_tickets` — the busiest table in the system.
 *
 * Position counting (Rule 13) and next-ticket selection both rely on the
 * composite index ix_tickets_queue_status_seq.
 */
import { diffSeconds, forUpdate, getDb, inClause, likeTerm } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';
import { ACTIVE_TICKET_STATUSES, type TicketStatus } from '../types/domain';

export interface TicketRow {
  id: number;
  queue_id: number;
  service_id: number;
  user_id: number;
  ticket_number: string;
  sequence_number: number;
  status: TicketStatus;
  counter_id: number | null;
  estimated_wait_minutes: number | null;
  joined_at: string;
  called_at: string | null;
  service_started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface TicketDetailRow extends TicketRow {
  service_name: string;
  service_code: string;
  queue_date: string;
  queue_status: string;
  counter_number: number | null;
  counter_name: string | null;
  customer_first_name: string;
  customer_last_name: string;
  customer_phone: string;
  customer_email: string;
}

const DETAIL_SELECT = `
  SELECT t.*,
         s.name AS service_name,
         s.code AS service_code,
         q.queue_date,
         q.status AS queue_status,
         c.counter_number,
         c.name AS counter_name,
         u.first_name AS customer_first_name,
         u.last_name  AS customer_last_name,
         u.phone      AS customer_phone,
         u.email      AS customer_email
    FROM queue_tickets t
    JOIN services s ON s.id = t.service_id
    JOIN queues   q ON q.id = t.queue_id
    JOIN users    u ON u.id = t.user_id
    LEFT JOIN service_counters c ON c.id = t.counter_id
`;

export interface CreateTicketInput {
  queueId: number;
  serviceId: number;
  userId: number;
  ticketNumber: string;
  sequenceNumber: number;
  estimatedWaitMinutes: number;
  joinedAt: string;
}

export interface TicketListFilters {
  userId?: number;
  serviceId?: number;
  queueId?: number;
  counterId?: number;
  statuses?: readonly TicketStatus[];
  fromDate?: string;
  toDate?: string;
  search?: string;
  page: number;
  limit: number;
}

export const ticketRepository = {
  async findById(id: number, conn: DbConn = getDb()): Promise<TicketRow | null> {
    const rows = await conn.query<TicketRow>('SELECT * FROM queue_tickets WHERE id = ? LIMIT 1', [id]);
    return rows[0] ?? null;
  },

  async findDetailById(id: number, conn: DbConn = getDb()): Promise<TicketDetailRow | null> {
    const rows = await conn.query<TicketDetailRow>(`${DETAIL_SELECT} WHERE t.id = ? LIMIT 1`, [id]);
    return rows[0] ?? null;
  },

  /** Row lock on a single ticket — used by every staff state transition. */
  async lockById(tx: DbConn, id: number): Promise<TicketRow | null> {
    const rows = await tx.query<TicketRow>(`SELECT * FROM queue_tickets WHERE id = ?${forUpdate(tx.dialect)}`, [id]);
    return rows[0] ?? null;
  },

  /** Rule 1: the user's current active ticket for a service, if any. */
  async findActiveForUserService(userId: number, serviceId: number, conn: DbConn = getDb()): Promise<TicketRow | null> {
    const { sql, params } = inClause(ACTIVE_TICKET_STATUSES);
    const rows = await conn.query<TicketRow>(
      `SELECT * FROM queue_tickets WHERE user_id = ? AND service_id = ? AND status IN ${sql} LIMIT 1`,
      [userId, serviceId, ...params],
    );
    return rows[0] ?? null;
  },

  /** Every active ticket the user holds, across services (customer dashboard). */
  async findActiveForUser(userId: number, conn: DbConn = getDb()): Promise<TicketDetailRow[]> {
    const { sql, params } = inClause(ACTIVE_TICKET_STATUSES);
    return conn.query<TicketDetailRow>(
      `${DETAIL_SELECT} WHERE t.user_id = ? AND t.status IN ${sql} ORDER BY t.joined_at ASC`,
      [userId, ...params],
    );
  },

  /** Whether the user already finished a ticket for this service today. */
  async hasTerminalTicketToday(userId: number, queueId: number, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      `SELECT id FROM queue_tickets
        WHERE user_id = ? AND queue_id = ? AND status IN ('completed','skipped','no_show')
        LIMIT 1`,
      [userId, queueId],
    );
    return rows.length > 0;
  },

  /**
   * Rule 13 — "people ahead" is counted from actual waiting rows, never from a
   * cached counter. Cancelled/skipped/no-show tickets are excluded by
   * definition, which is also Rule 11.
   */
  async countAhead(queueId: number, sequenceNumber: number, conn: DbConn = getDb()): Promise<number> {
    const rows = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM queue_tickets
        WHERE queue_id = ? AND status = 'waiting' AND sequence_number < ?`,
      [queueId, sequenceNumber],
    );
    return Number(rows[0]?.n ?? 0);
  },

  async countWaiting(queueId: number, conn: DbConn = getDb()): Promise<number> {
    const rows = await conn.query<{ n: number }>(
      "SELECT COUNT(*) AS n FROM queue_tickets WHERE queue_id = ? AND status = 'waiting'",
      [queueId],
    );
    return Number(rows[0]?.n ?? 0);
  },

  /** Counts per status for one queue — powers every dashboard tile. */
  async countByStatus(queueId: number, conn: DbConn = getDb()): Promise<Record<TicketStatus, number>> {
    const rows = await conn.query<{ status: TicketStatus; n: number }>(
      'SELECT status, COUNT(*) AS n FROM queue_tickets WHERE queue_id = ? GROUP BY status',
      [queueId],
    );
    const result = {
      waiting: 0, called: 0, serving: 0, completed: 0, cancelled: 0, skipped: 0, no_show: 0,
    } as Record<TicketStatus, number>;
    for (const row of rows) result[row.status] = Number(row.n);
    return result;
  },

  /** The ticket shown as "NOW SERVING". */
  async findNowServing(queueId: number, conn: DbConn = getDb()): Promise<TicketRow | null> {
    const rows = await conn.query<TicketRow>(
      `SELECT * FROM queue_tickets
        WHERE queue_id = ? AND status IN ('called','serving')
        ORDER BY called_at DESC, sequence_number DESC
        LIMIT 1`,
      [queueId],
    );
    return rows[0] ?? null;
  },

  /**
   * The next ticket to call: the lowest waiting sequence number, locked so two
   * staff pressing "Call Next" simultaneously cannot both get it.
   * MUST be called inside a transaction.
   */
  async lockNextWaiting(tx: DbConn, queueId: number): Promise<TicketRow | null> {
    const rows = await tx.query<TicketRow>(
      `SELECT * FROM queue_tickets
        WHERE queue_id = ? AND status = 'waiting'
        ORDER BY sequence_number ASC
        LIMIT 1${forUpdate(tx.dialect)}`,
      [queueId],
    );
    return rows[0] ?? null;
  },

  async listWaiting(queueId: number, limit = 20, conn: DbConn = getDb()): Promise<TicketDetailRow[]> {
    return conn.query<TicketDetailRow>(
      `${DETAIL_SELECT} WHERE t.queue_id = ? AND t.status = 'waiting' ORDER BY t.sequence_number ASC LIMIT ?`,
      [queueId, limit],
    );
  },

  async listLive(queueId: number, conn: DbConn = getDb()): Promise<TicketDetailRow[]> {
    return conn.query<TicketDetailRow>(
      `${DETAIL_SELECT} WHERE t.queue_id = ? AND t.status IN ('called','serving') ORDER BY t.called_at ASC`,
      [queueId],
    );
  },

  /** The ticket a counter is currently working on (Rule 5). */
  async findActiveAtCounter(counterId: number, conn: DbConn = getDb()): Promise<TicketRow | null> {
    const rows = await conn.query<TicketRow>(
      "SELECT * FROM queue_tickets WHERE counter_id = ? AND status IN ('called','serving') LIMIT 1",
      [counterId],
    );
    return rows[0] ?? null;
  },

  async insert(input: CreateTicketInput, tx: DbConn): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await tx.execute(
      `INSERT INTO queue_tickets
         (queue_id, service_id, user_id, ticket_number, sequence_number, status, counter_id,
          estimated_wait_minutes, joined_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'waiting', NULL, ?, ?, ?, ?)`,
      [
        input.queueId,
        input.serviceId,
        input.userId,
        input.ticketNumber,
        input.sequenceNumber,
        input.estimatedWaitMinutes,
        input.joinedAt,
        stamp,
        stamp,
      ],
    );
    return result.insertId;
  },

  /**
   * The single point where a ticket changes state. Timestamp columns are set
   * from the same clock as the status, inside the caller's transaction.
   */
  async transition(
    tx: DbConn,
    ticketId: number,
    status: TicketStatus,
    extras: { counterId?: number | null; timestampColumn?: 'called_at' | 'service_started_at' | 'completed_at' | 'cancelled_at' } = {},
  ): Promise<void> {
    const stamp = toSqlDateTime();
    const sets = ['status = ?', 'updated_at = ?'];
    const params: unknown[] = [status, stamp];

    if (extras.counterId !== undefined) { sets.push('counter_id = ?'); params.push(extras.counterId); }
    if (extras.timestampColumn) { sets.push(`${extras.timestampColumn} = ?`); params.push(stamp); }

    params.push(ticketId);
    await tx.execute(`UPDATE queue_tickets SET ${sets.join(', ')} WHERE id = ?`, params);
  },

  /** Paginated ticket list used by history, staff views and admin search. */
  async list(filters: TicketListFilters, conn: DbConn = getDb()): Promise<{ rows: TicketDetailRow[]; total: number }> {
    const where: string[] = [];
    const params: unknown[] = [];

    if (filters.userId) { where.push('t.user_id = ?'); params.push(filters.userId); }
    if (filters.serviceId) { where.push('t.service_id = ?'); params.push(filters.serviceId); }
    if (filters.queueId) { where.push('t.queue_id = ?'); params.push(filters.queueId); }
    if (filters.counterId) { where.push('t.counter_id = ?'); params.push(filters.counterId); }
    if (filters.statuses?.length) {
      const { sql, params: statusParams } = inClause(filters.statuses);
      where.push(`t.status IN ${sql}`);
      params.push(...statusParams);
    }
    if (filters.fromDate) { where.push('q.queue_date >= ?'); params.push(filters.fromDate); }
    if (filters.toDate) { where.push('q.queue_date <= ?'); params.push(filters.toDate); }
    if (filters.search?.trim()) {
      where.push('(t.ticket_number LIKE ? OR u.first_name LIKE ? OR u.last_name LIKE ? OR u.email LIKE ?)');
      const term = likeTerm(filters.search.trim());
      params.push(term, term, term, term);
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const totals = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
         JOIN users  u ON u.id = t.user_id
         ${whereSql}`,
      params,
    );

    const offset = (filters.page - 1) * filters.limit;
    const rows = await conn.query<TicketDetailRow>(
      `${DETAIL_SELECT} ${whereSql} ORDER BY t.joined_at DESC, t.id DESC LIMIT ? OFFSET ?`,
      [...params, filters.limit, offset],
    );
    return { rows, total: Number(totals[0]?.n ?? 0) };
  },

  /**
   * Measured service time for today (docs/queue-engine.md §5.2): the average
   * minutes between service_started_at and completed_at, and the sample size.
   */
  async measuredServiceMinutes(
    serviceId: number,
    queueDate: string,
    conn: DbConn = getDb(),
  ): Promise<{ averageMinutes: number | null; sampleSize: number }> {
    const expression = diffSeconds(conn.dialect, 't.service_started_at', 't.completed_at');
    const rows = await conn.query<{ avg_seconds: number | null; n: number }>(
      `SELECT AVG(${expression}) AS avg_seconds, COUNT(*) AS n
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE t.service_id = ?
          AND q.queue_date = ?
          AND t.status = 'completed'
          AND t.service_started_at IS NOT NULL
          AND t.completed_at IS NOT NULL`,
      [serviceId, queueDate],
    );
    const sampleSize = Number(rows[0]?.n ?? 0);
    const averageSeconds = rows[0]?.avg_seconds;
    return {
      averageMinutes: sampleSize > 0 && averageSeconds != null ? Number(averageSeconds) / 60 : null,
      sampleSize,
    };
  },

  /** Average minutes customers actually waited before being called. */
  async measuredWaitMinutes(queueId: number, conn: DbConn = getDb()): Promise<number | null> {
    const expression = diffSeconds(conn.dialect, 'joined_at', 'called_at');
    const rows = await conn.query<{ avg_seconds: number | null }>(
      `SELECT AVG(${expression}) AS avg_seconds
         FROM queue_tickets
        WHERE queue_id = ? AND called_at IS NOT NULL`,
      [queueId],
    );
    const value = rows[0]?.avg_seconds;
    return value == null ? null : Number(value) / 60;
  },
};
