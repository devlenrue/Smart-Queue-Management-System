import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/admin/manage_users_screen.dart';
import 'package:smartqueue/features/admin/user_detail_screen.dart';
import 'package:smartqueue/models/user.dart';
import 'package:smartqueue/repositories/admin_repository.dart';

import '../helpers/test_harness.dart';

/// §9, §40 — user administration.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
    harness.admin.userList = <User>[
      sampleUser(id: 9, firstName: 'John', lastName: 'Doe'),
      sampleUser(id: 10, firstName: 'Mary', lastName: 'Atieno'),
      sampleUser(
        id: 4,
        firstName: 'Jane',
        lastName: 'Wanjiku',
        email: 'jane.staff@smartqueue.test',
        role: UserRole.staff,
      ),
    ];
  });

  testWidgets('lists every account with its role and status',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageUsersScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-user-9')), findsOneWidget);
    expect(find.byKey(const Key('admin-user-4')), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Staff'), findsWidgets);
    expect(find.text('Active'), findsWidgets);
  });

  testWidgets('sends the typed search to the server rather than filtering locally',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageUsersScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('admin-user-search')), 'mary');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(harness.admin.lastUserSearch, 'mary');
    expect(find.text('Mary Atieno'), findsOneWidget);
    expect(find.text('John Doe'), findsNothing);
  });

  testWidgets('filters by role through the same query', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageUsersScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-user-role-staff')));
    await tester.pumpAndSettle();

    expect(harness.admin.lastUserRole, UserRole.staff);
    expect(find.text('Jane Wanjiku'), findsOneWidget);
    expect(find.text('John Doe'), findsNothing);
  });

  testWidgets('suspends an account from the row', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ManageUsersScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-user-suspend-9')));
    await tester.pumpAndSettle();

    expect(harness.admin.writes, contains('user:9:status:suspended'));
    expect(find.textContaining('is now suspended'), findsOneWidget);

    await tester.drainSnackBars();
  });

  testWidgets('reports a rejected suspension instead of pretending it worked',
      (WidgetTester tester) async {
    harness.admin.actionFailure = const ConflictFailure('That account cannot be suspended.');

    await tester.pumpScreen(harness, const ManageUsersScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-user-suspend-9')));
    await tester.pumpAndSettle();

    expect(find.text('That account cannot be suspended.'), findsOneWidget);

    await tester.drainSnackBars();
  });

  testWidgets('will not let an administrator act on their own row',
      (WidgetTester tester) async {
    harness.admin.userList = <User>[
      sampleUser(id: 2, firstName: 'Admin', lastName: 'User', role: UserRole.admin),
    ];

    await tester.pumpScreen(harness, const ManageUsersScreen());
    await tester.pumpAndSettle();

    final IconButton button = tester.widget<IconButton>(
      find.byKey(const Key('admin-user-suspend-2')),
    );
    expect(button.onPressed, isNull);
  });

  group('user detail', () {
    testWidgets('shows the activity behind the account', (WidgetTester tester) async {
      harness.admin.userDetailValue = sampleUserDetail(user: sampleUser(id: 9));

      await tester.pumpScreen(harness, const UserDetailScreen(userId: 9));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsWidgets);
      expect(find.byKey(const Key('admin-user-tickets')), findsOneWidget);
      expect(find.text('15'), findsWidgets);
      expect(find.textContaining('73% of all visits'), findsOneWidget);
    });

    testWidgets('offers no role controls to an ordinary administrator',
        (WidgetTester tester) async {
      harness.admin.userDetailValue = sampleUserDetail(user: sampleUser(id: 9));

      await tester.pumpScreen(harness, const UserDetailScreen(userId: 9));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-user-suspend')), findsOneWidget);
      expect(find.byKey(const Key('admin-user-role-staff')), findsNothing);
      expect(find.byKey(const Key('admin-user-delete')), findsNothing);
    });

    testWidgets('gives a super administrator the role and delete controls',
        (WidgetTester tester) async {
      harness.signIn(role: UserRole.superAdmin, firstName: 'Super', id: 1);
      harness.admin.userDetailValue = sampleUserDetail(user: sampleUser(id: 9));

      await tester.pumpScreen(harness, const UserDetailScreen(userId: 9));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-user-role-staff')), findsOneWidget);
      expect(find.byKey(const Key('admin-user-delete')), findsOneWidget);
    });

    testWidgets('explains itself instead of offering buttons on your own account',
        (WidgetTester tester) async {
      harness.admin.userDetailValue = sampleUserDetail(
        user: sampleUser(id: 2, firstName: 'Admin', lastName: 'User', role: UserRole.admin),
      );

      await tester.pumpScreen(harness, const UserDetailScreen(userId: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('This is your own account'), findsOneWidget);
      expect(find.byKey(const Key('admin-user-suspend')), findsNothing);
    });
  });

  group('AdminRepository.canManage', () {
    test('nobody administers themselves', () {
      expect(
        AdminRepository.canManage(
          actor: UserRole.superAdmin,
          target: sampleUser(id: 1),
          actorId: 1,
        ),
        isFalse,
      );
    });

    test('an admin may not touch another admin, a super admin may', () {
      final User admin = sampleUser(id: 3, role: UserRole.admin);
      expect(
        AdminRepository.canManage(actor: UserRole.admin, target: admin, actorId: 2),
        isFalse,
      );
      expect(
        AdminRepository.canManage(actor: UserRole.superAdmin, target: admin, actorId: 1),
        isTrue,
      );
    });

    test('only a super admin hands out roles', () {
      expect(AdminRepository.assignableRolesFor(UserRole.admin), isEmpty);
      expect(AdminRepository.assignableRolesFor(UserRole.superAdmin), hasLength(4));
    });
  });
}
