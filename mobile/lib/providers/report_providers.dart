import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_mapper.dart';
import '../core/errors/failure.dart';
import '../models/report.dart';
import '../repositories/report_repository.dart';
import 'infrastructure_providers.dart';

/// State for the reporting screen (§41).
///
/// Reports are historical, so nothing here polls: an administrator asks a
/// question, gets an answer, and asks again when they want a newer one.
/// That keeps this file to three ideas — the filter, one future per report,
/// and the export controller.

// ── the filter every report shares ────────────────────────────────────────

/// The quick ranges above the report. Custom is what a hand-picked range
/// selects, and it is never offered as a button.
enum ReportPreset {
  today('Today'),
  last7('Last 7 days'),
  last30('Last 30 days'),
  thisMonth('This month'),
  custom('Custom');

  const ReportPreset(this.label);

  final String label;

  /// The buttons, in the order they appear — everything except [custom],
  /// which is what picking dates by hand selects rather than a button.
  static List<ReportPreset> get quickRanges {
    return ReportPreset.values
        .where((ReportPreset preset) => preset != ReportPreset.custom)
        .toList(growable: false);
  }
}

class ReportFilter {
  const ReportFilter({
    required this.from,
    required this.to,
    this.preset = ReportPreset.today,
    this.serviceId,
    this.staffId,
  });

  final DateTime from;
  final DateTime to;
  final ReportPreset preset;

  /// Null means every service, which is what the server assumes too.
  final int? serviceId;
  final int? staffId;

  String get fromWire => wireDate(from);
  String get toWire => wireDate(to);

  bool get isSingleDay => fromWire == toWire;

  /// 'YYYY-MM-DD' in the device's own timezone, matching what the server
  /// stores in `queues.queue_date`.
  static String wireDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  /// Midnight, so two filters for the same day compare equal however they
  /// were built.
  static DateTime dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

  static ReportFilter forPreset(ReportPreset preset, {DateTime? now}) {
    final DateTime today = dayOf(now ?? DateTime.now());
    switch (preset) {
      case ReportPreset.today:
      case ReportPreset.custom:
        return ReportFilter(from: today, to: today, preset: preset);
      case ReportPreset.last7:
        return ReportFilter(
          from: today.subtract(const Duration(days: 6)),
          to: today,
          preset: preset,
        );
      case ReportPreset.last30:
        return ReportFilter(
          from: today.subtract(const Duration(days: 29)),
          to: today,
          preset: preset,
        );
      case ReportPreset.thisMonth:
        return ReportFilter(from: DateTime(today.year, today.month), to: today, preset: preset);
    }
  }

  ReportFilter copyWith({
    DateTime? from,
    DateTime? to,
    ReportPreset? preset,
    Object? serviceId = _unset,
    Object? staffId = _unset,
  }) {
    return ReportFilter(
      from: from ?? this.from,
      to: to ?? this.to,
      preset: preset ?? this.preset,
      serviceId: serviceId == _unset ? this.serviceId : serviceId as int?,
      staffId: staffId == _unset ? this.staffId : staffId as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReportFilter &&
      other.fromWire == fromWire &&
      other.toWire == toWire &&
      other.preset == preset &&
      other.serviceId == serviceId &&
      other.staffId == staffId;

  @override
  int get hashCode => Object.hash(fromWire, toWire, preset, serviceId, staffId);
}

const Object _unset = Object();

class ReportFilterNotifier extends Notifier<ReportFilter> {
  @override
  ReportFilter build() => ReportFilter.forPreset(ReportPreset.today);

  void setPreset(ReportPreset preset, {DateTime? now}) {
    state = ReportFilter.forPreset(preset, now: now).copyWith(
      serviceId: state.serviceId,
      staffId: state.staffId,
    );
  }

  /// A hand-picked range. Reversed dates are swapped rather than rejected —
  /// the server would answer 422 and the administrator only mis-tapped.
  void setRange(DateTime from, DateTime to) {
    final DateTime a = ReportFilter.dayOf(from);
    final DateTime b = ReportFilter.dayOf(to);
    final bool reversed = b.isBefore(a);
    state = state.copyWith(
      from: reversed ? b : a,
      to: reversed ? a : b,
      preset: ReportPreset.custom,
    );
  }

  void setService(int? serviceId) => state = state.copyWith(serviceId: serviceId);

  void setStaff(int? staffId) => state = state.copyWith(staffId: staffId);
}

final NotifierProvider<ReportFilterNotifier, ReportFilter> reportFilterProvider =
    NotifierProvider<ReportFilterNotifier, ReportFilter>(ReportFilterNotifier.new);

/// Which tab is open. It lives outside the screen because the export button
/// in the app bar has to know which report it is exporting.
class ReportKindNotifier extends Notifier<ReportKind> {
  @override
  ReportKind build() => ReportKind.daily;

  void set(ReportKind kind) => state = kind;
}

final NotifierProvider<ReportKindNotifier, ReportKind> reportKindProvider =
    NotifierProvider<ReportKindNotifier, ReportKind>(ReportKindNotifier.new);

// ── the four reports ──────────────────────────────────────────────────────

final AutoDisposeFutureProvider<DailyReport> dailyReportProvider =
    FutureProvider.autoDispose<DailyReport>((Ref ref) {
  final ReportFilter filter = ref.watch(reportFilterProvider);
  return ref.watch(reportRepositoryProvider).daily(
        from: filter.fromWire,
        to: filter.toWire,
        serviceId: filter.serviceId,
      );
});

final AutoDisposeFutureProvider<ServicesReport> servicesReportProvider =
    FutureProvider.autoDispose<ServicesReport>((Ref ref) {
  final ReportFilter filter = ref.watch(reportFilterProvider);
  return ref.watch(reportRepositoryProvider).services(
        from: filter.fromWire,
        to: filter.toWire,
        serviceId: filter.serviceId,
      );
});

final AutoDisposeFutureProvider<StaffReport> staffReportProvider =
    FutureProvider.autoDispose<StaffReport>((Ref ref) {
  final ReportFilter filter = ref.watch(reportFilterProvider);
  return ref.watch(reportRepositoryProvider).staff(
        from: filter.fromWire,
        to: filter.toWire,
        serviceId: filter.serviceId,
        staffId: filter.staffId,
      );
});

final AutoDisposeFutureProvider<QueuesReport> queuesReportProvider =
    FutureProvider.autoDispose<QueuesReport>((Ref ref) {
  final ReportFilter filter = ref.watch(reportFilterProvider);
  return ref.watch(reportRepositoryProvider).queues(
        from: filter.fromWire,
        to: filter.toWire,
        serviceId: filter.serviceId,
      );
});

/// Re-runs whichever report is open, for the refresh button and the
/// pull-to-refresh gesture. Takes a [WidgetRef] because the screen is the
/// only thing that knows which tab is in front of the administrator.
void refreshReport(WidgetRef ref, ReportKind kind) {
  switch (kind) {
    case ReportKind.daily:
      ref.invalidate(dailyReportProvider);
    case ReportKind.services:
      ref.invalidate(servicesReportProvider);
    case ReportKind.staff:
      ref.invalidate(staffReportProvider);
    case ReportKind.queues:
      ref.invalidate(queuesReportProvider);
  }
}

// ── CSV export ────────────────────────────────────────────────────────────

/// Downloads the CSV the server generates and writes it to disk.
///
/// The client never builds the CSV itself: the file a marker opens has to
/// be the same bytes the API produced, or the export proves nothing.
class ReportExportController extends AutoDisposeAsyncNotifier<String?> {
  @override
  String? build() => null;

  /// Returns the path the file was written to, and throws a [Failure] the
  /// screen can show verbatim.
  Future<String> export(ReportKind kind) async {
    state = const AsyncValue<String?>.loading();
    try {
      final ReportFilter filter = ref.read(reportFilterProvider);
      final ReportRepository repository = ref.read(reportRepositoryProvider);

      final String csv = await repository.csv(
        kind,
        from: filter.fromWire,
        to: filter.toWire,
        serviceId: filter.serviceId,
        staffId: kind == ReportKind.staff ? filter.staffId : null,
      );

      final String path = await ref.read(reportExporterProvider).save(
            filenameFor(kind, filter),
            csv,
          );
      state = AsyncValue<String?>.data(path);
      return path;
    } catch (error) {
      final Failure failure = ErrorMapper.fromObject(error);
      state = AsyncValue<String?>.error(failure, StackTrace.current);
      throw failure;
    }
  }

  /// Mirrors the name in the server's `Content-Disposition`, so the file on
  /// the phone and the file a browser would have downloaded match.
  static String filenameFor(ReportKind kind, ReportFilter filter) {
    return filter.isSingleDay
        ? 'smartqueue-${kind.wire}-${filter.fromWire}.csv'
        : 'smartqueue-${kind.wire}-${filter.fromWire}_${filter.toWire}.csv';
  }
}

final AutoDisposeAsyncNotifierProvider<ReportExportController, String?> reportExportProvider =
    AsyncNotifierProvider.autoDispose<ReportExportController, String?>(
        ReportExportController.new);
