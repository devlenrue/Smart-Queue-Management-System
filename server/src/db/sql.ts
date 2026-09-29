/**
 * The complete list of places where MySQL and SQLite differ at *runtime*.
 *
 * Everything else in the repository layer is plain, portable SQL with `?`
 * placeholders. Keeping the differences in one 40-line file is what makes the
 * dual-driver arrangement honest rather than a maintenance trap.
 */
import type { DbDialect } from '../config/env';

/**
 * Pessimistic row lock. MySQL takes a real `FOR UPDATE` lock; the SQLite driver
 * gets the same guarantee from `BEGIN IMMEDIATE` plus a transaction mutex, so
 * it needs no clause. See docs/queue-engine.md §3.
 */
export function forUpdate(dialect: DbDialect): string {
  return dialect === 'mysql' ? ' FOR UPDATE' : '';
}

/** Whole seconds between two DATETIME columns, as a SQL expression. */
export function diffSeconds(dialect: DbDialect, fromExpr: string, toExpr: string): string {
  return dialect === 'mysql'
    ? `TIMESTAMPDIFF(SECOND, ${fromExpr}, ${toExpr})`
    : `(julianday(${toExpr}) - julianday(${fromExpr})) * 86400.0`;
}

/** Whole minutes between two DATETIME columns, as a SQL expression. */
export function diffMinutes(dialect: DbDialect, fromExpr: string, toExpr: string): string {
  return dialect === 'mysql'
    ? `TIMESTAMPDIFF(SECOND, ${fromExpr}, ${toExpr}) / 60.0`
    : `(julianday(${toExpr}) - julianday(${fromExpr})) * 1440.0`;
}

/** The hour-of-day of a DATETIME column, as a SQL expression (0-23). */
export function hourOf(dialect: DbDialect, expr: string): string {
  return dialect === 'mysql' ? `HOUR(${expr})` : `CAST(strftime('%H', ${expr}) AS INTEGER)`;
}

/** The date part of a DATETIME column, as a SQL expression ('YYYY-MM-DD'). */
export function dateOf(dialect: DbDialect, expr: string): string {
  return dialect === 'mysql' ? `DATE(${expr})` : `date(${expr})`;
}

/** Builds `IN (?, ?, ?)` and returns the matching parameter list. */
export function inClause(values: readonly unknown[]): { sql: string; params: unknown[] } {
  if (values.length === 0) return { sql: '(NULL)', params: [] };
  return { sql: `(${values.map(() => '?').join(', ')})`, params: [...values] };
}

/** Escapes LIKE wildcards in user input before it is wrapped in %…%. */
export function likeTerm(term: string): string {
  return `%${term.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
}

/**
 * Validates a client-supplied sort column against an allow-list. Column names
 * can never be parameterised, so this is the only safe way to accept them.
 */
export function safeSortColumn(requested: string | undefined, allowed: Record<string, string>, fallback: string): string {
  if (!requested) return fallback;
  return allowed[requested] ?? fallback;
}

export function safeSortDirection(requested: string | undefined): 'ASC' | 'DESC' {
  return String(requested).toLowerCase() === 'asc' ? 'ASC' : 'DESC';
}
