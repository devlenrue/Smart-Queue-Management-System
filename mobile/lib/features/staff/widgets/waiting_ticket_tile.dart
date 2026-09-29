import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/ticket.dart';
import '../../../widgets/app_card.dart';

/// One row of the waiting list.
///
/// Waited-time is the number a clerk actually uses — it is what tells them
/// somebody has been sitting there for forty minutes — so it is rendered
/// larger than the join time and coloured once it gets long.
class WaitingTicketTile extends StatelessWidget {
  const WaitingTicketTile({
    super.key,
    required this.ticket,
    required this.position,
    this.onTap,
    this.trailing,
  });

  final Ticket ticket;

  /// 1-based place in the waiting list.
  final int position;

  final VoidCallback? onTap;
  final Widget? trailing;

  /// Past this many minutes the wait is shown in the error colour.
  static const int longWaitMinutes = 30;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool longWait = ticket.waitedMinutes >= longWaitMinutes;
    final Color waitColour =
        longWait ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$position',
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    ticket.ticketNumber,
                    key: Key('waiting-ticket-${ticket.id}'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ticket.customer?.fullName ?? 'Customer',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (longWait) ...<Widget>[
                      Icon(Icons.priority_high_rounded, size: 14, color: waitColour),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      'waited ${Formatters.duration(ticket.waitedMinutes)}',
                      style: theme.textTheme.labelMedium?.copyWith(color: waitColour),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'joined ${Formatters.timeFromIso(ticket.joinedAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (trailing != null) ...<Widget>[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
