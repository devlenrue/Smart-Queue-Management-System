import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/staff/widgets/ticket_action_bar.dart';
import 'package:smartqueue/repositories/staff_repository.dart';

import '../helpers/test_harness.dart';

/// The client half of the state machine (docs/queue-engine.md §1.1).
///
/// The action bar must only ever offer transitions the server would accept,
/// so a clerk is never handed a button that can only produce a 409.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.staff);
  });

  group('which actions each state allows', () {
    test('waiting may be called or skipped, nothing else', () {
      expect(
        StaffRepository.actionsFor(TicketStatus.waiting),
        <StaffAction>{StaffAction.call, StaffAction.skip},
      );
    });

    test('called may start, recall, skip or be marked a no-show', () {
      expect(
        StaffRepository.actionsFor(TicketStatus.called),
        <StaffAction>{
          StaffAction.start,
          StaffAction.recall,
          StaffAction.skip,
          StaffAction.noShow,
        },
      );
    });

    test('serving may only be completed', () {
      expect(
        StaffRepository.actionsFor(TicketStatus.serving),
        <StaffAction>{StaffAction.complete},
      );
    });

    test('terminal states allow nothing', () {
      for (final TicketStatus status in <TicketStatus>[
        TicketStatus.completed,
        TicketStatus.cancelled,
        TicketStatus.skipped,
        TicketStatus.noShow,
      ]) {
        expect(StaffRepository.actionsFor(status), isEmpty, reason: status.name);
      }
    });
  });

  testWidgets('a waiting ticket offers Call and Skip only', (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket())),
    );

    expect(find.byKey(const Key('staff-action-call')), findsOneWidget);
    expect(find.byKey(const Key('staff-action-skip')), findsOneWidget);
    expect(find.byKey(const Key('staff-action-complete')), findsNothing);
    expect(find.byKey(const Key('staff-action-start')), findsNothing);
  });

  testWidgets('a called ticket offers Start, Call again, Skip and No-show',
      (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket(status: TicketStatus.called))),
    );

    expect(find.byKey(const Key('staff-action-start')), findsOneWidget);
    expect(find.byKey(const Key('staff-action-recall')), findsOneWidget);
    expect(find.byKey(const Key('staff-action-skip')), findsOneWidget);
    expect(find.byKey(const Key('staff-action-noShow')), findsOneWidget);
    expect(find.byKey(const Key('staff-action-call')), findsNothing);
  });

  testWidgets('starting a ticket calls the server and confirms', (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket(status: TicketStatus.called))),
    );

    await tester.tap(find.byKey(const Key('staff-action-start')));
    await tester.pump();
    await tester.pump();

    expect(harness.staff.actions, contains('start'));
    expect(find.text('FIN-012 started.'), findsOneWidget);
    await tester.unmountAndDrain(harness);
  });

  testWidgets('completing a ticket calls the server', (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket(status: TicketStatus.serving))),
    );

    await tester.tap(find.byKey(const Key('staff-action-complete')));
    await tester.pump();
    await tester.pump();

    expect(harness.staff.actions, contains('complete'));
    expect(find.text('FIN-012 completed.'), findsOneWidget);
    await tester.unmountAndDrain(harness);
  });

  testWidgets('skipping asks first and does nothing if the clerk backs out',
      (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket())),
    );

    await tester.tap(find.byKey(const Key('staff-action-skip')));
    await tester.pumpAndSettle();

    expect(find.text('Skip FIN-012?'), findsOneWidget);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(harness.staff.actions, isEmpty);
  });

  testWidgets('skipping goes through once confirmed', (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket())),
    );

    await tester.tap(find.byKey(const Key('staff-action-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Skip'));
    await tester.pump();
    await tester.pump();

    expect(harness.staff.actions, contains('skip'));
    await tester.unmountAndDrain(harness);
  });

  testWidgets('a finished ticket offers nothing at all', (WidgetTester tester) async {
    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket(status: TicketStatus.completed))),
    );

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining('nothing left to do'), findsOneWidget);
  });

  testWidgets('shows the server\'s refusal rather than pretending it worked',
      (WidgetTester tester) async {
    harness.staff.actionFailure = const ConflictFailure(
      message: 'That ticket has already been served.',
      code: 'INVALID_STATE_TRANSITION',
    );

    await tester.pumpScreen(
      harness,
      Scaffold(body: TicketActionBar(ticket: sampleTicket(status: TicketStatus.serving))),
    );

    await tester.tap(find.byKey(const Key('staff-action-complete')));
    await tester.pump();
    await tester.pump();

    expect(find.text('That ticket has already been served.'), findsOneWidget);
  });
}
