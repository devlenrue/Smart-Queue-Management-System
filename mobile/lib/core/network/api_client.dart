import 'package:dio/dio.dart';

import '../errors/error_mapper.dart';
import '../errors/failure.dart';
import 'api_response.dart';

/// A thin, typed wrapper over Dio.
///
/// Two jobs: unwrap the `{ success, message, data, meta }` envelope, and
/// guarantee that everything thrown out of here is a [Failure]. Repositories
/// above this line never see a `DioException`.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Dio get dio => _dio;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic data) parse,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.get<dynamic>(path, queryParameters: _clean(query), cancelToken: cancelToken),
      parse,
    );
  }

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required T Function(dynamic data) parse,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.post<dynamic>(path, data: body, queryParameters: _clean(query), cancelToken: cancelToken),
      parse,
    );
  }

  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? body,
    required T Function(dynamic data) parse,
    CancelToken? cancelToken,
  }) {
    return _send<T>(() => _dio.put<dynamic>(path, data: body, cancelToken: cancelToken), parse);
  }

  Future<ApiResponse<T>> patch<T>(
    String path, {
    Object? body,
    required T Function(dynamic data) parse,
    CancelToken? cancelToken,
  }) {
    return _send<T>(() => _dio.patch<dynamic>(path, data: body, cancelToken: cancelToken), parse);
  }

  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic data) parse,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.delete<dynamic>(path, queryParameters: _clean(query), cancelToken: cancelToken),
      parse,
    );
  }

  Future<ApiResponse<T>> _send<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data) parse,
  ) async {
    try {
      final Response<dynamic> response = await request();
      final dynamic body = response.data;

      // 204 No Content, or a server that answered with an empty body.
      if (body == null || (body is String && body.isEmpty)) {
        return ApiResponse<T>(message: '', data: parse(null));
      }

      if (body is! Map<String, dynamic>) {
        throw const UnknownFailure(message: 'The server sent a response we could not read.');
      }

      // A 2xx with success:false should not happen, but if it ever does,
      // trust the envelope over the status line.
      if (body['success'] == false) {
        throw ErrorMapper.fromResponse(response);
      }

      return ApiResponse<T>.fromJson(body, parse);
    } on DioException catch (error) {
      throw ErrorMapper.fromDioException(error);
    } on Failure {
      rethrow;
    } catch (error) {
      throw ErrorMapper.fromObject(error);
    }
  }

  /// Dio serialises nulls as empty query values, which the server's zod
  /// schemas then reject. Strip them instead.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final Map<String, dynamic> cleaned = <String, dynamic>{};
    query.forEach((String key, dynamic value) {
      if (value != null) cleaned[key] = value;
    });
    return cleaned.isEmpty ? null : cleaned;
  }
}

/// Parsers shared by the API classes.
class Parse {
  const Parse._();

  static Map<String, dynamic> object(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const UnknownFailure(message: 'The server sent a response we could not read.');
  }

  static List<Map<String, dynamic>> list(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  static void nothing(dynamic _) {}

  static int integer(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final dynamic value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
