import 'package:flutter/foundation.dart';

import '../models/api_exception.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api);

  final ApiClient _api;

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  Future<bool> login(String email, String password) async {
    return _authenticate(() => _api.login(email.trim(), password));
  }

  Future<bool> register(
    String fullName,
    String email,
    String password,
  ) async {
    return _authenticate(
      () => _api.register(fullName.trim(), email.trim(), password),
    );
  }

  Future<bool> _authenticate(Future<AuthResult> Function() action) async {
    _setLoading(true);
    _error = null;
    try {
      final result = await action();
      _api.token = result.token;
      _user = result.user;
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Unable to connect to the server.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void logout() {
    _api.token = null;
    _user = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
