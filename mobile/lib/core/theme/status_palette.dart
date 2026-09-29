import 'package:flutter/material.dart';

import '../constants/enums.dart';

/// One colour + icon mapping for every status in the system, exposed as a
/// `ThemeExtension` so badges, charts and the display board can never drift
/// apart (§67).
///
/// Colour is never the only carrier of meaning — every badge also renders an
/// icon and a word, which keeps the UI readable for colour-blind users.
@immutable
class StatusPalette extends ThemeExtension<StatusPalette> {
  const StatusPalette({
    required this.waiting,
    required this.called,
    required this.serving,
    required this.completed,
    required this.cancelled,
    required this.skipped,
    required this.noShow,
    required this.onStatus,
  });

  final Color waiting;
  final Color called;
  final Color serving;
  final Color completed;
  final Color cancelled;
  final Color skipped;
  final Color noShow;

  /// Foreground colour used on top of any of the above.
  final Color onStatus;

  static const StatusPalette light = StatusPalette(
    waiting: Color(0xFFB88700), // amber 700
    called: Color(0xFF00897B), // teal 600
    serving: Color(0xFF1565C0), // blue 700
    completed: Color(0xFF2E7D32), // green 700
    cancelled: Color(0xFF6B7280), // grey 600
    skipped: Color(0xFFE64A19), // deep orange 600
    noShow: Color(0xFFC62828), // red 700
    onStatus: Colors.white,
  );

  static const StatusPalette dark = StatusPalette(
    waiting: Color(0xFFE0A800),
    called: Color(0xFF26A69A),
    serving: Color(0xFF42A5F5),
    completed: Color(0xFF66BB6A),
    cancelled: Color(0xFF9CA3AF),
    skipped: Color(0xFFFF7043),
    noShow: Color(0xFFEF5350),
    onStatus: Color(0xFF10151C),
  );

  Color ofTicket(TicketStatus status) {
    switch (status) {
      case TicketStatus.waiting:
        return waiting;
      case TicketStatus.called:
        return called;
      case TicketStatus.serving:
        return serving;
      case TicketStatus.completed:
        return completed;
      case TicketStatus.cancelled:
        return cancelled;
      case TicketStatus.skipped:
        return skipped;
      case TicketStatus.noShow:
        return noShow;
    }
  }

  Color ofQueue(QueueStatus status) {
    switch (status) {
      case QueueStatus.waiting:
        return completed;
      case QueueStatus.paused:
        return waiting;
      case QueueStatus.closed:
        return cancelled;
    }
  }

  Color ofCounter(CounterStatus status) {
    switch (status) {
      case CounterStatus.available:
        return completed;
      case CounterStatus.busy:
        return serving;
      case CounterStatus.offline:
        return cancelled;
    }
  }

  Color ofService(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.open:
        return completed;
      case ServiceStatus.closed:
        return waiting;
      case ServiceStatus.inactive:
        return cancelled;
    }
  }

  static IconData iconOfTicket(TicketStatus status) {
    switch (status) {
      case TicketStatus.waiting:
        return Icons.hourglass_top_rounded;
      case TicketStatus.called:
        return Icons.campaign_rounded;
      case TicketStatus.serving:
        return Icons.support_agent_rounded;
      case TicketStatus.completed:
        return Icons.check_circle_rounded;
      case TicketStatus.cancelled:
        return Icons.cancel_rounded;
      case TicketStatus.skipped:
        return Icons.skip_next_rounded;
      case TicketStatus.noShow:
        return Icons.person_off_rounded;
    }
  }

  @override
  StatusPalette copyWith({
    Color? waiting,
    Color? called,
    Color? serving,
    Color? completed,
    Color? cancelled,
    Color? skipped,
    Color? noShow,
    Color? onStatus,
  }) {
    return StatusPalette(
      waiting: waiting ?? this.waiting,
      called: called ?? this.called,
      serving: serving ?? this.serving,
      completed: completed ?? this.completed,
      cancelled: cancelled ?? this.cancelled,
      skipped: skipped ?? this.skipped,
      noShow: noShow ?? this.noShow,
      onStatus: onStatus ?? this.onStatus,
    );
  }

  @override
  StatusPalette lerp(ThemeExtension<StatusPalette>? other, double t) {
    if (other is! StatusPalette) return this;
    return StatusPalette(
      waiting: Color.lerp(waiting, other.waiting, t)!,
      called: Color.lerp(called, other.called, t)!,
      serving: Color.lerp(serving, other.serving, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      cancelled: Color.lerp(cancelled, other.cancelled, t)!,
      skipped: Color.lerp(skipped, other.skipped, t)!,
      noShow: Color.lerp(noShow, other.noShow, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
    );
  }
}

/// `context.statusPalette` instead of a two-line lookup at every call site.
extension StatusPaletteX on BuildContext {
  StatusPalette get statusPalette =>
      Theme.of(this).extension<StatusPalette>() ?? StatusPalette.light;
}
