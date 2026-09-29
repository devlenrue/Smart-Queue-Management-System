import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../core/errors/error_mapper.dart';
import '../core/network/api_response.dart';
import '../models/counter.dart';
import '../models/queue.dart';
import '../models/staff_dashboard.dart';
import '../models/staff_statistics.dart';
import '../models/ticket.dart';
import '../repositories/staff_repository.dart';
import 'auth_providers.dart';
import 'infrastructure_providers.dart';
import 'paged_state.dart';

// ── the console's live view ───────────────────────────────────────────────

/// The whole dashboard, re-read on a timer.
///
/// A stream rather than a future because the waiting list changes while the
/// clerk is looking at it: another counter calls someone, a customer cancels.
/// Polling at the queue interval (10 s by default) keeps it close enough to
/// live without a socket, which §82 rules out.
class StaffDashboardNotifier extends AutoDisposeStreamNotifier<StaffDashboard> {
  @override
  Stream<StaffDashboard> build() async* {
    if (!ref.watch(isAuthenticatedProvider)) return;

    final StaffRepository repository = ref.watch(staffRepositoryProvider);
    final Duration interval = ref.watch(pollIntervalProvider);

    StaffDashboard? last;
    while (true) {
      try {
        last = await repository.dashboard();
        yield last;
      } catch (error) {
        // A dropped poll must not blank a console someone is working from.
        if (last == null) rethrow;
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Re-reads immediately, without waiting for the next tick — what every
  /// successful action calls.
  Future<void> refreshNow() async {
    final StaffDashboard fresh = await ref.read(staffRepositoryProvider).dashboard();
    state = AsyncValue<StaffDashboard>.data(fresh);
  }
}

final AutoDisposeStreamNotifierProvider<StaffDashboardNotifier, StaffDashboard>
    staffDashboardProvider =
    StreamNotifierProvider.autoDispose<StaffDashboardNotifier, StaffDashboard>(
        StaffDashboardNotifier.new);

/// Every counter at the clerk's service — who else is on duty (§20).
final AutoDisposeFutureProvider<List<ServiceCounter>> serviceCountersProvider =
    FutureProvider.autoDispose<List<ServiceCounter>>((Ref ref) async {
  final int? serviceId = ref.watch(staffDashboardProvider).valueOrNull?.service?.id;
  if (serviceId == null) return const <ServiceCounter>[];
  return ref.watch(staffRepositoryProvider).counters(serviceId: serviceId);
});

// ── the full waiting list ─────────────────────────────────────────────────

/// The dashboard previews five; this screen shows everyone.
///
/// It reads the queue monitor rather than the dashboard because the monitor
/// returns the whole waiting list *and* the state of every counter, which is
/// what the current-queue screen shows in its header. Watching the dashboard
/// means the list re-reads on the same tick, so the two never disagree.
class StaffQueueNotifier extends AutoDisposeAsyncNotifier<QueueMonitor?> {
  @override
  Future<QueueMonitor?> build() async {
    final int? queueId = ref.watch(staffDashboardProvider).valueOrNull?.queue?.queueId;
    if (queueId == null) return null;
    return ref.watch(queueRepositoryProvider).monitor(queueId);
  }

  Future<void> refresh() async {
    final int? queueId = ref.read(staffDashboardProvider).valueOrNull?.queue?.queueId;
    if (queueId == null) return;
    state = await AsyncValue.guard(() => ref.read(queueRepositoryProvider).monitor(queueId));
  }
}

final AutoDisposeAsyncNotifierProvider<StaffQueueNotifier, QueueMonitor?> staffQueueProvider =
    AsyncNotifierProvider.autoDispose<StaffQueueNotifier, QueueMonitor?>(StaffQueueNotifier.new);

// ── actions ───────────────────────────────────────────────────────────────

/// Every write the console performs.
///
/// One controller for all of them, because they share the same shape: run,
/// refresh the console, and hand the caller either a result or a [Failure]
/// to show.
///
/// Kept alive rather than auto-disposed on purpose.
///
/// Every caller reaches this through `ref.read(...notifier)` from a button
/// handler and keeps its own busy flag, so nothing ever *watches* it. An
/// auto-dispose provider with no watchers is torn down on the next event-loop
/// turn — that is, while the request is still in flight — and the `ref` calls
/// it makes afterwards would throw. It holds one nullable result, so keeping
/// it alive costs nothing.
class StaffActionController extends AsyncNotifier<TicketActionResult?> {
  @override
  Future<TicketActionResult?> build() async => null;

  StaffRepository get _repository => ref.read(staffRepositoryProvider);

  Future<TicketActionResult> callNext({required int serviceId, int? counterId}) {
    return _run(() => _repository.callNext(serviceId: serviceId, counterId: counterId));
  }

  Future<TicketActionResult> call(int ticketId, {int? counterId}) {
    return _run(() => _repository.call(ticketId, counterId: counterId));
  }

  Future<TicketActionResult> perform(StaffAction action, int ticketId, {String? reason}) {
    switch (action) {
      case StaffAction.call:
        return call(ticketId);
      case StaffAction.recall:
        return _run(() => _repository.recall(ticketId));
      case StaffAction.start:
        return _run(() => _repository.start(ticketId));
      case StaffAction.complete:
        return _run(() => _repository.complete(ticketId));
      case StaffAction.skip:
        return _run(() => _repository.skip(ticketId, reason: reason));
      case StaffAction.noShow:
        return _run(() => _repository.noShow(ticketId));
    }
  }

  Future<StaffCounter> setCounterStatus(int counterId, CounterStatus status) async {
    state = const AsyncValue<TicketActionResult?>.loading();
    try {
      final StaffCounter counter = await _repository.setCounterStatus(counterId, status);
      state = const AsyncValue<TicketActionResult?>.data(null);
      await _refreshConsole();
      return counter;
    } catch (error) {
      final failure = ErrorMapper.fromObject(error);
      state = AsyncValue<TicketActionResult?>.error(failure, StackTrace.current);
      throw failure;
    }
  }

  Future<TicketActionResult> _run(Future<TicketActionResult> Function() action) async {
    state = const AsyncValue<TicketActionResult?>.loading();
    try {
      final TicketActionResult result = await action();
      state = AsyncValue<TicketActionResult?>.data(result);
      await _refreshConsole();
      return result;
    } catch (error) {
      // A 409 here is an ordinary outcome — somebody else got there first —
      // so the screen renders it, and the controller does not log it as a bug.
      final failure = ErrorMapper.fromObject(error);
      state = AsyncValue<TicketActionResult?>.error(failure, StackTrace.current);
      throw failure;
    }
  }

  /// One transition moves the queue, the counter, the tallies and the
  /// history, so all of them are re-read rather than patched by hand.
  Future<void> _refreshConsole() async {
    ref.invalidate(staffHistoryProvider);
    ref.invalidate(staffStatisticsProvider);
    ref.invalidate(serviceCountersProvider);
    try {
      await ref.read(staffDashboardProvider.notifier).refreshNow();
    } catch (_) {
      // The action itself succeeded; a failed refresh is the poller's problem.
    }
    ref.invalidate(staffQueueProvider);
  }
}

final AsyncNotifierProvider<StaffActionController, TicketActionResult?> staffActionProvider =
    AsyncNotifierProvider<StaffActionController, TicketActionResult?>(StaffActionController.new);

// ── history ───────────────────────────────────────────────────────────────

class StaffHistoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) => state = status;
}

final NotifierProvider<StaffHistoryFilterNotifier, String?> staffHistoryFilterProvider =
    NotifierProvider<StaffHistoryFilterNotifier, String?>(StaffHistoryFilterNotifier.new);

/// What this clerk handled — defaults to the server's last-seven-days window.
class StaffHistoryNotifier extends AutoDisposeAsyncNotifier<PagedState<Ticket>> {
  String? _status;

  @override
  Future<PagedState<Ticket>> build() async {
    _status = ref.watch(staffHistoryFilterProvider);
    final Paged<Ticket> page = await ref.watch(staffRepositoryProvider).handledTickets(
          page: 1,
          limit: AppConstants.defaultPageSize,
          status: _status,
        );
    return PagedState<Ticket>.fromPage(page);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final Paged<Ticket> page = await ref.read(staffRepositoryProvider).handledTickets(
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
      final Paged<Ticket> next = await ref.read(staffRepositoryProvider).handledTickets(
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

final AutoDisposeAsyncNotifierProvider<StaffHistoryNotifier, PagedState<Ticket>>
    staffHistoryProvider =
    AsyncNotifierProvider.autoDispose<StaffHistoryNotifier, PagedState<Ticket>>(
        StaffHistoryNotifier.new);

// ── statistics ────────────────────────────────────────────────────────────

/// The chosen window on the statistics screen. Null means "let the server
/// decide", which is the last seven days.
class StatsRange {
  const StatsRange({this.from, this.to, this.label = 'Last 7 days'});

  final String? from;
  final String? to;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is StatsRange && other.from == from && other.to == to && other.label == label;

  @override
  int get hashCode => Object.hash(from, to, label);
}

class StatsRangeNotifier extends Notifier<StatsRange> {
  @override
  StatsRange build() => const StatsRange();

  void set(StatsRange range) => state = range;
}

final NotifierProvider<StatsRangeNotifier, StatsRange> statsRangeProvider =
    NotifierProvider<StatsRangeNotifier, StatsRange>(StatsRangeNotifier.new);

final AutoDisposeFutureProvider<StaffStatistics> staffStatisticsProvider =
    FutureProvider.autoDispose<StaffStatistics>((Ref ref) {
  final StatsRange range = ref.watch(statsRangeProvider);
  return ref.watch(staffRepositoryProvider).statistics(from: range.from, to: range.to);
});
