import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/responsive.dart';
import '../../providers/customer_providers.dart';

/// The five-tab frame around every customer screen.
///
/// `StatefulShellRoute.indexedStack` keeps one navigation stack per tab, so
/// coming back to Services lands where you left it. On a wide window the
/// bottom bar becomes a side rail (§66).
class CustomerShell extends ConsumerWidget {
  const CustomerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const List<_Tab> _tabs = <_Tab>[
    _Tab(label: 'Home', icon: Icons.home_outlined, selected: Icons.home_rounded),
    _Tab(label: 'Services', icon: Icons.grid_view_outlined, selected: Icons.grid_view_rounded),
    _Tab(
      label: 'My tickets',
      icon: Icons.confirmation_number_outlined,
      selected: Icons.confirmation_number_rounded,
    ),
    _Tab(label: 'Alerts', icon: Icons.notifications_outlined, selected: Icons.notifications_rounded),
    _Tab(label: 'Profile', icon: Icons.person_outline_rounded, selected: Icons.person_rounded),
  ];

  void _onTap(int index) {
    // Tapping the tab you are already on pops back to its root.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final int activeTickets = ref.watch(activeTicketsProvider).valueOrNull?.length ?? 0;
    final bool useRail = !Responsive.isCompact(context);

    if (useRail) {
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
                    icon: _badged(i, _tabs[i].icon, unread, activeTickets),
                    selectedIcon: _badged(i, _tabs[i].selected, unread, activeTickets),
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
              icon: _badged(i, _tabs[i].icon, unread, activeTickets),
              selectedIcon: _badged(i, _tabs[i].selected, unread, activeTickets),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }

  /// Tab 2 shows how many live tickets you hold, tab 3 how many unread
  /// alerts — the two numbers a waiting customer cares about.
  Widget _badged(int index, IconData icon, int unread, int activeTickets) {
    final int count = switch (index) {
      2 => activeTickets,
      3 => unread,
      _ => 0,
    };
    if (count <= 0) return Icon(icon);
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }
}

class _Tab {
  const _Tab({required this.label, required this.icon, required this.selected});

  final String label;
  final IconData icon;
  final IconData selected;
}
