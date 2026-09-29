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

/// Where a notice is in its life: composed, on the board, or retired.
enum AnnouncementStatus {
  draft,
  published,
  archived;

  static AnnouncementStatus parse(String? value) {
    switch (value) {
      case 'published':
        return AnnouncementStatus.published;
      case 'archived':
        return AnnouncementStatus.archived;
      default:
        return AnnouncementStatus.draft;
    }
  }

  String get wire => name;

  String get label {
    switch (this) {
      case AnnouncementStatus.draft:
        return 'Draft';
      case AnnouncementStatus.published:
        return 'Published';
      case AnnouncementStatus.archived:
        return 'Archived';
    }
  }
}

/// The composer's view of an announcement (`/announcements/manage`).
///
/// The public board only ever returns published notices, so [Announcement]
/// has no status field. The admin list needs one, and wraps rather than
/// subclasses so the customer screens keep the narrower type.
class ManagedAnnouncement {
  const ManagedAnnouncement({required this.announcement, required this.status});

  final Announcement announcement;
  final AnnouncementStatus status;

  int get id => announcement.id;
  String get title => announcement.title;
  String get content => announcement.content;
  bool get isGlobal => announcement.isGlobal;
  int? get serviceId => announcement.serviceId;
  String? get serviceName => announcement.serviceName;
  String? get authorName => announcement.authorName;
  String? get publishedAt => announcement.publishedAt;
  String? get expiresAt => announcement.expiresAt;
  String get scopeLabel => announcement.scopeLabel;

  bool get isPublished => status == AnnouncementStatus.published;

  factory ManagedAnnouncement.fromJson(Map<String, dynamic> json) {
    return ManagedAnnouncement(
      announcement: Announcement.fromJson(json),
      status: AnnouncementStatus.parse(Json.asStringOrNull(json['status'])),
    );
  }
}
