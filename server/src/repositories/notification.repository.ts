/** SQL for `notifications`. */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';
import type { NotificationType } from '../types/domain';

export interface NotificationRow {
  id: number;
  user_id: number;
  ticket_id: number | null;
  title: string;
  message: string;
  type: NotificationType;
  is_read: number;
  created_at: string;
}

export interface CreateNotificationInput {
  userId: number;
  ticketId?: number | null;
  title: string;
  message: string;
  type?: NotificationType;
}

export const notificationRepository = {
  async insert(input: CreateNotificationInput, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute(
      'INSERT INTO notifications (user_id, ticket_id, title, message, type, is_read, created_at) VALUES (?, ?, ?, ?, ?, 0, ?)',
      [input.userId, input.ticketId ?? null, input.title, input.message, input.type ?? 'queue', toSqlDateTime()],
    );
    return result.insertId;
  },

  async list(
    filters: { userId: number; isRead?: boolean; type?: NotificationType; page: number; limit: number },
    conn: DbConn = getDb(),
  ): Promise<{ rows: NotificationRow[]; total: number }> {
    const where = ['user_id = ?'];
    const params: unknown[] = [filters.userId];
    if (filters.isRead !== undefined) { where.push('is_read = ?'); params.push(filters.isRead ? 1 : 0); }
    if (filters.type) { where.push('type = ?'); params.push(filters.type); }

    const whereSql = `WHERE ${where.join(' AND ')}`;
    const totals = await conn.query<{ n: number }>(`SELECT COUNT(*) AS n FROM notifications ${whereSql}`, params);
    const offset = (filters.page - 1) * filters.limit;
    const rows = await conn.query<NotificationRow>(
      `SELECT * FROM notifications ${whereSql} ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?`,
      [...params, filters.limit, offset],
    );
    return { rows, total: Number(totals[0]?.n ?? 0) };
  },

  async findById(id: number, conn: DbConn = getDb()): Promise<NotificationRow | null> {
    const rows = await conn.query<NotificationRow>('SELECT * FROM notifications WHERE id = ? LIMIT 1', [id]);
    return rows[0] ?? null;
  },

  async unreadCount(userId: number, conn: DbConn = getDb()): Promise<number> {
    const rows = await conn.query<{ n: number }>(
      'SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND is_read = 0',
      [userId],
    );
    return Number(rows[0]?.n ?? 0);
  },

  async markRead(id: number, userId: number, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?', [id, userId]);
    return result.affectedRows;
  },

  async markAllRead(userId: number, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0', [userId]);
    return result.affectedRows;
  },
};
