/**
 * SQL for `staff_assignments`.
 *
 * Rule 4 ("only staff assigned to the service may call its tickets") is
 * answered by `isAssignedToService`.
 */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';

export interface AssignmentRow {
  id: number;
  staff_id: number;
  service_id: number;
  counter_id: number | null;
  assigned_at: string;
  unassigned_at: string | null;
  status: 'active' | 'ended';
  created_at: string;
  updated_at: string;
}

export interface AssignmentDetailRow extends AssignmentRow {
  service_name: string;
  service_code: string;
  counter_number: number | null;
  counter_name: string | null;
  staff_first_name: string;
  staff_last_name: string;
}

const DETAIL_SELECT = `
  SELECT a.*,
         s.name AS service_name,
         s.code AS service_code,
         c.counter_number,
         c.name AS counter_name,
         u.first_name AS staff_first_name,
         u.last_name  AS staff_last_name
    FROM staff_assignments a
    JOIN services s ON s.id = a.service_id
    JOIN users    u ON u.id = a.staff_id
    LEFT JOIN service_counters c ON c.id = a.counter_id
`;

export const assignmentRepository = {
  async isAssignedToService(staffId: number, serviceId: number, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      "SELECT id FROM staff_assignments WHERE staff_id = ? AND service_id = ? AND status = 'active' LIMIT 1",
      [staffId, serviceId],
    );
    return rows.length > 0;
  },

  async findActiveForStaff(staffId: number, conn: DbConn = getDb()): Promise<AssignmentDetailRow | null> {
    const rows = await conn.query<AssignmentDetailRow>(
      `${DETAIL_SELECT} WHERE a.staff_id = ? AND a.status = 'active' ORDER BY a.assigned_at DESC LIMIT 1`,
      [staffId],
    );
    return rows[0] ?? null;
  },

  async listForStaff(staffId: number, conn: DbConn = getDb()): Promise<AssignmentDetailRow[]> {
    return conn.query<AssignmentDetailRow>(`${DETAIL_SELECT} WHERE a.staff_id = ? ORDER BY a.assigned_at DESC`, [staffId]);
  },

  async listForService(serviceId: number, conn: DbConn = getDb()): Promise<AssignmentDetailRow[]> {
    return conn.query<AssignmentDetailRow>(
      `${DETAIL_SELECT} WHERE a.service_id = ? AND a.status = 'active' ORDER BY c.counter_number ASC`,
      [serviceId],
    );
  },

  async create(
    input: { staffId: number; serviceId: number; counterId?: number | null },
    conn: DbConn = getDb(),
  ): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      `INSERT INTO staff_assignments (staff_id, service_id, counter_id, assigned_at, unassigned_at, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, NULL, 'active', ?, ?)`,
      [input.staffId, input.serviceId, input.counterId ?? null, stamp, stamp, stamp],
    );
    return result.insertId;
  },

  /** Ends every active assignment for a staff member (history is kept). */
  async endAllForStaff(staffId: number, conn: DbConn = getDb()): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      "UPDATE staff_assignments SET status = 'ended', unassigned_at = ?, updated_at = ? WHERE staff_id = ? AND status = 'active'",
      [stamp, stamp, staffId],
    );
    return result.affectedRows;
  },

  /** Who is currently posted to this counter, if anybody. */
  async findActiveByCounter(counterId: number, conn: DbConn = getDb()): Promise<AssignmentDetailRow | null> {
    const rows = await conn.query<AssignmentDetailRow>(
      `${DETAIL_SELECT} WHERE a.counter_id = ? AND a.status = 'active' ORDER BY a.assigned_at DESC LIMIT 1`,
      [counterId],
    );
    return rows[0] ?? null;
  },

  /** Ends every active posting that points at a counter (it is being freed or deleted). */
  async endAllForCounter(counterId: number, conn: DbConn = getDb()): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      "UPDATE staff_assignments SET status = 'ended', unassigned_at = ?, updated_at = ? WHERE counter_id = ? AND status = 'active'",
      [stamp, stamp, counterId],
    );
    return result.affectedRows;
  },

  async endById(id: number, conn: DbConn = getDb()): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      "UPDATE staff_assignments SET status = 'ended', unassigned_at = ?, updated_at = ? WHERE id = ? AND status = 'active'",
      [stamp, stamp, id],
    );
    return result.affectedRows;
  },
};
