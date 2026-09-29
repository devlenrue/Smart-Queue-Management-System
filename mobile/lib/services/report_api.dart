import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/report.dart';

/// The reporting endpoints (§41, docs/api.md §13).
///
/// All four take the same query, so it is built once in [_query] and the
/// five methods below differ only in the path and the model they parse.
/// `format=csv` returns a file instead of an envelope, which is why the
/// export goes through [ApiClient.getText].
class ReportApi {
  const ReportApi(this._client);

  final ApiClient _client;

  static Map<String, dynamic> _query({
    String? from,
    String? to,
    int? serviceId,
    int? staffId,
    String? format,
  }) {
    return <String, dynamic>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (serviceId != null) 'serviceId': serviceId,
      if (staffId != null) 'staffId': staffId,
      if (format != null) 'format': format,
    };
  }

  Future<DailyReport> daily({String? from, String? to, int? serviceId}) async {
    final ApiResponse<Map<String, dynamic>> response =
        await _client.get<Map<String, dynamic>>(
      ApiEndpoints.reportsDaily,
      query: _query(from: from, to: to, serviceId: serviceId),
      parse: Parse.object,
    );
    return DailyReport.fromJson(response.data);
  }

  Future<ServicesReport> services({String? from, String? to, int? serviceId}) async {
    final ApiResponse<Map<String, dynamic>> response =
        await _client.get<Map<String, dynamic>>(
      ApiEndpoints.reportsServices,
      query: _query(from: from, to: to, serviceId: serviceId),
      parse: Parse.object,
    );
    return ServicesReport.fromJson(response.data);
  }

  Future<StaffReport> staff({String? from, String? to, int? serviceId, int? staffId}) async {
    final ApiResponse<Map<String, dynamic>> response =
        await _client.get<Map<String, dynamic>>(
      ApiEndpoints.reportsStaff,
      query: _query(from: from, to: to, serviceId: serviceId, staffId: staffId),
      parse: Parse.object,
    );
    return StaffReport.fromJson(response.data);
  }

  Future<QueuesReport> queues({String? from, String? to, int? serviceId}) async {
    final ApiResponse<Map<String, dynamic>> response =
        await _client.get<Map<String, dynamic>>(
      ApiEndpoints.reportsQueues,
      query: _query(from: from, to: to, serviceId: serviceId),
      parse: Parse.object,
    );
    return QueuesReport.fromJson(response.data);
  }

  /// The same report, as the CSV text the server would have offered a
  /// browser as a download.
  Future<String> csv(
    ReportKind kind, {
    String? from,
    String? to,
    int? serviceId,
    int? staffId,
  }) {
    return _client.getText(
      ApiEndpoints.report(kind.wire),
      query: _query(from: from, to: to, serviceId: serviceId, staffId: staffId, format: 'csv'),
    );
  }
}
