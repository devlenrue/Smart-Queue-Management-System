import mysql from 'mysql2/promise';
import type { MysqlConnectionConfig } from '../config/env';
import type { DbConn, DbDriver, DbRow, WriteResult } from './types';
import { logger } from '../utils/logger';

interface MysqlErrorLike {
  code?: string;
  errno?: number;
}

function wrapConnection(connection: mysql.PoolConnection | mysql.Pool): DbConn {
  return {
    dialect: 'mysql',
    async query<T = DbRow>(sql: string, params: readonly unknown[] = []): Promise<T[]> {
      const [rows] = await connection.query(sql, params as unknown[]);
      return rows as T[];
    },
    async execute(sql: string, params: readonly unknown[] = []): Promise<WriteResult> {
      const [result] = await connection.query(sql, params as unknown[]);
      const header = result as mysql.ResultSetHeader;
      return { insertId: Number(header.insertId ?? 0), affectedRows: Number(header.affectedRows ?? 0) };
    },
  };
}

/**
 * The production driver: a real mysql2 connection pool.
 *
 * `dateStrings: true` makes DATE/DATETIME/TIME come back as the exact strings
 * that were written, which is what keeps this driver and the SQLite one
 * byte-compatible (see utils/datetime.ts).
 */
export class MysqlDriver implements DbDriver {
  readonly dialect = 'mysql' as const;
  private readonly pool: mysql.Pool;
  private readonly root: DbConn;

  constructor(settings: MysqlConnectionConfig, poolSize: number) {
    this.pool = mysql.createPool({
      host: settings.host,
      port: settings.port,
      user: settings.user,
      password: settings.password,
      database: settings.database,
      waitForConnections: true,
      connectionLimit: poolSize,
      queueLimit: 0,
      dateStrings: true,
      supportBigNumbers: true,
      bigNumberStrings: false,
      multipleStatements: false,
      timezone: 'local',
      charset: 'utf8mb4_unicode_ci',
    });
    this.root = wrapConnection(this.pool);
  }

  query<T = DbRow>(sql: string, params: readonly unknown[] = []): Promise<T[]> {
    return this.root.query<T>(sql, params);
  }

  execute(sql: string, params: readonly unknown[] = []): Promise<WriteResult> {
    return this.root.execute(sql, params);
  }

  async transaction<T>(fn: (tx: DbConn) => Promise<T>): Promise<T> {
    const connection = await this.pool.getConnection();
    try {
      await connection.beginTransaction();
      try {
        const result = await fn(wrapConnection(connection));
        await connection.commit();
        return result;
      } catch (error) {
        await connection.rollback().catch((rollbackError) => {
          logger.error('Transaction rollback failed', rollbackError);
        });
        throw error;
      }
    } finally {
      connection.release();
    }
  }

  isDuplicateKeyError(error: unknown): boolean {
    const candidate = error as MysqlErrorLike | null;
    return candidate?.code === 'ER_DUP_ENTRY' || candidate?.errno === 1062;
  }

  async ping(): Promise<void> {
    await this.pool.query('SELECT 1');
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
