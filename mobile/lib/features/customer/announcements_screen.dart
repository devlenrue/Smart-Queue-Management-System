import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/announcement.dart';
import '../../providers/customer_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';

/// §41. Published, unexpired announcements — the server decides which ones
/// those are, so nothing draft or stale can reach this list.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Announcement>> announcements = ref.watch(announcementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(announcementsProvider),
        child: announcements.when(
          loading: () => const SkeletonList(itemHeight: 100),
          error: (Object error, _) => ListView(
            children: <Widget>[
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
              ErrorState(error: error, onRetry: () => ref.invalidate(announcementsProvider)),
            ],
          ),
          data: (List<Announcement> items) {
            if (items.isEmpty) {
              return ListView(
                children: <Widget>[
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  const EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'Nothing announced',
                    message: 'Notices from the service desks will appear here.',
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: Responsive.pagePadding(context),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final Announcement item = items[index];
                return AppCard(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push(RoutePaths.announcementDetailOf(item.id)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.campaign_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item.scopeLabel,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                Formatters.relativeFromIso(item.publishedAt),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            item.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AnnouncementDetailScreen extends ConsumerWidget {
  const AnnouncementDetailScreen({super.key, required this.announcementId});

  final int announcementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<Announcement> announcement =
        ref.watch(announcementDetailProvider(announcementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: announcement.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(announcementDetailProvider(announcementId)),
        ),
        data: (Announcement item) => ListView(
          padding: Responsive.pagePadding(context),
          children: <Widget>[
            Text(item.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                Text(
                  item.scopeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  Formatters.dateTimeFromIso(item.publishedAt),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (item.authorName != null)
                  Text(
                    'by ${item.authorName}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(item.content, style: theme.textTheme.bodyLarge),
            if (item.expiresAt != null) ...<Widget>[
              const SizedBox(height: 24),
              Text(
                'Valid until ${Formatters.dateTimeFromIso(item.expiresAt)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
