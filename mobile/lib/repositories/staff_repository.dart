import '../core/constants/enums.dart';
import '../core/network/api_response.dart';
import '../models/counter.dart';
import '../models/staff_dashboard.dart';
import '../models/staff_statistics.dart';
import '../models/ticket.dart';
import '../services/staff_api.dart';

/// The staff console's data source.
///
/// The console has exactly one interesting rule of its own: which actions a
/// ticket currently permits. That lives here, next to the calls it guards,
/// rather than being re-derived by every button.
class StaffRepository {
  const StaffRepository(this._api);

  final StaffApi _api;

  Future<StaffDashboard> dashboard({int? serviceId, int? counterId}) =>
      _api.dashboard(serviceId: serviceId, counterId: counterId);

  Future<StaffStatistics> statistics({String? from, String? to}) =>
      _api.statistics(from: from, to: to);

  Future<Paged<Ticket>> handledTickets({
    int page = 1,
    int limit = 20,
    String? status,
    String? from,
    String? to,
  }) {
    return _api.handledTickets(page: page, limit: limit, status: status, from: from, to: to);
  }

  Future<List<ServiceCounter>> counters({int? serviceId, String? status}) =>
      _api.counters(serviceId: serviceId, status: status);

  Future<StaffCounter> setCounterStatus(int counterId, CounterStatus status) =>
      _api.setCounterStatus(counterId, status.wire);

  Future<TicketActionResult> callNext({required int serviceId, int? counterId}) =>
      _api.callNext(serviceId: serviceId, counterId: counterId);

  Future<TicketActionResult> call(int ticketId, {int? counterId}) =>
      _api.call(ticketId, counterId: counterId);

  Future<TicketActionResult> recall(int ticketId) => _api.recall(ticketId);

  Future<TicketActionResult> start(int ticketId) => _api.start(ticketId);

  Future<TicketActionResult> complete(int ticketId) => _api.complete(ticketId);

  Future<TicketActionResult> skip(int ticketId, {String? reason}) =>
      _api.skip(ticketId, reason: reason);

  Future<TicketActionResult> noShow(int ticketId) => _api.noShow(ticketId);

  /// Which transitions the server would accept for a ticket in this state —
  /// the client half of docs/queue-engine.md §1.1.
  ///
  /// The server is still the authority; this only decides which buttons to
  /// show, so a clerk is never offered an action that can only 409.
  static Set<StaffAction> actionsFor(TicketStatus status) {
    switch (status) {
      case TicketStatus.waiting:
        return const <StaffAction>{StaffAction.call, StaffAction.skip};
      case TicketStatus.called:
        return const <StaffAction>{
          StaffAction.start,
          StaffAction.recall,
          StaffAction.skip,
          StaffAction.noShow,
        };
      case TicketStatus.serving:
        return const <StaffAction>{StaffAction.complete};
      case TicketStatus.completed:
      case TicketStatus.cancelled:
      case TicketStatus.skipped:
      case TicketStatus.noShow:
        return const <StaffAction>{};
    }
  }
}

/// The seven things a clerk can do to a ticket.
enum StaffAction {
  call,
  recall,
  start,
  complete,
  skip,
  noShow;

  String get label {
    switch (this) {
      case StaffAction.call:
        return 'Call';
      case StaffAction.recall:
        return 'Call again';
      case StaffAction.start:
        return 'Start serving';
      case StaffAction.complete:
        return 'Complete';
      case StaffAction.skip:
        return 'Skip';
      case StaffAction.noShow:
        return 'No-show';
    }
  }

  /// Past tense, for the confirmation snackbar.
  String get pastTense {
    switch (this) {
      case StaffAction.call:
        return 'called';
      case StaffAction.recall:
        return 'called again';
      case StaffAction.start:
        return 'started';
      case StaffAction.complete:
        return 'completed';
      case StaffAction.skip:
        return 'skipped';
      case StaffAction.noShow:
        return 'marked as a no-show';
    }
  }

  /// Skipping and no-show end the visit without serving the customer, so
  /// both ask first.
  bool get needsConfirmation => this == StaffAction.skip || this == StaffAction.noShow;
}
