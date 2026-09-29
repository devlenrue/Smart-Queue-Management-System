/** SQL for `service_counters`. */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';
import type { CounterStatus } from '../types/domain';

export interface CounterRow {
  id: number;
  service_id: number;
  counter_number: number;
  name: string;
  status: CounterStatus;
  assigned_staff_id: number | null;
  created_at: string;
  updated_at: string;
}

export interface CounterWithStaffRow extends CounterRow {
  service_name: string;
  service_code: string;
  staff_first_name: string | null;
  staff_last_name: string | null;
  current_ticket: string | null;
}

/** Counters that can actually serve someone right now (§19 denominator). */
const ACTIVE_COUNTER_STATUSES = "('available','busy')";

export const counterRepository = {
  async findById(id: number, conn: DbConn = getDb()): Promise<CounterRow | null> {
    const rows = await conn.query<CounterRow>('SELECT * FROM service_counters WHERE id = ? LIMIT 1', [id]);
    return rows[0] ?? null;
  },

  async findByStaff(staffId: number, conn: DbConn = getDb()): Promise<CounterRow | null> {
    const rows = await conn.query<CounterRow>('SELECT * FROM service_counters WHERE assigned_staff_id = ? LIMIT 1', [staffId]);
    return rows[0] ?? null;
  },

  async listByService(serviceId: number, conn: DbConn = getDb()): Promise<CounterRow[]> {
    return conn.query<CounterRow>('SELECT * FROM service_counters WHERE service_id = ? ORDER BY counter_number ASC', [serviceId]);
  },

  /** Counter list enriched with staff name and the ticket currently at it. */
  async listDetailed(
    filters: { serviceId?: number; status?: CounterStatus },
    conn: DbConn = getDb(),
  ): Promise<CounterWithStaffRow[]> {
    const where: string[] = [];
    const params: unknown[] = [];
    if (filters.serviceId) { where.push('c.service_id = ?'); params.push(filters.serviceId); }
    if (filters.status) { where.push('c.status = ?'); params.push(filters.status); }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    return conn.query<CounterWithStaffRow>(
      `SELECT c.*,
              s.name AS service_name,
              s.code AS service_code,
              u.first_name AS staff_first_name,
              u.last_name  AS staff_last_name,
              (SELECT t.ticket_number FROM queue_tickets t
                WHERE t.counter_id = c.id AND t.status IN ('called','serving')
                ORDER BY t.called_at DESC LIMIT 1) AS current_ticket
         FROM service_counters c
         JOIN services s ON s.id = c.service_id
         LEFT JOIN users u ON u.id = c.assigned_staff_id
         ${whereSql}
        ORDER BY s.code ASC, c.counter_number ASC`,
      params,
    );
  },

  /** The denominator of the waiting-time estimate, never below 1. */
  async countActive(serviceId: number, conn: DbConn = getDb()): Promise<number> {
    const rows = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM service_counters WHERE service_id = ? AND status IN ${ACTIVE_COUNTER_STATUSES}`,
      [serviceId],
    );
    return Number(rows[0]?.n ?? 0);
  },

  async countActiveAll(conn: DbConn = getDb()): Promise<number> {
    const rows = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM service_counters WHERE status IN ${ACTIVE_COUNTER_STATUSES}`,
    );
    return Number(rows[0]?.n ?? 0);
  },

  async numberExists(serviceId: number, counterNumber: number, exceptId?: number, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      `SELECT id FROM service_counters WHERE service_id = ? AND counter_number = ?${exceptId ? ' AND id <> ?' : ''} LIMIT 1`,
      exceptId ? [serviceId, counterNumber, exceptId] : [serviceId, counterNumber],
    );
    return rows.length > 0;
  },

  async create(
    input: { serviceId: number; counterNumber: number; name: string; status?: CounterStatus; assignedStaffId?: number | null },
    conn: DbConn = getDb(),
  ): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      `INSERT INTO service_counters (service_id, counter_number, name, status, assigned_staff_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [input.serviceId, input.counterNumber, input.name, input.status ?? 'offline', input.assignedStaffId ?? null, stamp, stamp],
    );
    return result.insertId;
  },

  async update(
    id: number,
    input: Partial<{ counterNumber: number; name: string; status: CounterStatus }>,
    conn: DbConn = getDb(),
  ): Promise<void> {
    const sets: string[] = [];
    const params: unknown[] = [];
    if (input.counterNumber !== undefined) { sets.push('counter_number = ?'); params.push(input.counterNumber); }
    if (input.name !== undefined) { sets.push('name = ?'); params.push(input.name); }
    if (input.status !== undefined) { sets.push('status = ?'); params.push(input.status); }
    if (sets.length === 0) return;
    sets.push('updated_at = ?');
    params.push(toSqlDateTime(), id);
    await conn.execute(`UPDATE service_counters SET ${sets.join(', ')} WHERE id = ?`, params);
  },

  async setStatus(id: number, status: CounterStatus, conn: DbConn = getDb()): Promise<void> {
    await conn.execute('UPDATE service_counters SET status = ?, updated_at = ? WHERE id = ?', [status, toSqlDateTime(), id]);
  },

  async assignStaff(id: number, staffId: number | null, conn: DbConn = getDb()): Promise<void> {
    await conn.execute('UPDATE service_counters SET assigned_staff_id = ?, status = ?, updated_at = ? WHERE id = ?', [
      staffId,
      staffId ? 'available' : 'offline',
      toSqlDateTime(),
      id,
    ]);
  },

  async remove(id: number, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('DELETE FROM service_counters WHERE id = ?', [id]);
    return result.affectedRows;
  },
};
