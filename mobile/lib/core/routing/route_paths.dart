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

  static String serviceDetailOf(int id) => '/services/$id';
  static String ticketDetailOf(int id) => '/tickets/$id';
  static String queueTrackingOf(int id) => '/tickets/$id/queue';
  static String announcementDetailOf(int id) => '/announcements/$id';

  /// Routes reachable without a session.
  static const Set<String> publicRoutes = <String>{
    splash,
    login,
    register,
    forgotPassword,
  };
}
