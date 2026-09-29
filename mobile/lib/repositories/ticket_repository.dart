import '../core/network/api_response.dart';
import '../models/ticket.dart';
import '../services/ticket_api.dart';

class TicketRepository {
  const TicketRepository(this._api);

  final TicketApi _api;

  Future<Paged<Ticket>> history({
    int page = 1,
    int limit = 20,
    String? status,
    int? serviceId,
  }) {
    return _api.myTickets(page: page, limit: limit, status: status, serviceId: serviceId);
  }

  Future<List<Ticket>> active() => _api.active();

  /// The dashboard only has room for one; the newest active ticket is the
  /// one the customer is most likely thinking about.
  Future<Ticket?> currentTicket() async {
    final List<Ticket> tickets = await _api.active();
    if (tickets.isEmpty) return null;
    return tickets.first;
  }

  Future<Ticket> byId(int id) => _api.byId(id);

  Future<TicketPosition> position(int id) => _api.position(id);

  Future<List<TicketEvent>> events(int id) => _api.events(id);

  Future<Ticket> cancel(int id, {String? reason}) => _api.cancel(id, reason: reason);
}
