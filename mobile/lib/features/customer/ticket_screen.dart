import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/theme/status_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/ticket.dart';
import '../../providers/customer_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';

/// §44/§45. The screen a customer keeps open while they wait.
///
/// The big number is the ticket; everything under it is refreshed from
/// `GET /tickets/:id/position` every few seconds until the ticket reaches a
/// terminal state, at which point the polling stops on its own.
class TicketScreen extends ConsumerWidget {
  const TicketScreen({super.key, required this.ticketId});

  final int ticketId;

  Future<void> _cancel(BuildContext context, WidgetRef ref, Ticket ticket) async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Leave the queue?',
      message: 'Ticket ${ticket.ticketNumber} will be cancelled and you will lose your place. '
          'You would have to join again at the back of the queue.',
      confirmLabel: 'Cancel ticket',
      cancelLabel: 'Keep my place',
      isDestructive: true,
      icon: Icons.exit_to_app_rounded,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(queueActionProvider.notifier).cancel(ticket.id);
      if (!context.mounted) return;
      showSuccessSnackBar(context, 'Ticket ${ticket.ticketNumber} cancelled.');
    } catch (error) {
      if (!context.mounted) return;
      showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Ticket> ticket = ref.watch(ticketDetailProvider(ticketId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your ticket'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Queue board',
            onPressed: () => context.push(RoutePaths.queueTrackingOf(ticketId)),
            icon: const Icon(Icons.dashboard_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ticket.when(
        loading: () => const LoadingView(message: 'Loading ticket…'),
        error: (Object error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(ticketDetailProvider(ticketId)),
        ),
        data: (Ticket data) => _Body(
          ticket: data,
          onCancel: () => _cancel(context, ref, data),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.ticket, required this.onCancel});

  final Ticket ticket;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TicketPosition> position = ref.watch(ticketPositionProvider(ticket.id));
    final TicketPosition? live = position.valueOrNull;

    // The live feed is authoritative once it arrives; before that, the
    // ticket's own status is the best we have.
    final TicketStatus status = live?.status ?? ticket.status;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(ticketDetailProvider(ticket.id));
        ref.invalidate(ticketPositionProvider(ticket.id));
      },
      child: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          _TicketHero(ticket: ticket, status: status),
          const SizedBox(height: 20),
          if (status == TicketStatus.called)
            _CalledBanner(counterName: live?.counter?.name ?? ticket.counter?.name)
          else if (status == TicketStatus.serving)
            _ServingBanner(counterName: live?.counter?.name ?? ticket.counter?.name)
          else if (status.isActive)
            _PositionPanel(position: live, isLoading: position.isLoading)
          else
            _ClosedPanel(ticket: ticket, status: status),
          const SizedBox(height: 20),
          _DetailsCard(ticket: ticket, live: live),
          const SizedBox(height: 20),
          _Timeline(ticketId: ticket.id),
          const SizedBox(height: 28),
          if (status.canCancel)
            AppSecondaryButton(
              key: const Key('ticket-cancel'),
              label: 'Cancel my ticket',
              icon: Icons.close_rounded,
              isDestructive: true,
              onPressed: onCancel,
            ),
          const SizedBox(height: 12),
          AppButton(
            label: 'View the queue board',
            icon: Icons.dashboard_outlined,
            onPressed: () => context.push(RoutePaths.queueTrackingOf(ticket.id)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _TicketHero extends StatelessWidget {
  const _TicketHero({required this.ticket, required this.status});

  final Ticket ticket;
  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = context.statusPalette.ofTicket(status);

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: <Widget>[
            Text(
              ticket.serviceName,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FittedBox(
              child: Text(
                ticket.ticketNumber,
                key: const Key('ticket-number'),
                style: theme.textTheme.displayLarge?.copyWith(color: accent),
              ),
            ),
            const SizedBox(height: 14),
            StatusBadge.ticket(context, status),
          ],
        ),
      ),
    );
  }
}

class _PositionPanel extends StatelessWidget {
  const _PositionPanel({required this.position, required this.isLoading});

  final TicketPosition? position;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (position == null && isLoading) {
      return const SkeletonBox(height: 150, radius: 16);
    }

    final TicketPosition? value = position;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Text(
              'YOUR POSITION',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value?.position == null ? '—' : Formatters.ordinal(value!.position!),
              key: const Key('ticket-position'),
              style: theme.textTheme.displayMedium,
            ),
            const SizedBox(height: 6),
            Text(
              value == null
                  ? 'Checking the queue…'
                  : '${Formatters.people(value.peopleAhead)} ahead of you',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Cell(
                    label: 'Estimated wait',
                    value: value == null
                        ? '—'
                        : Formatters.waitEstimate(value.estimatedWaitMinutes),
                  ),
                ),
                Expanded(
                  child: _Cell(label: 'Now serving', value: value?.nowServing ?? '—'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.sync_rounded,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  'Updates automatically',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalledBanner extends StatelessWidget {
  const _CalledBanner({this.counterName});

  final String? counterName;

  @override
  Widget build(BuildContext context) {
    final StatusPalette palette = context.statusPalette;
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.called.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.called, width: 1.5),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.campaign_rounded, size: 40, color: palette.called),
          const SizedBox(height: 12),
          Text(
            'It is your turn',
            style: theme.textTheme.titleLarge?.copyWith(color: palette.called),
          ),
          const SizedBox(height: 6),
          Text(
            counterName == null
                ? 'Please make your way to the counter now.'
                : 'Please go to $counterName now.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'If you are not there when the counter is ready, your ticket may '
            'be marked as a no-show.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServingBanner extends StatelessWidget {
  const _ServingBanner({this.counterName});

  final String? counterName;

  @override
  Widget build(BuildContext context) {
    final StatusPalette palette = context.statusPalette;
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.serving.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.serving.withOpacity(0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.support_agent_rounded, size: 30, color: palette.serving),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'You are being served',
                  style: theme.textTheme.titleSmall?.copyWith(color: palette.serving),
                ),
                const SizedBox(height: 2),
                Text(
                  counterName == null ? 'At the counter now.' : 'At $counterName.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosedPanel extends StatelessWidget {
  const _ClosedPanel({required this.ticket, required this.status});

  final Ticket ticket;
  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = context.statusPalette.ofTicket(status);

    final String message = switch (status) {
      TicketStatus.completed => 'This visit is finished. Thank you for your patience.',
      TicketStatus.cancelled => 'You cancelled this ticket.',
      TicketStatus.skipped => 'This ticket was skipped. Speak to the counter staff if you are still here.',
      TicketStatus.noShow => 'You were called but not present, so the ticket was closed.',
      _ => 'This ticket is no longer active.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        children: <Widget>[
          Icon(StatusPalette.iconOfTicket(status), size: 32, color: color),
          const SizedBox(height: 10),
          Text(status.label, style: theme.textTheme.titleSmall?.copyWith(color: color)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.ticket, this.live});

  final Ticket ticket;
  final TicketPosition? live;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Ticket details', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _KeyValue(label: 'Service', value: '${ticket.serviceName} (${ticket.serviceCode})'),
            _KeyValue(label: 'Issued', value: Formatters.dateTimeFromIso(ticket.joinedAt)),
            if (ticket.calledAt != null)
              _KeyValue(label: 'Called', value: Formatters.dateTimeFromIso(ticket.calledAt)),
            if (ticket.completedAt != null)
              _KeyValue(label: 'Completed', value: Formatters.dateTimeFromIso(ticket.completedAt)),
            if (ticket.counter != null || live?.counter != null)
              _KeyValue(
                label: 'Counter',
                value: (live?.counter ?? ticket.counter)!.name,
              ),
            _KeyValue(label: 'Queue date', value: ticket.queueDate),
            if (ticket.waitedMinutes > 0)
              _KeyValue(label: 'Waited', value: Formatters.duration(ticket.waitedMinutes)),
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
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
    return Column(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// The audit trail from `GET /tickets/:id/events` — proof to a marker that
/// every transition is recorded server-side.
class _Timeline extends ConsumerWidget {
  const _Timeline({required this.ticketId});

  final int ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TicketEvent>> events = ref.watch(ticketEventsProvider(ticketId));

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('History', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            events.when(
              loading: () => const SkeletonBox(height: 60),
              error: (Object error, _) => ErrorState(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(ticketEventsProvider(ticketId)),
              ),
              data: (List<TicketEvent> list) {
                if (list.isEmpty) {
                  return Text('Nothing recorded yet.', style: theme.textTheme.bodySmall);
                }
                return Column(
                  children: <Widget>[
                    for (int i = 0; i < list.length; i++)
                      _TimelineRow(event: list[i], isLast: i == list.length - 1),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast});

  final TicketEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                margin: const EdgeInsets.only(top: 4),
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(event.label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      Formatters.dateTimeFromIso(event.createdAt),
                      if (event.actorName != null) 'by ${event.actorName}',
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
