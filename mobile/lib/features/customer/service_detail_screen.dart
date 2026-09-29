import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../models/service.dart';
import '../../models/ticket.dart';
import '../../providers/customer_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/status_badge.dart';
import 'widgets/join_queue_sheet.dart';

/// §42 detail view: what this service is, when it opens, how busy it is,
/// and the one button that matters.
class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final int serviceId;

  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  bool _joining = false;

  Future<void> _join(Service service) async {
    setState(() => _joining = true);
    final Ticket? ticket = await JoinQueueSheet.show(context, service);
    if (!mounted) return;
    setState(() => _joining = false);

    if (ticket != null) {
      ref.invalidate(serviceDetailProvider(widget.serviceId));
      showSuccessSnackBar(context, 'Ticket ${ticket.ticketNumber} is yours.');
      context.pushReplacement(RoutePaths.ticketDetailOf(ticket.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Service> service = ref.watch(serviceDetailProvider(widget.serviceId));

    return Scaffold(
      appBar: AppBar(title: Text(service.valueOrNull?.name ?? 'Service')),
      body: service.when(
        loading: () => const LoadingView(message: 'Loading service…'),
        error: (Object error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(serviceDetailProvider(widget.serviceId)),
        ),
        data: (Service data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(serviceDetailProvider(widget.serviceId)),
          child: ListView(
            padding: Responsive.pagePadding(context),
            children: <Widget>[
              _Header(service: data),
              const SizedBox(height: 20),
              _LiveQueue(service: data),
              const SizedBox(height: 20),
              if (data.description != null && data.description!.isNotEmpty) ...<Widget>[
                _Section(
                  title: 'About this service',
                  child: Text(data.description!, style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(height: 20),
              ],
              _HoursSection(serviceId: widget.serviceId, today: data.hoursToday),
              const SizedBox(height: 28),
              AppButton(
                key: const Key('detail-join'),
                label: data.canJoin ? 'Join this queue' : data.unavailableReason,
                icon: data.canJoin ? Icons.add_rounded : Icons.block_rounded,
                isLoading: _joining,
                onPressed: data.canJoin ? () => _join(data) : null,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 56,
          width: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            service.code,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(service.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              if (service.category != null)
                Text(
                  service.category!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              StatusBadge.service(context, service.status),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveQueue extends StatelessWidget {
  const _LiveQueue({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final QueueSummary? queue = service.queue;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Right now', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (queue != null) StatusBadge.queue(context, queue.status, dense: true),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                _Stat(label: 'Now serving', value: queue?.nowServing ?? '—'),
                _Stat(label: 'Waiting', value: '${queue?.waitingCount ?? 0}'),
                _Stat(
                  label: 'Est. wait',
                  value: Formatters.duration(queue?.estimatedWaitMinutes ?? 0),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                _Stat(label: 'Counters open', value: '${queue?.activeCounters ?? 0}'),
                _Stat(label: 'Served today', value: '${queue?.completedToday ?? 0}'),
                _Stat(label: 'Places left', value: '${queue?.capacityRemaining ?? 0}'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Estimated wait = people ahead × average service time ÷ counters open.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _HoursSection extends ConsumerWidget {
  const _HoursSection({required this.serviceId, this.today});

  final int serviceId;
  final TodayHours? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<ServiceHours>> hours = ref.watch(serviceHoursProvider(serviceId));

    return _Section(
      title: 'Opening hours',
      trailing: today == null
          ? null
          : Text(
              today!.isOpenNow ? 'Open now' : 'Closed now',
              style: theme.textTheme.labelMedium?.copyWith(
                color: today!.isOpenNow
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
      child: hours.when(
        loading: () => const Column(
          children: <Widget>[
            SkeletonBox(height: 14),
            SizedBox(height: 10),
            SkeletonBox(height: 14),
          ],
        ),
        error: (Object error, _) => ErrorState(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(serviceHoursProvider(serviceId)),
        ),
        data: (List<ServiceHours> list) {
          if (list.isEmpty) {
            return Text('No hours published.', style: theme.textTheme.bodySmall);
          }
          return Column(
            children: <Widget>[
              for (final ServiceHours row in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 110,
                        child: Text(row.dayName, style: theme.textTheme.bodyMedium),
                      ),
                      Text(
                        row.range,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: row.isOpen
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
