import 'package:dio/dio.dart';

import '../storage/secure_storage.dart';

/// Attaches the bearer token to every request that needs one.
///
/// A 401 means the token is dead — the interceptor clears it and calls
/// [onUnauthenticated] so the router can send the user to /login. It does not
/// navigate itself; routing is not the network layer's job.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required SecureStorage storage,
    required Future<void> Function() onUnauthenticated,
  })  : _storage = storage,
        _onUnauthenticated = onUnauthenticated;

  final SecureStorage _storage;
  final Future<void> Function() _onUnauthenticated;

  /// Endpoints that must not carry a token — sending a stale one to /login
  /// would be harmless but confusing in the server log.
  static const List<String> _public = <String>[
    '/auth/login',
    '/auth/register',
  ];

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final bool isPublic = _public.any((String path) => options.path.endsWith(path));
    if (!isPublic) {
      final String? token = await _storage.readToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final int? status = err.response?.statusCode;
    final Object? code = err.response?.data is Map ? (err.response!.data as Map)['code'] : null;

    // A failed sign-in is a 401 too, but it must not wipe an existing session.
    final bool isLoginAttempt = err.requestOptions.path.endsWith('/auth/login');
    final bool tokenIsDead = status == 401 && !isLoginAttempt && code != 'INVALID_CREDENTIALS';

    if (tokenIsDead) {
      await _storage.clear();
      await _onUnauthenticated();
    }
    handler.next(err);
  }
}

/// Logs requests in debug builds only. Never logs the Authorization header.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({required this.enabled, this.log});

  final bool enabled;
  final void Function(String message)? log;

  void _write(String message) {
    if (!enabled) return;
    (log ?? _noop)(message);
  }

  static void _noop(String _) {}

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _write('→ ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _write('← ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _write('✗ ${err.response?.statusCode ?? err.type.name} ${err.requestOptions.path}');
    handler.next(err);
  }
}
