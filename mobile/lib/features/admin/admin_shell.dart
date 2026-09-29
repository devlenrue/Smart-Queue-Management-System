import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../providers/auth_providers.dart';

/// One entry in the admin navigation.
class AdminDestination {
  const AdminDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    this.superAdminOnly = false,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  /// System settings is the one page an ordinary admin cannot open; the
  /// server answers 403, so the console does not offer it either.
  final bool superAdminOnly;
}

/// The frame around the administrator console.
///
/// A drawer rather than a bottom bar: ten destinations do not fit in a tab
/// strip, and administrators work on a laptop far more often than on a
/// phone. On a wide window the drawer is permanent and nothing has to be
/// opened at all.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const List<AdminDestination> destinations = <AdminDestination>[
    AdminDestination(
      label: 'Dashboard',
      path: RoutePaths.adminHome,
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
    ),
    AdminDestination(
      label: 'Services',
      path: RoutePaths.adminServices,
      icon: Icons.apartment_outlined,
      selectedIcon: Icons.apartment_rounded,
    ),
    AdminDestination(
      label: 'Counters',
      path: RoutePaths.adminCounters,
      icon: Icons.desk_outlined,
      selectedIcon: Icons.desk_rounded,
    ),
    AdminDestination(
      label: 'Staff',
      path: RoutePaths.adminStaff,
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge_rounded,
    ),
    AdminDestination(
      label: 'Users',
      path: RoutePaths.adminUsers,
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
    ),
    AdminDestination(
      label: 'Queue monitor',
      path: RoutePaths.adminQueues,
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart_rounded,
    ),
    AdminDestination(
      label: 'Announcements',
      path: RoutePaths.adminAnnouncements,
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign_rounded,
    ),
    AdminDestination(
      label: 'System settings',
      path: RoutePaths.adminSettings,
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      superAdminOnly: true,
    ),
  ];

  /// Which destinations this role may see.
  static List<AdminDestination> visibleTo(UserRole role) {
    return destinations
        .where((AdminDestination d) => !d.superAdminOnly || role == UserRole.superAdmin)
        .toList(growable: false);
  }

  /// The selected entry is the longest destination path the location starts
  /// with, so `/admin/users/9` still highlights "Users".
  static int indexOf(String location, List<AdminDestination> items) {
    int best = 0;
    int bestLength = -1;
    for (int i = 0; i < items.length; i++) {
      final String path = items[i].path;
      if (location.startsWith(path) && path.length > bestLength) {
        best = i;
        bestLength = path.length;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole role = ref.watch(currentUserProvider)?.role ?? UserRole.admin;
    final List<AdminDestination> items = visibleTo(role);
    final int index = indexOf(location, items);

    void go(int next) {
      if (next < 0 || next >= items.length) return;
      context.go(items[next].path);
    }

    // Expanded: the rail is permanent, so every page keeps its own AppBar
    // and there is no hamburger anywhere.
    if (Responsive.of(context) == ScreenSize.expanded) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            _AdminRail(items: items, index: index, onSelect: go),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      drawer: _AdminDrawer(
        items: items,
        index: index,
        onSelect: (int next) {
          Navigator.of(context).pop();
          go(next);
        },
      ),
      body: child,
    );
  }
}

class _AdminRail extends StatelessWidget {
  const _AdminRail({required this.items, required this.index, required this.onSelect});

  final List<AdminDestination> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 232,
      child: NavigationRail(
        extended: true,
        minExtendedWidth: 232,
        selectedIndex: index,
        onDestinationSelected: onSelect,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.admin_panel_settings_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Administration', style: theme.textTheme.titleSmall),
              ),
            ],
          ),
        ),
        destinations: <NavigationRailDestination>[
          for (final AdminDestination item in items)
            NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: Text(item.label),
            ),
        ],
      ),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({required this.items, required this.index, required this.onSelect});

  final List<AdminDestination> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return NavigationDrawer(
      selectedIndex: index,
      onDestinationSelected: onSelect,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.admin_panel_settings_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text('Administration', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        for (final AdminDestination item in items)
          NavigationDrawerDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: Text(item.label),
          ),
      ],
    );
  }
}

/// The page frame every admin screen uses.
///
/// It exists so the hamburger appears on exactly the screens that need one
/// — the shell is a drawer below the expanded breakpoint and a permanent
/// rail above it — without each screen re-deciding that.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.floatingActionButton,
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final bool expanded = Responsive.of(context) == ScreenSize.expanded;

    return Scaffold(
      appBar: AppBar(
        // The rail is always on screen above the breakpoint, so there is
        // nothing to open and Flutter should not draw a menu button.
        automaticallyImplyLeading: !expanded,
        title: subtitle == null
            ? Text(title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
        actions: <Widget>[
          ...actions,
          if (onRefresh != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      floatingActionButton: floatingActionButton,
      body: onRefresh == null
          ? body
          : RefreshIndicator(onRefresh: onRefresh!, child: body),
    );
  }
}
