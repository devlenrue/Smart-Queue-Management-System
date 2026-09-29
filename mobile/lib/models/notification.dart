import '../core/constants/enums.dart';
import '../core/utils/json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    this.ticketId,
    this.createdAt,
  });

  final int id;
  final String title;
  final String message;
  final NotificationType type;
  final bool isRead;
  final int? ticketId;
  final String? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: Json.asInt(json['id']),
      title: Json.asString(json['title']),
      message: Json.asString(json['message']),
      type: NotificationType.parse(Json.asStringOrNull(json['type'])),
      isRead: Json.asBool(json['isRead']),
      ticketId: Json.asIntOrNull(json['ticketId']),
      createdAt: Json.asStringOrNull(json['createdAt']),
    );
  }

  AppNotification markedRead() {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      isRead: true,
      ticketId: ticketId,
      createdAt: createdAt,
    );
  }
}
