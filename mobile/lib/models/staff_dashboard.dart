import '../core/constants/enums.dart';
import '../core/utils/json.dart';
import 'queue.dart';
import 'ticket.dart';

/// Which service and counter this clerk is working today.
class StaffAssignment {
  const StaffAssignment({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    this.counterId,
    this.counterNumber,
    this.counterName,
    this.assignedAt,
  });

  final int id;
  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final int? counterId;
  final int? counterNumber;
  final String? counterName;
  final String? assignedAt;

  factory StaffAssignment.fromJson(Map<String, dynamic> json) {
    return StaffAssignment(
      id: Json.asInt(json['id']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      counterId: Json.asIntOrNull(json['counterId']),
      counterNumber: Json.asIntOrNull(json['counterNumber']),
      counterName: Json.asStringOrNull(json['counterName']),
      assignedAt: Json.asStringOrNull(json['assignedAt']),
    );
  }
}

/// The service header on the console.
class StaffServiceRef {
  const StaffServiceRef({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
  });

  final int id;
  final String name;
  final String code;
  final ServiceStatus status;

  factory StaffServiceRef.fromJson(Map<String, dynamic> json) {
    return StaffServiceRef(
      id: Json.asInt(json['id']),
      name: Json.asString(json['name']),
      code: Json.asString(json['code']),
      status: ServiceStatus.parse(Json.asStringOrNull(json['status'])),
    );
  }
}

/// The clerk's own counter, with the switch that opens and closes it.
class StaffCounter {
  const StaffCounter({
    required this.id,
    required this.serviceId,
    required this.counterNumber,
    required this.name,
    required this.status,
    this.assignedStaffId,
  });

  final int id;
  final int serviceId;
  final int counterNumber;
  final String name;
  final CounterStatus status;
  final int? assignedStaffId;

  factory StaffCounter.fromJson(Map<String, dynamic> json) {
    return StaffCounter(
      id: Json.asInt(json['id']),
      serviceId: Json.asInt(json['serviceId']),
      counterNumber: Json.asInt(json['counterNumber']),
      name: Json.asString(json['name']),
      status: CounterStatus.parse(Json.asStringOrNull(json['status'])),
      assignedStaffId: Json.asIntOrNull(json['assignedStaffId']),
    );
  }

  /// A counter cannot go off duty with somebody standing at it; the server
  /// enforces this too, but greying the switch out is friendlier than a 409.
  bool get canGoOffline => status != CounterStatus.busy;
}

/// The four tiles across the top of the console.
class StaffDashboardStats {
  const StaffDashboardStats({
    required this.waiting,
    required this.servedToday,
    required this.skippedToday,
    required this.noShowToday,
    required this.cancelledToday,
    required this.averageServiceMinutes,
    required this.averageWaitMinutes,
  });

  /// Everyone still waiting in the service's queue.
  final int waiting;

  /// What *this* clerk completed today — not the service total.
  final int servedToday;
  final int skippedToday;
  final int noShowToday;
  final int cancelledToday;
  final int averageServiceMinutes;
  final int averageWaitMinutes;

  factory StaffDashboardStats.fromJson(Map<String, dynamic> json) {
    return StaffDashboardStats(
      waiting: Json.asInt(json['waiting']),
      servedToday: Json.asInt(json['servedToday']),
      skippedToday: Json.asInt(json['skippedToday']),
      noShowToday: Json.asInt(json['noShowToday']),
      cancelledToday: Json.asInt(json['cancelledToday']),
      averageServiceMinutes: Json.asInt(json['averageServiceMinutes']),
      averageWaitMinutes: Json.asInt(json['averageWaitMinutes']),
    );
  }

  static const StaffDashboardStats empty = StaffDashboardStats(
    waiting: 0,
    servedToday: 0,
    skippedToday: 0,
    noShowToday: 0,
    cancelledToday: 0,
    averageServiceMinutes: 0,
    averageWaitMinutes: 0,
  );
}

/// `GET /dashboard/staff` — the console's whole first screen in one payload.
class StaffDashboard {
  const StaffDashboard({
    required this.today,
    required this.assigned,
    required this.upNext,
    required this.stats,
    this.assignment,
    this.service,
    this.counter,
    this.queue,
    this.currentTicket,
  });

  final String today;

  /// False when nobody has put this person on a service yet. The screen then
  /// explains what to do instead of showing a broken console.
  final bool assigned;

  final StaffAssignment? assignment;
  final StaffServiceRef? service;
  final StaffCounter? counter;
  final QueueStatusView? queue;

  /// Whoever is at the counter right now — `called` or `serving`.
  final Ticket? currentTicket;

  /// The next few waiting tickets, in queue order.
  final List<Ticket> upNext;

  final StaffDashboardStats stats;

  factory StaffDashboard.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? assignment = Json.asMap(json['assignment']);
    final Map<String, dynamic>? service = Json.asMap(json['service']);
    final Map<String, dynamic>? counter = Json.asMap(json['counter']);
    final Map<String, dynamic>? queue = Json.asMap(json['queue']);
    final Map<String, dynamic>? current = Json.asMap(json['currentTicket']);
    final Map<String, dynamic>? stats = Json.asMap(json['stats']);

    return StaffDashboard(
      today: Json.asString(json['today']),
      assigned: Json.asBool(json['assigned']),
      assignment: assignment == null ? null : StaffAssignment.fromJson(assignment),
      service: service == null ? null : StaffServiceRef.fromJson(service),
      counter: counter == null ? null : StaffCounter.fromJson(counter),
      queue: queue == null ? null : QueueStatusView.fromJson(queue),
      currentTicket: current == null ? null : Ticket.fromJson(current),
      upNext: Json.mapList(json['upNext'], Ticket.fromJson),
      stats: stats == null ? StaffDashboardStats.empty : StaffDashboardStats.fromJson(stats),
    );
  }
}
