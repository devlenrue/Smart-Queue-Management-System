import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/features/staff/staff_history_screen.dart';
import 'package:smartqueue/features/staff/staff_statistics_screen.dart';
import 'package:smartqueue/models/staff_statistics.dart';
import 'package:smartqueue/models/ticket.dart';

import '../helpers/test_harness.dart';

/// §37 — the two screens that answer "what have I done?".
///
/// Neither polls, so neither needs the drain that the console tests use.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.staff);
  });

  group('statistics screen', () {
    testWidgets('shows the totals the server computed', (WidgetTester tester) async {
      harness.staff.statisticsValue = sampleStaffStatistics(served: 12, skipped: 2, noShow: 1);

      await tester.pumpScreen(harness, const StaffStatisticsScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stats-served')), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      expect(find.text('Completion rate'), findsOneWidget);
      // 12 of 15 dispositions ended in a completed service.
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('15 handled'), findsOneWidget);
    });

    testWidgets('renders one bar per day', (WidgetTester tester) async {
      harness.staff.statisticsValue = sampleStaffStatistics(
        byDay: const <StaffDayStat>[
          StaffDayStat(date: '2026-09-26', served: 3, averageServiceMinutes: 4),
          StaffDayStat(date: '2026-09-27', served: 0, averageServiceMinutes: 0),
          StaffDayStat(date: '2026-09-28', served: 9, averageServiceMinutes: 6),
        ],
      );

      await tester.pumpScreen(harness, const StaffStatisticsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Served per day'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('9'), findsWidgets);
    });

    testWidgets('shows the averages in words a clerk can read',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const StaffStatisticsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Time at your counter'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('Customer wait before you called'), findsOneWidget);
      expect(find.text('12 min'), findsOneWidget);
    });

    testWidgets('says so plainly when there is nothing to report',
        (WidgetTester tester) async {
      harness.staff.statisticsValue = sampleStaffStatistics(served: 0, skipped: 0, noShow: 0);

      await tester.pumpScreen(harness, const StaffStatisticsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Nothing to report yet'), findsOneWidget);
    });

    testWidgets('re-reads when the range changes', (WidgetTester tester) async {
      await tester.pumpScreen(harness, const StaffStatisticsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.byKey(const Key('stats-served')), findsOneWidget);
    });
  });

  group('history screen', () {
    testWidgets('lists the tickets this clerk handled', (WidgetTester tester) async {
      harness.staff.handled = <Ticket>[
        sampleTicket(
          id: 31,
          ticketNumber: 'FIN-010',
          status: TicketStatus.completed,
          customer: sampleCustomer(fullName: 'Alice Kamau'),
        ),
        sampleTicket(
          id: 32,
          ticketNumber: 'FIN-011',
          status: TicketStatus.skipped,
          customer: sampleCustomer(fullName: 'Brian Otieno'),
        ),
      ];

      await tester.pumpScreen(harness, const StaffHistoryScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-ticket-31')), findsOneWidget);
      expect(find.byKey(const Key('history-ticket-32')), findsOneWidget);
      expect(find.text('Alice Kamau'), findsOneWidget);
    });

    testWidgets('filters by status', (WidgetTester tester) async {
      harness.staff.handled = <Ticket>[
        sampleTicket(id: 31, ticketNumber: 'FIN-010', status: TicketStatus.completed),
        sampleTicket(id: 32, ticketNumber: 'FIN-011', status: TicketStatus.skipped),
      ];

      await tester.pumpScreen(harness, const StaffHistoryScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('history-filter-skipped')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-ticket-32')), findsOneWidget);
      expect(find.byKey(const Key('history-ticket-31')), findsNothing);
    });

    testWidgets('offers a way back when a filter empties the list',
        (WidgetTester tester) async {
      harness.staff.handled = <Ticket>[
        sampleTicket(id: 31, ticketNumber: 'FIN-010', status: TicketStatus.completed),
      ];

      await tester.pumpScreen(harness, const StaffHistoryScreen());
      await tester.pumpAndSettle();

      // The filter strip scrolls horizontally, and "No-show" sits off the
      // right edge of a phone, so it has to be brought into view first.
      await tester.dragUntilVisible(
        find.byKey(const Key('history-filter-no_show')),
        find.byKey(const Key('history-filters')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('history-filter-no_show')));
      await tester.pumpAndSettle();

      expect(find.text('No no-show tickets'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-ticket-31')), findsOneWidget);
    });

    testWidgets('explains an empty history rather than showing a blank page',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const StaffHistoryScreen());
      await tester.pumpAndSettle();

      expect(find.text('Nothing handled yet'), findsOneWidget);
    });
  });
}
