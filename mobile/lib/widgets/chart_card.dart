import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_card.dart';

/// One column of [BarChartCard].
class BarDatum {
  const BarDatum({required this.label, required this.value, this.tooltip});

  final String label;
  final int value;
  final String? tooltip;
}

/// A plain bar chart, drawn with layout widgets.
///
/// The same decision as the staff statistics screen: a week of bars is not
/// worth a charting dependency, and `Expanded` + `Container` gives a chart
/// that inherits the theme, scales with the card and costs nothing to test.
class BarChartCard extends StatelessWidget {
  const BarChartCard({
    super.key,
    required this.title,
    required this.data,
    this.subtitle,
    this.height = 160,
    this.emptyMessage = 'Nothing to chart yet.',
  });

  final String title;
  final List<BarDatum> data;
  final String? subtitle;
  final double height;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int peak = data.fold<int>(0, (int max, BarDatum d) => d.value > max ? d.value : max);
    final int total = data.fold<int>(0, (int sum, BarDatum d) => sum + d.value);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (data.isEmpty || total == 0)
            SizedBox(
              height: height,
              child: Center(
                child: Text(
                  emptyMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final BarDatum datum in data)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            Text('${datum.value}', style: theme.textTheme.labelSmall),
                            const SizedBox(height: 4),
                            Tooltip(
                              message: datum.tooltip ?? '${datum.label}: ${datum.value}',
                              child: Container(
                                // A zero day still gets 4px, so the axis
                                // reads evenly instead of losing a column.
                                height: peak == 0
                                    ? 4
                                    : 4 + ((height - 50) * datum.value / peak),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: datum.value == peak ? 0.95 : 0.55,
                                  ),
                                  borderRadius:
                                      const BorderRadius.vertical(top: Radius.circular(6)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              datum.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One wedge of [DonutChartCard].
class DonutSlice {
  const DonutSlice({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;
}

/// A ring chart with a legend, painted by [_DonutPainter].
///
/// Every slice is named in the legend with its own count, so the picture is
/// decoration and the legend is the data — the chart still works for anyone
/// who cannot tell the colours apart.
class DonutChartCard extends StatelessWidget {
  const DonutChartCard({
    super.key,
    required this.title,
    required this.slices,
    this.centerLabel,
    this.size = 140,
  });

  final String title;
  final List<DonutSlice> slices;
  final String? centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<DonutSlice> shown =
        slices.where((DonutSlice s) => s.value > 0).toList(growable: false);
    final int total = shown.fold<int>(0, (int sum, DonutSlice s) => sum + s.value);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
          if (total == 0)
            SizedBox(
              height: size,
              child: Center(
                child: Text(
                  'No tickets today yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      slices: shown,
                      track: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('$total', style: theme.textTheme.headlineSmall),
                          Text(
                            centerLabel ?? 'tickets',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final DonutSlice slice in shown)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: slice.color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  slice.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text('${slice.value}', style: theme.textTheme.labelMedium),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.track});

  final List<DonutSlice> slices;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.shortestSide * 0.16;
    final Rect rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );

    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);

    final int total = slices.fold<int>(0, (int sum, DonutSlice s) => sum + s.value);
    if (total == 0) return;

    // Start at twelve o'clock and go clockwise, which is how anyone reads a
    // pie chart without being told.
    double start = -math.pi / 2;
    for (final DonutSlice slice in slices) {
      final double sweep = 2 * math.pi * slice.value / total;
      canvas.drawArc(
        rect,
        start,
        // A hair of padding between wedges, but never more than the wedge.
        math.max(sweep - 0.02, sweep * 0.6),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = slice.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.track != track;
}
