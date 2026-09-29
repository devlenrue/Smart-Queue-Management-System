import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../models/service.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// One service in the catalogue, with its live queue figures (§42).
///
/// Every number here comes straight off the server's `queue` block — the
/// card computes nothing, so what the marker sees is what the database says.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.service,
    this.onTap,
    this.onJoin,
    this.isJoining = false,
  });

  final Service service;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;
  final bool isJoining;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final QueueSummary? queue = service.queue;
    final bool canJoin = service.canJoin && onJoin != null;

    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _CodeChip(code: service.code),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          service.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (service.category != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            service.category!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.service(context, service.status, dense: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Metric(
                      icon: Icons.people_alt_outlined,
                      label: 'Waiting',
                      value: '${queue?.waitingCount ?? 0}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      icon: Icons.schedule_rounded,
                      label: 'Est. wait',
                      value: Formatters.duration(queue?.estimatedWaitMinutes ?? 0),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      icon: Icons.confirmation_number_outlined,
                      label: 'Now serving',
                      value: queue?.nowServing ?? '—',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      canJoin
                          ? '${queue?.activeCounters ?? 0} ${(queue?.activeCounters ?? 0) == 1 ? 'counter' : 'counters'} open'
                          : service.unavailableReason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: canJoin
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onJoin != null)
                    FilledButton.tonal(
                      onPressed: canJoin && !isJoining ? onJoin : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: isJoining
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Join'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 44,
      width: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        code,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
