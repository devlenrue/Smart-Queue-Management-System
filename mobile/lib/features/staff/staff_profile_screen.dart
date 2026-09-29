import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/counter.dart';
import '../../models/staff_dashboard.dart';
import '../../models/user.dart';
import '../../providers/auth_providers.dart';
import '../../providers/staff_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';

/// Read-only: who you are and where you are posted.
///
/// Reassignment is an administrator's job (§53), so this screen shows the
/// assignment rather than offering to change it.
class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Sign out?',
      message: 'Your counter stays as it is. Sign in again to keep working.',
      confirmLabel: 'Sign out',
      isDestructive: true,
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final User? user = ref.watch(currentUserProvider);
    final StaffDashboard? dashboard = ref.watch(staffDashboardProvider).valueOrNull;

    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                child: Text(
                  Formatters.initials(user.firstName, user.lastName),
                  style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(user.fullName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(user.role.label),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
                      labelStyle:
                          theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Posting', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: dashboard?.assignment == null
                ? Text(
                    'You are not assigned to a service yet. An administrator can post you to one.',
                    style: theme.textTheme.bodyMedium,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Line(
                        label: 'Service',
                        value:
                            '${dashboard!.assignment!.serviceName} (${dashboard.assignment!.serviceCode})',
                      ),
                      _Line(
                        label: 'Counter',
                        value: dashboard.assignment!.counterName ?? 'Not assigned to a counter',
                      ),
                      _Line(
                        label: 'Since',
                        value: Formatters.dateTimeFromIso(dashboard.assignment!.assignedAt),
                      ),
                      if (dashboard.counter != null) ...<Widget>[
                        const SizedBox(height: 10),
                        StatusBadge.counter(context, dashboard.counter!.status),
                      ],
                    ],
                  ),
          ),
          if (dashboard?.service != null) ...<Widget>[
            const SizedBox(height: 24),
            Text('Counters at ${dashboard!.service!.name}', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            const _CounterRoster(),
          ],
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            subtitle: const Text('Theme and how often screens refresh'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(RoutePaths.settings),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About SmartQueue'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(RoutePaths.about),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => _logout(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Who else is on duty. Read-only — moving people between counters is an
/// administrator's job (§53).
class _CounterRoster extends ConsumerWidget {
  const _CounterRoster();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<ServiceCounter>> async = ref.watch(serviceCountersProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      ),
      error: (Object error, StackTrace _) => ErrorState(error: error, compact: true),
      data: (List<ServiceCounter> counters) {
        if (counters.isEmpty) {
          return Text('No counters are set up yet.', style: theme.textTheme.bodySmall);
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: <Widget>[
              for (final ServiceCounter counter in counters)
                ListTile(
                  key: Key('roster-counter-${counter.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(counter.name, style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    counter.isStaffed
                        ? '${counter.staffName}${counter.currentTicket == null ? '' : ' · ${counter.currentTicket}'}'
                        : 'Nobody on duty',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: StatusBadge.counter(context, counter.status, dense: true),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
