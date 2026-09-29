import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/auth/login_screen.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  testWidgets('shows the sign-in form', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const LoginScreen());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('will not call the API when the form is empty', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const LoginScreen());

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(harness.auth.loginCalls, 0);
    expect(find.text('Email is required'), findsOneWidget);
  });

  testWidgets('rejects a malformed email before sending it', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const LoginScreen());

    await tester.enterText(find.byKey(const Key('login-email')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('login-password')), 'Password123!');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(harness.auth.loginCalls, 0);
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('sends trimmed credentials when the form is valid', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const LoginScreen());

    await tester.enterText(find.byKey(const Key('login-email')), '  john.doe@smartqueue.test ');
    await tester.enterText(find.byKey(const Key('login-password')), 'Password123!');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(harness.auth.loginCalls, 1);
    expect(harness.auth.lastEmail, 'john.doe@smartqueue.test');
    expect(harness.auth.lastPassword, 'Password123!');
  });

  testWidgets('shows the server message when credentials are wrong',
      (WidgetTester tester) async {
    harness.auth.loginFailure = const AuthFailure(
      message: 'Email or password is incorrect',
      code: 'INVALID_CREDENTIALS',
      statusCode: 401,
    );

    await tester.pumpScreen(harness, const LoginScreen());

    await tester.enterText(find.byKey(const Key('login-email')), 'john.doe@smartqueue.test');
    await tester.enterText(find.byKey(const Key('login-password')), 'WrongPass1');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form-error')), findsOneWidget);
    expect(find.text('Email or password is incorrect'), findsOneWidget);
  });

  testWidgets('shows a suspended-account message from the server',
      (WidgetTester tester) async {
    harness.auth.loginFailure = const AuthFailure(
      message: 'This account has been suspended. Contact an administrator.',
      code: 'ACCOUNT_SUSPENDED',
      statusCode: 403,
    );

    await tester.pumpScreen(harness, const LoginScreen());

    await tester.enterText(find.byKey(const Key('login-email')), 'john.doe@smartqueue.test');
    await tester.enterText(find.byKey(const Key('login-password')), 'Password123!');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('This account has been suspended. Contact an administrator.'),
      findsOneWidget,
    );
  });

  testWidgets('paints a 422 field error next to the field it belongs to',
      (WidgetTester tester) async {
    harness.auth.loginFailure = const ValidationFailure(
      message: 'Validation failed',
      fieldErrors: <String, String>{'email': 'No account uses that address'},
    );

    await tester.pumpScreen(harness, const LoginScreen());

    await tester.enterText(find.byKey(const Key('login-email')), 'ghost@smartqueue.test');
    await tester.enterText(find.byKey(const Key('login-password')), 'Password123!');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('No account uses that address'), findsOneWidget);
  });

  testWidgets('hides the password by default and reveals it on request',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const LoginScreen());

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
