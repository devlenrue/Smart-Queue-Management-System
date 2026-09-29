import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/report.dart';
import '../../models/service.dart';
import '../../providers/admin_providers.dart';
import '../../providers/report_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_state.dart';
import 'admin_shell.dart';
import 'widgets/report_tables.dart';

/// Reporting (§41).
///
/// Four reports behind one set of controls, because an administrator asking
/// "how did last week go?" wants the same date range applied to all of them.
/// The tab, the range and the service filter therefore live in providers
/// rather than in this widget — the export button in the app bar reads the
/// same state the table below does, so the CSV can never cover a different
/// period from the numbers on screen.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReportKind kind = ref.watch(reportKindProvider);
    final ReportFilter filter = ref.watch(reportFilterProvider);

    return AdminPage(
      title: 'Reports',
      subtitle: _rangeLabel(filter),
      actions: <Widget>[_ExportButton(kind: kind)],
      onRefresh: () async => refreshReport(ref, kind),
      body: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          _KindTabs(selected: kind),
          const SizedBox(height: 8),
          Text(
            kind.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _RangeBar(filter: filter),
          const SizedBox(height: 16),
          switch (kind) {
            ReportKind.daily => const DailyReportView(),
            ReportKind.services => const ServicesReportView(),
            ReportKind.staff => const StaffReportView(),
            ReportKind.queues => const QueuesReportView(),
          },
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _rangeLabel(ReportFilter filter) {
    if (filter.isSingleDay) return Formatters.fullDate(filter.from);
    return '${Formatters.dayMonth(filter.from)} – ${Formatters.dayMonth(filter.to)} '
        '${filter.to.year}';
  }
}

/// The four reports, as chips rather than a `TabBar`: the page frame owns
/// the app bar, and four short labels wrap cleanly on a phone.
class _KindTabs extends ConsumerWidget {
  const _KindTabs({required this.selected});

  final ReportKind selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final ReportKind kind in ReportKind.values)
          ChoiceChip(
            key: Key('report-tab-${kind.wire}'),
            label: Text(kind.label),
            selected: kind == selected,
            onSelected: (bool _) => ref.read(reportKindProvider.notifier).set(kind),
          ),
      ],
    );
  }
}

/// Quick ranges, a custom range and the service filter.
class _RangeBar extends ConsumerWidget {
  const _RangeBar({required this.filter});

  final ReportFilter filter;

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: filter.from, end: filter.to),
      helpText: 'Report period',
    );
    if (picked == null) return;
    ref.read(reportFilterProvider.notifier).setRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `valueOrNull` rather than a `when`: the filter is usable before the
    // service list arrives, and an empty dropdown is not an error state.
    final List<Service> services = ref.watch(adminServicesProvider).valueOrNull ?? const <Service>[];

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final ReportPreset preset in ReportPreset.quickRanges)
                ChoiceChip(
                  key: Key('report-preset-${preset.name}'),
                  label: Text(preset.label),
                  selected: filter.preset == preset,
                  onSelected: (bool _) => ref.read(reportFilterProvider.notifier).setPreset(preset),
                ),
              OutlinedButton.icon(
                key: const Key('report-custom-range'),
                onPressed: () => _pickRange(context, ref),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  filter.preset == ReportPreset.custom
                      ? '${filter.fromWire} → ${filter.toWire}'
                      : 'Pick dates',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 0 stands for "all services" rather than null: a dropdown with a
          // null value shows its hint instead of the matching item, which
          // would leave the field looking empty until something is picked.
          DropdownButtonFormField<int>(
            key: const Key('report-service-filter'),
            initialValue: filter.serviceId ?? 0,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Service',
              prefixIcon: Icon(Icons.filter_alt_outlined),
              isDense: true,
            ),
            items: <DropdownMenuItem<int>>[
              const DropdownMenuItem<int>(value: 0, child: Text('All services')),
              for (final Service service in services)
                DropdownMenuItem<int>(
                  value: service.id,
                  child: Text('${service.name} (${service.code})'),
                ),
            ],
            onChanged: (int? value) =>
                ref.read(reportFilterProvider.notifier).setService(value == 0 ? null : value),
          ),
        ],
      ),
    );
  }
}

/// Downloads the current report as CSV and says where it landed.
class _ExportButton extends ConsumerStatefulWidget {
  const _ExportButton({required this.kind});

  final ReportKind kind;

  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String path = await ref.read(reportExportProvider.notifier).export(widget.kind);
      if (!mounted) return;
      showSuccessSnackBar(context, 'Saved $path');
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
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return IconButton(
      key: const Key('report-export'),
      tooltip: 'Export as CSV',
      onPressed: _export,
      icon: const Icon(Icons.download_rounded),
    );
  }
}
