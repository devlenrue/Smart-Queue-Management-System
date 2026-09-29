import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/responsive.dart';
import '../../providers/infrastructure_providers.dart';
import '../../widgets/app_card.dart';

/// §54. Small, real settings — each one changes actual behaviour.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final Duration interval = ref.watch(pollIntervalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          Text('Appearance', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              children: <Widget>[
                for (final ThemeMode option in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: option,
                    groupValue: mode,
                    onChanged: (ThemeMode? value) {
                      if (value != null) ref.read(themeModeProvider.notifier).set(value);
                    },
                    title: Text(switch (option) {
                      ThemeMode.system => 'Match my device',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Live updates', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'How often your ticket position refreshes',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Every ${interval.inSeconds} seconds. A shorter interval feels '
                    'more live but uses more data and battery.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    value: interval.inSeconds.toDouble(),
                    min: 3,
                    max: 30,
                    divisions: 27,
                    label: '${interval.inSeconds}s',
                    onChanged: (double value) => ref
                        .read(pollIntervalProvider.notifier)
                        .set(Duration(seconds: value.round())),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Connection', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const AppCard(
            child: ListTile(
              leading: Icon(Icons.cloud_outlined),
              title: Text('API server'),
              subtitle: Text(AppConstants.apiBaseUrl),
              isThreeLine: false,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set this at build time with '
            '--dart-define=API_BASE_URL=http://your-host:5000/api/v1',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
