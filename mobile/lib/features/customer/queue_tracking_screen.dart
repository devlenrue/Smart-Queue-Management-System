import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/queue.dart';
import '../../models/ticket.dart';
import '../../providers/customer_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/queue_card.dart';

/// §46. The public board for the queue a ticket belongs to.
///
/// Two independent live reads share this screen: the queue's own figures and
/// the viewer's position within it. They refresh on separate timers and
/// neither blocks the other.
class QueueTrackingScreen extends ConsumerWidget {
  const QueueTrackingScreen({super.key, required this.ticketId});

  final int ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Ticket> ticket = ref.watch(ticketDetailProvider(ticketId));

    return Scaffold(
      appBar: AppBar(title: const Text('Queue board')),
      body: ticket.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(ticketDetailProvider(ticketId)),
        ),
        data: (Ticket data) => _Board(ticket: data),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<QueueStatusView> queue = ref.watch(queueStatusProvider(ticket.queueId));
    final AsyncValue<TicketPosition> position = ref.watch(ticketPositionProvider(ticket.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(queueStatusProvider(ticket.queueId));
        ref.invalidate(ticketPositionProvider(ticket.id));
      },
      child: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          queue.when(
            loading: () => const SkeletonBox(height: 320, radius: 16),
            error: (Object error, _) => ErrorState(
              error: error,
              onRetry: () => ref.invalidate(queueStatusProvider(ticket.queueId)),
            ),
            data: (QueueStatusView status) =>
                QueueStatusCard(status: status, highlight: ticket.ticketNumber),
          ),
          const SizedBox(height: 20),
          position.when(
            loading: () => const SkeletonBox(height: 110, radius: 16),
            error: (Object error, _) => ErrorState(error: error, compact: true),
            data: (TicketPosition value) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Where you are', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text(
                            value.position == null
                                ? value.status.label
                                : '${Formatters.ordinal(value.position!)} in line · '
                                    '${Formatters.people(value.peopleAhead)} ahead',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Formatters.waitEstimate(value.estimatedWaitMinutes),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ticket.ticketNumber,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Figures come straight from the server and refresh on their own. '
            'Estimated wait = people ahead × average service time ÷ counters open.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
