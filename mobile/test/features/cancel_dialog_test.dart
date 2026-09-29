import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/errors/failure.dart';
import 'package:smartqueue/features/customer/ticket_screen.dart';
import 'package:smartqueue/models/ticket.dart';
import 'package:smartqueue/widgets/confirmation_dialog.dart';

import '../helpers/test_harness.dart';

/// §27: cancelling gives up your place, so it must never happen on a single
/// stray tap, and the server's refusal must be shown rather than swallowed.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.tickets.activeTickets = <Ticket>[sampleTicket()];
    harness.tickets.positions = <TicketPosition>[samplePosition()];
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ticket-cancel')));
    await tester.pumpAndSettle();
  }

  testWidgets('asks for confirmation before cancelling', (WidgetTester tester) async {
    await openDialog(tester);

    expect(find.byType(ConfirmationDialog), findsOneWidget);
    expect(find.text('Leave the queue?'), findsOneWidget);
    expect(find.textContaining('FIN-012'), findsWidgets);
    expect(harness.tickets.cancelCalls, 0, reason: 'nothing may be sent until confirmed');

    await tester.tap(find.text('Keep my place'));
    await tester.settlePolling(harness);
  });

  testWidgets('backing out of the dialog leaves the ticket alone',
      (WidgetTester tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Keep my place'));
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmationDialog), findsNothing);
    expect(harness.tickets.cancelCalls, 0);

    await tester.settlePolling(harness);
  });

  testWidgets('confirming sends the cancellation for the right ticket',
      (WidgetTester tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Cancel ticket'));
    await tester.pumpAndSettle();

    expect(harness.tickets.cancelCalls, 1);
    expect(harness.tickets.cancelledId, 55);

    await tester.settlePolling(harness);
  });

  testWidgets('shows the server refusal when cancellation is not allowed',
      (WidgetTester tester) async {
    harness.tickets.cancelFailure = const ConflictFailure(
      message: 'This service does not allow cancelling a ticket.',
      code: 'CANCELLATION_NOT_ALLOWED',
    );

    await openDialog(tester);
    await tester.tap(find.text('Cancel ticket'));
    await tester.pumpAndSettle();

    expect(find.text('This service does not allow cancelling a ticket.'), findsOneWidget);

    await tester.settlePolling(harness);
  });

  testWidgets('shows the conflict when staff called the ticket first',
      (WidgetTester tester) async {
    // The §60 race: the customer taps Cancel at the same moment a counter
    // calls them. The server wins; the UI must say so.
    harness.tickets.cancelFailure = const ConflictFailure(
      message: 'Ticket has already been called and cannot be cancelled.',
      code: 'INVALID_STATE_TRANSITION',
    );

    await openDialog(tester);
    await tester.tap(find.text('Cancel ticket'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ticket has already been called and cannot be cancelled.'),
      findsOneWidget,
    );

    await tester.settlePolling(harness);
  });

  testWidgets('the dialog is styled as destructive', (WidgetTester tester) async {
    await openDialog(tester);

    final ConfirmationDialog dialog =
        tester.widget<ConfirmationDialog>(find.byType(ConfirmationDialog));
    expect(dialog.isDestructive, isTrue);
    expect(dialog.confirmLabel, 'Cancel ticket');
    expect(dialog.cancelLabel, 'Keep my place');

    await tester.tap(find.text('Keep my place'));
    await tester.settlePolling(harness);
  });

  testWidgets('a ticket that is being served offers no cancel button at all',
      (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket(status: TicketStatus.serving)];
    harness.tickets.positions = <TicketPosition>[
      samplePosition(status: TicketStatus.serving, position: null),
    ];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.byKey(const Key('ticket-cancel')), findsNothing);

    await tester.settlePolling(harness);
  });
}
