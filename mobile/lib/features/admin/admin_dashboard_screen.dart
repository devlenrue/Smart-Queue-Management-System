import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/theme/status_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/admin_dashboard.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/chart_card.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';

/// The whole institution on one screen (§31, §42).
///
/// Everything here is read from `GET /dashboard/admin` in a single request:
/// the seven headline figures, the served-per-day series, today's tickets by
/// state, and the per-service breakdown. One endpoint means the numbers
/// always agree with each other, which is exactly what a dashboard is for.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AdminDashboard> async = ref.watch(adminDashboardProvider);
    final int days = ref.watch(dashboardWindowProvider);

    return AdminPage(
      title: 'Dashboard',
      subtitle: async.valueOrNull == null
          ? null
          : Formatters.fullDate(Formatters.parse(async.valueOrNull!.today)),
      onRefresh: () => ref.read(adminDashboardProvider.notifier).refreshNow(),
      body: async.when(
        loading: () => const SkeletonList(count: 5),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(adminDashboardProvider)),
        data: (AdminDashboard data) => ListView(
          padding: Responsive.pagePadding(context),
          children: <Widget>[
            _StatGrid(data: data),
            const SizedBox(height: 16),
            _Charts(data: data, days: days, ref: ref),
            const SizedBox(height: 16),
            Text('By service', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _ServiceTable(rows: data.byService),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.data});

  final AdminDashboard data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StatusPalette palette = context.statusPalette;

    final List<Widget> cards = <Widget>[
      DashboardStatCard(
        key: const Key('admin-stat-waiting'),
        label: 'Customers waiting',
        value: '${data.customersWaiting}',
        icon: Icons.groups_rounded,
        color: palette.ofTicket(TicketStatus.waiting),
        caption: 'across ${data.activeQueues} live queues',
      ),
      DashboardStatCard(
        key: const Key('admin-stat-served'),
        label: 'Served today',
        value: '${data.customersServedToday}',
        icon: Icons.task_alt_rounded,
        color: palette.ofTicket(TicketStatus.completed),
        caption: '${data.ticketsIssuedToday} tickets issued',
      ),
      DashboardStatCard(
        key: const Key('admin-stat-wait'),
        label: 'Average wait',
        value: _minutes(data.averageWaitMinutes),
        icon: Icons.hourglass_bottom_rounded,
        caption: 'service ${_minutes(data.averageServiceMinutes)}',
      ),
      DashboardStatCard(
        key: const Key('admin-stat-staff'),
        label: 'Staff on duty',
        value: '${data.staffOnDuty}',
        icon: Icons.badge_rounded,
        caption: '${data.activeCounters} counters open',
      ),
      DashboardStatCard(
        key: const Key('admin-stat-services'),
        label: 'Active services',
        value: '${data.activeServices}',
        icon: Icons.apartment_rounded,
      ),
      DashboardStatCard(
        key: const Key('admin-stat-cancelled'),
        label: 'Cancelled',
        value: '${data.cancelledToday}',
        icon: Icons.cancel_outlined,
        color: palette.ofTicket(TicketStatus.cancelled),
      ),
      DashboardStatCard(
        key: const Key('admin-stat-noshow'),
        label: 'Skipped / no-show',
        value: '${data.skippedToday + data.noShowToday}',
        icon: Icons.person_off_outlined,
        color: palette.ofTicket(TicketStatus.noShow),
        caption: '${data.skippedToday} skipped · ${data.noShowToday} no-show',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (data.busiest != null && data.busiest!.waiting > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Busiest right now: ${data.busiest!.name} '
              '(${Formatters.people(data.busiest!.waiting)} waiting)',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        GridView.count(
          // Seven figures in one column would be a very long scroll, so the
          // grid is one wider than the page default at every breakpoint.
          crossAxisCount: Responsive.columns(context) + 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: cards,
        ),
      ],
    );
  }

  static String _minutes(double value) {
    if (value <= 0) return '—';
    // One decimal is meaningful at these magnitudes; two is noise.
    final String text = value.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} min';
  }
}

class _Charts extends StatelessWidget {
  const _Charts({required this.data, required this.days, required this.ref});

  final AdminDashboard data;
  final int days;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final StatusPalette palette = context.statusPalette;

    final Widget bars = BarChartCard(
      key: const Key('admin-served-chart'),
      title: 'Served per day',
      subtitle: 'last $days days',
      data: <BarDatum>[
        for (final ServedPoint point in data.servedPerDay)
          BarDatum(
            label: point.shortLabel,
            value: point.served,
            tooltip: '${point.label} ${point.date}: ${point.served} served',
          ),
      ],
    );

    final Widget donut = DonutChartCard(
      key: const Key('admin-status-chart'),
      title: "Today's tickets",
      slices: <DonutSlice>[
        for (final ({String label, int value, TicketStatus status}) slice
            in data.statusBreakdown.slices)
          DonutSlice(
            label: slice.label,
            value: slice.value,
            color: palette.ofTicket(slice.status),
          ),
      ],
    );

    if (Responsive.isCompact(context)) {
      return Column(children: <Widget>[bars, const SizedBox(height: 12), donut]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 3, child: bars),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: donut),
      ],
    );
  }
}

class _ServiceTable extends StatelessWidget {
  const _ServiceTable({required this.rows});

  final List<AdminServiceRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<AdminServiceRow>(
      shrinkWrap: true,
      rows: rows,
      rowKey: (AdminServiceRow row) => Key('admin-service-row-${row.serviceId}'),
      onRowTap: (AdminServiceRow row) =>
          context.go(RoutePaths.adminQueueBoardOf(row.serviceId)),
      emptyTitle: 'No services yet',
      emptyMessage: 'Create a service and its queue figures will appear here.',
      columns: <AppDataColumn<AdminServiceRow>>[
        AppDataColumn<AdminServiceRow>(
          label: 'Service',
          primary: true,
          cell: (AdminServiceRow row) => Text('${row.name} (${row.code})'),
        ),
        AppDataColumn<AdminServiceRow>(
          label: 'Status',
          cell: (AdminServiceRow row) => StatusBadge.service(context, row.status, dense: true),
        ),
        AppDataColumn<AdminServiceRow>(
          label: 'Issued',
          numeric: true,
          cell: (AdminServiceRow row) => Text('${row.issued}'),
        ),
        AppDataColumn<AdminServiceRow>(
          label: 'Waiting',
          numeric: true,
          cell: (AdminServiceRow row) => Text('${row.waiting}'),
        ),
        AppDataColumn<AdminServiceRow>(
          label: 'Serving',
          numeric: true,
          cell: (AdminServiceRow row) => Text('${row.serving}'),
        ),
        AppDataColumn<AdminServiceRow>(
          label: 'Completed',
          numeric: true,
          cell: (AdminServiceRow row) => Text('${row.completed}'),
        ),
        AppDataColumn<AdminServiceRow>(
          label: 'Avg wait',
          numeric: true,
          cell: (AdminServiceRow row) => Text(
            row.averageWaitMinutes <= 0 ? '—' : '${row.averageWaitMinutes.round()} min',
          ),
        ),
      ],
    );
  }
}
