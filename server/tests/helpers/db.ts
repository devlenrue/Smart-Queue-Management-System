import { closeDb, getDb } from '../../src/db';
import { dropAll, runMigrations } from '../../src/db/migrate';
import { runSeed } from '../../src/db/seed';
import { toSqlDateTime } from '../../src/utils/datetime';
import type { DbDriver } from '../../src/db/types';

/** Drops everything, re-migrates, and optionally seeds. */
export async function freshDatabase(options: { seed?: boolean } = {}): Promise<DbDriver> {
  await dropAll();
  await runMigrations();
  if (options.seed) await runSeed();
  return getDb();
}

export async function closeDatabase(): Promise<void> {
  await closeDb();
}

export const nowSql = (): string => toSqlDateTime();

/** Inserts a bare user row without going through the API. */
export async function insertUser(overrides: Partial<{
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  role: string;
  status: string;
}> = {}): Promise<number> {
  const stamp = nowSql();
  const unique = Math.floor(Math.random() * 1_000_000_000);
  const result = await getDb().execute(
    `INSERT INTO users (first_name, last_name, email, phone, password_hash, role, status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      overrides.firstName ?? 'Test',
      overrides.lastName ?? 'User',
      overrides.email ?? `user${unique}@test.local`,
      overrides.phone ?? `+2547${String(unique).padStart(8, '0').slice(0, 8)}`,
      '$2a$04$abcdefghijklmnopqrstuv',
      overrides.role ?? 'customer',
      overrides.status ?? 'active',
      stamp,
      stamp,
    ],
  );
  return result.insertId;
}

export async function insertService(code = 'TST', name = 'Test Service'): Promise<number> {
  const stamp = nowSql();
  const result = await getDb().execute(
    `INSERT INTO services (name, code, description, category, average_service_time, daily_capacity, status, created_at, updated_at)
     VALUES (?, ?, 'Test', 'Test', 5, 200, 'open', ?, ?)`,
    [name, code, stamp, stamp],
  );
  return result.insertId;
}

export async function insertCounter(serviceId: number, counterNumber = 1, staffId: number | null = null): Promise<number> {
  const stamp = nowSql();
  const result = await getDb().execute(
    `INSERT INTO service_counters (service_id, counter_number, name, status, assigned_staff_id, created_at, updated_at)
     VALUES (?, ?, ?, 'available', ?, ?, ?)`,
    [serviceId, counterNumber, `Counter ${counterNumber}`, staffId, stamp, stamp],
  );
  return result.insertId;
}

export async function insertQueue(serviceId: number, queueDate: string): Promise<number> {
  const stamp = nowSql();
  const result = await getDb().execute(
    `INSERT INTO queues (service_id, queue_date, status, current_number, last_issued_number, total_served, created_at, updated_at)
     VALUES (?, ?, 'waiting', 0, 0, 0, ?, ?)`,
    [serviceId, queueDate, stamp, stamp],
  );
  return result.insertId;
}

export async function insertTicket(params: {
  queueId: number;
  serviceId: number;
  userId: number;
  sequence: number;
  ticketNumber: string;
  status?: string;
  counterId?: number | null;
}): Promise<number> {
  const stamp = nowSql();
  const result = await getDb().execute(
    `INSERT INTO queue_tickets
       (queue_id, service_id, user_id, ticket_number, sequence_number, status, counter_id,
        estimated_wait_minutes, joined_at, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 5, ?, ?, ?)`,
    [
      params.queueId,
      params.serviceId,
      params.userId,
      params.ticketNumber,
      params.sequence,
      params.status ?? 'waiting',
      params.counterId ?? null,
      stamp,
      stamp,
      stamp,
    ],
  );
  return result.insertId;
}
