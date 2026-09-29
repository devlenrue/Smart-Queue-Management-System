import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/status_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/ticket.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/status_badge.dart';

/// The customer at the counter right now — the single most important thing
/// on the console, so it gets the largest type on the screen.
class NowServingCard extends StatelessWidget {
  const NowServingCard({super.key, required this.ticket, this.onTap});

  final Ticket ticket;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = context.statusPalette.ofTicket(ticket.status);
    final String customerName = ticket.customer?.fullName ?? 'Customer';

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                ticket.status == TicketStatus.serving ? 'Now serving' : 'Called to your counter',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              StatusBadge.ticket(context, ticket.status, dense: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ticket.ticketNumber,
                    key: const Key('staff-current-ticket'),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.12),
                child: Text(
                  _initialsOf(customerName),
                  style: theme.textTheme.titleMedium?.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(customerName, style: theme.textTheme.titleMedium),
          if (ticket.customer?.phone.isNotEmpty ?? false)
            Text(
              ticket.customer!.phone,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: <Widget>[
              _Fact(label: 'Waited', value: Formatters.duration(ticket.waitedMinutes)),
              if (ticket.serviceMinutes != null)
                _Fact(label: 'At counter', value: Formatters.duration(ticket.serviceMinutes)),
              _Fact(label: 'Joined', value: Formatters.timeFromIso(ticket.joinedAt)),
              if (ticket.counter != null) _Fact(label: 'Counter', value: '${ticket.counter!.counterNumber}'),
            ],
          ),
        ],
      ),
    );
  }

  static String _initialsOf(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}
