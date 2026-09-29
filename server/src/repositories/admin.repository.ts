/**
 * Organisation-wide aggregates for the administrator console (§31, §42).
 *
 * `statistics.repository.ts` answers "how did *this clerk* do?".  This file
 * answers "how is *the whole building* doing?" — the same discipline applies:
 * every number is a SQL aggregate computed at read time, nothing is cached and
 * nothing is incremented by the application, so the dashboard can never drift
 * away from the tickets it is describing.
 */
import { dateOf, diffMinutes, getDb } from '../db';
import type { DbConn } from '../db/types';
import type { ServiceStatus } from '../types/domain';

export interface DayTotalsRow {
  issued: number;
  served: number;
  cancelled: number;
  skipped: number;
  no_show: number;
  waiting: number;
  serving: number;
}

export interface DayAveragesRow {
  averageWaitMinutes: number | null;
  averageServiceMinutes: number | null;
}

export interface ServiceBreakdownRow {
  service_id: number;
  name: string;
  code: string;
  status: ServiceStatus;
  issued: number;
  waiting: number;
  serving: number;
  completed: number;
  cancelled: number;
  wait_minutes: number | null;
}

export interface ServedPerDayRow {
  day: string;
  served: number;
}

export interface HeadcountRow {
  activeServices: number;
  activeQueues: number;
  activeCounters: number;
  staffOnDuty: number;
}

export interface UserActivityRow {
  totalTickets: number;
  completed: number;
  cancelled: number;
  noShow: number;
  active: number;
  lastTicketAt: string | null;
  lastActionAt: string | null;
}

/** Tickets that still occupy a place in a queue. */
const LIVE_STATUSES = "('called','serving')";

export const adminRepository = {
  /**
   * One row of counters for a single queue day, across every service.
   *
   * `issued` counts every ticket the day produced — including the cancelled
   * ones — because that is what "load" means. `served` counts only completions.
   */
  async dayTotals(queueDate: string, conn: DbConn = getDb()): Promise<DayTotalsRow> {
    const rows = await conn.query<DayTotalsRow>(
      `SELECT
         COUNT(t.id) AS issued,
         SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS served,
         SUM(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
         SUM(CASE WHEN t.status = 'skipped'   THEN 1 ELSE 0 END) AS skipped,
         SUM(CASE WHEN t.status = 'no_show'   THEN 1 ELSE 0 END) AS no_show,
         SUM(CASE WHEN t.status = 'waiting'   THEN 1 ELSE 0 END) AS waiting,
         SUM(CASE WHEN t.status IN ${LIVE_STATUSES} THEN 1 ELSE 0 END) AS serving
       FROM queue_tickets t
       JOIN queues q ON q.id = t.queue_id
      WHERE q.queue_date = ?`,
      [queueDate],
    );
    const row = rows[0];
    return {
      issued: Number(row?.issued ?? 0),
      served: Number(row?.served ?? 0),
      cancelled: Number(row?.cancelled ?? 0),
      skipped: Number(row?.skipped ?? 0),
      no_show: Number(row?.no_show ?? 0),
      waiting: Number(row?.waiting ?? 0),
      serving: Number(row?.serving ?? 0),
    };
  },

  /**
   * How long people waited and how long they were served, for one day.
   *
   *   wait    = called_at    − joined_at          (every ticket that was called)
   *   service = completed_at − service_started_at (every ticket that finished)
   */
  async dayAverages(queueDate: string, conn: DbConn = getDb()): Promise<DayAveragesRow> {
    const waitExpr = diffMinutes(conn.dialect, 't.joined_at', 't.called_at');
    const serviceExpr = diffMinutes(conn.dialect, 't.service_started_at', 't.completed_at');

    const rows = await conn.query<{ wait_minutes: number | null; service_minutes: number | null }>(
      `SELECT AVG(CASE WHEN t.called_at IS NOT NULL THEN ${waitExpr} END) AS wait_minutes,
              AVG(CASE WHEN t.service_started_at IS NOT NULL AND t.completed_at IS NOT NULL
                       THEN ${serviceExpr} END) AS service_minutes
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE q.queue_date = ?`,
      [queueDate],
    );
    const row = rows[0];
    return {
      averageWaitMinutes: row?.wait_minutes == null ? null : Number(row.wait_minutes),
      averageServiceMinutes: row?.service_minutes == null ? null : Number(row.service_minutes),
    };
  },

  /**
   * The per-service table of §31.
   *
   * Driven from `services` with LEFT JOINs so a service that has not issued a
   * single ticket today still appears, with zeroes — an administrator needs to
   * see the quiet desk just as much as the busy one.
   */
  async serviceBreakdown(queueDate: string, conn: DbConn = getDb()): Promise<ServiceBreakdownRow[]> {
    const waitExpr = diffMinutes(conn.dialect, 't.joined_at', 't.called_at');

    const rows = await conn.query<ServiceBreakdownRow>(
      `SELECT s.id AS service_id, s.name, s.code, s.status,
              COUNT(t.id) AS issued,
              SUM(CASE WHEN t.status = 'waiting'   THEN 1 ELSE 0 END) AS waiting,
              SUM(CASE WHEN t.status IN ${LIVE_STATUSES} THEN 1 ELSE 0 END) AS serving,
              SUM(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS completed,
              SUM(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
              AVG(CASE WHEN t.called_at IS NOT NULL THEN ${waitExpr} END) AS wait_minutes
         FROM services s
         LEFT JOIN queues q        ON q.service_id = s.id AND q.queue_date = ?
         LEFT JOIN queue_tickets t ON t.queue_id = q.id
        WHERE s.status <> 'inactive'
        GROUP BY s.id, s.name, s.code, s.status
        ORDER BY s.code ASC`,
      [queueDate],
    );
    return rows.map((row) => ({
      service_id: Number(row.service_id),
      name: row.name,
      code: row.code,
      status: row.status,
      issued: Number(row.issued ?? 0),
      waiting: Number(row.waiting ?? 0),
      serving: Number(row.serving ?? 0),
      completed: Number(row.completed ?? 0),
      cancelled: Number(row.cancelled ?? 0),
      wait_minutes: row.wait_minutes == null ? null : Number(row.wait_minutes),
    }));
  },

  /** Completions per queue day — the bar chart of §42. Sparse: quiet days are absent. */
  async servedPerDay(from: string, to: string, conn: DbConn = getDb()): Promise<ServedPerDayRow[]> {
    const rows = await conn.query<{ day: string; served: number }>(
      `SELECT q.queue_date AS day, COUNT(*) AS served
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE t.status = 'completed' AND q.queue_date BETWEEN ? AND ?
        GROUP BY q.queue_date
        ORDER BY q.queue_date ASC`,
      [from, to],
    );
    return rows.map((row) => ({ day: String(row.day).slice(0, 10), served: Number(row.served) }));
  },

  /** Ticket counts by status for one day — the donut of §42. */
  async statusBreakdown(queueDate: string, conn: DbConn = getDb()): Promise<Record<string, number>> {
    const rows = await conn.query<{ status: string; n: number }>(
      `SELECT t.status, COUNT(*) AS n
         FROM queue_tickets t
         JOIN queues q ON q.id = t.queue_id
        WHERE q.queue_date = ?
        GROUP BY t.status`,
      [queueDate],
    );
    return Object.fromEntries(rows.map((row) => [row.status, Number(row.n)]));
  },

  /** The four "how much of the organisation is switched on right now" figures. */
  async headcount(queueDate: string, conn: DbConn = getDb()): Promise<HeadcountRow> {
    const [services, queues, counters, staff] = await Promise.all([
      conn.query<{ n: number }>("SELECT COUNT(*) AS n FROM services WHERE status = 'open'"),
      conn.query<{ n: number }>("SELECT COUNT(*) AS n FROM queues WHERE queue_date = ? AND status <> 'closed'", [queueDate]),
      conn.query<{ n: number }>(`SELECT COUNT(*) AS n FROM service_counters WHERE status IN ('available','busy')`),
      conn.query<{ n: number }>("SELECT COUNT(*) AS n FROM staff_assignments WHERE status = 'active'"),
    ]);
    return {
      activeServices: Number(services[0]?.n ?? 0),
      activeQueues: Number(queues[0]?.n ?? 0),
      activeCounters: Number(counters[0]?.n ?? 0),
      staffOnDuty: Number(staff[0]?.n ?? 0),
    };
  },

  /**
   * The activity block on `GET /users/:id`.
   *
   * Two different notions of "last seen": the last ticket this person *took*
   * (they are a customer) and the last queue event they *caused* (they are a
   * clerk). The service layer keeps whichever is later.
   */
  async userActivity(userId: number, conn: DbConn = getDb()): Promise<UserActivityRow> {
    const [tickets, actions] = await Promise.all([
      conn.query<{
        total: number;
        completed: number;
        cancelled: number;
        no_show: number;
        active: number;
        last_ticket: string | null;
      }>(
        `SELECT COUNT(*) AS total,
                SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
                SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
                SUM(CASE WHEN status = 'no_show'   THEN 1 ELSE 0 END) AS no_show,
                SUM(CASE WHEN status IN ('waiting','called','serving') THEN 1 ELSE 0 END) AS active,
                MAX(joined_at) AS last_ticket
           FROM queue_tickets WHERE user_id = ?`,
        [userId],
      ),
      conn.query<{ last_action: string | null }>(
        'SELECT MAX(created_at) AS last_action FROM queue_events WHERE user_id = ?',
        [userId],
      ),
    ]);

    const row = tickets[0];
    return {
      totalTickets: Number(row?.total ?? 0),
      completed: Number(row?.completed ?? 0),
      cancelled: Number(row?.cancelled ?? 0),
      noShow: Number(row?.no_show ?? 0),
      active: Number(row?.active ?? 0),
      lastTicketAt: row?.last_ticket ?? null,
      lastActionAt: actions[0]?.last_action ?? null,
    };
  },

  /**
   * How many customers registered per day, over a range — the growth line on
   * the dashboard. `dateOf` is the one dialect difference (DATE vs date()).
   */
  async signupsPerDay(from: string, to: string, conn: DbConn = getDb()): Promise<ServedPerDayRow[]> {
    const dayExpr = dateOf(conn.dialect, 'created_at');
    const rows = await conn.query<{ day: string; n: number }>(
      `SELECT ${dayExpr} AS day, COUNT(*) AS n
         FROM users
        WHERE role = 'customer' AND ${dayExpr} BETWEEN ? AND ?
        GROUP BY ${dayExpr}
        ORDER BY day ASC`,
      [from, to],
    );
    return rows.map((row) => ({ day: String(row.day).slice(0, 10), served: Number(row.n) }));
  },
};
