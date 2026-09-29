/**
 * Phase 4 verification — the queue engine.
 *
 * Covers §16–§19 (join, ticket numbering, position, estimated wait) and
 * closes with the complete §85 success workflow run end to end against the
 * real database through the real HTTP API.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, callNext, clearQueueData, createUserAndLogin, join, position, setupService } from './helpers/api';
import { getDb } from '../src/db';
import { computeWaitMinutes, effectiveServiceMinutes, MIN_SAMPLE_SIZE } from '../src/services/estimation.service';
import { formatTicketNumber } from '../src/services/queue.service';
import { toSqlDateTime, todayDate } from '../src/utils/datetime';

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
// Ticket numbering (§17)
// ---------------------------------------------------------------------------

describe('ticket numbering', () => {
  it('formats a sequence as CODE-000 with three digits', () => {
    expect(formatTicketNumber('FIN', 1)).toBe('FIN-001');
    expect(formatTicketNumber('FIN', 23)).toBe('FIN-023');
    expect(formatTicketNumber('lib', 7)).toBe('LIB-007');
    expect(formatTicketNumber('REG', 150)).toBe('REG-150');
  });

  it('keeps counting past 999 rather than truncating', () => {
    expect(formatTicketNumber('FIN', 1000)).toBe('FIN-1000');
  });

  it('issues FIN-001 to the first customer of the day', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const response = await join(app, serviceId, customer);

    expect(response.status).toBe(201);
    expect(response.body.data.ticket.ticketNumber).toBe('FIN-001');
    expect(response.body.data.ticket.sequenceNumber).toBe(1);
    expect(response.body.data.ticket.status).toBe('waiting');
  });

  it('increments the number for each customer that follows', async () => {
    const { serviceId } = await setupService(app);
    const numbers: string[] = [];

    for (let i = 0; i < 3; i += 1) {
      const customer = await createUserAndLogin(app);
      const response = await join(app, serviceId, customer);
      numbers.push(response.body.data.ticket.ticketNumber);
    }

    expect(numbers).toEqual(['FIN-001', 'FIN-002', 'FIN-003']);
  });

  it('generates the number on the server and ignores anything the client sends', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const response = await request(app)
      .post(`/api/v1/services/${serviceId}/queue/join`)
      .set('Authorization', `Bearer ${customer.token}`)
      .send({ ticketNumber: 'FIN-999', sequenceNumber: 999, status: 'serving' });

    expect(response.status).toBe(201);
    expect(response.body.data.ticket.ticketNumber).toBe('FIN-001');
    expect(response.body.data.ticket.status).toBe('waiting');
  });

  it('numbers each service independently', async () => {
    const finance = await setupService(app, { code: 'FIN', name: 'Finance' });
    const library = await setupService(app, { code: 'LIB', name: 'Library' });
    const customer = await createUserAndLogin(app);

    const first = await join(app, finance.serviceId, customer);
    const second = await join(app, library.serviceId, customer);

    expect(first.body.data.ticket.ticketNumber).toBe('FIN-001');
    expect(second.body.data.ticket.ticketNumber).toBe('LIB-001');
  });
});

// ---------------------------------------------------------------------------
// Join guards (§59 Rules 1, 2, 3)
// ---------------------------------------------------------------------------

describe('joining a queue', () => {
  it('requires authentication', async () => {
    const { serviceId } = await setupService(app);
    const response = await request(app).post(`/api/v1/services/${serviceId}/queue/join`);
    expect(response.status).toBe(401);
  });

  it('rejects a second active ticket for the same service (Rule 1)', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    await join(app, serviceId, customer);
    const second = await join(app, serviceId, customer);

    expect(second.status).toBe(409);
    expect(second.body.code).toBe('DUPLICATE_ACTIVE_TICKET');
    expect(second.body.message).toContain('FIN-001');
  });

  it('allows one active ticket in each of two different services', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const registry = await setupService(app, { code: 'REG' });
    const customer = await createUserAndLogin(app);

    expect((await join(app, finance.serviceId, customer)).status).toBe(201);
    expect((await join(app, registry.serviceId, customer)).status).toBe(201);
  });

  it('lets a customer rejoin once their previous ticket is finished', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const first = await join(app, serviceId, customer);
    await act(app, customer, first.body.data.ticket.id, 'cancel');

    const second = await join(app, serviceId, customer);
    expect(second.status).toBe(201);
    expect(second.body.data.ticket.ticketNumber).toBe('FIN-002');
    expect(staff).toHaveLength(1);
  });

  it('refuses a second ticket after being served when the service disallows rejoining', async () => {
    const { serviceId, staff } = await setupService(app, { allowRejoin: false });
    const customer = await createUserAndLogin(app);

    const first = await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);
    await act(app, staff[0], first.body.data.ticket.id, 'start');
    await act(app, staff[0], first.body.data.ticket.id, 'complete');

    const second = await join(app, serviceId, customer);
    expect(second.status).toBe(409);
    expect(second.body.code).toBe('REJOIN_NOT_ALLOWED');
  });

  it('still lets a customer rejoin after cancelling, even when rejoining is disallowed', async () => {
    // Cancelling is not "being served", so it must not lock the customer out.
    const { serviceId } = await setupService(app, { allowRejoin: false });
    const customer = await createUserAndLogin(app);

    const first = await join(app, serviceId, customer);
    await act(app, customer, first.body.data.ticket.id, 'cancel');

    const second = await join(app, serviceId, customer);
    expect(second.status).toBe(201);
  });

  it('rejects an inactive service', async () => {
    const { serviceId } = await setupService(app, { status: 'inactive' });
    const customer = await createUserAndLogin(app);

    const response = await join(app, serviceId, customer);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('SERVICE_INACTIVE');
  });

  it('rejects a closed service', async () => {
    const { serviceId } = await setupService(app, { status: 'closed' });
    const customer = await createUserAndLogin(app);

    const response = await join(app, serviceId, customer);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('SERVICE_CLOSED');
  });

  it('rejects a paused queue', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const customer = await createUserAndLogin(app);

    const status = await request(app).get(`/api/v1/services/${serviceId}/queue`);
    await request(app)
      .post(`/api/v1/queues/${status.body.data.queueId}/pause`)
      .set('Authorization', `Bearer ${admin.token}`);

    const response = await join(app, serviceId, customer);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('QUEUE_PAUSED');
  });

  it('rejects a closed queue', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const customer = await createUserAndLogin(app);

    const status = await request(app).get(`/api/v1/services/${serviceId}/queue`);
    await request(app)
      .post(`/api/v1/queues/${status.body.data.queueId}/close`)
      .set('Authorization', `Bearer ${admin.token}`);

    const response = await join(app, serviceId, customer);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('QUEUE_CLOSED');
  });

  it('stops issuing tickets once capacity is reached (Rule 3)', async () => {
    const { serviceId } = await setupService(app, { maxQueueSize: 2 });

    for (let i = 0; i < 2; i += 1) {
      const customer = await createUserAndLogin(app);
      expect((await join(app, serviceId, customer)).status).toBe(201);
    }

    const unlucky = await createUserAndLogin(app);
    const response = await join(app, serviceId, unlucky);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('QUEUE_FULL');
  });

  it('counts cancelled tickets against capacity, so numbers are never reused', async () => {
    const { serviceId } = await setupService(app, { maxQueueSize: 2 });
    const first = await createUserAndLogin(app);
    const second = await createUserAndLogin(app);

    const issued = await join(app, serviceId, first);
    await act(app, first, issued.body.data.ticket.id, 'cancel');

    const next = await join(app, serviceId, second);
    expect(next.body.data.ticket.ticketNumber).toBe('FIN-002');

    const third = await createUserAndLogin(app);
    expect((await join(app, serviceId, third)).status).toBe(409);
  });

  it('rejects a join outside the service opening hours', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    // A window that has certainly already closed today.
    await getDb().execute(
      `INSERT INTO service_hours (service_id, day_of_week, opening_time, closing_time, status)
       VALUES (?, ?, '00:00:00', '00:01:00', 'open')`,
      [serviceId, new Date().getDay()],
    );

    const response = await join(app, serviceId, customer);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('OUTSIDE_SERVICE_HOURS');
  });

  it('rejects a join on a day the service is marked closed', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    await getDb().execute(
      `INSERT INTO service_hours (service_id, day_of_week, opening_time, closing_time, status)
       VALUES (?, ?, '08:00:00', '17:00:00', 'closed')`,
      [serviceId, new Date().getDay()],
    );

    const response = await join(app, serviceId, customer);
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('OUTSIDE_SERVICE_HOURS');
  });

  it('returns 404 for a service that does not exist', async () => {
    const customer = await createUserAndLogin(app);
    const response = await join(app, 999_999, customer);
    expect(response.status).toBe(404);
  });

  it('can also be addressed by queue id, as docs/api.md §5 specifies', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const queue = await request(app).get(`/api/v1/services/${serviceId}/queue`);

    const response = await request(app)
      .post(`/api/v1/queues/${queue.body.data.queueId}/join`)
      .set('Authorization', `Bearer ${customer.token}`);

    expect(response.status).toBe(201);
    expect(response.body.data.ticket.ticketNumber).toBe('FIN-001');
  });

  it('returns 404 when joining a queue id that does not exist', async () => {
    const customer = await createUserAndLogin(app);
    const response = await request(app)
      .post('/api/v1/queues/999999/join')
      .set('Authorization', `Bearer ${customer.token}`);
    expect(response.status).toBe(404);
  });

  it('writes an audit event and a notification in the same transaction (Rule 14)', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const response = await join(app, serviceId, customer);
    const ticketId = response.body.data.ticket.id;

    const events = await getDb().query<{ event_type: string; user_id: number }>(
      'SELECT event_type, user_id FROM queue_events WHERE ticket_id = ?',
      [ticketId],
    );
    const notifications = await getDb().query<{ title: string; user_id: number }>(
      'SELECT title, user_id FROM notifications WHERE ticket_id = ?',
      [ticketId],
    );

    expect(events).toHaveLength(1);
    expect(events[0].event_type).toBe('joined');
    expect(Number(events[0].user_id)).toBe(customer.id);
    expect(notifications).toHaveLength(1);
    expect(notifications[0].title).toContain('FIN-001');
  });

  it('creates exactly one queue row per service per day (Rule 12)', async () => {
    const { serviceId } = await setupService(app);

    for (let i = 0; i < 3; i += 1) {
      const customer = await createUserAndLogin(app);
      await join(app, serviceId, customer);
    }

    const queues = await getDb().query<{ n: number }>(
      'SELECT COUNT(*) AS n FROM queues WHERE service_id = ? AND queue_date = ?',
      [serviceId, todayDate()],
    );
    expect(Number(queues[0].n)).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Estimated wait (§19)
// ---------------------------------------------------------------------------

describe('estimated wait time', () => {
  it('is zero when nobody is ahead', () => {
    expect(computeWaitMinutes(0, 5, 2)).toBe(0);
    expect(computeWaitMinutes(-1, 5, 2)).toBe(0);
  });

  it('multiplies people ahead by the service time', () => {
    expect(computeWaitMinutes(4, 5, 1)).toBe(20);
    expect(computeWaitMinutes(10, 3, 1)).toBe(30);
  });

  it('divides by the number of active counters', () => {
    expect(computeWaitMinutes(10, 5, 2)).toBe(25);
    expect(computeWaitMinutes(10, 5, 5)).toBe(10);
  });

  it('rounds up, because a partial minute is still a minute of waiting', () => {
    expect(computeWaitMinutes(5, 5, 2)).toBe(13); // 12.5 → 13
  });

  it('never divides by zero when every counter is offline', () => {
    expect(computeWaitMinutes(4, 5, 0)).toBe(20);
  });

  it('uses the configured service time until there is enough evidence', async () => {
    const { serviceId } = await setupService(app, { averageServiceTime: 8 });
    const result = await effectiveServiceMinutes({ serviceId, configuredMinutes: 8 });

    expect(result.sampleSize).toBeLessThan(MIN_SAMPLE_SIZE);
    expect(result.effectiveMinutes).toBe(8);
  });

  it('blends measured and configured times once enough services are complete', async () => {
    const { serviceId, counterIds } = await setupService(app, { averageServiceTime: 10 });
    const db = getDb();
    const stamp = toSqlDateTime();

    const queue = await db.execute(
      `INSERT INTO queues (service_id, queue_date, status, current_number, last_issued_number, total_served, created_at, updated_at)
       VALUES (?, ?, 'waiting', 0, 0, 0, ?, ?)`,
      [serviceId, todayDate(), stamp, stamp],
    );

    // Six completed tickets that each took exactly 20 minutes.
    for (let i = 1; i <= 6; i += 1) {
      const customer = await createUserAndLogin(app);
      const started = new Date(Date.now() - 60 * 60 * 1000);
      const finished = new Date(started.getTime() + 20 * 60 * 1000);
      await db.execute(
        `INSERT INTO queue_tickets
           (queue_id, service_id, user_id, ticket_number, sequence_number, status, counter_id,
            estimated_wait_minutes, joined_at, called_at, service_started_at, completed_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'completed', ?, 10, ?, ?, ?, ?, ?, ?)`,
        [
          queue.insertId,
          serviceId,
          customer.id,
          formatTicketNumber('FIN', i),
          i,
          counterIds[0],
          toSqlDateTime(started),
          toSqlDateTime(started),
          toSqlDateTime(started),
          toSqlDateTime(finished),
          stamp,
          stamp,
        ],
      );
    }

    const result = await effectiveServiceMinutes({ serviceId, configuredMinutes: 10 });

    expect(result.sampleSize).toBe(6);
    expect(result.measuredMinutes).toBeCloseTo(20, 0);
    // 0.7 × 20 + 0.3 × 10 = 17
    expect(result.effectiveMinutes).toBe(17);
  });

  it('grows the estimate as the line gets longer', async () => {
    const { serviceId } = await setupService(app, { averageServiceTime: 6, counters: 1 });

    const first = await join(app, serviceId, await createUserAndLogin(app));
    const second = await join(app, serviceId, await createUserAndLogin(app));
    const third = await join(app, serviceId, await createUserAndLogin(app));

    expect(first.body.data.ticket.estimatedWaitMinutes).toBe(0);
    expect(second.body.data.ticket.estimatedWaitMinutes).toBe(6);
    expect(third.body.data.ticket.estimatedWaitMinutes).toBe(12);
  });

  it('halves the estimate when a second counter is open', async () => {
    const oneCounter = await setupService(app, { code: 'ONE', averageServiceTime: 10, counters: 1 });
    const twoCounters = await setupService(app, { code: 'TWO', averageServiceTime: 10, counters: 2 });

    for (let i = 0; i < 4; i += 1) {
      await join(app, oneCounter.serviceId, await createUserAndLogin(app));
      await join(app, twoCounters.serviceId, await createUserAndLogin(app));
    }

    const single = await join(app, oneCounter.serviceId, await createUserAndLogin(app));
    const double = await join(app, twoCounters.serviceId, await createUserAndLogin(app));

    expect(single.body.data.ticket.estimatedWaitMinutes).toBe(40); // 4 × 10 ÷ 1
    expect(double.body.data.ticket.estimatedWaitMinutes).toBe(20); // 4 × 10 ÷ 2
  });
});

// ---------------------------------------------------------------------------
// Position tracking (§18)
// ---------------------------------------------------------------------------

describe('position tracking', () => {
  it('reports position 1 and nobody ahead for the first customer', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const response = await join(app, serviceId, customer);

    expect(response.body.data.position.position).toBe(1);
    expect(response.body.data.position.peopleAhead).toBe(0);
  });

  it('places the third customer behind two others', async () => {
    const { serviceId } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    await join(app, serviceId, await createUserAndLogin(app));

    const third = await createUserAndLogin(app);
    const response = await join(app, serviceId, third);

    expect(response.body.data.position.position).toBe(3);
    expect(response.body.data.position.peopleAhead).toBe(2);
  });

  it('moves everyone up when the customer ahead is served', async () => {
    const { serviceId, staff } = await setupService(app);
    const first = await createUserAndLogin(app);
    const second = await createUserAndLogin(app);

    await join(app, serviceId, first);
    const secondTicket = await join(app, serviceId, second);
    expect(secondTicket.body.data.position.position).toBe(2);

    const called = await callNext(app, staff[0], serviceId);
    await act(app, staff[0], called.body.data.ticket.id, 'start');
    await act(app, staff[0], called.body.data.ticket.id, 'complete');

    const updated = await position(app, second, secondTicket.body.data.ticket.id);
    expect(updated.body.data.position).toBe(1);
    expect(updated.body.data.peopleAhead).toBe(0);
  });

  it('drops the position once the ticket itself is called', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);

    await callNext(app, staff[0], serviceId);

    const updated = await position(app, customer, ticket.body.data.ticket.id);
    expect(updated.body.data.status).toBe('called');
    expect(updated.body.data.position).toBeNull();
    expect(updated.body.data.counter.counterNumber).toBe(1);
  });

  it('reports who is now being served', async () => {
    const { serviceId, staff } = await setupService(app);
    const first = await createUserAndLogin(app);
    const second = await createUserAndLogin(app);
    await join(app, serviceId, first);
    const secondTicket = await join(app, serviceId, second);

    await callNext(app, staff[0], serviceId);

    const view = await position(app, second, secondTicket.body.data.ticket.id);
    expect(view.body.data.nowServing).toBe('FIN-001');
  });

  it('sends the "your turn is approaching" alert once and only once', async () => {
    const { serviceId } = await setupService(app, { notificationThreshold: 3 });
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, await createUserAndLogin(app));
    const ticket = await join(app, serviceId, customer);

    // Poll three times; the customer is 1 away, inside the threshold.
    await position(app, customer, ticket.body.data.ticket.id);
    await position(app, customer, ticket.body.data.ticket.id);
    await position(app, customer, ticket.body.data.ticket.id);

    const alerts = await getDb().query<{ n: number }>(
      "SELECT COUNT(*) AS n FROM notifications WHERE ticket_id = ? AND title = 'Your turn is approaching'",
      [ticket.body.data.ticket.id],
    );
    expect(Number(alerts[0].n)).toBe(1);
  });

  it('stays quiet while the customer is still far from the front', async () => {
    const { serviceId } = await setupService(app, { notificationThreshold: 1 });
    for (let i = 0; i < 4; i += 1) await join(app, serviceId, await createUserAndLogin(app));

    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await position(app, customer, ticket.body.data.ticket.id);

    const alerts = await getDb().query<{ n: number }>(
      "SELECT COUNT(*) AS n FROM notifications WHERE ticket_id = ? AND title = 'Your turn is approaching'",
      [ticket.body.data.ticket.id],
    );
    expect(Number(alerts[0].n)).toBe(0);
  });

  it('refuses to show one customer another customer\'s position', async () => {
    const { serviceId } = await setupService(app);
    const owner = await createUserAndLogin(app);
    const nosy = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, owner);

    const response = await position(app, nosy, ticket.body.data.ticket.id);
    expect(response.status).toBe(403);
  });
});

// ---------------------------------------------------------------------------
// §85 — the success workflow, start to finish
// ---------------------------------------------------------------------------

describe('§85 end-to-end success workflow', () => {
  it('runs join → call → serve → complete against the real database', async () => {
    const { serviceId, counterIds, staff } = await setupService(app, { averageServiceTime: 5, counters: 1 });
    const db = getDb();

    // 1. A customer registers and signs in.
    const registration = await request(app).post('/api/v1/auth/register').send({
      firstName: 'Amina',
      lastName: 'Wanjiru',
      email: 'amina.wanjiru@test.local',
      phone: '+254733111222',
      password: 'Password123',
      confirmPassword: 'Password123',
    });
    expect(registration.status).toBe(201);
    const customer = { id: registration.body.data.user.id, email: '', token: registration.body.data.token };

    // 2. They browse the service list and see live queue figures.
    const services = await request(app).get('/api/v1/services');
    expect(services.status).toBe(200);
    const listed = services.body.data.find((s: { id: number }) => s.id === serviceId);
    expect(listed.queue.waitingCount).toBe(0);
    expect(listed.queue.isAcceptingTickets).toBe(true);

    // 3. They join the queue and receive a ticket.
    const joined = await join(app, serviceId, customer);
    expect(joined.status).toBe(201);
    const ticket = joined.body.data.ticket;
    expect(ticket.ticketNumber).toBe('FIN-001');
    expect(ticket.status).toBe('waiting');
    expect(joined.body.data.position.position).toBe(1);

    // 4. The ticket is really in the database.
    const stored = await db.query<{ status: string; user_id: number; ticket_number: string }>(
      'SELECT status, user_id, ticket_number FROM queue_tickets WHERE id = ?',
      [ticket.id],
    );
    expect(stored[0].ticket_number).toBe('FIN-001');
    expect(Number(stored[0].user_id)).toBe(customer.id);

    // 5. Staff call the next customer.
    const called = await callNext(app, staff[0], serviceId);
    expect(called.status).toBe(200);
    expect(called.body.data.ticket.id).toBe(ticket.id);
    expect(called.body.data.ticket.status).toBe('called');
    expect(called.body.data.ticket.counter.counterNumber).toBe(1);

    const counterAfterCall = await db.query<{ status: string }>('SELECT status FROM service_counters WHERE id = ?', [
      counterIds[0],
    ]);
    expect(counterAfterCall[0].status).toBe('busy');

    // 6. The customer is notified.
    const callNotice = await db.query<{ title: string }>(
      "SELECT title FROM notifications WHERE ticket_id = ? AND title LIKE '%being called%'",
      [ticket.id],
    );
    expect(callNotice).toHaveLength(1);

    // 7. Service starts, then completes.
    const started = await act(app, staff[0], ticket.id, 'start');
    expect(started.body.data.ticket.status).toBe('serving');

    const completed = await act(app, staff[0], ticket.id, 'complete');
    expect(completed.body.data.ticket.status).toBe('completed');
    expect(completed.body.data.ticket.completedAt).not.toBeNull();

    // 8. The counter is free again and the queue tally has moved.
    const counterAfterComplete = await db.query<{ status: string }>(
      'SELECT status FROM service_counters WHERE id = ?',
      [counterIds[0]],
    );
    expect(counterAfterComplete[0].status).toBe('available');

    const queueRow = await db.query<{ total_served: number; current_number: number; last_issued_number: number }>(
      'SELECT total_served, current_number, last_issued_number FROM queues WHERE service_id = ? AND queue_date = ?',
      [serviceId, todayDate()],
    );
    expect(Number(queueRow[0].total_served)).toBe(1);
    expect(Number(queueRow[0].current_number)).toBe(1);
    expect(Number(queueRow[0].last_issued_number)).toBe(1);

    // 9. The audit trail records every step in order.
    const history = await request(app)
      .get(`/api/v1/tickets/${ticket.id}/events`)
      .set('Authorization', `Bearer ${customer.token}`);
    expect(history.body.data.map((e: { eventType: string }) => e.eventType)).toEqual([
      'joined',
      'called',
      'service_started',
      'completed',
    ]);

    // 10. The customer's own history shows the finished ticket.
    const myTickets = await request(app)
      .get('/api/v1/tickets')
      .set('Authorization', `Bearer ${customer.token}`);
    expect(myTickets.body.data).toHaveLength(1);
    expect(myTickets.body.data[0].status).toBe('completed');

    const active = await request(app)
      .get('/api/v1/tickets/active')
      .set('Authorization', `Bearer ${customer.token}`);
    expect(active.body.data).toHaveLength(0);
  });
});
