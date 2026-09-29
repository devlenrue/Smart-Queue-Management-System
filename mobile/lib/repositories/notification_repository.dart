import '../core/network/api_response.dart';
import '../models/announcement.dart';
import '../services/notification_api.dart';

class NotificationRepository {
  const NotificationRepository(this._api);

  final NotificationApi _api;

  Future<NotificationPage> list({int page = 1, int limit = 20, bool? isRead, String? type}) {
    return _api.list(page: page, limit: limit, isRead: isRead, type: type);
  }

  Future<int> unreadCount() => _api.unreadCount();

  Future<void> markRead(int id) => _api.markRead(id);

  Future<int> markAllRead() => _api.markAllRead();

  Future<Paged<Announcement>> announcements({int page = 1, int limit = 20, int? serviceId}) {
    return _api.announcements(page: page, limit: limit, serviceId: serviceId);
  }

  Future<Announcement> announcement(int id) => _api.announcement(id);
}
