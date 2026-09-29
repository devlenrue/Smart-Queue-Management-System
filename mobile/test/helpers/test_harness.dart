import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/core/export/report_exporter.dart';
import 'package:smartqueue/core/network/api_client.dart';
import 'package:smartqueue/core/network/api_response.dart';
import 'package:smartqueue/core/storage/prefs_storage.dart';
import 'package:smartqueue/core/storage/secure_storage.dart';
import 'package:smartqueue/core/theme/app_theme.dart';
import 'package:smartqueue/models/admin_dashboard.dart';
import 'package:smartqueue/models/announcement.dart';
import 'package:smartqueue/models/counter.dart';
import 'package:smartqueue/models/notification.dart';
import 'package:smartqueue/models/queue.dart';
import 'package:smartqueue/models/report.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/models/staff_dashboard.dart';
import 'package:smartqueue/models/staff_member.dart';
import 'package:smartqueue/models/staff_statistics.dart';
import 'package:smartqueue/models/ticket.dart';
import 'package:smartqueue/models/system_setting.dart';
import 'package:smartqueue/models/user.dart';
import 'package:smartqueue/models/user_detail.dart';
import 'package:smartqueue/providers/infrastructure_providers.dart';
import 'package:smartqueue/repositories/admin_repository.dart';
import 'package:smartqueue/repositories/auth_repository.dart';
import 'package:smartqueue/repositories/notification_repository.dart';
import 'package:smartqueue/repositories/queue_repository.dart';
import 'package:smartqueue/repositories/report_repository.dart';
import 'package:smartqueue/repositories/service_repository.dart';
import 'package:smartqueue/repositories/staff_repository.dart';
import 'package:smartqueue/repositories/ticket_repository.dart';
import 'package:smartqueue/services/admin_api.dart';
import 'package:smartqueue/services/auth_api.dart';
import 'package:smartqueue/services/notification_api.dart';
import 'package:smartqueue/services/queue_api.dart';
import 'package:smartqueue/services/report_api.dart';
import 'package:smartqueue/services/service_api.dart';
import 'package:smartqueue/services/staff_api.dart';
import 'package:smartqueue/services/ticket_api.dart';

/// Test doubles for the repository layer.
///
/// The fakes extend the real repositories and override every method, so the
/// Dio instance handed to `super` is never touched — no HTTP, no platform
/// channels, and the widgets under test see exactly the API they see in
/// production.

ApiClient _idleClient() => ApiClient(Dio());

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository()
      : super(api: AuthApi(_idleClient()), storage: InMemorySecureStorage());

  User? sessionUser;
  Failure? loginFailure;
  Failure? registerFailure;
  int loginCalls = 0;
  int registerCalls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<User?> restoreSession() async => sessionUser;

  @override
  Future<User> login({required String email, required String password}) async {
    loginCalls++;
    lastEmail = email;
    lastPassword = password;
    if (loginFailure != null) throw loginFailure!;
    sessionUser = sampleUser(email: email);
    return sessionUser!;
  }

  @override
  Future<User> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
  }) async {
    registerCalls++;
    lastEmail = email;
    if (registerFailure != null) throw registerFailure!;
    sessionUser = sampleUser(email: email, firstName: firstName, lastName: lastName);
    return sessionUser!;
  }

  @override
  Future<void> logout() async => sessionUser = null;

  @override
  Future<User> updateProfile({String? firstName, String? lastName, String? phone}) async {
    sessionUser = (sessionUser ?? sampleUser()).copyWith(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
    );
    return sessionUser!;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {}
}

class FakeServiceRepository extends ServiceRepository {
  FakeServiceRepository() : super(ServiceApi(_idleClient()));

  List<Service> services = <Service>[];
  List<String> categoryList = const <String>['Finance', 'Records'];
  Object? failure;
  String? lastSearch;
  String? lastStatus;
  int listCalls = 0;

  @override
  Future<Paged<Service>> list({
    int page = 1,
    int limit = 20,
    String? search,
    String? category,
    String? status,
  }) async {
    listCalls++;
    lastSearch = search;
    lastStatus = status;
    if (failure != null) throw failure!;

    final List<Service> filtered = services.where((Service s) {
      final bool matchesSearch = search == null ||
          search.isEmpty ||
          s.name.toLowerCase().contains(search.toLowerCase());
      final bool matchesCategory = category == null || s.category == category;
      final bool matchesStatus = status == null || s.status.name == status;
      return matchesSearch && matchesCategory && matchesStatus;
    }).toList(growable: false);

    return Paged<Service>(
      items: filtered,
      meta: PageMeta(page: page, limit: limit, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<Service> byId(int id) async {
    if (failure != null) throw failure!;
    return services.firstWhere((Service s) => s.id == id, orElse: sampleService);
  }

  @override
  Future<List<ServiceHours>> hours(int serviceId) async => const <ServiceHours>[];

  @override
  Future<List<String>> categories({bool refresh = false}) async => categoryList;
}

class FakeTicketRepository extends TicketRepository {
  FakeTicketRepository() : super(TicketApi(_idleClient()));

  List<Ticket> tickets = <Ticket>[];
  List<Ticket> activeTickets = <Ticket>[];

  /// Not named `events`: that is the name of the method it feeds, and a
  /// field cannot share a name with an inherited method.
  List<TicketEvent> eventList = <TicketEvent>[];

  /// Scripted position readings, returned one per poll, so a test can watch
  /// the queue move. Once the script runs out the ticket is reported
  /// completed — that ends the polling loop, which is what stops a widget
  /// test from finishing with a timer still pending.
  List<TicketPosition> positions = <TicketPosition>[];
  int positionCalls = 0;

  Object? failure;
  Object? cancelFailure;
  int cancelCalls = 0;
  int? cancelledId;

  @override
  Future<Paged<Ticket>> history({
    int page = 1,
    int limit = 20,
    String? status,
    int? serviceId,
  }) async {
    if (failure != null) throw failure!;
    final List<Ticket> filtered = status == null
        ? tickets
        : tickets.where((Ticket t) => t.status.wire == status).toList(growable: false);
    return Paged<Ticket>(
      items: filtered,
      meta: PageMeta(page: page, limit: limit, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<List<Ticket>> active() async {
    if (failure != null) throw failure!;
    return activeTickets;
  }

  @override
  Future<Ticket?> currentTicket() async =>
      activeTickets.isEmpty ? null : activeTickets.first;

  @override
  Future<Ticket> byId(int id) async {
    if (failure != null) throw failure!;
    return tickets.firstWhere(
      (Ticket t) => t.id == id,
      orElse: () => activeTickets.firstWhere((Ticket t) => t.id == id, orElse: sampleTicket),
    );
  }

  @override
  Future<TicketPosition> position(int id) async {
    if (positionCalls >= positions.length) {
      positionCalls++;
      return samplePosition(status: TicketStatus.completed, position: null);
    }
    return positions[positionCalls++];
  }

  @override
  Future<List<TicketEvent>> events(int id) async => eventList;

  @override
  Future<Ticket> cancel(int id, {String? reason}) async {
    cancelCalls++;
    cancelledId = id;
    if (cancelFailure != null) throw cancelFailure!;
    return sampleTicket(id: id, status: TicketStatus.cancelled);
  }
}

class FakeQueueRepository extends QueueRepository {
  FakeQueueRepository() : super(QueueApi(_idleClient()));

  Object? joinFailure;
  int joinCalls = 0;
  int? joinedServiceId;
  Ticket joinedTicket = sampleTicket();

  /// What the admin queue monitor reads: one row per live queue.
  List<QueueStatusView> queueList = <QueueStatusView>[sampleQueueStatus()];

  @override
  Future<List<QueueStatusView>> list({String? date, int? serviceId, String? status}) async =>
      serviceId == null
          ? queueList
          : queueList
              .where((QueueStatusView q) => q.serviceId == serviceId)
              .toList(growable: false);

  @override
  Future<QueueStatusView> status(int queueId) async => sampleQueueStatus();

  @override
  Future<QueueStatusView> forService(int serviceId) async => sampleQueueStatus();

  /// The staff board. `waiting` is what the current-queue screen renders.
  List<Ticket> monitorWaiting = <Ticket>[];
  List<ServiceCounter> monitorCounters = <ServiceCounter>[sampleServiceCounter()];
  Object? monitorFailure;
  int monitorCalls = 0;

  @override
  Future<QueueMonitor> monitor(int queueId) async {
    monitorCalls++;
    if (monitorFailure != null) throw monitorFailure!;
    return QueueMonitor(
      serviceId: 1,
      serviceName: 'Finance Office',
      serviceCode: 'FIN',
      queue: sampleQueueStatus(),
      counters: monitorCounters,
      serving: const <Ticket>[],
      waiting: monitorWaiting,
      nowServing: 'FIN-009',
    );
  }

  @override
  Future<JoinResult> join(int serviceId) async {
    joinCalls++;
    joinedServiceId = serviceId;
    if (joinFailure != null) throw joinFailure!;
    return JoinResult(ticket: joinedTicket, position: samplePosition());
  }
}

class FakeNotificationRepository extends NotificationRepository {
  FakeNotificationRepository() : super(NotificationApi(_idleClient()));

  List<AppNotification> notifications = <AppNotification>[];
  List<Announcement> announcementList = <Announcement>[];
  int unread = 0;
  int markReadCalls = 0;
  int markAllCalls = 0;

  @override
  Future<NotificationPage> list({
    int page = 1,
    int limit = 20,
    bool? isRead,
    String? type,
  }) async {
    return NotificationPage(
      items: notifications,
      meta: PageMeta(page: page, limit: limit, total: notifications.length, totalPages: 1),
      unreadCount: unread,
    );
  }

  @override
  Future<int> unreadCount() async => unread;

  @override
  Future<void> markRead(int id) async => markReadCalls++;

  @override
  Future<int> markAllRead() async {
    markAllCalls++;
    return notifications.length;
  }

  @override
  Future<Paged<Announcement>> announcements({
    int page = 1,
    int limit = 20,
    int? serviceId,
  }) async {
    return Paged<Announcement>(
      items: announcementList,
      meta: PageMeta(page: page, limit: limit, total: announcementList.length, totalPages: 1),
    );
  }

  @override
  Future<Announcement> announcement(int id) async => announcementList.first;
}

class FakeStaffRepository extends StaffRepository {
  FakeStaffRepository() : super(StaffApi(_idleClient()));

  StaffDashboard dashboardValue = sampleStaffDashboard();
  StaffStatistics statisticsValue = sampleStaffStatistics();
  List<Ticket> handled = <Ticket>[];
  List<ServiceCounter> counterList = <ServiceCounter>[sampleServiceCounter()];

  Object? dashboardFailure;
  Object? actionFailure;

  int dashboardCalls = 0;
  int callNextCalls = 0;
  int? lastCalledTicketId;
  final List<String> actions = <String>[];

  @override
  Future<StaffDashboard> dashboard({int? serviceId, int? counterId}) async {
    dashboardCalls++;
    if (dashboardFailure != null) throw dashboardFailure!;
    return dashboardValue;
  }

  @override
  Future<StaffStatistics> statistics({String? from, String? to}) async => statisticsValue;

  @override
  Future<Paged<Ticket>> handledTickets({
    int page = 1,
    int limit = 20,
    String? status,
    String? from,
    String? to,
  }) async {
    final List<Ticket> filtered = status == null
        ? handled
        : handled.where((Ticket t) => t.status.wire == status).toList(growable: false);
    return Paged<Ticket>(
      items: filtered,
      meta: PageMeta(page: page, limit: limit, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<List<ServiceCounter>> counters({int? serviceId, String? status}) async => counterList;

  @override
  Future<StaffCounter> setCounterStatus(int counterId, CounterStatus status) async {
    actions.add('counter:${status.wire}');
    if (actionFailure != null) throw actionFailure!;
    return sampleStaffCounter(status: status);
  }

  @override
  Future<TicketActionResult> callNext({required int serviceId, int? counterId}) async {
    callNextCalls++;
    actions.add('callNext');
    if (actionFailure != null) throw actionFailure!;
    return sampleActionResult(status: TicketStatus.called);
  }

  @override
  Future<TicketActionResult> call(int ticketId, {int? counterId}) async {
    lastCalledTicketId = ticketId;
    actions.add('call');
    if (actionFailure != null) throw actionFailure!;
    return sampleActionResult(id: ticketId, status: TicketStatus.called);
  }

  @override
  Future<TicketActionResult> recall(int ticketId) async => _act('recall', ticketId, TicketStatus.called);

  @override
  Future<TicketActionResult> start(int ticketId) async => _act('start', ticketId, TicketStatus.serving);

  @override
  Future<TicketActionResult> complete(int ticketId) async =>
      _act('complete', ticketId, TicketStatus.completed);

  @override
  Future<TicketActionResult> skip(int ticketId, {String? reason}) async =>
      _act('skip', ticketId, TicketStatus.skipped);

  @override
  Future<TicketActionResult> noShow(int ticketId) async =>
      _act('noShow', ticketId, TicketStatus.noShow);

  TicketActionResult _act(String name, int ticketId, TicketStatus status) {
    actions.add(name);
    if (actionFailure != null) throw actionFailure!;
    return sampleActionResult(id: ticketId, status: status);
  }
}

/// Everything a widget test needs, created together so no test forgets one
/// and falls through to a real platform channel.
/// The administrator console's data source.
///
/// Records what it was asked for — the filters, the ids, the order of the
/// writes — so a test can assert that a screen sent the right request
/// rather than only that it rendered the answer.
class FakeAdminRepository extends AdminRepository {
  FakeAdminRepository() : super(AdminApi(_idleClient()));

  AdminDashboard dashboardValue = sampleAdminDashboard();
  List<User> userList = <User>[];
  UserDetail? userDetailValue;
  List<StaffMember> staffList = <StaffMember>[];
  List<ManagedAnnouncement> announcementList = <ManagedAnnouncement>[];
  List<SystemSetting> settingsList = <SystemSetting>[];

  Object? dashboardFailure;
  Object? actionFailure;

  int dashboardCalls = 0;
  int userCalls = 0;
  int staffCalls = 0;
  String? lastUserSearch;
  UserRole? lastUserRole;
  UserStatus? lastUserStatus;
  String? lastStaffSearch;
  bool? lastUnassignedOnly;
  final List<String> writes = <String>[];

  @override
  Future<AdminDashboard> dashboard({String? date, int? days}) async {
    dashboardCalls++;
    if (dashboardFailure != null) throw dashboardFailure!;
    return dashboardValue;
  }

  @override
  Future<Paged<User>> users({
    int page = 1,
    int limit = 20,
    String? search,
    UserRole? role,
    UserStatus? status,
  }) async {
    userCalls++;
    lastUserSearch = search;
    lastUserRole = role;
    lastUserStatus = status;

    final List<User> filtered = userList.where((User user) {
      final bool matchesText = search == null ||
          search.isEmpty ||
          user.fullName.toLowerCase().contains(search.toLowerCase());
      return matchesText && (role == null || user.role == role) &&
          (status == null || user.status == status);
    }).toList(growable: false);

    return Paged<User>(
      items: filtered,
      meta: PageMeta(page: page, limit: limit, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<UserDetail> user(int id) async {
    if (userDetailValue != null) return userDetailValue!;
    return sampleUserDetail(user: userList.firstWhere((User u) => u.id == id, orElse: sampleUser));
  }

  @override
  Future<User> setUserStatus(int id, UserStatus status) async {
    writes.add('user:$id:status:${status.name}');
    if (actionFailure != null) throw actionFailure!;
    return sampleUser(id: id);
  }

  @override
  Future<User> setUserRole(int id, UserRole role) async {
    writes.add('user:$id:role:${role.wire}');
    if (actionFailure != null) throw actionFailure!;
    return sampleUser(id: id, role: role);
  }

  @override
  Future<void> deleteUser(int id) async {
    writes.add('user:$id:delete');
    if (actionFailure != null) throw actionFailure!;
  }

  @override
  Future<Paged<StaffMember>> staff({
    int page = 1,
    int limit = 20,
    String? search,
    int? serviceId,
    UserStatus? status,
    bool unassigned = false,
  }) async {
    staffCalls++;
    lastStaffSearch = search;
    lastUnassignedOnly = unassigned;

    final List<StaffMember> filtered = staffList.where((StaffMember member) {
      final bool matchesText = search == null ||
          search.isEmpty ||
          member.fullName.toLowerCase().contains(search.toLowerCase());
      final bool matchesPosting = !unassigned || !member.isPosted;
      return matchesText && matchesPosting && (status == null || member.status == status);
    }).toList(growable: false);

    return Paged<StaffMember>(
      items: filtered,
      meta: PageMeta(page: page, limit: limit, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<StaffMember> createStaff({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    int? serviceId,
    int? counterId,
  }) async {
    writes.add('staff:create:$email:${counterId ?? '-'}');
    if (actionFailure != null) throw actionFailure!;
    return sampleStaffMember(id: 99, firstName: firstName, lastName: lastName, email: email);
  }

  @override
  Future<StaffMember> updateStaff(
    int id, {
    String? firstName,
    String? lastName,
    String? phone,
    UserStatus? status,
  }) async {
    writes.add('staff:$id:update');
    if (actionFailure != null) throw actionFailure!;
    return sampleStaffMember(id: id);
  }

  @override
  Future<StaffMember> assignStaff(int id, {required int counterId}) async {
    writes.add('staff:$id:assign:$counterId');
    if (actionFailure != null) throw actionFailure!;
    return sampleStaffMember(id: id);
  }

  @override
  Future<StaffMember> unassignStaff(int id) async {
    writes.add('staff:$id:unassign');
    if (actionFailure != null) throw actionFailure!;
    return sampleStaffMember(id: id, posted: false);
  }

  @override
  Future<ServiceCounter> createCounter({
    required int serviceId,
    required int counterNumber,
    String? name,
    int? staffId,
  }) async {
    writes.add('counter:create:$serviceId:$counterNumber');
    if (actionFailure != null) throw actionFailure!;
    return sampleServiceCounter(id: 90, counterNumber: counterNumber);
  }

  @override
  Future<ServiceCounter> updateCounter(
    int id, {
    int? counterNumber,
    String? name,
    CounterStatus? status,
  }) async {
    writes.add('counter:$id:update');
    if (actionFailure != null) throw actionFailure!;
    return sampleServiceCounter(id: id);
  }

  @override
  Future<ServiceCounter> assignCounter(int id, {required int staffId}) async {
    writes.add('counter:$id:assign:$staffId');
    if (actionFailure != null) throw actionFailure!;
    return sampleServiceCounter(id: id);
  }

  @override
  Future<ServiceCounter> clearCounter(int id) async {
    writes.add('counter:$id:clear');
    if (actionFailure != null) throw actionFailure!;
    return sampleServiceCounter(id: id, staffId: null, staffName: null);
  }

  @override
  Future<void> deleteCounter(int id) async {
    writes.add('counter:$id:delete');
    if (actionFailure != null) throw actionFailure!;
  }

  @override
  Future<Service> createService(Map<String, dynamic> body) async {
    writes.add('service:create:${body['code']}');
    if (actionFailure != null) throw actionFailure!;
    return sampleService();
  }

  @override
  Future<Service> updateService(int id, Map<String, dynamic> body) async {
    writes.add('service:$id:update');
    if (actionFailure != null) throw actionFailure!;
    return sampleService(id: id);
  }

  @override
  Future<void> deleteService(int id) async {
    writes.add('service:$id:delete');
    if (actionFailure != null) throw actionFailure!;
  }

  @override
  Future<QueueSettings> updateServiceSettings(int id, Map<String, dynamic> body) async {
    writes.add('service:$id:settings');
    if (actionFailure != null) throw actionFailure!;
    return const QueueSettings(
      maxQueueSize: 100,
      allowCancellation: true,
      allowRejoin: true,
      notificationThreshold: 3,
      estimatedServiceTime: 5,
    );
  }

  @override
  Future<List<ServiceHours>> updateServiceHours(
    int id,
    List<Map<String, dynamic>> hours,
  ) async {
    writes.add('service:$id:hours:${hours.length}');
    if (actionFailure != null) throw actionFailure!;
    return const <ServiceHours>[];
  }

  @override
  Future<Paged<ManagedAnnouncement>> announcements({
    int page = 1,
    int limit = 20,
    AnnouncementStatus? status,
    int? serviceId,
    String? search,
  }) async {
    final List<ManagedAnnouncement> filtered = status == null
        ? announcementList
        : announcementList
            .where((ManagedAnnouncement a) => a.status == status)
            .toList(growable: false);
    return Paged<ManagedAnnouncement>(
      items: filtered,
      meta: PageMeta(page: page, limit: limit, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<ManagedAnnouncement> createAnnouncement({
    required String title,
    required String content,
    int? serviceId,
    String? expiresAt,
    bool publishNow = false,
  }) async {
    writes.add('announcement:create:${publishNow ? 'published' : 'draft'}');
    if (actionFailure != null) throw actionFailure!;
    return sampleManagedAnnouncement(
      title: title,
      status: publishNow ? AnnouncementStatus.published : AnnouncementStatus.draft,
    );
  }

  @override
  Future<ManagedAnnouncement> updateAnnouncement(
    int id, {
    String? title,
    String? content,
    int? serviceId,
    bool clearService = false,
    String? expiresAt,
  }) async {
    writes.add('announcement:$id:update');
    if (actionFailure != null) throw actionFailure!;
    return sampleManagedAnnouncement(id: id, title: title ?? 'Notice');
  }

  @override
  Future<ManagedAnnouncement> publishAnnouncement(int id) async {
    writes.add('announcement:$id:publish');
    if (actionFailure != null) throw actionFailure!;
    return sampleManagedAnnouncement(id: id, status: AnnouncementStatus.published);
  }

  @override
  Future<ManagedAnnouncement> archiveAnnouncement(int id) async {
    writes.add('announcement:$id:archive');
    if (actionFailure != null) throw actionFailure!;
    return sampleManagedAnnouncement(id: id, status: AnnouncementStatus.archived);
  }

  @override
  Future<void> deleteAnnouncement(int id) async {
    writes.add('announcement:$id:delete');
    if (actionFailure != null) throw actionFailure!;
  }

  @override
  Future<List<SystemSetting>> settings() async => settingsList;

  @override
  Future<List<SystemSetting>> saveSettings(Map<String, Object?> values) async {
    writes.add('settings:${values.keys.join(',')}');
    if (actionFailure != null) throw actionFailure!;
    return settingsList;
  }
}

class FakeReportRepository extends ReportRepository {
  FakeReportRepository() : super(ReportApi(_idleClient()));

  DailyReport dailyValue = sampleDailyReport();
  ServicesReport servicesValue = sampleServicesReport();
  StaffReport staffValue = sampleStaffReport();
  QueuesReport queuesValue = sampleQueuesReport();

  /// What the server would have sent for `?format=csv`.
  String csvValue = 'Date,Service,Code,Issued\r\n2026-09-29,Finance Office,FIN,4\r\n';

  Object? failure;
  Object? csvFailure;

  int dailyCalls = 0;
  int servicesCalls = 0;
  int staffCalls = 0;
  int queuesCalls = 0;
  int csvCalls = 0;

  String? lastFrom;
  String? lastTo;
  int? lastServiceId;
  int? lastStaffId;
  ReportKind? lastCsvKind;

  void _record(String? from, String? to, int? serviceId, int? staffId) {
    lastFrom = from;
    lastTo = to;
    lastServiceId = serviceId;
    lastStaffId = staffId;
  }

  @override
  Future<DailyReport> daily({String? from, String? to, int? serviceId}) async {
    dailyCalls++;
    _record(from, to, serviceId, null);
    if (failure != null) throw failure!;
    return dailyValue;
  }

  @override
  Future<ServicesReport> services({String? from, String? to, int? serviceId}) async {
    servicesCalls++;
    _record(from, to, serviceId, null);
    if (failure != null) throw failure!;
    return servicesValue;
  }

  @override
  Future<StaffReport> staff({String? from, String? to, int? serviceId, int? staffId}) async {
    staffCalls++;
    _record(from, to, serviceId, staffId);
    if (failure != null) throw failure!;
    return staffValue;
  }

  @override
  Future<QueuesReport> queues({String? from, String? to, int? serviceId}) async {
    queuesCalls++;
    _record(from, to, serviceId, null);
    if (failure != null) throw failure!;
    return queuesValue;
  }

  @override
  Future<String> csv(
    ReportKind kind, {
    String? from,
    String? to,
    int? serviceId,
    int? staffId,
  }) async {
    csvCalls++;
    lastCsvKind = kind;
    _record(from, to, serviceId, staffId);
    if (csvFailure != null) throw csvFailure!;
    return csvValue;
  }
}

/// Keeps an exported report in memory instead of writing to a documents
/// directory that a widget test has no platform channel to reach.
class FakeReportExporter implements ReportExporter {
  String directory = '/storage/smartqueue-reports';
  String? lastFilename;
  String? lastContents;
  Object? failure;
  int saveCalls = 0;

  @override
  Future<String> save(String filename, String contents) async {
    saveCalls++;
    lastFilename = filename;
    lastContents = contents;
    if (failure != null) throw failure!;
    return '$directory/$filename';
  }
}

class TestHarness {
  TestHarness({required this.prefs});

  final PrefsStorage prefs;

  final FakeAuthRepository auth = FakeAuthRepository();
  final FakeServiceRepository services = FakeServiceRepository();
  final FakeTicketRepository tickets = FakeTicketRepository();
  final FakeQueueRepository queues = FakeQueueRepository();
  final FakeNotificationRepository notifications = FakeNotificationRepository();
  final FakeStaffRepository staff = FakeStaffRepository();
  final FakeAdminRepository admin = FakeAdminRepository();
  final FakeReportRepository reports = FakeReportRepository();
  final FakeReportExporter exporter = FakeReportExporter();

  /// Puts somebody in the session, so screens behind the auth guard build.
  void signIn({
    UserRole role = UserRole.customer,
    String firstName = 'Jane',
    int id = 7,
  }) {
    auth.sessionUser = sampleUser(
      id: id,
      firstName: firstName,
      lastName: 'Wanjiku',
      email: 'jane.staff@smartqueue.test',
      role: role,
    );
  }

  static Future<TestHarness> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return TestHarness(prefs: await PrefsStorage.create());
  }

  List<Override> get overrides => <Override>[
        prefsStorageProvider.overrideWithValue(prefs),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        authRepositoryProvider.overrideWithValue(auth),
        serviceRepositoryProvider.overrideWithValue(services),
        ticketRepositoryProvider.overrideWithValue(tickets),
        queueRepositoryProvider.overrideWithValue(queues),
        notificationRepositoryProvider.overrideWithValue(notifications),
        staffRepositoryProvider.overrideWithValue(staff),
        adminRepositoryProvider.overrideWithValue(admin),
        reportRepositoryProvider.overrideWithValue(reports),
        reportExporterProvider.overrideWithValue(exporter),
      ];

  /// Wraps a screen in the minimum real app scaffolding: a ProviderScope
  /// with the fakes, and a MaterialApp carrying the production theme (so
  /// `StatusPalette` resolves exactly as it does at runtime).
  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: child,
      ),
    );
  }
}

extension PumpX on WidgetTester {
  /// Pumps a screen on a tall phone-sized surface.
  ///
  /// The default 800×600 test window is shorter than a real phone, which
  /// pushes buttons at the bottom of a form out of the viewport and makes
  /// `tap()` miss. Sizing the surface like an actual device keeps the tests
  /// about behaviour rather than about scrolling.
  Future<void> pumpScreen(
    TestHarness harness,
    Widget child, {
    Size size = const Size(420, 1600),
  }) async {
    view.physicalSize = size;
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await pumpWidget(harness.wrap(child));
    await pump();
  }

  /// Takes the screen down and pumps past one poll interval.
  ///
  /// A poll loop that has no terminal state — the staff console keeps
  /// refreshing all day — sleeps on a `PollClock`, which the provider
  /// cancels the moment it is disposed. Replacing the tree therefore ends
  /// the loop on its own; this helper makes that teardown explicit and,
  /// by pumping a whole interval afterwards, fails right here rather than
  /// in the framework's end-of-test check if a loop ever leaks again.
  ///
  /// [interval] overrides the wait for a screen that polls on a multiple of
  /// the configured rate — the admin dashboard re-reads every third tick.
  Future<void> unmountAndDrain(TestHarness harness, {Duration? interval}) async {
    await pumpWidget(const SizedBox.shrink());
    await pump(interval ?? harness.prefs.readPollInterval());
    await pump();
  }

  /// Runs the polling loop forward until it stops on its own.
  ///
  /// `pumpAndSettle` only waits for frames, and a poll interval is a bare
  /// timer, so a screen that polls has to be wound on deliberately. Once
  /// the fake reports a completed ticket the loop returns and no timer is
  /// left pending when the test ends.
  Future<void> settlePolling(TestHarness harness, {int maxPolls = 8}) async {
    final Duration interval = harness.prefs.readPollInterval();
    for (int i = 0; i < maxPolls; i++) {
      await pump(interval);
      await pump();
    }
    await pumpAndSettle();
  }
}

// ── sample data ───────────────────────────────────────────────────────────

User sampleUser({
  int id = 1,
  String firstName = 'John',
  String lastName = 'Doe',
  String email = 'john.doe@smartqueue.test',
  UserRole role = UserRole.customer,
}) {
  return User(
    id: id,
    firstName: firstName,
    lastName: lastName,
    email: email,
    phone: '+254700000001',
    role: role,
    status: UserStatus.active,
    createdAt: '2026-01-15T08:00:00.000Z',
  );
}

Service sampleService({
  int id = 1,
  String name = 'Finance Office',
  String code = 'FIN',
  ServiceStatus status = ServiceStatus.open,
  int waiting = 4,
  int estimatedWait = 12,
  bool accepting = true,
  String? category = 'Finance',
  String? nowServing = 'FIN-007',
}) {
  return Service(
    id: id,
    name: name,
    code: code,
    status: status,
    averageServiceTime: 5,
    dailyCapacity: 100,
    description: 'Fee payments, statements and refunds.',
    category: category,
    hoursToday: const TodayHours(opensAt: '08:00', closesAt: '17:00', isOpenNow: true),
    queue: QueueSummary(
      queueId: 100 + id,
      status: QueueStatus.waiting,
      waitingCount: waiting,
      servingCount: 1,
      completedToday: 9,
      estimatedWaitMinutes: estimatedWait,
      activeCounters: 3,
      isAcceptingTickets: accepting,
      capacityRemaining: 80,
      nowServing: nowServing,
    ),
  );
}

Ticket sampleTicket({
  int id = 55,
  String ticketNumber = 'FIN-012',
  TicketStatus status = TicketStatus.waiting,
  int queueId = 101,
  int waitedMinutes = 6,
  CounterSummary? counter,
  CustomerSummary? customer,
}) {
  return Ticket(
    id: id,
    ticketNumber: ticketNumber,
    sequenceNumber: 12,
    status: status,
    queueId: queueId,
    serviceId: 1,
    serviceName: 'Finance Office',
    serviceCode: 'FIN',
    queueDate: '2026-09-29',
    waitedMinutes: waitedMinutes,
    counter: counter,
    customer: customer,
    joinedAt: '2026-09-29T08:15:00.000Z',
  );
}

/// The customer block the staff reads carry and the customer reads do not.
CustomerSummary sampleCustomer({
  int id = 24,
  String fullName = 'Alice Kamau',
  String phone = '+254700111222',
}) {
  return CustomerSummary(
    id: id,
    fullName: fullName,
    phone: phone,
    email: 'alice@smartqueue.test',
  );
}

TicketPosition samplePosition({
  int ticketId = 55,
  String ticketNumber = 'FIN-012',
  TicketStatus status = TicketStatus.waiting,
  int? position = 3,
  int peopleAhead = 2,
  int estimatedWaitMinutes = 10,
  String? nowServing = 'FIN-009',
  CounterSummary? counter,
}) {
  return TicketPosition(
    ticketId: ticketId,
    ticketNumber: ticketNumber,
    status: status,
    position: position,
    peopleAhead: peopleAhead,
    estimatedWaitMinutes: estimatedWaitMinutes,
    activeCounters: 3,
    queueStatus: QueueStatus.waiting,
    nowServing: nowServing,
    counter: counter,
  );
}

QueueStatusView sampleQueueStatus({int waitingCount = 4, String? nowServing = 'FIN-009'}) {
  return QueueStatusView(
    queueId: 101,
    serviceId: 1,
    serviceName: 'Finance Office',
    serviceCode: 'FIN',
    queueDate: '2026-09-29',
    status: QueueStatus.waiting,
    currentNumber: 9,
    waitingCount: waitingCount,
    servingCount: 1,
    completedToday: 9,
    cancelledToday: 1,
    skippedToday: 0,
    noShowToday: 0,
    ticketsIssuedToday: 15,
    activeCounters: 3,
    averageWaitMinutes: 11,
    averageServiceMinutes: 5,
    estimatedWaitMinutes: 10,
    isAcceptingTickets: true,
    capacityRemaining: 85,
    nowServing: nowServing,
  );
}

ServiceCounter sampleServiceCounter({
  int id = 2,
  int counterNumber = 2,
  String name = 'Finance Counter 2',
  CounterStatus status = CounterStatus.available,
  String? staffName = 'Jane Wanjiku',
  int? staffId = 7,
  String? currentTicket,
}) {
  return ServiceCounter(
    id: id,
    serviceId: 1,
    counterNumber: counterNumber,
    name: name,
    status: status,
    staffName: staffName,
    staffId: staffId,
    currentTicket: currentTicket,
  );
}

StaffCounter sampleStaffCounter({
  int id = 2,
  int counterNumber = 2,
  String name = 'Finance Counter 2',
  CounterStatus status = CounterStatus.available,
}) {
  return StaffCounter(
    id: id,
    serviceId: 1,
    counterNumber: counterNumber,
    name: name,
    status: status,
    assignedStaffId: 7,
  );
}

StaffDashboard sampleStaffDashboard({
  bool assigned = true,
  Ticket? currentTicket,
  List<Ticket>? upNext,
  CounterStatus counterStatus = CounterStatus.available,
  int waiting = 4,
  int servedToday = 6,
  int skippedToday = 1,
  int noShowToday = 0,
  bool withCounter = true,
}) {
  return StaffDashboard(
    today: '2026-09-29',
    assigned: assigned,
    assignment: assigned
        ? const StaffAssignment(
            id: 1,
            serviceId: 1,
            serviceName: 'Finance Office',
            serviceCode: 'FIN',
            counterId: 2,
            counterNumber: 2,
            counterName: 'Finance Counter 2',
            assignedAt: '2026-09-01T08:00:00.000Z',
          )
        : null,
    service: assigned
        ? const StaffServiceRef(
            id: 1,
            name: 'Finance Office',
            code: 'FIN',
            status: ServiceStatus.open,
          )
        : null,
    counter: assigned && withCounter ? sampleStaffCounter(status: counterStatus) : null,
    queue: assigned ? sampleQueueStatus(waitingCount: waiting) : null,
    currentTicket: currentTicket,
    upNext: upNext ?? const <Ticket>[],
    stats: StaffDashboardStats(
      waiting: waiting,
      servedToday: servedToday,
      skippedToday: skippedToday,
      noShowToday: noShowToday,
      cancelledToday: 0,
      averageServiceMinutes: 5,
      averageWaitMinutes: 12,
    ),
  );
}

StaffStatistics sampleStaffStatistics({
  int served = 12,
  int skipped = 2,
  int noShow = 1,
  List<StaffDayStat>? byDay,
}) {
  return StaffStatistics(
    staff: const StaffProfileRef(
      id: 7,
      name: 'Jane Wanjiku',
      email: 'jane.staff@smartqueue.test',
      role: UserRole.staff,
    ),
    from: '2026-09-23',
    to: '2026-09-29',
    ticketsServed: served,
    ticketsSkipped: skipped,
    ticketsNoShow: noShow,
    ticketsRecalled: 3,
    ticketsHandled: served + skipped + noShow,
    completionRate: served + skipped + noShow == 0
        ? 0
        : ((served / (served + skipped + noShow)) * 100).round(),
    averageServiceMinutes: 5.4,
    averageWaitMinutes: 12.1,
    byDay: byDay ??
        const <StaffDayStat>[
          StaffDayStat(date: '2026-09-28', served: 5, averageServiceMinutes: 5.2),
          StaffDayStat(date: '2026-09-29', served: 7, averageServiceMinutes: 5.6),
        ],
  );
}

TicketActionResult sampleActionResult({
  int id = 55,
  String ticketNumber = 'FIN-012',
  TicketStatus status = TicketStatus.called,
}) {
  return TicketActionResult(
    ticket: sampleTicket(id: id, ticketNumber: ticketNumber, status: status),
    waitingCount: 3,
    completedToday: 10,
    nowServing: ticketNumber,
  );
}

// ── admin sample data (Phase 7) ───────────────────────────────────────────

AdminDashboard sampleAdminDashboard({
  int waiting = 34,
  int served = 23,
  int staffOnDuty = 5,
  List<AdminServiceRow>? byService,
  List<ServedPoint>? servedPerDay,
  StatusBreakdown? breakdown,
}) {
  return AdminDashboard(
    today: '2026-09-29',
    activeServices: 5,
    activeQueues: 5,
    activeCounters: 5,
    staffOnDuty: staffOnDuty,
    customersWaiting: waiting,
    customersServedToday: served,
    averageWaitMinutes: 15.8,
    averageServiceMinutes: 8.9,
    ticketsIssuedToday: 65,
    cancelledToday: 2,
    skippedToday: 0,
    noShowToday: 1,
    byService: byService ??
        const <AdminServiceRow>[
          AdminServiceRow(
            serviceId: 1,
            name: 'Finance Office',
            code: 'FIN',
            status: ServiceStatus.open,
            issued: 13,
            waiting: 6,
            serving: 2,
            completed: 3,
            cancelled: 1,
            averageWaitMinutes: 18.5,
          ),
          AdminServiceRow(
            serviceId: 2,
            name: 'Registrar',
            code: 'REG',
            status: ServiceStatus.open,
            issued: 14,
            waiting: 8,
            serving: 1,
            completed: 5,
            cancelled: 0,
            averageWaitMinutes: 12.0,
          ),
        ],
    servedPerDay: servedPerDay ??
        const <ServedPoint>[
          ServedPoint(date: '2026-09-27', label: 'Sunday', served: 63),
          ServedPoint(date: '2026-09-28', label: 'Monday', served: 64),
          ServedPoint(date: '2026-09-29', label: 'Tuesday', served: 23),
        ],
    statusBreakdown: breakdown ??
        const StatusBreakdown(
          waiting: 34,
          serving: 5,
          completed: 23,
          cancelled: 2,
          skipped: 0,
          noShow: 1,
        ),
  );
}

StaffMember sampleStaffMember({
  int id = 4,
  String firstName = 'Jane',
  String lastName = 'Wanjiku',
  String email = 'jane.staff@smartqueue.test',
  UserStatus status = UserStatus.active,
  bool posted = true,
  int counterId = 2,
  int counterNumber = 2,
  String serviceName = 'Finance Office',
  CounterStatus counterStatus = CounterStatus.available,
}) {
  return StaffMember(
    id: id,
    firstName: firstName,
    lastName: lastName,
    fullName: '$firstName $lastName',
    email: email,
    phone: '+254700000011',
    role: UserRole.staff,
    status: status,
    createdAt: '2026-01-15T08:00:00.000Z',
    posting: posted
        ? RosterPosting(
            assignmentId: id,
            serviceId: 1,
            serviceName: serviceName,
            serviceCode: 'FIN',
            counterId: counterId,
            counterNumber: counterNumber,
            counterName: '$serviceName Counter $counterNumber',
            counterStatus: counterStatus,
            assignedAt: '2026-09-01T08:00:00.000Z',
          )
        : null,
  );
}

UserDetail sampleUserDetail({User? user, UserActivity? activity, RosterPosting? posting}) {
  return UserDetail(
    user: user ?? sampleUser(id: 9),
    activity: activity ??
        const UserActivity(
          totalTickets: 15,
          completed: 11,
          cancelled: 2,
          noShow: 0,
          active: 2,
          lastActivityAt: '2026-09-29T06:01:18.000Z',
        ),
    posting: posting,
    updatedAt: '2026-09-29T06:01:18.000Z',
  );
}

ManagedAnnouncement sampleManagedAnnouncement({
  int id = 1,
  String title = 'System maintenance',
  AnnouncementStatus status = AnnouncementStatus.draft,
  int? serviceId,
}) {
  return ManagedAnnouncement(
    announcement: Announcement(
      id: id,
      title: title,
      content: 'The portal will be unavailable on Saturday evening.',
      isGlobal: serviceId == null,
      serviceId: serviceId,
      serviceName: serviceId == null ? null : 'Finance Office',
      authorName: 'Admin User',
      publishedAt: status == AnnouncementStatus.published ? '2026-09-29T08:00:00.000Z' : null,
    ),
    status: status,
  );
}

SystemSetting sampleSystemSetting({
  String key = 'institution_name',
  String value = 'University Service Centre',
  String? description = 'Shown on the display board',
}) {
  return SystemSetting(
    key: key,
    value: value,
    description: description,
    updatedAt: '2026-09-29T08:00:00.000Z',
  );
}

// ── report sample data (Phase 8) ──────────────────────────────────────────

/// The fixture from `server/tests/reports.test.ts`, so the screen is shown
/// the same numbers the backend suite proves by hand: four finance tickets
/// (two served, one skipped, one cancelled) and one registrar ticket still
/// waiting.
DailyReport sampleDailyReport() {
  return const DailyReport(
    range: ReportRange(from: '2026-09-29', to: '2026-09-29'),
    rows: <DailyReportRow>[
      DailyReportRow(
        date: '2026-09-29',
        serviceId: 1,
        serviceName: 'Finance Office',
        serviceCode: 'FIN',
        issued: 4,
        served: 2,
        cancelled: 1,
        skipped: 1,
        noShow: 0,
        averageWaitMinutes: 20.0,
        averageServiceMinutes: 10.0,
      ),
      DailyReportRow(
        date: '2026-09-29',
        serviceId: 2,
        serviceName: 'Registrar',
        serviceCode: 'REG',
        issued: 1,
        served: 0,
        cancelled: 0,
        skipped: 0,
        noShow: 0,
      ),
    ],
    totals: ReportTotals(
      issued: 5,
      served: 2,
      cancelled: 1,
      skipped: 1,
      noShow: 0,
      averageWaitMinutes: 20.0,
      averageServiceMinutes: 10.0,
    ),
  );
}

ServicesReport sampleServicesReport() {
  return const ServicesReport(
    range: ReportRange(from: '2026-09-29', to: '2026-09-29'),
    rows: <ServiceReportRow>[
      ServiceReportRow(
        serviceId: 1,
        serviceName: 'Finance Office',
        serviceCode: 'FIN',
        status: 'open',
        issued: 4,
        customersServed: 2,
        cancelled: 1,
        skipped: 1,
        noShow: 0,
        completionRate: 50,
        peakQueueLength: 3,
        averageWaitMinutes: 20.0,
        averageServiceMinutes: 10.0,
        peakHour: 9,
        peakHourLabel: '09:00–10:00',
      ),
      ServiceReportRow(
        serviceId: 2,
        serviceName: 'Registrar',
        serviceCode: 'REG',
        status: 'open',
        issued: 1,
        customersServed: 0,
        cancelled: 0,
        skipped: 0,
        noShow: 0,
        completionRate: 0,
        peakQueueLength: 1,
      ),
    ],
    totals: ReportTotals(
      issued: 5,
      served: 2,
      cancelled: 1,
      skipped: 1,
      noShow: 0,
      averageWaitMinutes: 20.0,
      averageServiceMinutes: 10.0,
    ),
  );
}

StaffReport sampleStaffReport() {
  return const StaffReport(
    range: ReportRange(from: '2026-09-29', to: '2026-09-29'),
    rows: <StaffReportRow>[
      StaffReportRow(
        staffId: 4,
        staffName: 'Jane Wanjiku',
        email: 'jane.staff@smartqueue.test',
        serviceId: 1,
        serviceName: 'Finance Office',
        serviceCode: 'FIN',
        ticketsHandled: 5,
        ticketsServed: 1,
        ticketsSkipped: 1,
        ticketsNoShow: 0,
        ticketsRecalled: 0,
        averageServiceMinutes: 10.0,
      ),
      StaffReportRow(
        staffId: 5,
        staffName: 'Peter Otieno',
        email: 'peter.staff@smartqueue.test',
        serviceId: 1,
        serviceName: 'Finance Office',
        serviceCode: 'FIN',
        ticketsHandled: 3,
        ticketsServed: 1,
        ticketsSkipped: 0,
        ticketsNoShow: 0,
        ticketsRecalled: 0,
        averageServiceMinutes: 10.0,
      ),
    ],
    totals: StaffReportTotals(
      staff: 2,
      ticketsHandled: 8,
      ticketsServed: 2,
      ticketsSkipped: 1,
      ticketsNoShow: 0,
      averageServiceMinutes: 10.0,
    ),
  );
}

QueuesReport sampleQueuesReport() {
  return const QueuesReport(
    range: ReportRange(from: '2026-09-29', to: '2026-09-29'),
    rows: <QueueReportRow>[
      QueueReportRow(
        queueId: 3,
        date: '2026-09-29',
        serviceId: 1,
        serviceName: 'Finance Office',
        serviceCode: 'FIN',
        status: 'closed',
        issued: 4,
        served: 2,
        peakQueue: 3,
        averageQueue: 1.6,
        countersUsed: 2,
        utilisationPercent: 25,
        openedAt: '2026-09-29T06:00:00.000Z',
        closedAt: '2026-09-29T06:40:00.000Z',
      ),
      QueueReportRow(
        queueId: 6,
        date: '2026-09-29',
        serviceId: 2,
        serviceName: 'Registrar',
        serviceCode: 'REG',
        status: 'waiting',
        issued: 1,
        served: 0,
        peakQueue: 1,
        averageQueue: 1.0,
        countersUsed: 1,
        utilisationPercent: 0,
        openedAt: '2026-09-29T06:30:00.000Z',
      ),
    ],
    totals: QueuesReportTotals(
      queues: 2,
      issued: 5,
      served: 2,
      peakQueue: 3,
      averageUtilisationPercent: 13,
    ),
  );
}
