import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/ticket.dart';
import '../../../providers/staff_providers.dart';
import '../../../repositories/staff_repository.dart';
import '../../../widgets/confirmation_dialog.dart';
import '../../../widgets/error_state.dart';

/// The row of buttons under a ticket.
///
/// Which buttons appear is decided by [StaffRepository.actionsFor] — the
/// client half of the state machine — so a clerk is never offered an action
/// the server would reject with a 409. The server remains the authority;
/// this only avoids offering a dead end.
class TicketActionBar extends ConsumerStatefulWidget {
  const TicketActionBar({
    super.key,
    required this.ticket,
    this.onDone,
    this.compact = false,
  });

  final Ticket ticket;

  /// Called after a successful transition, with the new status.
  final void Function(StaffAction action, TicketActionResult result)? onDone;

  /// Dense form for list rows; the full form is used on detail screens.
  final bool compact;

  @override
  ConsumerState<TicketActionBar> createState() => _TicketActionBarState();
}

class _TicketActionBarState extends ConsumerState<TicketActionBar> {
  StaffAction? _running;

  Future<void> _perform(StaffAction action) async {
    if (_running != null) return;

    String? reason;
    if (action.needsConfirmation) {
      final bool confirmed = await ConfirmationDialog.show(
        context,
        title: action == StaffAction.skip
            ? 'Skip ${widget.ticket.ticketNumber}?'
            : 'Mark ${widget.ticket.ticketNumber} as a no-show?',
        message: action == StaffAction.skip
            ? 'They keep their ticket number but lose their place. Use this when somebody is not ready yet.'
            : 'Use this when the customer did not come to the counter after being called.',
        confirmLabel: action.label,
        cancelLabel: 'Go back',
        isDestructive: true,
        icon: action == StaffAction.skip ? Icons.skip_next_rounded : Icons.person_off_outlined,
      );
      if (!confirmed) return;
      if (action == StaffAction.skip) reason = 'Skipped at the counter';
    }

    setState(() => _running = action);
    try {
      final TicketActionResult result =
          await ref.read(staffActionProvider.notifier).perform(action, widget.ticket.id, reason: reason);
      if (!mounted) return;
      showSuccessSnackBar(context, '${widget.ticket.ticketNumber} ${action.pastTense}.');
      widget.onDone?.call(action, result);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<StaffAction> available = StaffRepository.actionsFor(widget.ticket.status);

    if (available.isEmpty) {
      return Text(
        'This ticket is ${widget.ticket.status.label.toLowerCase()} — nothing left to do.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    // The action that moves the visit forward gets the filled button; the
    // rest are outlined, so the next step is obvious at a glance.
    final StaffAction primary = _primaryOf(available);
    final List<StaffAction> others =
        available.where((StaffAction a) => a != primary).toList(growable: false);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          key: Key('staff-action-${primary.name}'),
          onPressed: _running == null ? () => _perform(primary) : null,
          icon: _running == primary
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(_iconOf(primary), size: 18),
          label: Text(primary.label),
        ),
        for (final StaffAction action in others)
          OutlinedButton.icon(
            key: Key('staff-action-${action.name}'),
            onPressed: _running == null ? () => _perform(action) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: action.needsConfirmation ? Theme.of(context).colorScheme.error : null,
              visualDensity: widget.compact ? VisualDensity.compact : null,
            ),
            icon: _running == action
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_iconOf(action), size: 18),
            label: Text(action.label),
          ),
      ],
    );
  }

  static StaffAction _primaryOf(Set<StaffAction> available) {
    for (final StaffAction candidate in <StaffAction>[
      StaffAction.complete,
      StaffAction.start,
      StaffAction.call,
    ]) {
      if (available.contains(candidate)) return candidate;
    }
    return available.first;
  }

  static IconData _iconOf(StaffAction action) {
    switch (action) {
      case StaffAction.call:
        return Icons.campaign_outlined;
      case StaffAction.recall:
        return Icons.replay_rounded;
      case StaffAction.start:
        return Icons.play_arrow_rounded;
      case StaffAction.complete:
        return Icons.check_rounded;
      case StaffAction.skip:
        return Icons.skip_next_rounded;
      case StaffAction.noShow:
        return Icons.person_off_outlined;
    }
  }
}
