import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/utils/responsive.dart';
import '../../models/counter.dart';
import '../../models/service.dart';
import '../../models/staff_member.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/form_error_banner.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';

/// Counters, grouped by the service they belong to (§54).
///
/// Grouping matters here in a way it does not on the other tables: a counter
/// number is only unique inside its service, so "Counter 1" is meaningless
/// until you know whose counter 1 it is.
class ManageCountersScreen extends ConsumerWidget {
  const ManageCountersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ServiceCounter>> async = ref.watch(adminCountersProvider);
    final List<Service> services = ref.watch(adminServicesProvider).valueOrNull ?? const <Service>[];

    return AdminPage(
      title: 'Counters',
      subtitle: async.valueOrNull == null ? null : '${async.valueOrNull!.length} in total',
      onRefresh: () async {
        ref.invalidate(adminCountersProvider);
        ref.invalidate(adminServicesProvider);
      },
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin-add-counter'),
        onPressed: services.isEmpty
            ? null
            : () => CounterFormDialog.show(context, services: services),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New counter'),
      ),
      body: async.when(
        loading: () => const SkeletonList(count: 5),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(adminCountersProvider)),
        data: (List<ServiceCounter> counters) {
          if (counters.isEmpty) {
            return const EmptyState(
              icon: Icons.desk_outlined,
              title: 'No counters yet',
              message: 'Create a counter and post a member of staff to it.',
            );
          }

          final Map<int, List<ServiceCounter>> grouped = <int, List<ServiceCounter>>{};
          for (final ServiceCounter counter in counters) {
            grouped.putIfAbsent(counter.serviceId, () => <ServiceCounter>[]).add(counter);
          }
          final List<int> serviceIds = grouped.keys.toList()..sort();

          return ListView(
            padding: Responsive.pagePadding(context),
            children: <Widget>[
              for (final int serviceId in serviceIds)
                _ServiceGroup(
                  title: _titleFor(serviceId, grouped[serviceId]!, services),
                  counters: grouped[serviceId]!,
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  static String _titleFor(int serviceId, List<ServiceCounter> counters, List<Service> services) {
    for (final ServiceCounter counter in counters) {
      if (counter.serviceName != null) return counter.serviceName!;
    }
    for (final Service service in services) {
      if (service.id == serviceId) return service.name;
    }
    return 'Service $serviceId';
  }
}

class _ServiceGroup extends StatelessWidget {
  const _ServiceGroup({required this.title, required this.counters});

  final String title;
  final List<ServiceCounter> counters;

  @override
  Widget build(BuildContext context) {
    final List<ServiceCounter> sorted = <ServiceCounter>[...counters]
      ..sort((ServiceCounter a, ServiceCounter b) => a.counterNumber.compareTo(b.counterNumber));

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final ServiceCounter counter in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CounterTile(counter: counter),
            ),
        ],
      ),
    );
  }
}

class _CounterTile extends ConsumerStatefulWidget {
  const _CounterTile({required this.counter});

  final ServiceCounter counter;

  @override
  ConsumerState<_CounterTile> createState() => _CounterTileState();
}

class _CounterTileState extends ConsumerState<_CounterTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showSuccessSnackBar(context, success);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearStaff() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Free this counter?',
      message: '${widget.counter.staffName} will be released from '
          '${widget.counter.name} and the counter will go offline.',
      confirmLabel: 'Free counter',
    );
    if (!confirmed) return;
    await _run(
      () => ref.read(adminActionProvider.notifier).clearCounter(widget.counter.id),
      '${widget.counter.name} is now unstaffed.',
    );
  }

  Future<void> _delete() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete ${widget.counter.name}?',
      message: 'The counter will be removed. Tickets already served there keep '
          'their history.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    await _run(
      () => ref.read(adminActionProvider.notifier).deleteCounter(widget.counter.id),
      '${widget.counter.name} was deleted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ServiceCounter counter = widget.counter;

    return AppCard(
      key: Key('admin-counter-${counter.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Text('${counter.counterNumber}', style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(counter.name, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  counter.isStaffed
                      ? '${counter.staffName}${counter.currentTicket == null ? '' : ' · serving ${counter.currentTicket}'}'
                      : 'Unstaffed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          StatusBadge.counter(context, counter.status, dense: true),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            PopupMenuButton<String>(
              key: Key('admin-counter-menu-${counter.id}'),
              onSelected: (String value) {
                switch (value) {
                  case 'edit':
                    CounterFormDialog.show(context, existing: counter);
                  case 'assign':
                    AssignStaffToCounterDialog.show(context, counter: counter);
                  case 'free':
                    _clearStaff();
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(value: 'edit', child: Text('Rename or renumber')),
                PopupMenuItem<String>(
                  value: 'assign',
                  child: Text(counter.isStaffed ? 'Change who is here' : 'Post staff here'),
                ),
                if (counter.isStaffed)
                  const PopupMenuItem<String>(value: 'free', child: Text('Free this counter')),
                const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}

/// Create a counter, or rename and renumber an existing one.
class CounterFormDialog extends ConsumerStatefulWidget {
  const CounterFormDialog({super.key, this.existing, this.services = const <Service>[]});

  final ServiceCounter? existing;
  final List<Service> services;

  static Future<void> show(
    BuildContext context, {
    ServiceCounter? existing,
    List<Service> services = const <Service>[],
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          CounterFormDialog(existing: existing, services: services),
    );
  }

  @override
  ConsumerState<CounterFormDialog> createState() => _CounterFormDialogState();
}

class _CounterFormDialogState extends ConsumerState<CounterFormDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _name;
  int? _serviceId;
  CounterStatus? _status;
  bool _busy = false;
  Object? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ServiceCounter? existing = widget.existing;
    _number = TextEditingController(text: existing?.counterNumber.toString() ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _serviceId = existing?.serviceId ?? (widget.services.isEmpty ? null : widget.services.first.id);
    _status = existing?.status;
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_isEdit && _serviceId == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ServiceCounter saved = _isEdit
          ? await ref.read(adminActionProvider.notifier).updateCounter(
                widget.existing!.id,
                counterNumber: int.parse(_number.text.trim()),
                name: _name.text.trim(),
                status: _status,
              )
          : await ref.read(adminActionProvider.notifier).createCounter(
                serviceId: _serviceId!,
                counterNumber: int.parse(_number.text.trim()),
                name: _name.text.trim(),
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnackBar(context, '${saved.name} was saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit ${widget.existing!.name}' : 'New counter'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_error != null) ...<Widget>[
                  FormErrorBanner(message: ErrorMapper.fromObject(_error!).userMessage),
                  const SizedBox(height: 12),
                ],
                if (!_isEdit && widget.services.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<int>(
                      key: const Key('counter-service'),
                      initialValue: _serviceId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Service',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<int>>[
                        for (final Service service in widget.services)
                          DropdownMenuItem<int>(
                            value: service.id,
                            child: Text('${service.name} (${service.code})'),
                          ),
                      ],
                      onChanged: (int? id) => setState(() => _serviceId = id),
                    ),
                  ),
                AppTextField(
                  key: const Key('counter-number'),
                  label: 'Counter number',
                  controller: _number,
                  keyboardType: TextInputType.number,
                  helperText: 'Unique within the service',
                  validator: (String? value) {
                    final int? parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null) return 'Enter a number';
                    if (parsed < 1 || parsed > 99) return 'Use a number between 1 and 99';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('counter-name'),
                  label: 'Name',
                  controller: _name,
                  helperText: 'Leave blank to use "<Service> Counter <n>"',
                ),
                if (_isEdit) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CounterStatus>(
                    key: const Key('counter-status'),
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<CounterStatus>>[
                      for (final CounterStatus status in CounterStatus.values)
                        DropdownMenuItem<CounterStatus>(
                          value: status,
                          child: Text(status.label),
                        ),
                    ],
                    onChanged: (CounterStatus? status) => setState(() => _status = status),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton(
          key: const Key('counter-save'),
          label: 'Save',
          expanded: false,
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/// Put a named clerk at this counter — the counter-first half of the same
/// assignment the staff screen performs person-first.
class AssignStaffToCounterDialog extends ConsumerStatefulWidget {
  const AssignStaffToCounterDialog({super.key, required this.counter});

  final ServiceCounter counter;

  static Future<void> show(BuildContext context, {required ServiceCounter counter}) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AssignStaffToCounterDialog(counter: counter),
    );
  }

  @override
  ConsumerState<AssignStaffToCounterDialog> createState() => _AssignStaffToCounterDialogState();
}

class _AssignStaffToCounterDialogState extends ConsumerState<AssignStaffToCounterDialog> {
  int? _staffId;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _staffId = widget.counter.staffId;
  }

  Future<void> _submit() async {
    if (_staffId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ServiceCounter saved = await ref
          .read(adminActionProvider.notifier)
          .assignCounter(widget.counter.id, staffId: _staffId!);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnackBar(context, '${saved.staffName ?? 'Staff'} is now at ${saved.name}.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<StaffMember>> staff = ref.watch(assignableStaffProvider);

    return AlertDialog(
      title: Text('Staff ${widget.counter.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_error != null) ...<Widget>[
              FormErrorBanner(message: ErrorMapper.fromObject(_error!).userMessage),
              const SizedBox(height: 12),
            ],
            staff.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace _) => Text(ErrorMapper.fromObject(error).userMessage),
              data: (List<StaffMember> people) {
                if (people.isEmpty) {
                  return const Text('There are no active staff accounts to post here yet.');
                }
                return DropdownButtonFormField<int>(
                  key: const Key('counter-staff'),
                  initialValue: _staffId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Staff member',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<int>>[
                    for (final StaffMember person in people)
                      DropdownMenuItem<int>(
                        value: person.id,
                        child: Text(
                          person.isPosted
                              ? '${person.fullName} — at ${person.posting!.label}'
                              : person.fullName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (int? id) => setState(() => _staffId = id),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Posting somebody who is already at another counter moves them; '
              'their previous posting is ended in the same transaction.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton(
          key: const Key('counter-assign-save'),
          label: 'Post',
          expanded: false,
          isLoading: _busy,
          onPressed: _busy || _staffId == null ? null : _submit,
        ),
      ],
    );
  }
}
