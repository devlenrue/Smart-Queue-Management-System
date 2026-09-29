import '../core/constants/enums.dart';
import '../core/utils/json.dart';
import 'staff_member.dart';
import 'user.dart';

/// What an account has actually done — the half of `GET /users/:id` that the
/// user-detail screen exists to show.
class UserActivity {
  const UserActivity({
    required this.totalTickets,
    required this.completed,
    required this.cancelled,
    required this.noShow,
    required this.active,
    this.lastActivityAt,
  });

  final int totalTickets;
  final int completed;
  final int cancelled;
  final int noShow;
  final int active;
  final String? lastActivityAt;

  factory UserActivity.fromJson(Map<String, dynamic> json) {
    return UserActivity(
      totalTickets: Json.asInt(json['totalTickets']),
      completed: Json.asInt(json['completed']),
      cancelled: Json.asInt(json['cancelled']),
      noShow: Json.asInt(json['noShow']),
      active: Json.asInt(json['active']),
      lastActivityAt: Json.asStringOrNull(json['lastActivityAt']),
    );
  }

  static const UserActivity empty = UserActivity(
    totalTickets: 0,
    completed: 0,
    cancelled: 0,
    noShow: 0,
    active: 0,
  );

  /// Completed as a percentage of everything ever taken. Zero rather than
  /// NaN for an account that has never joined a queue.
  int get completionRate =>
      totalTickets == 0 ? 0 : ((completed / totalTickets) * 100).round();
}

/// `GET /users/:id` — the account, its activity, and its posting if it has one.
class UserDetail {
  const UserDetail({
    required this.user,
    required this.activity,
    this.posting,
    this.updatedAt,
  });

  final User user;
  final UserActivity activity;
  final RosterPosting? posting;
  final String? updatedAt;

  int get id => user.id;
  String get fullName => user.fullName;
  UserRole get role => user.role;
  UserStatus get status => user.status;

  factory UserDetail.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? posting = Json.asMap(json['posting']);
    final Map<String, dynamic>? activity = Json.asMap(json['activity']);
    return UserDetail(
      user: User.fromJson(json),
      activity: activity == null ? UserActivity.empty : UserActivity.fromJson(activity),
      posting: posting == null ? null : RosterPosting.fromJson(posting),
      updatedAt: Json.asStringOrNull(json['updatedAt']),
    );
  }
}
