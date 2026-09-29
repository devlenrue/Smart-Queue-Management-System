/**
 * Aggregate SQL for the staff console (§20, §37).
 *
 * Every number here is computed from `queue_tickets` and `queue_events` at
 * read time. Nothing is cached and nothing is incremented by the application,
 * which is why the dashboard, the statistics screen and the Phase 8 reports
 * can never disagree with each other.
 *
 * "Handled by" a staff member means *they* caused the event — `queue_events.
 * user_id`. Using the ticket's counter instead would misattribute work as soon
 * as an administrator reassigns a counter mid-day.
 */
import { diffMinutes, getDb, inClause } from '../db';
import type { DbConn } from '../db/types';
import type { TicketDetailRow } from './ticket.repository';
import type { TicketStatus } from '../types/domain';

export interface DateRange {
  from: string;
  to: string;
}

/** The event types that represent a staff member disposing of a ticket. */
const HANDLED_EVENTS = ['called', 'recalled', 'service_started', 'completed', 'skipped', 'no_show'] as const;

export interface StaffTotalsRow {
  served: number;
  skipped: number;
  no_show: number;
  recalled: number;
}

export interface StaffAveragesRow {
  averageServiceMinutes: number | null;
  averageWaitMinutes: number | null;
}

export interface StaffDayRow {
  day: string;
  served: number;
  averageServiceMinutes: number | null;
}

export interface CounterTallyRow {
  completed: number;
  skipped: number;
  no_show: number;
  cancelled: number;
}

/** `FROM queue_tickets` with every join the detail projection needs. */
const TICKET_JOINS = `
    FROM queue_tickets t
    JOIN queues   q ON q.id = t.queue_id
    JOIN services s ON s.id = t.service_id
    JOIN users    u ON u.id = t.user_id
    LEFT JOIN service_counters c ON c.id = t.counter_id
`;

const TICKET_COLUMNS = `
    t.*,
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
`;

export const statisticsRepository = {
  /**
   * Terminal dispositions credited to one staff member inside a date range.
   *
   * Counting events rather than tickets keeps `skipped` honest: a ticket that
   * was called, skipped and never returned is one skip — not one skip plus a
   * phantom "served".
   */
  async staffTotals(staffId: number, range: DateRange, conn: DbConn = getDb()): Promise<StaffTotalsRow> {
    const rows = await conn.query<StaffTotalsRow>(
      `SELECT
         SUM(CASE WHEN e.event_type = 'completed' THEN 1 ELSE 0 END) AS served,
         SUM(CASE WHEN e.event_type = 'skipped'   THEN 1 ELSE 0 END) AS skipped,
         SUM(CASE WHEN e.event_type = 'no_show'   THEN 1 ELSE 0 END) AS no_show,
         SUM(CASE WHEN e.event_type = 'recalled'  THEN 1 ELSE 0 END) AS recalled
       FROM queue_events e
       JOIN queue_tickets t ON t.id = e.ticket_id
       JOIN queues q        ON q.id = t.queue_id
      WHERE e.user_id = ? AND q.queue_date BETWEEN ? AND ?`,
      [staffId, range.from, range.to],
    );
    const row = rows[0];
    return {
      served: Number(row?.served ?? 0),
      skipped: Number(row?.skipped ?? 0),
      no_show: Number(row?.no_show ?? 0),
      recalled: Number(row?.recalled ?? 0),
    };
  },

  /**
   * Average handling time and average customer wait, over the tickets this
   * staff member completed. Both come from real timestamps:
   *   service time = completed_at - service_started_at
   *   wait time    = called_at    - joined_at
   */
  async staffAverages(staffId: number, range: DateRange, conn: DbConn = getDb()): Promise<StaffAveragesRow> {
    const serviceExpr = diffMinutes(conn.dialect, 't.service_started_at', 't.completed_at');
    const waitExpr = diffMinutes(conn.dialect, 't.joined_at', 't.called_at');

    const rows = await conn.query<{ service_minutes: number | null; wait_minutes: number | null }>(
      `SELECT AVG(CASE WHEN t.service_started_at IS NOT NULL AND t.completed_at IS NOT NULL
                       THEN ${serviceExpr} END) AS service_minutes,
              AVG(CASE WHEN t.called_at IS NOT NULL THEN ${waitExpr} END) AS wait_minutes
         FROM queue_events e
         JOIN queue_tickets t ON t.id = e.ticket_id
         JOIN queues q        ON q.id = t.queue_id
        WHERE e.user_id = ? AND e.event_type = 'completed' AND q.queue_date BETWEEN ? AND ?`,
      [staffId, range.from, range.to],
    );
    const row = rows[0];
    return {
      averageServiceMinutes: row?.service_minutes == null ? null : Number(row.service_minutes),
      averageWaitMinutes: row?.wait_minutes == null ? null : Number(row.wait_minutes),
    };
  },

  /** One row per queue_date — the bars on the statistics screen (§37). */
  async staffByDay(staffId: number, range: DateRange, conn: DbConn = getDb()): Promise<StaffDayRow[]> {
    const serviceExpr = diffMinutes(conn.dialect, 't.service_started_at', 't.completed_at');

    const rows = await conn.query<{ day: string; served: number; service_minutes: number | null }>(
      `SELECT q.queue_date AS day,
              COUNT(*) AS served,
              AVG(CASE WHEN t.service_started_at IS NOT NULL AND t.completed_at IS NOT NULL
                       THEN ${serviceExpr} END) AS service_minutes
         FROM queue_events e
         JOIN queue_tickets t ON t.id = e.ticket_id
         JOIN queues q        ON q.id = t.queue_id
        WHERE e.user_id = ? AND e.event_type = 'completed' AND q.queue_date BETWEEN ? AND ?
        GROUP BY q.queue_date
        ORDER BY q.queue_date ASC`,
      [staffId, range.from, range.to],
    );
    return rows.map((row) => ({
      day: String(row.day).slice(0, 10),
      served: Number(row.served),
      averageServiceMinutes: row.service_minutes == null ? null : Number(row.service_minutes),
    }));
  },

  /**
   * The tickets this staff member touched, newest first — the "what did I do
   * today?" screen. Paginated because a busy counter clears 60+ a day.
   */
  async staffHandledTickets(
    staffId: number,
    filters: { range: DateRange; statuses?: readonly TicketStatus[]; page: number; limit: number },
    conn: DbConn = getDb(),
  ): Promise<{ rows: TicketDetailRow[]; total: number }> {
    const handled = inClause(HANDLED_EVENTS);

    // EXISTS rather than a JOIN onto queue_events: a ticket that was called,
    // recalled and then completed by the same person must appear once.
    const conditions: string[] = [
      `EXISTS (SELECT 1 FROM queue_events e
                WHERE e.ticket_id = t.id AND e.user_id = ? AND e.event_type IN ${handled.sql})`,
      'q.queue_date BETWEEN ? AND ?',
    ];
    const params: unknown[] = [staffId, ...handled.params, filters.range.from, filters.range.to];

    if (filters.statuses?.length) {
      const statuses = inClause(filters.statuses);
      conditions.push(`t.status IN ${statuses.sql}`);
      params.push(...statuses.params);
    }

    const whereSql = `WHERE ${conditions.join(' AND ')}`;

    const countRows = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM queue_tickets t JOIN queues q ON q.id = t.queue_id ${whereSql}`,
      params,
    );
    const total = Number(countRows[0]?.n ?? 0);
    if (total === 0) return { rows: [], total: 0 };

    const offset = (filters.page - 1) * filters.limit;
    const rows = await conn.query<TicketDetailRow>(
      `SELECT ${TICKET_COLUMNS} ${TICKET_JOINS} ${whereSql}
        ORDER BY COALESCE(t.completed_at, t.called_at, t.joined_at) DESC, t.id DESC
        LIMIT ? OFFSET ?`,
      [...params, filters.limit, offset],
    );
    return { rows, total };
  },

  /**
   * Today's tally for one counter — how the dashboard says "you have served
   * 12" rather than "this service has served 45".
   */
  async counterTallyForDate(counterId: number, queueDate: string, conn: DbConn = getDb()): Promise<CounterTallyRow> {
    const rows = await conn.query<CounterTallyRow>(
      `SELECT
         SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS completed,
         SUM(CASE WHEN t.status = 'skipped'   THEN 1 ELSE 0 END) AS skipped,
         SUM(CASE WHEN t.status = 'no_show'   THEN 1 ELSE 0 END) AS no_show,
         SUM(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled
       FROM queue_tickets t
       JOIN queues q ON q.id = t.queue_id
      WHERE t.counter_id = ? AND q.queue_date = ?`,
      [counterId, queueDate],
    );
    const row = rows[0];
    return {
      completed: Number(row?.completed ?? 0),
      skipped: Number(row?.skipped ?? 0),
      no_show: Number(row?.no_show ?? 0),
      cancelled: Number(row?.cancelled ?? 0),
    };
  },
};
