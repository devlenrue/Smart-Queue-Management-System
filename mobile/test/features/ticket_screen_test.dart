import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/features/customer/ticket_screen.dart';
import 'package:smartqueue/models/counter.dart';
import 'package:smartqueue/models/ticket.dart';

import '../helpers/test_harness.dart';

/// §44/§45. The screen a customer watches while they wait.
///
/// Every test winds the polling loop to its end with [PumpX.settlePolling]
/// so no timer outlives the widget tree.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  testWidgets('shows the ticket number issued by the server', (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket(ticketNumber: 'FIN-012')];
    harness.tickets.positions = <TicketPosition>[samplePosition()];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.byKey(const Key('ticket-number')), findsOneWidget);
    expect(find.text('FIN-012'), findsWidgets);

    await tester.settlePolling(harness);
  });

  testWidgets('shows position, people ahead and the estimate while waiting',
      (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket()];
    harness.tickets.positions = <TicketPosition>[
      samplePosition(position: 3, peopleAhead: 2, estimatedWaitMinutes: 10),
    ];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.byKey(const Key('ticket-position')), findsOneWidget);
    expect(find.text('3rd'), findsOneWidget);
    expect(find.text('2 people ahead of you'), findsOneWidget);
    expect(find.text('about 10 minutes'), findsOneWidget);

    await tester.settlePolling(harness);
  });

  testWidgets('updates when the next poll moves the customer up the queue',
      (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket()];
    harness.tickets.positions = <TicketPosition>[
      samplePosition(position: 3, peopleAhead: 2),
      samplePosition(position: 1, peopleAhead: 0, estimatedWaitMinutes: 0),
    ];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();
    expect(find.text('3rd'), findsOneWidget);

    // Wind on by exactly one poll interval.
    await tester.pump(harness.prefs.readPollInterval());
    await tester.pump();

    expect(find.text('1st'), findsOneWidget);
    expect(find.text('You are next'), findsOneWidget);

    await tester.settlePolling(harness);
  });

  testWidgets('replaces the position panel with a call-to-counter banner',
      (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket(status: TicketStatus.called)];
    harness.tickets.positions = <TicketPosition>[
      samplePosition(
        status: TicketStatus.called,
        position: null,
        counter: const CounterSummary(id: 1, counterNumber: 2, name: 'Counter 2'),
      ),
    ];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.text('It is your turn'), findsOneWidget);
    expect(find.text('Please go to Counter 2 now.'), findsOneWidget);
    expect(find.byKey(const Key('ticket-position')), findsNothing);

    await tester.settlePolling(harness);
  });

  testWidgets('offers Cancel only while the ticket is still waiting',
      (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket()];
    harness.tickets.positions = <TicketPosition>[samplePosition()];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.byKey(const Key('ticket-cancel')), findsOneWidget);

    await tester.settlePolling(harness);
  });

  testWidgets('hides Cancel once the ticket has been called', (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket(status: TicketStatus.called)];
    harness.tickets.positions = <TicketPosition>[
      samplePosition(status: TicketStatus.called, position: null),
    ];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.byKey(const Key('ticket-cancel')), findsNothing);

    await tester.settlePolling(harness);
  });

  testWidgets('explains a completed ticket instead of showing a position',
      (WidgetTester tester) async {
    harness.tickets.tickets = <Ticket>[sampleTicket(status: TicketStatus.completed)];
    harness.tickets.positions = <TicketPosition>[
      samplePosition(status: TicketStatus.completed, position: null),
    ];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pumpAndSettle();

    expect(find.text('This visit is finished. Thank you for your patience.'), findsOneWidget);
    expect(find.byKey(const Key('ticket-cancel')), findsNothing);
  });

  testWidgets('shows the ticket details the server sent', (WidgetTester tester) async {
    harness.tickets.activeTickets = <Ticket>[sampleTicket()];
    harness.tickets.positions = <TicketPosition>[samplePosition()];

    await tester.pumpScreen(harness, const TicketScreen(ticketId: 55));
    await tester.pump();

    expect(find.text('Ticket details'), findsOneWidget);
    expect(find.text('Finance Office (FIN)'), findsOneWidget);
    expect(find.text('2026-09-29'), findsOneWidget);

    await tester.settlePolling(harness);
  });
}
