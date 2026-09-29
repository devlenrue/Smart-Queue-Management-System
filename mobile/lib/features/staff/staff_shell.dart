import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/responsive.dart';
import '../../providers/staff_providers.dart';

/// The frame around the staff console.
///
/// A rail rather than a bottom bar wherever there is room: counter staff are
/// often on a tablet or a desktop browser, and the dashboard wants the
/// vertical space for the waiting list.
class StaffShell extends ConsumerWidget {
  const StaffShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const List<_StaffTab> _tabs = <_StaffTab>[
    _StaffTab(label: 'Console', icon: Icons.dashboard_outlined, selected: Icons.dashboard_rounded),
    _StaffTab(label: 'Queue', icon: Icons.groups_outlined, selected: Icons.groups_rounded),
    _StaffTab(label: 'History', icon: Icons.history_rounded, selected: Icons.history_rounded),
    _StaffTab(label: 'Stats', icon: Icons.insights_outlined, selected: Icons.insights_rounded),
    _StaffTab(label: 'Profile', icon: Icons.person_outline_rounded, selected: Icons.person_rounded),
  ];

  void _onTap(int index) {
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The badge is the number still waiting — the one figure a clerk glances
    // at between customers.
    final int waiting = ref.watch(staffDashboardProvider).valueOrNull?.queue?.waitingCount ?? 0;

    if (!Responsive.isCompact(context)) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _onTap,
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (int i = 0; i < _tabs.length; i++)
                  NavigationRailDestination(
                    icon: _badged(i, _tabs[i].icon, waiting),
                    selectedIcon: _badged(i, _tabs[i].selected, waiting),
                    label: Text(_tabs[i].label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: <NavigationDestination>[
          for (int i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: _badged(i, _tabs[i].icon, waiting),
              selectedIcon: _badged(i, _tabs[i].selected, waiting),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }

  Widget _badged(int index, IconData icon, int waiting) {
    if (index != 1 || waiting <= 0) return Icon(icon);
    return Badge(
      label: Text(waiting > 99 ? '99+' : '$waiting'),
      child: Icon(icon),
    );
  }
}

class _StaffTab {
  const _StaffTab({required this.label, required this.icon, required this.selected});

  final String label;
  final IconData icon;
  final IconData selected;
}
