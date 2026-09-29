import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../models/ticket.dart';
import '../../providers/customer_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/ticket_card.dart';

/// §47. Every ticket this customer has ever taken, newest first, filterable
/// by status and paged from the server.
class MyTicketsScreen extends ConsumerStatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  ConsumerState<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends ConsumerState<MyTicketsScreen> {
  final ScrollController _controller = ScrollController();

  static const List<({String? value, String label})> _filters = <({String? value, String label})>[
    (value: null, label: 'All'),
    (value: 'waiting', label: 'Waiting'),
    (value: 'serving', label: 'Being served'),
    (value: 'completed', label: 'Completed'),
    (value: 'cancelled', label: 'Cancelled'),
    (value: 'no_show', label: 'No show'),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final double remaining = _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < 400) {
      unawaited(ref.read(ticketHistoryProvider.notifier).loadMore().catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<Ticket>> history = ref.watch(ticketHistoryProvider);
    final String? active = ref.watch(historyFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My tickets'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                for (final ({String? value, String label}) filter in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 10),
                    child: FilterChip(
                      label: Text(filter.label),
                      selected: active == filter.value,
                      onSelected: (_) =>
                          ref.read(historyFilterProvider.notifier).set(filter.value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ticketHistoryProvider.notifier).refresh(),
        child: history.when(
          loading: () => const SkeletonList(itemHeight: 96),
          error: (Object error, _) => ListView(
            children: <Widget>[
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
              ErrorState(
                error: error,
                onRetry: () => ref.read(ticketHistoryProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (PagedState<Ticket> state) {
            if (state.isEmpty) {
              return ListView(
                children: <Widget>[
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  EmptyState(
                    icon: Icons.confirmation_number_outlined,
                    title: active == null ? 'No tickets yet' : 'Nothing with that status',
                    message: active == null
                        ? 'When you join a queue your ticket will show up here.'
                        : 'Try a different filter to see your other tickets.',
                    actionLabel: active == null ? 'Browse services' : 'Show all',
                    onAction: active == null
                        ? () => context.go(RoutePaths.services)
                        : () => ref.read(historyFilterProvider.notifier).set(null),
                  ),
                ],
              );
            }

            return ListView.separated(
              controller: _controller,
              padding: Responsive.pagePadding(context),
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                if (index >= state.items.length) return const LoadMoreIndicator();
                final Ticket ticket = state.items[index];
                return TicketCard(
                  key: Key('history-ticket-${ticket.id}'),
                  ticket: ticket,
                  onTap: () => context.push(RoutePaths.ticketDetailOf(ticket.id)),
                  trailing: ticket.status.isActive
                      ? Icon(
                          Icons.circle,
                          size: 10,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
