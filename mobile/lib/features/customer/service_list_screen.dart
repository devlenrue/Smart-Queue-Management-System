import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../models/service.dart';
import '../../models/ticket.dart';
import '../../providers/customer_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/service_card.dart';
import 'widgets/join_queue_sheet.dart';

/// §42. The service catalogue, with search, category filter and paging.
///
/// Searching and filtering happen on the server (`?search=&category=`) so
/// the list stays correct when there are more services than one page.
class ServiceListScreen extends ConsumerStatefulWidget {
  const ServiceListScreen({super.key});

  @override
  ConsumerState<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends ConsumerState<ServiceListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int? _joiningServiceId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double remaining =
        _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    if (remaining < 400) {
      unawaited(ref.read(serviceListProvider.notifier).loadMore().catchError((Object _) {}));
    }
  }

  /// Typing fires a request per keystroke otherwise; 350 ms is long enough
  /// to batch a word and short enough to still feel instant.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(serviceFiltersProvider.notifier).setSearch(value.trim());
    });
  }

  Future<void> _join(Service service) async {
    setState(() => _joiningServiceId = service.id);
    final Ticket? ticket = await JoinQueueSheet.show(context, service);
    if (!mounted) return;
    setState(() => _joiningServiceId = null);

    if (ticket != null) {
      showSuccessSnackBar(context, 'Ticket ${ticket.ticketNumber} is yours.');
      context.push(RoutePaths.ticketDetailOf(ticket.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<Service>> services = ref.watch(serviceListProvider);
    final ServiceFilters filters = ref.watch(serviceFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(124),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: <Widget>[
                TextField(
                  key: const Key('service-search'),
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search services',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                const _CategoryFilterBar(),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(serviceListProvider.notifier).refresh(),
        child: services.when(
          loading: () => const SkeletonList(),
          error: (Object error, _) => ListView(
            children: <Widget>[
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
              ErrorState(
                error: error,
                onRetry: () => ref.read(serviceListProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (PagedState<Service> state) {
            if (state.isEmpty) {
              return ListView(
                children: <Widget>[
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    title: filters.isActive ? 'No matches' : 'No services yet',
                    message: filters.isActive
                        ? 'Nothing matches that search. Try a different word or clear the filters.'
                        : 'Once an administrator adds a service it will appear here.',
                    actionLabel: filters.isActive ? 'Clear filters' : null,
                    onAction: filters.isActive
                        ? () {
                            _searchController.clear();
                            ref.read(serviceFiltersProvider.notifier).clear();
                          }
                        : null,
                  ),
                ],
              );
            }

            final int columns = Responsive.columns(context);

            return ListView.separated(
              controller: _scrollController,
              padding: Responsive.pagePadding(context),
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                if (index >= state.items.length) return const LoadMoreIndicator();

                // On a wide window, pack two or three cards per row.
                if (columns > 1 && index % columns != 0) return const SizedBox.shrink();
                if (columns > 1) {
                  final List<Service> row = state.items
                      .skip(index)
                      .take(columns)
                      .toList(growable: false);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int i = 0; i < columns; i++) ...<Widget>[
                        Expanded(
                          child: i < row.length
                              ? _card(row[i])
                              : const SizedBox.shrink(),
                        ),
                        if (i < columns - 1) const SizedBox(width: 12),
                      ],
                    ],
                  );
                }

                return _card(state.items[index]);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _card(Service service) {
    return ServiceCard(
      key: Key('service-card-${service.id}'),
      service: service,
      isJoining: _joiningServiceId == service.id,
      onTap: () => context.push(RoutePaths.serviceDetailOf(service.id)),
      onJoin: () => _join(service),
    );
  }
}

class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<String>> categories = ref.watch(serviceCategoriesProvider);
    final ServiceFilters filters = ref.watch(serviceFiltersProvider);
    final List<String> values = categories.valueOrNull ?? const <String>[];

    if (values.isEmpty) return const SizedBox(height: 0);

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: filters.category == null,
              onSelected: (_) => ref.read(serviceFiltersProvider.notifier).setCategory(null),
            ),
          ),
          for (final String category in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(category),
                selected: filters.category == category,
                onSelected: (bool selected) => ref
                    .read(serviceFiltersProvider.notifier)
                    .setCategory(selected ? category : null),
              ),
            ),
        ],
      ),
    );
  }
}
