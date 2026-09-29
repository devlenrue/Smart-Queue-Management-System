import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

/// The JWT lives in the platform keystore, never in shared preferences.
///
/// Wrapped in an interface so tests can substitute an in-memory version
/// without needing a platform channel.
abstract class SecureStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<int?> readUserId();
  Future<void> writeUserId(int id);
  Future<void> clear();
}

class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: AppConstants.tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: AppConstants.tokenKey, value: token);

  @override
  Future<int?> readUserId() async {
    final String? raw = await _storage.read(key: AppConstants.userIdKey);
    return raw == null ? null : int.tryParse(raw);
  }

  @override
  Future<void> writeUserId(int id) =>
      _storage.write(key: AppConstants.userIdKey, value: id.toString());

  @override
  Future<void> clear() async {
    await _storage.delete(key: AppConstants.tokenKey);
    await _storage.delete(key: AppConstants.userIdKey);
  }
}

/// Used by widget tests, and by the web build where the keystore is absent.
class InMemorySecureStorage implements SecureStorage {
  String? _token;
  int? _userId;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<int?> readUserId() async => _userId;

  @override
  Future<void> writeUserId(int id) async => _userId = id;

  @override
  Future<void> clear() async {
    _token = null;
    _userId = null;
  }
}
