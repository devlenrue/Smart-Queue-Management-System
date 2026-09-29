import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../models/service.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';

/// The service catalogue, as an administrator sees it — including the
/// closed and retired ones the customer list hides.
class ManageServicesScreen extends ConsumerStatefulWidget {
  const ManageServicesScreen({super.key});

  @override
  ConsumerState<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _ManageServicesScreenState extends ConsumerState<ManageServicesScreen> {
  String _search = '';
  ServiceStatus? _status;

  List<Service> _filtered(List<Service> all) {
    final String needle = _search.trim().toLowerCase();
    return all.where((Service service) {
      final bool matchesText = needle.isEmpty ||
          service.name.toLowerCase().contains(needle) ||
          service.code.toLowerCase().contains(needle);
      final bool matchesStatus = _status == null || service.status == _status;
      return matchesText && matchesStatus;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Service>> async = ref.watch(adminServicesProvider);

    return AdminPage(
      title: 'Services',
      subtitle: async.valueOrNull == null ? null : '${async.valueOrNull!.length} configured',
      onRefresh: () async => ref.invalidate(adminServicesProvider),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin-add-service'),
        onPressed: () => context.go(RoutePaths.adminServiceNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New service'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: <Widget>[
                TextField(
                  key: const Key('admin-service-search'),
                  onChanged: (String value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    hintText: 'Search services',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    for (final ServiceStatus status in ServiceStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          key: Key('admin-service-filter-${status.name}'),
                          label: Text(status.label),
                          selected: _status == status,
                          onSelected: (bool on) => setState(() => _status = on ? status : null),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const SkeletonList(count: 5),
              error: (Object error, StackTrace _) =>
                  ErrorState(error: error, onRetry: () => ref.invalidate(adminServicesProvider)),
              data: (List<Service> all) => ListView(
                padding: Responsive.pagePadding(context),
                children: <Widget>[
                  AppDataTable<Service>(
                    shrinkWrap: true,
                    rows: _filtered(all),
                    rowKey: (Service s) => Key('admin-service-${s.id}'),
                    onRowTap: (Service s) => context.go(RoutePaths.adminServiceEditOf(s.id)),
                    emptyTitle: 'No services match',
                    emptyMessage: 'Create one, or clear the filters.',
                    emptyIcon: Icons.apartment_outlined,
                    cardFooter: (Service s) => _RowActions(service: s),
                    columns: <AppDataColumn<Service>>[
                      AppDataColumn<Service>(
                        label: 'Service',
                        primary: true,
                        cell: (Service s) => Text('${s.name} (${s.code})'),
                      ),
                      AppDataColumn<Service>(
                        label: 'Category',
                        cell: (Service s) => Text(s.category ?? '—'),
                      ),
                      AppDataColumn<Service>(
                        label: 'Status',
                        cell: (Service s) => StatusBadge.service(context, s.status, dense: true),
                      ),
                      AppDataColumn<Service>(
                        label: 'Avg service',
                        numeric: true,
                        cell: (Service s) => Text('${s.averageServiceTime} min'),
                      ),
                      AppDataColumn<Service>(
                        label: 'Capacity',
                        numeric: true,
                        cell: (Service s) => Text('${s.dailyCapacity}/day'),
                      ),
                      AppDataColumn<Service>(
                        label: 'Counters',
                        numeric: true,
                        cell: (Service s) => Text('${s.counters.length}'),
                      ),
                      AppDataColumn<Service>(
                        label: 'Waiting',
                        numeric: true,
                        cell: (Service s) => Text('${s.queue?.waitingCount ?? 0}'),
                      ),
                      AppDataColumn<Service>(
                        label: '',
                        showOnCard: false,
                        cell: (Service s) => _RowActions(service: s),
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

class _RowActions extends ConsumerStatefulWidget {
  const _RowActions({required this.service});

  final Service service;

  @override
  ConsumerState<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends ConsumerState<_RowActions> {
  bool _busy = false;

  Future<void> _delete() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete ${widget.service.name}?',
      message: 'A service with history cannot be deleted — close it instead. '
          'This will only succeed for a service nobody has used.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminActionProvider.notifier).deleteService(widget.service.id);
      if (!mounted) return;
      showSuccessSnackBar(context, '${widget.service.name} was deleted.');
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
          key: Key('admin-service-edit-${widget.service.id}'),
          tooltip: 'Edit',
          onPressed: () => context.go(RoutePaths.adminServiceEditOf(widget.service.id)),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        IconButton(
          key: Key('admin-service-monitor-${widget.service.id}'),
          tooltip: 'Live board',
          onPressed: () => context.go(RoutePaths.adminQueueBoardOf(widget.service.id)),
          icon: const Icon(Icons.monitor_heart_outlined, size: 20),
        ),
        IconButton(
          key: Key('admin-service-delete-${widget.service.id}'),
          tooltip: 'Delete',
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
        ),
      ],
    );
  }
}
