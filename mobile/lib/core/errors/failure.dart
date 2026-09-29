/// The only error type the UI ever sees.
///
/// A `DioException`, a socket error and a 422 body all become one of these,
/// so no widget has to know that Dio exists and no raw server payload can
/// reach the screen (§63).
sealed class Failure implements Exception {
  const Failure({
    required this.message,
    this.code,
    this.statusCode,
    this.fieldErrors = const <String, String>{},
  });

  /// Already phrased for a human — the server writes these carefully.
  final String message;

  /// The machine-readable server code, e.g. `QUEUE_FULL`. Null for transport
  /// errors, which never reached the server.
  final String? code;

  final int? statusCode;

  /// Field name → message, for painting errors next to the right input.
  final Map<String, String> fieldErrors;

  String get userMessage => message;

  /// True when trying again might plausibly work.
  bool get isRetryable => this is NetworkFailure || this is ServerFailure;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// No connection, DNS failure, or a timeout — the request never landed.
class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'Cannot reach the server. Check your connection and try again.',
    super.code,
  });
}

/// 5xx — the server is at fault, not the user.
class ServerFailure extends Failure {
  const ServerFailure({
    super.message = 'Something went wrong on the server. Please try again shortly.',
    super.code,
    super.statusCode,
  });
}

/// 422 — carries the per-field messages.
class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.code = 'VALIDATION_ERROR',
    super.statusCode = 422,
    super.fieldErrors,
  });

  /// The first field message, useful for a snackbar when there is no form.
  String? get firstFieldError => fieldErrors.values.isEmpty ? null : fieldErrors.values.first;
}

/// 409 — a business rule said no. `code` identifies which one.
class ConflictFailure extends Failure {
  const ConflictFailure({
    required super.message,
    super.code,
    super.statusCode = 409,
  });

  bool get isDuplicateTicket => code == 'DUPLICATE_ACTIVE_TICKET';
  bool get isQueueFull => code == 'QUEUE_FULL';
}

/// 401 / 403.
class AuthFailure extends Failure {
  const AuthFailure({
    required super.message,
    super.code,
    super.statusCode,
  });

  /// A token problem means the session must be torn down; a permission
  /// problem does not.
  bool get requiresSignOut =>
      statusCode == 401 || code == 'TOKEN_EXPIRED' || code == 'TOKEN_REVOKED';
}

/// 404.
class NotFoundFailure extends Failure {
  const NotFoundFailure({
    super.message = 'We could not find what you were looking for.',
    super.code = 'NOT_FOUND',
    super.statusCode = 404,
  });
}

/// 429.
class RateLimitFailure extends Failure {
  const RateLimitFailure({
    super.message = 'Too many attempts. Please wait a moment and try again.',
    super.code = 'RATE_LIMITED',
    super.statusCode = 429,
  });
}

/// Anything we did not anticipate. Never shows a stack trace to the user.
class UnknownFailure extends Failure {
  const UnknownFailure({
    super.message = 'Something unexpected happened. Please try again.',
    super.code,
    super.statusCode,
  });
}
