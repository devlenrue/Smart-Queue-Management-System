import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/staff_statistics.dart';
import '../../providers/staff_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';

/// §37 — how this clerk's week has gone.
///
/// The bar chart is drawn with plain widgets rather than a charting package:
/// one bar per day is not worth a dependency, and `Expanded` + `Container`
/// scales correctly on every screen size for free.
class StaffStatisticsScreen extends ConsumerWidget {
  const StaffStatisticsScreen({super.key});

  static final List<StatsRange> _ranges = <StatsRange>[
    const StatsRange(label: 'Last 7 days'),
    StatsRange(label: 'Today', from: _today(), to: _today()),
    StatsRange(label: 'Last 30 days', from: _daysAgo(29), to: _today()),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StaffStatistics> async = ref.watch(staffStatisticsProvider);
    final StatsRange selected = ref.watch(statsRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My statistics'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                for (final StatsRange range in _ranges)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(range.label),
                      selected: selected.label == range.label,
                      onSelected: (_) => ref.read(statsRangeProvider.notifier).set(range),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const LoadingView(message: 'Adding it up…'),
        error: (Object error, StackTrace _) =>
            ErrorState(error: error, onRetry: () => ref.invalidate(staffStatisticsProvider)),
        data: (StaffStatistics stats) {
          if (stats.isEmpty) {
            return const EmptyState(
              icon: Icons.insights_outlined,
              title: 'Nothing to report yet',
              message: 'Once you have served a few customers, your figures will appear here.',
            );
          }
          return ListView(
            padding: Responsive.pagePadding(context),
            children: <Widget>[
              Text(
                '${stats.from} to ${stats.to}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              _Totals(stats: stats),
              const SizedBox(height: 20),
              _ServedChart(stats: stats),
              const SizedBox(height: 20),
              _Averages(stats: stats),
            ],
          );
        },
      ),
    );
  }

  static String _today() => _format(DateTime.now());

  static String _daysAgo(int days) => _format(DateTime.now().subtract(Duration(days: days)));

  static String _format(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.stats});

  final StaffStatistics stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GridView.count(
      crossAxisCount: Responsive.isCompact(context) ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: <Widget>[
        DashboardStatCard(
          key: const Key('stats-served'),
          label: 'Served',
          value: '${stats.ticketsServed}',
          icon: Icons.task_alt_rounded,
          color: scheme.tertiary,
        ),
        DashboardStatCard(
          label: 'Skipped',
          value: '${stats.ticketsSkipped}',
          icon: Icons.skip_next_rounded,
        ),
        DashboardStatCard(
          label: 'No-shows',
          value: '${stats.ticketsNoShow}',
          icon: Icons.person_off_outlined,
          color: scheme.error,
        ),
        DashboardStatCard(
          label: 'Completion rate',
          value: '${stats.completionRate}%',
          icon: Icons.percent_rounded,
          caption: '${stats.ticketsHandled} handled',
        ),
      ],
    );
  }
}

/// One bar per day. Heights are relative to the busiest day in the window,
/// so a quiet week still reads clearly.
class _ServedChart extends StatelessWidget {
  const _ServedChart({required this.stats});

  final StaffStatistics stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int peak = stats.busiestDay;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Served per day', style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final StaffDayStat day in stats.byDay)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          Text('${day.served}', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          // A day with zero served still gets 4px so the
                          // column is visible and the axis reads evenly.
                          Container(
                            height: peak == 0 ? 4 : 4 + (110 * day.served / peak),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: day.served == peak ? 0.95 : 0.55),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _weekdayOf(day),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _weekdayOf(StaffDayStat day) {
    final DateTime? date = day.day;
    if (date == null) return '';
    return _weekdays[(date.weekday - 1) % 7];
  }
}

class _Averages extends StatelessWidget {
  const _Averages({required this.stats});

  final StaffStatistics stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Averages', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          _AverageRow(
            icon: Icons.timer_outlined,
            label: 'Time at your counter',
            value: Formatters.duration(stats.averageServiceMinutes.round()),
            caption: 'From starting service to completing it',
          ),
          const Divider(height: 24),
          _AverageRow(
            icon: Icons.hourglass_bottom_rounded,
            label: 'Customer wait before you called',
            value: Formatters.duration(stats.averageWaitMinutes.round()),
            caption: 'From joining the queue to being called',
          ),
          if (stats.ticketsRecalled > 0) ...<Widget>[
            const Divider(height: 24),
            _AverageRow(
              icon: Icons.replay_rounded,
              label: 'Second calls',
              value: '${stats.ticketsRecalled}',
              caption: 'Customers you had to call more than once',
            ),
          ],
        ],
      ),
    );
  }
}

class _AverageRow extends StatelessWidget {
  const _AverageRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                caption,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
