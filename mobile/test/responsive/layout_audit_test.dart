import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/features/admin/manage_staff_screen.dart';
import 'package:smartqueue/features/admin/manage_users_screen.dart';
import 'package:smartqueue/features/admin/reports_screen.dart';
import 'package:smartqueue/features/auth/login_screen.dart';
import 'package:smartqueue/features/customer/service_list_screen.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/models/staff_member.dart';
import 'package:smartqueue/models/user.dart';
import 'package:smartqueue/widgets/service_card.dart';

import '../helpers/test_harness.dart';

/// Phase 9 — §66 responsive audit.
///
/// Every screen is pumped at the three widths the brief names: 360 dp (a
/// small phone), 768 dp (a tablet) and 1280 dp (a laptop). Two things are
/// checked at each width:
///
///   * nothing overflows — a `RenderFlex` overflow is reported as a test
///     exception, so `takeException()` returning null is the assertion;
///   * the layout actually changes where it is supposed to, rather than
///     merely surviving: cards below 600 dp, a `DataTable` above it, and
///     one, two or three service cards per row.
///
/// The height is held at 1600 throughout. The audit is about the width
/// rules — every screen puts its content in a scroll view, so a short
/// viewport only proves that scrolling works, which the feature suites
/// already do.
void main() {
  late TestHarness harness;

  const double tallEnough = 1600;
  const Size phone = Size(360, tallEnough);
  const Size tablet = Size(768, tallEnough);
  const Size laptop = Size(1280, tallEnough);

  /// Every width the audit runs at, labelled for the test name.
  const Map<String, Size> widths = <String, Size>{
    '360 dp phone': phone,
    '768 dp tablet': tablet,
    '1280 dp laptop': laptop,
  };

  setUp(() async {
    harness = await TestHarness.create();
    harness.services.services = <Service>[
      sampleService(id: 1, name: 'Finance Office', code: 'FIN', waiting: 4),
      sampleService(id: 2, name: 'Registrar', code: 'REG', waiting: 0, category: 'Records'),
      sampleService(id: 3, name: 'Library Desk', code: 'LIB', waiting: 2),
    ];
    harness.admin.userList = <User>[
      sampleUser(id: 9, firstName: 'John', lastName: 'Doe'),
      sampleUser(id: 10, firstName: 'Mary', lastName: 'Atieno'),
    ];
    harness.admin.staffList = <StaffMember>[
      sampleStaffMember(id: 4, firstName: 'Jane', lastName: 'Wanjiku'),
      sampleStaffMember(id: 5, firstName: 'Peter', lastName: 'Kamau'),
    ];
  });

  /// Pumps [child] at [size] and settles, then reports any layout exception.
  Future<void> pumpAt(WidgetTester tester, Widget child, Size size) async {
    await tester.pumpScreen(harness, child, size: size);
    await tester.pumpAndSettle();
  }

  // ── no screen overflows at any of the three widths ──────────────────────

  widths.forEach((String label, Size size) {
    group('at $label', () {
      testWidgets('the service catalogue lays out cleanly', (WidgetTester tester) async {
        await pumpAt(tester, const ServiceListScreen(), size);

        expect(tester.takeException(), isNull);
        expect(find.byType(ServiceCard), findsNWidgets(3));
      });

      testWidgets('the user roster lays out cleanly', (WidgetTester tester) async {
        harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
        await pumpAt(tester, const ManageUsersScreen(), size);

        expect(tester.takeException(), isNull);
        // The row is findable in either layout, because the card and the
        // identifying table cell carry the same key.
        expect(find.byKey(const Key('admin-user-9')), findsOneWidget);
      });

      testWidgets('the staff roster lays out cleanly', (WidgetTester tester) async {
        harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
        await pumpAt(tester, const ManageStaffScreen(), size);

        expect(tester.takeException(), isNull);
        expect(find.text('Jane Wanjiku'), findsWidgets);
      });

      testWidgets('the reports console lays out cleanly', (WidgetTester tester) async {
        harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
        await pumpAt(tester, const ReportsScreen(), size);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('report-export')), findsOneWidget);
      });

      testWidgets('the sign-in form lays out cleanly', (WidgetTester tester) async {
        await pumpAt(tester, const LoginScreen(), size);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('login-email')), findsOneWidget);
        expect(find.byKey(const Key('login-submit')), findsOneWidget);
      });
    });
  });

  // ── the layout genuinely changes, it does not merely survive ────────────

  group('the breakpoint does something', () {
    testWidgets('a table on a wide screen becomes cards on a phone',
        (WidgetTester tester) async {
      harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);

      await pumpAt(tester, const ManageUsersScreen(), laptop);
      expect(find.byType(DataTable), findsOneWidget,
          reason: 'a laptop has room for a real table');

      await pumpAt(tester, const ManageUsersScreen(), phone);
      expect(find.byType(DataTable), findsNothing,
          reason: 'a DataTable on a 360 dp screen either overflows or shrinks to nothing');
      expect(find.byKey(const Key('admin-user-9')), findsOneWidget);
    });

    testWidgets('a tablet still gets the table', (WidgetTester tester) async {
      harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);

      await pumpAt(tester, const ManageUsersScreen(), tablet);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('service cards go one, two and three to a row',
        (WidgetTester tester) async {
      Future<int> cardsOnTheFirstRow(Size size) async {
        await pumpAt(tester, const ServiceListScreen(), size);
        final double firstRowY = tester.getTopLeft(find.byKey(const Key('service-card-1'))).dy;
        int count = 0;
        for (final int id in <int>[1, 2, 3]) {
          final Finder card = find.byKey(Key('service-card-$id'));
          if (card.evaluate().isEmpty) continue;
          if (tester.getTopLeft(card).dy == firstRowY) count++;
        }
        return count;
      }

      expect(await cardsOnTheFirstRow(phone), 1);
      expect(await cardsOnTheFirstRow(tablet), 2);
      expect(await cardsOnTheFirstRow(laptop), 3);
    });
  });
}
