import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/queue.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';

/// Every live queue at a glance, one card per service (§54).
///
/// Tapping one opens the board for that service, which is the same data the
/// clerk at the counter is looking at — so a supervisor can answer "what is
/// happening at Finance?" without walking there.
class QueueMonitorScreen extends ConsumerWidget {
  const QueueMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<QueueStatusView>> async = ref.watch(adminQueuesProvider);

    return AdminPage(
      title: 'Queue monitor',
      subtitle: async.valueOrNull == null ? null : '${async.valueOrNull!.length} queues today',
      onRefresh: () async => ref.invalidate(adminQueuesProvider),
      body: async.when(
        loading: () => const SkeletonList(count: 4),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(adminQueuesProvider)),
        data: (List<QueueStatusView> queues) {
          if (queues.isEmpty) {
            return const EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'No queues open',
              message: 'A queue is created the first time somebody joins a service today.',
            );
          }

          return GridView.count(
            padding: Responsive.pagePadding(context),
            crossAxisCount: Responsive.columns(context),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: <Widget>[
              for (final QueueStatusView queue in queues)
                _QueueCard(
                  queue: queue,
                  onTap: () => context.go(RoutePaths.adminQueueBoardOf(queue.serviceId)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.queue, required this.onTap});

  final QueueStatusView queue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      key: Key('admin-queue-${queue.serviceId}'),
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  queue.serviceName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusBadge.queue(context, queue.status, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('${queue.waitingCount}', style: theme.textTheme.headlineMedium),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('waiting', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'Now serving ${queue.nowServing ?? '—'}',
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${queue.activeCounters} counters · '
            '~${Formatters.duration(queue.estimatedWaitMinutes)} wait',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
