import '../core/constants/enums.dart';
import '../core/utils/json.dart';

/// One bar on the statistics chart.
class StaffDayStat {
  const StaffDayStat({
    required this.date,
    required this.served,
    required this.averageServiceMinutes,
  });

  final String date;
  final int served;
  final double averageServiceMinutes;

  factory StaffDayStat.fromJson(Map<String, dynamic> json) {
    return StaffDayStat(
      date: Json.asString(json['date']),
      served: Json.asInt(json['served']),
      averageServiceMinutes: Json.asDouble(json['averageServiceMinutes']),
    );
  }

  DateTime? get day => DateTime.tryParse(date);
}

class StaffProfileRef {
  const StaffProfileRef({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final int id;
  final String name;
  final String email;
  final UserRole role;

  factory StaffProfileRef.fromJson(Map<String, dynamic> json) {
    return StaffProfileRef(
      id: Json.asInt(json['id']),
      name: Json.asString(json['name']),
      email: Json.asString(json['email']),
      role: UserRole.parse(Json.asStringOrNull(json['role'])),
    );
  }
}

/// `GET /staff/:id/statistics` (§37).
class StaffStatistics {
  const StaffStatistics({
    required this.staff,
    required this.from,
    required this.to,
    required this.ticketsServed,
    required this.ticketsSkipped,
    required this.ticketsNoShow,
    required this.ticketsRecalled,
    required this.ticketsHandled,
    required this.completionRate,
    required this.averageServiceMinutes,
    required this.averageWaitMinutes,
    required this.byDay,
  });

  final StaffProfileRef staff;
  final String from;
  final String to;
  final int ticketsServed;
  final int ticketsSkipped;
  final int ticketsNoShow;
  final int ticketsRecalled;

  /// served + skipped + no-show.
  final int ticketsHandled;

  /// Percentage of dispositions that ended in a completed service.
  final int completionRate;

  final double averageServiceMinutes;
  final double averageWaitMinutes;
  final List<StaffDayStat> byDay;

  factory StaffStatistics.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> range = Json.asMap(json['range']) ?? const <String, dynamic>{};
    return StaffStatistics(
      staff: StaffProfileRef.fromJson(Json.asMap(json['staff']) ?? const <String, dynamic>{}),
      from: Json.asString(range['from']),
      to: Json.asString(range['to']),
      ticketsServed: Json.asInt(json['ticketsServed']),
      ticketsSkipped: Json.asInt(json['ticketsSkipped']),
      ticketsNoShow: Json.asInt(json['ticketsNoShow']),
      ticketsRecalled: Json.asInt(json['ticketsRecalled']),
      ticketsHandled: Json.asInt(json['ticketsHandled']),
      completionRate: Json.asInt(json['completionRate']),
      averageServiceMinutes: Json.asDouble(json['averageServiceMinutes']),
      averageWaitMinutes: Json.asDouble(json['averageWaitMinutes']),
      byDay: Json.mapList(json['byDay'], StaffDayStat.fromJson),
    );
  }

  bool get isEmpty => ticketsHandled == 0;

  /// The tallest bar, so the chart can scale itself.
  int get busiestDay =>
      byDay.fold<int>(0, (int max, StaffDayStat day) => day.served > max ? day.served : max);
}
