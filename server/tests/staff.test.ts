/**
 * Phase 6 verification — the staff console's read model and the counter
 * switch, plus the two rules that keep one clerk out of another's queue.
 *
 * Covers §20 (staff dashboard), §37 (staff statistics), §53 (staff endpoints)
 * and §59 Rules 4 and 5. The §74 walkthrough — sign in, see the queue, call,
 * serve, complete, watch the numbers move — is the last describe block.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, join, setupService } from './helpers/api';
import type { TestService, TestUser } from './helpers/api';

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

const dashboard = (user: TestUser, query = '') =>
  request(app).get(`/api/v1/dashboard/staff${query}`).set('Authorization', bearer(user.token));

const statistics = (viewer: TestUser, staffId: number | 'me', query = '') =>
  request(app).get(`/api/v1/staff/${staffId}/statistics${query}`).set('Authorization', bearer(viewer.token));

const handled = (viewer: TestUser, staffId: number | 'me', query = '') =>
  request(app).get(`/api/v1/staff/${staffId}/tickets${query}`).set('Authorization', bearer(viewer.token));

const setCounterStatus = (user: TestUser, counterId: number, status: string) =>
  request(app)
    .patch(`/api/v1/counters/${counterId}/status`)
    .set('Authorization', bearer(user.token))
    .send({ status });

/** Drives one ticket all the way from joining to completed. */
async function serveOne(service: TestService, staff: TestUser, customer: TestUser): Promise<number> {
  const joined = await join(app, service.serviceId, customer);
  expect(joined.status).toBe(201);
  const called = await callNext(app, staff, service.serviceId);
  expect(called.status).toBe(200);
  const ticketId = called.body.data.ticket.id;
  expect((await act(app, staff, ticketId, 'start')).status).toBe(200);
  expect((await act(app, staff, ticketId, 'complete')).status).toBe(200);
  return ticketId;
}

// ---------------------------------------------------------------------------
// Access control
// ---------------------------------------------------------------------------

describe('staff console access control', () => {
  it('refuses the staff dashboard to a customer', async () => {
    const customer = await createUserAndLogin(app);
    const response = await dashboard(customer);

    expect(response.status).toBe(403);
    expect(response.body.success).toBe(false);
  });

  it('refuses the staff dashboard to an anonymous caller', async () => {
    const response = await request(app).get('/api/v1/dashboard/staff');
    expect(response.status).toBe(401);
  });

  it('lets one staff member read only their own statistics', async () => {
    const service = await setupService(app, { counters: 2 });
    const [first, second] = service.staff;

    expect((await statistics(first, first.id)).status).toBe(200);
    expect((await statistics(first, second.id)).status).toBe(403);
  });

  it('lets an admin read anyone\'s statistics', async () => {
    const service = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await statistics(admin, service.staff[0].id);
    expect(response.status).toBe(200);
    expect(response.body.data.staff.id).toBe(service.staff[0].id);
  });

  it('accepts "me" as the staff id', async () => {
    const service = await setupService(app);
    const response = await statistics(service.staff[0], 'me');

    expect(response.status).toBe(200);
    expect(response.body.data.staff.id).toBe(service.staff[0].id);
  });
});

// ---------------------------------------------------------------------------
// Rule 4 — a staff member may only work their own service's queue
// ---------------------------------------------------------------------------

describe('Rule 4 — assignment scoping', () => {
  it('refuses a call-next for a service the staff member is not assigned to', async () => {
    const finance = await setupService(app, { code: 'FIN', name: 'Finance Office' });
    const registry = await setupService(app, { code: 'REG', name: 'Registry' });
    const customer = await createUserAndLogin(app);
    await join(app, registry.serviceId, customer);

    const response = await callNext(app, finance.staff[0], registry.serviceId, registry.counterIds[0]);

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('NOT_ASSIGNED_TO_SERVICE');
  });

  it('refuses a transition on another service\'s ticket', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const registry = await setupService(app, { code: 'REG' });
    const customer = await createUserAndLogin(app);

    await join(app, registry.serviceId, customer);
    const called = await callNext(app, registry.staff[0], registry.serviceId);
    const ticketId = called.body.data.ticket.id;

    const response = await act(app, finance.staff[0], ticketId, 'start');

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('NOT_ASSIGNED_TO_SERVICE');
  });

  it('refuses the counter list of a service the staff member does not work', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const registry = await setupService(app, { code: 'REG' });

    const own = await request(app)
      .get(`/api/v1/counters?serviceId=${finance.serviceId}`)
      .set('Authorization', bearer(finance.staff[0].token));
    const other = await request(app)
      .get(`/api/v1/counters?serviceId=${registry.serviceId}`)
      .set('Authorization', bearer(finance.staff[0].token));

    expect(own.status).toBe(200);
    expect(other.status).toBe(403);
    expect(other.body.code).toBe('NOT_ASSIGNED_TO_SERVICE');
  });

  it('ignores a serviceId override that is not the staff member\'s own', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const registry = await setupService(app, { code: 'REG' });

    const response = await dashboard(finance.staff[0], `?serviceId=${registry.serviceId}`);

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('NOT_ASSIGNED_TO_SERVICE');
  });
});

// ---------------------------------------------------------------------------
// Rule 5 — one active ticket per counter
// ---------------------------------------------------------------------------

describe('Rule 5 — a busy counter takes no second ticket', () => {
  it('rejects a second call to the same counter', async () => {
    const service = await setupService(app, { counters: 1 });
    const [staff] = service.staff;
    const a = await createUserAndLogin(app);
    const b = await createUserAndLogin(app);
    await join(app, service.serviceId, a);
    await join(app, service.serviceId, b);

    const first = await callNext(app, staff, service.serviceId);
    const second = await callNext(app, staff, service.serviceId);

    expect(first.status).toBe(200);
    expect(second.status).toBe(409);
    expect(second.body.code).toBe('COUNTER_BUSY');
  });

  it('frees the counter once the ticket is completed', async () => {
    const service = await setupService(app, { counters: 1 });
    const [staff] = service.staff;
    const a = await createUserAndLogin(app);
    const b = await createUserAndLogin(app);
    await join(app, service.serviceId, a);
    await join(app, service.serviceId, b);

    const first = await callNext(app, staff, service.serviceId);
    await act(app, staff, first.body.data.ticket.id, 'start');
    await act(app, staff, first.body.data.ticket.id, 'complete');

    const second = await callNext(app, staff, service.serviceId);
    expect(second.status).toBe(200);
    expect(second.body.data.ticket.ticketNumber).toBe('FIN-002');
  });
});

// ---------------------------------------------------------------------------
// The counter switch
// ---------------------------------------------------------------------------

describe('counter status', () => {
  it('lets a clerk take their own counter offline and back', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;

    const offline = await setCounterStatus(staff, service.counterIds[0], 'offline');
    expect(offline.status).toBe(200);
    expect(offline.body.data.status).toBe('offline');

    const back = await setCounterStatus(staff, service.counterIds[0], 'available');
    expect(back.status).toBe(200);
    expect(back.body.data.status).toBe('available');
  });

  it('refuses to go offline while a customer is at the counter', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    const customer = await createUserAndLogin(app);
    await join(app, service.serviceId, customer);
    const called = await callNext(app, staff, service.serviceId);
    await act(app, staff, called.body.data.ticket.id, 'start');

    const response = await setCounterStatus(staff, service.counterIds[0], 'offline');

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('COUNTER_BUSY');
  });

  it('refuses to change somebody else\'s counter', async () => {
    const service = await setupService(app, { counters: 2 });

    const response = await setCounterStatus(service.staff[0], service.counterIds[1], 'offline');

    expect(response.status).toBe(403);
  });

  it('stops an offline counter from calling a ticket', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    const customer = await createUserAndLogin(app);
    await join(app, service.serviceId, customer);
    await setCounterStatus(staff, service.counterIds[0], 'offline');

    const response = await callNext(app, staff, service.serviceId);

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('COUNTER_OFFLINE');
  });
});

// ---------------------------------------------------------------------------
// GET /dashboard/staff
// ---------------------------------------------------------------------------

describe('GET /dashboard/staff', () => {
  it('reports an unassigned staff member honestly instead of failing', async () => {
    const orphan = await createUserAndLogin(app, { role: 'staff' });

    const response = await dashboard(orphan);

    expect(response.status).toBe(200);
    expect(response.body.data.assigned).toBe(false);
    expect(response.body.data.service).toBeNull();
    expect(response.body.data.counter).toBeNull();
    expect(response.body.data.upNext).toEqual([]);
    expect(response.body.data.stats.waiting).toBe(0);
  });

  it('names the service and counter the clerk is working', async () => {
    const service = await setupService(app, { code: 'FIN', name: 'Finance Office' });

    const response = await dashboard(service.staff[0]);

    expect(response.status).toBe(200);
    expect(response.body.data.assigned).toBe(true);
    expect(response.body.data.service).toMatchObject({ code: 'FIN', name: 'Finance Office' });
    expect(response.body.data.counter).toMatchObject({ counterNumber: 1, status: 'available' });
    expect(response.body.data.assignment.serviceCode).toBe('FIN');
  });

  it('lists who is waiting, in queue order, with the customer attached', async () => {
    const service = await setupService(app);
    const first = await createUserAndLogin(app, { firstName: 'Ann', lastName: 'First' });
    const second = await createUserAndLogin(app, { firstName: 'Ben', lastName: 'Second' });
    await join(app, service.serviceId, first);
    await join(app, service.serviceId, second);

    const response = await dashboard(service.staff[0]);

    expect(response.body.data.queue.waitingCount).toBe(2);
    expect(response.body.data.upNext.map((t: { ticketNumber: string }) => t.ticketNumber)).toEqual([
      'FIN-001',
      'FIN-002',
    ]);
    expect(response.body.data.upNext[0].customer.fullName).toBe('Ann First');
  });

  it('shows the ticket currently at the counter', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    const customer = await createUserAndLogin(app, { firstName: 'Cara', lastName: 'Third' });
    await join(app, service.serviceId, customer);
    const called = await callNext(app, staff, service.serviceId);
    await act(app, staff, called.body.data.ticket.id, 'start');

    const response = await dashboard(staff);

    expect(response.body.data.currentTicket).toMatchObject({
      ticketNumber: 'FIN-001',
      status: 'serving',
    });
    expect(response.body.data.currentTicket.customer.fullName).toBe('Cara Third');
    expect(response.body.data.counter.status).toBe('busy');
  });

  it('counts what this clerk served, not what the service served', async () => {
    const service = await setupService(app, { counters: 2 });
    const [mine, theirs] = service.staff;

    await serveOne(service, mine, await createUserAndLogin(app));
    await serveOne(service, theirs, await createUserAndLogin(app));
    await serveOne(service, theirs, await createUserAndLogin(app));

    const response = await dashboard(mine);

    expect(response.body.data.stats.servedToday).toBe(1);
    // The queue-wide figure is still available, on the queue object.
    expect(response.body.data.queue.completedToday).toBe(3);
  });

  it('lets an admin look at any service\'s console', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const customer = await createUserAndLogin(app);
    await join(app, finance.serviceId, customer);

    const response = await dashboard(admin, `?serviceId=${finance.serviceId}`);

    expect(response.status).toBe(200);
    expect(response.body.data.service.code).toBe('FIN');
    expect(response.body.data.queue.waitingCount).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// GET /staff/:id/statistics
// ---------------------------------------------------------------------------

describe('GET /staff/:id/statistics', () => {
  it('returns zeroes for a clerk who has done nothing yet', async () => {
    const service = await setupService(app);

    const response = await statistics(service.staff[0], 'me');

    expect(response.body.data.ticketsServed).toBe(0);
    expect(response.body.data.ticketsSkipped).toBe(0);
    expect(response.body.data.averageServiceMinutes).toBe(0);
    expect(response.body.data.completionRate).toBe(0);
    expect(response.body.data.byDay).toEqual([]);
  });

  it('counts served, skipped and no-show separately', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;

    await serveOne(service, staff, await createUserAndLogin(app));

    // A skip straight from waiting.
    const skipped = await join(app, service.serviceId, await createUserAndLogin(app));
    await act(app, staff, skipped.body.data.ticket.id, 'skip', { reason: 'Stepped out' });

    // A no-show has to be called first.
    await join(app, service.serviceId, await createUserAndLogin(app));
    const calledForNoShow = await callNext(app, staff, service.serviceId);
    await act(app, staff, calledForNoShow.body.data.ticket.id, 'no-show');

    const response = await statistics(staff, 'me');

    expect(response.body.data.ticketsServed).toBe(1);
    expect(response.body.data.ticketsSkipped).toBe(1);
    expect(response.body.data.ticketsNoShow).toBe(1);
    expect(response.body.data.ticketsHandled).toBe(3);
    expect(response.body.data.completionRate).toBe(33);
  });

  it('credits work to the clerk who did it', async () => {
    const service = await setupService(app, { counters: 2 });
    const [mine, theirs] = service.staff;

    await serveOne(service, mine, await createUserAndLogin(app));
    await serveOne(service, mine, await createUserAndLogin(app));
    await serveOne(service, theirs, await createUserAndLogin(app));

    expect((await statistics(mine, 'me')).body.data.ticketsServed).toBe(2);
    expect((await statistics(theirs, 'me')).body.data.ticketsServed).toBe(1);
  });

  it('groups the served count by day', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    await serveOne(service, staff, await createUserAndLogin(app));
    await serveOne(service, staff, await createUserAndLogin(app));

    const response = await statistics(staff, 'me');
    const today = new Date();
    const iso = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(
      today.getDate(),
    ).padStart(2, '0')}`;

    expect(response.body.data.byDay).toHaveLength(1);
    expect(response.body.data.byDay[0]).toMatchObject({ date: iso, served: 2 });
  });

  it('defaults to the last seven days and honours an explicit range', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    await serveOne(service, staff, await createUserAndLogin(app));

    const past = await statistics(staff, 'me', '?from=2020-01-01&to=2020-01-31');

    expect(past.body.data.range).toEqual({ from: '2020-01-01', to: '2020-01-31' });
    expect(past.body.data.ticketsServed).toBe(0);

    const now = await statistics(staff, 'me');
    expect(now.body.data.ticketsServed).toBe(1);
    expect(now.body.data.range.from < now.body.data.range.to).toBe(true);
  });

  it('rejects a malformed date', async () => {
    const service = await setupService(app);

    const response = await statistics(service.staff[0], 'me', '?from=yesterday');

    expect(response.status).toBe(422);
    expect(response.body.errors[0].field).toBe('from');
  });
});

// ---------------------------------------------------------------------------
// GET /staff/:id/tickets
// ---------------------------------------------------------------------------

describe('GET /staff/:id/tickets', () => {
  it('lists the tickets this clerk handled, once each', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    const ticketId = await serveOne(service, staff, await createUserAndLogin(app));

    const response = await handled(staff, 'me');

    expect(response.status).toBe(200);
    // Called, started and completed by the same person — but one row.
    expect(response.body.data.tickets).toHaveLength(1);
    expect(response.body.data.tickets[0].id).toBe(ticketId);
    expect(response.body.data.tickets[0].status).toBe('completed');
    expect(response.body.meta.total).toBe(1);
  });

  it('excludes tickets somebody else handled', async () => {
    const service = await setupService(app, { counters: 2 });
    const [mine, theirs] = service.staff;
    await serveOne(service, mine, await createUserAndLogin(app));
    await serveOne(service, theirs, await createUserAndLogin(app));

    expect((await handled(mine, 'me')).body.data.tickets).toHaveLength(1);
    expect((await handled(theirs, 'me')).body.data.tickets).toHaveLength(1);
  });

  it('excludes a ticket the customer cancelled before it was ever called', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    const customer = await createUserAndLogin(app);
    const joined = await join(app, service.serviceId, customer);
    await request(app)
      .post(`/api/v1/tickets/${joined.body.data.ticket.id}/cancel`)
      .set('Authorization', bearer(customer.token));

    const response = await handled(staff, 'me');

    expect(response.body.data.tickets).toEqual([]);
  });

  it('filters by status', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    await serveOne(service, staff, await createUserAndLogin(app));
    const skipped = await join(app, service.serviceId, await createUserAndLogin(app));
    await act(app, staff, skipped.body.data.ticket.id, 'skip');

    const all = await handled(staff, 'me');
    const onlySkipped = await handled(staff, 'me', '?status=skipped');

    expect(all.body.data.tickets).toHaveLength(2);
    expect(onlySkipped.body.data.tickets).toHaveLength(1);
    expect(onlySkipped.body.data.tickets[0].status).toBe('skipped');
  });

  it('paginates', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;
    for (let i = 0; i < 3; i += 1) {
      await serveOne(service, staff, await createUserAndLogin(app));
    }

    const response = await handled(staff, 'me', '?page=2&limit=2');

    expect(response.body.data.tickets).toHaveLength(1);
    expect(response.body.meta).toMatchObject({ page: 2, limit: 2, total: 3, totalPages: 2 });
  });
});

// ---------------------------------------------------------------------------
// §74 steps 7–13 — the demonstration, end to end
// ---------------------------------------------------------------------------

describe('§74 walkthrough — a clerk works the queue', () => {
  it('runs sign-in → see queue → call → serve → complete → next', async () => {
    const service = await setupService(app, { code: 'FIN', name: 'Finance Office', counters: 1 });
    const [staff] = service.staff;
    const alice = await createUserAndLogin(app, { firstName: 'Alice', lastName: 'Kamau' });
    const brian = await createUserAndLogin(app, { firstName: 'Brian', lastName: 'Otieno' });

    // 7 — two customers are already waiting.
    await join(app, service.serviceId, alice);
    await join(app, service.serviceId, brian);

    // 8 — the clerk opens the console and sees them both.
    let view = await dashboard(staff);
    expect(view.body.data.stats.waiting).toBe(2);
    expect(view.body.data.currentTicket).toBeNull();
    expect(view.body.data.upNext[0].ticketNumber).toBe('FIN-001');

    // 9 — Call Next takes the lowest waiting sequence.
    const called = await callNext(app, staff, service.serviceId);
    expect(called.status).toBe(200);
    expect(called.body.data.ticket.ticketNumber).toBe('FIN-001');
    expect(called.body.data.ticket.status).toBe('called');
    expect(called.body.data.ticket.counter.counterNumber).toBe(1);
    const aliceTicket = called.body.data.ticket.id;

    // 10 — the console now shows who is at the counter, and one fewer waiting.
    view = await dashboard(staff);
    expect(view.body.data.currentTicket.ticketNumber).toBe('FIN-001');
    expect(view.body.data.currentTicket.customer.fullName).toBe('Alice Kamau');
    expect(view.body.data.stats.waiting).toBe(1);
    expect(view.body.data.counter.status).toBe('busy');

    // 11 — start serving.
    const started = await act(app, staff, aliceTicket, 'start');
    expect(started.body.data.ticket.status).toBe('serving');

    // 12 — complete. The counter is released and the tally moves.
    const completed = await act(app, staff, aliceTicket, 'complete');
    expect(completed.body.data.ticket.status).toBe('completed');
    expect(completed.body.data.queue.completedToday).toBe(1);

    view = await dashboard(staff);
    expect(view.body.data.currentTicket).toBeNull();
    expect(view.body.data.counter.status).toBe('available');
    expect(view.body.data.stats.servedToday).toBe(1);

    // 13 — the next customer is called without any extra setup.
    const next = await callNext(app, staff, service.serviceId);
    expect(next.body.data.ticket.ticketNumber).toBe('FIN-002');
    expect(next.body.data.ticket.customer.fullName).toBe('Brian Otieno');

    // And the statistics screen agrees with the dashboard.
    const stats = await statistics(staff, 'me');
    expect(stats.body.data.ticketsServed).toBe(1);
    expect(stats.body.data.ticketsHandled).toBe(1);
    expect(stats.body.data.completionRate).toBe(100);

    // …as does the history screen.
    const history = await handled(staff, 'me');
    expect(history.body.data.tickets.map((t: { ticketNumber: string }) => t.ticketNumber).sort()).toEqual([
      'FIN-001',
      'FIN-002',
    ]);
  });

  it('empties the queue and says so', async () => {
    const service = await setupService(app);
    const [staff] = service.staff;

    const response = await callNext(app, staff, service.serviceId);

    expect(response.status).toBe(404);
    expect(response.body.code).toBe('NO_WAITING_TICKETS');
  });
});
