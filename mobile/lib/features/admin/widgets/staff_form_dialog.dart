import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../../models/counter.dart';
import '../../../models/staff_member.dart';
import '../../../providers/admin_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/form_error_banner.dart';

/// Create a clerk, optionally posting them to a counter in the same breath.
///
/// The posting is part of the create call rather than a second step: the
/// server does both inside one transaction, so a clerk is never left
/// half-created if the counter turns out to be taken.
class StaffFormDialog extends ConsumerStatefulWidget {
  const StaffFormDialog({super.key, this.existing});

  /// Null to create; otherwise the clerk being edited, in which case only
  /// the profile fields are shown (the server has no password-reset route
  /// for another account, and email is immutable).
  final StaffMember? existing;

  static Future<StaffMember?> show(BuildContext context, {StaffMember? existing}) {
    return showDialog<StaffMember>(
      context: context,
      builder: (BuildContext context) => StaffFormDialog(existing: existing),
    );
  }

  @override
  ConsumerState<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends ConsumerState<StaffFormDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final TextEditingController _password = TextEditingController();

  int? _counterId;
  bool _busy = false;
  Object? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final StaffMember? existing = widget.existing;
    _firstName = TextEditingController(text: existing?.firstName ?? '');
    _lastName = TextEditingController(text: existing?.lastName ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final StaffMember saved = _isEdit
          ? await ref.read(adminActionProvider.notifier).updateStaff(
                widget.existing!.id,
                firstName: _firstName.text.trim(),
                lastName: _lastName.text.trim(),
                phone: _phone.text.trim(),
              )
          : await ref.read(adminActionProvider.notifier).createStaff(
                firstName: _firstName.text.trim(),
                lastName: _lastName.text.trim(),
                email: _email.text.trim(),
                phone: _phone.text.trim(),
                password: _password.text,
                counterId: _counterId,
              );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      showSuccessSnackBar(
        context,
        _isEdit ? '${saved.fullName} was updated.' : '${saved.fullName} joined the team.',
      );
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
    final AsyncValue<List<ServiceCounter>> counters = ref.watch(adminCountersProvider);

    return AlertDialog(
      title: Text(_isEdit ? 'Edit ${widget.existing!.firstName}' : 'Add a staff member'),
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
                AppTextField(
                  key: const Key('staff-first-name'),
                  label: 'First name',
                  controller: _firstName,
                  validator: (String? v) => Validators.name(v, 'First name'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('staff-last-name'),
                  label: 'Last name',
                  controller: _lastName,
                  validator: (String? v) => Validators.name(v, 'Last name'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('staff-email'),
                  label: 'Email',
                  controller: _email,
                  enabled: !_isEdit,
                  keyboardType: TextInputType.emailAddress,
                  helperText: _isEdit ? 'Email cannot be changed here' : null,
                  validator: _isEdit ? null : Validators.email,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('staff-phone'),
                  label: 'Phone',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                ),
                if (!_isEdit) ...<Widget>[
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('staff-password'),
                    label: 'Temporary password',
                    controller: _password,
                    obscure: true,
                    helperText: 'They can change it after signing in',
                    validator: Validators.password,
                  ),
                  const SizedBox(height: 12),
                  counters.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (Object _, StackTrace __) => const Text(
                      'Counters could not be loaded — you can post them later.',
                    ),
                    data: (List<ServiceCounter> all) => _CounterPicker(
                      counters: _free(all),
                      value: _counterId,
                      onChanged: (int? id) => setState(() => _counterId = id),
                    ),
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
          key: const Key('staff-save'),
          label: _isEdit ? 'Save' : 'Create',
          isLoading: _busy,
          expanded: false,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }

  /// Only counters nobody is standing at can be offered — the server
  /// answers `STAFF_ALREADY_ASSIGNED` for the rest.
  static List<ServiceCounter> _free(List<ServiceCounter> all) {
    return all.where((ServiceCounter c) => !c.isStaffed).toList(growable: false);
  }
}

/// A grouped dropdown of free counters, labelled by service.
class _CounterPicker extends StatelessWidget {
  const _CounterPicker({required this.counters, required this.value, required this.onChanged});

  final List<ServiceCounter> counters;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (counters.isEmpty) {
      return Text(
        'Every counter is currently staffed. Create the account now and post them later.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return DropdownButtonFormField<int?>(
      key: const Key('staff-counter'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Post to a counter (optional)',
        border: OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<int?>>[
        const DropdownMenuItem<int?>(value: null, child: Text('Not posted yet')),
        for (final ServiceCounter counter in counters)
          DropdownMenuItem<int?>(
            value: counter.id,
            child: Text(
              '${counter.serviceName ?? 'Service ${counter.serviceId}'} · ${counter.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Move a clerk to a different counter, or release them.
class AssignCounterDialog extends ConsumerStatefulWidget {
  const AssignCounterDialog({super.key, required this.staff});

  final StaffMember staff;

  static Future<bool?> show(BuildContext context, {required StaffMember staff}) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AssignCounterDialog(staff: staff),
    );
  }

  @override
  ConsumerState<AssignCounterDialog> createState() => _AssignCounterDialogState();
}

class _AssignCounterDialogState extends ConsumerState<AssignCounterDialog> {
  int? _counterId;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _counterId = widget.staff.posting?.counterId;
  }

  Future<void> _submit() async {
    if (_counterId == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final StaffMember saved = await ref
          .read(adminActionProvider.notifier)
          .assignStaff(widget.staff.id, counterId: _counterId!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showSuccessSnackBar(context, '${saved.fullName} is now at ${saved.posting?.label}.');
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
    final AsyncValue<List<ServiceCounter>> counters = ref.watch(adminCountersProvider);

    return AlertDialog(
      title: Text('Post ${widget.staff.firstName}'),
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
            Text(
              widget.staff.isPosted
                  ? 'Currently at ${widget.staff.posting!.label}.'
                  : 'Not posted to any counter.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            counters.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace _) => Text(
                'Counters could not be loaded.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              data: (List<ServiceCounter> all) => _CounterPicker(
                counters: all
                    .where((ServiceCounter c) =>
                        !c.isStaffed || c.staffId == widget.staff.id)
                    .toList(growable: false),
                value: _counterId,
                onChanged: (int? id) => setState(() => _counterId = id),
              ),
            ),
            if (counters.valueOrNull != null && _counterIsBusy(counters.valueOrNull!))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'A counter that is mid-customer cannot be reassigned until the '
                  'ticket is finished.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
          key: const Key('staff-assign-save'),
          label: 'Post',
          expanded: false,
          isLoading: _busy,
          onPressed: _busy || _counterId == null ? null : _submit,
        ),
      ],
    );
  }

  bool _counterIsBusy(List<ServiceCounter> all) {
    for (final ServiceCounter counter in all) {
      if (counter.id == _counterId) return counter.status == CounterStatus.busy;
    }
    return false;
  }
}
