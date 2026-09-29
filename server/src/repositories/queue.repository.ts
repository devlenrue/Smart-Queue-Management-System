/**
 * SQL for `queues` — the daily queue instance per service.
 *
 * `lockForUpdate` is the linchpin of concurrency-safe ticket numbering
 * (docs/queue-engine.md §3).
 */
import { forUpdate, getDb, isDuplicateKeyError } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime, todayDate } from '../utils/datetime';
import type { QueueStatus } from '../types/domain';

export interface QueueRow {
  id: number;
  service_id: number;
  queue_date: string;
  status: QueueStatus;
  current_number: number;
  last_issued_number: number;
  total_served: number;
  created_at: string;
  updated_at: string;
}

export interface QueueWithServiceRow extends QueueRow {
  service_name: string;
  service_code: string;
  service_status: string;
  average_service_time: number;
}

export const queueRepository = {
  async findById(id: number, conn: DbConn = getDb()): Promise<QueueRow | null> {
    const rows = await conn.query<QueueRow>('SELECT * FROM queues WHERE id = ? LIMIT 1', [id]);
    return rows[0] ?? null;
  },

  async findWithService(id: number, conn: DbConn = getDb()): Promise<QueueWithServiceRow | null> {
    const rows = await conn.query<QueueWithServiceRow>(
      `SELECT q.*, s.name AS service_name, s.code AS service_code,
              s.status AS service_status, s.average_service_time
         FROM queues q
         JOIN services s ON s.id = q.service_id
        WHERE q.id = ?
        LIMIT 1`,
      [id],
    );
    return rows[0] ?? null;
  },

  async findByServiceAndDate(serviceId: number, queueDate: string, conn: DbConn = getDb()): Promise<QueueRow | null> {
    const rows = await conn.query<QueueRow>(
      'SELECT * FROM queues WHERE service_id = ? AND queue_date = ? LIMIT 1',
      [serviceId, queueDate],
    );
    return rows[0] ?? null;
  },

  /**
   * Today's queue row for a service, creating it on first use.
   *
   * Two requests can reach the INSERT at the same time; the loser catches the
   * unique-key violation on (service_id, queue_date) and re-reads the winner's
   * row. This is why `UNIQUE(service_id, queue_date)` exists.
   */
  async getOrCreate(serviceId: number, queueDate = todayDate(), conn: DbConn = getDb()): Promise<QueueRow> {
    const existing = await this.findByServiceAndDate(serviceId, queueDate, conn);
    if (existing) return existing;

    const stamp = toSqlDateTime();
    try {
      await conn.execute(
        `INSERT INTO queues (service_id, queue_date, status, current_number, last_issued_number, total_served, created_at, updated_at)
         VALUES (?, ?, 'waiting', 0, 0, 0, ?, ?)`,
        [serviceId, queueDate, stamp, stamp],
      );
    } catch (error) {
      if (!isDuplicateKeyError(error)) throw error;
    }

    const created = await this.findByServiceAndDate(serviceId, queueDate, conn);
    if (!created) throw new Error(`Could not create the queue for service ${serviceId} on ${queueDate}`);
    return created;
  },

  /**
   * Pessimistic row lock. Every concurrent joiner for the same service blocks
   * here, which is what serialises ticket-number allocation.
   * MUST be called inside a transaction.
   */
  async lockForUpdate(tx: DbConn, queueId: number): Promise<QueueRow | null> {
    const rows = await tx.query<QueueRow>(`SELECT * FROM queues WHERE id = ?${forUpdate(tx.dialect)}`, [queueId]);
    return rows[0] ?? null;
  },

  /** Allocates the next sequence number. Only ever called under the lock. */
  async setIssuedNumber(tx: DbConn, queueId: number, sequenceNumber: number): Promise<void> {
    await tx.execute('UPDATE queues SET last_issued_number = ?, updated_at = ? WHERE id = ?', [
      sequenceNumber,
      toSqlDateTime(),
      queueId,
    ]);
  },

  /** The "NOW SERVING" number. */
  async setCurrentNumber(tx: DbConn, queueId: number, sequenceNumber: number): Promise<void> {
    await tx.execute('UPDATE queues SET current_number = ?, updated_at = ? WHERE id = ?', [
      sequenceNumber,
      toSqlDateTime(),
      queueId,
    ]);
  },

  async incrementServed(tx: DbConn, queueId: number): Promise<void> {
    await tx.execute('UPDATE queues SET total_served = total_served + 1, updated_at = ? WHERE id = ?', [
      toSqlDateTime(),
      queueId,
    ]);
  },

  async setStatus(queueId: number, status: QueueStatus, conn: DbConn = getDb()): Promise<void> {
    await conn.execute('UPDATE queues SET status = ?, updated_at = ? WHERE id = ?', [status, toSqlDateTime(), queueId]);
  },

  async listForDate(
    filters: { queueDate: string; serviceId?: number; status?: QueueStatus },
    conn: DbConn = getDb(),
  ): Promise<QueueWithServiceRow[]> {
    const where: string[] = ['q.queue_date = ?'];
    const params: unknown[] = [filters.queueDate];
    if (filters.serviceId) { where.push('q.service_id = ?'); params.push(filters.serviceId); }
    if (filters.status) { where.push('q.status = ?'); params.push(filters.status); }

    return conn.query<QueueWithServiceRow>(
      `SELECT q.*, s.name AS service_name, s.code AS service_code,
              s.status AS service_status, s.average_service_time
         FROM queues q
         JOIN services s ON s.id = q.service_id
        WHERE ${where.join(' AND ')}
        ORDER BY s.name ASC`,
      params,
    );
  },
};
