/**
 * Phase 4 verification — §60 concurrency.
 *
 * "Two customers tap Join at the same instant" is the scenario that breaks
 * naive queue systems: both read `last_issued_number = 7`, both write 8, and
 * two people hold ticket FIN-008.
 *
 * The engine prevents this with a row lock taken at the top of the join
 * transaction (SELECT … FOR UPDATE on MySQL, BEGIN IMMEDIATE on SQLite),
 * backed by a UNIQUE (queue_id, sequence_number) constraint as the last line
 * of defence. These tests fire the requests genuinely in parallel with
 * Promise.all and then audit the database.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, setupService, type TestUser } from './helpers/api';
import { getDb, isDuplicateKeyError } from '../src/db';
import { todayDate } from '../src/utils/datetime';

let app: Express;

beforeAll(async () => {
  await freshDatabase();
  app = createApp();
});

afterAll(async () => {
  await closeDatabase();
});

beforeEach(async () => {
  await clearQueueData();
});

async function makeCustomers(count: number): Promise<TestUser[]> {
  const users: TestUser[] = [];
  for (let i = 0; i < count; i += 1) users.push(await createUserAndLogin(app));
  return users;
}

/** Fires every join at once, without awaiting in between. */
function joinAllAtOnce(serviceId: number, users: TestUser[]) {
  return Promise.all(
    users.map((user) =>
      request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(user.token)),
    ),
  );
}

describe('simultaneous joins', () => {
  it('gives ten customers ten different ticket numbers', async () => {
    const { serviceId } = await setupService(app);
    const customers = await makeCustomers(10);

    const responses = await joinAllAtOnce(serviceId, customers);

    expect(responses.every((r) => r.status === 201)).toBe(true);

    const numbers = responses.map((r) => r.body.data.ticket.ticketNumber).sort();
    expect(new Set(numbers).size).toBe(10);
    expect(numbers).toEqual([
      'FIN-001',
      'FIN-002',
      'FIN-003',
      'FIN-004',
      'FIN-005',
      'FIN-006',
      'FIN-007',
      'FIN-008',
      'FIN-009',
      'FIN-010',
    ]);
  });

  it('allocates a contiguous run of sequence numbers with no gaps or repeats', async () => {
    const { serviceId } = await setupService(app);
    const customers = await makeCustomers(12);

    await joinAllAtOnce(serviceId, customers);

    const rows = await getDb().query<{ sequence_number: number }>(
      'SELECT sequence_number FROM queue_tickets WHERE service_id = ? ORDER BY sequence_number ASC',
      [serviceId],
    );
    expect(rows.map((r) => Number(r.sequence_number))).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  });

  it('leaves last_issued_number exactly equal to the number of tickets issued', async () => {
    const { serviceId } = await setupService(app);
    const customers = await makeCustomers(8);

    await joinAllAtOnce(serviceId, customers);

    const queue = await getDb().query<{ last_issued_number: number }>(
      'SELECT last_issued_number FROM queues WHERE service_id = ? AND queue_date = ?',
      [serviceId, todayDate()],
    );
    const tickets = await getDb().query<{ n: number }>('SELECT COUNT(*) AS n FROM queue_tickets WHERE service_id = ?', [
      serviceId,
    ]);

    expect(Number(queue[0].last_issued_number)).toBe(8);
    expect(Number(tickets[0].n)).toBe(8);
  });

  it('creates only one queue row when the day\'s first joins arrive together', async () => {
    const { serviceId } = await setupService(app);
    const customers = await makeCustomers(6);

    await joinAllAtOnce(serviceId, customers);

    const queues = await getDb().query<{ n: number }>('SELECT COUNT(*) AS n FROM queues WHERE service_id = ?', [
      serviceId,
    ]);
    expect(Number(queues[0].n)).toBe(1);
  });

  it('issues exactly one ticket when the same customer taps Join twice at once (Rule 1)', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const responses = await Promise.all([
      request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(customer.token)),
      request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(customer.token)),
      request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(customer.token)),
    ]);

    const created = responses.filter((r) => r.status === 201);
    const rejected = responses.filter((r) => r.status !== 201);

    expect(created).toHaveLength(1);
    expect(rejected).toHaveLength(2);
    expect(rejected.every((r) => r.status === 409)).toBe(true);

    const tickets = await getDb().query<{ n: number }>(
      'SELECT COUNT(*) AS n FROM queue_tickets WHERE user_id = ? AND service_id = ?',
      [customer.id, serviceId],
    );
    expect(Number(tickets[0].n)).toBe(1);
  });

  it('never exceeds capacity, however many people arrive together (Rule 3)', async () => {
    const { serviceId } = await setupService(app, { maxQueueSize: 3 });
    const customers = await makeCustomers(9);

    const responses = await joinAllAtOnce(serviceId, customers);

    const accepted = responses.filter((r) => r.status === 201);
    const refused = responses.filter((r) => r.status === 409);

    expect(accepted).toHaveLength(3);
    expect(refused).toHaveLength(6);
    expect(refused.every((r) => r.body.code === 'QUEUE_FULL')).toBe(true);
  });

  it('keeps two services independent under parallel load', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const library = await setupService(app, { code: 'LIB' });
    const customers = await makeCustomers(5);

    await Promise.all([
      ...customers.map((u) =>
        request(app).post(`/api/v1/services/${finance.serviceId}/queue/join`).set('Authorization', bearer(u.token)),
      ),
      ...customers.map((u) =>
        request(app).post(`/api/v1/services/${library.serviceId}/queue/join`).set('Authorization', bearer(u.token)),
      ),
    ]);

    const rows = await getDb().query<{ code: string; n: number }>(
      `SELECT s.code AS code, COUNT(*) AS n
         FROM queue_tickets t JOIN services s ON s.id = t.service_id
        GROUP BY s.code ORDER BY s.code`,
    );
    expect(rows.map((r) => [r.code, Number(r.n)])).toEqual([
      ['FIN', 5],
      ['LIB', 5],
    ]);
  });
});

describe('simultaneous staff actions', () => {
  it('hands two staff calling at once two different customers', async () => {
    const { serviceId, staff } = await setupService(app, { counters: 2 });
    await joinAllAtOnce(serviceId, await makeCustomers(4));

    const [first, second] = await Promise.all([
      callNext(app, staff[0], serviceId),
      callNext(app, staff[1], serviceId),
    ]);

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(first.body.data.ticket.id).not.toBe(second.body.data.ticket.id);
    expect(first.body.data.ticket.counter.id).not.toBe(second.body.data.ticket.counter.id);
  });

  it('gives three staff three distinct tickets, in order', async () => {
    const { serviceId, staff } = await setupService(app, { counters: 3 });
    await joinAllAtOnce(serviceId, await makeCustomers(6));

    const results = await Promise.all(staff.map((member) => callNext(app, member, serviceId)));
    const numbers = results.map((r) => r.body.data.ticket.ticketNumber).sort();

    expect(numbers).toEqual(['FIN-001', 'FIN-002', 'FIN-003']);
  });

  it('lets only one of several simultaneous completions succeed', async () => {
    const { serviceId, staff } = await setupService(app, { counters: 1 });
    await joinAllAtOnce(serviceId, await makeCustomers(1));
    const called = await callNext(app, staff[0], serviceId);
    const ticketId = called.body.data.ticket.id;
    await act(app, staff[0], ticketId, 'start');

    const responses = await Promise.all([
      act(app, staff[0], ticketId, 'complete'),
      act(app, staff[0], ticketId, 'complete'),
      act(app, staff[0], ticketId, 'complete'),
    ]);

    expect(responses.filter((r) => r.status === 200)).toHaveLength(1);
    expect(responses.filter((r) => r.status === 409)).toHaveLength(2);

    const queue = await getDb().query<{ total_served: number }>('SELECT total_served FROM queues WHERE service_id = ?', [
      serviceId,
    ]);
    expect(Number(queue[0].total_served)).toBe(1);
  });

  it('does not let a cancellation and a call both take effect on one ticket', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await request(app)
      .post(`/api/v1/services/${serviceId}/queue/join`)
      .set('Authorization', bearer(customer.token));
    const ticketId = ticket.body.data.ticket.id;

    const [cancelled, calledResult] = await Promise.all([
      act(app, customer, ticketId, 'cancel'),
      act(app, staff[0], ticketId, 'call'),
    ]);

    const outcomes = [cancelled.status, calledResult.status].sort();
    expect(outcomes).toEqual([200, 409]);

    const row = await getDb().query<{ status: string }>('SELECT status FROM queue_tickets WHERE id = ?', [ticketId]);
    expect(['cancelled', 'called']).toContain(row[0].status);
  });
});

describe('the database is the final guard', () => {
  it('rejects a duplicate sequence number even if the application logic were bypassed', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(customer.token));

    const other = await createUserAndLogin(app);
    const queue = await getDb().query<{ id: number }>('SELECT id FROM queues WHERE service_id = ?', [serviceId]);

    let caught: unknown;
    try {
      // Deliberately re-using sequence 1 — this is the race the lock prevents.
      await getDb().execute(
        `INSERT INTO queue_tickets
           (queue_id, service_id, user_id, ticket_number, sequence_number, status, estimated_wait_minutes, joined_at, created_at, updated_at)
         VALUES (?, ?, ?, 'FIN-999', 1, 'waiting', 0, datetime('now'), datetime('now'), datetime('now'))`,
        [queue[0].id, serviceId, other.id],
      );
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeDefined();
    expect(isDuplicateKeyError(caught)).toBe(true);
  });

  it('rejects a duplicate ticket number within the same queue (Rule 12)', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(customer.token));

    const other = await createUserAndLogin(app);
    const queue = await getDb().query<{ id: number }>('SELECT id FROM queues WHERE service_id = ?', [serviceId]);

    let caught: unknown;
    try {
      await getDb().execute(
        `INSERT INTO queue_tickets
           (queue_id, service_id, user_id, ticket_number, sequence_number, status, estimated_wait_minutes, joined_at, created_at, updated_at)
         VALUES (?, ?, ?, 'FIN-001', 99, 'waiting', 0, datetime('now'), datetime('now'), datetime('now'))`,
        [queue[0].id, serviceId, other.id],
      );
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeDefined();
    expect(isDuplicateKeyError(caught)).toBe(true);
  });

  it('rejects a second active ticket for one user through the unique index (Rule 1)', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(customer.token));

    const queue = await getDb().query<{ id: number }>('SELECT id FROM queues WHERE service_id = ?', [serviceId]);

    let caught: unknown;
    try {
      await getDb().execute(
        `INSERT INTO queue_tickets
           (queue_id, service_id, user_id, ticket_number, sequence_number, status, estimated_wait_minutes, joined_at, created_at, updated_at)
         VALUES (?, ?, ?, 'FIN-050', 50, 'waiting', 0, datetime('now'), datetime('now'), datetime('now'))`,
        [queue[0].id, serviceId, customer.id],
      );
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeDefined();
    expect(isDuplicateKeyError(caught)).toBe(true);
  });
});
