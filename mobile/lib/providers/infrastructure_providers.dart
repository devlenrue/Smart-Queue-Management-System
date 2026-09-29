import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/network/api_client.dart';
import '../core/network/interceptors.dart';
import '../core/storage/prefs_storage.dart';
import '../core/storage/secure_storage.dart';
import '../repositories/admin_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/queue_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/staff_repository.dart';
import '../repositories/ticket_repository.dart';
import '../services/admin_api.dart';
import '../services/auth_api.dart';
import '../services/notification_api.dart';
import '../services/queue_api.dart';
import '../services/service_api.dart';
import '../services/staff_api.dart';
import '../services/ticket_api.dart';

/// Wiring only: storage → Dio → api → repository. Every one of these is
/// overridable in a test with a single `overrides:` entry.

// ── storage ───────────────────────────────────────────────────────────────

final Provider<SecureStorage> secureStorageProvider = Provider<SecureStorage>((Ref ref) {
  return FlutterSecureStorageAdapter();
});

/// Overridden in `main()` once `SharedPreferences` has loaded, because it
/// cannot be created synchronously.
final Provider<PrefsStorage> prefsStorageProvider = Provider<PrefsStorage>((Ref ref) {
  throw UnimplementedError('prefsStorageProvider must be overridden in main()');
});

// ── session expiry signal ─────────────────────────────────────────────────

/// Bumped by [AuthInterceptor] when the server rejects the token.
///
/// A counter rather than a bool, so two rejections in a row still notify;
/// and a plain provider rather than a direct call into the auth controller,
/// which would make the network layer depend on the feature layer.
class SessionExpiryNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void signal() => state = state + 1;
}

final NotifierProvider<SessionExpiryNotifier, int> sessionExpiryProvider =
    NotifierProvider<SessionExpiryNotifier, int>(SessionExpiryNotifier.new);

// ── network ───────────────────────────────────────────────────────────────

final Provider<Dio> dioProvider = Provider<Dio>((Ref ref) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // Let the interceptors and ErrorMapper decide what an error is;
      // Dio should hand us every response, including 4xx.
      validateStatus: (int? status) => status != null && status < 500,
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      storage: ref.watch(secureStorageProvider),
      onUnauthenticated: () async => ref.read(sessionExpiryProvider.notifier).signal(),
    ),
  );
  dio.interceptors.add(LoggingInterceptor(enabled: kDebugMode, log: debugPrint));

  ref.onDispose(dio.close);
  return dio;
});

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  return ApiClient(ref.watch(dioProvider));
});

// ── api classes ───────────────────────────────────────────────────────────

final Provider<AuthApi> authApiProvider =
    Provider<AuthApi>((Ref ref) => AuthApi(ref.watch(apiClientProvider)));

final Provider<ServiceApi> serviceApiProvider =
    Provider<ServiceApi>((Ref ref) => ServiceApi(ref.watch(apiClientProvider)));

final Provider<QueueApi> queueApiProvider =
    Provider<QueueApi>((Ref ref) => QueueApi(ref.watch(apiClientProvider)));

final Provider<TicketApi> ticketApiProvider =
    Provider<TicketApi>((Ref ref) => TicketApi(ref.watch(apiClientProvider)));

final Provider<NotificationApi> notificationApiProvider =
    Provider<NotificationApi>((Ref ref) => NotificationApi(ref.watch(apiClientProvider)));

final Provider<StaffApi> staffApiProvider =
    Provider<StaffApi>((Ref ref) => StaffApi(ref.watch(apiClientProvider)));

final Provider<AdminApi> adminApiProvider =
    Provider<AdminApi>((Ref ref) => AdminApi(ref.watch(apiClientProvider)));

// ── repositories ──────────────────────────────────────────────────────────

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return AuthRepository(
    api: ref.watch(authApiProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

final Provider<ServiceRepository> serviceRepositoryProvider = Provider<ServiceRepository>((Ref ref) {
  return ServiceRepository(ref.watch(serviceApiProvider));
});

final Provider<QueueRepository> queueRepositoryProvider = Provider<QueueRepository>((Ref ref) {
  return QueueRepository(ref.watch(queueApiProvider));
});

final Provider<TicketRepository> ticketRepositoryProvider = Provider<TicketRepository>((Ref ref) {
  return TicketRepository(ref.watch(ticketApiProvider));
});

final Provider<NotificationRepository> notificationRepositoryProvider =
    Provider<NotificationRepository>((Ref ref) {
  return NotificationRepository(ref.watch(notificationApiProvider));
});

final Provider<StaffRepository> staffRepositoryProvider = Provider<StaffRepository>((Ref ref) {
  return StaffRepository(ref.watch(staffApiProvider));
});

final Provider<AdminRepository> adminRepositoryProvider = Provider<AdminRepository>((Ref ref) {
  return AdminRepository(ref.watch(adminApiProvider));
});

// ── preferences ───────────────────────────────────────────────────────────

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(prefsStorageProvider).readThemeMode();

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(prefsStorageProvider).writeThemeMode(mode);
  }
}

final NotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// How often live screens re-read. Exposed in Settings (§54) so a marker can
/// see polling slow down and speed up on a real device.
class PollIntervalNotifier extends Notifier<Duration> {
  @override
  Duration build() => ref.watch(prefsStorageProvider).readPollInterval();

  Future<void> set(Duration interval) async {
    state = interval;
    await ref.read(prefsStorageProvider).writePollInterval(interval);
  }
}

final NotifierProvider<PollIntervalNotifier, Duration> pollIntervalProvider =
    NotifierProvider<PollIntervalNotifier, Duration>(PollIntervalNotifier.new);
