import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/core/network/api_client.dart';
import 'package:smartqueue/core/network/api_response.dart';
import 'package:smartqueue/core/storage/prefs_storage.dart';
import 'package:smartqueue/core/storage/secure_storage.dart';
import 'package:smartqueue/core/theme/app_theme.dart';
import 'package:smartqueue/models/announcement.dart';
import 'package:smartqueue/models/counter.dart';
import 'package:smartqueue/models/notification.dart';
import 'package:smartqueue/models/queue.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/models/staff_dashboard.dart';
import 'package:smartqueue/models/staff_statistics.dart';
import 'package:smartqueue/models/ticket.dart';
import 'package:smartqueue/models/user.dart';
import 'package:smartqueue/providers/infrastructure_providers.dart';
import 'package:smartqueue/repositories/auth_repository.dart';
import 'package:smartqueue/repositories/notification_repository.dart';
import 'package:smartqueue/repositories/queue_repository.dart';
import 'package:smartqueue/repositories/service_repository.dart';
import 'package:smartqueue/repositories/staff_repository.dart';
import 'package:smartqueue/repositories/ticket_repository.dart';
import 'package:smartqueue/services/auth_api.dart';
import 'package:smartqueue/services/notification_api.dart';
import 'package:smartqueue/services/queue_api.dart';
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
  int listCalls = 0;

  @override
  Future<Paged<Service>> list({
    int page = 1,
    int limit = 20,
    String? search,
    String? category,
  }) async {
    listCalls++;
    lastSearch = search;
    if (failure != null) throw failure!;

    final List<Service> filtered = services.where((Service s) {
      final bool matchesSearch = search == null ||
          search.isEmpty ||
          s.name.toLowerCase().contains(search.toLowerCase());
      final bool matchesCategory = category == null || s.category == category;
      return matchesSearch && matchesCategory;
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
  List<TicketEvent> events = <TicketEvent>[];

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
  Future<List<TicketEvent>> events(int id) async => events;

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
class TestHarness {
  TestHarness({required this.prefs});

  final PrefsStorage prefs;

  final FakeAuthRepository auth = FakeAuthRepository();
  final FakeServiceRepository services = FakeServiceRepository();
  final FakeTicketRepository tickets = FakeTicketRepository();
  final FakeQueueRepository queues = FakeQueueRepository();
  final FakeNotificationRepository notifications = FakeNotificationRepository();
  final FakeStaffRepository staff = FakeStaffRepository();

  /// Puts somebody in the session, so screens behind the auth guard build.
  void signIn({UserRole role = UserRole.customer, String firstName = 'Jane'}) {
    auth.sessionUser = sampleUser(
      id: 7,
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

  /// Takes the screen down and lets the last poll timer fire.
  ///
  /// A poll loop that has no terminal state — the staff console keeps
  /// refreshing all day — is suspended inside `Future.delayed` when the tree
  /// is disposed. Replacing the tree cancels the subscription; pumping once
  /// more lets that timer fire, at which point the generator resumes, hits
  /// its `yield` on a cancelled stream and exits. Without this the test ends
  /// with a pending timer.
  Future<void> unmountAndDrain(TestHarness harness) async {
    await pumpWidget(const SizedBox.shrink());
    await pump(harness.prefs.readPollInterval());
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
