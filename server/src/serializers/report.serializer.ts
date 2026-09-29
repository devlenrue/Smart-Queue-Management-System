/**
 * Report rows → API DTOs (docs/api.md §13).
 *
 * Aggregates arrive as whatever the driver decided: SQLite hands back plain
 * numbers, MySQL returns `DECIMAL` sums as strings, and `AVG` over an empty
 * group is `NULL` in both. Everything is therefore coerced here, once, and
 * every average is rounded to one decimal — the precision the screens and
 * the CSV actually show.
 */
import { toIso } from '../utils/datetime';
import type {
  DailyAggregateRow,
  QueueAggregateRow,
  ServiceAggregateRow,
  StaffAggregateRow,
  TotalsAggregateRow,
} from '../repositories/report.repository';
import type { ServiceStatus } from '../types/domain';

export interface ReportRangeDto {
  from: string;
  to: string;
}

export interface ReportTotalsDto {
  issued: number;
  served: number;
  cancelled: number;
  skipped: number;
  noShow: number;
  averageWaitMinutes: number | null;
  averageServiceMinutes: number | null;
}

export interface DailyReportRowDto {
  date: string;
  serviceId: number;
  serviceName: string;
  serviceCode: string;
  issued: number;
  served: number;
  cancelled: number;
  skipped: number;
  noShow: number;
  averageWaitMinutes: number | null;
  averageServiceMinutes: number | null;
}

export interface ServiceReportRowDto extends Omit<DailyReportRowDto, 'date'> {
  status: ServiceStatus;
  customersServed: number;
  completionRate: number;
  peakHour: number | null;
  peakHourLabel: string | null;
  peakQueueLength: number;
}

export interface StaffReportRowDto {
  staffId: number;
  staffName: string;
  email: string;
  serviceId: number;
  serviceName: string;
  serviceCode: string;
  ticketsHandled: number;
  ticketsServed: number;
  ticketsSkipped: number;
  ticketsNoShow: number;
  ticketsRecalled: number;
  averageServiceMinutes: number | null;
}

export interface QueueReportRowDto {
  queueId: number;
  date: string;
  serviceId: number;
  serviceName: string;
  serviceCode: string;
  status: string;
  issued: number;
  served: number;
  openedAt: string | null;
  closedAt: string | null;
  peakQueue: number;
  averageQueue: number;
  countersUsed: number;
  utilisationPercent: number;
}

/** `null` stays `null` — "no tickets" is not "zero minutes". */
export function round1(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const numeric = Number(value);
  if (Number.isNaN(numeric)) return null;
  return Math.round(numeric * 10) / 10;
}

export function count(value: number | string | null | undefined): number {
  const numeric = Number(value ?? 0);
  return Number.isNaN(numeric) ? 0 : numeric;
}

/** 14 → '14:00–15:00', the way a supervisor would say it. */
export function hourLabel(hour: number | null): string | null {
  if (hour === null) return null;
  const pad = (n: number): string => String(n).padStart(2, '0');
  return `${pad(hour)}:00–${pad((hour + 1) % 24)}:00`;
}

export function serialiseTotals(row: TotalsAggregateRow): ReportTotalsDto {
  return {
    issued: count(row.issued),
    served: count(row.served),
    cancelled: count(row.cancelled),
    skipped: count(row.skipped),
    noShow: count(row.no_show),
    averageWaitMinutes: round1(row.average_wait),
    averageServiceMinutes: round1(row.average_service),
  };
}

export function serialiseDailyRow(row: DailyAggregateRow): DailyReportRowDto {
  return {
    date: String(row.queue_date),
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    issued: count(row.issued),
    served: count(row.served),
    cancelled: count(row.cancelled),
    skipped: count(row.skipped),
    noShow: count(row.no_show),
    averageWaitMinutes: round1(row.average_wait),
    averageServiceMinutes: round1(row.average_service),
  };
}

export function serialiseServiceRow(
  row: ServiceAggregateRow,
  extras: { peakHour: number | null; peakQueueLength: number },
): ServiceReportRowDto {
  const issued = count(row.issued);
  const served = count(row.served);
  return {
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    status: row.service_status as ServiceStatus,
    issued,
    served,
    customersServed: served,
    cancelled: count(row.cancelled),
    skipped: count(row.skipped),
    noShow: count(row.no_show),
    completionRate: issued === 0 ? 0 : Math.round((served / issued) * 100),
    averageWaitMinutes: round1(row.average_wait),
    averageServiceMinutes: round1(row.average_service),
    peakHour: extras.peakHour,
    peakHourLabel: hourLabel(extras.peakHour),
    peakQueueLength: extras.peakQueueLength,
  };
}

export function serialiseStaffRow(row: StaffAggregateRow): StaffReportRowDto {
  return {
    staffId: Number(row.staff_id),
    staffName: `${row.first_name} ${row.last_name}`.trim(),
    email: row.email,
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    ticketsHandled: count(row.handled),
    ticketsServed: count(row.served),
    ticketsSkipped: count(row.skipped),
    ticketsNoShow: count(row.no_show),
    ticketsRecalled: count(row.recalled),
    averageServiceMinutes: round1(row.average_service),
  };
}

export function serialiseQueueRow(
  row: QueueAggregateRow,
  extras: {
    openedAt: string | null;
    closedAt: string | null;
    peakQueue: number;
    averageQueue: number;
    utilisationPercent: number;
  },
): QueueReportRowDto {
  return {
    queueId: Number(row.queue_id),
    date: String(row.queue_date),
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    status: row.queue_status,
    issued: count(row.issued),
    served: count(row.served),
    openedAt: toIso(extras.openedAt),
    closedAt: toIso(extras.closedAt),
    peakQueue: extras.peakQueue,
    averageQueue: extras.averageQueue,
    countersUsed: count(row.counters_used),
    utilisationPercent: extras.utilisationPercent,
  };
}
