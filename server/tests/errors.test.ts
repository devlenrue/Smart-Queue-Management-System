/**
 * Phase 9 — the error contract.
 *
 * docs/api.md promises that every failure comes back as
 * `{ success: false, message, code, errors[] }`, and that a given `code` is
 * always paired with the same HTTP status. This suite proves both, one code at
 * a time, by actually provoking each failure through the HTTP layer.
 *
 * The last test in the file is the important one: it walks the runtime
 * catalogue in src/utils/AppError.ts and fails if any 4xx code has no test
 * above. Adding a new error code without a negative-path test breaks the build.
 */
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import type { Express } from 'express';
import jwt from 'jsonwebtoken';
import { createApp } from '../src/app';
import { config } from '../src/config/env';
import { getDb } from '../src/db';
import { ERROR_CODES, statusForCode, type ErrorCode } from '../src/utils/AppError';
import { assignmentRepository } from '../src/repositories/assignment.repository';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, join, setupService, TEST_PASSWORD } from './helpers/api';

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

/** Codes proved in a different file, with a note saying where. */
const PROVED_ELSEWHERE: Partial<Record<ErrorCode, string>> = {
  // The limiter is disabled under NODE_ENV=test everywhere except that file,
  // which re-enables it through RATE_LIMIT_IN_TESTS before importing the app.
  RATE_LIMITED: 'tests/security.test.ts',
};

/** `await ok(join(...), 201)` — those helpers return a bare promise, not a chainable supertest request. */
async function ok(pending: Promise<request.Response>, status = 200): Promise<request.Response> {
  const response = await pending;
  if (response.status !== status) {
    throw new Error(`Expected ${status} but got ${response.status}: ${JSON.stringify(response.body)}`);
  }
  return response;
}

const exercised = new Set<ErrorCode>();

/**
 * Asserts the full envelope, not just the status: a wrong code with the right
 * status is still a broken contract for the Flutter client, which switches on
 * `code` (see mobile/lib/core/error/error_mapper.dart).
 */
function expectError(response: request.Response, code: ErrorCode): void {
  expect({
    status: response.status,
    code: response.body?.code,
    success: response.body?.success,
    message: response.body?.message,
    errors: response.body?.errors,
  }).toEqual({
    status: statusForCode(code),
    code,
    success: false,
    message: expect.any(String),
    errors: expect.any(Array),
  });
  expect(response.body.message.length).toBeGreaterThan(0);
  expect(response.body).not.toHaveProperty('data');
  exercised.add(code);
}

// ---------------------------------------------------------------------------
// 400 — the request itself is wrong
// ---------------------------------------------------------------------------

describe('400', () => {
  it('BAD_REQUEST — a body that is not valid JSON', async () => {
    const response = await request(app)
      .post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{"email": "broken@test.local"');

    expectError(response, 'BAD_REQUEST');
  });

  it('BAD_REQUEST — a clerk calling the next ticket with no counter to call it to', async () => {
    const { serviceId } = await setupService(app);
    const floater = await createUserAndLogin(app, { role: 'staff' });
    // Assigned to the service, but standing at no counter.
    await assignmentRepository.create({ staffId: floater.id, serviceId, counterId: null });

    expectError(await callNext(app, floater, serviceId), 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------------------
// 401 — who are you?
// ---------------------------------------------------------------------------

describe('401', () => {
  it('UNAUTHENTICATED — no token at all', async () => {
    expectError(await request(app).get('/api/v1/profile'), 'UNAUTHENTICATED');
  });

  it('UNAUTHENTICATED — a token that does not verify', async () => {
    const response = await request(app).get('/api/v1/profile').set('Authorization', bearer('not.a.real.token'));
    expectError(response, 'UNAUTHENTICATED');
  });

  it('INVALID_CREDENTIALS — the right email with the wrong password', async () => {
    const user = await createUserAndLogin(app);
    const response = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: user.email, password: `${TEST_PASSWORD}-wrong` });

    expectError(response, 'INVALID_CREDENTIALS');
  });

  it('INVALID_CREDENTIALS — an email nobody has registered (no account enumeration)', async () => {
    const response = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'ghost@test.local', password: TEST_PASSWORD });

    expectError(response, 'INVALID_CREDENTIALS');
    expect(response.body.message).not.toMatch(/exist|found|unknown/i);
  });

  it('TOKEN_EXPIRED — a properly signed token whose lifetime has run out', async () => {
    const user = await createUserAndLogin(app);
    const expired = jwt.sign({ sub: String(user.id), role: 'customer' }, config.jwt.secret, {
      expiresIn: '-1m',
      jwtid: randomUUID(),
    });

    expectError(await request(app).get('/api/v1/profile').set('Authorization', bearer(expired)), 'TOKEN_EXPIRED');
  });

  it('TOKEN_REVOKED — a token reused after signing out', async () => {
    const user = await createUserAndLogin(app);
    await request(app).post('/api/v1/auth/logout').set('Authorization', bearer(user.token)).expect(200);

    expectError(await request(app).get('/api/v1/profile').set('Authorization', bearer(user.token)), 'TOKEN_REVOKED');
  });
});

// ---------------------------------------------------------------------------
// 403 — we know who you are, and you may not
// ---------------------------------------------------------------------------

describe('403', () => {
  it('FORBIDDEN — a customer reaching for an admin endpoint', async () => {
    const shopper = await createUserAndLogin(app);
    expectError(await request(app).get('/api/v1/users').set('Authorization', bearer(shopper.token)), 'FORBIDDEN');
  });

  it('ACCOUNT_INACTIVE — a deactivated account with a still-valid token', async () => {
    const user = await createUserAndLogin(app);
    await getDb().execute('UPDATE users SET status = ? WHERE id = ?', ['inactive', user.id]);

    expectError(await request(app).get('/api/v1/profile').set('Authorization', bearer(user.token)), 'ACCOUNT_INACTIVE');
  });

  it('ACCOUNT_SUSPENDED — a suspended account with a still-valid token', async () => {
    const user = await createUserAndLogin(app);
    await getDb().execute('UPDATE users SET status = ? WHERE id = ?', ['suspended', user.id]);

    expectError(await request(app).get('/api/v1/profile').set('Authorization', bearer(user.token)), 'ACCOUNT_SUSPENDED');
  });

  it('NOT_ASSIGNED_TO_SERVICE — a clerk managing a queue that is not theirs (Rule 4)', async () => {
    const finance = await setupService(app, { code: 'FIN', name: 'Finance Office' });
    const registry = await setupService(app, { code: 'REG', name: 'Registry' });
    await join(app, registry.serviceId, await createUserAndLogin(app));

    // Finance's clerk, pointed at Registry's queue.
    expectError(await callNext(app, finance.staff[0], registry.serviceId), 'NOT_ASSIGNED_TO_SERVICE');
  });
});

// ---------------------------------------------------------------------------
// 404 — no such thing
// ---------------------------------------------------------------------------

describe('404', () => {
  it('NOT_FOUND — a service id that does not exist', async () => {
    expectError(await request(app).get('/api/v1/services/999999'), 'NOT_FOUND');
  });

  it('NOT_FOUND — a route that does not exist, still in the envelope', async () => {
    const response = await request(app).get('/api/v1/nothing-here');
    expectError(response, 'NOT_FOUND');
    expect(response.body.message).toContain('/api/v1/nothing-here');
  });

  it('NOT_FOUND — every service sub-resource checks the parent first', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const auth = bearer(boss.token);
    const missing = 999999;

    expectError(await request(app).get(`/api/v1/services/${missing}/hours`), 'NOT_FOUND');
    expectError(await request(app).get(`/api/v1/services/${missing}/settings`).set('Authorization', auth), 'NOT_FOUND');
    expectError(
      await request(app).put(`/api/v1/services/${missing}/settings`).set('Authorization', auth).send({ maxQueueSize: 50 }),
      'NOT_FOUND',
    );
    expectError(
      await request(app)
        .put(`/api/v1/services/${missing}/hours`)
        .set('Authorization', auth)
        .send({ hours: [{ dayOfWeek: 1, openingTime: '09:00', closingTime: '17:00', status: 'open' }] }),
      'NOT_FOUND',
    );
    expectError(
      await request(app).put(`/api/v1/services/${missing}`).set('Authorization', auth).send({ name: 'Renamed' }),
      'NOT_FOUND',
    );
    expectError(await request(app).delete(`/api/v1/services/${missing}`).set('Authorization', auth), 'NOT_FOUND');
  });

  it('NOT_FOUND — tickets, queues, counters and staff that do not exist', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const auth = bearer(boss.token);
    const missing = 999999;

    expectError(await request(app).get(`/api/v1/tickets/${missing}`).set('Authorization', auth), 'NOT_FOUND');
    expectError(await request(app).get(`/api/v1/tickets/${missing}/position`).set('Authorization', auth), 'NOT_FOUND');
    expectError(await request(app).get(`/api/v1/queues/${missing}`), 'NOT_FOUND');
    expectError(await request(app).get(`/api/v1/queues/${missing}/monitor`).set('Authorization', auth), 'NOT_FOUND');
    expectError(
      await request(app).put(`/api/v1/counters/${missing}`).set('Authorization', auth).send({ name: 'Desk' }),
      'NOT_FOUND',
    );
    expectError(
      await request(app).put(`/api/v1/staff/${missing}`).set('Authorization', auth).send({ firstName: 'Nobody' }),
      'NOT_FOUND',
    );
    expectError(await request(app).get(`/api/v1/staff/${missing}/statistics`).set('Authorization', auth), 'NOT_FOUND');
    expectError(await request(app).get(`/api/v1/users/${missing}`).set('Authorization', auth), 'NOT_FOUND');
  });

  it('NO_WAITING_TICKETS — calling next on an empty queue', async () => {
    const { serviceId, staff } = await setupService(app);
    expectError(await callNext(app, staff[0], serviceId), 'NO_WAITING_TICKETS');
  });
});

// ---------------------------------------------------------------------------
// 409 — well formed, but it conflicts with the state of the world
// ---------------------------------------------------------------------------

describe('409 — accounts', () => {
  const registration = (overrides: Record<string, string> = {}) => ({
    firstName: 'Amina',
    lastName: 'Otieno',
    email: `amina${Math.floor(Math.random() * 1_000_000)}@test.local`,
    phone: `+2547${Math.floor(10_000_000 + Math.random() * 80_000_000)}`,
    password: 'Password123',
    confirmPassword: 'Password123',
    ...overrides,
  });

  it('EMAIL_TAKEN — registering an email that already exists', async () => {
    const first = registration();
    await request(app).post('/api/v1/auth/register').send(first).expect(201);

    const response = await request(app).post('/api/v1/auth/register').send(registration({ email: first.email }));
    expectError(response, 'EMAIL_TAKEN');
  });

  it('PHONE_TAKEN — registering a phone number that already exists', async () => {
    const first = registration();
    await request(app).post('/api/v1/auth/register').send(first).expect(201);

    const response = await request(app).post('/api/v1/auth/register').send(registration({ phone: first.phone }));
    expectError(response, 'PHONE_TAKEN');
  });

  it('PHONE_TAKEN — moving someone else\'s number onto your own profile', async () => {
    const other = registration();
    await request(app).post('/api/v1/auth/register').send(other).expect(201);
    const me = await createUserAndLogin(app);

    const response = await request(app)
      .put('/api/v1/profile')
      .set('Authorization', bearer(me.token))
      .send({ phone: other.phone });

    expectError(response, 'PHONE_TAKEN');
  });

  it('CONFLICT — an administrator acting on their own account', async () => {
    const boss = await createUserAndLogin(app, { role: 'super_admin' });
    const auth = bearer(boss.token);

    expectError(
      await request(app).patch(`/api/v1/users/${boss.id}/status`).set('Authorization', auth).send({ status: 'inactive' }),
      'CONFLICT',
    );
    expectError(
      await request(app).patch(`/api/v1/users/${boss.id}/role`).set('Authorization', auth).send({ role: 'customer' }),
      'CONFLICT',
    );
    expectError(await request(app).delete(`/api/v1/users/${boss.id}`).set('Authorization', auth), 'CONFLICT');
  });

  it('CONFLICT — posting a customer to a service counter', async () => {
    const { serviceId, counterIds } = await setupService(app, { counters: 2 });
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const shopper = await createUserAndLogin(app);

    // The second counter is free, but the person named is not staff.
    const response = await request(app)
      .post(`/api/v1/counters/${counterIds[1]}/assign`)
      .set('Authorization', bearer(boss.token))
      .send({ staffId: shopper.id });

    expect(serviceId).toBeGreaterThan(0);
    expectError(response, 'CONFLICT');
  });
});

describe('409 — the catalogue', () => {
  it('SERVICE_CODE_TAKEN — two services cannot share a code', async () => {
    await setupService(app, { code: 'FIN' });
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(boss.token))
      .send({ name: 'Another Finance', code: 'FIN', category: 'Admin', averageServiceTime: 5, dailyCapacity: 100 });

    expectError(response, 'SERVICE_CODE_TAKEN');
  });

  it('SERVICE_CODE_TAKEN — nor can a rename steal one', async () => {
    const first = await setupService(app, { code: 'FIN' });
    const second = await setupService(app, { code: 'REG' });
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/services/${second.serviceId}`)
      .set('Authorization', bearer(boss.token))
      .send({ code: 'FIN' });

    expect(first.serviceId).toBeGreaterThan(0);
    expectError(response, 'SERVICE_CODE_TAKEN');
  });

  it('COUNTER_NUMBER_TAKEN — counter numbers are unique within a service', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .post('/api/v1/counters')
      .set('Authorization', bearer(boss.token))
      .send({ serviceId, counterNumber: 1, name: 'Duplicate Desk' });

    expectError(response, 'COUNTER_NUMBER_TAKEN');
  });

  it('STAFF_ALREADY_ASSIGNED — one counter, one clerk (Rule 5)', async () => {
    const { serviceId, counterIds } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const newcomer = await createUserAndLogin(app, { role: 'staff' });

    const response = await request(app)
      .post(`/api/v1/staff/${newcomer.id}/assign`)
      .set('Authorization', bearer(boss.token))
      .send({ serviceId, counterId: counterIds[0] });

    expectError(response, 'STAFF_ALREADY_ASSIGNED');
  });
});

describe('409 — joining a queue', () => {
  it('DUPLICATE_ACTIVE_TICKET — one active ticket per person per service (Rule 1)', async () => {
    const { serviceId } = await setupService(app);
    const shopper = await createUserAndLogin(app);
    await ok(join(app, serviceId, shopper), 201);

    expectError(await join(app, serviceId, shopper), 'DUPLICATE_ACTIVE_TICKET');
  });

  it('REJOIN_NOT_ALLOWED — a service that does not allow a second attempt today', async () => {
    const { serviceId, staff, counterIds } = await setupService(app, { allowRejoin: false });
    const shopper = await createUserAndLogin(app);

    // The rule bites on people who have *already been dealt with* today
    // (completed, skipped or no-show), so take the ticket all the way through.
    const first = await ok(join(app, serviceId, shopper), 201);
    const ticketId = first.body.data.ticket.id;
    await ok(callNext(app, staff[0], serviceId, counterIds[0]), 200);
    await ok(act(app, staff[0], ticketId, 'start'), 200);
    await ok(act(app, staff[0], ticketId, 'complete'), 200);

    expectError(await join(app, serviceId, shopper), 'REJOIN_NOT_ALLOWED');
  });

  it('SERVICE_CLOSED — the service is closed for the day', async () => {
    const { serviceId } = await setupService(app, { status: 'closed' });
    expectError(await join(app, serviceId, await createUserAndLogin(app)), 'SERVICE_CLOSED');
  });

  it('SERVICE_INACTIVE — the service has been retired', async () => {
    const { serviceId } = await setupService(app, { status: 'inactive' });
    expectError(await join(app, serviceId, await createUserAndLogin(app)), 'SERVICE_INACTIVE');
  });

  it('OUTSIDE_SERVICE_HOURS — today is a closed day', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const today = new Date().getDay();

    await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(boss.token))
      .send({ hours: [{ dayOfWeek: today, openingTime: '09:00', closingTime: '17:00', status: 'closed' }] })
      .expect(200);

    expectError(await join(app, serviceId, await createUserAndLogin(app)), 'OUTSIDE_SERVICE_HOURS');
  });

  it('OUTSIDE_SERVICE_HOURS — the doors have not opened yet', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const today = new Date().getDay();

    // A window that has certainly not started: it opens at 23:58.
    await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(boss.token))
      .send({ hours: [{ dayOfWeek: today, openingTime: '23:58', closingTime: '23:59', status: 'open' }] })
      .expect(200);

    const response = await join(app, serviceId, await createUserAndLogin(app));
    // Between 23:58 and 23:59 the window is genuinely open; skip that minute.
    if (response.status === 201) return;
    expectError(response, 'OUTSIDE_SERVICE_HOURS');
  });

  it('QUEUE_PAUSED — an administrator has paused intake', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const first = await ok(join(app, serviceId, await createUserAndLogin(app)), 201);
    const queueId = first.body.data.ticket.queueId;

    await request(app).post(`/api/v1/queues/${queueId}/pause`).set('Authorization', bearer(boss.token)).expect(200);

    expectError(await join(app, serviceId, await createUserAndLogin(app)), 'QUEUE_PAUSED');
  });

  it('QUEUE_CLOSED — the queue is finished for the day', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const first = await ok(join(app, serviceId, await createUserAndLogin(app)), 201);
    const queueId = first.body.data.ticket.queueId;

    await request(app).post(`/api/v1/queues/${queueId}/close`).set('Authorization', bearer(boss.token)).expect(200);

    expectError(await join(app, serviceId, await createUserAndLogin(app)), 'QUEUE_CLOSED');
  });

  it('QUEUE_FULL — the day\'s capacity is spent (Rule 8)', async () => {
    const { serviceId } = await setupService(app, { maxQueueSize: 1 });
    await ok(join(app, serviceId, await createUserAndLogin(app)), 201);

    expectError(await join(app, serviceId, await createUserAndLogin(app)), 'QUEUE_FULL');
  });
});

describe('409 — working a ticket', () => {
  it('INVALID_STATE_TRANSITION — completing a ticket nobody has called', async () => {
    const { serviceId, staff } = await setupService(app);
    const shopper = await createUserAndLogin(app);
    const ticket = (await ok(join(app, serviceId, shopper), 201)).body.data.ticket;

    expectError(await act(app, staff[0], ticket.id, 'complete'), 'INVALID_STATE_TRANSITION');
  });

  it('INVALID_STATE_TRANSITION — a terminal ticket cannot move again', async () => {
    const { serviceId } = await setupService(app);
    const shopper = await createUserAndLogin(app);
    const ticket = (await ok(join(app, serviceId, shopper), 201)).body.data.ticket;
    await ok(act(app, shopper, ticket.id, 'cancel'), 200);

    expectError(await act(app, shopper, ticket.id, 'cancel'), 'INVALID_STATE_TRANSITION');
  });

  it('CANCELLATION_NOT_ALLOWED — a service that forbids walking away', async () => {
    const { serviceId } = await setupService(app, { allowCancellation: false });
    const shopper = await createUserAndLogin(app);
    const ticket = (await ok(join(app, serviceId, shopper), 201)).body.data.ticket;

    expectError(await act(app, shopper, ticket.id, 'cancel'), 'CANCELLATION_NOT_ALLOWED');
  });

  it('COUNTER_OFFLINE — calling a ticket to a closed desk', async () => {
    const { serviceId, staff, counterIds } = await setupService(app);
    await ok(join(app, serviceId, await createUserAndLogin(app)), 201);
    await request(app)
      .patch(`/api/v1/counters/${counterIds[0]}/status`)
      .set('Authorization', bearer(staff[0].token))
      .send({ status: 'offline' })
      .expect(200);

    expectError(await callNext(app, staff[0], serviceId, counterIds[0]), 'COUNTER_OFFLINE');
  });

  it('COUNTER_BUSY — a desk with a live customer cannot be emptied', async () => {
    const { serviceId, staff, counterIds } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    await ok(join(app, serviceId, await createUserAndLogin(app)), 201);
    await ok(callNext(app, staff[0], serviceId, counterIds[0]), 200);

    const response = await request(app)
      .delete(`/api/v1/counters/${counterIds[0]}/assign`)
      .set('Authorization', bearer(boss.token));

    expectError(response, 'COUNTER_BUSY');
  });
});

// ---------------------------------------------------------------------------
// 413 / 422
// ---------------------------------------------------------------------------

describe('413', () => {
  it('PAYLOAD_TOO_LARGE — a body over the 256 kB ceiling is refused, not crashed on', async () => {
    const response = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'big@test.local', password: 'x'.repeat(300_000) });

    expectError(response, 'PAYLOAD_TOO_LARGE');
  });
});

describe('422', () => {
  it('VALIDATION_ERROR — field-level detail the client can attach to inputs', async () => {
    const response = await request(app).post('/api/v1/auth/register').send({
      firstName: 'A',
      lastName: '',
      email: 'not-an-email',
      phone: '123',
      password: 'short',
      confirmPassword: 'different',
    });

    expectError(response, 'VALIDATION_ERROR');
    expect(response.body.errors.length).toBeGreaterThan(1);
    expect(response.body.errors[0]).toEqual({ field: expect.any(String), message: expect.any(String) });
    expect(response.body.errors.map((e: { field: string }) => e.field)).toEqual(
      expect.arrayContaining(['email', 'password']),
    );
  });

  it('VALIDATION_ERROR — a path parameter that is not a number', async () => {
    expectError(await request(app).get('/api/v1/services/abc'), 'VALIDATION_ERROR');
  });

  it('VALIDATION_ERROR — a query parameter out of range', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const response = await request(app)
      .get('/api/v1/users?page=0&limit=9999')
      .set('Authorization', bearer(boss.token));

    expectError(response, 'VALIDATION_ERROR');
  });
});

// ---------------------------------------------------------------------------
// The point of the file
// ---------------------------------------------------------------------------

describe('the catalogue itself', () => {
  it('pairs every code with exactly one HTTP status', () => {
    for (const code of ERROR_CODES) {
      const status = statusForCode(code);
      expect(status).toBeGreaterThanOrEqual(400);
      expect(status).toBeLessThan(600);
    }
  });

  it('has a negative-path test for every 4xx code', () => {
    const clientErrors = ERROR_CODES.filter((code) => statusForCode(code) < 500);
    const missing = clientErrors.filter((code) => !exercised.has(code) && !PROVED_ELSEWHERE[code]);

    expect(missing).toEqual([]);
    // Sanity: the sweep above is not silently passing because nothing ran.
    expect(exercised.size).toBeGreaterThanOrEqual(clientErrors.length - Object.keys(PROVED_ELSEWHERE).length);
  });
});
