import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../core/errors/error_mapper.dart';
import '../core/network/api_response.dart';
import '../models/admin_dashboard.dart';
import '../models/announcement.dart';
import '../models/counter.dart';
import '../models/queue.dart';
import '../models/service.dart';
import '../models/staff_member.dart';
import '../models/system_setting.dart';
import '../models/user.dart';
import '../models/user_detail.dart';
import '../repositories/admin_repository.dart';
import 'auth_providers.dart';
import 'infrastructure_providers.dart';
import 'paged_state.dart';

/// State for the administrator console.
///
/// Three kinds of provider live here:
///
/// * one polled stream — the dashboard, which has to stay live;
/// * a handful of filtered, paged lists — users, staff, announcements;
/// * a single write controller, [AdminActionController], which every mutation
///   goes through so that the invalidation rules are stated once.

// ── dashboard (§31, §42) ──────────────────────────────────────────────────

/// The dashboard is institution-wide rather than per-customer, so it moves
/// slowly; a third of the queue poll rate is plenty and keeps a supervisor's
/// screen from hammering the API all day.
final Provider<Duration> adminPollIntervalProvider = Provider<Duration>((Ref ref) {
  return ref.watch(pollIntervalProvider) * 3;
});

/// How many days of history the served-per-day chart shows.
class DashboardWindowNotifier extends Notifier<int> {
  @override
  int build() => 7;

  void set(int days) => state = days.clamp(1, 31);
}

final NotifierProvider<DashboardWindowNotifier, int> dashboardWindowProvider =
    NotifierProvider<DashboardWindowNotifier, int>(DashboardWindowNotifier.new);

class AdminDashboardNotifier extends AutoDisposeStreamNotifier<AdminDashboard> {
  @override
  Stream<AdminDashboard> build() async* {
    if (!ref.watch(isAuthenticatedProvider)) return;

    final AdminRepository repository = ref.watch(adminRepositoryProvider);
    final int days = ref.watch(dashboardWindowProvider);
    final Duration interval = ref.watch(adminPollIntervalProvider);

    AdminDashboard? last;
    while (true) {
      try {
        last = await repository.dashboard(days: days);
        yield last;
      } catch (error) {
        // One dropped poll must not blank a board someone is watching.
        if (last == null) rethrow;
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<void> refreshNow() async {
    final AdminDashboard fresh = await ref
        .read(adminRepositoryProvider)
        .dashboard(days: ref.read(dashboardWindowProvider));
    state = AsyncValue<AdminDashboard>.data(fresh);
  }
}

final AutoDisposeStreamNotifierProvider<AdminDashboardNotifier, AdminDashboard>
    adminDashboardProvider =
    StreamNotifierProvider.autoDispose<AdminDashboardNotifier, AdminDashboard>(
        AdminDashboardNotifier.new);

// ── users (§9, §40) ───────────────────────────────────────────────────────

/// Search text plus the two dropdowns above the user table.
class UserFilter {
  const UserFilter({this.search, this.role, this.status});

  final String? search;
  final UserRole? role;
  final UserStatus? status;

  UserFilter copyWith({
    Object? search = _unset,
    Object? role = _unset,
    Object? status = _unset,
  }) {
    return UserFilter(
      search: search == _unset ? this.search : search as String?,
      role: role == _unset ? this.role : role as UserRole?,
      status: status == _unset ? this.status : status as UserStatus?,
    );
  }

  bool get isEmpty => (search == null || search!.isEmpty) && role == null && status == null;

  @override
  bool operator ==(Object other) =>
      other is UserFilter &&
      other.search == search &&
      other.role == role &&
      other.status == status;

  @override
  int get hashCode => Object.hash(search, role, status);
}

/// Sentinel so `copyWith(role: null)` can mean "clear the filter" rather
/// than "leave it alone".
const Object _unset = Object();

class UserFilterNotifier extends Notifier<UserFilter> {
  @override
  UserFilter build() => const UserFilter();

  void search(String? value) => state = state.copyWith(search: value);
  void role(UserRole? value) => state = state.copyWith(role: value);
  void status(UserStatus? value) => state = state.copyWith(status: value);
  void clear() => state = const UserFilter();
}

final NotifierProvider<UserFilterNotifier, UserFilter> userFilterProvider =
    NotifierProvider<UserFilterNotifier, UserFilter>(UserFilterNotifier.new);

class AdminUsersNotifier extends AutoDisposeAsyncNotifier<PagedState<User>> {
  late UserFilter _filter;

  @override
  Future<PagedState<User>> build() async {
    _filter = ref.watch(userFilterProvider);
    return PagedState<User>.fromPage(await _fetch(1));
  }

  Future<Paged<User>> _fetch(int page) {
    return ref.read(adminRepositoryProvider).users(
          page: page,
          limit: AppConstants.defaultPageSize,
          search: _filter.search,
          role: _filter.role,
          status: _filter.status,
        );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async => PagedState<User>.fromPage(await _fetch(1)));
  }

  Future<void> loadMore() async {
    final PagedState<User>? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue<PagedState<User>>.data(current.loadingMore());
    try {
      state = AsyncValue<PagedState<User>>.data(current.appending(await _fetch(current.meta.page + 1)));
    } catch (error) {
      state = AsyncValue<PagedState<User>>.data(current);
      throw ErrorMapper.fromObject(error);
    }
  }
}

final AutoDisposeAsyncNotifierProvider<AdminUsersNotifier, PagedState<User>> adminUsersProvider =
    AsyncNotifierProvider.autoDispose<AdminUsersNotifier, PagedState<User>>(
        AdminUsersNotifier.new);

final AutoDisposeFutureProviderFamily<UserDetail, int> adminUserProvider =
    FutureProvider.autoDispose.family<UserDetail, int>((Ref ref, int id) {
  return ref.watch(adminRepositoryProvider).user(id);
});

// ── staff roster (§55) ────────────────────────────────────────────────────

class StaffFilter {
  const StaffFilter({this.search, this.serviceId, this.status, this.unassignedOnly = false});

  final String? search;
  final int? serviceId;
  final UserStatus? status;
  final bool unassignedOnly;

  StaffFilter copyWith({
    Object? search = _unset,
    Object? serviceId = _unset,
    Object? status = _unset,
    bool? unassignedOnly,
  }) {
    return StaffFilter(
      search: search == _unset ? this.search : search as String?,
      serviceId: serviceId == _unset ? this.serviceId : serviceId as int?,
      status: status == _unset ? this.status : status as UserStatus?,
      unassignedOnly: unassignedOnly ?? this.unassignedOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StaffFilter &&
      other.search == search &&
      other.serviceId == serviceId &&
      other.status == status &&
      other.unassignedOnly == unassignedOnly;

  @override
  int get hashCode => Object.hash(search, serviceId, status, unassignedOnly);
}

class StaffFilterNotifier extends Notifier<StaffFilter> {
  @override
  StaffFilter build() => const StaffFilter();

  void search(String? value) => state = state.copyWith(search: value);
  void service(int? value) => state = state.copyWith(serviceId: value);
  void status(UserStatus? value) => state = state.copyWith(status: value);
  void unassignedOnly(bool value) => state = state.copyWith(unassignedOnly: value);
  void clear() => state = const StaffFilter();
}

final NotifierProvider<StaffFilterNotifier, StaffFilter> staffFilterProvider =
    NotifierProvider<StaffFilterNotifier, StaffFilter>(StaffFilterNotifier.new);

class AdminStaffNotifier extends AutoDisposeAsyncNotifier<PagedState<StaffMember>> {
  late StaffFilter _filter;

  @override
  Future<PagedState<StaffMember>> build() async {
    _filter = ref.watch(staffFilterProvider);
    return PagedState<StaffMember>.fromPage(await _fetch(1));
  }

  Future<Paged<StaffMember>> _fetch(int page) {
    return ref.read(adminRepositoryProvider).staff(
          page: page,
          limit: AppConstants.defaultPageSize,
          search: _filter.search,
          serviceId: _filter.serviceId,
          status: _filter.status,
          unassigned: _filter.unassignedOnly,
        );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async => PagedState<StaffMember>.fromPage(await _fetch(1)));
  }

  Future<void> loadMore() async {
    final PagedState<StaffMember>? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue<PagedState<StaffMember>>.data(current.loadingMore());
    try {
      state = AsyncValue<PagedState<StaffMember>>.data(
        current.appending(await _fetch(current.meta.page + 1)),
      );
    } catch (error) {
      state = AsyncValue<PagedState<StaffMember>>.data(current);
      throw ErrorMapper.fromObject(error);
    }
  }
}

final AutoDisposeAsyncNotifierProvider<AdminStaffNotifier, PagedState<StaffMember>>
    adminStaffProvider =
    AsyncNotifierProvider.autoDispose<AdminStaffNotifier, PagedState<StaffMember>>(
        AdminStaffNotifier.new);

// ── services and counters (§4, §54) ───────────────────────────────────────

/// Every service, whatever its status — the admin table shows closed and
/// retired ones too, which the customer list deliberately hides.
final AutoDisposeFutureProvider<List<Service>> adminServicesProvider =
    FutureProvider.autoDispose<List<Service>>((Ref ref) async {
  final Paged<Service> page = await ref.watch(serviceRepositoryProvider).list(limit: 100);
  return page.items;
});

/// Every counter in the institution, in one read, grouped by the screen.
final AutoDisposeFutureProvider<List<ServiceCounter>> adminCountersProvider =
    FutureProvider.autoDispose<List<ServiceCounter>>((Ref ref) {
  return ref.watch(staffRepositoryProvider).counters();
});

/// The clerks an assign dialog may offer. Kept separate from
/// [adminStaffProvider] so opening a dialog does not disturb the table's
/// filters.
final AutoDisposeFutureProvider<List<StaffMember>> assignableStaffProvider =
    FutureProvider.autoDispose<List<StaffMember>>((Ref ref) async {
  final Paged<StaffMember> page =
      await ref.watch(adminRepositoryProvider).staff(limit: 100, status: UserStatus.active);
  return page.items;
});

// ── queue monitor (§54) ───────────────────────────────────────────────────

final AutoDisposeFutureProvider<List<QueueStatusView>> adminQueuesProvider =
    FutureProvider.autoDispose<List<QueueStatusView>>((Ref ref) {
  return ref.watch(queueRepositoryProvider).list();
});

/// One service's live board. Polls like the staff console does, because it
/// is the same data a supervisor would otherwise walk over to look at.
class AdminMonitorNotifier extends AutoDisposeFamilyStreamNotifier<QueueMonitor?, int> {
  @override
  Stream<QueueMonitor?> build(int serviceId) async* {
    final Duration interval = ref.watch(pollIntervalProvider);
    final List<QueueStatusView> queues = await ref.watch(adminQueuesProvider.future);

    QueueStatusView? queue;
    for (final QueueStatusView candidate in queues) {
      if (candidate.serviceId == serviceId) {
        queue = candidate;
        break;
      }
    }
    // No queue today means nobody has joined yet — an empty board, not an
    // error.
    if (queue == null) {
      yield null;
      return;
    }

    QueueMonitor? last;
    while (true) {
      try {
        last = await ref.read(queueRepositoryProvider).monitor(queue.queueId);
        yield last;
      } catch (error) {
        if (last == null) rethrow;
      }
      await Future<void>.delayed(interval);
    }
  }
}

final AutoDisposeStreamNotifierProviderFamily<AdminMonitorNotifier, QueueMonitor?, int>
    adminMonitorProvider =
    StreamNotifierProvider.autoDispose.family<AdminMonitorNotifier, QueueMonitor?, int>(
        AdminMonitorNotifier.new);

// ── announcements (§11) ───────────────────────────────────────────────────

class AnnouncementFilterNotifier extends Notifier<AnnouncementStatus?> {
  @override
  AnnouncementStatus? build() => null;

  void set(AnnouncementStatus? value) => state = value;
}

final NotifierProvider<AnnouncementFilterNotifier, AnnouncementStatus?>
    announcementFilterProvider =
    NotifierProvider<AnnouncementFilterNotifier, AnnouncementStatus?>(
        AnnouncementFilterNotifier.new);

class AdminAnnouncementsNotifier
    extends AutoDisposeAsyncNotifier<PagedState<ManagedAnnouncement>> {
  AnnouncementStatus? _status;

  @override
  Future<PagedState<ManagedAnnouncement>> build() async {
    _status = ref.watch(announcementFilterProvider);
    return PagedState<ManagedAnnouncement>.fromPage(await _fetch(1));
  }

  Future<Paged<ManagedAnnouncement>> _fetch(int page) {
    return ref.read(adminRepositoryProvider).announcements(
          page: page,
          limit: AppConstants.defaultPageSize,
          status: _status,
        );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () async => PagedState<ManagedAnnouncement>.fromPage(await _fetch(1)),
    );
  }

  Future<void> loadMore() async {
    final PagedState<ManagedAnnouncement>? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue<PagedState<ManagedAnnouncement>>.data(current.loadingMore());
    try {
      state = AsyncValue<PagedState<ManagedAnnouncement>>.data(
        current.appending(await _fetch(current.meta.page + 1)),
      );
    } catch (error) {
      state = AsyncValue<PagedState<ManagedAnnouncement>>.data(current);
      throw ErrorMapper.fromObject(error);
    }
  }
}

final AutoDisposeAsyncNotifierProvider<AdminAnnouncementsNotifier,
        PagedState<ManagedAnnouncement>> adminAnnouncementsProvider =
    AsyncNotifierProvider.autoDispose<AdminAnnouncementsNotifier,
        PagedState<ManagedAnnouncement>>(AdminAnnouncementsNotifier.new);

// ── system settings (§14) ─────────────────────────────────────────────────

final AutoDisposeFutureProvider<List<SystemSetting>> systemSettingsProvider =
    FutureProvider.autoDispose<List<SystemSetting>>((Ref ref) {
  return ref.watch(adminRepositoryProvider).settings();
});

// ── writes ────────────────────────────────────────────────────────────────

/// Every administrative write.
///
/// Kept alive for the same reason [StaffActionController] is: callers reach
/// it through `ref.read(...notifier)` from a button, so nothing watches it,
/// and an auto-disposed notifier would be torn down mid-request.
///
/// Each method states which lists its change invalidates. That is the whole
/// point of routing writes through one class — the rules are in one file
/// instead of scattered across ten dialogs.
class AdminActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

  // users ------------------------------------------------------------------

  Future<User> setUserStatus(int id, UserStatus status) {
    return _run(() async {
      final User user = await _repository.setUserStatus(id, status);
      // Suspending a clerk frees their counter, so the roster and the
      // counter board move too.
      _invalidateUsers();
      _invalidateRoster();
      return user;
    });
  }

  Future<User> setUserRole(int id, UserRole role) {
    return _run(() async {
      final User user = await _repository.setUserRole(id, role);
      _invalidateUsers();
      _invalidateRoster();
      return user;
    });
  }

  Future<void> deleteUser(int id) {
    return _run(() async {
      await _repository.deleteUser(id);
      _invalidateUsers();
      _invalidateRoster();
    });
  }

  // staff ------------------------------------------------------------------

  Future<StaffMember> createStaff({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    int? serviceId,
    int? counterId,
  }) {
    return _run(() async {
      final StaffMember staff = await _repository.createStaff(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
        serviceId: serviceId,
        counterId: counterId,
      );
      _invalidateRoster();
      _invalidateUsers();
      return staff;
    });
  }

  Future<StaffMember> updateStaff(
    int id, {
    String? firstName,
    String? lastName,
    String? phone,
    UserStatus? status,
  }) {
    return _run(() async {
      final StaffMember staff = await _repository.updateStaff(
        id,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        status: status,
      );
      _invalidateRoster();
      _invalidateUsers();
      return staff;
    });
  }

  Future<StaffMember> assignStaff(int id, {required int counterId}) {
    return _run(() async {
      final StaffMember staff = await _repository.assignStaff(id, counterId: counterId);
      _invalidateRoster();
      return staff;
    });
  }

  Future<StaffMember> unassignStaff(int id) {
    return _run(() async {
      final StaffMember staff = await _repository.unassignStaff(id);
      _invalidateRoster();
      return staff;
    });
  }

  // counters ---------------------------------------------------------------

  Future<ServiceCounter> createCounter({
    required int serviceId,
    required int counterNumber,
    String? name,
    int? staffId,
  }) {
    return _run(() async {
      final ServiceCounter counter = await _repository.createCounter(
        serviceId: serviceId,
        counterNumber: counterNumber,
        name: name,
        staffId: staffId,
      );
      _invalidateRoster();
      return counter;
    });
  }

  Future<ServiceCounter> updateCounter(
    int id, {
    int? counterNumber,
    String? name,
    CounterStatus? status,
  }) {
    return _run(() async {
      final ServiceCounter counter = await _repository.updateCounter(
        id,
        counterNumber: counterNumber,
        name: name,
        status: status,
      );
      _invalidateRoster();
      return counter;
    });
  }

  Future<ServiceCounter> assignCounter(int id, {required int staffId}) {
    return _run(() async {
      final ServiceCounter counter = await _repository.assignCounter(id, staffId: staffId);
      _invalidateRoster();
      return counter;
    });
  }

  Future<ServiceCounter> clearCounter(int id) {
    return _run(() async {
      final ServiceCounter counter = await _repository.clearCounter(id);
      _invalidateRoster();
      return counter;
    });
  }

  Future<void> deleteCounter(int id) {
    return _run(() async {
      await _repository.deleteCounter(id);
      _invalidateRoster();
    });
  }

  // services ---------------------------------------------------------------

  Future<Service> createService(Map<String, dynamic> body) {
    return _run(() async {
      final Service service = await _repository.createService(body);
      _invalidateServices();
      return service;
    });
  }

  Future<Service> updateService(int id, Map<String, dynamic> body) {
    return _run(() async {
      final Service service = await _repository.updateService(id, body);
      _invalidateServices();
      return service;
    });
  }

  Future<void> deleteService(int id) {
    return _run(() async {
      await _repository.deleteService(id);
      _invalidateServices();
    });
  }

  Future<void> updateServiceSettings(int id, Map<String, dynamic> body) {
    return _run(() async {
      await _repository.updateServiceSettings(id, body);
      _invalidateServices();
    });
  }

  Future<void> updateServiceHours(int id, List<Map<String, dynamic>> hours) {
    return _run(() async {
      await _repository.updateServiceHours(id, hours);
      _invalidateServices();
    });
  }

  // announcements ----------------------------------------------------------

  Future<ManagedAnnouncement> createAnnouncement({
    required String title,
    required String content,
    int? serviceId,
    String? expiresAt,
    bool publishNow = false,
  }) {
    return _run(() async {
      final ManagedAnnouncement announcement = await _repository.createAnnouncement(
        title: title,
        content: content,
        serviceId: serviceId,
        expiresAt: expiresAt,
        publishNow: publishNow,
      );
      ref.invalidate(adminAnnouncementsProvider);
      return announcement;
    });
  }

  Future<ManagedAnnouncement> updateAnnouncement(
    int id, {
    String? title,
    String? content,
    int? serviceId,
    bool clearService = false,
    String? expiresAt,
  }) {
    return _run(() async {
      final ManagedAnnouncement announcement = await _repository.updateAnnouncement(
        id,
        title: title,
        content: content,
        serviceId: serviceId,
        clearService: clearService,
        expiresAt: expiresAt,
      );
      ref.invalidate(adminAnnouncementsProvider);
      return announcement;
    });
  }

  Future<ManagedAnnouncement> publishAnnouncement(int id) {
    return _run(() async {
      final ManagedAnnouncement announcement = await _repository.publishAnnouncement(id);
      ref.invalidate(adminAnnouncementsProvider);
      return announcement;
    });
  }

  Future<ManagedAnnouncement> archiveAnnouncement(int id) {
    return _run(() async {
      final ManagedAnnouncement announcement = await _repository.archiveAnnouncement(id);
      ref.invalidate(adminAnnouncementsProvider);
      return announcement;
    });
  }

  Future<void> deleteAnnouncement(int id) {
    return _run(() async {
      await _repository.deleteAnnouncement(id);
      ref.invalidate(adminAnnouncementsProvider);
    });
  }

  // settings ---------------------------------------------------------------

  Future<List<SystemSetting>> saveSettings(Map<String, Object?> values) {
    return _run(() async {
      final List<SystemSetting> settings = await _repository.saveSettings(values);
      ref.invalidate(systemSettingsProvider);
      return settings;
    });
  }

  // ------------------------------------------------------------------------

  void _invalidateUsers() {
    ref.invalidate(adminUsersProvider);
  }

  void _invalidateRoster() {
    ref.invalidate(adminStaffProvider);
    ref.invalidate(adminCountersProvider);
    ref.invalidate(assignableStaffProvider);
  }

  void _invalidateServices() {
    ref.invalidate(adminServicesProvider);
    ref.invalidate(adminCountersProvider);
    ref.invalidate(adminQueuesProvider);
  }

  /// Runs a write, keeps the controller's own busy/error state, and always
  /// throws a [Failure] so the caller can show it verbatim.
  Future<T> _run<T>(Future<T> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      final T result = await action();
      state = const AsyncValue<void>.data(null);
      return result;
    } catch (error) {
      final Object failure = ErrorMapper.fromObject(error);
      state = AsyncValue<void>.error(failure, StackTrace.current);
      throw failure;
    }
  }
}

final AsyncNotifierProvider<AdminActionController, void> adminActionProvider =
    AsyncNotifierProvider<AdminActionController, void>(AdminActionController.new);
