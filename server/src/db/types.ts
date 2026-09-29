import type { DbDialect } from '../config/env';

export type { DbDialect };

export type DbRow = Record<string, unknown>;

export interface WriteResult {
  /** AUTO_INCREMENT id of the inserted row (0 for non-inserts). */
  insertId: number;
  affectedRows: number;
}

/**
 * The surface a repository is allowed to use. Both the pooled driver and a
 * transaction handle implement it, which is why every repository function can
 * take a `DbConn` and work identically inside or outside a transaction.
 */
export interface DbConn {
  readonly dialect: DbDialect;
  query<T = DbRow>(sql: string, params?: readonly unknown[]): Promise<T[]>;
  execute(sql: string, params?: readonly unknown[]): Promise<WriteResult>;
}

export interface DbDriver extends DbConn {
  /**
   * Runs `fn` inside a real database transaction, committing on success and
   * rolling back on any thrown error. Used by every multi-row queue operation
   * (business Rule 14).
   */
  transaction<T>(fn: (tx: DbConn) => Promise<T>): Promise<T>;
  /** True when the error is a unique-constraint violation. */
  isDuplicateKeyError(error: unknown): boolean;
  ping(): Promise<void>;
  close(): Promise<void>;
}
