import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../providers/auth_providers.dart';
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

      // Signed in but sitting on the splash or a login form — move along.
      if (isPublic) return RoutePaths.home;

      return null;
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

/// A malformed `:id` should land on the not-found screen, not crash.
int _idOf(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '') ?? -1;
