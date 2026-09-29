import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/core/theme/app_theme.dart';
import 'package:smartqueue/core/theme/status_palette.dart';
import 'package:smartqueue/widgets/status_badge.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders the word for every ticket status', (WidgetTester tester) async {
    for (final TicketStatus status in TicketStatus.values) {
      await tester.pumpWidget(
        host(Builder(builder: (BuildContext c) => StatusBadge.ticket(c, status))),
      );
      expect(find.text(status.label), findsOneWidget, reason: 'missing label for $status');
    }
  });

  testWidgets('pairs every status with an icon, so colour is never the only cue',
      (WidgetTester tester) async {
    for (final TicketStatus status in TicketStatus.values) {
      await tester.pumpWidget(
        host(Builder(builder: (BuildContext c) => StatusBadge.ticket(c, status))),
      );
      expect(find.byIcon(StatusPalette.iconOfTicket(status)), findsOneWidget);
    }
  });

  test('gives each ticket status its own colour', () {
    const StatusPalette palette = StatusPalette.light;
    final Set<Color> colours =
        TicketStatus.values.map(palette.ofTicket).toSet();
    expect(colours.length, TicketStatus.values.length);
  });

  testWidgets('exposes the status to screen readers', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

    await tester.pumpWidget(
      host(Builder(builder: (BuildContext c) => StatusBadge.ticket(c, TicketStatus.called))),
    );
    expect(find.bySemanticsLabel('Status: Called'), findsOneWidget);
  });

  testWidgets('renders queue, service and counter variants', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext c) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              StatusBadge.queue(c, QueueStatus.paused),
              StatusBadge.service(c, ServiceStatus.open),
              StatusBadge.counter(c, CounterStatus.busy),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
  });

  testWidgets('the dense variant still shows its label', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext c) =>
              StatusBadge.ticket(c, TicketStatus.noShow, dense: true),
        ),
      ),
    );
    expect(find.text('No show'), findsOneWidget);
  });
}
