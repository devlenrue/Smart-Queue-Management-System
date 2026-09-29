/**
 * Phase 4 verification — the ticket state machine and who may drive it.
 *
 * Covers §20–§27 and §59 Rules 4, 5, 6, 7, 8, 9, 10, 11.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, join, setupService } from './helpers/api';
import { getDb } from '../src/db';
import { canTransition } from '../src/services/ticket.service';
import type { TicketStatus } from '../src/types/domain';

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

// ---------------------------------------------------------------------------
// The transition table itself
// ---------------------------------------------------------------------------

describe('transition table', () => {
  const legal: Array<[TicketStatus, TicketStatus]> = [
    ['waiting', 'called'],
    ['waiting', 'cancelled'],
    ['waiting', 'skipped'],
    ['called', 'serving'],
    ['called', 'skipped'],
    ['called', 'no_show'],
    ['serving', 'completed'],
  ];

  const illegal: Array<[TicketStatus, TicketStatus]> = [
    ['waiting', 'serving'],
    ['waiting', 'completed'],
    ['waiting', 'no_show'],
    ['called', 'completed'],
    ['called', 'cancelled'],
    ['serving', 'cancelled'],
    ['serving', 'called'],
    ['serving', 'skipped'],
    ['completed', 'serving'],
    ['completed', 'completed'],
    ['cancelled', 'waiting'],
    ['cancelled', 'called'],
    ['skipped', 'called'],
    ['no_show', 'called'],
  ];

  it.each(legal)('allows %s → %s', (from, to) => {
    expect(canTransition(from, to)).toBe(true);
  });

  it.each(illegal)('rejects %s → %s', (from, to) => {
    expect(canTransition(from, to)).toBe(false);
  });

  it('treats every terminal status as final', () => {
    const terminals: TicketStatus[] = ['completed', 'cancelled', 'skipped', 'no_show'];
    const all: TicketStatus[] = ['waiting', 'called', 'serving', 'completed', 'cancelled', 'skipped', 'no_show'];
    for (const from of terminals) {
      for (const to of all) {
        expect(canTransition(from, to)).toBe(false);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Customer cancellation (§27)
// ---------------------------------------------------------------------------

describe('cancellation', () => {
  it('lets the owner cancel while still waiting', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);

    const response = await act(app, customer, ticket.body.data.ticket.id, 'cancel');

    expect(response.status).toBe(200);
    expect(response.body.data.ticket.status).toBe('cancelled');
    expect(response.body.data.ticket.cancelledAt).not.toBeNull();
  });

  it('refuses to cancel once the ticket has been called', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);

    const response = await act(app, customer, ticket.body.data.ticket.id, 'cancel');

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('INVALID_STATE_TRANSITION');
  });

  it('refuses to cancel somebody else\'s ticket', async () => {
    const { serviceId } = await setupService(app);
    const owner = await createUserAndLogin(app);
    const stranger = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, owner);

    const response = await act(app, stranger, ticket.body.data.ticket.id, 'cancel');
    expect(response.status).toBe(403);
  });

  it('refuses to cancel when the service forbids cancellation', async () => {
    const { serviceId } = await setupService(app, { allowCancellation: false });
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);

    const response = await act(app, customer, ticket.body.data.ticket.id, 'cancel');
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('CANCELLATION_NOT_ALLOWED');
  });

  it('cannot be cancelled twice', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);

    await act(app, customer, ticket.body.data.ticket.id, 'cancel');
    const second = await act(app, customer, ticket.body.data.ticket.id, 'cancel');

    expect(second.status).toBe(409);
  });

  it('lets an admin cancel on a customer\'s behalf', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const ticket = await join(app, serviceId, customer);

    const response = await act(app, admin, ticket.body.data.ticket.id, 'cancel');
    expect(response.status).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// Calling (§21, §26)
// ---------------------------------------------------------------------------

describe('calling customers', () => {
  it('calls the lowest waiting number first', async () => {
    const { serviceId, staff } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    await join(app, serviceId, await createUserAndLogin(app));

    const called = await callNext(app, staff[0], serviceId);
    expect(called.body.data.ticket.ticketNumber).toBe('FIN-001');
  });

  it('skips over a cancelled ticket when choosing the next (Rule 11)', async () => {
    const { serviceId, staff } = await setupService(app);
    const first = await createUserAndLogin(app);
    const firstTicket = await join(app, serviceId, first);
    await join(app, serviceId, await createUserAndLogin(app));
    await act(app, first, firstTicket.body.data.ticket.id, 'cancel');

    const called = await callNext(app, staff[0], serviceId);
    expect(called.body.data.ticket.ticketNumber).toBe('FIN-002');
  });

  it('returns a clear 404 when nobody is waiting', async () => {
    const { serviceId, staff } = await setupService(app);
    const response = await callNext(app, staff[0], serviceId);

    expect(response.status).toBe(404);
    expect(response.body.code).toBe('NO_WAITING_TICKETS');
  });

  it('refuses a second call at a counter that is already busy (Rule 5)', async () => {
    const { serviceId, staff } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    await join(app, serviceId, await createUserAndLogin(app));

    await callNext(app, staff[0], serviceId);
    const second = await callNext(app, staff[0], serviceId);

    expect(second.status).toBe(409);
    expect(second.body.code).toBe('COUNTER_BUSY');
  });

  it('frees the counter again once the service is complete', async () => {
    const { serviceId, staff } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    await join(app, serviceId, await createUserAndLogin(app));

    const first = await callNext(app, staff[0], serviceId);
    await act(app, staff[0], first.body.data.ticket.id, 'start');
    await act(app, staff[0], first.body.data.ticket.id, 'complete');

    const second = await callNext(app, staff[0], serviceId);
    expect(second.status).toBe(200);
    expect(second.body.data.ticket.ticketNumber).toBe('FIN-002');
  });

  it('can call one specific ticket out of order', async () => {
    const { serviceId, staff } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    const second = await join(app, serviceId, await createUserAndLogin(app));

    const response = await act(app, staff[0], second.body.data.ticket.id, 'call');
    expect(response.status).toBe(200);
    expect(response.body.data.ticket.ticketNumber).toBe('FIN-002');
  });

  it('recalls without changing the status, and records the event', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'recall');

    expect(response.status).toBe(200);
    expect(response.body.data.ticket.status).toBe('called');

    const events = await getDb().query<{ n: number }>(
      "SELECT COUNT(*) AS n FROM queue_events WHERE ticket_id = ? AND event_type = 'recalled'",
      [ticket.body.data.ticket.id],
    );
    expect(Number(events[0].n)).toBe(1);
  });

  it('refuses to recall a ticket that was never called', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'recall');
    expect(response.status).toBe(409);
  });

  it('refuses to call from an offline counter', async () => {
    const { serviceId, staff, counterIds } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    await getDb().execute("UPDATE service_counters SET status = 'offline' WHERE id = ?", [counterIds[0]]);

    const response = await callNext(app, staff[0], serviceId);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('COUNTER_OFFLINE');
  });

  it('refuses a counter that belongs to another service', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const library = await setupService(app, { code: 'LIB' });
    await join(app, finance.serviceId, await createUserAndLogin(app));

    const admin = await createUserAndLogin(app, { role: 'admin' });
    const response = await callNext(app, admin, finance.serviceId, library.counterIds[0]);
    expect(response.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// Serving, completing, skipping, no-show (§22–§25)
// ---------------------------------------------------------------------------

describe('serving and finishing', () => {
  it('requires a call before the service can start', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'start');
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('INVALID_STATE_TRANSITION');
  });

  it('requires the service to have started before it can be completed', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));
    await callNext(app, staff[0], serviceId);

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'complete');
    expect(response.status).toBe(409);
  });

  it('records the timestamps of each step', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));
    await callNext(app, staff[0], serviceId);
    await act(app, staff[0], ticket.body.data.ticket.id, 'start');
    const done = await act(app, staff[0], ticket.body.data.ticket.id, 'complete');

    expect(done.body.data.ticket.joinedAt).not.toBeNull();
    expect(done.body.data.ticket.calledAt).not.toBeNull();
    expect(done.body.data.ticket.serviceStartedAt).not.toBeNull();
    expect(done.body.data.ticket.completedAt).not.toBeNull();
  });

  it('cannot complete the same ticket twice', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));
    await callNext(app, staff[0], serviceId);
    await act(app, staff[0], ticket.body.data.ticket.id, 'start');
    await act(app, staff[0], ticket.body.data.ticket.id, 'complete');

    const again = await act(app, staff[0], ticket.body.data.ticket.id, 'complete');
    expect(again.status).toBe(409);
  });

  it('increments total_served exactly once per completion', async () => {
    const { serviceId, staff } = await setupService(app);
    for (let i = 0; i < 2; i += 1) {
      await join(app, serviceId, await createUserAndLogin(app));
      const called = await callNext(app, staff[0], serviceId);
      await act(app, staff[0], called.body.data.ticket.id, 'start');
      await act(app, staff[0], called.body.data.ticket.id, 'complete');
    }

    const rows = await getDb().query<{ total_served: number }>(
      'SELECT total_served FROM queues WHERE service_id = ?',
      [serviceId],
    );
    expect(Number(rows[0].total_served)).toBe(2);
  });

  it('skips a waiting ticket and notifies the customer', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'skip', { reason: 'Documents missing' });

    expect(response.status).toBe(200);
    expect(response.body.data.ticket.status).toBe('skipped');

    const events = await getDb().query<{ description: string }>(
      "SELECT description FROM queue_events WHERE ticket_id = ? AND event_type = 'skipped'",
      [ticket.body.data.ticket.id],
    );
    expect(events[0].description).toBe('Documents missing');
  });

  it('marks a called ticket as a no-show and frees the counter', async () => {
    const { serviceId, staff, counterIds } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));
    await callNext(app, staff[0], serviceId);

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'no-show');

    expect(response.status).toBe(200);
    expect(response.body.data.ticket.status).toBe('no_show');

    const counter = await getDb().query<{ status: string }>('SELECT status FROM service_counters WHERE id = ?', [
      counterIds[0],
    ]);
    expect(counter[0].status).toBe('available');
  });

  it('refuses a no-show for a ticket that is only waiting', async () => {
    const { serviceId, staff } = await setupService(app);
    const ticket = await join(app, serviceId, await createUserAndLogin(app));

    const response = await act(app, staff[0], ticket.body.data.ticket.id, 'no-show');
    expect(response.status).toBe(409);
  });

  it('lets the customer take a new ticket after a no-show', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);
    await act(app, staff[0], ticket.body.data.ticket.id, 'no-show');

    const again = await join(app, serviceId, customer);
    expect(again.status).toBe(201);
    expect(again.body.data.ticket.ticketNumber).toBe('FIN-002');
  });
});

// ---------------------------------------------------------------------------
// Authorisation on transitions (Rule 4)
// ---------------------------------------------------------------------------

describe('who may drive the state machine', () => {
  it('blocks a customer from calling the next ticket', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);

    const response = await callNext(app, customer, serviceId);
    expect(response.status).toBe(403);
  });

  it('blocks a customer from completing their own ticket', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);
    await act(app, staff[0], ticket.body.data.ticket.id, 'start');

    const response = await act(app, customer, ticket.body.data.ticket.id, 'complete');
    expect(response.status).toBe(403);
  });

  it('blocks staff who are not assigned to the service (Rule 4)', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const library = await setupService(app, { code: 'LIB' });
    await join(app, finance.serviceId, await createUserAndLogin(app));

    // Library staff, trying to work the Finance queue.
    const response = await callNext(app, library.staff[0], finance.serviceId, finance.counterIds[0]);

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('NOT_ASSIGNED_TO_SERVICE');
  });

  it('lets an admin act on any service without an assignment', async () => {
    const { serviceId, counterIds } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    await join(app, serviceId, await createUserAndLogin(app));

    const response = await callNext(app, admin, serviceId, counterIds[0]);
    expect(response.status).toBe(200);
  });

  it('tells staff with no counter what to do about it', async () => {
    const { serviceId } = await setupService(app);
    const orphan = await createUserAndLogin(app, { role: 'staff' });
    const admin = await createUserAndLogin(app, { role: 'admin' });
    await join(app, serviceId, await createUserAndLogin(app));

    // Assigned to the service, but not sitting at a counter.
    await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(admin.token))
      .send({ name: 'Unused', code: 'UNU', averageServiceTime: 5, dailyCapacity: 10 });
    await getDb().execute(
      `INSERT INTO staff_assignments (staff_id, service_id, counter_id, assigned_at, status, created_at, updated_at)
       VALUES (?, ?, NULL, datetime('now'), 'active', datetime('now'), datetime('now'))`,
      [orphan.id, serviceId],
    );

    const response = await callNext(app, orphan, serviceId);
    expect(response.status).toBe(400);
    expect(response.body.message).toContain('not assigned to a counter');
  });

  it('returns 404 for a ticket that does not exist', async () => {
    const { staff } = await setupService(app);
    const response = await act(app, staff[0], 999_999, 'start');
    expect(response.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Route names promised by docs/api.md
// ---------------------------------------------------------------------------

describe('the documented route names all resolve', () => {
  it('serves GET /tickets/my as well as GET /tickets', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);

    const viaMy = await request(app).get('/api/v1/tickets/my').set('Authorization', bearer(customer.token));
    const viaRoot = await request(app).get('/api/v1/tickets').set('Authorization', bearer(customer.token));

    expect(viaMy.status).toBe(200);
    expect(viaMy.body.data).toHaveLength(1);
    expect(viaMy.body.data).toEqual(viaRoot.body.data);
  });

  it('filters GET /tickets/my?status=active', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await act(app, customer, ticket.body.data.ticket.id, 'cancel');

    const active = await request(app)
      .get('/api/v1/tickets/my?status=active')
      .set('Authorization', bearer(customer.token));
    const all = await request(app).get('/api/v1/tickets/my').set('Authorization', bearer(customer.token));

    expect(active.body.data).toHaveLength(0);
    expect(all.body.data).toHaveLength(1);
  });

  it('serves POST /tickets/next as well as POST /tickets/call-next', async () => {
    const { serviceId, staff } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));

    const response = await request(app)
      .post('/api/v1/tickets/next')
      .set('Authorization', bearer(staff[0].token))
      .send({ serviceId });

    expect(response.status).toBe(200);
    expect(response.body.data.ticket.ticketNumber).toBe('FIN-001');
  });

  it('serves GET /queues/:id/status', async () => {
    const { serviceId } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    const queue = await request(app).get(`/api/v1/services/${serviceId}/queue`);

    const response = await request(app).get(`/api/v1/queues/${queue.body.data.queueId}/status`);

    expect(response.status).toBe(200);
    expect(response.body.data.waitingCount).toBe(1);
  });

  it('accepts PATCH as well as POST for pause, resume and close', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const queue = await request(app).get(`/api/v1/services/${serviceId}/queue`);
    const id = queue.body.data.queueId;

    const paused = await request(app).patch(`/api/v1/queues/${id}/pause`).set('Authorization', bearer(admin.token));
    expect(paused.body.data.status).toBe('paused');

    const resumed = await request(app).patch(`/api/v1/queues/${id}/resume`).set('Authorization', bearer(admin.token));
    expect(resumed.body.data.status).toBe('waiting');

    const closed = await request(app).patch(`/api/v1/queues/${id}/close`).set('Authorization', bearer(admin.token));
    expect(closed.body.data.status).toBe('closed');
  });

  it('refuses queue control to a customer', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const queue = await request(app).get(`/api/v1/services/${serviceId}/queue`);

    const response = await request(app)
      .post(`/api/v1/queues/${queue.body.data.queueId}/pause`)
      .set('Authorization', bearer(customer.token));

    expect(response.status).toBe(403);
  });
});
