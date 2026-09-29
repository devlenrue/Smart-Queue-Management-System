import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../core/network/api_response.dart';
import '../core/utils/json.dart';
import '../models/announcement.dart';
import '../models/notification.dart';

/// The inbox response carries the unread badge count alongside the page, so
/// opening the list refreshes the badge for free.
class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.meta,
    required this.unreadCount,
  });

  final List<AppNotification> items;
  final PageMeta meta;
  final int unreadCount;
}

class NotificationApi {
  const NotificationApi(this._client);

  final ApiClient _client;

  Future<NotificationPage> list({
    int page = 1,
    int limit = 20,
    bool? isRead,
    String? type,
  }) async {
    final ApiResponse<Map<String, dynamic>> response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.notifications,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (isRead != null) 'isRead': isRead,
        if (type != null) 'type': type,
      },
      parse: Parse.object,
    );

    final Map<String, dynamic> data = response.data;
    return NotificationPage(
      items: Json.mapList(data['notifications'], AppNotification.fromJson),
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: 0, totalPages: 1),
      unreadCount: Json.asInt(data['unreadCount']),
    );
  }

  Future<int> unreadCount() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.unreadCount,
      parse: Parse.object,
    );
    return Json.asInt(response.data['count']);
  }

  Future<void> markRead(int id) async {
    await _client.patch<void>(ApiEndpoints.markRead(id), parse: Parse.nothing);
  }

  /// Returns the number of rows that changed.
  Future<int> markAllRead() async {
    final response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.readAll,
      parse: Parse.object,
    );
    return Json.asInt(response.data['updated']);
  }

  Future<Paged<Announcement>> announcements({
    int page = 1,
    int limit = 20,
    int? serviceId,
  }) async {
    final ApiResponse<List<Map<String, dynamic>>> response =
        await _client.get<List<Map<String, dynamic>>>(
      ApiEndpoints.announcements,
      query: <String, dynamic>{
        'page': page,
        'limit': limit,
        if (serviceId != null) 'serviceId': serviceId,
      },
      parse: Parse.list,
    );

    return Paged<Announcement>(
      items: response.data.map(Announcement.fromJson).toList(growable: false),
      meta: response.meta ?? PageMeta(page: page, limit: limit, total: response.data.length, totalPages: 1),
    );
  }

  Future<Announcement> announcement(int id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.announcement(id),
      parse: Parse.object,
    );
    return Announcement.fromJson(response.data);
  }
}
