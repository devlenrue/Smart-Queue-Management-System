import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/constants/enums.dart';
import 'package:smartqueue/features/admin/manage_announcements_screen.dart';
import 'package:smartqueue/features/admin/queue_board_screen.dart';
import 'package:smartqueue/features/admin/queue_monitor_screen.dart';
import 'package:smartqueue/features/admin/system_settings_screen.dart';
import 'package:smartqueue/models/announcement.dart';
import 'package:smartqueue/models/counter.dart';
import 'package:smartqueue/models/queue.dart';
import 'package:smartqueue/models/system_setting.dart';
import 'package:smartqueue/widgets/app_button.dart';
import 'package:smartqueue/models/ticket.dart';

import '../helpers/test_harness.dart';

/// §54, §11, §14 — the live board, the composer and the settings editor.
void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    harness.signIn(role: UserRole.admin, firstName: 'Admin', id: 2);
  });

  group('queue monitor', () {
    testWidgets('lists one card per live queue', (WidgetTester tester) async {
      harness.queues.queueList = <QueueStatusView>[
        sampleQueueStatus(waitingCount: 6),
      ];

      await tester.pumpScreen(harness, const QueueMonitorScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-queue-1')), findsOneWidget);
      expect(find.text('Finance Office'), findsOneWidget);
      expect(find.text('6'), findsWidgets);
      expect(find.textContaining('Now serving FIN-009'), findsOneWidget);
    });

    testWidgets('says so when nobody has opened a queue today',
        (WidgetTester tester) async {
      harness.queues.queueList = <QueueStatusView>[];

      await tester.pumpScreen(harness, const QueueMonitorScreen());
      await tester.pumpAndSettle();

      expect(find.text('No queues open'), findsOneWidget);
    });
  });

  group('live board', () {
    setUp(() {
      harness.queues.queueList = <QueueStatusView>[sampleQueueStatus()];
      harness.queues.monitorCounters = <ServiceCounter>[
        sampleServiceCounter(id: 1, counterNumber: 1, name: 'Finance Counter 1', currentTicket: 'FIN-009'),
        sampleServiceCounter(
          id: 2,
          counterNumber: 2,
          name: 'Finance Counter 2',
          status: CounterStatus.offline,
          staffId: null,
          staffName: null,
        ),
      ];
      harness.queues.monitorWaiting = <Ticket>[
        sampleTicket(id: 11, ticketNumber: 'FIN-010', customer: sampleCustomer(fullName: 'Alice Kamau')),
        sampleTicket(
          id: 12,
          ticketNumber: 'FIN-011',
          waitedMinutes: 34,
          customer: sampleCustomer(fullName: 'Brian Otieno'),
        ),
      ];
    });

    testWidgets('shows every counter and the whole waiting list',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const QueueBoardScreen(serviceId: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('board-counter-1')), findsOneWidget);
      expect(find.byKey(const Key('board-counter-2')), findsOneWidget);
      expect(find.text('FIN-009'), findsWidgets);
      expect(find.byKey(const Key('board-ticket-11')), findsOneWidget);
      expect(find.byKey(const Key('board-ticket-12')), findsOneWidget);
      expect(find.text('Waiting (2)'), findsOneWidget);

      await tester.unmountAndDrain(harness);
    });

    testWidgets('is read-only — no call or complete buttons anywhere',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const QueueBoardScreen(serviceId: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call-next')), findsNothing);
      expect(find.byKey(const Key('call-ticket-11')), findsNothing);

      await tester.unmountAndDrain(harness);
    });

    testWidgets('shows an empty board for a service with no queue today',
        (WidgetTester tester) async {
      harness.queues.queueList = <QueueStatusView>[];

      await tester.pumpScreen(harness, const QueueBoardScreen(serviceId: 99));
      await tester.pumpAndSettle();

      expect(find.text('No queue today'), findsOneWidget);
    });
  });

  group('announcements', () {
    setUp(() {
      harness.admin.announcementList = <ManagedAnnouncement>[
        sampleManagedAnnouncement(id: 1, title: 'Draft notice'),
        sampleManagedAnnouncement(
          id: 2,
          title: 'Live notice',
          status: AnnouncementStatus.published,
        ),
      ];
    });

    testWidgets('marks which notices are drafts and which are live',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const ManageAnnouncementsScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-announcement-1')), findsOneWidget);
      expect(find.text('Draft'), findsWidgets);
      expect(find.text('Published'), findsWidgets);
      // A draft offers Publish; a published notice offers Archive instead.
      expect(find.byKey(const Key('admin-announcement-publish-1')), findsOneWidget);
      expect(find.byKey(const Key('admin-announcement-publish-2')), findsNothing);
      expect(find.byKey(const Key('admin-announcement-archive-2')), findsOneWidget);
    });

    testWidgets('publishing warns about the fan-out before it happens',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const ManageAnnouncementsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-announcement-publish-1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Every active customer will be notified once'), findsOneWidget);
      expect(harness.admin.writes, isEmpty);

      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Publish')),
      );
      await tester.pumpAndSettle();

      expect(harness.admin.writes, contains('announcement:1:publish'));
    });

    testWidgets('filters to drafts only', (WidgetTester tester) async {
      await tester.pumpScreen(harness, const ManageAnnouncementsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin-announcement-filter-draft')));
      await tester.pumpAndSettle();

      expect(find.text('Draft notice'), findsOneWidget);
      expect(find.text('Live notice'), findsNothing);
    });
  });

  group('system settings', () {
    setUp(() {
      harness.signIn(role: UserRole.superAdmin, firstName: 'Super', id: 1);
      harness.admin.settingsList = <SystemSetting>[
        sampleSystemSetting(),
        sampleSystemSetting(
          key: 'allow_registration',
          value: 'true',
          description: 'Whether the public may create accounts',
        ),
      ];
    });

    testWidgets('renders a switch for a boolean and a field for the rest',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const SystemSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('setting-institution_name')), findsOneWidget);
      expect(find.byKey(const Key('setting-allow_registration')), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Institution name'), findsOneWidget);
    });

    testWidgets('only enables Save once something has actually changed',
        (WidgetTester tester) async {
      await tester.pumpScreen(harness, const SystemSettingsScreen());
      await tester.pumpAndSettle();

      expect(
        tester.widget<AppButton>(find.byKey(const Key('settings-save'))).onPressed,
        isNull,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(harness.admin.writes, contains('settings:allow_registration'));
    });
  });
}
