import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/report.dart';
import '../../../providers/report_providers.dart';
import '../../../widgets/app_data_table.dart';
import '../../../widgets/chart_card.dart';
import '../../../widgets/dashboard_stat_card.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/status_badge.dart';

/// The body of each report tab (§41).
///
/// One widget per report, all four built the same way: a strip of totals, a
/// chart of the single figure that matters, then the table the CSV mirrors
/// column for column. Keeping them out of `reports_screen.dart` leaves that
/// file about the chrome — tabs, dates, export — rather than about columns.

// ── shared pieces ─────────────────────────────────────────────────────────

/// Loading, error and data, handled once for all four reports.
class ReportSection<T> extends StatelessWidget {
  const ReportSection({
    super.key,
    required this.async,
    required this.onRetry,
    required this.builder,
  });

  final AsyncValue<T> async;
  final VoidCallback onRetry;
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context) {
    return async.when(
      // A fixed height, because this sits inside a scrolling column where a
      // spinner with no bounds would assert.
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorState(error: error, onRetry: onRetry),
      ),
      data: builder,
    );
  }
}

/// The figures above a report.
class ReportTotalsStrip extends StatelessWidget {
  const ReportTotalsStrip({super.key, required this.tiles});

  final List<ReportTotalTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (final ReportTotalTile tile in tiles)
          SizedBox(
            width: 168,
            child: DashboardStatCard(
              key: Key('report-total-${tile.id}'),
              label: tile.label,
              value: tile.value,
              icon: tile.icon,
              caption: tile.caption,
            ),
          ),
      ],
    );
  }
}

class ReportTotalTile {
  const ReportTotalTile({
    required this.id,
    required this.label,
    required this.value,
    this.icon,
    this.caption,
  });

  final String id;
  final String label;
  final String value;
  final IconData? icon;
  final String? caption;
}

/// One decimal place, and an em dash where there is no measurement at all —
/// "no ticket reached a counter" is not "zero minutes".
String minutesText(double? value) => value == null ? '—' : value.toStringAsFixed(1);

String _dateText(String date) => Formatters.dayMonth(Formatters.parse(date));

/// Bars for at most the last [limit] days, so a month-long range stays
/// readable instead of turning into a picket fence.
List<BarDatum> _trim(List<BarDatum> bars, {int limit = 14}) {
  return bars.length <= limit ? bars : bars.sublist(bars.length - limit);
}

// ── §41.1 daily summary ───────────────────────────────────────────────────

class DailyReportView extends ConsumerWidget {
  const DailyReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DailyReport> async = ref.watch(dailyReportProvider);

    return ReportSection<DailyReport>(
      async: async,
      onRetry: () => ref.invalidate(dailyReportProvider),
      builder: (DailyReport report) {
        final ReportTotals totals = report.totals;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReportTotalsStrip(
              tiles: <ReportTotalTile>[
                ReportTotalTile(
                  id: 'issued',
                  label: 'Tickets issued',
                  value: '${totals.issued}',
                  icon: Icons.confirmation_number_outlined,
                ),
                ReportTotalTile(
                  id: 'served',
                  label: 'Customers served',
                  value: '${totals.served}',
                  icon: Icons.task_alt_rounded,
                  caption: '${totals.completionRate}% of those issued',
                ),
                ReportTotalTile(
                  id: 'unfinished',
                  label: 'Cancelled, skipped, no-show',
                  value: '${totals.cancelled + totals.skipped + totals.noShow}',
                  icon: Icons.remove_circle_outline_rounded,
                ),
                ReportTotalTile(
                  id: 'wait',
                  label: 'Average wait',
                  value: '${minutesText(totals.averageWaitMinutes)} min',
                  icon: Icons.hourglass_bottom_rounded,
                ),
                ReportTotalTile(
                  id: 'service',
                  label: 'Average service',
                  value: '${minutesText(totals.averageServiceMinutes)} min',
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            BarChartCard(
              title: 'Customers served per day',
              subtitle: '${report.rows.length} rows',
              data: _trim(_servedPerDay(report.rows)),
              emptyMessage: 'No tickets were issued in this range.',
            ),
            const SizedBox(height: 16),
            AppDataTable<DailyReportRow>(
              shrinkWrap: true,
              rows: report.rows,
              rowKey: (DailyReportRow row) => Key('report-row-${row.key}'),
              emptyTitle: 'No queues in this range',
              emptyMessage: 'Nothing was issued between these dates.',
              emptyIcon: Icons.event_busy_outlined,
              columns: <AppDataColumn<DailyReportRow>>[
                AppDataColumn<DailyReportRow>(
                  label: 'Date',
                  primary: true,
                  cell: (DailyReportRow row) => Text(_dateText(row.date)),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Service',
                  cell: (DailyReportRow row) => Text(row.serviceName),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Issued',
                  numeric: true,
                  cell: (DailyReportRow row) => Text('${row.issued}'),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Served',
                  numeric: true,
                  cell: (DailyReportRow row) => Text('${row.served}'),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Cancelled',
                  numeric: true,
                  cell: (DailyReportRow row) => Text('${row.cancelled}'),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Skipped',
                  numeric: true,
                  cell: (DailyReportRow row) => Text('${row.skipped}'),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'No-show',
                  numeric: true,
                  cell: (DailyReportRow row) => Text('${row.noShow}'),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Avg wait (min)',
                  numeric: true,
                  cell: (DailyReportRow row) => Text(minutesText(row.averageWaitMinutes)),
                ),
                AppDataColumn<DailyReportRow>(
                  label: 'Avg service (min)',
                  numeric: true,
                  cell: (DailyReportRow row) => Text(minutesText(row.averageServiceMinutes)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static List<BarDatum> _servedPerDay(List<DailyReportRow> rows) {
    final Map<String, int> byDate = <String, int>{};
    for (final DailyReportRow row in rows) {
      byDate[row.date] = (byDate[row.date] ?? 0) + row.served;
    }
    final List<String> dates = byDate.keys.toList()..sort();
    return <BarDatum>[
      for (final String date in dates)
        BarDatum(
          label: _dateText(date),
          value: byDate[date] ?? 0,
          tooltip: '${Formatters.fullDate(Formatters.parse(date))}: ${byDate[date]} served',
        ),
    ];
  }
}

// ── §41.2 service performance ─────────────────────────────────────────────

class ServicesReportView extends ConsumerWidget {
  const ServicesReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ServicesReport> async = ref.watch(servicesReportProvider);

    return ReportSection<ServicesReport>(
      async: async,
      onRetry: () => ref.invalidate(servicesReportProvider),
      builder: (ServicesReport report) {
        final ReportTotals totals = report.totals;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReportTotalsStrip(
              tiles: <ReportTotalTile>[
                ReportTotalTile(
                  id: 'services',
                  label: 'Services',
                  value: '${report.rows.length}',
                  icon: Icons.apartment_rounded,
                ),
                ReportTotalTile(
                  id: 'served',
                  label: 'Customers served',
                  value: '${totals.served}',
                  icon: Icons.task_alt_rounded,
                ),
                ReportTotalTile(
                  id: 'completion',
                  label: 'Completion rate',
                  value: '${totals.completionRate}%',
                  icon: Icons.percent_rounded,
                ),
                ReportTotalTile(
                  id: 'wait',
                  label: 'Average wait',
                  value: '${minutesText(totals.averageWaitMinutes)} min',
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            BarChartCard(
              title: 'Customers served by service',
              data: <BarDatum>[
                for (final ServiceReportRow row in report.rows)
                  BarDatum(
                    label: row.serviceCode,
                    value: row.customersServed,
                    tooltip: '${row.serviceName}: ${row.customersServed} served',
                  ),
              ],
              emptyMessage: 'Nobody was served in this range.',
            ),
            const SizedBox(height: 16),
            AppDataTable<ServiceReportRow>(
              shrinkWrap: true,
              rows: report.rows,
              rowKey: (ServiceReportRow row) => Key('report-row-${row.serviceId}'),
              emptyTitle: 'No services',
              emptyMessage: 'No service has been created yet.',
              emptyIcon: Icons.apartment_outlined,
              columns: <AppDataColumn<ServiceReportRow>>[
                AppDataColumn<ServiceReportRow>(
                  label: 'Service',
                  primary: true,
                  cell: (ServiceReportRow row) => Text(row.serviceName),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Status',
                  cell: (ServiceReportRow row) =>
                      StatusBadge.service(context, ServiceStatus.parse(row.status), dense: true),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Issued',
                  numeric: true,
                  cell: (ServiceReportRow row) => Text('${row.issued}'),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Served',
                  numeric: true,
                  cell: (ServiceReportRow row) => Text('${row.customersServed}'),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Completed',
                  numeric: true,
                  cell: (ServiceReportRow row) => Text('${row.completionRate}%'),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Avg wait (min)',
                  numeric: true,
                  cell: (ServiceReportRow row) => Text(minutesText(row.averageWaitMinutes)),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Avg service (min)',
                  numeric: true,
                  cell: (ServiceReportRow row) => Text(minutesText(row.averageServiceMinutes)),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Peak hour',
                  cell: (ServiceReportRow row) => Text(row.peakHourLabel ?? '—'),
                ),
                AppDataColumn<ServiceReportRow>(
                  label: 'Longest queue',
                  numeric: true,
                  cell: (ServiceReportRow row) => Text('${row.peakQueueLength}'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── §41.3 staff performance ───────────────────────────────────────────────

class StaffReportView extends ConsumerWidget {
  const StaffReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StaffReport> async = ref.watch(staffReportProvider);

    return ReportSection<StaffReport>(
      async: async,
      onRetry: () => ref.invalidate(staffReportProvider),
      builder: (StaffReport report) {
        final StaffReportTotals totals = report.totals;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReportTotalsStrip(
              tiles: <ReportTotalTile>[
                ReportTotalTile(
                  id: 'staff',
                  label: 'Staff on the report',
                  value: '${totals.staff}',
                  icon: Icons.badge_outlined,
                ),
                ReportTotalTile(
                  id: 'served',
                  label: 'Tickets served',
                  value: '${totals.ticketsServed}',
                  icon: Icons.task_alt_rounded,
                ),
                ReportTotalTile(
                  id: 'handled',
                  label: 'Actions taken',
                  value: '${totals.ticketsHandled}',
                  icon: Icons.touch_app_outlined,
                  caption: 'calls, recalls, completions',
                ),
                ReportTotalTile(
                  id: 'service',
                  label: 'Average service',
                  value: '${minutesText(totals.averageServiceMinutes)} min',
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            BarChartCard(
              title: 'Tickets served per clerk',
              data: <BarDatum>[
                for (final StaffReportRow row in report.rows)
                  BarDatum(
                    label: Formatters.initials(
                      row.staffName.split(' ').first,
                      row.staffName.split(' ').length > 1 ? row.staffName.split(' ').last : '',
                    ),
                    value: row.ticketsServed,
                    tooltip: '${row.staffName}: ${row.ticketsServed} served',
                  ),
              ],
              emptyMessage: 'No clerk handled a ticket in this range.',
            ),
            const SizedBox(height: 16),
            AppDataTable<StaffReportRow>(
              shrinkWrap: true,
              rows: report.rows,
              rowKey: (StaffReportRow row) => Key('report-row-${row.key}'),
              emptyTitle: 'Nobody served anyone',
              emptyMessage: 'No staff member handled a ticket between these dates.',
              emptyIcon: Icons.badge_outlined,
              columns: <AppDataColumn<StaffReportRow>>[
                AppDataColumn<StaffReportRow>(
                  label: 'Staff',
                  primary: true,
                  cell: (StaffReportRow row) => Text(row.staffName),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'Service',
                  cell: (StaffReportRow row) => Text(row.serviceName),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'Served',
                  numeric: true,
                  cell: (StaffReportRow row) => Text('${row.ticketsServed}'),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'Skipped',
                  numeric: true,
                  cell: (StaffReportRow row) => Text('${row.ticketsSkipped}'),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'No-show',
                  numeric: true,
                  cell: (StaffReportRow row) => Text('${row.ticketsNoShow}'),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'Recalled',
                  numeric: true,
                  cell: (StaffReportRow row) => Text('${row.ticketsRecalled}'),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'Actions',
                  numeric: true,
                  cell: (StaffReportRow row) => Text('${row.ticketsHandled}'),
                ),
                AppDataColumn<StaffReportRow>(
                  label: 'Avg service (min)',
                  numeric: true,
                  cell: (StaffReportRow row) => Text(minutesText(row.averageServiceMinutes)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── §41.4 queue analytics ─────────────────────────────────────────────────

class QueuesReportView extends ConsumerWidget {
  const QueuesReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<QueuesReport> async = ref.watch(queuesReportProvider);

    return ReportSection<QueuesReport>(
      async: async,
      onRetry: () => ref.invalidate(queuesReportProvider),
      builder: (QueuesReport report) {
        final QueuesReportTotals totals = report.totals;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReportTotalsStrip(
              tiles: <ReportTotalTile>[
                ReportTotalTile(
                  id: 'queues',
                  label: 'Queues',
                  value: '${totals.queues}',
                  icon: Icons.queue_outlined,
                ),
                ReportTotalTile(
                  id: 'issued',
                  label: 'Tickets issued',
                  value: '${totals.issued}',
                  icon: Icons.confirmation_number_outlined,
                ),
                ReportTotalTile(
                  id: 'peak',
                  label: 'Longest queue',
                  value: '${totals.peakQueue}',
                  icon: Icons.groups_outlined,
                  caption: 'people waiting at once',
                ),
                ReportTotalTile(
                  id: 'utilisation',
                  label: 'Counter utilisation',
                  value: '${totals.averageUtilisationPercent}%',
                  icon: Icons.speed_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            BarChartCard(
              title: 'Longest queue by service',
              data: <BarDatum>[
                for (final QueueReportRow row in report.rows)
                  BarDatum(
                    label: row.serviceCode,
                    value: row.peakQueue,
                    tooltip: '${row.serviceName}, ${_dateText(row.date)}: ${row.peakQueue} waiting',
                  ),
              ],
              emptyMessage: 'No queue ran in this range.',
            ),
            const SizedBox(height: 16),
            AppDataTable<QueueReportRow>(
              shrinkWrap: true,
              rows: report.rows,
              rowKey: (QueueReportRow row) => Key('report-row-${row.queueId}'),
              emptyTitle: 'No queues in this range',
              emptyMessage: 'No queue was opened between these dates.',
              emptyIcon: Icons.event_busy_outlined,
              columns: <AppDataColumn<QueueReportRow>>[
                AppDataColumn<QueueReportRow>(
                  label: 'Service',
                  primary: true,
                  cell: (QueueReportRow row) => Text(row.serviceName),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Date',
                  cell: (QueueReportRow row) => Text(_dateText(row.date)),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Status',
                  cell: (QueueReportRow row) =>
                      StatusBadge.queue(context, QueueStatus.parse(row.status), dense: true),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Opened',
                  cell: (QueueReportRow row) => Text(Formatters.timeFromIso(row.openedAt)),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Closed',
                  cell: (QueueReportRow row) =>
                      Text(row.isOpen ? 'Still open' : Formatters.timeFromIso(row.closedAt)),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Issued',
                  numeric: true,
                  cell: (QueueReportRow row) => Text('${row.issued}'),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Served',
                  numeric: true,
                  cell: (QueueReportRow row) => Text('${row.served}'),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Peak',
                  numeric: true,
                  cell: (QueueReportRow row) => Text('${row.peakQueue}'),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Average',
                  numeric: true,
                  cell: (QueueReportRow row) => Text(row.averageQueue.toStringAsFixed(1)),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Counters',
                  numeric: true,
                  cell: (QueueReportRow row) => Text('${row.countersUsed}'),
                ),
                AppDataColumn<QueueReportRow>(
                  label: 'Utilisation',
                  numeric: true,
                  cell: (QueueReportRow row) => Text('${row.utilisationPercent}%'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
