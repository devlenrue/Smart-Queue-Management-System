import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/counter.dart';
import '../models/staff_dashboard.dart';
import '../models/staff_statistics.dart';
import '../models/ticket.dart';

/// Every call the staff console makes. One method per endpoint; no logic.
class StaffApi {
  const StaffApi(this._client);

  final ApiClient _client;

  /// `GET /dashboard/staff`. `serviceId` is only honoured for admins, who
  /// have no assignment of their own and may supervise any desk.
  Future<StaffDashboard> dashboard({int? serviceId, int? counterId}) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.staffDashboard,
      query: <String, dynamic>{
        if (serviceId != null) 'serviceId': serviceId,
        if (counterId != null) 'counterId': counterId,
      },
      parse: Parse.object,
    );
    return StaffDashboard.fromJson(response.data);
  }

  Future<StaffStatistics> statistics({String? from, String? to}) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.myStatistics,
      query: <String, dynamic>{
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
      parse: Parse.object,
    );
    return StaffStatistics.fromJson(response.data);
  }

  /// The clerk's own handling history. The envelope nests the rows under
  /// `tickets` so the resolved date range can travel alongside them.
  Future<Paged<Ticket>> handledTickets({
    int page = 1,
    int limit = 20,
    String? status,
    String? from,
    String? to,
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.myHandledTickets,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
      parse: Parse.object,
    );

    final dynamic rows = response.data['tickets'];
    final List<Ticket> tickets = rows is List
        ? rows.whereType<Map<String, dynamic>>().map(Ticket.fromJson).toList(growable: false)
        : const <Ticket>[];

    return Paged<Ticket>(
      items: tickets,
      meta: response.meta ??
          PageMeta(page: page, limit: limit, total: tickets.length, totalPages: 1),
    );
  }

  Future<List<ServiceCounter>> counters({int? serviceId, String? status}) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.counters,
      query: <String, dynamic>{
        if (serviceId != null) 'serviceId': serviceId,
        if (status != null) 'status': status,
      },
      parse: Parse.list,
    );
    return response.data.map(ServiceCounter.fromJson).toList(growable: false);
  }

  Future<StaffCounter> setCounterStatus(int counterId, String status) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.counterStatus(counterId),
      body: <String, dynamic>{'status': status},
      parse: Parse.object,
    );
    return StaffCounter.fromJson(response.data);
  }

  // ── ticket transitions ──────────────────────────────────────────────────
  //
  // All seven answer with the same `{ ticket, queue }` envelope, so the
  // console can repaint its counters from a single round trip.

  Future<TicketActionResult> callNext({required int serviceId, int? counterId}) {
    return _transition(
      ApiEndpoints.callNext,
      body: <String, dynamic>{
        'serviceId': serviceId,
        if (counterId != null) 'counterId': counterId,
      },
    );
  }

  Future<TicketActionResult> call(int ticketId, {int? counterId}) {
    return _transition(
      ApiEndpoints.callTicket(ticketId),
      body: counterId == null ? null : <String, dynamic>{'counterId': counterId},
    );
  }

  Future<TicketActionResult> recall(int ticketId) => _transition(ApiEndpoints.recallTicket(ticketId));

  Future<TicketActionResult> start(int ticketId) => _transition(ApiEndpoints.startTicket(ticketId));

  Future<TicketActionResult> complete(int ticketId) =>
      _transition(ApiEndpoints.completeTicket(ticketId));

  Future<TicketActionResult> skip(int ticketId, {String? reason}) {
    return _transition(
      ApiEndpoints.skipTicket(ticketId),
      body: reason == null || reason.isEmpty ? null : <String, dynamic>{'reason': reason},
    );
  }

  Future<TicketActionResult> noShow(int ticketId) => _transition(ApiEndpoints.noShowTicket(ticketId));

  Future<TicketActionResult> _transition(String path, {Map<String, dynamic>? body}) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.post<Map<String, dynamic>>(
      path,
      body: body,
      parse: Parse.object,
    );
    return TicketActionResult.fromJson(response.data);
  }
}
