import '../core/errors/failure.dart';
import '../core/storage/secure_storage.dart';
import '../models/user.dart';
import '../services/auth_api.dart';

/// Owns the session: the API calls plus the token that outlives them.
///
/// This is the only place that writes the token, so there is exactly one
/// answer to "am I signed in?".
class AuthRepository {
  AuthRepository({required AuthApi api, required SecureStorage storage})
      : _api = api,
        _storage = storage;

  final AuthApi _api;
  final SecureStorage _storage;

  Future<User> login({required String email, required String password}) async {
    final AuthResult result = await _api.login(email: email.trim(), password: password);
    await _persist(result);
    return result.user;
  }

  Future<User> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
  }) async {
    final AuthResult result = await _api.register(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      phone: phone.trim(),
      password: password,
      confirmPassword: confirmPassword,
    );
    await _persist(result);
    return result.user;
  }

  /// Called on app start. Returns null when there is no usable session.
  ///
  /// A stored token is not trusted on its own — it is verified against
  /// `/auth/me`, which also catches a user who was suspended since last time.
  Future<User?> restoreSession() async {
    final String? token = await _storage.readToken();
    if (token == null || token.isEmpty) return null;

    try {
      return await _api.me();
    } on AuthFailure {
      await _storage.clear();
      return null;
    } on NetworkFailure {
      // Offline at launch is not a reason to sign someone out; let the
      // caller decide, and keep the token.
      rethrow;
    }
  }

  /// Best-effort: the local session is cleared even if the server call
  /// fails, because the user asked to be signed out.
  Future<void> logout() async {
    try {
      await _api.logout();
    } on Failure {
      // ignored on purpose
    } finally {
      await _storage.clear();
    }
  }

  Future<User> updateProfile({String? firstName, String? lastName, String? phone}) {
    return _api.updateProfile(
      firstName: firstName?.trim(),
      lastName: lastName?.trim(),
      phone: phone?.trim(),
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _api.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  Future<void> _persist(AuthResult result) async {
    await _storage.writeToken(result.token);
    await _storage.writeUserId(result.user.id);
  }
}
