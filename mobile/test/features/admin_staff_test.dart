import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/admin/manage_counters_screen.dart';
import 'package:smartqueue/features/admin/manage_staff_screen.dart';
import 'package:smartqueue/models/counter.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/models/staff_member.dart';

import '../helpers/test_harness.dart';

/// §54, §55 — the roster and the counters it posts people to.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
    harness.admin.staffList = <StaffMember>[
      sampleStaffMember(id: 4),
      sampleStaffMember(
        id: 5,
        firstName: 'Peter',
        lastName: 'Otieno',
        email: 'peter.staff@smartqueue.test',
        posted: false,
      ),
    ];
    harness.services.services = <Service>[sampleService()];
  });

  testWidgets('shows where each clerk is posted, and who is not',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageStaffScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-staff-4')), findsOneWidget);
    expect(find.text('Finance Office · Counter 2'), findsOneWidget);
    expect(find.byKey(const Key('admin-staff-5')), findsOneWidget);
    expect(find.text('Not posted'), findsWidgets);
  });

  testWidgets('the "not posted" filter asks the server for exactly that',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageStaffScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-staff-unassigned')));
    await tester.pumpAndSettle();

    expect(harness.admin.lastUnassignedOnly, isTrue);
    expect(find.text('Peter Otieno'), findsOneWidget);
    expect(find.text('Jane Wanjiku'), findsNothing);
  });

  testWidgets('releasing a clerk asks first, then calls unassign',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageStaffScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-staff-unassign-4')));
    await tester.pumpAndSettle();

    expect(find.text('Release from counter?'), findsOneWidget);
    expect(harness.admin.writes, isEmpty);

    await tester.tap(find.text('Release'));
    await tester.pumpAndSettle();

    expect(harness.admin.writes, contains('staff:4:unassign'));

    await tester.drainSnackBars();
  });

  testWidgets('a clerk who is not posted cannot be released',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageStaffScreen());
    await tester.pumpAndSettle();

    final IconButton button = tester.widget<IconButton>(
      find.byKey(const Key('admin-staff-unassign-5')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('surfaces a busy counter rather than swallowing the conflict',
      (WidgetTester tester) async {
    harness.admin.actionFailure =
        const ConflictFailure('Finance Counter 2 is still handling ticket FIN-012.');

    await tester.pumpScreen(harness, const ManageStaffScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-staff-unassign-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Release'));
    await tester.pumpAndSettle();

    expect(
      find.text('Finance Counter 2 is still handling ticket FIN-012.'),
      findsOneWidget,
    );

    await tester.drainSnackBars();
  });

  testWidgets('the new-staff form validates before it calls the server',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageStaffScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-add-staff')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();

    expect(harness.admin.writes, isEmpty);

    await tester.enterText(find.byKey(const Key('staff-first-name')), 'Amina');
    await tester.enterText(find.byKey(const Key('staff-last-name')), 'Hassan');
    await tester.enterText(find.byKey(const Key('staff-email')), 'amina@smartqueue.test');
    await tester.enterText(find.byKey(const Key('staff-phone')), '+254711900900');
    await tester.enterText(find.byKey(const Key('staff-password')), 'Password123');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();

    expect(harness.admin.writes, contains('staff:create:amina@smartqueue.test:-'));

    await tester.drainSnackBars();
  });

  group('counters', () {
    setUp(() {
      harness.staff.counterList = <ServiceCounter>[
        sampleServiceCounter(id: 1, counterNumber: 1, name: 'Finance Counter 1'),
        sampleServiceCounter(
          id: 2,
          counterNumber: 2,
          name: 'Finance Counter 2',
          status: CounterStatus.offline,
          staffId: null,
          staffName: null,
        ),
      ];
    });

    testWidgets('groups counters under their service and says who is at each',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const ManageCountersScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-counter-1')), findsOneWidget);
      expect(find.byKey(const Key('admin-counter-2')), findsOneWidget);
      expect(find.text('Jane Wanjiku'), findsOneWidget);
      expect(find.text('Unstaffed'), findsOneWidget);
    });

    testWidgets('creating a counter sends the service and the number',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const ManageCountersScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-add-counter')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('counter-number')), '4');
      await tester.enterText(find.byKey(const Key('counter-name')), 'Finance Counter 4');
      await tester.tap(find.byKey(const Key('counter-save')));
      await tester.pumpAndSettle();

      expect(harness.admin.writes, contains('counter:create:1:4'));

      await tester.drainSnackBars();
    });

    testWidgets('refuses a counter number that is not a number',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const ManageCountersScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-add-counter')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('counter-number')), 'abc');
      await tester.tap(find.byKey(const Key('counter-save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a number'), findsOneWidget);
      expect(harness.admin.writes, isEmpty);
    });
  });
}
