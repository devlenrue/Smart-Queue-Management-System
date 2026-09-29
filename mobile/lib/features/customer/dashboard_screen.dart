import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/theme/status_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/service.dart';
import '../../models/ticket.dart';
import '../../models/user.dart';
import '../../providers/auth_providers.dart';
import '../../providers/customer_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'widgets/announcement_strip.dart';

/// §40. The first thing a customer sees: their live ticket, then the
/// services they could join.
class CustomerDashboardScreen extends ConsumerWidget {
  const CustomerDashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(activeTicketsProvider);
    ref.invalidate(serviceListProvider);
    ref.invalidate(announcementsProvider);
    ref.invalidate(unreadCountProvider);
    await ref.read(activeTicketsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final User? user = ref.watch(currentUserProvider);
    final AsyncValue<List<Ticket>> tickets = ref.watch(activeTicketsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              Formatters.greeting(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(user?.firstName ?? 'there', style: theme.textTheme.titleLarge),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push(RoutePaths.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: Responsive.pagePadding(context),
          children: <Widget>[
            const AnnouncementStrip(),
            Text('Your queue', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            tickets.when(
              loading: () => const SkeletonBox(height: 150, radius: 16),
              error: (Object error, _) => ErrorState(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(activeTicketsProvider),
              ),
              data: (List<Ticket> list) => list.isEmpty
                  ? const _NoActiveTicket()
                  : Column(
                      children: <Widget>[
                        for (final Ticket ticket in list) ...<Widget>[
                          _ActiveTicketPanel(ticket: ticket),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Text('Available services', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go(RoutePaths.services),
                  child: const Text('Browse all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _ServiceHighlights(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// The hero card for a ticket that is currently live.
class _ActiveTicketPanel extends ConsumerWidget {
  const _ActiveTicketPanel({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Color accent = context.statusPalette.ofTicket(ticket.status);

    // Live position, refreshed on the poll interval.
    final AsyncValue<TicketPosition> position = ref.watch(ticketPositionProvider(ticket.id));
    final TicketPosition? value = position.valueOrNull;

    return AppCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(RoutePaths.ticketDetailOf(ticket.id)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ticket.serviceName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusBadge.ticket(context, value?.status ?? ticket.status, dense: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    ticket.ticketNumber,
                    style: theme.textTheme.displayMedium?.copyWith(color: accent),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        'NOW SERVING',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(value?.nowServing ?? '—', style: theme.textTheme.titleLarge),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (value != null && value.isBeingCalled)
                _CallToCounter(counterName: value.counter?.name)
              else
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Mini(
                        label: 'Ahead of you',
                        value: value == null ? '—' : '${value.peopleAhead}',
                      ),
                    ),
                    Expanded(
                      child: _Mini(
                        label: 'Your position',
                        value: value?.position == null
                            ? '—'
                            : Formatters.ordinal(value!.position!),
                      ),
                    ),
                    Expanded(
                      child: _Mini(
                        label: 'Est. wait',
                        value: value == null
                            ? '—'
                            : Formatters.duration(value.estimatedWaitMinutes),
                      ),
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

class _CallToCounter extends StatelessWidget {
  const _CallToCounter({this.counterName});

  final String? counterName;

  @override
  Widget build(BuildContext context) {
    final StatusPalette palette = context.statusPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.called.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.called.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.campaign_rounded, color: palette.called),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              counterName == null
                  ? 'You are being called. Please go to the counter now.'
                  : 'You are being called to $counterName. Please go now.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: palette.called),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _NoActiveTicket extends StatelessWidget {
  const _NoActiveTicket();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.confirmation_number_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No active ticket', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Pick a service below to take a number.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A short list of the busiest-to-quietest services, as a taster for the
/// full catalogue on the Services tab.
class _ServiceHighlights extends ConsumerWidget {
  const _ServiceHighlights();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedState<Service>> services = ref.watch(serviceListProvider);

    return services.when(
      loading: () => const Column(
        children: <Widget>[
          SkeletonBox(height: 86, radius: 16),
          SizedBox(height: 12),
          SkeletonBox(height: 86, radius: 16),
        ],
      ),
      error: (Object error, _) => ErrorState(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(serviceListProvider),
      ),
      data: (PagedState<Service> state) {
        final List<Service> open =
            state.items.where((Service s) => s.canJoin).take(3).toList(growable: false);
        final List<Service> shown = open.isEmpty ? state.items.take(3).toList() : open;

        if (shown.isEmpty) {
          return AppCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No services are set up yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        return Column(
          children: <Widget>[
            for (final Service service in shown) ...<Widget>[
              DashboardStatCard(
                label: service.name,
                value: '${service.waitingCount} waiting',
                caption: service.canJoin
                    ? 'Est. ${Formatters.duration(service.estimatedWaitMinutes)} · '
                        'now serving ${service.nowServing ?? '—'}'
                    : service.unavailableReason,
                icon: Icons.room_service_outlined,
                onTap: () => context.push(RoutePaths.serviceDetailOf(service.id)),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
