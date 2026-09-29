import 'package:flutter/material.dart';

import '../core/constants/enums.dart';
import '../core/theme/status_palette.dart';

/// A coloured pill with an icon and a word.
///
/// Colour alone never carries the meaning — the icon and the label are
/// always there too, so the badge still reads correctly in greyscale or to
/// someone who cannot distinguish amber from green.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
  });

  /// Named constructors keep the colour lookup out of every call site.
  factory StatusBadge.ticket(BuildContext context, TicketStatus status, {bool dense = false}) {
    return StatusBadge(
      label: status.label,
      color: context.statusPalette.ofTicket(status),
      icon: StatusPalette.iconOfTicket(status),
      dense: dense,
    );
  }

  factory StatusBadge.queue(BuildContext context, QueueStatus status, {bool dense = false}) {
    return StatusBadge(
      label: status.label,
      color: context.statusPalette.ofQueue(status),
      icon: switch (status) {
        QueueStatus.waiting => Icons.play_circle_outline_rounded,
        QueueStatus.paused => Icons.pause_circle_outline_rounded,
        QueueStatus.closed => Icons.lock_outline_rounded,
      },
      dense: dense,
    );
  }

  factory StatusBadge.service(BuildContext context, ServiceStatus status, {bool dense = false}) {
    return StatusBadge(
      label: status.label,
      color: context.statusPalette.ofService(status),
      icon: switch (status) {
        ServiceStatus.open => Icons.check_circle_outline_rounded,
        ServiceStatus.closed => Icons.schedule_rounded,
        ServiceStatus.inactive => Icons.block_rounded,
      },
      dense: dense,
    );
  }

  factory StatusBadge.counter(BuildContext context, CounterStatus status, {bool dense = false}) {
    return StatusBadge(
      label: status.label,
      color: context.statusPalette.ofCounter(status),
      icon: switch (status) {
        CounterStatus.available => Icons.event_available_rounded,
        CounterStatus.busy => Icons.support_agent_rounded,
        CounterStatus.offline => Icons.power_settings_new_rounded,
      },
      dense: dense,
    );
  }

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = (dense
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.labelMedium)
        ?.copyWith(color: color);

    return Semantics(
      // container + excludeSemantics so the badge speaks once, as
      // "Status: Waiting", instead of merging the icon and the word into a
      // node that reads the label twice.
      container: true,
      excludeSemantics: true,
      label: 'Status: $label',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: dense ? 12 : 14, color: color),
              SizedBox(width: dense ? 4 : 6),
            ],
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}
