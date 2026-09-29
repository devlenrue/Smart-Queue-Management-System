import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/route_paths.dart';
import '../../widgets/empty_state.dart';

/// Shown when a route does not exist — a mistyped deep link, or an `:id`
/// that is not a number.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: EmptyState(
        icon: Icons.explore_off_rounded,
        title: 'That page does not exist',
        message: 'We could not find anything at $location.',
        actionLabel: 'Go home',
        onAction: () => context.go(RoutePaths.home),
      ),
    );
  }
}
