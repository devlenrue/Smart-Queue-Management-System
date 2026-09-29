import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/counter.dart';
import '../../models/queue.dart';
import '../../models/ticket.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';

/// One service's live board: what each counter is doing, and who is waiting.
///
/// Read-only on purpose. Calling and completing tickets belongs to the clerk
/// at the desk; an administrator watching over their shoulder should not be
/// able to reach in and move the queue from here.
class QueueBoardScreen extends ConsumerWidget {
  const QueueBoardScreen({super.key, required this.serviceId});

  final int serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<QueueMonitor?> async = ref.watch(adminMonitorProvider(serviceId));
    final QueueMonitor? monitor = async.valueOrNull;

    return AdminPage(
      title: monitor?.serviceName ?? 'Live board',
      subtitle: monitor == null
          ? null
          : '${monitor.queue.waitingCount} waiting · now serving ${monitor.nowServing ?? '—'}',
      onRefresh: () async => ref.invalidate(adminMonitorProvider(serviceId)),
      body: async.when(
        loading: () => const SkeletonList(count: 4),
        error: (Object error, StackTrace _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(adminMonitorProvider(serviceId)),
        ),
        data: (QueueMonitor? monitor) {
          if (monitor == null) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No queue today',
              message: 'A queue opens as soon as the first customer joins this service.',
            );
          }
          return ListView(
            padding: Responsive.pagePadding(context),
            children: <Widget>[
              _Stats(queue: monitor.queue),
              const SizedBox(height: 16),
              Text('Counters', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final ServiceCounter counter in monitor.counters)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CounterRow(counter: counter),
                ),
              const SizedBox(height: 16),
              Text(
                'Waiting (${monitor.waiting.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (monitor.waiting.isEmpty)
                const EmptyState(
                  icon: Icons.done_all_rounded,
                  title: 'Queue cleared',
                  message: 'Nobody is waiting at this service right now.',
                )
              else
                for (int i = 0; i < monitor.waiting.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _WaitingRow(ticket: monitor.waiting[i], position: i + 1),
                  ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.queue});

  final QueueStatusView queue;

  @override
  Widget build(BuildContext context) {
    final int columns = Responsive.isCompact(context) ? 2 : 4;

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: <Widget>[
        DashboardStatCard(
          key: const Key('board-waiting'),
          label: 'Waiting',
          value: '${queue.waitingCount}',
          icon: Icons.groups_rounded,
        ),
        DashboardStatCard(
          label: 'Completed today',
          value: '${queue.completedToday}',
          icon: Icons.task_alt_rounded,
        ),
        DashboardStatCard(
          label: 'Estimated wait',
          value: Formatters.duration(queue.estimatedWaitMinutes),
          icon: Icons.hourglass_bottom_rounded,
          caption: '${queue.activeCounters} counters open',
        ),
        DashboardStatCard(
          label: 'Issued today',
          value: '${queue.ticketsIssuedToday}',
          icon: Icons.confirmation_number_outlined,
          caption: '${queue.capacityRemaining} left of capacity',
        ),
      ],
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({required this.counter});

  final ServiceCounter counter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      key: Key('board-counter-${counter.id}'),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(counter.name, style: theme.textTheme.bodyLarge),
                Text(
                  counter.staffName ?? 'Unstaffed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (counter.currentTicket != null) ...<Widget>[
            Text(counter.currentTicket!, style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
          ],
          StatusBadge.counter(context, counter.status, dense: true),
        ],
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.ticket, required this.position});

  final Ticket ticket;
  final int position;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Twenty minutes is the point at which a wait stops being ordinary and
    // starts being something a supervisor should notice.
    final bool longWait = ticket.waitedMinutes >= 20;

    return AppCard(
      key: Key('board-ticket-${ticket.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Text('$position', style: theme.textTheme.labelMedium),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(ticket.ticketNumber, style: theme.textTheme.titleSmall),
                Text(
                  ticket.customer?.fullName ?? 'Customer',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'waiting ${Formatters.duration(ticket.waitedMinutes)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: longWait ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
