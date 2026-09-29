import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/user.dart';
import '../../models/user_detail.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../repositories/admin_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import 'admin_shell.dart';
import 'widgets/user_status_chip.dart';

/// One account in full: who they are, what they have done, where they are
/// posted, and the three things an administrator can do about it.
class UserDetailScreen extends ConsumerWidget {
  const UserDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserDetail> async = ref.watch(adminUserProvider(userId));

    return AdminPage(
      title: async.valueOrNull?.fullName ?? 'User',
      subtitle: async.valueOrNull?.user.email,
      onRefresh: () async => ref.invalidate(adminUserProvider(userId)),
      body: async.when(
        loading: () => const SkeletonList(count: 3),
        error: (Object error, StackTrace _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(adminUserProvider(userId)),
        ),
        data: (UserDetail detail) => ListView(
          padding: Responsive.pagePadding(context),
          children: <Widget>[
            _Identity(detail: detail),
            const SizedBox(height: 12),
            _Activity(detail: detail),
            if (detail.posting != null) ...<Widget>[
              const SizedBox(height: 12),
              _Posting(detail: detail),
            ],
            const SizedBox(height: 12),
            _Actions(detail: detail),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.detail});

  final UserDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final User user = detail.user;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 26,
                child: Text(Formatters.initials(user.firstName, user.lastName)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(user.fullName, style: theme.textTheme.titleMedium),
                    Text(
                      user.role.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              UserStatusChip(status: user.status, dense: false),
            ],
          ),
          const Divider(height: 24),
          _Field(label: 'Email', value: user.email),
          _Field(label: 'Phone', value: user.phone),
          _Field(label: 'Joined', value: Formatters.dateTimeFromIso(user.createdAt)),
          _Field(
            label: 'Last seen',
            value: detail.activity.lastActivityAt == null
                ? 'No activity yet'
                : Formatters.relativeFromIso(detail.activity.lastActivityAt),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.detail});

  final UserDetail detail;

  @override
  Widget build(BuildContext context) {
    final UserActivity activity = detail.activity;
    final int columns = Responsive.isCompact(context) ? 2 : 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Activity', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: <Widget>[
            DashboardStatCard(
              key: const Key('admin-user-tickets'),
              label: 'Tickets taken',
              value: '${activity.totalTickets}',
              icon: Icons.confirmation_number_outlined,
            ),
            DashboardStatCard(
              label: 'Completed',
              value: '${activity.completed}',
              icon: Icons.task_alt_rounded,
              caption: '${activity.completionRate}% of all visits',
            ),
            DashboardStatCard(
              label: 'Cancelled',
              value: '${activity.cancelled}',
              icon: Icons.cancel_outlined,
            ),
            DashboardStatCard(
              label: 'Live now',
              value: '${activity.active}',
              icon: Icons.hourglass_bottom_rounded,
              caption: '${activity.noShow} no-shows',
            ),
          ],
        ),
      ],
    );
  }
}

class _Posting extends StatelessWidget {
  const _Posting({required this.detail});

  final UserDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Icon(Icons.desk_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Currently posted', style: theme.textTheme.labelMedium),
                Text(detail.posting!.label, style: theme.textTheme.bodyMedium),
                Text(
                  'Since ${Formatters.dateTimeFromIso(detail.posting!.assignedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status, role and deletion.
///
/// Which of the three appear depends on who is looking: an ordinary admin
/// may suspend a customer or a clerk, and nothing else. The server enforces
/// the same rules — this only avoids showing a button that could only 403.
class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.detail});

  final UserDetail detail;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(adminUserProvider(widget.detail.id));
      showSuccessSnackBar(context, success);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(UserStatus status) {
    return _run(
      () => ref.read(adminActionProvider.notifier).setUserStatus(widget.detail.id, status),
      '${widget.detail.fullName} is now ${status.name}.',
    );
  }

  Future<void> _setRole(UserRole role) async {
    final bool losingStaff = widget.detail.role == UserRole.staff && role != UserRole.staff;
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Change role?',
      message: losingStaff
          ? '${widget.detail.fullName} will become ${role.label.toLowerCase()} and will be '
              'released from their counter.'
          : '${widget.detail.fullName} will become ${role.label.toLowerCase()}.',
      confirmLabel: 'Change role',
    );
    if (!confirmed) return;
    await _run(
      () => ref.read(adminActionProvider.notifier).setUserRole(widget.detail.id, role),
      '${widget.detail.fullName} is now ${role.label.toLowerCase()}.',
    );
  }

  Future<void> _delete() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete account?',
      message: '${widget.detail.fullName} and their ticket history will be removed. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminActionProvider.notifier).deleteUser(widget.detail.id);
      if (!mounted) return;
      showSuccessSnackBar(context, '${widget.detail.fullName} was deleted.');
      context.go(RoutePaths.adminUsers);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final User? me = ref.watch(currentUserProvider);
    final bool allowed = me != null &&
        AdminRepository.canManage(actor: me.role, target: widget.detail.user, actorId: me.id);
    final List<UserRole> roles =
        me == null ? const <UserRole>[] : AdminRepository.assignableRolesFor(me.role);

    if (!allowed) {
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                me != null && me.id == widget.detail.id
                    ? 'This is your own account. Use Profile to change it.'
                    : 'You do not have permission to change this account.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final UserStatus status = widget.detail.status;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Administration', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (status != UserStatus.suspended)
                FilledButton.tonalIcon(
                  key: const Key('admin-user-suspend'),
                  onPressed: _busy ? null : () => _setStatus(UserStatus.suspended),
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Suspend'),
                ),
              if (status != UserStatus.active)
                FilledButton.tonalIcon(
                  key: const Key('admin-user-activate'),
                  onPressed: _busy ? null : () => _setStatus(UserStatus.active),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Reinstate'),
                ),
              if (status != UserStatus.inactive)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _setStatus(UserStatus.inactive),
                  icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
                  label: const Text('Deactivate'),
                ),
            ],
          ),
          if (roles.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            Text('Role', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final UserRole role in roles)
                  ChoiceChip(
                    key: Key('admin-user-role-${role.wire}'),
                    label: Text(role.label),
                    selected: widget.detail.role == role,
                    onSelected: _busy || widget.detail.role == role
                        ? null
                        : (bool _) => _setRole(role),
                  ),
              ],
            ),
            const Divider(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('admin-user-delete'),
                onPressed: _busy ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete account'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
