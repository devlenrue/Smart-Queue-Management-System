import '../core/constants/enums.dart';
import '../core/utils/json.dart';

/// One row of the per-service table on the admin dashboard (§31).
class AdminServiceRow {
  const AdminServiceRow({
    required this.serviceId,
    required this.name,
    required this.code,
    required this.status,
    required this.issued,
    required this.waiting,
    required this.serving,
    required this.completed,
    required this.cancelled,
    required this.averageWaitMinutes,
  });

  final int serviceId;
  final String name;
  final String code;
  final ServiceStatus status;
  final int issued;
  final int waiting;
  final int serving;
  final int completed;
  final int cancelled;
  final double averageWaitMinutes;

  factory AdminServiceRow.fromJson(Map<String, dynamic> json) {
    return AdminServiceRow(
      serviceId: Json.asInt(json['serviceId']),
      name: Json.asString(json['name']),
      code: Json.asString(json['code']),
      status: ServiceStatus.parse(Json.asStringOrNull(json['status'])),
      issued: Json.asInt(json['issued']),
      waiting: Json.asInt(json['waiting']),
      serving: Json.asInt(json['serving']),
      completed: Json.asInt(json['completed']),
      cancelled: Json.asInt(json['cancelled']),
      averageWaitMinutes: Json.asDouble(json['averageWaitMinutes']),
    );
  }
}

/// One bar of the served-per-day chart. The server zero-fills quiet days, so
/// the series is always dense and the axis never lies.
class ServedPoint {
  const ServedPoint({required this.date, required this.label, required this.served});

  final String date;
  final String label;
  final int served;

  factory ServedPoint.fromJson(Map<String, dynamic> json) {
    return ServedPoint(
      date: Json.asString(json['date']),
      label: Json.asString(json['label']),
      served: Json.asInt(json['served']),
    );
  }

  /// `Monday` → `Mon`, for a chart axis that has to fit seven of them.
  String get shortLabel => label.length <= 3 ? label : label.substring(0, 3);
}

/// Today's tickets by state — the donut beside the bar chart.
class StatusBreakdown {
  const StatusBreakdown({
    required this.waiting,
    required this.serving,
    required this.completed,
    required this.cancelled,
    required this.skipped,
    required this.noShow,
  });

  final int waiting;
  final int serving;
  final int completed;
  final int cancelled;
  final int skipped;
  final int noShow;

  factory StatusBreakdown.fromJson(Map<String, dynamic> json) {
    return StatusBreakdown(
      waiting: Json.asInt(json['waiting']),
      serving: Json.asInt(json['serving']),
      completed: Json.asInt(json['completed']),
      cancelled: Json.asInt(json['cancelled']),
      skipped: Json.asInt(json['skipped']),
      noShow: Json.asInt(json['noShow']),
    );
  }

  int get total => waiting + serving + completed + cancelled + skipped + noShow;

  /// Slices in a fixed order, so the legend colours never shuffle between
  /// polls.
  List<({String label, int value, TicketStatus status})> get slices {
    return <({String label, int value, TicketStatus status})>[
      (label: 'Waiting', value: waiting, status: TicketStatus.waiting),
      (label: 'Serving', value: serving, status: TicketStatus.serving),
      (label: 'Completed', value: completed, status: TicketStatus.completed),
      (label: 'Cancelled', value: cancelled, status: TicketStatus.cancelled),
      (label: 'Skipped', value: skipped, status: TicketStatus.skipped),
      (label: 'No-show', value: noShow, status: TicketStatus.noShow),
    ];
  }
}

/// `GET /dashboard/admin` — the whole institution on one screen.
class AdminDashboard {
  const AdminDashboard({
    required this.today,
    required this.activeServices,
    required this.activeQueues,
    required this.activeCounters,
    required this.staffOnDuty,
    required this.customersWaiting,
    required this.customersServedToday,
    required this.averageWaitMinutes,
    required this.averageServiceMinutes,
    required this.ticketsIssuedToday,
    required this.cancelledToday,
    required this.skippedToday,
    required this.noShowToday,
    required this.byService,
    required this.servedPerDay,
    required this.statusBreakdown,
  });

  final String today;
  final int activeServices;
  final int activeQueues;
  final int activeCounters;
  final int staffOnDuty;
  final int customersWaiting;
  final int customersServedToday;
  final double averageWaitMinutes;
  final double averageServiceMinutes;
  final int ticketsIssuedToday;
  final int cancelledToday;
  final int skippedToday;
  final int noShowToday;
  final List<AdminServiceRow> byService;
  final List<ServedPoint> servedPerDay;
  final StatusBreakdown statusBreakdown;

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    return AdminDashboard(
      today: Json.asString(json['today']),
      activeServices: Json.asInt(json['activeServices']),
      activeQueues: Json.asInt(json['activeQueues']),
      activeCounters: Json.asInt(json['activeCounters']),
      staffOnDuty: Json.asInt(json['staffOnDuty']),
      customersWaiting: Json.asInt(json['customersWaiting']),
      customersServedToday: Json.asInt(json['customersServedToday']),
      averageWaitMinutes: Json.asDouble(json['averageWaitMinutes']),
      averageServiceMinutes: Json.asDouble(json['averageServiceMinutes']),
      ticketsIssuedToday: Json.asInt(json['ticketsIssuedToday']),
      cancelledToday: Json.asInt(json['cancelledToday']),
      skippedToday: Json.asInt(json['skippedToday']),
      noShowToday: Json.asInt(json['noShowToday']),
      byService: Json.mapList(json['byService'], AdminServiceRow.fromJson),
      servedPerDay: Json.mapList(json['servedPerDay'], ServedPoint.fromJson),
      statusBreakdown:
          StatusBreakdown.fromJson(Json.asMap(json['statusBreakdown']) ?? const <String, dynamic>{}),
    );
  }

  /// The busiest service today — the one a supervisor should look at first.
  AdminServiceRow? get busiest {
    if (byService.isEmpty) return null;
    return byService.reduce(
      (AdminServiceRow a, AdminServiceRow b) => b.waiting > a.waiting ? b : a,
    );
  }
}
