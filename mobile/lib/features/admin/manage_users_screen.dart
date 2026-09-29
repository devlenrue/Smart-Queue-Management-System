import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/user.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/paged_state.dart';
import '../../repositories/admin_repository.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import 'admin_shell.dart';
import 'widgets/user_status_chip.dart';

/// Every account in the system (§9, §40), with search and the two filters
/// that matter: role and status.
///
/// Suspending someone is the one action offered inline, because it is the
/// one an administrator performs in a hurry. Everything else — role changes,
/// deletion — lives behind the row, on the detail screen, where the
/// consequences can be spelled out.
class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      ref.read(adminUsersProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<User>> async = ref.watch(adminUsersProvider);
    final UserFilter filter = ref.watch(userFilterProvider);
    final User? me = ref.watch(currentUserProvider);

    return AdminPage(
      title: 'Users',
      subtitle: async.valueOrNull == null ? null : '${async.valueOrNull!.meta.total} accounts',
      onRefresh: () => ref.read(adminUsersProvider.notifier).refresh(),
      body: Column(
        children: <Widget>[
          _Filters(search: _search, filter: filter),
          Expanded(
            child: async.when(
              loading: () => const SkeletonList(count: 6),
              error: (Object error, StackTrace _) =>
                  ErrorState(error: error, onRetry: () => ref.invalidate(adminUsersProvider)),
              data: (PagedState<User> page) => ListView(
                controller: _scroll,
                padding: Responsive.pagePadding(context),
                children: <Widget>[
                  AppDataTable<User>(
                    shrinkWrap: true,
                    rows: page.items,
                    rowKey: (User user) => Key('admin-user-${user.id}'),
                    onRowTap: (User user) => context.go(RoutePaths.adminUserOf(user.id)),
                    emptyTitle: 'No accounts match',
                    emptyMessage: filter.isEmpty
                        ? 'No accounts have been created yet.'
                        : 'Try a different search or clear the filters.',
                    emptyIcon: Icons.person_search_outlined,
                    cardFooter: (User user) => _RowActions(user: user, me: me),
                    columns: <AppDataColumn<User>>[
                      AppDataColumn<User>(
                        label: 'Name',
                        primary: true,
                        cell: (User user) => Text(user.fullName),
                      ),
                      AppDataColumn<User>(
                        label: 'Email',
                        cell: (User user) => Text(user.email),
                      ),
                      AppDataColumn<User>(
                        label: 'Phone',
                        cell: (User user) => Text(user.phone),
                      ),
                      AppDataColumn<User>(
                        label: 'Role',
                        cell: (User user) => Text(user.role.label),
                      ),
                      AppDataColumn<User>(
                        label: 'Status',
                        cell: (User user) => UserStatusChip(status: user.status),
                      ),
                      AppDataColumn<User>(
                        label: 'Joined',
                        cell: (User user) =>
                            Text(Formatters.dayMonth(Formatters.parse(user.createdAt))),
                      ),
                      AppDataColumn<User>(
                        label: '',
                        showOnCard: false,
                        cell: (User user) => _RowActions(user: user, me: me),
                      ),
                    ],
                  ),
                  if (page.isLoadingMore) const LoadMoreIndicator(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.search, required this.filter});

  final TextEditingController search;
  final UserFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserFilterNotifier notifier = ref.read(userFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: <Widget>[
          TextField(
            key: const Key('admin-user-search'),
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: notifier.search,
            decoration: InputDecoration(
              hintText: 'Search name, email or phone',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        search.clear();
                        notifier.search(null);
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final UserRole role in UserRole.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: Key('admin-user-role-${role.wire}'),
                      label: Text(role.label),
                      selected: filter.role == role,
                      onSelected: (bool on) => notifier.role(on ? role : null),
                    ),
                  ),
                const SizedBox(width: 8),
                for (final UserStatus status in UserStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: Key('admin-user-status-${status.name}'),
                      label: Text(_statusLabel(status)),
                      selected: filter.status == status,
                      onSelected: (bool on) => notifier.status(on ? status : null),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(UserStatus status) {
    switch (status) {
      case UserStatus.active:
        return 'Active';
      case UserStatus.inactive:
        return 'Inactive';
      case UserStatus.suspended:
        return 'Suspended';
    }
  }
}

/// Suspend / reinstate, inline. Nothing else: role changes and deletion are
/// consequential enough to deserve the detail screen.
class _RowActions extends ConsumerStatefulWidget {
  const _RowActions({required this.user, required this.me});

  final User user;
  final User? me;

  @override
  ConsumerState<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends ConsumerState<_RowActions> {
  bool _busy = false;

  Future<void> _toggle() async {
    final bool suspending = widget.user.status != UserStatus.suspended;
    setState(() => _busy = true);
    try {
      await ref.read(adminActionProvider.notifier).setUserStatus(
            widget.user.id,
            suspending ? UserStatus.suspended : UserStatus.active,
          );
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        '${widget.user.fullName} is now ${suspending ? 'suspended' : 'active'}.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? me = widget.me;
    final bool allowed = me != null &&
        AdminRepository.canManage(actor: me.role, target: widget.user, actorId: me.id);
    final bool suspended = widget.user.status == UserStatus.suspended;

    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: Key('admin-user-suspend-${widget.user.id}'),
          tooltip: allowed
              ? (suspended ? 'Reinstate' : 'Suspend')
              : 'You cannot change this account',
          onPressed: allowed ? _toggle : null,
          icon: Icon(suspended ? Icons.lock_open_rounded : Icons.block_rounded, size: 20),
        ),
        IconButton(
          key: Key('admin-user-open-${widget.user.id}'),
          tooltip: 'Open',
          onPressed: () => context.go(RoutePaths.adminUserOf(widget.user.id)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}
