import '../models/queue.dart';
import '../models/ticket.dart';
import '../services/queue_api.dart';

class QueueRepository {
  const QueueRepository(this._api);

  final QueueApi _api;

  Future<QueueStatusView> status(int queueId) => _api.status(queueId);

  Future<QueueStatusView> forService(int serviceId) => _api.forService(serviceId);

  Future<QueueMonitor> monitor(int queueId) => _api.monitor(queueId);

  Future<JoinResult> join(int serviceId) => _api.join(serviceId);
}
