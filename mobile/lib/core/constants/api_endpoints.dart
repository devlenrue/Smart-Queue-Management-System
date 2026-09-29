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

  // notifications
  static const String notifications = '/notifications';
  static const String unreadCount = '/notifications/unread-count';
  static const String readAll = '/notifications/read-all';
  static String markRead(int id) => '/notifications/$id/read';

  // announcements
  static const String announcements = '/announcements';
  static String announcement(int id) => '/announcements/$id';

  // system
  static const String health = '/system/health';
}
