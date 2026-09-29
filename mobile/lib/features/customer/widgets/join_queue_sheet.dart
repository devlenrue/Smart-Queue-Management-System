import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_mapper.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/service.dart';
import '../../../models/ticket.dart';
import '../../../providers/customer_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/form_error_banner.dart';

/// The confirm-before-you-join sheet (§43).
///
/// It shows what the customer is committing to — position, likely wait —
/// then calls the server. Errors are shown *in the sheet* rather than as a
/// snackbar, because the two most common ones ("you are already in this
/// queue", "the queue is full") are answers to the question being asked.
class JoinQueueSheet extends ConsumerStatefulWidget {
  const JoinQueueSheet({super.key, required this.service});

  final Service service;

  /// Returns the created ticket, or null if the sheet was dismissed.
  static Future<Ticket?> show(BuildContext context, Service service) {
    return showModalBottomSheet<Ticket>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => JoinQueueSheet(service: service),
    );
  }

  @override
  ConsumerState<JoinQueueSheet> createState() => _JoinQueueSheetState();
}

class _JoinQueueSheetState extends ConsumerState<JoinQueueSheet> {
  bool _submitting = false;
  Failure? _failure;

  Future<void> _join() async {
    setState(() {
      _submitting = true;
      _failure = null;
    });

    try {
      final Ticket ticket =
          await ref.read(queueActionProvider.notifier).join(widget.service.id);
      if (!mounted) return;
      Navigator.of(context).pop(ticket);
    } catch (error) {
      if (!mounted) return;
      setState(() => _failure = ErrorMapper.fromObject(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Service service = widget.service;
    final QueueSummary? queue = service.queue;

    final int waiting = queue?.waitingCount ?? 0;
    final int yourPosition = waiting + 1;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Join the queue', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            service.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (_failure != null) ...<Widget>[
            FormErrorBanner(message: _explain(_failure!)),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: <Widget>[
                _Row(
                  icon: Icons.people_alt_outlined,
                  label: 'People waiting now',
                  value: '$waiting',
                ),
                const SizedBox(height: 12),
                _Row(
                  icon: Icons.tag_rounded,
                  label: 'You would be',
                  value: '${Formatters.ordinal(yourPosition)} in line',
                ),
                const SizedBox(height: 12),
                _Row(
                  icon: Icons.schedule_rounded,
                  label: 'Estimated wait',
                  value: Formatters.waitEstimate(queue?.estimatedWaitMinutes),
                ),
                const SizedBox(height: 12),
                _Row(
                  icon: Icons.point_of_sale_outlined,
                  label: 'Counters open',
                  value: '${queue?.activeCounters ?? 0}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your ticket number is issued by the server the moment you tap '
            'Join. Keep the app open to see your position update.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            key: const Key('join-confirm'),
            label: 'Join queue',
            icon: Icons.add_rounded,
            isLoading: _submitting,
            onPressed: _join,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }

  /// Turns the server's rule codes into a sentence that tells the customer
  /// what to do next, not just what went wrong.
  String _explain(Failure failure) {
    switch (failure.code) {
      case 'DUPLICATE_ACTIVE_TICKET':
        return 'You already hold a ticket for this service. Open My tickets to see it.';
      case 'QUEUE_FULL':
        return 'This queue has reached its limit for today. Please try again tomorrow.';
      case 'QUEUE_PAUSED':
        return 'The queue is paused right now. Try again in a few minutes.';
      case 'QUEUE_CLOSED':
        return 'The queue is closed for today.';
      case 'OUTSIDE_SERVICE_HOURS':
        return 'This service is outside its opening hours right now.';
      case 'SERVICE_CLOSED':
        return 'This service is closed at the moment.';
      case 'SERVICE_INACTIVE':
        return 'This service is not accepting tickets.';
      case 'REJOIN_NOT_ALLOWED':
        return 'You have already been served here today, and this service does not allow rejoining.';
      default:
        return failure.userMessage;
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}
