import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/enums.dart';
import '../core/errors/error_mapper.dart';
import '../core/errors/failure.dart';
import '../models/user.dart';
import '../repositories/auth_repository.dart';
import 'infrastructure_providers.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// The session, as the router and every screen sees it.
class AuthState {
  const AuthState({required this.status, this.user, this.restoreError});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut({Failure? error})
      : this(status: AuthStatus.unauthenticated, restoreError: error);
  const AuthState.signedIn(User user) : this(status: AuthStatus.authenticated, user: user);

  final AuthStatus status;
  final User? user;

  /// Set when the app could not reach the server at launch while a token
  /// was present — the splash screen offers Retry instead of dumping the
  /// user back at the login form.
  final Failure? restoreError;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
  UserRole get role => user?.role ?? UserRole.customer;
}

/// Holds the session and performs every action that changes it.
///
/// Screens call these methods and catch [Failure] to render an inline
/// message; the controller never shows UI itself.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    // A 401 from anywhere in the app tears the session down here.
    ref.listen<int>(sessionExpiryProvider, (int? previous, int next) {
      if (previous != null && next > previous) {
        state = const AsyncValue<AuthState>.data(AuthState.signedOut());
      }
    });

    try {
      final User? user = await _repository.restoreSession();
      return user == null ? const AuthState.signedOut() : AuthState.signedIn(user);
    } on Failure catch (failure) {
      // Offline at launch: stay signed out but remember why.
      return AuthState.signedOut(error: failure);
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue<AuthState>.loading();
    try {
      final User user = await _repository.login(email: email, password: password);
      state = AsyncValue<AuthState>.data(AuthState.signedIn(user));
    } catch (error) {
      // The form shows the message; the session itself is simply not started.
      state = const AsyncValue<AuthState>.data(AuthState.signedOut());
      throw ErrorMapper.fromObject(error);
    }
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    try {
      final User user = await _repository.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
        confirmPassword: confirmPassword,
      );
      state = AsyncValue<AuthState>.data(AuthState.signedIn(user));
    } catch (error) {
      state = const AsyncValue<AuthState>.data(AuthState.signedOut());
      throw ErrorMapper.fromObject(error);
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AsyncValue<AuthState>.data(AuthState.signedOut());
  }

  /// Re-runs the launch restore, for the splash screen's Retry button.
  Future<void> retryRestore() async {
    state = const AsyncValue<AuthState>.loading();
    state = await AsyncValue.guard(() async {
      final User? user = await _repository.restoreSession();
      return user == null ? const AuthState.signedOut() : AuthState.signedIn(user);
    });
  }

  Future<void> updateProfile({String? firstName, String? lastName, String? phone}) async {
    try {
      final User updated = await _repository.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
      );
      state = AsyncValue<AuthState>.data(AuthState.signedIn(updated));
    } catch (error) {
      throw ErrorMapper.fromObject(error);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
    } catch (error) {
      throw ErrorMapper.fromObject(error);
    }
  }
}

final AsyncNotifierProvider<AuthController, AuthState> authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience reads, so widgets do not repeat `.valueOrNull?.user`.

final Provider<User?> currentUserProvider = Provider<User?>((Ref ref) {
  return ref.watch(authControllerProvider).valueOrNull?.user;
});

final Provider<bool> isAuthenticatedProvider = Provider<bool>((Ref ref) {
  return ref.watch(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
});

final Provider<UserRole> currentRoleProvider = Provider<UserRole>((Ref ref) {
  return ref.watch(currentUserProvider)?.role ?? UserRole.customer;
});
