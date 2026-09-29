import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/error_mapper.dart';
import '../core/network/api_response.dart';
import '../core/utils/polling.dart';
import '../models/announcement.dart';
import '../models/notification.dart';
import '../models/queue.dart';
import '../models/service.dart';
import '../models/ticket.dart';
import '../services/notification_api.dart';
import 'auth_providers.dart';
import 'infrastructure_providers.dart';
import 'paged_state.dart';

// ── services list ─────────────────────────────────────────────────────────

class ServiceFilters {
  const ServiceFilters({this.search = '', this.category});

  final String search;
  final String? category;

  ServiceFilters copyWith({String? search, String? category, bool clearCategory = false}) {
    return ServiceFilters(
      search: search ?? this.search,
      category: clearCategory ? null : (category ?? this.category),
    );
  }

  bool get isActive => search.isNotEmpty || category != null;

  @override
  bool operator ==(Object other) =>
      other is ServiceFilters && other.search == search && other.category == category;

  @override
  int get hashCode => Object.hash(search, category);
}

class ServiceFiltersNotifier extends Notifier<ServiceFilters> {
  @override
  ServiceFilters build() => const ServiceFilters();

  void setSearch(String value) => state = state.copyWith(search: value);
  void setCategory(String? value) =>
      state = value == null ? state.copyWith(clearCategory: true) : state.copyWith(category: value);
  void clear() => state = const ServiceFilters();
}

final NotifierProvider<ServiceFiltersNotifier, ServiceFilters> serviceFiltersProvider =
    NotifierProvider<ServiceFiltersNotifier, ServiceFilters>(ServiceFiltersNotifier.new);

/// The catalogue. Re-runs whenever the filters change, which is what makes
/// the search box work without a single line of filtering in the widget.
class ServiceListNotifier extends AutoDisposeAsyncNotifier<PagedState<Service>> {
  ServiceFilters _filters = const ServiceFilters();

  @override
  Future<PagedState<Service>> build() async {
    _filters = ref.watch(serviceFiltersProvider);

    final Paged<Service> page = await ref.watch(serviceRepositoryProvider).list(
          page: 1,
          limit: AppConstants.defaultPageSize,
          search: _filters.search,
          category: _filters.category,
        );
    return PagedState<Service>.fromPage(page);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final Paged<Service> page = await ref.read(serviceRepositoryProvider).list(
            page: 1,
            limit: AppConstants.defaultPageSize,
            search: _filters.search,
            category: _filters.category,
          );
      return PagedState<Service>.fromPage(page);
    });
  }

  Future<void> loadMore() async {
    final PagedState<Service>? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue<PagedState<Service>>.data(current.loadingMore());
    try {
      final Paged<Service> next = await ref.read(serviceRepositoryProvider).list(
            page: current.meta.page + 1,
            limit: current.meta.limit,
            search: _filters.search,
            category: _filters.category,
          );
      state = AsyncValue<PagedState<Service>>.data(current.appending(next));
    } catch (error) {
      // Keep the rows already on screen; the footer shows the retry.
      state = AsyncValue<PagedState<Service>>.data(current);
      throw ErrorMapper.fromObject(error);
    }
  }
}

final AutoDisposeAsyncNotifierProvider<ServiceListNotifier, PagedState<Service>>
    serviceListProvider =
    AsyncNotifierProvider.autoDispose<ServiceListNotifier, PagedState<Service>>(
        ServiceListNotifier.new);

final AutoDisposeFutureProvider<List<String>> serviceCategoriesProvider =
    FutureProvider.autoDispose<List<String>>((Ref ref) {
  return ref.watch(serviceRepositoryProvider).categories();
});

final AutoDisposeFutureProviderFamily<Service, int> serviceDetailProvider =
    FutureProvider.autoDispose.family<Service, int>((Ref ref, int id) {
  return ref.watch(serviceRepositoryProvider).byId(id);
});

final AutoDisposeFutureProviderFamily<List<ServiceHours>, int> serviceHoursProvider =
    FutureProvider.autoDispose.family<List<ServiceHours>, int>((Ref ref, int id) {
  return ref.watch(serviceRepositoryProvider).hours(id);
});

// ── tickets ───────────────────────────────────────────────────────────────

/// Every live ticket the signed-in customer holds. The dashboard and the
/// bottom-nav badge both read this.
class ActiveTicketsNotifier extends AutoDisposeAsyncNotifier<List<Ticket>> {
  @override
  Future<List<Ticket>> build() async {
    if (!ref.watch(isAuthenticatedProvider)) return const <Ticket>[];
    return ref.watch(ticketRepositoryProvider).active();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(ticketRepositoryProvider).active());
  }
}

final AutoDisposeAsyncNotifierProvider<ActiveTicketsNotifier, List<Ticket>> activeTicketsProvider =
    AsyncNotifierProvider.autoDispose<ActiveTicketsNotifier, List<Ticket>>(
        ActiveTicketsNotifier.new);

/// The one ticket the dashboard highlights.
final AutoDisposeProvider<Ticket?> currentTicketProvider = Provider.autoDispose<Ticket?>((Ref ref) {
  final List<Ticket>? tickets = ref.watch(activeTicketsProvider).valueOrNull;
  if (tickets == null || tickets.isEmpty) return null;
  return tickets.first;
});

final AutoDisposeFutureProviderFamily<Ticket, int> ticketDetailProvider =
    FutureProvider.autoDispose.family<Ticket, int>((Ref ref, int id) {
  return ref.watch(ticketRepositoryProvider).byId(id);
});

final AutoDisposeFutureProviderFamily<List<TicketEvent>, int> ticketEventsProvider =
    FutureProvider.autoDispose.family<List<TicketEvent>, int>((Ref ref, int id) {
  return ref.watch(ticketRepositoryProvider).events(id);
});

/// The live position feed (§45).
///
/// Polling, not websockets — §82 rules those out, and a 5-second re-read is
/// honest about what it costs. The loop stops as soon as the ticket reaches
/// a terminal state, so a completed ticket never keeps the radio awake.
class TicketPositionNotifier extends AutoDisposeFamilyStreamNotifier<TicketPosition, int> {
  @override
  Stream<TicketPosition> build(int ticketId) async* {
    final Duration interval = ref.watch(pollIntervalProvider);
    final repository = ref.watch(ticketRepositoryProvider);

    while (true) {
      final TicketPosition position = await repository.position(ticketId);
      yield position;
      if (position.isFinished) return;
      await Future<void>.delayed(interval);
    }
  }
}

final AutoDisposeStreamNotifierProviderFamily<TicketPositionNotifier, TicketPosition, int>
    ticketPositionProvider =
    StreamNotifierProvider.autoDispose.family<TicketPositionNotifier, TicketPosition, int>(
        TicketPositionNotifier.new);

/// Live queue figures for the tracking screen. Keeps the last good reading
/// when a single poll fails, so a flaky connection does not blank the board.
final AutoDisposeStreamProviderFamily<QueueStatusView, int> queueStatusProvider =
    StreamProvider.autoDispose.family<QueueStatusView, int>((Ref ref, int queueId) {
  final repository = ref.watch(queueRepositoryProvider);
  return pollKeepingLastValue<QueueStatusView>(
    AppConstants.queuePollInterval,
    () => repository.status(queueId),
  );
});

// ── history ───────────────────────────────────────────────────────────────

class HistoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) => state = status;
}

final NotifierProvider<HistoryFilterNotifier, String?> historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, String?>(HistoryFilterNotifier.new);

class TicketHistoryNotifier extends AutoDisposeAsyncNotifier<PagedState<Ticket>> {
  String? _status;

  @override
  Future<PagedState<Ticket>> build() async {
    _status = ref.watch(historyFilterProvider);
    final Paged<Ticket> page = await ref.watch(ticketRepositoryProvider).history(
          page: 1,
          limit: AppConstants.defaultPageSize,
          status: _status,
        );
    return PagedState<Ticket>.fromPage(page);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final Paged<Ticket> page = await ref.read(ticketRepositoryProvider).history(
            page: 1,
            limit: AppConstants.defaultPageSize,
            status: _status,
          );
      return PagedState<Ticket>.fromPage(page);
    });
  }

  Future<void> loadMore() async {
    final PagedState<Ticket>? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue<PagedState<Ticket>>.data(current.loadingMore());
    try {
      final Paged<Ticket> next = await ref.read(ticketRepositoryProvider).history(
            page: current.meta.page + 1,
            limit: current.meta.limit,
            status: _status,
          );
      state = AsyncValue<PagedState<Ticket>>.data(current.appending(next));
    } catch (error) {
      state = AsyncValue<PagedState<Ticket>>.data(current);
      throw ErrorMapper.fromObject(error);
    }
  }
}

final AutoDisposeAsyncNotifierProvider<TicketHistoryNotifier, PagedState<Ticket>>
    ticketHistoryProvider =
    AsyncNotifierProvider.autoDispose<TicketHistoryNotifier, PagedState<Ticket>>(
        TicketHistoryNotifier.new);

// ── queue actions ─────────────────────────────────────────────────────────

/// Join and cancel. Separate from the read providers because an action has
/// a lifecycle of its own: idle → in flight → done, and the button needs to
/// know which one it is in.
///
/// Kept alive rather than auto-disposed on purpose.
///
/// Every caller reaches this through `ref.read(...notifier)` from a button
/// handler and keeps its own busy flag, so nothing ever *watches* it. An
/// auto-dispose provider with no watchers is torn down on the next event-loop
/// turn — that is, while the request is still in flight — and the `ref` calls
/// it makes afterwards would throw. It holds one nullable result, so keeping
/// it alive costs nothing.
class QueueActionController extends AsyncNotifier<Ticket?> {
  @override
  Future<Ticket?> build() async => null;

  /// Returns the new ticket. Throws a [Failure] the sheet can render — a
  /// 409 here is an ordinary outcome (already queued, queue full), not a bug.
  Future<Ticket> join(int serviceId) async {
    state = const AsyncValue<Ticket?>.loading();
    try {
      final JoinResult result = await ref.read(queueRepositoryProvider).join(serviceId);
      state = AsyncValue<Ticket?>.data(result.ticket);
      _invalidateQueueReads();
      return result.ticket;
    } catch (error) {
      final failure = ErrorMapper.fromObject(error);
      state = AsyncValue<Ticket?>.error(failure, StackTrace.current);
      throw failure;
    }
  }

  Future<Ticket> cancel(int ticketId, {String? reason}) async {
    state = const AsyncValue<Ticket?>.loading();
    try {
      final Ticket ticket = await ref.read(ticketRepositoryProvider).cancel(ticketId, reason: reason);
      state = AsyncValue<Ticket?>.data(ticket);
      _invalidateQueueReads();
      ref.invalidate(ticketDetailProvider(ticketId));
      ref.invalidate(ticketEventsProvider(ticketId));
      return ticket;
    } catch (error) {
      final failure = ErrorMapper.fromObject(error);
      state = AsyncValue<Ticket?>.error(failure, StackTrace.current);
      throw failure;
    }
  }

  /// One join changes the catalogue's waiting counts, the active ticket
  /// list and the history, so all three are dropped at once.
  void _invalidateQueueReads() {
    ref.invalidate(serviceListProvider);
    ref.invalidate(activeTicketsProvider);
    ref.invalidate(ticketHistoryProvider);
  }
}

final AsyncNotifierProvider<QueueActionController, Ticket?> queueActionProvider =
    AsyncNotifierProvider<QueueActionController, Ticket?>(QueueActionController.new);

// ── notifications ─────────────────────────────────────────────────────────

class NotificationsNotifier extends AutoDisposeAsyncNotifier<PagedState<AppNotification>> {
  @override
  Future<PagedState<AppNotification>> build() async {
    if (!ref.watch(isAuthenticatedProvider)) {
      return PagedState<AppNotification>.fromPage(Paged.empty<AppNotification>());
    }
    final NotificationPage page =
        await ref.watch(notificationRepositoryProvider).list(limit: AppConstants.defaultPageSize);
    return PagedState<AppNotification>(items: page.items, meta: page.meta);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final NotificationPage page =
          await ref.read(notificationRepositoryProvider).list(limit: AppConstants.defaultPageSize);
      return PagedState<AppNotification>(items: page.items, meta: page.meta);
    });
  }

  Future<void> loadMore() async {
    final PagedState<AppNotification>? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue<PagedState<AppNotification>>.data(current.loadingMore());
    try {
      final NotificationPage next = await ref.read(notificationRepositoryProvider).list(
            page: current.meta.page + 1,
            limit: current.meta.limit,
          );
      state = AsyncValue<PagedState<AppNotification>>.data(
        current.appending(Paged<AppNotification>(items: next.items, meta: next.meta)),
      );
    } catch (error) {
      state = AsyncValue<PagedState<AppNotification>>.data(current);
      throw ErrorMapper.fromObject(error);
    }
  }

  /// Optimistic: the row greys out immediately, and is put back if the
  /// server refuses.
  Future<void> markRead(int id) async {
    final PagedState<AppNotification>? current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue<PagedState<AppNotification>>.data(
      current.withItems(<AppNotification>[
        for (final AppNotification item in current.items)
          item.id == id ? item.markedRead() : item,
      ]),
    );

    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
      ref.invalidate(unreadCountProvider);
    } catch (_) {
      state = AsyncValue<PagedState<AppNotification>>.data(current);
    }
  }

  Future<void> markAllRead() async {
    final PagedState<AppNotification>? current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue<PagedState<AppNotification>>.data(
      current.withItems(
        current.items.map((AppNotification item) => item.markedRead()).toList(growable: false),
      ),
    );

    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.invalidate(unreadCountProvider);
    } catch (_) {
      state = AsyncValue<PagedState<AppNotification>>.data(current);
    }
  }
}

final AutoDisposeAsyncNotifierProvider<NotificationsNotifier, PagedState<AppNotification>>
    notificationsProvider =
    AsyncNotifierProvider.autoDispose<NotificationsNotifier, PagedState<AppNotification>>(
        NotificationsNotifier.new);

/// The bell badge. Polled slowly — it is a nicety, not the main event.
final AutoDisposeStreamProvider<int> unreadCountProvider =
    StreamProvider.autoDispose<int>((Ref ref) {
  if (!ref.watch(isAuthenticatedProvider)) return Stream<int>.value(0);
  final repository = ref.watch(notificationRepositoryProvider);
  return pollEvery<int>(
    AppConstants.unreadPollInterval,
    repository.unreadCount,
    emitErrors: false,
  );
});

// ── announcements ─────────────────────────────────────────────────────────

final AutoDisposeFutureProvider<List<Announcement>> announcementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((Ref ref) async {
  final Paged<Announcement> page =
      await ref.watch(notificationRepositoryProvider).announcements(limit: 20);
  return page.items;
});

final AutoDisposeFutureProviderFamily<Announcement, int> announcementDetailProvider =
    FutureProvider.autoDispose.family<Announcement, int>((Ref ref, int id) {
  return ref.watch(notificationRepositoryProvider).announcement(id);
});
