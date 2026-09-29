import 'package:flutter/material.dart';

import '../core/utils/responsive.dart';
import 'app_card.dart';
import 'empty_state.dart';

/// One column of an [AppDataTable].
class AppDataColumn<T> {
  const AppDataColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.primary = false,
    this.showOnCard = true,
  });

  final String label;

  /// Builds the cell. A widget rather than a string so a column can hold a
  /// status badge or a pair of icon buttons.
  final Widget Function(T row) cell;

  final bool numeric;

  /// The identifying column — the name — shown as the card title on a phone
  /// instead of as a labelled field.
  final bool primary;

  /// Set false for a column that only makes sense in the wide layout, such
  /// as a row-action cluster that the card renders in its own footer.
  final bool showOnCard;
}

/// A table on a desktop or tablet, a list of cards on a phone.
///
/// Material's `DataTable` is the right thing on a wide screen and quite
/// wrong on a narrow one, where it either overflows or shrinks the text to
/// nothing. Rather than force one layout on both, this widget takes the
/// column definitions once and renders whichever suits the width — so every
/// admin screen gets the same behaviour without repeating the decision.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.rows,
    required this.columns,
    this.onRowTap,
    this.rowKey,
    this.cardFooter,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage = 'There is nothing to show with the current filters.',
    this.emptyIcon = Icons.inbox_outlined,
    this.shrinkWrap = false,
  });

  final List<T> rows;
  final List<AppDataColumn<T>> columns;
  final void Function(T row)? onRowTap;

  /// A stable widget key per row, so a test can find one by name and
  /// Flutter can keep element state across a refresh.
  final Key Function(T row)? rowKey;

  /// Extra widgets under a card in the narrow layout — usually the row
  /// actions that the wide layout puts in their own column.
  final Widget Function(T row)? cardFooter;

  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyState(title: emptyTitle, message: emptyMessage, icon: emptyIcon);
    }

    return Responsive.isCompact(context) ? _cards(context) : _table(context);
  }

  Widget _cards(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppDataColumn<T>? title = _primaryColumn;
    final List<AppDataColumn<T>> fields = columns
        .where((AppDataColumn<T> c) => c.showOnCard && !c.primary)
        .toList(growable: false);

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final T row = rows[index];
        return AppCard(
          key: rowKey?.call(row),
          padding: const EdgeInsets.all(14),
          onTap: onRowTap == null ? null : () => onRowTap!(row),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null)
                DefaultTextStyle.merge(
                  style: theme.textTheme.titleSmall ?? const TextStyle(),
                  child: title.cell(row),
                ),
              if (title != null && fields.isNotEmpty) const SizedBox(height: 10),
              for (final AppDataColumn<T> column in fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 110,
                        child: Text(
                          column.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: column.cell(row),
                        ),
                      ),
                    ],
                  ),
                ),
              if (cardFooter != null) ...<Widget>[
                const SizedBox(height: 8),
                cardFooter!(row),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The identifying column, if one was marked. Written as a loop rather
  /// than `firstOrNull` so the widget needs no extra package.
  AppDataColumn<T>? get _primaryColumn {
    for (final AppDataColumn<T> column in columns) {
      if (column.primary) return column;
    }
    return null;
  }

  Widget _table(BuildContext context) {
    // Only the identifying cell carries the row key, so `find.byKey` still
    // matches exactly one widget in either layout.
    final AppDataColumn<T>? keyed = _primaryColumn ?? (columns.isEmpty ? null : columns.first);

    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 120),
          child: DataTable(
            columnSpacing: 24,
            horizontalMargin: 16,
            showCheckboxColumn: false,
            columns: <DataColumn>[
              for (final AppDataColumn<T> column in columns)
                DataColumn(label: Text(column.label), numeric: column.numeric),
            ],
            rows: <DataRow>[
              for (final T row in rows)
                DataRow(
                  onSelectChanged: onRowTap == null ? null : (bool? _) => onRowTap!(row),
                  cells: <DataCell>[
                    for (final AppDataColumn<T> column in columns)
                      DataCell(
                        identical(column, keyed) && rowKey != null
                            ? KeyedSubtree(key: rowKey!(row), child: column.cell(row))
                            : column.cell(row),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
