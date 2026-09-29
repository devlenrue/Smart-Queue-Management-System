import { config } from '../config/env';
import { logger } from '../utils/logger';
import { MysqlDriver } from './mysqlDriver';
import { SqliteDriver } from './sqliteDriver';
import type { DbConn, DbDriver } from './types';

export * from './types';
export * from './sql';

let driver: DbDriver | null = null;

function createDriver(): DbDriver {
  if (config.database.dialect === 'mysql') {
    const settings = config.database.mysql;
    if (!settings) throw new Error('MySQL configuration missing from DATABASE_URL');
    logger.info(`Database: MySQL ${settings.host}:${settings.port}/${settings.database}`);
    return new MysqlDriver(settings, config.database.poolSize);
  }
  const file = config.database.sqliteFile ?? ':memory:';
  logger.info(`Database: SQLite ${file} (local driver — MySQL is the deployment target)`);
  return new SqliteDriver(file);
}

/** Lazily created singleton connection pool. */
export function getDb(): DbDriver {
  if (!driver) driver = createDriver();
  return driver;
}

/** Verifies the database is reachable; called once at boot. */
export async function connectDb(): Promise<void> {
  await getDb().ping();
}

export async function closeDb(): Promise<void> {
  if (driver) {
    await driver.close();
    driver = null;
  }
}

/**
 * Runs `fn` inside a transaction (business Rule 14).
 *
 *   await withTransaction(async (tx) => {
 *     await ticketRepository.insert(tx, …);
 *     await eventRepository.insert(tx, …);
 *   });
 */
export function withTransaction<T>(fn: (tx: DbConn) => Promise<T>): Promise<T> {
  return getDb().transaction(fn);
}

/**
 * Retries a transaction when it loses a race on a unique key.
 *
 * Ticket allocation is already serialised by a row lock, so this should never
 * fire; it exists so that a lost race degrades into a retry instead of a 500
 * (docs/queue-engine.md §3).
 */
export async function withRetryableTransaction<T>(fn: (tx: DbConn) => Promise<T>, attempts = 3): Promise<T> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await withTransaction(fn);
    } catch (error) {
      lastError = error;
      if (!getDb().isDuplicateKeyError(error) || attempt === attempts) throw error;
      logger.warn(`Duplicate-key conflict, retrying transaction (attempt ${attempt + 1}/${attempts})`);
      await new Promise((resolve) => setTimeout(resolve, 10 * attempt));
    }
  }
  throw lastError;
}

export function isDuplicateKeyError(error: unknown): boolean {
  return getDb().isDuplicateKeyError(error);
}
