/**
 * Aggregate SQL for the four management reports (§41, Phase 8).
 *
 * Everything is derived at read time from `queues`, `queue_tickets` and
 * `queue_events` — the same tables the dashboards read — so a report can
 * never disagree with the console it was run from. Nothing here is cached
 * and no counter column is trusted.
 *
 * The division of labour with `report.service.ts` is deliberate:
 *
 *   repository → one SQL statement per shape of question
 *   service    → the arithmetic SQL is bad at (peak concurrency, averages
 *                over a window, utilisation), plus rounding and presentation
 *
 * That keeps the SQL portable across both dialects (§ dual-driver note in
 * docs/architecture.md) instead of reaching for window functions.
 */
import { diffMinutes, getDb, hourOf } from '../db';
import type { DbConn } from '../db/types';

export interface ReportFilters {
  from: string;
  to: string;
  serviceId?: number;
  staffId?: number;
}

export interface DailyAggregateRow {
  queue_date: string;
  service_id: number;
  service_name: string;
  service_code: string;
  issued: number | null;
  served: number | null;
  cancelled: number | null;
  skipped: number | null;
  no_show: number | null;
  average_wait: number | null;
  average_service: number | null;
}

export interface ServiceAggregateRow extends Omit<DailyAggregateRow, 'queue_date'> {
  service_status: string;
}

export interface HourlyRow {
  service_id: number;
  hour_of_day: number;
  issued: number;
}

export interface StaffAggregateRow {
  staff_id: number;
  first_name: string;
  last_name: string;
  email: string;
  service_id: number;
  service_name: string;
  service_code: string;
  handled: number | null;
  served: number | null;
  skipped: number | null;
  no_show: number | null;
  recalled: number | null;
  average_service: number | null;
}

export interface QueueAggregateRow {
  queue_id: number;
  queue_date: string;
  queue_status: string;
  service_id: number;
  service_name: string;
  service_code: string;
  created_at: string;
  issued: number | null;
  served: number | null;
  first_join: string | null;
  last_activity: string | null;
  counters_used: number | null;
  serving_minutes: number | null;
}

/** One person's stay in the waiting list, for the concurrency sweep. */
export interface WaitingIntervalRow {
  service_id: number;
  queue_date: string;
  started_at: string;
  ended_at: string | null;
}

export interface TotalsAggregateRow {
  issued: number | null;
  served: number | null;
  cancelled: number | null;
  skipped: number | null;
  no_show: number | null;
  average_wait: number | null;
  average_service: number | null;
}

/** The five dispositions every report counts, as SQL. */
const DISPOSITION_COLUMNS = `
  COUNT(t.id) AS issued,
  SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS served,
  SUM(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
  SUM(CASE WHEN t.status = 'skipped'   THEN 1 ELSE 0 END) AS skipped,
  SUM(CASE WHEN t.status = 'no_show'   THEN 1 ELSE 0 END) AS no_show
`;

/**
 * Wait = joined → called (what the customer experienced before reaching a
 * counter). Service = started → completed (what the clerk spent). Tickets
 * that never got that far contribute to neither average rather than being
 * counted as zero, which would flatter both figures.
 */
function averageColumns(conn: DbConn): string {
  const wait = diffMinutes(conn.dialect, 't.joined_at', 't.called_at');
  const service = diffMinutes(conn.dialect, 't.service_started_at', 't.completed_at');
  return `
  AVG(CASE WHEN t.called_at IS NOT NULL THEN ${wait} END) AS average_wait,
  AVG(CASE WHEN t.service_started_at IS NOT NULL AND t.completed_at IS NOT NULL
           THEN ${service} END) AS average_service
`;
}

export const reportRepository = {
  /** §41.1 — one row per (day × service) that had a queue open. */
  async daily(filters: ReportFilters, conn: DbConn = getDb()): Promise<DailyAggregateRow[]> {
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope = ' AND q.service_id = ?';
      params.push(filters.serviceId);
    }

    return conn.query<DailyAggregateRow>(
      `SELECT q.queue_date,
              s.id   AS service_id,
              s.name AS service_name,
              s.code AS service_code,
              ${DISPOSITION_COLUMNS},
              ${averageColumns(conn)}
         FROM queues q
         JOIN services s ON s.id = q.service_id
         LEFT JOIN queue_tickets t ON t.queue_id = q.id
        WHERE q.queue_date BETWEEN ? AND ?${scope}
        GROUP BY q.queue_date, s.id, s.name, s.code
        ORDER BY q.queue_date DESC, s.name ASC`,
      params,
    );
  },

  /** Range-wide totals, computed in SQL rather than by adding up rounded rows. */
  async totals(filters: ReportFilters, conn: DbConn = getDb()): Promise<TotalsAggregateRow> {
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope = ' AND t.service_id = ?';
      params.push(filters.serviceId);
    }

    const rows = await conn.query<TotalsAggregateRow>(
      `SELECT ${DISPOSITION_COLUMNS},
              ${averageColumns(conn)}
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE q.queue_date BETWEEN ? AND ?${scope}`,
      params,
    );
    return (
      rows[0] ?? {
        issued: 0,
        served: 0,
        cancelled: 0,
        skipped: 0,
        no_show: 0,
        average_wait: null,
        average_service: null,
      }
    );
  },

  /**
   * §41.2 — one row per service, including services that saw nobody: an
   * empty counter is a finding, not a gap in the report. The date filter
   * lives in the JOIN, not the WHERE, or the outer join would be undone.
   */
  async services(filters: ReportFilters, conn: DbConn = getDb()): Promise<ServiceAggregateRow[]> {
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope = ' WHERE s.id = ?';
      params.push(filters.serviceId);
    }

    return conn.query<ServiceAggregateRow>(
      `SELECT s.id     AS service_id,
              s.name   AS service_name,
              s.code   AS service_code,
              s.status AS service_status,
              ${DISPOSITION_COLUMNS},
              ${averageColumns(conn)}
         FROM services s
         LEFT JOIN queues q        ON q.service_id = s.id AND q.queue_date BETWEEN ? AND ?
         LEFT JOIN queue_tickets t ON t.queue_id = q.id
         ${scope}
        GROUP BY s.id, s.name, s.code, s.status
        ORDER BY served DESC, s.name ASC`,
      params,
    );
  },

  /** Tickets issued per hour of day, per service — the input to peak hour. */
  async hourly(filters: ReportFilters, conn: DbConn = getDb()): Promise<HourlyRow[]> {
    const hour = hourOf(conn.dialect, 't.joined_at');
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope = ' AND t.service_id = ?';
      params.push(filters.serviceId);
    }

    return conn.query<HourlyRow>(
      `SELECT t.service_id, ${hour} AS hour_of_day, COUNT(*) AS issued
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE q.queue_date BETWEEN ? AND ?${scope}
        GROUP BY t.service_id, ${hour}
        ORDER BY t.service_id ASC, issued DESC`,
      params,
    );
  },

  /**
   * §41.3 — one row per (staff member × service they worked).
   *
   * Attribution follows `queue_events.user_id`: the person who pressed the
   * button owns the outcome. Using the ticket's counter instead would move
   * a morning's work to whoever is standing there in the afternoon.
   */
  async staff(filters: ReportFilters, conn: DbConn = getDb()): Promise<StaffAggregateRow[]> {
    const service = diffMinutes(conn.dialect, 't.service_started_at', 't.completed_at');
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope += ' AND t.service_id = ?';
      params.push(filters.serviceId);
    }
    if (filters.staffId) {
      scope += ' AND u.id = ?';
      params.push(filters.staffId);
    }

    return conn.query<StaffAggregateRow>(
      `SELECT u.id         AS staff_id,
              u.first_name,
              u.last_name,
              u.email,
              s.id   AS service_id,
              s.name AS service_name,
              s.code AS service_code,
              SUM(CASE WHEN e.event_type IN ('called','recalled','service_started','completed','skipped','no_show')
                       THEN 1 ELSE 0 END) AS handled,
              SUM(CASE WHEN e.event_type = 'completed' THEN 1 ELSE 0 END) AS served,
              SUM(CASE WHEN e.event_type = 'skipped'   THEN 1 ELSE 0 END) AS skipped,
              SUM(CASE WHEN e.event_type = 'no_show'   THEN 1 ELSE 0 END) AS no_show,
              SUM(CASE WHEN e.event_type = 'recalled'  THEN 1 ELSE 0 END) AS recalled,
              AVG(CASE WHEN e.event_type = 'completed'
                        AND t.service_started_at IS NOT NULL
                        AND t.completed_at IS NOT NULL
                       THEN ${service} END) AS average_service
         FROM queue_events e
         JOIN queue_tickets t ON t.id = e.ticket_id
         JOIN queues q        ON q.id = t.queue_id
         JOIN users u         ON u.id = e.user_id
         JOIN services s      ON s.id = t.service_id
        WHERE q.queue_date BETWEEN ? AND ?
          AND u.role IN ('staff','admin','super_admin')${scope}
        GROUP BY u.id, u.first_name, u.last_name, u.email, s.id, s.name, s.code
       HAVING handled > 0
        ORDER BY served DESC, u.first_name ASC`,
      params,
    );
  },

  /** §41.4 — one row per queue (service × day), open window included. */
  async queues(filters: ReportFilters, conn: DbConn = getDb()): Promise<QueueAggregateRow[]> {
    const service = diffMinutes(conn.dialect, 't.service_started_at', 't.completed_at');
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope = ' AND q.service_id = ?';
      params.push(filters.serviceId);
    }

    return conn.query<QueueAggregateRow>(
      `SELECT q.id     AS queue_id,
              q.queue_date,
              q.status AS queue_status,
              q.created_at,
              s.id   AS service_id,
              s.name AS service_name,
              s.code AS service_code,
              COUNT(t.id) AS issued,
              SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS served,
              MIN(t.joined_at) AS first_join,
              MAX(COALESCE(t.completed_at, t.cancelled_at, t.called_at, t.joined_at)) AS last_activity,
              COUNT(DISTINCT t.counter_id) AS counters_used,
              SUM(CASE WHEN t.service_started_at IS NOT NULL AND t.completed_at IS NOT NULL
                       THEN ${service} ELSE 0 END) AS serving_minutes
         FROM queues q
         JOIN services s ON s.id = q.service_id
         LEFT JOIN queue_tickets t ON t.queue_id = q.id
        WHERE q.queue_date BETWEEN ? AND ?${scope}
        GROUP BY q.id, q.queue_date, q.status, q.created_at, s.id, s.name, s.code
        ORDER BY q.queue_date DESC, s.name ASC`,
      params,
    );
  },

  /**
   * Every stay in a waiting list inside the range, as a half-open interval.
   *
   * A ticket is "in the queue" from the moment it is issued until it is
   * called (or cancelled before anyone called it). Tickets still waiting
   * have no end yet — the service treats those as running to the end of the
   * window. Sorting here means the sweep can trust the order.
   */
  async waitingIntervals(filters: ReportFilters, conn: DbConn = getDb()): Promise<WaitingIntervalRow[]> {
    const params: unknown[] = [filters.from, filters.to];
    let scope = '';
    if (filters.serviceId) {
      scope = ' AND t.service_id = ?';
      params.push(filters.serviceId);
    }

    return conn.query<WaitingIntervalRow>(
      `SELECT t.service_id,
              q.queue_date,
              t.joined_at AS started_at,
              COALESCE(t.called_at, t.cancelled_at, t.completed_at) AS ended_at
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE q.queue_date BETWEEN ? AND ?${scope}
        ORDER BY t.joined_at ASC`,
      params,
    );
  },
};
