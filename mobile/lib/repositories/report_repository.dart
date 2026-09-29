import '../models/report.dart';
import '../services/report_api.dart';

/// Reporting reads for the administrator console.
///
/// Thin by design — the server does the aggregation, and a report is never
/// cached: an administrator who re-runs one is asking for today's answer,
/// not yesterday's. Keeping the class here anyway means the screens depend
/// on an interface the tests can replace, exactly like every other feature.
class ReportRepository {
  const ReportRepository(this._api);

  final ReportApi _api;

  Future<DailyReport> daily({String? from, String? to, int? serviceId}) {
    return _api.daily(from: from, to: to, serviceId: serviceId);
  }

  Future<ServicesReport> services({String? from, String? to, int? serviceId}) {
    return _api.services(from: from, to: to, serviceId: serviceId);
  }

  Future<StaffReport> staff({String? from, String? to, int? serviceId, int? staffId}) {
    return _api.staff(from: from, to: to, serviceId: serviceId, staffId: staffId);
  }

  Future<QueuesReport> queues({String? from, String? to, int? serviceId}) {
    return _api.queues(from: from, to: to, serviceId: serviceId);
  }

  Future<String> csv(ReportKind kind, {String? from, String? to, int? serviceId, int? staffId}) {
    return _api.csv(kind, from: from, to: to, serviceId: serviceId, staffId: staffId);
  }
}
