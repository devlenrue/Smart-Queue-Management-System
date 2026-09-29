import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/staff_dashboard.dart';
import '../../models/ticket.dart';
import '../../providers/auth_providers.dart';
import '../../providers/staff_providers.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'widgets/counter_status_tile.dart';
import 'widgets/now_serving_card.dart';
import 'widgets/ticket_action_bar.dart';
import 'widgets/waiting_ticket_tile.dart';

/// §20 — the screen a counter clerk keeps open all day.
///
/// Everything on it comes from one polled request, so the waiting count in
/// the header and the list under it can never disagree.
class StaffDashboardScreen extends ConsumerWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StaffDashboard> async = ref.watch(staffDashboardProvider);
    final String firstName = ref.watch(currentUserProvider)?.firstName ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('${Formatters.greeting()}, $firstName'.trim()),
            Text(
              async.valueOrNull?.service?.name ?? 'Staff console',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(staffDashboardProvider.notifier).refreshNow(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(message: 'Opening your counter…'),
        error: (Object error, StackTrace _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(staffDashboardProvider),
        ),
        data: (StaffDashboard dashboard) => _Body(dashboard: dashboard),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.dashboard});

  final StaffDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!dashboard.assigned) return const _Unassigned();

    return RefreshIndicator(
      onRefresh: () => ref.read(staffDashboardProvider.notifier).refreshNow(),
      child: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          if (dashboard.counter != null)
            CounterStatusTile(
              counter: dashboard.counter!,
              serviceName: dashboard.service?.name ?? '',
            )
          else
            const _NoCounterNotice(),
          const SizedBox(height: 16),
          _StatGrid(stats: dashboard.stats, queueStatus: dashboard.queue?.status),
          const SizedBox(height: 16),
          if (dashboard.currentTicket != null) ...<Widget>[
            NowServingCard(
              ticket: dashboard.currentTicket!,
              onTap: () => context.push(RoutePaths.staffTicketOf(dashboard.currentTicket!.id)),
            ),
            const SizedBox(height: 12),
            TicketActionBar(ticket: dashboard.currentTicket!),
            const SizedBox(height: 20),
          ] else ...<Widget>[
            _CallNextPanel(dashboard: dashboard),
            const SizedBox(height: 20),
          ],
          _UpNext(dashboard: dashboard),
        ],
      ),
    );
  }
}

/// No assignment means no queue to work. Say who can fix it.
class _Unassigned extends StatelessWidget {
  const _Unassigned();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.badge_outlined,
      title: 'No counter assigned',
      message:
          'You are not assigned to a service yet, so there is no queue to work. '
          'An administrator can assign you to a service and a counter.',
    );
  }
}

class _NoCounterNotice extends StatelessWidget {
  const _NoCounterNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You are assigned to this service but not to a counter, so you can watch the '
              'queue but not call from it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four figures: the queue, and what this clerk has done with it today.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, this.queueStatus});

  final StaffDashboardStats stats;
  final QueueStatus? queueStatus;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int columns = Responsive.isCompact(context) ? 2 : 4;

    final List<Widget> cards = <Widget>[
      DashboardStatCard(
        key: const Key('stat-waiting'),
        label: 'Waiting now',
        value: '${stats.waiting}',
        icon: Icons.groups_outlined,
        caption: queueStatus == null ? null : 'Queue ${queueStatus!.label.toLowerCase()}',
      ),
      DashboardStatCard(
        key: const Key('stat-served'),
        label: 'You served today',
        value: '${stats.servedToday}',
        icon: Icons.task_alt_rounded,
        color: scheme.tertiary,
      ),
      DashboardStatCard(
        label: 'Average service',
        value: Formatters.duration(stats.averageServiceMinutes),
        icon: Icons.timer_outlined,
      ),
      DashboardStatCard(
        label: 'Skipped / no-show',
        value: '${stats.skippedToday} / ${stats.noShowToday}',
        icon: Icons.person_off_outlined,
        color: scheme.error,
      ),
    ];

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: cards,
    );
  }
}

/// The big green button, and the reasons it is sometimes not available.
class _CallNextPanel extends ConsumerStatefulWidget {
  const _CallNextPanel({required this.dashboard});

  final StaffDashboard dashboard;

  @override
  ConsumerState<_CallNextPanel> createState() => _CallNextPanelState();
}

class _CallNextPanelState extends ConsumerState<_CallNextPanel> {
  bool _calling = false;

  Future<void> _callNext() async {
    final StaffDashboard dashboard = widget.dashboard;
    final int? serviceId = dashboard.service?.id;
    if (serviceId == null) return;

    setState(() => _calling = true);
    try {
      final TicketActionResult result = await ref.read(staffActionProvider.notifier).callNext(
            serviceId: serviceId,
            counterId: dashboard.counter?.id,
          );
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        '${result.ticket.ticketNumber} called to ${result.ticket.counter?.shortLabel ?? 'your counter'}.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final StaffDashboard dashboard = widget.dashboard;
    final ThemeData theme = Theme.of(context);
    final String? blocked = _whyBlocked(dashboard);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: const Key('call-next'),
            onPressed: blocked == null && !_calling ? _callNext : null,
            icon: _calling
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.campaign_rounded),
            label: Text(
              _calling ? 'Calling…' : 'Call next customer',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
          ),
        ),
        if (blocked != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            blocked,
            key: const Key('call-next-blocked'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// Every reason the button is disabled, in the order the clerk can act on.
  static String? _whyBlocked(StaffDashboard dashboard) {
    if (dashboard.counter == null) return 'You need a counter before you can call anybody.';
    if (dashboard.counter!.status == CounterStatus.offline) {
      return 'Your counter is off duty. Turn it back on to call the next customer.';
    }
    if (dashboard.currentTicket != null) {
      return 'Finish with ${dashboard.currentTicket!.ticketNumber} first.';
    }
    if ((dashboard.queue?.waitingCount ?? 0) == 0) return 'Nobody is waiting right now.';
    return null;
  }
}

/// The next few in line, with the whole list one tap away.
class _UpNext extends ConsumerWidget {
  const _UpNext({required this.dashboard});

  final StaffDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<Ticket> upNext = dashboard.upNext;
    final int waiting = dashboard.queue?.waitingCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Up next', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (dashboard.queue != null) StatusBadge.queue(context, dashboard.queue!.status, dense: true),
            const Spacer(),
            if (waiting > upNext.length)
              TextButton(
                onPressed: () => context.go(RoutePaths.staffQueue),
                child: Text('See all $waiting'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (upNext.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'The queue is empty. Nothing to do until somebody joins.',
              key: const Key('up-next-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (int i = 0; i < upNext.length; i++)
            WaitingTicketTile(
              ticket: upNext[i],
              position: i + 1,
              onTap: () => context.push(RoutePaths.staffTicketOf(upNext[i].id)),
            ),
      ],
    );
  }
}
