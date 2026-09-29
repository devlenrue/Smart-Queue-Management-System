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

  static String serviceDetailOf(int id) => '/services/$id';
  static String ticketDetailOf(int id) => '/tickets/$id';
  static String queueTrackingOf(int id) => '/tickets/$id/queue';
  static String announcementDetailOf(int id) => '/announcements/$id';
  static String staffTicketOf(int id) => '/staff/queue/ticket/$id';

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

  static bool isStaffRoute(String location) => location.startsWith(staffPrefix);
}
