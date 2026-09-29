import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import type { DbConn, DbDriver, DbRow, WriteResult } from './types';
import { toSqlDateTime } from '../utils/datetime';

/**
 * Local development / test driver.
 *
 * The target database for this project is MySQL. This driver exists so the
 * queue engine and its concurrency tests can run on a machine with no MySQL
 * server (see docs/roadmap.md "Verification strategy"). It speaks the same
 * `DbConn` interface, so not a single repository knows which one is in use.
 *
 * Two details make it behave like the MySQL driver rather than merely compile:
 *
 *  1. `BEGIN IMMEDIATE` takes SQLite's write lock at the *start* of the
 *     transaction, matching the pessimistic `SELECT … FOR UPDATE` semantics the
 *     queue engine relies on.
 *  2. `node:sqlite` is synchronous, so two interleaved `await`s could otherwise
 *     nest transactions on the one connection. A promise-chain mutex serialises
 *     them, which is exactly what a row lock does on MySQL.
 */
export class SqliteDriver implements DbDriver {
  readonly dialect = 'sqlite' as const;
  private readonly db: DatabaseSync;
  /** Serialises transactions — see note 2 above. */
  private chain: Promise<unknown> = Promise.resolve();

  constructor(file: string) {
    if (file !== ':memory:') {
      const dir = path.dirname(path.resolve(file));
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    }
    this.db = new DatabaseSync(file);
    this.db.exec('PRAGMA foreign_keys = ON');
    this.db.exec('PRAGMA journal_mode = WAL');
    this.db.exec('PRAGMA busy_timeout = 5000');
  }

  private static normaliseParams(params: readonly unknown[]): SQLInputValue[] {
    return params.map((value) => {
      if (value === undefined || value === null) return null;
      if (typeof value === 'boolean') return value ? 1 : 0;
      if (value instanceof Date) return toSqlDateTime(value);
      if (typeof value === 'number' || typeof value === 'bigint' || typeof value === 'string') return value;
      if (value instanceof Uint8Array) return value;
      return String(value);
    }) as SQLInputValue[];
  }

  private runQuery<T>(sql: string, params: readonly unknown[]): T[] {
    const statement = this.db.prepare(sql);
    return statement.all(...SqliteDriver.normaliseParams(params)) as T[];
  }

  private runExecute(sql: string, params: readonly unknown[]): WriteResult {
    const statement = this.db.prepare(sql);
    const result = statement.run(...SqliteDriver.normaliseParams(params));
    return { insertId: Number(result.lastInsertRowid ?? 0), affectedRows: Number(result.changes ?? 0) };
  }

  async query<T = DbRow>(sql: string, params: readonly unknown[] = []): Promise<T[]> {
    return this.runQuery<T>(sql, params);
  }

  async execute(sql: string, params: readonly unknown[] = []): Promise<WriteResult> {
    return this.runExecute(sql, params);
  }

  /** Multi-statement DDL, used only by the migration runner. */
  execScript(sql: string): void {
    this.db.exec(sql);
  }

  private get handle(): DbConn {
    return {
      dialect: this.dialect,
      query: async <T = DbRow>(sql: string, params: readonly unknown[] = []) => this.runQuery<T>(sql, params),
      execute: async (sql: string, params: readonly unknown[] = []) => this.runExecute(sql, params),
    };
  }

  transaction<T>(fn: (tx: DbConn) => Promise<T>): Promise<T> {
    const run = async (): Promise<T> => {
      this.db.exec('BEGIN IMMEDIATE');
      try {
        const result = await fn(this.handle);
        this.db.exec('COMMIT');
        return result;
      } catch (error) {
        try {
          this.db.exec('ROLLBACK');
        } catch {
          /* the transaction was already rolled back by SQLite */
        }
        throw error;
      }
    };

    const queued = this.chain.then(run, run);
    this.chain = queued.then(
      () => undefined,
      () => undefined,
    );
    return queued;
  }

  isDuplicateKeyError(error: unknown): boolean {
    const message = error instanceof Error ? error.message : String(error);
    return message.includes('UNIQUE constraint failed') || message.includes('PRIMARY KEY must be unique');
  }

  async ping(): Promise<void> {
    this.runQuery('SELECT 1', []);
  }

  async close(): Promise<void> {
    this.db.close();
  }
}
