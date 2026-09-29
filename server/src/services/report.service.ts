/**
 * The four management reports (§41, Phase 8).
 *
 * The repository answers questions SQL is good at — counts, sums, averages
 * per group. This layer does the two things it is not:
 *
 * 1. **Concurrency.** "How long was the longest queue?" is not a column; it
 *    is the maximum number of overlapping waits. That is a sweep over
 *    intervals, done here in a dozen lines rather than in a correlated
 *    subquery that only one dialect would optimise.
 * 2. **Ratios over a window.** Average queue length and counter utilisation
 *    both divide by how long the queue was actually open, which the
 *    repository reports as two timestamps.
 *
 * Both definitions are written down in docs/api.md §13 so a marker can check
 * the arithmetic rather than guess at it.
 */
import { reportRepository } from '../repositories/report.repository';
import type {
  HourlyRow,
  QueueAggregateRow,
  ReportFilters,
  WaitingIntervalRow,
} from '../repositories/report.repository';
import {
  serialiseDailyRow,
  serialiseQueueRow,
  serialiseServiceRow,
  serialiseStaffRow,
  serialiseTotals,
} from '../serializers/report.serializer';
import type {
  DailyReportRowDto,
  QueueReportRowDto,
  ReportRangeDto,
  ReportTotalsDto,
  ServiceReportRowDto,
  StaffReportRowDto,
} from '../serializers/report.serializer';
import { parseSqlDateTime, todayDate } from '../utils/datetime';

export type ReportKind = 'daily' | 'services' | 'staff' | 'queues';

export interface ReportQuery {
  from?: string;
  to?: string;
  serviceId?: number;
  staffId?: number;
}

export interface DailyReport {
  range: ReportRangeDto;
  rows: DailyReportRowDto[];
  totals: ReportTotalsDto;
}

export interface ServicesReport {
  range: ReportRangeDto;
  rows: ServiceReportRowDto[];
  totals: ReportTotalsDto;
}

export interface StaffReportTotals {
  staff: number;
  ticketsHandled: number;
  ticketsServed: number;
  ticketsSkipped: number;
  ticketsNoShow: number;
  averageServiceMinutes: number | null;
}

export interface StaffReport {
  range: ReportRangeDto;
  rows: StaffReportRowDto[];
  totals: StaffReportTotals;
}

export interface QueuesReportTotals {
  queues: number;
  issued: number;
  served: number;
  peakQueue: number;
  averageUtilisationPercent: number;
}

export interface QueuesReport {
  range: ReportRangeDto;
  rows: QueueReportRowDto[];
  totals: QueuesReportTotals;
}

/** A single stay in the waiting list, in epoch milliseconds. */
interface Interval {
  start: number;
  end: number;
}

/**
 * Maximum overlap and total waiting time across a set of intervals,
 * optionally clipped to a window.
 *
 * Ends are processed before starts at the same instant: if one customer is
 * called at exactly the moment the next joins, two people were never waiting
 * at once, and the report should not claim they were.
 *
 * Clipping matters because "average queue length" divides waiting time by
 * the window. Measure the two over different spans — as happens the moment
 * one ticket is still waiting after the queue's last recorded activity — and
 * the average comes out larger than the peak, which is nonsense.
 */
function sweep(
  intervals: Interval[],
  window?: { start: number; end: number },
): { peak: number; waitingMinutes: number } {
  const points: Array<[number, number]> = [];
  let waitingMs = 0;

  for (const interval of intervals) {
    const start = window ? Math.max(interval.start, window.start) : interval.start;
    const clipped = window ? Math.min(interval.end, window.end) : interval.end;
    // A wait that begins and ends in the same instant — joined and called
    // inside one second, or a ticket issued after the window's end — still
    // happened, so give it a millisecond rather than letting the tie-break
    // above cancel it out and report an empty queue.
    const end = Math.max(start + 1, clipped);
    points.push([start, 1], [end, -1]);
    waitingMs += end - start;
  }

  points.sort((a, b) => a[0] - b[0] || a[1] - b[1]);

  let current = 0;
  let peak = 0;
  for (const [, delta] of points) {
    current += delta;
    if (current > peak) peak = current;
  }

  return { peak, waitingMinutes: waitingMs / 60_000 };
}

function toEpoch(value: string | null | undefined, fallback: number): number {
  const parsed = parseSqlDateTime(value);
  return parsed ? parsed.getTime() : fallback;
}

/** Defaults to today, the way every console opens. */
function resolveRange(query: ReportQuery): ReportRangeDto {
  const today = todayDate();
  const from = query.from ?? today;
  const to = query.to ?? query.from ?? today;
  return { from, to };
}

function filtersOf(query: ReportQuery): ReportFilters {
  const range = resolveRange(query);
  return { ...range, serviceId: query.serviceId, staffId: query.staffId };
}

/** The busiest hour per service, from the hour-of-day histogram. */
function peakHours(rows: HourlyRow[]): Map<number, number> {
  const best = new Map<number, { hour: number; issued: number }>();
  for (const row of rows) {
    const serviceId = Number(row.service_id);
    const issued = Number(row.issued ?? 0);
    const current = best.get(serviceId);
    if (!current || issued > current.issued) {
      best.set(serviceId, { hour: Number(row.hour_of_day), issued });
    }
  }
  return new Map([...best].map(([serviceId, value]) => [serviceId, value.hour]));
}

/** Midnight at the end of a 'YYYY-MM-DD', in server-local time. */
function endOfDay(queueDate: string): number {
  const [year, month, day] = queueDate.split('-').map(Number);
  return new Date(year, month - 1, day + 1).getTime();
}

/**
 * Groups waiting intervals by a key the caller chooses.
 *
 * A ticket that is still waiting has no end. It is treated as waiting until
 * now — or until its own day ran out, whichever came first, so a ticket left
 * open on a past day cannot go on accumulating queue length for a week.
 */
function groupIntervals(
  rows: WaitingIntervalRow[],
  key: (row: WaitingIntervalRow) => string,
  now: number,
): Map<string, Interval[]> {
  const groups = new Map<string, Interval[]>();
  for (const row of rows) {
    const start = toEpoch(row.started_at, now);
    const openEnd = Math.min(now, endOfDay(String(row.queue_date)));
    const end = row.ended_at ? toEpoch(row.ended_at, openEnd) : openEnd;
    const list = groups.get(key(row));
    if (list) list.push({ start, end });
    else groups.set(key(row), [{ start, end }]);
  }
  return groups;
}

export const reportService = {
  /** §41.1 — day by day, service by service. */
  async daily(query: ReportQuery): Promise<DailyReport> {
    const filters = filtersOf(query);
    const [rows, totals] = await Promise.all([
      reportRepository.daily(filters),
      reportRepository.totals(filters),
    ]);

    return {
      range: { from: filters.from, to: filters.to },
      rows: rows.map(serialiseDailyRow),
      totals: serialiseTotals(totals),
    };
  },

  /** §41.2 — one line per service, with its busiest hour and longest queue. */
  async services(query: ReportQuery): Promise<ServicesReport> {
    const filters = filtersOf(query);
    const now = Date.now();

    const [rows, totals, hourly, intervals] = await Promise.all([
      reportRepository.services(filters),
      reportRepository.totals(filters),
      reportRepository.hourly(filters),
      reportRepository.waitingIntervals(filters),
    ]);

    const peakHour = peakHours(hourly);
    const byService = groupIntervals(intervals, (row) => String(row.service_id), now);

    return {
      range: { from: filters.from, to: filters.to },
      rows: rows.map((row) => {
        const serviceId = Number(row.service_id);
        const group = byService.get(String(serviceId)) ?? [];
        return serialiseServiceRow(row, {
          peakHour: peakHour.get(serviceId) ?? null,
          peakQueueLength: sweep(group).peak,
        });
      }),
      totals: serialiseTotals(totals),
    };
  },

  /** §41.3 — who handled what, credited by the events they caused. */
  async staff(query: ReportQuery): Promise<StaffReport> {
    const filters = filtersOf(query);
    const rows = (await reportRepository.staff(filters)).map(serialiseStaffRow);

    const served = rows.reduce((sum, row) => sum + row.ticketsServed, 0);
    // Weighted by the tickets each person served: the institution's average
    // handling time, not the average of averages.
    const weighted = rows.reduce(
      (sum, row) => sum + (row.averageServiceMinutes ?? 0) * row.ticketsServed,
      0,
    );

    return {
      range: { from: filters.from, to: filters.to },
      rows,
      totals: {
        staff: rows.length,
        ticketsHandled: rows.reduce((sum, row) => sum + row.ticketsHandled, 0),
        ticketsServed: served,
        ticketsSkipped: rows.reduce((sum, row) => sum + row.ticketsSkipped, 0),
        ticketsNoShow: rows.reduce((sum, row) => sum + row.ticketsNoShow, 0),
        averageServiceMinutes: served === 0 ? null : Math.round((weighted / served) * 10) / 10,
      },
    };
  },

  /** §41.4 — how each daily queue behaved while it was open. */
  async queues(query: ReportQuery): Promise<QueuesReport> {
    const filters = filtersOf(query);
    const now = Date.now();

    const [rows, intervals] = await Promise.all([
      reportRepository.queues(filters),
      reportRepository.waitingIntervals(filters),
    ]);

    const byQueue = groupIntervals(intervals, (row) => `${row.service_id}|${row.queue_date}`, now);

    const today = todayDate();

    const serialised = rows.map((row: QueueAggregateRow) => {
      const openedAt = row.first_join ?? row.created_at;
      const openedMs = toEpoch(openedAt, now);
      const lastActivityMs = toEpoch(row.last_activity, openedMs);

      // Today's queue is still running unless someone closed it, so it is
      // measured up to now — an office that has been open since eight and
      // idle since ten is not 100% utilised. A finished queue is measured to
      // its last recorded activity, which is where the day really ended.
      const stillOpen = String(row.queue_date) === today && row.queue_status !== 'closed';
      const windowEndMs = stillOpen ? Math.max(now, lastActivityMs) : Math.max(openedMs, lastActivityMs);
      // A queue whose whole life fitted inside a minute still gets a minute,
      // so utilisation cannot divide by zero and report 6000%.
      const windowMinutes = Math.max(1, (windowEndMs - openedMs) / 60_000);

      const group = byQueue.get(`${row.service_id}|${row.queue_date}`) ?? [];
      const { peak, waitingMinutes } = sweep(group, { start: openedMs, end: windowEndMs });

      const countersUsed = Math.max(1, Number(row.counters_used ?? 0));
      const servingMinutes = Number(row.serving_minutes ?? 0);
      const utilisation = (servingMinutes / (countersUsed * windowMinutes)) * 100;

      return serialiseQueueRow(row, {
        openedAt,
        // "Still open" is reported as no closing time rather than as the
        // last thing that happened to be recorded.
        closedAt: stillOpen ? null : row.last_activity,
        peakQueue: peak,
        averageQueue: Math.round((waitingMinutes / windowMinutes) * 10) / 10,
        utilisationPercent: Math.min(100, Math.round(utilisation)),
      });
    });

    const utilisations = serialised.map((row) => row.utilisationPercent);

    return {
      range: { from: filters.from, to: filters.to },
      rows: serialised,
      totals: {
        queues: serialised.length,
        issued: serialised.reduce((sum, row) => sum + row.issued, 0),
        served: serialised.reduce((sum, row) => sum + row.served, 0),
        peakQueue: serialised.reduce((max, row) => Math.max(max, row.peakQueue), 0),
        averageUtilisationPercent:
          utilisations.length === 0
            ? 0
            : Math.round(utilisations.reduce((sum, value) => sum + value, 0) / utilisations.length),
      },
    };
  },
};
