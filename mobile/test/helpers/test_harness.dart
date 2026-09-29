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
import 'package:smartqueue/models/ticket.dart';
import 'package:smartqueue/models/user.dart';
import 'package:smartqueue/providers/infrastructure_providers.dart';
import 'package:smartqueue/repositories/auth_repository.dart';
import 'package:smartqueue/repositories/notification_repository.dart';
import 'package:smartqueue/repositories/queue_repository.dart';
import 'package:smartqueue/repositories/service_repository.dart';
import 'package:smartqueue/repositories/ticket_repository.dart';
import 'package:smartqueue/services/auth_api.dart';
import 'package:smartqueue/services/notification_api.dart';
import 'package:smartqueue/services/queue_api.dart';
import 'package:smartqueue/services/service_api.dart';
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
  CounterSummary? counter,
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
    waitedMinutes: 6,
    counter: counter,
    joinedAt: '2026-09-29T08:15:00.000Z',
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

QueueStatusView sampleQueueStatus() {
  return const QueueStatusView(
    queueId: 101,
    serviceId: 1,
    serviceName: 'Finance Office',
    serviceCode: 'FIN',
    queueDate: '2026-09-29',
    status: QueueStatus.waiting,
    currentNumber: 9,
    waitingCount: 4,
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
    nowServing: 'FIN-009',
  );
}
