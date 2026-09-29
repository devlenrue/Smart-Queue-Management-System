import 'package:flutter/material.dart';

import '../core/theme/status_palette.dart';
import '../core/utils/formatters.dart';
import '../models/ticket.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// A ticket as it appears in a list — the dashboard's current ticket and
/// every row of the history screen.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    this.onTap,
    this.showDate = true,
    this.trailing,
  });

  final Ticket ticket;
  final VoidCallback? onTap;
  final bool showDate;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color statusColor = context.statusPalette.ofTicket(ticket.status);

    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          ticket.ticketNumber,
                          style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1),
                        ),
                        const SizedBox(width: 10),
                        StatusBadge.ticket(context, ticket.status, dense: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.serviceName,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing! else if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final List<String> parts = <String>[];
    if (showDate && ticket.joinedAt != null) {
      parts.add(Formatters.dateTimeFromIso(ticket.joinedAt));
    }
    if (ticket.counter != null) {
      parts.add(ticket.counter!.shortLabel);
    }
    if (ticket.status.isFinished && ticket.waitedMinutes > 0) {
      parts.add('waited ${Formatters.duration(ticket.waitedMinutes)}');
    }
    return parts.isEmpty ? ticket.serviceCode : parts.join(' · ');
  }
}
