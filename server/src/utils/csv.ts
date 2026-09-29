/**
 * Minimal RFC 4180 CSV writer (§41 — "export to CSV").
 *
 * Hand-written rather than a dependency: the whole format is one escaping
 * rule, and a report row is already a flat object by the time it gets here.
 *
 * * fields are separated by commas and records by CRLF, as the RFC says;
 * * a field is quoted only when it has to be — it contains a comma, a quote,
 *   a line break, or leading/trailing space;
 * * a quote inside a quoted field is doubled;
 * * `null` and `undefined` become an empty field, never the text "null".
 *
 * No byte-order mark: the response says `charset=utf-8` and every tool that
 * matters reads that. A BOM would corrupt the first header for the ones that
 * do not.
 */

export interface CsvColumn<T> {
  header: string;
  value: (row: T) => string | number | boolean | null | undefined;
}

const NEEDS_QUOTES = /[",\r\n]|^\s|\s$/;

export function csvCell(value: string | number | boolean | null | undefined): string {
  if (value === null || value === undefined) return '';
  const text = String(value);
  if (!NEEDS_QUOTES.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}

export function toCsv<T>(columns: ReadonlyArray<CsvColumn<T>>, rows: readonly T[]): string {
  const lines: string[] = [columns.map((column) => csvCell(column.header)).join(',')];
  for (const row of rows) {
    lines.push(columns.map((column) => csvCell(column.value(row))).join(','));
  }
  return `${lines.join('\r\n')}\r\n`;
}

/** `smartqueue-daily-2026-09-01_2026-09-29.csv` — sortable, and it says what it is. */
export function csvFilename(kind: string, from: string, to: string): string {
  return from === to ? `smartqueue-${kind}-${from}.csv` : `smartqueue-${kind}-${from}_${to}.csv`;
}
