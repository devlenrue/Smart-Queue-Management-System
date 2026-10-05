import 'model_helpers.dart';
import 'service.dart';
import 'ticket.dart';

class AdminQueueStatus {
  const AdminQueueStatus({
    required this.service,
    required this.currentServing,
    required this.waitingCount,
    required this.totalActiveTickets,
    required this.averageServiceMinutes,
    required this.tickets,
  });

  final ServiceModel service;
  final Ticket? currentServing;
  final int waitingCount;
  final int totalActiveTickets;
  final double averageServiceMinutes;
  final List<Ticket> tickets;

  factory AdminQueueStatus.fromJson(Map<String, dynamic> json) {
    return AdminQueueStatus(
      service: ServiceModel.fromJson(json['service'] as Map<String, dynamic>),
      currentServing: json['currentServing'] == null
          ? null
          : Ticket.fromJson(json['currentServing'] as Map<String, dynamic>),
      waitingCount: asInt(json['waitingCount']),
      totalActiveTickets: asInt(json['totalActiveTickets']),
      averageServiceMinutes: asDouble(json['averageServiceMinutes']),
      tickets: (json['tickets'] as List<dynamic>)
          .map((item) => Ticket.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
