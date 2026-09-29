/**
 * SQL for `services`, `service_hours` and `queue_settings` — one family.
 */
import { getDb, likeTerm, safeSortColumn, safeSortDirection } from '../db';
import type { DbConn } from '../db/types';
import { normaliseTime, toSqlDateTime } from '../utils/datetime';
import { config } from '../config/env';
import type { ServiceStatus } from '../types/domain';

export interface ServiceRow {
  id: number;
  name: string;
  code: string;
  description: string | null;
  category: string | null;
  average_service_time: number;
  daily_capacity: number;
  status: ServiceStatus;
  created_at: string;
  updated_at: string;
}

export interface QueueSettingsRow {
  id: number;
  service_id: number;
  max_queue_size: number;
  allow_cancellation: number;
  allow_rejoin: number;
  notification_threshold: number;
  estimated_service_time: number;
}

export interface ServiceHoursRow {
  id: number;
  service_id: number;
  day_of_week: number;
  opening_time: string;
  closing_time: string;
  status: 'open' | 'closed';
}

/** A service joined with its 1:1 settings row — what the engine needs. */
export interface ServiceWithSettings extends ServiceRow {
  max_queue_size: number;
  allow_cancellation: number;
  allow_rejoin: number;
  notification_threshold: number;
  estimated_service_time: number;
}

const SORTABLE: Record<string, string> = {
  name: 'name',
  code: 'code',
  category: 'category',
  status: 'status',
  createdAt: 'created_at',
};

export interface ServiceListFilters {
  status?: ServiceStatus;
  category?: string;
  search?: string;
  page?: number;
  limit?: number;
  sort?: string;
  order?: string;
}

export interface CreateServiceInput {
  name: string;
  code: string;
  description?: string | null;
  category?: string | null;
  averageServiceTime: number;
  dailyCapacity: number;
  status?: ServiceStatus;
}

export const serviceRepository = {
  async findById(id: number, conn: DbConn = getDb()): Promise<ServiceRow | null> {
    const rows = await conn.query<ServiceRow>('SELECT * FROM services WHERE id = ? LIMIT 1', [id]);
    return rows[0] ?? null;
  },

  async findByCode(code: string, conn: DbConn = getDb()): Promise<ServiceRow | null> {
    const rows = await conn.query<ServiceRow>('SELECT * FROM services WHERE code = ? LIMIT 1', [code.toUpperCase()]);
    return rows[0] ?? null;
  },

  /** Service + settings in one round trip; settings fall back to defaults. */
  async findWithSettings(id: number, conn: DbConn = getDb()): Promise<ServiceWithSettings | null> {
    const rows = await conn.query<ServiceWithSettings>(
      `SELECT s.*,
              IFNULL(q.max_queue_size, ?)         AS max_queue_size,
              IFNULL(q.allow_cancellation, 1)     AS allow_cancellation,
              IFNULL(q.allow_rejoin, 1)           AS allow_rejoin,
              IFNULL(q.notification_threshold, ?) AS notification_threshold,
              IFNULL(q.estimated_service_time, s.average_service_time) AS estimated_service_time
         FROM services s
         LEFT JOIN queue_settings q ON q.service_id = s.id
        WHERE s.id = ?
        LIMIT 1`,
      [config.queue.defaultMaxQueueSize, config.queue.defaultNotifyThreshold, id],
    );
    return rows[0] ?? null;
  },

  async codeExists(code: string, exceptId?: number, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      `SELECT id FROM services WHERE code = ?${exceptId ? ' AND id <> ?' : ''} LIMIT 1`,
      exceptId ? [code.toUpperCase(), exceptId] : [code.toUpperCase()],
    );
    return rows.length > 0;
  },

  async list(filters: ServiceListFilters, conn: DbConn = getDb()): Promise<{ rows: ServiceRow[]; total: number }> {
    const where: string[] = [];
    const params: unknown[] = [];

    if (filters.status) { where.push('status = ?'); params.push(filters.status); }
    if (filters.category) { where.push('category = ?'); params.push(filters.category); }
    if (filters.search?.trim()) {
      where.push('(name LIKE ? OR code LIKE ? OR description LIKE ?)');
      const term = likeTerm(filters.search.trim());
      params.push(term, term, term);
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const totals = await conn.query<{ n: number }>(`SELECT COUNT(*) AS n FROM services ${whereSql}`, params);

    const column = safeSortColumn(filters.sort, SORTABLE, 'name');
    const direction = safeSortDirection(filters.order ?? 'asc');
    const limit = filters.limit ?? 100;
    const offset = ((filters.page ?? 1) - 1) * limit;

    const rows = await conn.query<ServiceRow>(
      `SELECT * FROM services ${whereSql} ORDER BY ${column} ${direction}, id ASC LIMIT ? OFFSET ?`,
      [...params, limit, offset],
    );
    return { rows, total: Number(totals[0]?.n ?? 0) };
  },

  async create(input: CreateServiceInput, conn: DbConn = getDb()): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      `INSERT INTO services (name, code, description, category, average_service_time, daily_capacity, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        input.name,
        input.code.toUpperCase(),
        input.description ?? null,
        input.category ?? null,
        input.averageServiceTime,
        input.dailyCapacity,
        input.status ?? 'open',
        stamp,
        stamp,
      ],
    );
    return result.insertId;
  },

  async update(id: number, input: Partial<CreateServiceInput>, conn: DbConn = getDb()): Promise<void> {
    const sets: string[] = [];
    const params: unknown[] = [];
    const push = (column: string, value: unknown): void => { sets.push(`${column} = ?`); params.push(value); };

    if (input.name !== undefined) push('name', input.name);
    if (input.code !== undefined) push('code', input.code.toUpperCase());
    if (input.description !== undefined) push('description', input.description);
    if (input.category !== undefined) push('category', input.category);
    if (input.averageServiceTime !== undefined) push('average_service_time', input.averageServiceTime);
    if (input.dailyCapacity !== undefined) push('daily_capacity', input.dailyCapacity);
    if (input.status !== undefined) push('status', input.status);
    if (sets.length === 0) return;

    push('updated_at', toSqlDateTime());
    params.push(id);
    await conn.execute(`UPDATE services SET ${sets.join(', ')} WHERE id = ?`, params);
  },

  async remove(id: number, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('DELETE FROM services WHERE id = ?', [id]);
    return result.affectedRows;
  },

  // ----------------------------------------------------------- settings
  async findSettings(serviceId: number, conn: DbConn = getDb()): Promise<QueueSettingsRow | null> {
    const rows = await conn.query<QueueSettingsRow>('SELECT * FROM queue_settings WHERE service_id = ? LIMIT 1', [serviceId]);
    return rows[0] ?? null;
  },

  async createDefaultSettings(serviceId: number, estimatedServiceTime: number, conn: DbConn = getDb()): Promise<void> {
    const stamp = toSqlDateTime();
    await conn.execute(
      `INSERT INTO queue_settings (service_id, max_queue_size, allow_cancellation, allow_rejoin, notification_threshold, estimated_service_time, created_at, updated_at)
       VALUES (?, ?, 1, 1, ?, ?, ?, ?)`,
      [serviceId, config.queue.defaultMaxQueueSize, config.queue.defaultNotifyThreshold, estimatedServiceTime, stamp, stamp],
    );
  },

  async updateSettings(
    serviceId: number,
    input: Partial<{
      maxQueueSize: number;
      allowCancellation: boolean;
      allowRejoin: boolean;
      notificationThreshold: number;
      estimatedServiceTime: number;
    }>,
    conn: DbConn = getDb(),
  ): Promise<void> {
    const existing = await this.findSettings(serviceId, conn);
    if (!existing) {
      const service = await this.findById(serviceId, conn);
      await this.createDefaultSettings(serviceId, service?.average_service_time ?? config.queue.defaultServiceMinutes, conn);
    }

    const sets: string[] = [];
    const params: unknown[] = [];
    const push = (column: string, value: unknown): void => { sets.push(`${column} = ?`); params.push(value); };

    if (input.maxQueueSize !== undefined) push('max_queue_size', input.maxQueueSize);
    if (input.allowCancellation !== undefined) push('allow_cancellation', input.allowCancellation ? 1 : 0);
    if (input.allowRejoin !== undefined) push('allow_rejoin', input.allowRejoin ? 1 : 0);
    if (input.notificationThreshold !== undefined) push('notification_threshold', input.notificationThreshold);
    if (input.estimatedServiceTime !== undefined) push('estimated_service_time', input.estimatedServiceTime);
    if (sets.length === 0) return;

    push('updated_at', toSqlDateTime());
    params.push(serviceId);
    await conn.execute(`UPDATE queue_settings SET ${sets.join(', ')} WHERE service_id = ?`, params);
  },

  // -------------------------------------------------------------- hours
  async findHours(serviceId: number, conn: DbConn = getDb()): Promise<ServiceHoursRow[]> {
    return conn.query<ServiceHoursRow>('SELECT * FROM service_hours WHERE service_id = ? ORDER BY day_of_week ASC', [serviceId]);
  },

  async findHoursForDay(serviceId: number, dayOfWeek: number, conn: DbConn = getDb()): Promise<ServiceHoursRow | null> {
    const rows = await conn.query<ServiceHoursRow>(
      'SELECT * FROM service_hours WHERE service_id = ? AND day_of_week = ? LIMIT 1',
      [serviceId, dayOfWeek],
    );
    return rows[0] ?? null;
  },

  async replaceHours(
    serviceId: number,
    hours: Array<{ dayOfWeek: number; openingTime: string; closingTime: string; status: 'open' | 'closed' }>,
    conn: DbConn = getDb(),
  ): Promise<void> {
    await conn.execute('DELETE FROM service_hours WHERE service_id = ?', [serviceId]);
    for (const entry of hours) {
      await conn.execute(
        'INSERT INTO service_hours (service_id, day_of_week, opening_time, closing_time, status) VALUES (?, ?, ?, ?, ?)',
        [serviceId, entry.dayOfWeek, normaliseTime(entry.openingTime), normaliseTime(entry.closingTime), entry.status],
      );
    }
  },

  async distinctCategories(conn: DbConn = getDb()): Promise<string[]> {
    const rows = await conn.query<{ category: string | null }>(
      'SELECT DISTINCT category FROM services WHERE category IS NOT NULL ORDER BY category ASC',
    );
    return rows.map((row) => row.category).filter((value): value is string => Boolean(value));
  },
};
