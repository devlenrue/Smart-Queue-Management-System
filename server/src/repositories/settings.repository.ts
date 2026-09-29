/**
 * SQL for `system_settings` — the super-admin key/value table (§14).
 *
 * Values are stored as text and typed by the reader; a class project does not
 * need a schema registry, and keeping them opaque means adding a setting is a
 * one-line INSERT rather than a migration.
 *
 * The upsert is written as UPDATE-then-INSERT rather than `ON DUPLICATE KEY
 * UPDATE` / `ON CONFLICT DO UPDATE`, because those two spellings are the one
 * thing MySQL and SQLite refuse to agree on.
 */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';

export interface SettingRow {
  setting_key: string;
  setting_value: string;
  description: string | null;
  updated_at: string;
}

export const settingsRepository = {
  async list(conn: DbConn = getDb()): Promise<SettingRow[]> {
    return conn.query<SettingRow>('SELECT * FROM system_settings ORDER BY setting_key ASC');
  },

  async get(key: string, conn: DbConn = getDb()): Promise<SettingRow | null> {
    const rows = await conn.query<SettingRow>('SELECT * FROM system_settings WHERE setting_key = ? LIMIT 1', [key]);
    return rows[0] ?? null;
  },

  async upsert(key: string, value: string, description: string | null = null, conn: DbConn = getDb()): Promise<void> {
    const stamp = toSqlDateTime();
    const updated = await conn.execute(
      'UPDATE system_settings SET setting_value = ?, updated_at = ? WHERE setting_key = ?',
      [value, stamp, key],
    );
    if (updated.affectedRows > 0) return;

    await conn.execute(
      'INSERT INTO system_settings (setting_key, setting_value, description, updated_at) VALUES (?, ?, ?, ?)',
      [key, value, description, stamp],
    );
  },

  async remove(key: string, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('DELETE FROM system_settings WHERE setting_key = ?', [key]);
    return result.affectedRows;
  },
};
