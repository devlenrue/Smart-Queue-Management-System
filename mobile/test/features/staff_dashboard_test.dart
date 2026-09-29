import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/staff/staff_dashboard_screen.dart';
import 'package:smartqueue/models/counter.dart';
import 'package:smartqueue/models/ticket.dart';

import '../helpers/test_harness.dart';

/// §20 — the console a counter clerk keeps open all day.
///
/// The console polls forever, so every test ends with
/// [PumpX.unmountAndDrain]; otherwise the test finishes with the poll timer
/// still pending.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.staff);
  });

  testWidgets('names the service and counter the clerk is working',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(find.text('Finance Office'), findsWidgets);
    expect(find.text('Finance Counter 2'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('shows the queue count and what this clerk served today',
      (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(waiting: 7, servedToday: 12);

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(find.byKey(const Key('stat-waiting')), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.byKey(const Key('stat-served')), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('You served today'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('lists who is up next, in queue order', (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(
      upNext: <Ticket>[
        sampleTicket(id: 1, ticketNumber: 'FIN-013', customer: sampleCustomer(fullName: 'Alice Kamau')),
        sampleTicket(id: 2, ticketNumber: 'FIN-014', customer: sampleCustomer(fullName: 'Brian Otieno')),
      ],
    );

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(find.byKey(const Key('waiting-ticket-1')), findsOneWidget);
    expect(find.byKey(const Key('waiting-ticket-2')), findsOneWidget);
    expect(find.text('Alice Kamau'), findsOneWidget);
    expect(find.text('Brian Otieno'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('offers Call Next when a counter is open and somebody is waiting',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    final Finder button = find.byKey(const Key('call-next'));
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(find.byKey(const Key('call-next-blocked')), findsNothing);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('calls the next customer and says who was called',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    await tester.tap(find.byKey(const Key('call-next')));
    await tester.pump();
    await tester.pump();

    expect(harness.staff.callNextCalls, 1);
    expect(find.textContaining('FIN-012 called'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('disables Call Next while a customer is already at the counter',
      (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(
      currentTicket: sampleTicket(
        ticketNumber: 'FIN-011',
        status: TicketStatus.serving,
        customer: sampleCustomer(),
        counter: const CounterSummary(id: 2, counterNumber: 2, name: 'Finance Counter 2'),
      ),
    );

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    // The panel is replaced by the now-serving card and its action bar.
    expect(find.byKey(const Key('call-next')), findsNothing);
    expect(find.byKey(const Key('staff-current-ticket')), findsOneWidget);
    expect(find.text('FIN-011'), findsOneWidget);
    expect(find.text('Now serving'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('explains why Call Next is unavailable when the counter is off duty',
      (WidgetTester tester) async {
    harness.staff.dashboardValue =
        sampleStaffDashboard(counterStatus: CounterStatus.offline);

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byKey(const Key('call-next'))).onPressed, isNull);
    expect(
      find.text('Your counter is off duty. Turn it back on to call the next customer.'),
      findsOneWidget,
    );

    await tester.unmountAndDrain(harness);
  });

  testWidgets('explains an empty queue rather than showing a dead button',
      (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(waiting: 0);

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byKey(const Key('call-next'))).onPressed, isNull);
    expect(find.text('Nobody is waiting right now.'), findsOneWidget);
    expect(find.byKey(const Key('up-next-empty')), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('tells an unassigned staff member what to do', (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(assigned: false, waiting: 0);

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(find.text('No counter assigned'), findsOneWidget);
    expect(find.byKey(const Key('call-next')), findsNothing);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('lets a clerk watch the queue without a counter, but not call from it',
      (WidgetTester tester) async {
    harness.staff.dashboardValue = sampleStaffDashboard(withCounter: false);

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(find.textContaining('not to a counter'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('call-next'))).onPressed, isNull);
    expect(find.text('You need a counter before you can call anybody.'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('shows the server error instead of an empty console',
      (WidgetTester tester) async {
    harness.staff.dashboardFailure = const NetworkFailure();

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });

  testWidgets('surfaces a 409 from the server without breaking the console',
      (WidgetTester tester) async {
    harness.staff.actionFailure = const ConflictFailure(
      message: 'Counter 2 is already serving a customer.',
      code: 'COUNTER_BUSY',
    );

    await tester.pumpScreen(harness, const StaffDashboardScreen());
    await tester.pump();

    await tester.tap(find.byKey(const Key('call-next')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Counter 2 is already serving a customer.'), findsOneWidget);
    // Still usable afterwards.
    expect(find.byKey(const Key('call-next')), findsOneWidget);

    await tester.unmountAndDrain(harness);
  });
}
