import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/admin/admin_shell.dart';
import '../../features/admin/announcement_form_screen.dart';
import '../../features/admin/manage_announcements_screen.dart';
import '../../features/admin/manage_counters_screen.dart';
import '../../features/admin/manage_services_screen.dart';
import '../../features/admin/manage_staff_screen.dart';
import '../../features/admin/manage_users_screen.dart';
import '../../features/admin/queue_board_screen.dart';
import '../../features/admin/queue_monitor_screen.dart';
import '../../features/admin/service_form_screen.dart';
import '../../features/admin/system_settings_screen.dart';
import '../../features/admin/user_detail_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/customer/announcements_screen.dart';
import '../../features/customer/customer_shell.dart';
import '../../features/customer/dashboard_screen.dart';
import '../../features/customer/my_tickets_screen.dart';
import '../../features/customer/notifications_screen.dart';
import '../../features/customer/profile_screen.dart';
import '../../features/customer/queue_tracking_screen.dart';
import '../../features/customer/service_detail_screen.dart';
import '../../features/customer/service_list_screen.dart';
import '../../features/customer/settings_screen.dart';
import '../../features/customer/ticket_screen.dart';
import '../../features/misc/about_screen.dart';
import '../../features/misc/not_found_screen.dart';
import '../../features/staff/current_queue_screen.dart';
import '../../features/staff/staff_dashboard_screen.dart';
import '../../features/staff/staff_history_screen.dart';
import '../../features/staff/staff_profile_screen.dart';
import '../../features/staff/staff_shell.dart';
import '../../features/staff/staff_statistics_screen.dart';
import '../../providers/auth_providers.dart';
import '../constants/enums.dart';
import 'route_paths.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The router, with the auth guard built in.
///
/// Guarding here rather than in each screen means there is exactly one rule
/// about who may see what, and no screen can forget to apply it.
final Provider<GoRouter> goRouterProvider = Provider<GoRouter>((Ref ref) {
  // GoRouter wants a Listenable; Riverpod speaks in providers. This bridges
  // the two without rebuilding the router (which would reset the stack).
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref.listen<AsyncValue<AuthState>>(
    authControllerProvider,
    (AsyncValue<AuthState>? _, AsyncValue<AuthState> __) => refresh.value++,
  );
  ref.onDispose(refresh.dispose);

  final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    errorBuilder: (BuildContext context, GoRouterState state) =>
        NotFoundScreen(location: state.uri.toString()),
    redirect: (BuildContext context, GoRouterState state) {
      final AsyncValue<AuthState> auth = ref.read(authControllerProvider);
      final String location = state.matchedLocation;

      // Still restoring the session — hold everyone on the splash screen.
      if (auth.isLoading || auth.valueOrNull == null) {
        return location == RoutePaths.splash ? null : RoutePaths.splash;
      }

      final bool signedIn = auth.valueOrNull?.isAuthenticated ?? false;
      final bool isPublic = RoutePaths.publicRoutes.contains(location);

      if (!signedIn) return isPublic ? null : RoutePaths.login;

      // Each role has one home, and the app only ever sends people there.
      final UserRole role = auth.valueOrNull?.role ?? UserRole.customer;
      final String home = homeFor(role);

      // Signed in but sitting on the splash or a login form — move along.
      if (isPublic) return home;

      // Settings and About belong to everyone.
      if (RoutePaths.sharedRoutes.contains(location)) return null;

      // Two prefixes keep the three consoles apart. A customer cannot open
      // either of the back offices; a clerk cannot open administration; and
      // neither of them is dropped into a part of the app where they have
      // nothing to do.
      final bool wantsStaff = RoutePaths.isStaffRoute(location);
      final bool wantsAdmin = RoutePaths.isAdminRoute(location);

      switch (role) {
        case UserRole.customer:
          return wantsStaff || wantsAdmin ? RoutePaths.home : null;
        case UserRole.staff:
          return wantsStaff ? null : RoutePaths.staffHome;
        case UserRole.admin:
        case UserRole.superAdmin:
          // An administrator may also work a counter — the server exempts
          // them from the assignment check — so the staff console stays
          // open to them.
          return wantsStaff || wantsAdmin ? null : home;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.splash,
        builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (BuildContext context, GoRouterState state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.register,
        builder: (BuildContext context, GoRouterState state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        builder: (BuildContext context, GoRouterState state) => const ForgotPasswordScreen(),
      ),

      // The five bottom-nav tabs, each with its own navigation stack so
      // switching tabs does not lose where you were.
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell shell) {
          return CustomerShell(shell: shell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.home,
                builder: (BuildContext context, GoRouterState state) =>
                    const CustomerDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.services,
                builder: (BuildContext context, GoRouterState state) => const ServiceListScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      return ServiceDetailScreen(serviceId: _idOf(state));
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.tickets,
                builder: (BuildContext context, GoRouterState state) => const MyTicketsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      return TicketScreen(ticketId: _idOf(state));
                    },
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'queue',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (BuildContext context, GoRouterState state) {
                          return QueueTrackingScreen(ticketId: _idOf(state));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.notifications,
                builder: (BuildContext context, GoRouterState state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.profile,
                builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // The staff console. Five tabs, same indexed-stack arrangement as the
      // customer shell so each tab keeps its own history.
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell shell) {
          return StaffShell(shell: shell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.staffHome,
                builder: (BuildContext context, GoRouterState state) =>
                    const StaffDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.staffQueue,
                builder: (BuildContext context, GoRouterState state) => const CurrentQueueScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'ticket/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) {
                      return StaffTicketScreen(ticketId: _idOf(state));
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.staffHistory,
                builder: (BuildContext context, GoRouterState state) => const StaffHistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.staffStats,
                builder: (BuildContext context, GoRouterState state) =>
                    const StaffStatisticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.staffProfile,
                builder: (BuildContext context, GoRouterState state) => const StaffProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // The administrator console. A plain ShellRoute rather than an
      // indexed stack: these screens are tables that re-read when opened,
      // so there is no per-tab history worth preserving, and one navigator
      // keeps the drawer and the deep links simple.
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return AdminShell(location: state.matchedLocation, child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.adminHome,
            builder: (BuildContext context, GoRouterState state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: RoutePaths.adminServices,
            builder: (BuildContext context, GoRouterState state) => const ManageServicesScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'new',
                builder: (BuildContext context, GoRouterState state) => const ServiceFormScreen(),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (BuildContext context, GoRouterState state) =>
                    ServiceFormScreen(serviceId: _idOf(state)),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminCounters,
            builder: (BuildContext context, GoRouterState state) => const ManageCountersScreen(),
          ),
          GoRoute(
            path: RoutePaths.adminStaff,
            builder: (BuildContext context, GoRouterState state) => const ManageStaffScreen(),
          ),
          GoRoute(
            path: RoutePaths.adminUsers,
            builder: (BuildContext context, GoRouterState state) => const ManageUsersScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id',
                builder: (BuildContext context, GoRouterState state) =>
                    UserDetailScreen(userId: _idOf(state)),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminQueues,
            builder: (BuildContext context, GoRouterState state) => const QueueMonitorScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':serviceId',
                builder: (BuildContext context, GoRouterState state) => QueueBoardScreen(
                  serviceId: int.tryParse(state.pathParameters['serviceId'] ?? '') ?? -1,
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminAnnouncements,
            builder: (BuildContext context, GoRouterState state) =>
                const ManageAnnouncementsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'new',
                builder: (BuildContext context, GoRouterState state) =>
                    const AnnouncementFormScreen(),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (BuildContext context, GoRouterState state) =>
                    AnnouncementFormScreen(announcementId: _idOf(state)),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.adminSettings,
            builder: (BuildContext context, GoRouterState state) => const SystemSettingsScreen(),
          ),
        ],
      ),

      GoRoute(
        path: RoutePaths.announcements,
        builder: (BuildContext context, GoRouterState state) => const AnnouncementsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':id',
            builder: (BuildContext context, GoRouterState state) =>
                AnnouncementDetailScreen(announcementId: _idOf(state)),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.settings,
        builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.about,
        builder: (BuildContext context, GoRouterState state) => const AboutScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

/// Where each role lands after signing in.
///
/// Administrators have had their own console since Phase 7; they can still
/// reach the staff console from it, because the server exempts them from
/// the assignment check and lets them supervise any desk.
String homeFor(UserRole role) {
  switch (role) {
    case UserRole.customer:
      return RoutePaths.home;
    case UserRole.staff:
      return RoutePaths.staffHome;
    case UserRole.admin:
    case UserRole.superAdmin:
      return RoutePaths.adminHome;
  }
}

/// A malformed `:id` should land on the not-found screen, not crash.
int _idOf(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '') ?? -1;
