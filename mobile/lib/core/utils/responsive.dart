import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';

enum ScreenSize { compact, medium, expanded }

/// §66 — one place that decides what "small screen" means, so the shell,
/// the service grid and the page padding can never disagree about it.
class Responsive {
  const Responsive._();

  static ScreenSize of(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width < AppConstants.mobileBreakpoint) return ScreenSize.compact;
    if (width < AppConstants.tabletBreakpoint) return ScreenSize.medium;
    return ScreenSize.expanded;
  }

  /// Phone-sized: bottom navigation rather than a side rail.
  static bool isCompact(BuildContext context) => of(context) == ScreenSize.compact;

  /// Cards per row in the service catalogue.
  static int columns(BuildContext context) {
    switch (of(context)) {
      case ScreenSize.compact:
        return 1;
      case ScreenSize.medium:
        return 2;
      case ScreenSize.expanded:
        return 3;
    }
  }

  static EdgeInsets pagePadding(BuildContext context) {
    switch (of(context)) {
      case ScreenSize.compact:
        return const EdgeInsets.fromLTRB(16, 12, 16, 24);
      case ScreenSize.medium:
        return const EdgeInsets.fromLTRB(24, 16, 24, 32);
      case ScreenSize.expanded:
        return const EdgeInsets.fromLTRB(32, 20, 32, 40);
    }
  }
}
