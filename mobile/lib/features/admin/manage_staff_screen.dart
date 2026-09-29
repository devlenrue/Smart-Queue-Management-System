import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../models/service.dart';
import '../../models/staff_member.dart';
import '../../providers/admin_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';
import 'widgets/staff_form_dialog.dart';
import 'widgets/user_status_chip.dart';

/// The staff roster (§55): who works here, and where each of them is posted.
///
/// The "not posted" filter is the one administrators actually use — it
/// answers "who is on the payroll but not at a desk this morning?", which
/// is the question that precedes every reassignment.
class ManageStaffScreen extends ConsumerStatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  ConsumerState<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends ConsumerState<ManageStaffScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<StaffMember>> async = ref.watch(adminStaffProvider);
    final StaffFilter filter = ref.watch(staffFilterProvider);

    return AdminPage(
      title: 'Staff',
      subtitle: async.valueOrNull == null ? null : '${async.valueOrNull!.meta.total} on the roster',
      onRefresh: () => ref.read(adminStaffProvider.notifier).refresh(),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin-add-staff'),
        onPressed: () => StaffFormDialog.show(context),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add staff'),
      ),
      body: Column(
        children: <Widget>[
          _Filters(search: _search, filter: filter),
          Expanded(
            child: async.when(
              loading: () => const SkeletonList(count: 5),
              error: (Object error, StackTrace _) =>
                  ErrorState(error: error, onRetry: () => ref.invalidate(adminStaffProvider)),
              data: (PagedState<StaffMember> page) => ListView(
                padding: Responsive.pagePadding(context),
                children: <Widget>[
                  AppDataTable<StaffMember>(
                    shrinkWrap: true,
                    rows: page.items,
                    rowKey: (StaffMember s) => Key('admin-staff-${s.id}'),
                    emptyTitle: 'No staff match',
                    emptyMessage: 'Add a staff account, or clear the filters.',
                    emptyIcon: Icons.badge_outlined,
                    cardFooter: (StaffMember s) => _RowActions(staff: s),
                    columns: <AppDataColumn<StaffMember>>[
                      AppDataColumn<StaffMember>(
                        label: 'Name',
                        primary: true,
                        cell: (StaffMember s) => Text(s.fullName),
                      ),
                      AppDataColumn<StaffMember>(
                        label: 'Email',
                        cell: (StaffMember s) => Text(s.email),
                      ),
                      AppDataColumn<StaffMember>(
                        label: 'Posting',
                        cell: (StaffMember s) => s.isPosted
                            ? Text(s.posting!.label)
                            : Text(
                                'Not posted',
                                style: TextStyle(color: Theme.of(context).colorScheme.outline),
                              ),
                      ),
                      AppDataColumn<StaffMember>(
                        label: 'Counter',
                        cell: (StaffMember s) => s.posting?.counterStatus == null
                            ? const Text('—')
                            : StatusBadge.counter(context, s.posting!.counterStatus!, dense: true),
                      ),
                      AppDataColumn<StaffMember>(
                        label: 'Status',
                        cell: (StaffMember s) => UserStatusChip(status: s.status),
                      ),
                      AppDataColumn<StaffMember>(
                        label: '',
                        showOnCard: false,
                        cell: (StaffMember s) => _RowActions(staff: s),
                      ),
                    ],
                  ),
                  const SizedBox(height: 80),
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
  final StaffFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StaffFilterNotifier notifier = ref.read(staffFilterProvider.notifier);
    final List<Service> services = ref.watch(adminServicesProvider).valueOrNull ?? const <Service>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: <Widget>[
          TextField(
            key: const Key('admin-staff-search'),
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: notifier.search,
            decoration: const InputDecoration(
              hintText: 'Search staff by name or email',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: const Key('admin-staff-unassigned'),
                    label: const Text('Not posted'),
                    selected: filter.unassignedOnly,
                    onSelected: notifier.unassignedOnly,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: const Key('admin-staff-suspended'),
                    label: const Text('Suspended'),
                    selected: filter.status == UserStatus.suspended,
                    onSelected: (bool on) =>
                        notifier.status(on ? UserStatus.suspended : null),
                  ),
                ),
                const SizedBox(width: 8),
                for (final Service service in services)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: Key('admin-staff-service-${service.id}'),
                      label: Text(service.code),
                      selected: filter.serviceId == service.id,
                      onSelected: (bool on) => notifier.service(on ? service.id : null),
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

class _RowActions extends ConsumerStatefulWidget {
  const _RowActions({required this.staff});

  final StaffMember staff;

  @override
  ConsumerState<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends ConsumerState<_RowActions> {
  bool _busy = false;

  Future<void> _unassign() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Release from counter?',
      message: '${widget.staff.fullName} will leave ${widget.staff.posting!.label} '
          'and the counter will go offline.',
      confirmLabel: 'Release',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminActionProvider.notifier).unassignStaff(widget.staff.id);
      if (!mounted) return;
      showSuccessSnackBar(context, '${widget.staff.fullName} was released.');
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          key: Key('admin-staff-assign-${widget.staff.id}'),
          tooltip: widget.staff.isPosted ? 'Move to another counter' : 'Post to a counter',
          onPressed: () => AssignCounterDialog.show(context, staff: widget.staff),
          icon: const Icon(Icons.swap_horiz_rounded, size: 20),
        ),
        IconButton(
          key: Key('admin-staff-unassign-${widget.staff.id}'),
          tooltip: widget.staff.isPosted ? 'Release from counter' : 'Not posted',
          onPressed: widget.staff.isPosted ? _unassign : null,
          icon: const Icon(Icons.logout_rounded, size: 20),
        ),
        IconButton(
          key: Key('admin-staff-edit-${widget.staff.id}'),
          tooltip: 'Edit profile',
          onPressed: () => StaffFormDialog.show(context, existing: widget.staff),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        IconButton(
          key: Key('admin-staff-open-${widget.staff.id}'),
          tooltip: 'Open account',
          onPressed: () => context.go(RoutePaths.adminUserOf(widget.staff.id)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}
