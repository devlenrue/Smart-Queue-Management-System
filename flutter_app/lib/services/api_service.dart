import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/admin_queue_status.dart';
import '../models/api_exception.dart';
import '../models/queue_status.dart';
import '../models/service.dart';
import '../models/ticket.dart';
import '../models/user.dart';

class AuthResult {
  const AuthResult({required this.user, required this.token});

  final User user;
  final String token;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  // Android emulators use 10.0.2.2 to reach the host computer.
  // Override for iOS simulator or a physical device with:
  // flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:3000/api
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api',
  );

  final http.Client _client;
  String? _token;

  String get baseUrl => defaultBaseUrl.endsWith('/')
      ? defaultBaseUrl.substring(0, defaultBaseUrl.length - 1)
      : defaultBaseUrl;
  set token(String? value) => _token = value;

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        );
        break;
      case 'DELETE':
        response = await _client.delete(uri, headers: headers);
        break;
      default:
        throw const ApiException('Unsupported HTTP method.');
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message']?.toString()
          : null;
      throw ApiException(
        message ?? 'Request failed with status ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<AuthResult> login(String email, String password) async {
    final json = await _request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    ) as Map<String, dynamic>;
    return AuthResult(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
    );
  }

  Future<AuthResult> register(
    String fullName,
    String email,
    String password,
  ) async {
    final json = await _request(
      'POST',
      '/auth/register',
      body: {
        'fullName': fullName,
        'email': email,
        'password': password,
      },
    ) as Map<String, dynamic>;
    return AuthResult(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
    );
  }

  Future<List<ServiceModel>> getServices() async {
    final json = await _request('GET', '/services') as Map<String, dynamic>;
    return (json['services'] as List<dynamic>)
        .map((item) => ServiceModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Ticket> joinQueue(int serviceId) async {
    final json = await _request(
      'POST',
      '/queues/join',
      body: {'serviceId': serviceId},
    ) as Map<String, dynamic>;
    return Ticket.fromJson(json['ticket'] as Map<String, dynamic>);
  }

  Future<QueueStatus> getQueueStatus(int serviceId) async {
    final json = await _request(
      'GET',
      '/queues/service/$serviceId/status',
    ) as Map<String, dynamic>;
    return QueueStatus.fromJson(json);
  }

  Future<List<Ticket>> getHistory({int limit = 50}) async {
    final json = await _request(
      'GET',
      '/queues/history?limit=$limit',
    ) as Map<String, dynamic>;
    return (json['tickets'] as List<dynamic>)
        .map((item) => Ticket.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Ticket> cancelTicket(int ticketId) async {
    final json = await _request(
      'POST',
      '/queues/$ticketId/cancel',
    ) as Map<String, dynamic>;
    return Ticket.fromJson(json['ticket'] as Map<String, dynamic>);
  }

  Future<AdminQueueStatus> getAdminQueue(int serviceId) async {
    final json = await _request(
      'GET',
      '/admin/queues/$serviceId',
    ) as Map<String, dynamic>;
    return AdminQueueStatus.fromJson(json);
  }

  Future<Ticket> callNext(int serviceId) async {
    final json = await _request(
      'POST',
      '/admin/queues/$serviceId/call-next',
    ) as Map<String, dynamic>;
    return Ticket.fromJson(json['ticket'] as Map<String, dynamic>);
  }

  Future<Ticket> completeTicket(int ticketId) async {
    final json = await _request(
      'POST',
      '/admin/tickets/$ticketId/complete',
    ) as Map<String, dynamic>;
    return Ticket.fromJson(json['ticket'] as Map<String, dynamic>);
  }

  Future<Ticket> skipTicket(int ticketId) async {
    final json = await _request(
      'POST',
      '/admin/tickets/$ticketId/skip',
    ) as Map<String, dynamic>;
    return Ticket.fromJson(json['ticket'] as Map<String, dynamic>);
  }

  Future<ServiceModel> addService({
    required String name,
    String? description,
    required double averageServiceMinutes,
  }) async {
    final json = await _request(
      'POST',
      '/services',
      body: {
        'name': name,
        'description': description,
        'averageServiceMinutes': averageServiceMinutes,
      },
    ) as Map<String, dynamic>;
    return ServiceModel.fromJson(json['service'] as Map<String, dynamic>);
  }

  Future<ServiceModel> removeService(int serviceId) async {
    final json = await _request(
      'DELETE',
      '/services/$serviceId',
    ) as Map<String, dynamic>;
    return ServiceModel.fromJson(json['service'] as Map<String, dynamic>);
  }
}
