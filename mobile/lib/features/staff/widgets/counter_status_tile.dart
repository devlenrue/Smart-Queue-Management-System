import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../models/staff_dashboard.dart';
import '../../../providers/staff_providers.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/status_badge.dart';

/// The clerk's own counter, with the on/off-duty switch.
///
/// The switch is disabled while a customer is at the counter. The server
/// refuses that too (409 COUNTER_BUSY); greying it out just explains why
/// before the tap rather than after it.
class CounterStatusTile extends ConsumerStatefulWidget {
  const CounterStatusTile({super.key, required this.counter, required this.serviceName});

  final StaffCounter counter;
  final String serviceName;

  @override
  ConsumerState<CounterStatusTile> createState() => _CounterStatusTileState();
}

class _CounterStatusTileState extends ConsumerState<CounterStatusTile> {
  bool _busy = false;

  Future<void> _toggle(bool goOnDuty) async {
    setState(() => _busy = true);
    try {
      await ref.read(staffActionProvider.notifier).setCounterStatus(
            widget.counter.id,
            goOnDuty ? CounterStatus.available : CounterStatus.offline,
          );
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        goOnDuty ? 'You are on duty at ${widget.counter.name}.' : '${widget.counter.name} is now offline.',
      );
    } catch (error) {
      if (!mounted) return;
      showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StaffCounter counter = widget.counter;
    final bool onDuty = counter.status != CounterStatus.offline;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        counter.name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge.counter(context, counter.status, dense: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.serviceName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Tooltip(
              message: counter.canGoOffline
                  ? (onDuty ? 'Go off duty' : 'Go on duty')
                  : 'Finish the customer at your counter first',
              child: Switch(
                key: const Key('counter-duty-switch'),
                value: onDuty,
                onChanged: counter.canGoOffline ? _toggle : null,
              ),
            ),
        ],
      ),
    );
  }
}
