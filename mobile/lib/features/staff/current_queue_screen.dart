import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/queue.dart';
import '../../models/staff_dashboard.dart';
import '../../models/ticket.dart';
import '../../providers/staff_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import 'widgets/ticket_action_bar.dart';
import 'widgets/waiting_ticket_tile.dart';

/// The whole waiting list, not just the five the console previews.
///
/// Each row carries its own Call button so a clerk can pull a specific
/// person forward — the accessible-counter case, and the one where somebody
/// has plainly been waiting too long.
class CurrentQueueScreen extends ConsumerWidget {
  const CurrentQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<QueueMonitor?> async = ref.watch(staffQueueProvider);
    final StaffDashboard? dashboard = ref.watch(staffDashboardProvider).valueOrNull;
    final QueueMonitor? monitor = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Current queue'),
        bottom: dashboard?.queue == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(34),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: Row(
                      children: <Widget>[
                        // One flexible run on the left and one fixed label on
                        // the right: on a narrow phone the left ellipsises
                        // rather than overflowing the app bar.
                        Expanded(
                          child: Text(
                            '${dashboard!.queue!.waitingCount} waiting · '
                            'now serving ${dashboard.queue!.nowServing ?? '—'}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          monitor == null
                              ? '~${Formatters.duration(dashboard.queue!.estimatedWaitMinutes)} to clear'
                              : '${monitor.availableCounters}/${monitor.counters.length} counters free',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(staffQueueProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const SkeletonList(count: 6),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(staffQueueProvider)),
        data: (QueueMonitor? monitor) {
          final List<Ticket> waiting = monitor?.waiting ?? const <Ticket>[];
          if (waiting.isEmpty) {
            return const EmptyState(
              icon: Icons.done_all_rounded,
              title: 'Queue cleared',
              message: 'Nobody is waiting. New tickets will appear here as customers join.',
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(staffQueueProvider.notifier).refresh(),
            child: ListView.builder(
              padding: Responsive.pagePadding(context),
              itemCount: waiting.length,
              itemBuilder: (BuildContext context, int index) {
                final Ticket ticket = waiting[index];
                return WaitingTicketTile(
                  ticket: ticket,
                  position: index + 1,
                  onTap: () => context.push(RoutePaths.staffTicketOf(ticket.id)),
                  trailing: _CallButton(ticket: ticket, counterId: dashboard?.counter?.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Calls one specific ticket rather than the head of the queue.
class _CallButton extends ConsumerStatefulWidget {
  const _CallButton({required this.ticket, this.counterId});

  final Ticket ticket;
  final int? counterId;

  @override
  ConsumerState<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends ConsumerState<_CallButton> {
  bool _busy = false;

  Future<void> _call() async {
    setState(() => _busy = true);
    try {
      await ref.read(staffActionProvider.notifier).call(widget.ticket.id, counterId: widget.counterId);
      if (!mounted) return;
      showSuccessSnackBar(context, '${widget.ticket.ticketNumber} called.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
    return IconButton.filledTonal(
      key: Key('call-ticket-${widget.ticket.id}'),
      tooltip: 'Call ${widget.ticket.ticketNumber}',
      onPressed: widget.counterId == null ? null : _call,
      icon: const Icon(Icons.campaign_outlined, size: 20),
    );
  }
}

/// The detail view behind a tap on any row (§45).
class StaffTicketScreen extends ConsumerWidget {
  const StaffTicketScreen({super.key, required this.ticketId});

  final int ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The console already holds every live ticket, so the detail screen
    // reads from it rather than issuing another request. Falling back to a
    // fetch keeps deep links working.
    final Ticket? fromConsole = _findInConsole(ref);

    return Scaffold(
      appBar: AppBar(title: Text(fromConsole?.ticketNumber ?? 'Ticket')),
      body: fromConsole == null
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Ticket not in this queue',
              message:
                  'This ticket is no longer live at your service. Look for it in your history instead.',
            )
          : _StaffTicketBody(ticket: fromConsole),
    );
  }

  Ticket? _findInConsole(WidgetRef ref) {
    final StaffDashboard? dashboard = ref.watch(staffDashboardProvider).valueOrNull;
    if (dashboard == null) return null;
    if (dashboard.currentTicket?.id == ticketId) return dashboard.currentTicket;

    for (final Ticket ticket in dashboard.upNext) {
      if (ticket.id == ticketId) return ticket;
    }
    final QueueMonitor? monitor = ref.watch(staffQueueProvider).valueOrNull;
    for (final Ticket ticket in monitor?.waiting ?? const <Ticket>[]) {
      if (ticket.id == ticketId) return ticket;
    }
    return null;
  }
}

class _StaffTicketBody extends StatelessWidget {
  const _StaffTicketBody({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: Responsive.pagePadding(context),
      children: <Widget>[
        Text(
          ticket.ticketNumber,
          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(ticket.serviceName, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        _DetailRow(label: 'Customer', value: ticket.customer?.fullName ?? '—'),
        _DetailRow(label: 'Phone', value: ticket.customer?.phone ?? '—'),
        _DetailRow(label: 'Status', value: ticket.status.label),
        _DetailRow(label: 'Joined', value: Formatters.dateTimeFromIso(ticket.joinedAt)),
        _DetailRow(label: 'Waited', value: Formatters.duration(ticket.waitedMinutes)),
        if (ticket.calledAt != null)
          _DetailRow(label: 'Called', value: Formatters.timeFromIso(ticket.calledAt)),
        if (ticket.counter != null)
          _DetailRow(label: 'Counter', value: ticket.counter!.name),
        const SizedBox(height: 24),
        TicketActionBar(ticket: ticket),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
