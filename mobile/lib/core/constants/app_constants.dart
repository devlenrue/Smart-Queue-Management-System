/// Tunable values that are not secrets and not server-owned.
class AppConstants {
  const AppConstants._();

  static const String appName = 'SmartQueue';

  /// Overridable at build time:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:5000/api/v1
  ///
  /// The default targets the Android emulator's host loopback. On iOS
  /// simulator or desktop use http://localhost:5000/api/v1.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// How often the live screens re-read the server. The ticket screen is the
  /// fastest because it is the one a customer stares at.
  static const Duration ticketPollInterval = Duration(seconds: 5);
  static const Duration queuePollInterval = Duration(seconds: 10);
  static const Duration unreadPollInterval = Duration(seconds: 30);

  static const int defaultPageSize = 20;

  // storage keys
  static const String tokenKey = 'sq.auth.token';
  static const String userIdKey = 'sq.auth.userId';
  static const String themeModeKey = 'sq.prefs.themeMode';
  static const String pollSecondsKey = 'sq.prefs.pollSeconds';

  // responsive breakpoints (§66)
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1000;
}
