/** SQL for `announcements`. Phase 5 needs reads; Phase 7 adds the composer. */
import { getDb, likeTerm } from '../db';
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

  // -------------------------------------------------------------------------
  // Administrator side (Phase 7) — drafts included, nothing hidden
  // -------------------------------------------------------------------------

  /**
   * Every announcement, whatever its status, for the composer's list.
   * `serviceId` here means "attached to this service", not "visible to it",
   * which is why it is a plain equality rather than the `IS NULL OR =` of
   * `listPublished`.
   */
  async listAll(
    filters: { status?: AnnouncementStatus; serviceId?: number; search?: string; page: number; limit: number },
    conn: DbConn = getDb(),
  ): Promise<{ rows: AnnouncementDetailRow[]; total: number }> {
    const where: string[] = [];
    const params: unknown[] = [];

    if (filters.status) { where.push('a.status = ?'); params.push(filters.status); }
    if (filters.serviceId !== undefined) { where.push('a.service_id = ?'); params.push(filters.serviceId); }
    if (filters.search?.trim()) {
      where.push('(a.title LIKE ? OR a.content LIKE ?)');
      const term = likeTerm(filters.search.trim());
      params.push(term, term);
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const totals = await conn.query<{ n: number }>(`SELECT COUNT(*) AS n FROM announcements a ${whereSql}`, params);

    const offset = (filters.page - 1) * filters.limit;
    const rows = await conn.query<AnnouncementDetailRow>(
      `${DETAIL_SELECT} ${whereSql} ORDER BY COALESCE(a.published_at, a.created_at) DESC, a.id DESC LIMIT ? OFFSET ?`,
      [...params, filters.limit, offset],
    );

    return { rows, total: Number(totals[0]?.n ?? 0) };
  },

  async create(
    input: {
      title: string;
      content: string;
      serviceId?: number | null;
      createdBy: number | null;
      expiresAt?: string | null;
      status: AnnouncementStatus;
      publishedAt?: string | null;
    },
    conn: DbConn = getDb(),
  ): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      `INSERT INTO announcements (title, content, service_id, created_by, published_at, expires_at, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        input.title,
        input.content,
        input.serviceId ?? null,
        input.createdBy,
        input.publishedAt ?? null,
        input.expiresAt ?? null,
        input.status,
        stamp,
        stamp,
      ],
    );
    return result.insertId;
  },

  async update(
    id: number,
    input: Partial<{
      title: string;
      content: string;
      serviceId: number | null;
      expiresAt: string | null;
      status: AnnouncementStatus;
      publishedAt: string | null;
    }>,
    conn: DbConn = getDb(),
  ): Promise<void> {
    const sets: string[] = [];
    const params: unknown[] = [];
    if (input.title !== undefined) { sets.push('title = ?'); params.push(input.title); }
    if (input.content !== undefined) { sets.push('content = ?'); params.push(input.content); }
    if (input.serviceId !== undefined) { sets.push('service_id = ?'); params.push(input.serviceId); }
    if (input.expiresAt !== undefined) { sets.push('expires_at = ?'); params.push(input.expiresAt); }
    if (input.status !== undefined) { sets.push('status = ?'); params.push(input.status); }
    if (input.publishedAt !== undefined) { sets.push('published_at = ?'); params.push(input.publishedAt); }
    if (sets.length === 0) return;
    sets.push('updated_at = ?');
    params.push(toSqlDateTime(), id);
    await conn.execute(`UPDATE announcements SET ${sets.join(', ')} WHERE id = ?`, params);
  },

  async remove(id: number, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('DELETE FROM announcements WHERE id = ?', [id]);
    return result.affectedRows;
  },
};
