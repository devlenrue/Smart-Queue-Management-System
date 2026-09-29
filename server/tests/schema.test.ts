/**
 * Phase 2 verification.
 *
 * These tests do not go through the API at all. They prove that the *database*
 * enforces the structural rules, so a bug in the application layer — or a
 * direct SQL insert — still cannot corrupt the queue.
 */
import { getDb } from '../src/db';
import { listMigrations, runMigrations, splitStatements } from '../src/db/migrate';
import { todayDate, addDays } from '../src/utils/datetime';
import {
  closeDatabase,
  freshDatabase,
  insertCounter,
  insertQueue,
  insertService,
  insertTicket,
  insertUser,
} from './helpers/db';

const EXPECTED_TABLES = [
  'announcements',
  'notifications',
  'queue_events',
  'queue_settings',
  'queue_tickets',
  'queues',
  'revoked_tokens',
  'schema_migrations',
  'service_counters',
  'service_hours',
  'services',
  'staff_assignments',
  'system_settings',
  'users',
];

beforeAll(async () => {
  await freshDatabase();
});

afterAll(async () => {
  await closeDatabase();
});

describe('migration runner', () => {
  it('creates every table in the design', async () => {
    const rows = await getDb().query<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    expect(rows.map((row) => row.name)).toEqual(EXPECTED_TABLES);
  });

  it('is idempotent — a second run applies nothing', async () => {
    const applied = await runMigrations();
    expect(applied).toEqual([]);
  });

  it('ships a MySQL and a SQLite variant of every migration', () => {
    const mysql = listMigrations('mysql').map((migration) => migration.version);
    const sqlite = listMigrations('sqlite').map((migration) => migration.version);
    expect(mysql.length).toBeGreaterThan(0);
    expect(sqlite).toEqual(mysql);
  });

  it('splits statements without breaking on semicolons inside strings or comments', () => {
    const script = `
      -- a comment with a ; semicolon
      CREATE TABLE demo (note TEXT DEFAULT 'a;b');
      /* block ; comment */
      INSERT INTO demo (note) VALUES ('x;y');
    `;
    const statements = splitStatements(script);
    expect(statements).toHaveLength(2);
    expect(statements[0]).toContain('CREATE TABLE demo');
    expect(statements[1]).toContain("'x;y'");
  });
});

describe('structural constraints', () => {
  it('rejects a duplicate email', async () => {
    await insertUser({ email: 'dupe@test.local' });
    await expect(insertUser({ email: 'dupe@test.local' })).rejects.toThrow();
  });

  it('rejects a duplicate service code', async () => {
    await insertService('DUP', 'First');
    await expect(insertService('DUP', 'Second')).rejects.toThrow();
  });

  it('allows only one queue per service per day', async () => {
    const serviceId = await insertService('ONE', 'One Queue');
    const today = todayDate();
    await insertQueue(serviceId, today);
    await expect(insertQueue(serviceId, today)).rejects.toThrow();
    // …but a different day is fine.
    await expect(insertQueue(serviceId, addDays(today, 1))).resolves.toBeGreaterThan(0);
  });

  it('rejects a duplicate sequence number inside one queue (Rule 12)', async () => {
    const serviceId = await insertService('SEQ', 'Sequence');
    const queueId = await insertQueue(serviceId, todayDate());
    const userA = await insertUser();
    const userB = await insertUser();

    await insertTicket({ queueId, serviceId, userId: userA, sequence: 1, ticketNumber: 'SEQ-001' });
    await expect(
      insertTicket({ queueId, serviceId, userId: userB, sequence: 1, ticketNumber: 'SEQ-999' }),
    ).rejects.toThrow();
  });

  it('rejects a duplicate ticket number inside one queue (Rule 12)', async () => {
    const serviceId = await insertService('NUM', 'Number');
    const queueId = await insertQueue(serviceId, todayDate());
    const userA = await insertUser();
    const userB = await insertUser();

    await insertTicket({ queueId, serviceId, userId: userA, sequence: 1, ticketNumber: 'NUM-001' });
    await expect(
      insertTicket({ queueId, serviceId, userId: userB, sequence: 2, ticketNumber: 'NUM-001' }),
    ).rejects.toThrow();
  });
});

describe('Rule 1 — one active ticket per user per service, enforced by the database', () => {
  it('blocks a second active ticket for the same service', async () => {
    const serviceId = await insertService('R1A', 'Rule One');
    const queueId = await insertQueue(serviceId, todayDate());
    const userId = await insertUser();

    await insertTicket({ queueId, serviceId, userId, sequence: 1, ticketNumber: 'R1A-001' });
    await expect(
      insertTicket({ queueId, serviceId, userId, sequence: 2, ticketNumber: 'R1A-002' }),
    ).rejects.toThrow();
  });

  it('allows a new ticket once the previous one is terminal', async () => {
    const serviceId = await insertService('R1B', 'Rule One B');
    const queueId = await insertQueue(serviceId, todayDate());
    const userId = await insertUser();

    const firstId = await insertTicket({ queueId, serviceId, userId, sequence: 1, ticketNumber: 'R1B-001' });
    await getDb().execute("UPDATE queue_tickets SET status = 'completed' WHERE id = ?", [firstId]);

    await expect(
      insertTicket({ queueId, serviceId, userId, sequence: 2, ticketNumber: 'R1B-002' }),
    ).resolves.toBeGreaterThan(0);
  });

  it('allows simultaneous active tickets for two different services', async () => {
    const serviceA = await insertService('R1C', 'Service C');
    const serviceB = await insertService('R1D', 'Service D');
    const queueA = await insertQueue(serviceA, todayDate());
    const queueB = await insertQueue(serviceB, todayDate());
    const userId = await insertUser();

    await insertTicket({ queueId: queueA, serviceId: serviceA, userId, sequence: 1, ticketNumber: 'R1C-001' });
    await expect(
      insertTicket({ queueId: queueB, serviceId: serviceB, userId, sequence: 1, ticketNumber: 'R1D-001' }),
    ).resolves.toBeGreaterThan(0);
  });
});

describe('Rule 5 — one actively served ticket per counter, enforced by the database', () => {
  it('blocks a second called ticket at the same counter', async () => {
    const serviceId = await insertService('R5A', 'Rule Five');
    const queueId = await insertQueue(serviceId, todayDate());
    const counterId = await insertCounter(serviceId, 1);
    const userA = await insertUser();
    const userB = await insertUser();

    await insertTicket({ queueId, serviceId, userId: userA, sequence: 1, ticketNumber: 'R5A-001', status: 'called', counterId });
    await expect(
      insertTicket({ queueId, serviceId, userId: userB, sequence: 2, ticketNumber: 'R5A-002', status: 'serving', counterId }),
    ).rejects.toThrow();
  });

  it('frees the counter once the ticket is completed', async () => {
    const serviceId = await insertService('R5B', 'Rule Five B');
    const queueId = await insertQueue(serviceId, todayDate());
    const counterId = await insertCounter(serviceId, 1);
    const userA = await insertUser();
    const userB = await insertUser();

    const firstId = await insertTicket({ queueId, serviceId, userId: userA, sequence: 1, ticketNumber: 'R5B-001', status: 'serving', counterId });
    await getDb().execute("UPDATE queue_tickets SET status = 'completed' WHERE id = ?", [firstId]);

    await expect(
      insertTicket({ queueId, serviceId, userId: userB, sequence: 2, ticketNumber: 'R5B-002', status: 'called', counterId }),
    ).resolves.toBeGreaterThan(0);
  });
});

describe('referential integrity', () => {
  it('cascades ticket deletion when a queue is removed', async () => {
    const serviceId = await insertService('CAS', 'Cascade');
    const queueId = await insertQueue(serviceId, todayDate());
    const userId = await insertUser();
    await insertTicket({ queueId, serviceId, userId, sequence: 1, ticketNumber: 'CAS-001' });

    await getDb().execute('DELETE FROM queues WHERE id = ?', [queueId]);
    const remaining = await getDb().query<{ n: number }>('SELECT COUNT(*) AS n FROM queue_tickets WHERE queue_id = ?', [queueId]);
    expect(Number(remaining[0].n)).toBe(0);
  });

  it('nulls a ticket counter rather than deleting service history', async () => {
    const serviceId = await insertService('SNL', 'Set Null');
    const queueId = await insertQueue(serviceId, todayDate());
    const counterId = await insertCounter(serviceId, 1);
    const userId = await insertUser();
    const ticketId = await insertTicket({ queueId, serviceId, userId, sequence: 1, ticketNumber: 'SNL-001', status: 'completed', counterId });

    await getDb().execute('DELETE FROM service_counters WHERE id = ?', [counterId]);
    const rows = await getDb().query<{ counter_id: number | null }>('SELECT counter_id FROM queue_tickets WHERE id = ?', [ticketId]);
    expect(rows[0].counter_id).toBeNull();
  });

  it('rejects a ticket that points at a queue which does not exist', async () => {
    const serviceId = await insertService('FKX', 'Foreign Key');
    const userId = await insertUser();
    await expect(
      insertTicket({ queueId: 999_999, serviceId, userId, sequence: 1, ticketNumber: 'FKX-001' }),
    ).rejects.toThrow();
  });
});

describe('seed data', () => {
  it('produces the documented dataset', async () => {
    await freshDatabase({ seed: true });
    const db = getDb();

    const count = async (table: string, where = ''): Promise<number> => {
      const rows = await db.query<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table} ${where}`);
      return Number(rows[0].n);
    };

    expect(await count('users')).toBe(23);
    expect(await count('users', "WHERE role = 'super_admin'")).toBe(1);
    expect(await count('users', "WHERE role = 'admin'")).toBe(2);
    expect(await count('users', "WHERE role = 'staff'")).toBe(5);
    expect(await count('users', "WHERE role = 'customer'")).toBe(15);
    expect(await count('services')).toBe(5);
    expect(await count('queue_settings')).toBe(5);
    expect(await count('service_hours')).toBe(35);
    expect(await count('service_counters')).toBe(13);
    expect(await count('staff_assignments')).toBe(5);
    expect(await count('announcements')).toBe(3);
    expect(await count('queues')).toBe(15);
    expect(await count('queue_tickets')).toBeGreaterThan(100);
  });

  it('leaves no counter marked busy without a live ticket', async () => {
    const rows = await getDb().query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM service_counters c
        WHERE c.status = 'busy'
          AND NOT EXISTS (SELECT 1 FROM queue_tickets t WHERE t.counter_id = c.id AND t.status IN ('called','serving'))`,
    );
    expect(Number(rows[0].n)).toBe(0);
  });

  it('covers every ticket status so the UI has something to render', async () => {
    const rows = await getDb().query<{ status: string }>('SELECT DISTINCT status FROM queue_tickets');
    const statuses = rows.map((row) => row.status).sort();
    expect(statuses).toEqual(['called', 'cancelled', 'completed', 'no_show', 'serving', 'skipped', 'waiting']);
  });
});
