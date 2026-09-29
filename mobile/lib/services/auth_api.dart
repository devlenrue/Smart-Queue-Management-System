import '../core/constants/api_endpoints.dart';
import '../core/network/api_client.dart';
import '../models/user.dart';

/// Raw HTTP calls for authentication. No caching, no state — that belongs
/// to the repository above it.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<AuthResult> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        'confirmPassword': confirmPassword,
      },
      parse: Parse.object,
    );
    return AuthResult.fromJson(response.data);
  }

  Future<AuthResult> login({required String email, required String password}) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      body: <String, dynamic>{'email': email, 'password': password},
      parse: Parse.object,
    );
    return AuthResult.fromJson(response.data);
  }

  Future<User> me() async {
    final response = await _client.get<Map<String, dynamic>>(ApiEndpoints.me, parse: Parse.object);
    return User.fromJson(response.data);
  }

  Future<void> logout() async {
    await _client.post<void>(ApiEndpoints.logout, parse: Parse.nothing);
  }

  Future<User> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    final response = await _client.put<Map<String, dynamic>>(
      ApiEndpoints.profile,
      body: <String, dynamic>{
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (phone != null) 'phone': phone,
      },
      parse: Parse.object,
    );
    return User.fromJson(response.data);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await _client.post<void>(
      ApiEndpoints.changePassword,
      body: <String, dynamic>{
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      },
      parse: Parse.nothing,
    );
  }
}
