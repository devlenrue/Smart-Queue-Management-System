import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/app_button.dart';

/// Shown while the stored token is checked against `/auth/me`.
///
/// If the server cannot be reached the user is not dumped at the login form
/// — the token might be perfectly good and the Wi-Fi merely down — so this
/// screen offers Retry instead.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);
    final ThemeData theme = Theme.of(context);

    final Failure? restoreError = auth.valueOrNull?.restoreError;
    final bool showRetry = restoreError is NetworkFailure ||
        (auth.hasError && ErrorMapper.fromObject(auth.error!) is NetworkFailure);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: 96,
                width: 96,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.confirmation_number_rounded,
                  size: 48,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(AppConstants.appName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Skip the line. Track your turn.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              if (showRetry) ...<Widget>[
                Icon(Icons.wifi_off_rounded, color: theme.colorScheme.error, size: 28),
                const SizedBox(height: 12),
                Text(
                  restoreError?.userMessage ?? 'Cannot reach the server.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  expanded: false,
                  onPressed: () => ref.read(authControllerProvider.notifier).retryRestore(),
                ),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
