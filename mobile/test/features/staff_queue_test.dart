import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/features/staff/current_queue_screen.dart';
import 'package:smartqueue/models/ticket.dart';

import '../helpers/test_harness.dart';

/// The full waiting list, and the per-row Call button that lets a clerk
/// pull one specific person forward.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.staff);
    harness.queues.monitorWaiting = <Ticket>[
      sampleTicket(
        id: 11,
        ticketNumber: 'FIN-013',
        waitedMinutes: 4,
        customer: sampleCustomer(fullName: 'Alice Kamau'),
      ),
      sampleTicket(
        id: 12,
        ticketNumber: 'FIN-014',
        waitedMinutes: 41,
        customer: sampleCustomer(fullName: 'Brian Otieno'),
      ),
    ];
  });

  testWidgets('lists everyone waiting, numbered by their place in line',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const CurrentQueueScreen());
    await tester.pump();

    expect(find.byKey(const Key('waiting-ticket-11')), findsOneWidget);
    expect(find.byKey(const Key('waiting-ticket-12')), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Alice Kamau'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('shows how long each person has waited', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const CurrentQueueScreen());
    await tester.pump();

    expect(find.text('waited 4 min'), findsOneWidget);
    expect(find.text('waited 41 min'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('calls the specific ticket whose button was tapped',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const CurrentQueueScreen());
    await tester.pump();

    await tester.tap(find.byKey(const Key('call-ticket-12')));
    await tester.pump();
    await tester.pump();

    expect(harness.staff.lastCalledTicketId, 12);
    expect(harness.staff.actions, contains('call'));

    await tester.unmountAndDrain(harness);
  });

  testWidgets('says the queue is clear rather than showing an empty list',
      (WidgetTester tester) async {
    harness.queues.monitorWaiting = <Ticket>[];

    await tester.pumpScreen(harness, const CurrentQueueScreen());
    await tester.pump();

    expect(find.text('Queue cleared'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('cannot call anybody when the clerk has no counter',
      (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(withCounter: false);

    await tester.pumpScreen(harness, const CurrentQueueScreen());
    await tester.pump();

    final Finder button = find.byKey(const Key('call-ticket-11'));
    expect(button, findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNull);

    await tester.unmountAndDrain(harness);
  });
}
