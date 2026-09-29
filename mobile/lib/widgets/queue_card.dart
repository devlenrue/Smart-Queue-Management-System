import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../models/queue.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// The live queue board (§46): now serving, how many are waiting, and how
/// long the server thinks that will take.
class QueueStatusCard extends StatelessWidget {
  const QueueStatusCard({super.key, required this.status, this.highlight});

  final QueueStatusView status;

  /// A ticket number to point out — the viewer's own, on the tracking screen.
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    status.serviceName,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusBadge.queue(context, status.status, dense: true),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: <Widget>[
                  Text(
                    'NOW SERVING',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status.nowServing ?? '—',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (highlight != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Your ticket: $highlight',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _Cell(label: 'Waiting', value: '${status.waitingCount}'),
                _Cell(label: 'Being served', value: '${status.servingCount}'),
                _Cell(label: 'Completed', value: '${status.completedToday}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _Cell(label: 'Counters open', value: '${status.activeCounters}'),
                _Cell(label: 'Avg service', value: Formatters.duration(status.averageServiceMinutes)),
                _Cell(label: 'Est. wait', value: Formatters.duration(status.estimatedWaitMinutes)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(value, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
