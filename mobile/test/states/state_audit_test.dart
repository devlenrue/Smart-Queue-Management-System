import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/admin/manage_announcements_screen.dart';
import 'package:smartqueue/features/admin/manage_staff_screen.dart';
import 'package:smartqueue/features/admin/manage_users_screen.dart';
import 'package:smartqueue/features/customer/service_list_screen.dart';
import 'package:smartqueue/features/staff/staff_history_screen.dart';
import 'package:smartqueue/features/staff/staff_statistics_screen.dart';
import 'package:smartqueue/models/announcement.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/models/staff_member.dart';
import 'package:smartqueue/models/ticket.dart';
import 'package:smartqueue/models/user.dart';
import 'package:smartqueue/widgets/empty_state.dart';
import 'package:smartqueue/widgets/error_state.dart';
import 'package:smartqueue/widgets/loading_widget.dart';

import '../helpers/test_harness.dart';

/// Phase 9 — §64 and §65, audited screen by screen.
///
/// Three states are easy to forget because the happy path hides them: the
/// moment before the data arrives, the moment it arrives empty, and the
/// moment it does not arrive at all. §64 says a screen must never be blank
/// while it loads, and §65 says an empty list must explain itself rather
/// than look broken.
///
/// Rather than repeat the same three tests in six files, the screens are
/// listed once with the fake state that produces each condition, and the
/// audit runs the same three checks over all of them.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  /// Anything that tells the user work is in progress.
  final Finder loadingAffordance = find.byWidgetPredicate(
    (Widget widget) =>
        widget is SkeletonBox ||
        widget is CircularProgressIndicator ||
        widget is LinearProgressIndicator,
    description: 'a loading affordance',
  );

  /// Pumps exactly one frame, so the screen is caught before its provider
  /// resolves. `pumpScreen` pumps a second frame, by which time the fake
  /// has already answered.
  Future<void> pumpFirstFrame(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(harness.wrap(child));
  }

  /// One screen to audit: how to reach it, and how to starve it.
  void auditScreen(
    String name,
    Widget Function() build, {
    required void Function() signIn,
    required void Function() makeEmpty,
    required void Function() makeFail,
    bool hasEmptyState = true,
  }) {
    group(name, () {
      testWidgets('shows something while it loads', (WidgetTester tester) async {
        signIn();
        await pumpFirstFrame(tester, build());

        expect(loadingAffordance, findsWidgets,
            reason: '$name is blank on its first frame (§64)');

        // Let the fake answer, so no skeleton animation outlives the test.
        await tester.pump();
        await tester.pumpAndSettle();
        expect(loadingAffordance, findsNothing);
      });

      if (hasEmptyState) {
        testWidgets('explains itself when there is nothing to show',
            (WidgetTester tester) async {
          signIn();
          makeEmpty();

          await tester.pumpScreen(harness, build());
          await tester.pumpAndSettle();

          expect(find.byType(EmptyState), findsWidgets,
              reason: '$name shows a bare empty list instead of saying why (§65)');
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('offers a retry when the server cannot be reached',
          (WidgetTester tester) async {
        signIn();
        makeFail();

        await tester.pumpScreen(harness, build());
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsWidgets);
        expect(find.text('Something went wrong'), findsWidgets);
        expect(find.text('Try again'), findsWidgets);
      });
    });
  }

  auditScreen(
    'the service catalogue',
    () => const ServiceListScreen(),
    signIn: () => harness.signIn(),
    makeEmpty: () => harness.services.services = <Service>[],
    makeFail: () => harness.services.failure = const NetworkFailure(),
  );

  auditScreen(
    'the user roster',
    () => const ManageUsersScreen(),
    signIn: () => harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2),
    makeEmpty: () => harness.admin.userList = <User>[],
    makeFail: () => harness.admin.listFailure = const NetworkFailure(),
  );

  auditScreen(
    'the staff roster',
    () => const ManageStaffScreen(),
    signIn: () => harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2),
    makeEmpty: () => harness.admin.staffList = <StaffMember>[],
    makeFail: () => harness.admin.listFailure = const NetworkFailure(),
  );

  auditScreen(
    'the announcement list',
    () => const ManageAnnouncementsScreen(),
    signIn: () => harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2),
    makeEmpty: () => harness.admin.announcementList = <ManagedAnnouncement>[],
    makeFail: () => harness.admin.listFailure = const NetworkFailure(),
  );

  auditScreen(
    'a clerk\'s history',
    () => const StaffHistoryScreen(),
    signIn: () => harness.signIn(role: UserRole.staff, id: 4),
    makeEmpty: () => harness.staff.handled = <Ticket>[],
    makeFail: () => harness.staff.readFailure = const NetworkFailure(),
  );

  auditScreen(
    'a clerk\'s statistics',
    () => const StaffStatisticsScreen(),
    signIn: () => harness.signIn(role: UserRole.staff, id: 4),
    makeEmpty: () {},
    makeFail: () => harness.staff.readFailure = const NetworkFailure(),
    // Statistics are totals, not a list: there is always a number to show.
    hasEmptyState: false,
  );

  // ── the error view says what went wrong, not just that it did ──────────

  group('the error view', () {
    testWidgets('names the failure so the user can act on it',
        (WidgetTester tester) async {
      harness.signIn();
      harness.services.failure = const NetworkFailure();

      await tester.pumpScreen(harness, const ServiceListScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget,
          reason: 'a network failure should not look like a server failure');
    });

    testWidgets('a retry actually asks the server again',
        (WidgetTester tester) async {
      harness.signIn();
      harness.services.failure = const NetworkFailure();

      await tester.pumpScreen(harness, const ServiceListScreen());
      await tester.pumpAndSettle();
      final int callsBefore = harness.services.listCalls;

      harness.services.failure = null;
      harness.services.services = <Service>[sampleService(id: 1, name: 'Finance Office')];

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(harness.services.listCalls, greaterThan(callsBefore));
      expect(find.text('Finance Office'), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });
  });
}
