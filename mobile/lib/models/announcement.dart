import '../core/utils/json.dart';

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.isGlobal,
    this.serviceId,
    this.serviceName,
    this.serviceCode,
    this.authorName,
    this.publishedAt,
    this.expiresAt,
  });

  final int id;
  final String title;
  final String content;
  final bool isGlobal;
  final int? serviceId;
  final String? serviceName;
  final String? serviceCode;
  final String? authorName;
  final String? publishedAt;
  final String? expiresAt;

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: Json.asInt(json['id']),
      title: Json.asString(json['title']),
      content: Json.asString(json['content']),
      isGlobal: Json.asBool(json['isGlobal'], true),
      serviceId: Json.asIntOrNull(json['serviceId']),
      serviceName: Json.asStringOrNull(json['serviceName']),
      serviceCode: Json.asStringOrNull(json['serviceCode']),
      authorName: Json.asStringOrNull(json['authorName']),
      publishedAt: Json.asStringOrNull(json['publishedAt']),
      expiresAt: Json.asStringOrNull(json['expiresAt']),
    );
  }

  String get scopeLabel => isGlobal ? 'Everyone' : (serviceName ?? 'Service');
}
