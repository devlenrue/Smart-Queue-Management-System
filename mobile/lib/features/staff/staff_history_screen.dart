import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/ticket.dart';
import '../../providers/paged_state.dart';
import '../../providers/staff_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';

/// What this clerk has handled — the server defaults the window to the last
/// seven days, which is the span a staff member is ever asked about.
class StaffHistoryScreen extends ConsumerStatefulWidget {
  const StaffHistoryScreen({super.key});

  @override
  ConsumerState<StaffHistoryScreen> createState() => _StaffHistoryScreenState();
}

class _StaffHistoryScreenState extends ConsumerState<StaffHistoryScreen> {
  final ScrollController _controller = ScrollController();

  static const List<({String? value, String label})> _filters = <({String? value, String label})>[
    (value: null, label: 'All'),
    (value: 'completed', label: 'Completed'),
    (value: 'skipped', label: 'Skipped'),
    (value: 'no_show', label: 'No-show'),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final double remaining = _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < 320) {
      ref.read(staffHistoryProvider.notifier).loadMore().catchError((Object error) {
        if (mounted) showFailureSnackBar(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<Ticket>> async = ref.watch(staffHistoryProvider);
    final String? active = ref.watch(staffHistoryFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My history'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              key: const Key('history-filters'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                for (final ({String? value, String label}) filter in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('history-filter-${filter.value ?? 'all'}'),
                      label: Text(filter.label),
                      selected: active == filter.value,
                      onSelected: (_) =>
                          ref.read(staffHistoryFilterProvider.notifier).set(filter.value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const SkeletonList(count: 5, itemHeight: 84),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(staffHistoryProvider)),
        data: (PagedState<Ticket> page) {
          if (page.isEmpty) {
            return EmptyState(
              icon: Icons.history_rounded,
              title: active == null ? 'Nothing handled yet' : 'No ${active.replaceAll('_', '-')} tickets',
              message: active == null
                  ? 'Tickets you call, serve or skip will be listed here.'
                  : 'Try a different filter.',
              actionLabel: active == null ? null : 'Show all',
              onAction: active == null
                  ? null
                  : () => ref.read(staffHistoryFilterProvider.notifier).set(null),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(staffHistoryProvider.notifier).refresh(),
            child: ListView.builder(
              controller: _controller,
              padding: Responsive.pagePadding(context),
              itemCount: page.items.length + (page.isLoadingMore ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index >= page.items.length) return const LoadMoreIndicator();
                return _HistoryRow(ticket: page.items[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? when = ticket.completedAt ?? ticket.calledAt ?? ticket.joinedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    ticket.ticketNumber,
                    key: Key('history-ticket-${ticket.id}'),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                StatusBadge.ticket(context, ticket.status, dense: true),
                const SizedBox(height: 4),
                Text(
                  Formatters.relativeFromIso(when),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (ticket.status == TicketStatus.completed && ticket.serviceMinutes != null)
                  Text(
                    'served in ${Formatters.duration(ticket.serviceMinutes)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
