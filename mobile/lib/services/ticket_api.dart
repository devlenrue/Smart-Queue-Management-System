import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../models/ticket.dart';

class TicketApi {
  const TicketApi(this._client);

  final ApiClient _client;

  Future<Paged<Ticket>> myTickets({
    int page = 1,
    int limit = 20,
    String? status,
    int? serviceId,
  }) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.myTickets,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (serviceId != null) 'serviceId': serviceId,
      },
      parse: Parse.list,
    );

    return Paged<Ticket>(
      items: response.data.map(Ticket.fromJson).toList(growable: false),
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: response.data.length, totalPages: 1),
    );
  }

  Future<List<Ticket>> active() async {
    final response = await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.activeTickets,
      parse: Parse.list,
    );
    return response.data.map(Ticket.fromJson).toList(growable: false);
  }

  Future<Ticket> byId(int id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.ticket(id),
      parse: Parse.object,
    );
    return Ticket.fromJson(response.data);
  }

  Future<TicketPosition> position(int id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.ticketPosition(id),
      parse: Parse.object,
    );
    return TicketPosition.fromJson(response.data);
  }

  Future<List<TicketEvent>> events(int id) async {
    final response = await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.ticketEvents(id),
      parse: Parse.list,
    );
    return response.data.map(TicketEvent.fromJson).toList(growable: false);
  }

  Future<Ticket> cancel(int id, {String? reason}) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.cancelTicket(id),
      body: reason == null || reason.isEmpty ? null : <String, dynamic>{'reason': reason},
      parse: Parse.object,
    );
    // The cancel endpoint answers with the ticket, sometimes wrapped
    // alongside queue counters like the staff transitions do.
    final Map<String, dynamic> data = response.data;
    final dynamic nested = data['ticket'];
    return Ticket.fromJson(nested is Map<String, dynamic> ? nested : data);
  }
}
