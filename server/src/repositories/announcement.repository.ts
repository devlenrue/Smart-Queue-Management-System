/** SQL for `announcements`. Phase 5 needs reads; Phase 7 adds the composer. */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';
import type { AnnouncementStatus } from '../types/domain';

export interface AnnouncementRow {
  id: number;
  title: string;
  content: string;
  service_id: number | null;
  created_by: number | null;
  published_at: string | null;
  expires_at: string | null;
  status: AnnouncementStatus;
  created_at: string;
  updated_at: string;
}

export interface AnnouncementDetailRow extends AnnouncementRow {
  service_name: string | null;
  service_code: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
}

const DETAIL_SELECT = `
  SELECT a.*,
         s.name AS service_name,
         s.code AS service_code,
         u.first_name AS author_first_name,
         u.last_name  AS author_last_name
    FROM announcements a
    LEFT JOIN services s ON s.id = a.service_id
    LEFT JOIN users    u ON u.id = a.created_by
`;

export const announcementRepository = {
  async findById(id: number, conn: DbConn = getDb()): Promise<AnnouncementDetailRow | null> {
    const rows = await conn.query<AnnouncementDetailRow>(`${DETAIL_SELECT} WHERE a.id = ? LIMIT 1`, [id]);
    return rows[0] ?? null;
  },

  /**
   * What a customer is allowed to see: published, not yet expired, and either
   * global (`service_id IS NULL`) or attached to the service being viewed.
   */
  async listPublished(
    filters: { serviceId?: number; page: number; limit: number },
    conn: DbConn = getDb(),
  ): Promise<{ rows: AnnouncementDetailRow[]; total: number }> {
    const now = toSqlDateTime();
    const where = ["a.status = 'published'", 'a.published_at IS NOT NULL', 'a.published_at <= ?'];
    const params: unknown[] = [now];

    where.push('(a.expires_at IS NULL OR a.expires_at > ?)');
    params.push(now);

    if (filters.serviceId !== undefined) {
      where.push('(a.service_id IS NULL OR a.service_id = ?)');
      params.push(filters.serviceId);
    }

    const whereSql = `WHERE ${where.join(' AND ')}`;
    const totals = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM announcements a ${whereSql}`,
      params,
    );

    const offset = (filters.page - 1) * filters.limit;
    const rows = await conn.query<AnnouncementDetailRow>(
      `${DETAIL_SELECT} ${whereSql} ORDER BY a.published_at DESC, a.id DESC LIMIT ? OFFSET ?`,
      [...params, filters.limit, offset],
    );

    return { rows, total: Number(totals[0]?.n ?? 0) };
  },
};
