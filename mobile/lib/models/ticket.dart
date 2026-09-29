import '../core/constants/enums.dart';
import '../core/utils/json.dart';
import 'counter.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
  });

  final int id;
  final String fullName;
  final String phone;
  final String email;

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    return CustomerSummary(
      id: Json.asInt(json['id']),
      fullName: Json.asString(json['fullName']),
      phone: Json.asString(json['phone']),
      email: Json.asString(json['email']),
    );
  }
}

/// A queue ticket. `FIN-023`.
class Ticket {
  const Ticket({
    required this.id,
    required this.ticketNumber,
    required this.sequenceNumber,
    required this.status,
    required this.queueId,
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    required this.queueDate,
    required this.waitedMinutes,
    this.counter,
    this.customer,
    this.estimatedWaitMinutes,
    this.serviceMinutes,
    this.joinedAt,
    this.calledAt,
    this.serviceStartedAt,
    this.completedAt,
    this.cancelledAt,
  });

  final int id;
  final String ticketNumber;
  final int sequenceNumber;
  final TicketStatus status;
  final int queueId;
  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final String queueDate;
  final int waitedMinutes;
  final CounterSummary? counter;

  /// Only present on staff and admin reads.
  final CustomerSummary? customer;

  final int? estimatedWaitMinutes;
  final int? serviceMinutes;
  final String? joinedAt;
  final String? calledAt;
  final String? serviceStartedAt;
  final String? completedAt;
  final String? cancelledAt;

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: Json.asInt(json['id']),
      ticketNumber: Json.asString(json['ticketNumber']),
      sequenceNumber: Json.asInt(json['sequenceNumber']),
      status: TicketStatus.parse(Json.asStringOrNull(json['status'])),
      queueId: Json.asInt(json['queueId']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      queueDate: Json.asString(json['queueDate']),
      waitedMinutes: Json.asInt(json['waitedMinutes']),
      counter: Json.asMap(json['counter']) == null
          ? null
          : CounterSummary.fromJson(json['counter'] as Map<String, dynamic>),
      customer: Json.asMap(json['customer']) == null
          ? null
          : CustomerSummary.fromJson(json['customer'] as Map<String, dynamic>),
      estimatedWaitMinutes: Json.asIntOrNull(json['estimatedWaitMinutes']),
      serviceMinutes: Json.asIntOrNull(json['serviceMinutes']),
      joinedAt: Json.asStringOrNull(json['joinedAt']),
      calledAt: Json.asStringOrNull(json['calledAt']),
      serviceStartedAt: Json.asStringOrNull(json['serviceStartedAt']),
      completedAt: Json.asStringOrNull(json['completedAt']),
      cancelledAt: Json.asStringOrNull(json['cancelledAt']),
    );
  }

  bool get isActive => status.isActive;
  bool get canCancel => status.canCancel;
}

/// `GET /tickets/:id/position` — the payload the ticket screen polls.
class TicketPosition {
  const TicketPosition({
    required this.ticketId,
    required this.ticketNumber,
    required this.status,
    required this.peopleAhead,
    required this.estimatedWaitMinutes,
    required this.activeCounters,
    required this.queueStatus,
    this.position,
    this.nowServing,
    this.counter,
    this.updatedAt,
  });

  final int ticketId;
  final String ticketNumber;
  final TicketStatus status;

  /// Null once the ticket is no longer waiting.
  final int? position;

  final int peopleAhead;
  final int estimatedWaitMinutes;
  final int activeCounters;
  final QueueStatus queueStatus;
  final String? nowServing;
  final CounterSummary? counter;
  final String? updatedAt;

  factory TicketPosition.fromJson(Map<String, dynamic> json) {
    return TicketPosition(
      ticketId: Json.asInt(json['ticketId']),
      ticketNumber: Json.asString(json['ticketNumber']),
      status: TicketStatus.parse(Json.asStringOrNull(json['status'])),
      position: Json.asIntOrNull(json['position']),
      peopleAhead: Json.asInt(json['peopleAhead']),
      estimatedWaitMinutes: Json.asInt(json['estimatedWaitMinutes']),
      activeCounters: Json.asInt(json['activeCounters'], 1),
      queueStatus: QueueStatus.parse(Json.asStringOrNull(json['queueStatus'])),
      nowServing: Json.asStringOrNull(json['nowServing']),
      counter: Json.asMap(json['counter']) == null
          ? null
          : CounterSummary.fromJson(json['counter'] as Map<String, dynamic>),
      updatedAt: Json.asStringOrNull(json['updatedAt']),
    );
  }

  bool get isBeingCalled => status == TicketStatus.called;
  bool get isFinished => status.isFinished;
}

/// One row of the ticket's audit timeline.
class TicketEvent {
  const TicketEvent({
    required this.id,
    required this.eventType,
    this.description,
    this.actorName,
    this.createdAt,
  });

  final int id;
  final String eventType;
  final String? description;
  final String? actorName;
  final String? createdAt;

  factory TicketEvent.fromJson(Map<String, dynamic> json) {
    return TicketEvent(
      id: Json.asInt(json['id']),
      eventType: Json.asString(json['eventType']),
      description: Json.asStringOrNull(json['description']),
      actorName: Json.asStringOrNull(json['actorName']),
      createdAt: Json.asStringOrNull(json['createdAt']),
    );
  }

  /// Human wording for the timeline, independent of the server's phrasing.
  String get label {
    switch (eventType) {
      case 'joined':
        return 'Joined the queue';
      case 'called':
        return 'Called to a counter';
      case 'recalled':
        return 'Called again';
      case 'service_started':
        return 'Service started';
      case 'completed':
        return 'Service completed';
      case 'cancelled':
        return 'Ticket cancelled';
      case 'skipped':
        return 'Ticket skipped';
      case 'no_show':
        return 'Marked as a no-show';
      default:
        return eventType.replaceAll('_', ' ');
    }
  }
}

/// What `POST /services/:id/queue/join` returns: the new ticket plus its
/// first position reading, so the ticket screen can paint immediately.
class JoinResult {
  const JoinResult({required this.ticket, required this.position});

  final Ticket ticket;
  final TicketPosition position;

  factory JoinResult.fromJson(Map<String, dynamic> json) {
    return JoinResult(
      ticket: Ticket.fromJson(Json.asMap(json['ticket']) ?? const <String, dynamic>{}),
      position: TicketPosition.fromJson(Json.asMap(json['position']) ?? const <String, dynamic>{}),
    );
  }
}

/// What every staff transition returns.
class TicketActionResult {
  const TicketActionResult({
    required this.ticket,
    required this.waitingCount,
    required this.completedToday,
    this.nowServing,
  });

  final Ticket ticket;
  final int waitingCount;
  final int completedToday;
  final String? nowServing;

  factory TicketActionResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> queue = Json.asMap(json['queue']) ?? const <String, dynamic>{};
    return TicketActionResult(
      ticket: Ticket.fromJson(Json.asMap(json['ticket']) ?? const <String, dynamic>{}),
      waitingCount: Json.asInt(queue['waitingCount']),
      completedToday: Json.asInt(queue['completedToday']),
      nowServing: Json.asStringOrNull(queue['nowServing']),
    );
  }
}
