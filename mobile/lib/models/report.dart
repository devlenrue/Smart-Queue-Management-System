import '../core/utils/json.dart';

/// The four management reports (§41, docs/api.md §13).
///
/// Every endpoint answers with the same outer shape — `{ range, rows,
/// totals }` — so the screen can swap tabs without re-learning how to read a
/// response. Only the row and the totals change.
///
/// Minutes arrive as `null` where nobody reached that stage, which is not
/// the same as zero minutes; the models keep the distinction and the table
/// prints an em dash.

/// Which report is being looked at. The wire name is the path segment.
enum ReportKind {
  daily('daily', 'Daily', 'Day by day, service by service'),
  services('services', 'Services', 'How each service performed'),
  staff('staff', 'Staff', 'Who handled what'),
  queues('queues', 'Queues', 'How each queue behaved');

  const ReportKind(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;
}

class ReportRange {
  const ReportRange({required this.from, required this.to});

  final String from;
  final String to;

  bool get isSingleDay => from == to;

  factory ReportRange.fromJson(Map<String, dynamic> json) {
    return ReportRange(
      from: Json.asString(json['from']),
      to: Json.asString(json['to']),
    );
  }

  @override
  bool operator ==(Object other) => other is ReportRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The totals line under the daily and service reports.
class ReportTotals {
  const ReportTotals({
    required this.issued,
    required this.served,
    required this.cancelled,
    required this.skipped,
    required this.noShow,
    this.averageWaitMinutes,
    this.averageServiceMinutes,
  });

  final int issued;
  final int served;
  final int cancelled;
  final int skipped;
  final int noShow;
  final double? averageWaitMinutes;
  final double? averageServiceMinutes;

  /// Completion as a percentage of everything issued — the one figure a
  /// registrar quotes in a meeting.
  int get completionRate => issued == 0 ? 0 : ((served / issued) * 100).round();

  factory ReportTotals.fromJson(Map<String, dynamic> json) {
    return ReportTotals(
      issued: Json.asInt(json['issued']),
      served: Json.asInt(json['served']),
      cancelled: Json.asInt(json['cancelled']),
      skipped: Json.asInt(json['skipped']),
      noShow: Json.asInt(json['noShow']),
      averageWaitMinutes: _minutes(json['averageWaitMinutes']),
      averageServiceMinutes: _minutes(json['averageServiceMinutes']),
    );
  }

  static const ReportTotals empty = ReportTotals(
    issued: 0,
    served: 0,
    cancelled: 0,
    skipped: 0,
    noShow: 0,
  );
}

/// `null` means "nobody got that far", so it must survive the parse.
double? _minutes(dynamic value) => value == null ? null : Json.asDouble(value);

// ── §41.1 daily summary ────────────────────────────────────────────────────

class DailyReportRow {
  const DailyReportRow({
    required this.date,
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    required this.issued,
    required this.served,
    required this.cancelled,
    required this.skipped,
    required this.noShow,
    this.averageWaitMinutes,
    this.averageServiceMinutes,
  });

  final String date;
  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final int issued;
  final int served;
  final int cancelled;
  final int skipped;
  final int noShow;
  final double? averageWaitMinutes;
  final double? averageServiceMinutes;

  /// Unique per row even when one service appears on several days.
  String get key => '$date-$serviceId';

  factory DailyReportRow.fromJson(Map<String, dynamic> json) {
    return DailyReportRow(
      date: Json.asString(json['date']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      issued: Json.asInt(json['issued']),
      served: Json.asInt(json['served']),
      cancelled: Json.asInt(json['cancelled']),
      skipped: Json.asInt(json['skipped']),
      noShow: Json.asInt(json['noShow']),
      averageWaitMinutes: _minutes(json['averageWaitMinutes']),
      averageServiceMinutes: _minutes(json['averageServiceMinutes']),
    );
  }
}

class DailyReport {
  const DailyReport({required this.range, required this.rows, required this.totals});

  final ReportRange range;
  final List<DailyReportRow> rows;
  final ReportTotals totals;

  factory DailyReport.fromJson(Map<String, dynamic> json) {
    return DailyReport(
      range: ReportRange.fromJson(Json.asMap(json['range']) ?? const <String, dynamic>{}),
      rows: Json.mapList(json['rows'], DailyReportRow.fromJson),
      totals: ReportTotals.fromJson(Json.asMap(json['totals']) ?? const <String, dynamic>{}),
    );
  }
}

// ── §41.2 service performance ──────────────────────────────────────────────

class ServiceReportRow {
  const ServiceReportRow({
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    required this.status,
    required this.issued,
    required this.customersServed,
    required this.cancelled,
    required this.skipped,
    required this.noShow,
    required this.completionRate,
    required this.peakQueueLength,
    this.averageWaitMinutes,
    this.averageServiceMinutes,
    this.peakHour,
    this.peakHourLabel,
  });

  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final String status;
  final int issued;
  final int customersServed;
  final int cancelled;
  final int skipped;
  final int noShow;
  final int completionRate;
  final int peakQueueLength;
  final double? averageWaitMinutes;
  final double? averageServiceMinutes;

  /// 0–23, or null when the service saw nobody in the range.
  final int? peakHour;
  final String? peakHourLabel;

  factory ServiceReportRow.fromJson(Map<String, dynamic> json) {
    return ServiceReportRow(
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      status: Json.asString(json['status'], 'open'),
      issued: Json.asInt(json['issued']),
      customersServed: Json.asInt(json['customersServed']),
      cancelled: Json.asInt(json['cancelled']),
      skipped: Json.asInt(json['skipped']),
      noShow: Json.asInt(json['noShow']),
      completionRate: Json.asInt(json['completionRate']),
      peakQueueLength: Json.asInt(json['peakQueueLength']),
      averageWaitMinutes: _minutes(json['averageWaitMinutes']),
      averageServiceMinutes: _minutes(json['averageServiceMinutes']),
      peakHour: Json.asIntOrNull(json['peakHour']),
      peakHourLabel: Json.asStringOrNull(json['peakHourLabel']),
    );
  }
}

class ServicesReport {
  const ServicesReport({required this.range, required this.rows, required this.totals});

  final ReportRange range;
  final List<ServiceReportRow> rows;
  final ReportTotals totals;

  factory ServicesReport.fromJson(Map<String, dynamic> json) {
    return ServicesReport(
      range: ReportRange.fromJson(Json.asMap(json['range']) ?? const <String, dynamic>{}),
      rows: Json.mapList(json['rows'], ServiceReportRow.fromJson),
      totals: ReportTotals.fromJson(Json.asMap(json['totals']) ?? const <String, dynamic>{}),
    );
  }
}

// ── §41.3 staff performance ────────────────────────────────────────────────

class StaffReportRow {
  const StaffReportRow({
    required this.staffId,
    required this.staffName,
    required this.email,
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    required this.ticketsHandled,
    required this.ticketsServed,
    required this.ticketsSkipped,
    required this.ticketsNoShow,
    required this.ticketsRecalled,
    this.averageServiceMinutes,
  });

  final int staffId;
  final String staffName;
  final String email;
  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final int ticketsHandled;
  final int ticketsServed;
  final int ticketsSkipped;
  final int ticketsNoShow;
  final int ticketsRecalled;
  final double? averageServiceMinutes;

  /// One clerk can appear once per service they worked.
  String get key => '$staffId-$serviceId';

  factory StaffReportRow.fromJson(Map<String, dynamic> json) {
    return StaffReportRow(
      staffId: Json.asInt(json['staffId']),
      staffName: Json.asString(json['staffName']),
      email: Json.asString(json['email']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      ticketsHandled: Json.asInt(json['ticketsHandled']),
      ticketsServed: Json.asInt(json['ticketsServed']),
      ticketsSkipped: Json.asInt(json['ticketsSkipped']),
      ticketsNoShow: Json.asInt(json['ticketsNoShow']),
      ticketsRecalled: Json.asInt(json['ticketsRecalled']),
      averageServiceMinutes: _minutes(json['averageServiceMinutes']),
    );
  }
}

class StaffReportTotals {
  const StaffReportTotals({
    required this.staff,
    required this.ticketsHandled,
    required this.ticketsServed,
    required this.ticketsSkipped,
    required this.ticketsNoShow,
    this.averageServiceMinutes,
  });

  final int staff;
  final int ticketsHandled;
  final int ticketsServed;
  final int ticketsSkipped;
  final int ticketsNoShow;
  final double? averageServiceMinutes;

  factory StaffReportTotals.fromJson(Map<String, dynamic> json) {
    return StaffReportTotals(
      staff: Json.asInt(json['staff']),
      ticketsHandled: Json.asInt(json['ticketsHandled']),
      ticketsServed: Json.asInt(json['ticketsServed']),
      ticketsSkipped: Json.asInt(json['ticketsSkipped']),
      ticketsNoShow: Json.asInt(json['ticketsNoShow']),
      averageServiceMinutes: _minutes(json['averageServiceMinutes']),
    );
  }

  static const StaffReportTotals empty = StaffReportTotals(
    staff: 0,
    ticketsHandled: 0,
    ticketsServed: 0,
    ticketsSkipped: 0,
    ticketsNoShow: 0,
  );
}

class StaffReport {
  const StaffReport({required this.range, required this.rows, required this.totals});

  final ReportRange range;
  final List<StaffReportRow> rows;
  final StaffReportTotals totals;

  factory StaffReport.fromJson(Map<String, dynamic> json) {
    return StaffReport(
      range: ReportRange.fromJson(Json.asMap(json['range']) ?? const <String, dynamic>{}),
      rows: Json.mapList(json['rows'], StaffReportRow.fromJson),
      totals: StaffReportTotals.fromJson(Json.asMap(json['totals']) ?? const <String, dynamic>{}),
    );
  }
}

// ── §41.4 queue analytics ──────────────────────────────────────────────────

class QueueReportRow {
  const QueueReportRow({
    required this.queueId,
    required this.date,
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    required this.status,
    required this.issued,
    required this.served,
    required this.peakQueue,
    required this.averageQueue,
    required this.countersUsed,
    required this.utilisationPercent,
    this.openedAt,
    this.closedAt,
  });

  final int queueId;
  final String date;
  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final String status;
  final int issued;
  final int served;
  final int peakQueue;
  final double averageQueue;
  final int countersUsed;
  final int utilisationPercent;
  final String? openedAt;

  /// Null while the queue is still open.
  final String? closedAt;

  bool get isOpen => closedAt == null;

  factory QueueReportRow.fromJson(Map<String, dynamic> json) {
    return QueueReportRow(
      queueId: Json.asInt(json['queueId']),
      date: Json.asString(json['date']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      status: Json.asString(json['status'], 'waiting'),
      issued: Json.asInt(json['issued']),
      served: Json.asInt(json['served']),
      peakQueue: Json.asInt(json['peakQueue']),
      averageQueue: Json.asDouble(json['averageQueue']),
      countersUsed: Json.asInt(json['countersUsed']),
      utilisationPercent: Json.asInt(json['utilisationPercent']),
      openedAt: Json.asStringOrNull(json['openedAt']),
      closedAt: Json.asStringOrNull(json['closedAt']),
    );
  }
}

class QueuesReportTotals {
  const QueuesReportTotals({
    required this.queues,
    required this.issued,
    required this.served,
    required this.peakQueue,
    required this.averageUtilisationPercent,
  });

  final int queues;
  final int issued;
  final int served;
  final int peakQueue;
  final int averageUtilisationPercent;

  factory QueuesReportTotals.fromJson(Map<String, dynamic> json) {
    return QueuesReportTotals(
      queues: Json.asInt(json['queues']),
      issued: Json.asInt(json['issued']),
      served: Json.asInt(json['served']),
      peakQueue: Json.asInt(json['peakQueue']),
      averageUtilisationPercent: Json.asInt(json['averageUtilisationPercent']),
    );
  }

  static const QueuesReportTotals empty = QueuesReportTotals(
    queues: 0,
    issued: 0,
    served: 0,
    peakQueue: 0,
    averageUtilisationPercent: 0,
  );
}

class QueuesReport {
  const QueuesReport({required this.range, required this.rows, required this.totals});

  final ReportRange range;
  final List<QueueReportRow> rows;
  final QueuesReportTotals totals;

  factory QueuesReport.fromJson(Map<String, dynamic> json) {
    return QueuesReport(
      range: ReportRange.fromJson(Json.asMap(json['range']) ?? const <String, dynamic>{}),
      rows: Json.mapList(json['rows'], QueueReportRow.fromJson),
      totals: QueuesReportTotals.fromJson(Json.asMap(json['totals']) ?? const <String, dynamic>{}),
    );
  }
}
