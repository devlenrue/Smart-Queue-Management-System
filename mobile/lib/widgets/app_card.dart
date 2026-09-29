import 'package:flutter/material.dart';

/// The surface every panel in the app sits on.
///
/// This is a widget rather than a `cardTheme` entry on [ThemeData] on
/// purpose: the type of that slot was renamed between Flutter releases
/// (`CardTheme` → `CardThemeData`), so pinning the look here keeps the app
/// building on either one. It is a drop-in replacement for [Card].
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Optional — many cards put their own [InkWell] inside instead.
  final VoidCallback? onTap;

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius shape = BorderRadius.circular(radius);

    final Widget decorated = Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    return Material(
      color: scheme.surface,
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? decorated
          : InkWell(onTap: onTap, borderRadius: shape, child: decorated),
    );
  }
}
