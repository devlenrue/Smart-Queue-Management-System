import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/admin/reports_screen.dart';
import 'package:smartqueue/models/report.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/providers/report_providers.dart';

import '../helpers/test_harness.dart';

/// §41 — the four management reports and the CSV export.
///
/// The fake repository returns the same fixture the backend suite computes
/// by hand (`server/tests/reports.test.ts`), so a number that appears here
/// is a number the API really produces.
void main() {
  late TestHarness harness;

  /// Today, formatted the way the filter sends it to the server.
  final String today = ReportFilter.wireDate(DateTime.now());

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
    harness.services.services = <Service>[
      sampleService(id: 1, name: 'Finance Office', code: 'FIN'),
      sampleService(id: 2, name: 'Registrar', code: 'REG'),
    ];
  });

  // ── the daily report ────────────────────────────────────────────────────

  testWidgets('opens on the daily report for today', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    expect(harness.reports.dailyCalls, 1);
    expect(harness.reports.lastFrom, today);
    expect(harness.reports.lastTo, today);

    expect(find.byKey(const Key('report-row-2026-09-29-1')), findsOneWidget);
    expect(find.text('Finance Office'), findsWidgets);
    expect(find.text('Registrar'), findsWidgets);
  });

  testWidgets('shows the range totals above the table', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('report-total-issued')), findsOneWidget);
    expect(find.byKey(const Key('report-total-served')), findsOneWidget);
    expect(find.textContaining('20.0 min'), findsOneWidget);
    expect(find.textContaining('40% of those issued'), findsOneWidget);
  });

  testWidgets('prints a dash where no ticket reached a counter',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    // The registrar row has no average wait at all, which is not zero.
    expect(find.text('—'), findsWidgets);
  });

  // ── tabs ────────────────────────────────────────────────────────────────

  testWidgets('each tab fetches its own report', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-tab-services')));
    await tester.pumpAndSettle();
    expect(harness.reports.servicesCalls, 1);
    expect(find.text('09:00–10:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-tab-staff')));
    await tester.pumpAndSettle();
    expect(harness.reports.staffCalls, 1);
    expect(find.text('Jane Wanjiku'), findsOneWidget);
    expect(find.text('Peter Otieno'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-tab-queues')));
    await tester.pumpAndSettle();
    expect(harness.reports.queuesCalls, 1);
    expect(find.byKey(const Key('report-row-3')), findsOneWidget);
  });

  testWidgets('marks a queue that has not closed yet', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-tab-queues')));
    await tester.pumpAndSettle();

    expect(find.text('Still open'), findsOneWidget);
  });

  // ── the range ───────────────────────────────────────────────────────────

  testWidgets('a quick range asks the server for the new dates',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-preset-last7')));
    await tester.pumpAndSettle();

    final DateTime from = DateTime.now().subtract(const Duration(days: 6));
    expect(harness.reports.lastFrom, ReportFilter.wireDate(from));
    expect(harness.reports.lastTo, today);
    expect(harness.reports.dailyCalls, 2);
  });

  testWidgets('the range carries over when the tab changes',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-preset-last30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-tab-staff')));
    await tester.pumpAndSettle();

    final DateTime from = DateTime.now().subtract(const Duration(days: 29));
    expect(harness.reports.staffCalls, 1);
    expect(harness.reports.lastFrom, ReportFilter.wireDate(from));
  });

  testWidgets('the service filter is sent to the server, not applied locally',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-service-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar (REG)').last);
    await tester.pumpAndSettle();

    expect(harness.reports.lastServiceId, 2);
    expect(harness.reports.dailyCalls, 2);
  });

  // ── failures ────────────────────────────────────────────────────────────

  testWidgets('shows the server error with a retry', (WidgetTester tester) async {
    harness.reports.failure = const NetworkFailure(message: 'The server is unreachable.');

    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('unreachable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an empty report says so instead of showing a blank table',
      (WidgetTester tester) async {
    harness.reports.dailyValue = const DailyReport(
      range: ReportRange(from: '2020-01-01', to: '2020-01-31'),
      rows: <DailyReportRow>[],
      totals: ReportTotals.empty,
    );

    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    expect(find.text('No queues in this range'), findsOneWidget);
  });

  // ── CSV export ──────────────────────────────────────────────────────────

  testWidgets('exports the open report and says where the file went',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-export')));
    await tester.pumpAndSettle();

    expect(harness.reports.csvCalls, 1);
    expect(harness.reports.lastCsvKind, ReportKind.daily);
    expect(harness.exporter.lastFilename, 'smartqueue-daily-$today.csv');
    // The file holds the server's bytes, not something the client rebuilt.
    expect(harness.exporter.lastContents, harness.reports.csvValue);
    expect(find.textContaining('smartqueue-daily-$today.csv'), findsOneWidget);
  });

  testWidgets('exports whichever tab is open', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-tab-queues')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-export')));
    await tester.pumpAndSettle();

    expect(harness.reports.lastCsvKind, ReportKind.queues);
    expect(harness.exporter.lastFilename, 'smartqueue-queues-$today.csv');
  });

  testWidgets('names the file after a multi-day range', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-preset-last7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-export')));
    await tester.pumpAndSettle();

    final String from = ReportFilter.wireDate(DateTime.now().subtract(const Duration(days: 6)));
    expect(harness.exporter.lastFilename, 'smartqueue-daily-${from}_$today.csv');
  });

  testWidgets('reports a failed export rather than pretending it saved',
      (WidgetTester tester) async {
    harness.reports.csvFailure =
        const ServerFailure(message: 'The report could not be generated.');

    await tester.pumpScreen(harness, const ReportsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-export')));
    await tester.pumpAndSettle();

    expect(harness.exporter.saveCalls, 0);
    expect(find.textContaining('could not be generated'), findsOneWidget);
  });
}
