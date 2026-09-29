/// Every route in one place, with helpers for the parameterised ones so no
/// screen ever builds a path by string concatenation.
class RoutePaths {
  const RoutePaths._();

  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // customer shell tabs
  static const String home = '/home';
  static const String services = '/services';
  static const String tickets = '/tickets';
  static const String notifications = '/notifications';
  static const String profile = '/profile';

  // detail routes
  static const String serviceDetail = '/services/:id';
  static const String ticketDetail = '/tickets/:id';
  static const String queueTracking = '/tickets/:id/queue';
  static const String announcements = '/announcements';
  static const String announcementDetail = '/announcements/:id';
  static const String settings = '/settings';
  static const String about = '/about';

  // staff console (§20). A separate namespace so the guard can keep a
  // customer out of it with one prefix check.
  static const String staffHome = '/staff/console';
  static const String staffQueue = '/staff/queue';
  static const String staffHistory = '/staff/history';
  static const String staffStats = '/staff/statistics';
  static const String staffProfile = '/staff/profile';

  // admin console (§2.4). Its own namespace for the same reason /staff has
  // one: the guard needs a single prefix check per role.
  static const String adminHome = '/admin/dashboard';
  static const String adminServices = '/admin/services';
  static const String adminServiceNew = '/admin/services/new';
  static const String adminServiceEdit = '/admin/services/:id/edit';
  static const String adminCounters = '/admin/counters';
  static const String adminStaff = '/admin/staff';
  static const String adminUsers = '/admin/users';
  static const String adminUserDetail = '/admin/users/:id';
  static const String adminQueues = '/admin/queues';
  static const String adminQueueBoard = '/admin/queues/:serviceId';
  static const String adminReports = '/admin/reports';
  static const String adminAnnouncements = '/admin/announcements';
  static const String adminAnnouncementNew = '/admin/announcements/new';
  static const String adminAnnouncementEdit = '/admin/announcements/:id/edit';
  static const String adminSettings = '/admin/settings';

  static String serviceDetailOf(int id) => '/services/$id';
  static String ticketDetailOf(int id) => '/tickets/$id';
  static String queueTrackingOf(int id) => '/tickets/$id/queue';
  static String announcementDetailOf(int id) => '/announcements/$id';
  static String staffTicketOf(int id) => '/staff/queue/ticket/$id';

  static String adminServiceEditOf(int id) => '/admin/services/$id/edit';
  static String adminUserOf(int id) => '/admin/users/$id';
  static String adminQueueBoardOf(int serviceId) => '/admin/queues/$serviceId';
  static String adminAnnouncementEditOf(int id) => '/admin/announcements/$id/edit';

  /// Routes reachable without a session.
  static const Set<String> publicRoutes = <String>{
    splash,
    login,
    register,
    forgotPassword,
  };

  /// Reachable by anyone signed in, whatever their role.
  static const Set<String> sharedRoutes = <String>{settings, about};

  /// The staff namespace. Everything under it needs `staff` or better.
  static const String staffPrefix = '/staff';

  /// The admin namespace. Everything under it needs `admin` or better; the
  /// two pages that also need `super_admin` say so on the server.
  static const String adminPrefix = '/admin';

  static bool isStaffRoute(String location) => location.startsWith(staffPrefix);

  static bool isAdminRoute(String location) => location.startsWith(adminPrefix);
}
