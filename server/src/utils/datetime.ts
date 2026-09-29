/**
 * Date/time helpers.
 *
 * Storage contract (identical on MySQL and SQLite so the repository layer never
 * branches on dialect):
 *   DATETIME → 'YYYY-MM-DD HH:mm:ss'  in the server's configured timezone
 *   DATE     → 'YYYY-MM-DD'
 *   TIME     → 'HH:mm:ss'
 *
 * The MySQL pool is created with `dateStrings: true` so it reads back exactly
 * what it wrote, which keeps the two drivers byte-compatible.
 */

const pad = (n: number, width = 2): string => String(n).padStart(width, '0');

/** 'YYYY-MM-DD HH:mm:ss' in server-local time. */
export function toSqlDateTime(date: Date = new Date()): string {
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  );
}

/** 'YYYY-MM-DD' in server-local time. */
export function toSqlDate(date: Date = new Date()): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** 'HH:mm:ss' in server-local time. */
export function toSqlTime(date: Date = new Date()): string {
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

/** Today's queue_date. */
export function todayDate(): string {
  return toSqlDate(new Date());
}

/** 0 = Sunday … 6 = Saturday — matches `service_hours.day_of_week`. */
export function dayOfWeek(date: Date = new Date()): number {
  return date.getDay();
}

/** Parses a stored DATETIME back into a Date, tolerating ISO input. */
export function parseSqlDateTime(value: string | Date | null | undefined): Date | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  const text = String(value).trim();
  if (!text) return null;
  // 'YYYY-MM-DD HH:mm:ss' is not reliably parsed by every engine; build it explicitly.
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(text);
  if (match) {
    const [, y, mo, d, h, mi, s] = match;
    return new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
  }
  const fallback = new Date(text);
  return Number.isNaN(fallback.getTime()) ? null : fallback;
}

/** Stored DATETIME → ISO-8601 string for the API, or null. */
export function toIso(value: string | Date | null | undefined): string | null {
  const date = parseSqlDateTime(value);
  return date ? date.toISOString() : null;
}

/** Whole minutes between two instants, never negative. */
export function minutesBetween(from: Date | string | null, to: Date | string | null): number {
  const a = parseSqlDateTime(from);
  const b = parseSqlDateTime(to);
  if (!a || !b) return 0;
  return Math.max(0, Math.round((b.getTime() - a.getTime()) / 60000));
}

/** Adds days to a 'YYYY-MM-DD' string. */
export function addDays(dateString: string, days: number): string {
  const [y, m, d] = dateString.split('-').map(Number);
  const date = new Date(y, m - 1, d);
  date.setDate(date.getDate() + days);
  return toSqlDate(date);
}

/** Normalises 'HH:mm' or 'HH:mm:ss' to 'HH:mm:ss'. */
export function normaliseTime(value: string): string {
  const parts = value.trim().split(':');
  const h = pad(Number(parts[0] ?? 0));
  const mi = pad(Number(parts[1] ?? 0));
  const s = pad(Number(parts[2] ?? 0));
  return `${h}:${mi}:${s}`;
}

/** 'HH:mm:ss' → 'HH:mm' for API output. */
export function shortTime(value: string | null | undefined): string | null {
  if (!value) return null;
  const parts = String(value).split(':');
  return `${pad(Number(parts[0] ?? 0))}:${pad(Number(parts[1] ?? 0))}`;
}

/** 'HH:mm:ss' → '8:00 AM', for user-facing messages such as "It opens at 8:00 AM". */
export function formatTime12h(value: string | null | undefined): string {
  if (!value) return '';
  const [hRaw, mRaw] = String(value).split(':');
  const hours = Number(hRaw);
  const minutes = Number(mRaw ?? 0);
  const suffix = hours >= 12 ? 'PM' : 'AM';
  const display = hours % 12 === 0 ? 12 : hours % 12;
  return `${display}:${pad(minutes)} ${suffix}`;
}

/** Minutes since midnight, for comparing "now" against service hours. */
export function minutesSinceMidnight(value: string | Date = new Date()): number {
  if (value instanceof Date) return value.getHours() * 60 + value.getMinutes();
  const [h, m] = String(value).split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}
