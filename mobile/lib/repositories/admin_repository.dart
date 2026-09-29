import '../core/constants/enums.dart';
import '../core/network/api_response.dart';
import '../models/admin_dashboard.dart';
import '../models/announcement.dart';
import '../models/counter.dart';
import '../models/service.dart';
import '../models/staff_member.dart';
import '../models/system_setting.dart';
import '../models/user.dart';
import '../models/user_detail.dart';
import '../services/admin_api.dart';

/// The administrator console's data source.
///
/// Mostly a pass-through, like the other repositories — the rules it cares
/// about (who may be suspended, which counter is free) all live on the
/// server. What it does own is the small amount of client-side policy the UI
/// needs to decide what to *offer*: see [canManage] and [assignableRolesFor].
class AdminRepository {
  const AdminRepository(this._api);

  final AdminApi _api;

  // ── dashboard ───────────────────────────────────────────────────────────

  Future<AdminDashboard> dashboard({String? date, int? days}) =>
      _api.dashboard(date: date, days: days);

  // ── users ───────────────────────────────────────────────────────────────

  Future<Paged<User>> users({
    int page = 1,
    int limit = 20,
    String? search,
    UserRole? role,
    UserStatus? status,
  }) {
    return _api.users(
      page: page,
      limit: limit,
      search: search,
      role: role?.wire,
      status: status?.name,
    );
  }

  Future<UserDetail> user(int id) => _api.user(id);

  Future<User> setUserStatus(int id, UserStatus status) => _api.setUserStatus(id, status.name);

  Future<User> setUserRole(int id, UserRole role) => _api.setUserRole(id, role.wire);

  Future<void> deleteUser(int id) => _api.deleteUser(id);

  // ── staff roster ────────────────────────────────────────────────────────

  Future<Paged<StaffMember>> staff({
    int page = 1,
    int limit = 20,
    String? search,
    int? serviceId,
    UserStatus? status,
    bool unassigned = false,
  }) {
    return _api.staff(
      page: page,
      limit: limit,
      search: search,
      serviceId: serviceId,
      status: status?.name,
      unassigned: unassigned,
    );
  }

  Future<StaffMember> createStaff({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    int? serviceId,
    int? counterId,
  }) {
    return _api.createStaff(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      password: password,
      serviceId: serviceId,
      counterId: counterId,
    );
  }

  Future<StaffMember> updateStaff(
    int id, {
    String? firstName,
    String? lastName,
    String? phone,
    UserStatus? status,
  }) {
    return _api.updateStaff(
      id,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      status: status?.name,
    );
  }

  Future<StaffMember> assignStaff(int id, {required int counterId}) =>
      _api.assignStaff(id, counterId: counterId);

  Future<StaffMember> unassignStaff(int id) => _api.unassignStaff(id);

  // ── counters ────────────────────────────────────────────────────────────

  Future<ServiceCounter> createCounter({
    required int serviceId,
    required int counterNumber,
    String? name,
    int? staffId,
  }) {
    return _api.createCounter(
      serviceId: serviceId,
      counterNumber: counterNumber,
      name: name,
      staffId: staffId,
    );
  }

  Future<ServiceCounter> updateCounter(
    int id, {
    int? counterNumber,
    String? name,
    CounterStatus? status,
  }) {
    return _api.updateCounter(
      id,
      counterNumber: counterNumber,
      name: name,
      status: status?.wire,
    );
  }

  Future<ServiceCounter> assignCounter(int id, {required int staffId}) =>
      _api.assignCounter(id, staffId: staffId);

  Future<ServiceCounter> clearCounter(int id) => _api.clearCounter(id);

  Future<void> deleteCounter(int id) => _api.deleteCounter(id);

  // ── services ────────────────────────────────────────────────────────────

  Future<Service> createService(Map<String, dynamic> body) => _api.createService(body);

  Future<Service> updateService(int id, Map<String, dynamic> body) =>
      _api.updateService(id, body);

  Future<void> deleteService(int id) => _api.deleteService(id);

  Future<QueueSettings> updateServiceSettings(int id, Map<String, dynamic> body) =>
      _api.updateServiceSettings(id, body);

  Future<List<ServiceHours>> updateServiceHours(int id, List<Map<String, dynamic>> hours) =>
      _api.updateServiceHours(id, hours);

  // ── announcements ───────────────────────────────────────────────────────

  Future<Paged<ManagedAnnouncement>> announcements({
    int page = 1,
    int limit = 20,
    AnnouncementStatus? status,
    int? serviceId,
    String? search,
  }) {
    return _api.manageAnnouncements(
      page: page,
      limit: limit,
      status: status?.wire,
      serviceId: serviceId,
      search: search,
    );
  }

  Future<ManagedAnnouncement> createAnnouncement({
    required String title,
    required String content,
    int? serviceId,
    String? expiresAt,
    bool publishNow = false,
  }) {
    return _api.createAnnouncement(
      title: title,
      content: content,
      serviceId: serviceId,
      expiresAt: expiresAt,
      status: publishNow ? 'published' : 'draft',
    );
  }

  Future<ManagedAnnouncement> updateAnnouncement(
    int id, {
    String? title,
    String? content,
    int? serviceId,
    bool clearService = false,
    String? expiresAt,
  }) {
    return _api.updateAnnouncement(
      id,
      title: title,
      content: content,
      serviceId: serviceId,
      clearService: clearService,
      expiresAt: expiresAt,
    );
  }

  Future<ManagedAnnouncement> publishAnnouncement(int id) => _api.publishAnnouncement(id);

  Future<ManagedAnnouncement> archiveAnnouncement(int id) => _api.archiveAnnouncement(id);

  Future<void> deleteAnnouncement(int id) => _api.deleteAnnouncement(id);

  // ── system settings ─────────────────────────────────────────────────────

  Future<List<SystemSetting>> settings() => _api.settings();

  Future<List<SystemSetting>> saveSettings(Map<String, Object?> values) =>
      _api.saveSettings(values);

  // ── client-side policy ──────────────────────────────────────────────────

  /// Whether `actor` may act on `target` at all.
  ///
  /// The server enforces the same three rules and answers 403 if the client
  /// gets it wrong; this only keeps buttons off screens where they could
  /// never work:
  ///
  /// 1. nobody administers themselves through this console — use Profile;
  /// 2. an ordinary admin may not touch an admin or a super admin;
  /// 3. only a super admin may change roles or delete accounts.
  static bool canManage({required UserRole actor, required User target, required int actorId}) {
    if (target.id == actorId) return false;
    if (!actor.isAdmin) return false;
    if (actor == UserRole.superAdmin) return true;
    return !target.role.isAdmin;
  }

  /// Which roles this actor may hand out. Only a super admin sees this list
  /// at all; an admin gets nothing, matching `PATCH /users/:id/role`.
  static List<UserRole> assignableRolesFor(UserRole actor) {
    if (actor != UserRole.superAdmin) return const <UserRole>[];
    return const <UserRole>[UserRole.customer, UserRole.staff, UserRole.admin, UserRole.superAdmin];
  }
}
