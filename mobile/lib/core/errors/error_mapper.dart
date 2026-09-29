import 'package:dio/dio.dart';

import 'failure.dart';

/// Turns anything thrown by the network layer into a [Failure].
///
/// The rule is simple: if the server bothered to write a message, show the
/// server's message; the client only supplies wording when the request never
/// got an answer.
class ErrorMapper {
  const ErrorMapper._();

  static Failure fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return const NetworkFailure(
          message: 'The server took too long to respond. Please try again.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure(
          message: 'The server is taking too long to reply. Please try again.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.cancel:
        return const NetworkFailure(message: 'The request was cancelled.', code: 'CANCELLED');
      case DioExceptionType.badCertificate:
        return const NetworkFailure(
          message: 'The server certificate could not be verified.',
          code: 'BAD_CERTIFICATE',
        );
      case DioExceptionType.badResponse:
        return fromResponse(error.response);
      case DioExceptionType.unknown:
        return const NetworkFailure();
    }
  }

  static Failure fromResponse(Response<dynamic>? response) {
    final int status = response?.statusCode ?? 0;
    final dynamic body = response?.data;

    final Map<String, dynamic> map = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final String? serverMessage = map['message'] is String ? map['message'] as String : null;
    final String? code = map['code'] is String ? map['code'] as String : null;
    final Map<String, String> fields = _parseFieldErrors(map['errors']);

    switch (status) {
      case 400:
        return UnknownFailure(
          message: serverMessage ?? 'That request could not be understood.',
          code: code ?? 'BAD_REQUEST',
          statusCode: 400,
        );
      case 401:
      case 403:
        return AuthFailure(
          message: serverMessage ?? _defaultAuthMessage(status),
          code: code,
          statusCode: status,
        );
      case 404:
        return NotFoundFailure(
          message: serverMessage ?? 'We could not find what you were looking for.',
          code: code ?? 'NOT_FOUND',
        );
      case 409:
        return ConflictFailure(
          message: serverMessage ?? 'That action conflicts with the current state.',
          code: code,
        );
      case 422:
        return ValidationFailure(
          message: serverMessage ?? 'Please check the highlighted fields.',
          code: code ?? 'VALIDATION_ERROR',
          fieldErrors: fields,
        );
      case 429:
        return RateLimitFailure(message: serverMessage ?? 'Too many attempts. Please wait a moment.');
      default:
        if (status >= 500) {
          return ServerFailure(
            message: serverMessage ?? 'Something went wrong on the server. Please try again shortly.',
            code: code,
            statusCode: status,
          );
        }
        return UnknownFailure(message: serverMessage ?? 'Something unexpected happened.', code: code, statusCode: status);
    }
  }

  /// Anything that is not already a Failure — a parse error, a null cast.
  static Failure fromObject(Object error) {
    if (error is Failure) return error;
    if (error is DioException) return fromDioException(error);
    if (error is FormatException) {
      return const UnknownFailure(message: 'The server sent a response we could not read.');
    }
    return const UnknownFailure();
  }

  static String _defaultAuthMessage(int status) {
    return status == 401
        ? 'Your session has ended. Please sign in again.'
        : 'You do not have permission to do that.';
  }

  /// `errors: [{ field, message }]` → `{ field: message }`.
  static Map<String, String> _parseFieldErrors(dynamic raw) {
    if (raw is! List) return const <String, String>{};
    final Map<String, String> result = <String, String>{};
    for (final dynamic entry in raw) {
      if (entry is Map) {
        final Object? field = entry['field'];
        final Object? message = entry['message'];
        if (field is String && message is String && !result.containsKey(field)) {
          result[field] = message;
        }
      }
    }
    return result;
  }
}
