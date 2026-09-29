import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_mapper.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/system_setting.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_state.dart';
import '../../widgets/form_error_banner.dart';
import '../../widgets/loading_widget.dart';
import 'admin_shell.dart';

/// `system_settings`, editable by a super administrator only (§14).
///
/// The table is deliberately schemaless — key, value, description — so the
/// editor is too: whatever keys the server has, the screen renders. Values
/// are stored as text, so a boolean-looking value gets a switch and
/// everything else gets a text field.
class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  /// Pending edits, keyed by setting key. Empty means nothing has changed.
  final Map<String, String> _draft = <String, String>{};
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};

  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(SystemSetting setting) {
    return _controllers.putIfAbsent(
      setting.key,
      () => TextEditingController(text: setting.value),
    );
  }

  Future<void> _save() async {
    if (_draft.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminActionProvider.notifier)
          .saveSettings(Map<String, Object?>.from(_draft));
      if (!mounted) return;
      _draft.clear();
      showSuccessSnackBar(context, 'Settings saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addKey() async {
    final TextEditingController key = TextEditingController();
    final TextEditingController value = TextEditingController();

    final bool? added = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a setting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('setting-new-key'),
              controller: key,
              decoration: const InputDecoration(
                labelText: 'Key',
                hintText: 'queue.max_daily',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('setting-new-value'),
              controller: value,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('setting-new-save'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final String name = key.text.trim();
    key.dispose();
    final String text = value.text;
    value.dispose();

    if (added != true || name.isEmpty) return;
    setState(() => _draft[name] = text);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SystemSetting>> async = ref.watch(systemSettingsProvider);

    return AdminPage(
      title: 'System settings',
      subtitle: _draft.isEmpty ? null : '${_draft.length} unsaved change(s)',
      onRefresh: () async {
        _draft.clear();
        for (final TextEditingController controller in _controllers.values) {
          controller.dispose();
        }
        _controllers.clear();
        ref.invalidate(systemSettingsProvider);
      },
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin-add-setting'),
        onPressed: _busy ? null : _addKey,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add setting'),
      ),
      body: async.when(
        loading: () => const SkeletonList(count: 5),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(systemSettingsProvider)),
        data: (List<SystemSetting> settings) => ListView(
          padding: Responsive.pagePadding(context),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              FormErrorBanner(message: ErrorMapper.fromObject(_error!).userMessage),
              const SizedBox(height: 12),
            ],
            Text(
              'These apply to the whole institution. Only a super administrator '
              'can change them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final SystemSetting setting in settings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SettingTile(
                  setting: setting,
                  controller: setting.isBoolean ? null : _controllerFor(setting),
                  pending: _draft[setting.key],
                  onChanged: (String value) => setState(() {
                    if (value == setting.value) {
                      _draft.remove(setting.key);
                    } else {
                      _draft[setting.key] = value;
                    }
                  }),
                ),
              ),
            const SizedBox(height: 12),
            AppButton(
              key: const Key('settings-save'),
              label: 'Save changes',
              isLoading: _busy,
              onPressed: _draft.isEmpty || _busy ? null : _save,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.setting,
    required this.controller,
    required this.pending,
    required this.onChanged,
  });

  final SystemSetting setting;
  final TextEditingController? controller;
  final String? pending;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dirty = pending != null;

    return AppCard(
      key: Key('setting-${setting.key}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(setting.label, style: theme.textTheme.titleSmall)),
              if (dirty)
                Text(
                  'unsaved',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error),
                ),
            ],
          ),
          Text(
            setting.key,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (setting.description != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(setting.description!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          if (setting.isBoolean)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: (pending ?? setting.value) == 'true',
              onChanged: (bool value) => onChanged(value ? 'true' : 'false'),
              title: Text((pending ?? setting.value) == 'true' ? 'Enabled' : 'Disabled'),
            )
          else
            TextField(
              controller: controller,
              keyboardType: setting.isNumeric ? TextInputType.number : TextInputType.text,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onChanged: onChanged,
            ),
          if (setting.updatedAt != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Updated ${Formatters.relativeFromIso(setting.updatedAt)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
