import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/customer/service_list_screen.dart';
import 'package:smartqueue/models/service.dart';
import 'package:smartqueue/widgets/service_card.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.services.services = <Service>[
      sampleService(id: 1, name: 'Finance Office', code: 'FIN', waiting: 4),
      sampleService(id: 2, name: 'Registrar', code: 'REG', waiting: 0, category: 'Records'),
      sampleService(
        id: 3,
        name: 'Library Desk',
        code: 'LIB',
        status: ServiceStatus.closed,
        accepting: false,
        waiting: 2,
      ),
    ];
  });

  testWidgets('lists the services the server returned', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    expect(find.text('Finance Office'), findsOneWidget);
    expect(find.text('Registrar'), findsOneWidget);
    expect(find.text('Library Desk'), findsOneWidget);
    expect(find.byType(ServiceCard), findsNWidgets(3));
  });

  testWidgets('shows the live waiting count from the server', (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    // The Finance card carries the server's waiting figure, not a guess.
    expect(find.text('4'), findsWidgets);
    expect(find.text('FIN-007'), findsWidgets);
  });

  testWidgets('disables Join for a closed service and says why',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    expect(find.text('Closed'), findsWidgets);

    final Finder libraryCard = find.byKey(const Key('service-card-3'));
    final Finder joinButton = find.descendant(
      of: libraryCard,
      matching: find.widgetWithText(FilledButton, 'Join'),
    );

    final FilledButton button = tester.widget<FilledButton>(joinButton);
    expect(button.onPressed, isNull, reason: 'a closed service must not be joinable');
  });

  testWidgets('searching asks the server rather than filtering locally',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    final int callsBefore = harness.services.listCalls;

    await tester.enterText(find.byKey(const Key('service-search')), 'regis');
    // The field is debounced, so nothing should have gone out yet.
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.services.listCalls, callsBefore);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(harness.services.listCalls, greaterThan(callsBefore));
    expect(harness.services.lastSearch, 'regis');
    expect(find.text('Registrar'), findsOneWidget);
    expect(find.text('Finance Office'), findsNothing);
  });

  testWidgets('offers a way out when a search matches nothing',
      (WidgetTester tester) async {
    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('service-search')), 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('shows a retryable error when the server is unreachable',
      (WidgetTester tester) async {
    harness.services.failure = const NetworkFailure();

    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('says so plainly when there are no services at all',
      (WidgetTester tester) async {
    harness.services.services = <Service>[];

    await tester.pumpScreen(harness, const ServiceListScreen());
    await tester.pumpAndSettle();

    expect(find.text('No services yet'), findsOneWidget);
  });
}
