import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../models/notification.dart';
import '../../providers/customer_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/notification_tile.dart';

/// §48. The in-app inbox.
///
/// §82 rules out push infrastructure, so "notification" here means a row the
/// server wrote to `notifications` when something happened to your ticket.
/// Tapping one marks it read and jumps to the ticket it refers to.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final double remaining = _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < 300) {
      unawaited(ref.read(notificationsProvider.notifier).loadMore().catchError((Object _) {}));
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      await ref.read(notificationsProvider.notifier).markRead(notification.id);
    }
    if (!mounted) return;
    if (notification.ticketId != null) {
      context.push(RoutePaths.ticketDetailOf(notification.ticketId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<AppNotification>> notifications = ref.watch(notificationsProvider);
    final int unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: <Widget>[
          if (unread > 0)
            TextButton(
              key: const Key('mark-all-read'),
              onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Announcements',
            onPressed: () => context.push(RoutePaths.announcements),
            icon: const Icon(Icons.campaign_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: notifications.when(
          loading: () => const SkeletonList(itemHeight: 72),
          error: (Object error, _) => ListView(
            children: <Widget>[
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
              ErrorState(
                error: error,
                onRetry: () => ref.read(notificationsProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (PagedState<AppNotification> state) {
            if (state.isEmpty) {
              return ListView(
                children: <Widget>[
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'No alerts yet',
                    message: 'We will let you know here when your turn is close '
                        'and when you are called.',
                  ),
                ],
              );
            }

            return ListView.separated(
              controller: _controller,
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                if (index >= state.items.length) return const LoadMoreIndicator();
                final AppNotification item = state.items[index];
                return NotificationTile(
                  key: Key('notification-${item.id}'),
                  notification: item,
                  onTap: () => _open(item),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
