import 'package:flutter/material.dart';

import '../core/errors/error_mapper.dart';
import '../core/errors/failure.dart';
import 'app_button.dart';

/// The one error view. It renders a [Failure]'s message — which is already
/// human-readable — and only offers Retry when retrying could help.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Failure failure = ErrorMapper.fromObject(error);

    final IconData icon = switch (failure) {
      NetworkFailure() => Icons.wifi_off_rounded,
      AuthFailure() => Icons.lock_outline_rounded,
      NotFoundFailure() => Icons.search_off_rounded,
      ConflictFailure() => Icons.error_outline_rounded,
      RateLimitFailure() => Icons.hourglass_disabled_rounded,
      _ => Icons.cloud_off_rounded,
    };

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(failure.userMessage, style: theme.textTheme.bodySmall)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.colorScheme.error),
            ),
            const SizedBox(height: 20),
            Text('Something went wrong', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              failure.userMessage,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (failure.code != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                failure.code!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 24),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a [Failure] as a snackbar. Used for action errors, where the page
/// itself is fine and only the tap failed.
void showFailureSnackBar(BuildContext context, Object error) {
  final Failure failure = ErrorMapper.fromObject(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure.userMessage),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
