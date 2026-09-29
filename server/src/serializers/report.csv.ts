/**
 * The CSV face of each report (§41).
 *
 * Same numbers as the JSON, same order, one column per documented field —
 * the spreadsheet a registrar opens must reconcile with the screen they ran
 * it from. Minutes are written as plain decimals with no unit suffix so the
 * column stays numeric in Excel; an empty cell means "no tickets got that
 * far", which is not the same as zero.
 */
import { toCsv } from '../utils/csv';
import type { CsvColumn } from '../utils/csv';
import type {
  DailyReport,
  QueuesReport,
  ReportKind,
  ServicesReport,
  StaffReport,
} from '../services/report.service';
import type {
  DailyReportRowDto,
  QueueReportRowDto,
  ServiceReportRowDto,
  StaffReportRowDto,
} from './report.serializer';

const dailyColumns: ReadonlyArray<CsvColumn<DailyReportRowDto>> = [
  { header: 'Date', value: (row) => row.date },
  { header: 'Service', value: (row) => row.serviceName },
  { header: 'Code', value: (row) => row.serviceCode },
  { header: 'Issued', value: (row) => row.issued },
  { header: 'Served', value: (row) => row.served },
  { header: 'Cancelled', value: (row) => row.cancelled },
  { header: 'Skipped', value: (row) => row.skipped },
  { header: 'No show', value: (row) => row.noShow },
  { header: 'Average wait (min)', value: (row) => row.averageWaitMinutes },
  { header: 'Average service (min)', value: (row) => row.averageServiceMinutes },
];

const serviceColumns: ReadonlyArray<CsvColumn<ServiceReportRowDto>> = [
  { header: 'Service', value: (row) => row.serviceName },
  { header: 'Code', value: (row) => row.serviceCode },
  { header: 'Status', value: (row) => row.status },
  { header: 'Issued', value: (row) => row.issued },
  { header: 'Customers served', value: (row) => row.customersServed },
  { header: 'Cancelled', value: (row) => row.cancelled },
  { header: 'Skipped', value: (row) => row.skipped },
  { header: 'No show', value: (row) => row.noShow },
  { header: 'Completion rate (%)', value: (row) => row.completionRate },
  { header: 'Average wait (min)', value: (row) => row.averageWaitMinutes },
  { header: 'Average service (min)', value: (row) => row.averageServiceMinutes },
  { header: 'Peak hour', value: (row) => row.peakHourLabel },
  { header: 'Peak queue length', value: (row) => row.peakQueueLength },
];

const staffColumns: ReadonlyArray<CsvColumn<StaffReportRowDto>> = [
  { header: 'Staff', value: (row) => row.staffName },
  { header: 'Email', value: (row) => row.email },
  { header: 'Service', value: (row) => row.serviceName },
  { header: 'Code', value: (row) => row.serviceCode },
  { header: 'Handled', value: (row) => row.ticketsHandled },
  { header: 'Served', value: (row) => row.ticketsServed },
  { header: 'Skipped', value: (row) => row.ticketsSkipped },
  { header: 'No show', value: (row) => row.ticketsNoShow },
  { header: 'Recalled', value: (row) => row.ticketsRecalled },
  { header: 'Average service (min)', value: (row) => row.averageServiceMinutes },
];

const queueColumns: ReadonlyArray<CsvColumn<QueueReportRowDto>> = [
  { header: 'Date', value: (row) => row.date },
  { header: 'Service', value: (row) => row.serviceName },
  { header: 'Code', value: (row) => row.serviceCode },
  { header: 'Status', value: (row) => row.status },
  { header: 'Opened at', value: (row) => row.openedAt },
  { header: 'Closed at', value: (row) => row.closedAt },
  { header: 'Issued', value: (row) => row.issued },
  { header: 'Served', value: (row) => row.served },
  { header: 'Peak queue', value: (row) => row.peakQueue },
  { header: 'Average queue', value: (row) => row.averageQueue },
  { header: 'Counters used', value: (row) => row.countersUsed },
  { header: 'Utilisation (%)', value: (row) => row.utilisationPercent },
];

export type AnyReport = DailyReport | ServicesReport | StaffReport | QueuesReport;

/** Renders whichever report was asked for; the kind decides the columns. */
export function reportToCsv(kind: ReportKind, report: AnyReport): string {
  switch (kind) {
    case 'daily':
      return toCsv(dailyColumns, (report as DailyReport).rows);
    case 'services':
      return toCsv(serviceColumns, (report as ServicesReport).rows);
    case 'staff':
      return toCsv(staffColumns, (report as StaffReport).rows);
    case 'queues':
      return toCsv(queueColumns, (report as QueuesReport).rows);
  }
}
