import '../core/constants/enums.dart';
import '../core/utils/json.dart';

/// The full queue snapshot from `GET /queues/:id/status`.
class QueueStatusView {
  const QueueStatusView({
    required this.queueId,
    required this.serviceId,
    required this.serviceName,
    required this.serviceCode,
    required this.queueDate,
    required this.status,
    required this.currentNumber,
    required this.waitingCount,
    required this.servingCount,
    required this.completedToday,
    required this.cancelledToday,
    required this.skippedToday,
    required this.noShowToday,
    required this.ticketsIssuedToday,
    required this.activeCounters,
    required this.averageWaitMinutes,
    required this.averageServiceMinutes,
    required this.estimatedWaitMinutes,
    required this.isAcceptingTickets,
    required this.capacityRemaining,
    this.nowServing,
  });

  final int queueId;
  final int serviceId;
  final String serviceName;
  final String serviceCode;
  final String queueDate;
  final QueueStatus status;
  final int currentNumber;
  final int waitingCount;
  final int servingCount;
  final int completedToday;
  final int cancelledToday;
  final int skippedToday;
  final int noShowToday;
  final int ticketsIssuedToday;
  final int activeCounters;
  final int averageWaitMinutes;
  final int averageServiceMinutes;
  final int estimatedWaitMinutes;
  final bool isAcceptingTickets;
  final int capacityRemaining;
  final String? nowServing;

  factory QueueStatusView.fromJson(Map<String, dynamic> json) {
    return QueueStatusView(
      queueId: Json.asInt(json['queueId']),
      serviceId: Json.asInt(json['serviceId']),
      serviceName: Json.asString(json['serviceName']),
      serviceCode: Json.asString(json['serviceCode']),
      queueDate: Json.asString(json['queueDate']),
      status: QueueStatus.parse(Json.asStringOrNull(json['status'])),
      currentNumber: Json.asInt(json['currentNumber']),
      waitingCount: Json.asInt(json['waitingCount']),
      servingCount: Json.asInt(json['servingCount']),
      completedToday: Json.asInt(json['completedToday']),
      cancelledToday: Json.asInt(json['cancelledToday']),
      skippedToday: Json.asInt(json['skippedToday']),
      noShowToday: Json.asInt(json['noShowToday']),
      ticketsIssuedToday: Json.asInt(json['ticketsIssuedToday']),
      activeCounters: Json.asInt(json['activeCounters']),
      averageWaitMinutes: Json.asInt(json['averageWaitMinutes']),
      averageServiceMinutes: Json.asInt(json['averageServiceMinutes']),
      estimatedWaitMinutes: Json.asInt(json['estimatedWaitMinutes']),
      isAcceptingTickets: Json.asBool(json['isAcceptingTickets']),
      capacityRemaining: Json.asInt(json['capacityRemaining']),
      nowServing: Json.asStringOrNull(json['nowServing']),
    );
  }
}
