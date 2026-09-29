/**
 * All SQL that touches `users`, `revoked_tokens` and `system_settings`.
 *
 * Every statement is parameterised — there is no string concatenation of user
 * input anywhere in this file (§62). Sort columns come from an allow-list.
 */
import { getDb, likeTerm, safeSortColumn, safeSortDirection } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';
import type { Role, UserRow, UserStatus } from '../types/domain';

const SORTABLE: Record<string, string> = {
  createdAt: 'created_at',
  firstName: 'first_name',
  lastName: 'last_name',
  email: 'email',
  role: 'role',
  status: 'status',
};

export interface CreateUserInput {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  passwordHash: string;
  role: Role;
  status?: UserStatus;
}

export interface UserListFilters {
  role?: Role;
  status?: UserStatus;
  search?: string;
  page: number;
  limit: number;
  sort?: string;
  order?: string;
}

export const userRepository = {
  async findById(id: number, conn: DbConn = getDb()): Promise<UserRow | null> {
    const rows = await conn.query<UserRow>('SELECT * FROM users WHERE id = ? LIMIT 1', [id]);
    return rows[0] ?? null;
  },

  async findByEmail(email: string, conn: DbConn = getDb()): Promise<UserRow | null> {
    const rows = await conn.query<UserRow>('SELECT * FROM users WHERE email = ? LIMIT 1', [email.toLowerCase()]);
    return rows[0] ?? null;
  },

  async findByPhone(phone: string, conn: DbConn = getDb()): Promise<UserRow | null> {
    const rows = await conn.query<UserRow>('SELECT * FROM users WHERE phone = ? LIMIT 1', [phone]);
    return rows[0] ?? null;
  },

  async emailExists(email: string, exceptId?: number, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      `SELECT id FROM users WHERE email = ?${exceptId ? ' AND id <> ?' : ''} LIMIT 1`,
      exceptId ? [email.toLowerCase(), exceptId] : [email.toLowerCase()],
    );
    return rows.length > 0;
  },

  async phoneExists(phone: string, exceptId?: number, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      `SELECT id FROM users WHERE phone = ?${exceptId ? ' AND id <> ?' : ''} LIMIT 1`,
      exceptId ? [phone, exceptId] : [phone],
    );
    return rows.length > 0;
  },

  async create(input: CreateUserInput, conn: DbConn = getDb()): Promise<number> {
    const stamp = toSqlDateTime();
    const result = await conn.execute(
      `INSERT INTO users (first_name, last_name, email, phone, password_hash, role, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        input.firstName,
        input.lastName,
        input.email.toLowerCase(),
        input.phone,
        input.passwordHash,
        input.role,
        input.status ?? 'active',
        stamp,
        stamp,
      ],
    );
    return result.insertId;
  },

  async updateProfile(
    id: number,
    input: { firstName?: string; lastName?: string; phone?: string },
    conn: DbConn = getDb(),
  ): Promise<void> {
    const sets: string[] = [];
    const params: unknown[] = [];
    if (input.firstName !== undefined) { sets.push('first_name = ?'); params.push(input.firstName); }
    if (input.lastName !== undefined) { sets.push('last_name = ?'); params.push(input.lastName); }
    if (input.phone !== undefined) { sets.push('phone = ?'); params.push(input.phone); }
    if (sets.length === 0) return;
    sets.push('updated_at = ?');
    params.push(toSqlDateTime(), id);
    await conn.execute(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`, params);
  },

  async updatePassword(id: number, passwordHash: string, conn: DbConn = getDb()): Promise<void> {
    await conn.execute('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?', [
      passwordHash,
      toSqlDateTime(),
      id,
    ]);
  },

  async updateStatus(id: number, status: UserStatus, conn: DbConn = getDb()): Promise<void> {
    await conn.execute('UPDATE users SET status = ?, updated_at = ? WHERE id = ?', [status, toSqlDateTime(), id]);
  },

  async updateRole(id: number, role: Role, conn: DbConn = getDb()): Promise<void> {
    await conn.execute('UPDATE users SET role = ?, updated_at = ? WHERE id = ?', [role, toSqlDateTime(), id]);
  },

  async remove(id: number, conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('DELETE FROM users WHERE id = ?', [id]);
    return result.affectedRows;
  },

  /** Paginated, filtered, searchable user list for the admin console (§40). */
  async list(filters: UserListFilters, conn: DbConn = getDb()): Promise<{ rows: UserRow[]; total: number }> {
    const where: string[] = [];
    const params: unknown[] = [];

    if (filters.role) { where.push('role = ?'); params.push(filters.role); }
    if (filters.status) { where.push('status = ?'); params.push(filters.status); }
    if (filters.search?.trim()) {
      where.push('(first_name LIKE ? OR last_name LIKE ? OR email LIKE ? OR phone LIKE ?)');
      const term = likeTerm(filters.search.trim());
      params.push(term, term, term, term);
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const totals = await conn.query<{ n: number }>(`SELECT COUNT(*) AS n FROM users ${whereSql}`, params);
    const total = Number(totals[0]?.n ?? 0);

    const column = safeSortColumn(filters.sort, SORTABLE, 'created_at');
    const direction = safeSortDirection(filters.order ?? 'desc');
    const offset = (filters.page - 1) * filters.limit;

    const rows = await conn.query<UserRow>(
      `SELECT * FROM users ${whereSql} ORDER BY ${column} ${direction}, id DESC LIMIT ? OFFSET ?`,
      [...params, filters.limit, offset],
    );
    return { rows, total };
  },

  async countByRole(conn: DbConn = getDb()): Promise<Record<string, number>> {
    const rows = await conn.query<{ role: string; n: number }>('SELECT role, COUNT(*) AS n FROM users GROUP BY role');
    return Object.fromEntries(rows.map((row) => [row.role, Number(row.n)]));
  },
};

export const tokenRepository = {
  async revoke(jti: string, userId: number, expiresAt: Date, conn: DbConn = getDb()): Promise<void> {
    await conn.execute(
      'INSERT INTO revoked_tokens (jti, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)',
      [jti, userId, toSqlDateTime(expiresAt), toSqlDateTime()],
    );
  },

  async isRevoked(jti: string, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ jti: string }>('SELECT jti FROM revoked_tokens WHERE jti = ? LIMIT 1', [jti]);
    return rows.length > 0;
  },

  /** Housekeeping: revoked tokens are worthless once they would have expired. */
  async pruneExpired(conn: DbConn = getDb()): Promise<number> {
    const result = await conn.execute('DELETE FROM revoked_tokens WHERE expires_at < ?', [toSqlDateTime()]);
    return result.affectedRows;
  },
};
