import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/announcement.dart';
import '../../providers/admin_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'admin_shell.dart';

/// The announcement composer's list (§11).
///
/// Unlike the public board this shows drafts and archived notices, because
/// the whole point of a draft is that you can see it before anybody else
/// does. Publishing is the only action that fans out notifications, and it
/// only does so once — the server ignores a re-publish.
class ManageAnnouncementsScreen extends ConsumerWidget {
  const ManageAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedState<ManagedAnnouncement>> async =
        ref.watch(adminAnnouncementsProvider);
    final AnnouncementStatus? filter = ref.watch(announcementFilterProvider);

    return AdminPage(
      title: 'Announcements',
      subtitle: async.valueOrNull == null ? null : '${async.valueOrNull!.meta.total} notices',
      onRefresh: () => ref.read(adminAnnouncementsProvider.notifier).refresh(),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admin-add-announcement'),
        onPressed: () => context.go(RoutePaths.adminAnnouncementNew),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Compose'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final AnnouncementStatus status in AnnouncementStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        key: Key('admin-announcement-filter-${status.wire}'),
                        label: Text(status.label),
                        selected: filter == status,
                        onSelected: (bool on) => ref
                            .read(announcementFilterProvider.notifier)
                            .set(on ? status : null),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const SkeletonList(count: 4),
              error: (Object error, StackTrace _) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(adminAnnouncementsProvider),
              ),
              data: (PagedState<ManagedAnnouncement> page) {
                if (page.isEmpty) {
                  return const EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'Nothing composed yet',
                    message: 'Write a notice and publish it to every customer.',
                  );
                }
                return ListView(
                  padding: Responsive.pagePadding(context),
                  children: <Widget>[
                    for (final ManagedAnnouncement item in page.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AnnouncementTile(item: item),
                      ),
                    const SizedBox(height: 80),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementTile extends ConsumerStatefulWidget {
  const _AnnouncementTile({required this.item});

  final ManagedAnnouncement item;

  @override
  ConsumerState<_AnnouncementTile> createState() => _AnnouncementTileState();
}

class _AnnouncementTileState extends ConsumerState<_AnnouncementTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showSuccessSnackBar(context, success);
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Publish this notice?',
      message: 'Every active customer will be notified once. Publishing again '
          'later will not notify them a second time.',
      confirmLabel: 'Publish',
    );
    if (!confirmed) return;
    await _run(
      () => ref.read(adminActionProvider.notifier).publishAnnouncement(widget.item.id),
      'Published — customers have been notified.',
    );
  }

  Future<void> _delete() async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete this notice?',
      message: 'It will disappear from the board. Notifications already sent stay '
          'in customers\' inboxes.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    await _run(
      () => ref.read(adminActionProvider.notifier).deleteAnnouncement(widget.item.id),
      'The notice was deleted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ManagedAnnouncement item = widget.item;

    final (String label, Color color, IconData icon) = switch (item.status) {
      AnnouncementStatus.draft => ('Draft', theme.colorScheme.outline, Icons.edit_note_rounded),
      AnnouncementStatus.published =>
        ('Published', theme.colorScheme.primary, Icons.campaign_rounded),
      AnnouncementStatus.archived =>
        ('Archived', theme.colorScheme.onSurfaceVariant, Icons.inventory_2_outlined),
    };

    return AppCard(
      key: Key('admin-announcement-${item.id}'),
      padding: const EdgeInsets.all(14),
      onTap: () => context.go(RoutePaths.adminAnnouncementEditOf(item.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(item.title, style: theme.textTheme.titleSmall)),
              StatusBadge(label: label, color: color, icon: icon, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${item.scopeLabel} · '
            '${item.publishedAt == null ? 'not published' : Formatters.relativeFromIso(item.publishedAt)}'
            '${item.authorName == null ? '' : ' · ${item.authorName}'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (_busy)
            const Padding(padding: EdgeInsets.all(6), child: LinearProgressIndicator())
          else
            Row(
              children: <Widget>[
                if (item.status != AnnouncementStatus.published)
                  TextButton.icon(
                    key: Key('admin-announcement-publish-${item.id}'),
                    onPressed: _publish,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Publish'),
                  ),
                if (item.status == AnnouncementStatus.published)
                  TextButton.icon(
                    key: Key('admin-announcement-archive-${item.id}'),
                    onPressed: () => _run(
                      () => ref
                          .read(adminActionProvider.notifier)
                          .archiveAnnouncement(item.id),
                      'The notice was archived.',
                    ),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('Archive'),
                  ),
                TextButton.icon(
                  key: Key('admin-announcement-edit-${item.id}'),
                  onPressed: () => context.go(RoutePaths.adminAnnouncementEditOf(item.id)),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                const Spacer(),
                IconButton(
                  key: Key('admin-announcement-delete-${item.id}'),
                  tooltip: 'Delete',
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
