import 'service.dart';
import 'ticket.dart';
import 'model_helpers.dart';

class QueueStatus {
  const QueueStatus({
    required this.service,
    required this.currentServing,
    required this.waitingCount,
    required this.totalActiveTickets,
    required this.averageServiceMinutes,
    required this.tickets,
    this.myTicket,
    required this.peopleAhead,
    this.currentPosition,
    required this.estimatedWaitMinutes,
  });

  final ServiceModel service;
  final Ticket? currentServing;
  final Ticket? myTicket;
  final int waitingCount;
  final int totalActiveTickets;
  final double averageServiceMinutes;
  final List<Ticket> tickets;
  final int peopleAhead;
  final int? currentPosition;
  final int estimatedWaitMinutes;

  bool get isNearTurn =>
      myTicket?.status == 'waiting' && peopleAhead >= 2 && peopleAhead <= 3;

  factory QueueStatus.fromJson(Map<String, dynamic> json) {
    return QueueStatus(
      service: ServiceModel.fromJson(json['service'] as Map<String, dynamic>),
      currentServing: json['currentServing'] == null
          ? null
          : Ticket.fromJson(json['currentServing'] as Map<String, dynamic>),
      myTicket: json['myTicket'] == null
          ? null
          : Ticket.fromJson(json['myTicket'] as Map<String, dynamic>),
      waitingCount: asInt(json['waitingCount']),
      totalActiveTickets: asInt(json['totalActiveTickets']),
      averageServiceMinutes: asDouble(json['averageServiceMinutes']),
      tickets: (json['tickets'] as List<dynamic>)
          .map((item) => Ticket.fromJson(item as Map<String, dynamic>))
          .toList(),
      peopleAhead: asInt(json['peopleAhead']),
      currentPosition: asNullableInt(json['currentPosition']),
      estimatedWaitMinutes: asInt(json['estimatedWaitMinutes']),
    );
  }
}
