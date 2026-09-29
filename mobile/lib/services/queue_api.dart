import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../models/queue.dart';
import '../models/ticket.dart';

class QueueApi {
  const QueueApi(this._client);

  final ApiClient _client;

  /// Every queue open today — the picker on the admin monitor board.
  Future<List<QueueStatusView>> list({String? date, int? serviceId, String? status}) async {
    final response = await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.queues,
      query: <String, dynamic>{
        if (date != null) 'date': date,
        if (serviceId != null) 'serviceId': serviceId,
        if (status != null) 'status': status,
      },
      parse: Parse.list,
    );
    return response.data.map(QueueStatusView.fromJson).toList(growable: false);
  }

  Future<QueueStatusView> status(int queueId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.queueStatus(queueId),
      parse: Parse.object,
    );
    return QueueStatusView.fromJson(response.data);
  }

  Future<QueueStatusView> forService(int serviceId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.serviceQueue(serviceId),
      parse: Parse.object,
    );
    return QueueStatusView.fromJson(response.data);
  }

  /// The staff board. Gated to staff and above on the server, so the
  /// customer app never reaches for it.
  Future<QueueMonitor> monitor(int queueId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.queueMonitor(queueId),
      parse: Parse.object,
    );
    return QueueMonitor.fromJson(response.data);
  }

  /// Rule 1 lives on the server: a second active ticket for the same service
  /// comes back as 409 DUPLICATE_ACTIVE_TICKET, which the error mapper turns
  /// into a [ConflictFailure] for the UI to explain.
  Future<JoinResult> join(int serviceId) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.joinService(serviceId),
      parse: Parse.object,
    );
    return JoinResult.fromJson(response.data);
  }
}
