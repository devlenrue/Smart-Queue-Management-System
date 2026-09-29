import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/errors/error_mapper.dart';
import 'package:smartqueue/core/errors/failure.dart';

/// The contract between the server's error envelope and the UI.
///
/// Every status the API can return is exercised here, because the mapper is
/// the only thing standing between a raw `DioException` and the screen.
void main() {
  final RequestOptions request = RequestOptions(path: '/queues/1/join');

  DioException badResponse(int status, Map<String, dynamic> body) {
    return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: status,
        data: body,
      ),
    );
  }

  group('transport errors', () {
    test('a connection error becomes a NetworkFailure', () {
      final Failure failure = ErrorMapper.fromDioException(
        DioException(requestOptions: request, type: DioExceptionType.connectionError),
      );
      expect(failure, isA<NetworkFailure>());
      expect(failure.isRetryable, isTrue);
    });

    test('a timeout is a NetworkFailure tagged TIMEOUT', () {
      final Failure failure = ErrorMapper.fromDioException(
        DioException(requestOptions: request, type: DioExceptionType.connectionTimeout),
      );
      expect(failure, isA<NetworkFailure>());
      expect(failure.code, 'TIMEOUT');
    });
  });

  group('server responses', () {
    test('401 becomes an AuthFailure that requires signing out', () {
      final Failure failure = ErrorMapper.fromDioException(
        badResponse(401, <String, dynamic>{
          'success': false,
          'message': 'Your session has ended.',
          'code': 'TOKEN_EXPIRED',
        }),
      );
      expect(failure, isA<AuthFailure>());
      expect((failure as AuthFailure).requiresSignOut, isTrue);
      expect(failure.userMessage, 'Your session has ended.');
    });

    test('403 is an AuthFailure that does not sign the user out', () {
      final Failure failure = ErrorMapper.fromDioException(
        badResponse(403, <String, dynamic>{
          'success': false,
          'message': 'You do not have permission to do that.',
          'code': 'FORBIDDEN',
        }),
      );
      expect(failure, isA<AuthFailure>());
      expect((failure as AuthFailure).requiresSignOut, isFalse);
    });

    test('409 DUPLICATE_ACTIVE_TICKET is recognised as such', () {
      final Failure failure = ErrorMapper.fromDioException(
        badResponse(409, <String, dynamic>{
          'success': false,
          'message': 'You already have an active ticket for this service.',
          'code': 'DUPLICATE_ACTIVE_TICKET',
        }),
      );
      expect(failure, isA<ConflictFailure>());
      expect((failure as ConflictFailure).isDuplicateTicket, isTrue);
      expect(failure.isQueueFull, isFalse);
    });

    test('409 QUEUE_FULL is recognised as such', () {
      final ConflictFailure failure = ErrorMapper.fromDioException(
        badResponse(409, <String, dynamic>{
          'success': false,
          'message': 'This queue is full.',
          'code': 'QUEUE_FULL',
        }),
      ) as ConflictFailure;
      expect(failure.isQueueFull, isTrue);
    });

    test('422 keeps the per-field messages', () {
      final Failure failure = ErrorMapper.fromDioException(
        badResponse(422, <String, dynamic>{
          'success': false,
          'message': 'Validation failed',
          'code': 'VALIDATION_ERROR',
          'errors': <Map<String, String>>[
            <String, String>{'field': 'email', 'message': 'Email is already registered'},
            <String, String>{'field': 'phone', 'message': 'Phone is already registered'},
          ],
        }),
      );
      expect(failure, isA<ValidationFailure>());
      final ValidationFailure validation = failure as ValidationFailure;
      expect(validation.fieldErrors['email'], 'Email is already registered');
      expect(validation.fieldErrors['phone'], 'Phone is already registered');
      expect(validation.firstFieldError, 'Email is already registered');
    });

    test('422 with no errors array still maps cleanly', () {
      final ValidationFailure failure = ErrorMapper.fromDioException(
        badResponse(422, <String, dynamic>{'success': false, 'message': 'Validation failed'}),
      ) as ValidationFailure;
      expect(failure.fieldErrors, isEmpty);
      expect(failure.firstFieldError, isNull);
    });

    test('404 becomes a NotFoundFailure', () {
      expect(
        ErrorMapper.fromDioException(
          badResponse(404, <String, dynamic>{'success': false, 'message': 'Ticket not found'}),
        ),
        isA<NotFoundFailure>(),
      );
    });

    test('429 becomes a RateLimitFailure', () {
      expect(
        ErrorMapper.fromDioException(
          badResponse(429, <String, dynamic>{'success': false, 'message': 'Slow down'}),
        ),
        isA<RateLimitFailure>(),
      );
    });

    test('500 becomes a retryable ServerFailure', () {
      final Failure failure = ErrorMapper.fromDioException(
        badResponse(500, <String, dynamic>{'success': false, 'message': 'Internal error'}),
      );
      expect(failure, isA<ServerFailure>());
      expect(failure.isRetryable, isTrue);
    });

    test('a body with no message still yields readable wording', () {
      final Failure failure = ErrorMapper.fromDioException(badResponse(500, <String, dynamic>{}));
      expect(failure.userMessage, isNotEmpty);
      expect(failure.userMessage, isNot(contains('null')));
    });
  });

  group('fromObject', () {
    test('passes an existing Failure straight through', () {
      const Failure original = ConflictFailure(message: 'nope', code: 'QUEUE_PAUSED');
      expect(identical(ErrorMapper.fromObject(original), original), isTrue);
    });

    test('wraps anything unrecognised without leaking internals', () {
      final Failure failure = ErrorMapper.fromObject(StateError('boom'));
      expect(failure, isA<UnknownFailure>());
      expect(failure.userMessage, isNot(contains('boom')));
    });
  });
}
