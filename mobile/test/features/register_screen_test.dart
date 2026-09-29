import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/auth/register_screen.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  Future<void> fillValidForm(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('register-firstName')), 'Grace');
    await tester.enterText(find.byKey(const Key('register-lastName')), 'Wanjiru');
    await tester.enterText(find.byKey(const Key('register-email')), 'grace@smartqueue.test');
    await tester.enterText(find.byKey(const Key('register-phone')), '+254712345678');
    await tester.enterText(find.byKey(const Key('register-password')), 'Password123');
    await tester.enterText(find.byKey(const Key('register-confirmPassword')), 'Password123');
    await tester.tap(find.byKey(const Key('register-terms')));
    await tester.pump();
  }

  testWidgets('offers no role selector — the server always creates a customer',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const RegisterScreen());

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Staff'), findsNothing);
    expect(find.text('Administrator'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('blocks submission until every field is valid', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const RegisterScreen());

    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();

    expect(harness.auth.registerCalls, 0);
    expect(find.text('First name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
  });

  testWidgets('catches a password mismatch before the request', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const RegisterScreen());

    await fillValidForm(tester);
    await tester.enterText(
      find.byKey(const Key('register-confirmPassword')),
      'DifferentPass1',
    );
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();

    expect(harness.auth.registerCalls, 0);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('will not submit until the terms box is ticked', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const RegisterScreen());

    await tester.enterText(find.byKey(const Key('register-firstName')), 'Grace');
    await tester.enterText(find.byKey(const Key('register-lastName')), 'Wanjiru');
    await tester.enterText(find.byKey(const Key('register-email')), 'grace@smartqueue.test');
    await tester.enterText(find.byKey(const Key('register-phone')), '+254712345678');
    await tester.enterText(find.byKey(const Key('register-password')), 'Password123');
    await tester.enterText(find.byKey(const Key('register-confirmPassword')), 'Password123');

    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();

    expect(harness.auth.registerCalls, 0);
    expect(find.text('Please accept the terms to continue.'), findsOneWidget);
  });

  testWidgets('registers when everything is filled in', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const RegisterScreen());

    await fillValidForm(tester);
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(harness.auth.registerCalls, 1);
    expect(harness.auth.lastEmail, 'grace@smartqueue.test');
  });

  testWidgets('surfaces a duplicate email from the server on the email field',
      (WidgetTester tester) async {
    harness.auth.registerFailure = const ValidationFailure(
      message: 'Validation failed',
      fieldErrors: <String, String>{'email': 'Email is already registered'},
    );

    await tester.pumpScreen(harness, const RegisterScreen());
    await fillValidForm(tester);
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email is already registered'), findsOneWidget);
  });

  testWidgets('shows the password strength meter as the user types',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const RegisterScreen());

    await tester.enterText(find.byKey(const Key('register-password')), 'abc1');
    await tester.pump();
    expect(find.text('Weak'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('register-password')), 'abcdefghijk1!');
    await tester.pump();
    expect(find.text('Strong'), findsOneWidget);
  });
}
