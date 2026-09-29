/// Every path the client calls, in one place, so a backend rename is a
/// one-file change. Paths are relative to the Dio `baseUrl`.
class ApiEndpoints {
  const ApiEndpoints._();

  // auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String me = '/auth/me';
  static const String logout = '/auth/logout';
  static const String changePassword = '/auth/change-password';
  static const String profile = '/profile';

  // services
  static const String services = '/services';
  static const String serviceCategories = '/services/categories';
  static String service(int id) => '/services/$id';
  static String serviceHours(int id) => '/services/$id/hours';
  static String serviceSettings(int id) => '/services/$id/settings';
  static String serviceQueue(int id) => '/services/$id/queue';
  static String joinService(int id) => '/services/$id/queue/join';

  // queues
  static const String queues = '/queues';
  static String queue(int id) => '/queues/$id';
  static String queueStatus(int id) => '/queues/$id/status';
  static String queueMonitor(int id) => '/queues/$id/monitor';
  static String queuePause(int id) => '/queues/$id/pause';
  static String queueResume(int id) => '/queues/$id/resume';
  static String queueClose(int id) => '/queues/$id/close';

  // tickets
  static const String myTickets = '/tickets/my';
  static const String activeTickets = '/tickets/active';
  static const String callNext = '/tickets/next';
  static String ticket(int id) => '/tickets/$id';
  static String ticketPosition(int id) => '/tickets/$id/position';
  static String ticketEvents(int id) => '/tickets/$id/events';
  static String cancelTicket(int id) => '/tickets/$id/cancel';
  static String callTicket(int id) => '/tickets/$id/call';
  static String recallTicket(int id) => '/tickets/$id/recall';
  static String startTicket(int id) => '/tickets/$id/start';
  static String completeTicket(int id) => '/tickets/$id/complete';
  static String skipTicket(int id) => '/tickets/$id/skip';
  static String noShowTicket(int id) => '/tickets/$id/no-show';

  // staff console
  static const String staffDashboard = '/dashboard/staff';
  static const String counters = '/counters';
  static String counterStatus(int id) => '/counters/$id/status';
  /// `me` is accepted by the server, so the client never interpolates its
  /// own user id into a URL it is already authenticated for.
  static const String myStatistics = '/staff/me/statistics';
  static const String myHandledTickets = '/staff/me/tickets';
  static String staffStatistics(int id) => '/staff/$id/statistics';

  // admin console (Phase 7)
  static const String adminDashboard = '/dashboard/admin';
  static const String users = '/users';
  static String user(int id) => '/users/$id';
  static String userStatus(int id) => '/users/$id/status';
  static String userRole(int id) => '/users/$id/role';
  static const String staffRoster = '/staff';
  static String staffMember(int id) => '/staff/$id';
  static String assignStaff(int id) => '/staff/$id/assign';
  static String unassignStaff(int id) => '/staff/$id/unassign';
  static String counter(int id) => '/counters/$id';
  static String counterAssignment(int id) => '/counters/$id/assign';
  static const String systemSettings = '/system/settings';

  // notifications
  static const String notifications = '/notifications';
  static const String unreadCount = '/notifications/unread-count';
  static const String readAll = '/notifications/read-all';
  static String markRead(int id) => '/notifications/$id/read';

  // announcements
  static const String announcements = '/announcements';
  static String announcement(int id) => '/announcements/$id';

  /// The composer's own list, which — unlike the public board — includes
  /// drafts and archived notices. Declared before `/:id` on the server so
  /// "manage" is never parsed as an id.
  static const String manageAnnouncements = '/announcements/manage';
  static String manageAnnouncement(int id) => '/announcements/manage/$id';
  static String publishAnnouncement(int id) => '/announcements/$id/publish';
  static String archiveAnnouncement(int id) => '/announcements/$id/archive';

  // system
  static const String health = '/system/health';
}
