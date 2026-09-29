import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/admin_dashboard.dart';
import '../models/announcement.dart';
import '../models/counter.dart';
import '../models/service.dart';
import '../models/staff_member.dart';
import '../models/system_setting.dart';
import '../models/user.dart';
import '../models/user_detail.dart';

/// Every call the administrator console makes. One method per endpoint, no
/// logic — the same shape as the other api classes.
class AdminApi {
  const AdminApi(this._client);

  final ApiClient _client;

  // ── dashboard (§31, §42) ────────────────────────────────────────────────

  Future<AdminDashboard> dashboard({String? date, int? days}) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.adminDashboard,
      query: <String, dynamic>{
        if (date != null) 'date': date,
        if (days != null) 'days': days,
      },
      parse: Parse.object,
    );
    return AdminDashboard.fromJson(response.data);
  }

  // ── users (§9, §40) ─────────────────────────────────────────────────────

  Future<Paged<User>> users({
    int page = 1,
    int limit = 20,
    String? search,
    String? role,
    String? status,
  }) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.users,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
        if (role != null) 'role': role,
        if (status != null) 'status': status,
      },
      parse: Parse.list,
    );
    final List<User> items = response.data.map(User.fromJson).toList(growable: false);
    return Paged<User>(
      items: items,
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: items.length, totalPages: 1),
    );
  }

  Future<UserDetail> user(int id) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.user(id),
      parse: Parse.object,
    );
    return UserDetail.fromJson(response.data);
  }

  Future<User> setUserStatus(int id, String status) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.userStatus(id),
      body: <String, dynamic>{'status': status},
      parse: Parse.object,
    );
    return User.fromJson(response.data);
  }

  Future<User> setUserRole(int id, String role) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.userRole(id),
      body: <String, dynamic>{'role': role},
      parse: Parse.object,
    );
    return User.fromJson(response.data);
  }

  Future<void> deleteUser(int id) =>
      _client.delete<void>(ApiEndpoints.user(id), parse: Parse.nothing);

  // ── staff roster (§55) ──────────────────────────────────────────────────

  Future<Paged<StaffMember>> staff({
    int page = 1,
    int limit = 20,
    String? search,
    int? serviceId,
    String? status,
    bool unassigned = false,
  }) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.staffRoster,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
        if (serviceId != null) 'serviceId': serviceId,
        if (status != null) 'status': status,
        if (unassigned) 'unassigned': 'true',
      },
      parse: Parse.list,
    );
    final List<StaffMember> items = response.data.map(StaffMember.fromJson).toList(growable: false);
    return Paged<StaffMember>(
      items: items,
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: items.length, totalPages: 1),
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
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.staffRoster,
      body: <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        if (serviceId != null) 'serviceId': serviceId,
        if (counterId != null) 'counterId': counterId,
      },
      parse: Parse.object,
    );
    return StaffMember.fromJson(response.data);
  }

  Future<StaffMember> updateStaff(
    int id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? status,
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.staffMember(id),
      body: <String, dynamic>{
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (phone != null) 'phone': phone,
        if (status != null) 'status': status,
      },
      parse: Parse.object,
    );
    return StaffMember.fromJson(response.data);
  }

  Future<StaffMember> assignStaff(int id, {required int counterId}) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.assignStaff(id),
      body: <String, dynamic>{'counterId': counterId},
      parse: Parse.object,
    );
    return StaffMember.fromJson(response.data);
  }

  Future<StaffMember> unassignStaff(int id) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.unassignStaff(id),
      body: const <String, dynamic>{},
      parse: Parse.object,
    );
    return StaffMember.fromJson(response.data);
  }

  // ── counters (§54) ──────────────────────────────────────────────────────

  Future<ServiceCounter> createCounter({
    required int serviceId,
    required int counterNumber,
    String? name,
    int? staffId,
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.counters,
      body: <String, dynamic>{
        'serviceId': serviceId,
        'counterNumber': counterNumber,
        if (name != null && name.isNotEmpty) 'name': name,
        if (staffId != null) 'staffId': staffId,
      },
      parse: Parse.object,
    );
    return ServiceCounter.fromJson(response.data);
  }

  Future<ServiceCounter> updateCounter(
    int id, {
    int? counterNumber,
    String? name,
    String? status,
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.counter(id),
      body: <String, dynamic>{
        if (counterNumber != null) 'counterNumber': counterNumber,
        if (name != null) 'name': name,
        if (status != null) 'status': status,
      },
      parse: Parse.object,
    );
    return ServiceCounter.fromJson(response.data);
  }

  Future<ServiceCounter> assignCounter(int id, {required int staffId}) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.counterAssignment(id),
      body: <String, dynamic>{'staffId': staffId},
      parse: Parse.object,
    );
    return ServiceCounter.fromJson(response.data);
  }

  Future<ServiceCounter> clearCounter(int id) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.delete<Map<String, dynamic>>(
      ApiEndpoints.counterAssignment(id),
      parse: Parse.object,
    );
    return ServiceCounter.fromJson(response.data);
  }

  Future<void> deleteCounter(int id) =>
      _client.delete<void>(ApiEndpoints.counter(id), parse: Parse.nothing);

  // ── services (§4 admin half) ────────────────────────────────────────────

  Future<Service> createService(Map<String, dynamic> body) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.services,
      body: body,
      parse: Parse.object,
    );
    return Service.fromJson(response.data);
  }

  Future<Service> updateService(int id, Map<String, dynamic> body) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.service(id),
      body: body,
      parse: Parse.object,
    );
    return Service.fromJson(response.data);
  }

  Future<void> deleteService(int id) =>
      _client.delete<void>(ApiEndpoints.service(id), parse: Parse.nothing);

  Future<QueueSettings> updateServiceSettings(int id, Map<String, dynamic> body) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.serviceSettings(id),
      body: body,
      parse: Parse.object,
    );
    return QueueSettings.fromJson(response.data);
  }

  Future<List<ServiceHours>> updateServiceHours(int id, List<Map<String, dynamic>> hours) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.put<List<Map<String, dynamic>>>(
      ApiEndpoints.serviceHours(id),
      body: <String, dynamic>{'hours': hours},
      parse: Parse.list,
    );
    return response.data.map(ServiceHours.fromJson).toList(growable: false);
  }

  // ── announcements (§11) ─────────────────────────────────────────────────

  Future<Paged<ManagedAnnouncement>> manageAnnouncements({
    int page = 1,
    int limit = 20,
    String? status,
    int? serviceId,
    String? search,
  }) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.manageAnnouncements,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (serviceId != null) 'serviceId': serviceId,
        if (search != null && search.isNotEmpty) 'search': search,
      },
      parse: Parse.list,
    );
    final List<ManagedAnnouncement> items =
        response.data.map(ManagedAnnouncement.fromJson).toList(growable: false);
    return Paged<ManagedAnnouncement>(
      items: items,
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: items.length, totalPages: 1),
    );
  }

  Future<ManagedAnnouncement> createAnnouncement({
    required String title,
    required String content,
    int? serviceId,
    String? expiresAt,
    String status = 'draft',
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.announcements,
      body: <String, dynamic>{
        'title': title,
        'content': content,
        'status': status,
        if (serviceId != null) 'serviceId': serviceId,
        if (expiresAt != null) 'expiresAt': expiresAt,
      },
      parse: Parse.object,
    );
    return ManagedAnnouncement.fromJson(response.data);
  }

  Future<ManagedAnnouncement> updateAnnouncement(
    int id, {
    String? title,
    String? content,
    int? serviceId,
    bool clearService = false,
    String? expiresAt,
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.announcement(id),
      body: <String, dynamic>{
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (clearService) 'serviceId': null else if (serviceId != null) 'serviceId': serviceId,
        if (expiresAt != null) 'expiresAt': expiresAt,
      },
      parse: Parse.object,
    );
    return ManagedAnnouncement.fromJson(response.data);
  }

  Future<ManagedAnnouncement> publishAnnouncement(int id) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.publishAnnouncement(id),
      parse: Parse.object,
    );
    return ManagedAnnouncement.fromJson(response.data);
  }

  Future<ManagedAnnouncement> archiveAnnouncement(int id) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.archiveAnnouncement(id),
      parse: Parse.object,
    );
    return ManagedAnnouncement.fromJson(response.data);
  }

  Future<void> deleteAnnouncement(int id) =>
      _client.delete<void>(ApiEndpoints.announcement(id), parse: Parse.nothing);

  // ── system settings (§14) ───────────────────────────────────────────────

  Future<List<SystemSetting>> settings() async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.systemSettings,
      parse: Parse.list,
    );
    return response.data.map(SystemSetting.fromJson).toList(growable: false);
  }

  /// A null value deletes the key, which is how the server models "reset to
  /// the default".
  Future<List<SystemSetting>> saveSettings(Map<String, Object?> values) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.put<List<Map<String, dynamic>>>(
      ApiEndpoints.systemSettings,
      body: values,
      parse: Parse.list,
    );
    return response.data.map(SystemSetting.fromJson).toList(growable: false);
  }
}
