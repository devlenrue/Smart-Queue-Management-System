import fs from 'node:fs';
import path from 'node:path';
import { config } from '../config/env';
import { logger } from '../utils/logger';
import { toSqlDateTime } from '../utils/datetime';
import { getDb } from './index';
import type { DbConn } from './types';

/**
 * Forward-only migration runner.
 *
 * Reads `database/migrations/NNN_name.<dialect>.sql`, applies anything not yet
 * recorded in `schema_migrations`, and records it. Running it twice is a no-op.
 */

export function resolveMigrationsDir(): string {
  const candidates = [
    process.env.MIGRATIONS_DIR,
    path.resolve(__dirname, '../../../database/migrations'),
    path.resolve(process.cwd(), '../database/migrations'),
    path.resolve(process.cwd(), 'database/migrations'),
  ].filter((candidate): candidate is string => Boolean(candidate));

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(`Could not locate database/migrations. Looked in:\n${candidates.join('\n')}`);
}

/**
 * Splits a SQL script into statements.
 *
 * A naive `split(';')` breaks on semicolons inside string literals and
 * comments, so this walks the text tracking quoting state. The schema uses no
 * stored procedures, so no custom DELIMITER handling is needed.
 */
export function splitStatements(script: string): string[] {
  const statements: string[] = [];
  let current = '';
  let quote: "'" | '"' | '`' | null = null;
  let lineComment = false;
  let blockComment = false;

  for (let i = 0; i < script.length; i += 1) {
    const char = script[i];
    const next = script[i + 1];

    if (lineComment) {
      if (char === '\n') {
        lineComment = false;
        current += char;
      }
      continue;
    }
    if (blockComment) {
      if (char === '*' && next === '/') {
        blockComment = false;
        i += 1;
      }
      continue;
    }
    if (quote) {
      current += char;
      if (char === '\\' && quote !== '`') {
        current += next ?? '';
        i += 1;
      } else if (char === quote) {
        // '' inside a string is an escaped quote
        if (next === quote) {
          current += next;
          i += 1;
        } else {
          quote = null;
        }
      }
      continue;
    }

    if (char === '-' && next === '-') {
      lineComment = true;
      i += 1;
      continue;
    }
    if (char === '/' && next === '*') {
      blockComment = true;
      i += 1;
      continue;
    }
    if (char === "'" || char === '"' || char === '`') {
      quote = char;
      current += char;
      continue;
    }
    if (char === ';') {
      if (current.trim()) statements.push(current.trim());
      current = '';
      continue;
    }
    current += char;
  }

  if (current.trim()) statements.push(current.trim());
  return statements;
}

export interface MigrationFile {
  version: string;
  file: string;
  fullPath: string;
}

export function listMigrations(dialect = config.database.dialect): MigrationFile[] {
  const dir = resolveMigrationsDir();
  const suffix = `.${dialect}.sql`;
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith(suffix))
    .sort((a, b) => a.localeCompare(b, 'en'))
    .map((file) => ({ version: file.slice(0, -suffix.length), file, fullPath: path.join(dir, file) }));
}

async function ensureMigrationsTable(db: DbConn): Promise<void> {
  const sql =
    db.dialect === 'mysql'
      ? `CREATE TABLE IF NOT EXISTS schema_migrations (
           version    VARCHAR(100) NOT NULL,
           applied_at DATETIME     NOT NULL,
           PRIMARY KEY (version)
         ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`
      : `CREATE TABLE IF NOT EXISTS schema_migrations (
           version    TEXT PRIMARY KEY,
           applied_at TEXT NOT NULL
         )`;
  await db.execute(sql);
}

export async function runMigrations(): Promise<string[]> {
  const db = getDb();
  await ensureMigrationsTable(db);

  const applied = new Set(
    (await db.query<{ version: string }>('SELECT version FROM schema_migrations')).map((row) => row.version),
  );

  const pending = listMigrations().filter((migration) => !applied.has(migration.version));
  if (pending.length === 0) {
    logger.info('Database is already up to date; no migrations to apply.');
    return [];
  }

  const applieds: string[] = [];
  for (const migration of pending) {
    const script = fs.readFileSync(migration.fullPath, 'utf8');
    const statements = splitStatements(script);
    logger.info(`Applying ${migration.file} (${statements.length} statements)`);
    // Each migration is one transaction. MySQL commits DDL implicitly, which is
    // a documented MySQL limitation, not a bug in the runner.
    await db.transaction(async (tx) => {
      for (const statement of statements) {
        await tx.execute(statement);
      }
      await tx.execute('INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)', [
        migration.version,
        toSqlDateTime(),
      ]);
    });
    applieds.push(migration.version);
  }

  logger.info(`Applied ${applieds.length} migration(s).`);
  return applieds;
}

/** Drops every table. Used by `npm run db:reset` and by the test harness. */
export async function dropAll(): Promise<void> {
  const db = getDb();
  const tables = [
    'schema_migrations',
    'announcements',
    'notifications',
    'staff_assignments',
    'queue_events',
    'queue_tickets',
    'queues',
    'queue_settings',
    'service_hours',
    'service_counters',
    'services',
    'revoked_tokens',
    'system_settings',
    'users',
  ];

  if (db.dialect === 'mysql') await db.execute('SET FOREIGN_KEY_CHECKS = 0');
  else await db.execute('PRAGMA foreign_keys = OFF');

  for (const table of tables) {
    await db.execute(`DROP TABLE IF EXISTS ${table}`);
  }

  if (db.dialect === 'mysql') await db.execute('SET FOREIGN_KEY_CHECKS = 1');
  else await db.execute('PRAGMA foreign_keys = ON');
}
