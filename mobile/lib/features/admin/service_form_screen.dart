import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../models/service.dart';
import '../../providers/admin_providers.dart';
import '../../providers/customer_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/error_state.dart';
import '../../widgets/form_error_banner.dart';
import '../../widgets/loading_widget.dart';
import 'admin_shell.dart';

/// Create or edit a service.
///
/// Three server calls hide behind one Save button — the service itself, its
/// queue settings and its weekly hours — because they are three tables and
/// three endpoints, but one decision as far as the person filling the form
/// in is concerned. A new service is created first so the other two have an
/// id to hang on.
class ServiceFormScreen extends ConsumerStatefulWidget {
  const ServiceFormScreen({super.key, this.serviceId});

  /// Null when creating.
  final int? serviceId;

  @override
  ConsumerState<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends ConsumerState<ServiceFormScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _averageServiceTime = TextEditingController(text: '5');
  final TextEditingController _dailyCapacity = TextEditingController(text: '100');
  final TextEditingController _maxQueueSize = TextEditingController(text: '100');
  final TextEditingController _threshold = TextEditingController(text: '3');

  ServiceStatus _status = ServiceStatus.open;
  bool _allowCancellation = true;
  bool _allowRejoin = true;
  bool _loaded = false;
  bool _busy = false;
  Object? _error;

  /// One row per weekday, index 0 = Sunday to match `service_hours`.
  final List<_DayHours> _hours = <_DayHours>[
    for (int day = 0; day < 7; day++)
      _DayHours(dayOfWeek: day, open: day != 0 && day != 6, from: '08:00', to: '17:00'),
  ];

  bool get _isEdit => widget.serviceId != null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    _category.dispose();
    _averageServiceTime.dispose();
    _dailyCapacity.dispose();
    _maxQueueSize.dispose();
    _threshold.dispose();
    super.dispose();
  }

  void _fill(Service service) {
    if (_loaded) return;
    _loaded = true;
    _name.text = service.name;
    _code.text = service.code;
    _description.text = service.description ?? '';
    _category.text = service.category ?? '';
    _averageServiceTime.text = '${service.averageServiceTime}';
    _dailyCapacity.text = '${service.dailyCapacity}';
    _status = service.status;

    final QueueSettings? settings = service.settings;
    if (settings != null) {
      _maxQueueSize.text = '${settings.maxQueueSize}';
      _threshold.text = '${settings.notificationThreshold}';
      _allowCancellation = settings.allowCancellation;
      _allowRejoin = settings.allowRejoin;
    }

    for (final ServiceHours row in service.hours) {
      if (row.dayOfWeek < 0 || row.dayOfWeek > 6) continue;
      _hours[row.dayOfWeek] = _DayHours(
        dayOfWeek: row.dayOfWeek,
        open: row.isOpen,
        from: row.openingTime ?? '08:00',
        to: row.closingTime ?? '17:00',
      );
    }
  }

  Map<String, dynamic> get _serviceBody => <String, dynamic>{
        'name': _name.text.trim(),
        'code': _code.text.trim().toUpperCase(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
        'averageServiceTime': int.parse(_averageServiceTime.text.trim()),
        'dailyCapacity': int.parse(_dailyCapacity.text.trim()),
        'status': _status.name,
      };

  Map<String, dynamic> get _settingsBody => <String, dynamic>{
        'maxQueueSize': int.parse(_maxQueueSize.text.trim()),
        'notificationThreshold': int.parse(_threshold.text.trim()),
        'allowCancellation': _allowCancellation,
        'allowRejoin': _allowRejoin,
        'estimatedServiceTime': int.parse(_averageServiceTime.text.trim()),
      };

  List<Map<String, dynamic>> get _hoursBody => <Map<String, dynamic>>[
        for (final _DayHours day in _hours)
          <String, dynamic>{
            'dayOfWeek': day.dayOfWeek,
            'openingTime': day.from,
            'closingTime': day.to,
            'status': day.open ? 'open' : 'closed',
          },
      ];

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final AdminActionController actions = ref.read(adminActionProvider.notifier);
      final int id = _isEdit
          ? widget.serviceId!
          : (await actions.createService(_serviceBody)).id;

      if (_isEdit) await actions.updateService(id, _serviceBody);
      await actions.updateServiceSettings(id, _settingsBody);
      await actions.updateServiceHours(id, _hoursBody);

      if (!mounted) return;
      showSuccessSnackBar(context, '${_name.text.trim()} was saved.');
      context.go(RoutePaths.adminServices);
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
    if (!_isEdit) return _page(context, child: _form_(context));

    final AsyncValue<Service> async = ref.watch(serviceDetailProvider(widget.serviceId!));
    return _page(
      context,
      child: async.when(
        loading: () => const SkeletonList(count: 4),
        error: (Object error, StackTrace _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(serviceDetailProvider(widget.serviceId!)),
        ),
        data: (Service service) {
          _fill(service);
          return _form_(context);
        },
      ),
    );
  }

  Widget _page(BuildContext context, {required Widget child}) {
    return AdminPage(
      title: _isEdit ? 'Edit service' : 'New service',
      subtitle: _isEdit ? _name.text : 'Add a service customers can queue for',
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => context.go(RoutePaths.adminServices),
          child: const Text('Cancel'),
        ),
      ],
      body: child,
    );
  }

  Widget _form_(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Form(
      key: _form,
      child: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            FormErrorBanner(message: ErrorMapper.fromObject(_error!).userMessage),
            const SizedBox(height: 12),
          ],
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Details', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('service-name'),
                  label: 'Name',
                  controller: _name,
                  validator: (String? v) =>
                      (v ?? '').trim().length < 3 ? 'Give the service a name' : null,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('service-code'),
                  label: 'Code',
                  controller: _code,
                  helperText: 'Two to eight letters or digits — it prefixes every ticket',
                  validator: (String? v) {
                    final String value = (v ?? '').trim().toUpperCase();
                    if (!RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(value)) {
                      return 'Use 2–8 letters or digits, e.g. FIN';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('service-description'),
                  label: 'Description',
                  controller: _description,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('service-category'),
                  label: 'Category',
                  controller: _category,
                  helperText: 'Groups the service in the customer list',
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        key: const Key('service-average'),
                        label: 'Average service time (min)',
                        controller: _averageServiceTime,
                        keyboardType: TextInputType.number,
                        validator: _positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        key: const Key('service-capacity'),
                        label: 'Daily capacity',
                        controller: _dailyCapacity,
                        keyboardType: TextInputType.number,
                        validator: _positive,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ServiceStatus>(
                  key: const Key('service-status'),
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<ServiceStatus>>[
                    for (final ServiceStatus status in ServiceStatus.values)
                      DropdownMenuItem<ServiceStatus>(value: status, child: Text(status.label)),
                  ],
                  onChanged: (ServiceStatus? value) =>
                      setState(() => _status = value ?? ServiceStatus.open),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Queue rules', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        key: const Key('service-max-queue'),
                        label: 'Maximum queue size',
                        controller: _maxQueueSize,
                        keyboardType: TextInputType.number,
                        validator: _positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        key: const Key('service-threshold'),
                        label: 'Alert when N away',
                        controller: _threshold,
                        keyboardType: TextInputType.number,
                        validator: _positive,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('service-allow-cancel'),
                  contentPadding: EdgeInsets.zero,
                  value: _allowCancellation,
                  onChanged: (bool value) => setState(() => _allowCancellation = value),
                  title: const Text('Customers may cancel their ticket'),
                ),
                SwitchListTile(
                  key: const Key('service-allow-rejoin'),
                  contentPadding: EdgeInsets.zero,
                  value: _allowRejoin,
                  onChanged: (bool value) => setState(() => _allowRejoin = value),
                  title: const Text('Customers may rejoin after being skipped'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Opening hours', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'A queue only accepts tickets inside these hours.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < _hours.length; i++)
                  _HoursRow(
                    day: _hours[i],
                    onChanged: (_DayHours next) => setState(() => _hours[i] = next),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            key: const Key('service-save'),
            label: _isEdit ? 'Save changes' : 'Create service',
            isLoading: _busy,
            onPressed: _busy ? null : _save,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String? _positive(String? value) {
    final int? parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 1) return 'Enter a number of 1 or more';
    return null;
  }
}

/// One weekday's hours in the editor.
class _DayHours {
  const _DayHours({
    required this.dayOfWeek,
    required this.open,
    required this.from,
    required this.to,
  });

  final int dayOfWeek;
  final bool open;
  final String from;
  final String to;

  static const List<String> names = <String>[
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  String get name => names[dayOfWeek];

  _DayHours copyWith({bool? open, String? from, String? to}) => _DayHours(
        dayOfWeek: dayOfWeek,
        open: open ?? this.open,
        from: from ?? this.from,
        to: to ?? this.to,
      );
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.day, required this.onChanged});

  final _DayHours day;
  final ValueChanged<_DayHours> onChanged;

  Future<void> _pick(BuildContext context, {required bool isOpening}) async {
    final List<String> parts = (isOpening ? day.from : day.to).split(':');
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (picked == null) return;

    final String value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onChanged(isOpening ? day.copyWith(from: value) : day.copyWith(to: value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(day.name, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Switch(
            key: Key('service-day-${day.dayOfWeek}'),
            value: day.open,
            onChanged: (bool value) => onChanged(day.copyWith(open: value)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: day.open ? () => _pick(context, isOpening: true) : null,
            child: Text(day.from),
          ),
          const Text('–'),
          TextButton(
            onPressed: day.open ? () => _pick(context, isOpening: false) : null,
            child: Text(day.to),
          ),
        ],
      ),
    );
  }
}
