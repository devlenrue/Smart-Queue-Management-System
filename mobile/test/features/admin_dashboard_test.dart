import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/core/routing/app_router.dart';
import 'package:smartqueue/core/routing/route_paths.dart';
import 'package:smartqueue/features/admin/admin_dashboard_screen.dart';
import 'package:smartqueue/features/admin/admin_shell.dart';
import 'package:smartqueue/models/admin_dashboard.dart';

import '../helpers/test_harness.dart';

/// §31, §42 — the institution-wide dashboard.
///
/// It polls on a multiple of the configured interval, so every test ends
/// with [PumpX.unmountAndDrain] at that longer interval; otherwise the test
/// finishes with a timer still pending.
void main() {
  late TestHarness harness;
  const Duration adminInterval = Duration(seconds: 15);

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.admin, firstName: 'Admin');
  });

  testWidgets('shows the headline figures for the whole institution',
      (WidgetTester tester) async {
    harness.admin.dashboardValue = sampleAdminDashboard(waiting: 34, served: 23, staffOnDuty: 5);

    await tester.pumpScreen(harness, const AdminDashboardScreen());
    await tester.pump();

    expect(find.byKey(const Key('admin-stat-waiting')), findsOneWidget);
    expect(find.text('34'), findsWidgets);
    expect(find.byKey(const Key('admin-stat-served')), findsOneWidget);
    expect(find.text('23'), findsWidgets);
    expect(find.byKey(const Key('admin-stat-staff')), findsOneWidget);
    expect(find.text('Staff on duty'), findsOneWidget);

    await tester.unmountAndDrain(harness, interval: adminInterval);
  });

  testWidgets('draws both charts from the one dashboard read',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const AdminDashboardScreen());
    await tester.pump();

    expect(find.byKey(const Key('admin-served-chart')), findsOneWidget);
    expect(find.byKey(const Key('admin-status-chart')), findsOneWidget);
    // The series is dense, so every day in the window has a bar with its
    // own count printed above it.
    expect(find.text('63'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
    expect(harness.admin.dashboardCalls, 1);

    await tester.unmountAndDrain(harness, interval: adminInterval);
  });

  testWidgets('lists every service with its own figures', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const AdminDashboardScreen());
    await tester.pump();

    expect(find.byKey(const Key('admin-service-row-1')), findsOneWidget);
    expect(find.byKey(const Key('admin-service-row-2')), findsOneWidget);
    expect(find.textContaining('Finance Office'), findsWidgets);
    expect(find.textContaining('Registrar'), findsWidgets);

    await tester.unmountAndDrain(harness, interval: adminInterval);
  });

  testWidgets('names the busiest service so it can be dealt with first',
      (WidgetTester tester) async {
    harness.admin.dashboardValue = sampleAdminDashboard(
      byService: const <AdminServiceRow>[
        AdminServiceRow(
          serviceId: 1,
          name: 'Finance Office',
          code: 'FIN',
          status: ServiceStatus.open,
          issued: 4,
          waiting: 2,
          serving: 1,
          completed: 1,
          cancelled: 0,
          averageWaitMinutes: 5,
        ),
        AdminServiceRow(
          serviceId: 5,
          name: 'Library',
          code: 'LIB',
          status: ServiceStatus.open,
          issued: 20,
          waiting: 17,
          serving: 1,
          completed: 2,
          cancelled: 0,
          averageWaitMinutes: 30,
        ),
      ],
    );

    await tester.pumpScreen(harness, const AdminDashboardScreen());
    await tester.pump();

    expect(find.textContaining('Busiest right now: Library'), findsOneWidget);
    expect(find.textContaining('17 people waiting'), findsOneWidget);

    await tester.unmountAndDrain(harness, interval: adminInterval);
  });

  testWidgets('shows the failure rather than an empty board when the first read fails',
      (WidgetTester tester) async {
    harness.admin.dashboardFailure = const NetworkFailure('No connection');

    await tester.pumpScreen(harness, const AdminDashboardScreen());
    await tester.pump();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.byKey(const Key('admin-stat-waiting')), findsNothing);

    await tester.unmountAndDrain(harness, interval: adminInterval);
  });

  group('AdminShell', () {
    test('hides system settings from an ordinary administrator', () {
      final List<AdminDestination> forAdmin = AdminShell.visibleTo(UserRole.admin);
      final List<AdminDestination> forSuper = AdminShell.visibleTo(UserRole.superAdmin);

      expect(
        forAdmin.map((AdminDestination d) => d.label),
        isNot(contains('System settings')),
      );
      expect(forSuper.map((AdminDestination d) => d.label), contains('System settings'));
    });

    test('each role lands in its own console', () {
      expect(homeFor(UserRole.customer), RoutePaths.home);
      expect(homeFor(UserRole.staff), RoutePaths.staffHome);
      expect(homeFor(UserRole.admin), RoutePaths.adminHome);
      expect(homeFor(UserRole.superAdmin), RoutePaths.adminHome);
    });

    test('keeps the parent destination highlighted on a detail route', () {
      final List<AdminDestination> items = AdminShell.visibleTo(UserRole.superAdmin);

      final int users = AdminShell.indexOf('/admin/users', items);
      expect(AdminShell.indexOf('/admin/users/9', items), users);

      final int queues = AdminShell.indexOf('/admin/queues', items);
      expect(AdminShell.indexOf('/admin/queues/3', items), queues);
    });
  });
}
