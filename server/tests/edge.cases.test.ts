/**
 * Phase 9 — the branches nobody walks on a happy path.
 *
 * The feature suites prove the system does what it is for. This one goes after
 * what is left: optional filters, defaulted arguments, "the row is missing"
 * guards, and the clean-up paths that only run when something is taken away.
 * It exists because `--coverage` said these lines had never executed, and an
 * unexecuted line is an unproven claim.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { getDb } from '../src/db';
import { announcementAdminService } from '../src/services/announcement.service';
import { adminService } from '../src/services/admin.service';
import { userService } from '../src/services/user.service';
import { todayDate, addDays } from '../src/utils/datetime';
import type { AuthUser } from '../src/types/domain';
import { closeDatabase, freshDatabase, insertQueue } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, join, setupService } from './helpers/api';

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

const get = (token: string, path: string) => request(app).get(`/api/v1${path}`).set('Authorization', bearer(token));

// ---------------------------------------------------------------------------
// Announcements — the editing paths (Phase 7 tested creating and reading)
// ---------------------------------------------------------------------------

describe('announcements: editing an existing notice', () => {
  const draft = { title: 'System maintenance', content: 'The portal is down on Saturday morning.' };

  it('publishing a draft through an edit fans it out to every active customer', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const shopper = await createUserAndLogin(app);
    const { serviceId } = await setupService(app);

    const created = await request(app)
      .post('/api/v1/announcements')
      .set('Authorization', bearer(boss.token))
      .send(draft)
      .expect(201);
    const id = created.body.data.id;

    // Nothing is sent while it is a draft.
    expect((await get(shopper.token, '/notifications')).body.data.notifications).toHaveLength(0);

    const updated = await request(app)
      .put(`/api/v1/announcements/${id}`)
      .set('Authorization', bearer(boss.token))
      .send({
        title: 'System maintenance (revised)',
        serviceId,
        expiresAt: '2030-01-01T09:00:00.000Z',
        status: 'published',
      })
      .expect(200);

    expect(updated.body.data.status).toBe('published');
    expect(updated.body.data.publishedAt).not.toBeNull();
    expect(updated.body.data.serviceId).toBe(serviceId);
    expect(updated.body.data.expiresAt).not.toBeNull();

    const inbox = (await get(shopper.token, '/notifications')).body.data.notifications;
    expect(inbox).toHaveLength(1);
    expect(inbox[0].title).toBe('System maintenance (revised)');
    expect(inbox[0].type).toBe('announcement');
  });

  it('publishing twice does not fan out twice', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const shopper = await createUserAndLogin(app);

    const created = await request(app)
      .post('/api/v1/announcements')
      .set('Authorization', bearer(boss.token))
      .send({ ...draft, status: 'published' })
      .expect(201);

    await request(app)
      .put(`/api/v1/announcements/${created.body.data.id}`)
      .set('Authorization', bearer(boss.token))
      .send({ status: 'published', content: 'Now with more detail.' })
      .expect(200);

    expect((await get(shopper.token, '/notifications')).body.data.notifications).toHaveLength(1);
  });

  it('clears an expiry and a service when they are sent as null', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const { serviceId } = await setupService(app);

    const created = await request(app)
      .post('/api/v1/announcements')
      .set('Authorization', bearer(boss.token))
      .send({ ...draft, serviceId, expiresAt: '2030-01-01T09:00:00.000Z' })
      .expect(201);

    const cleared = await request(app)
      .put(`/api/v1/announcements/${created.body.data.id}`)
      .set('Authorization', bearer(boss.token))
      .send({ serviceId: null, expiresAt: null })
      .expect(200);

    expect(cleared.body.data.serviceId).toBeNull();
    expect(cleared.body.data.expiresAt).toBeNull();
  });

  it('refuses to attach a notice to a service that does not exist', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const created = await request(app)
      .post('/api/v1/announcements')
      .set('Authorization', bearer(boss.token))
      .send(draft)
      .expect(201);

    const response = await request(app)
      .put(`/api/v1/announcements/${created.body.data.id}`)
      .set('Authorization', bearer(boss.token))
      .send({ serviceId: 999999 });

    expect(response.status).toBe(404);
    expect(response.body.code).toBe('NOT_FOUND');
  });

  it('rejects an unparseable timestamp even if it reaches the service directly', async () => {
    // The validator normally catches this; the service does not trust that.
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const created = await request(app)
      .post('/api/v1/announcements')
      .set('Authorization', bearer(boss.token))
      .send(draft)
      .expect(201);

    await expect(
      announcementAdminService.update(created.body.data.id, { expiresAt: 'the day after tomorrow' }),
    ).rejects.toMatchObject({ statusCode: 422, code: 'VALIDATION_ERROR' });
  });
});

// ---------------------------------------------------------------------------
// Roster — the clean-up paths
// ---------------------------------------------------------------------------

describe('roster: taking things away', () => {
  it('deactivating a clerk frees the desk they were standing at', async () => {
    const { serviceId, counterIds, staff } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/staff/${staff[0].id}/`.replace(/\/$/, ''))
      .set('Authorization', bearer(boss.token))
      .send({ status: 'inactive' })
      .expect(200);

    expect(response.body.data.status).toBe('inactive');
    expect(response.body.data.posting).toBeNull();

    const [counter] = await getDb().query<{ assigned_staff_id: number | null; status: string }>(
      'SELECT assigned_staff_id, status FROM service_counters WHERE id = ?',
      [counterIds[0]],
    );
    expect(counter.assigned_staff_id).toBeNull();
    expect(serviceId).toBeGreaterThan(0);
  });

  it('will not deactivate a clerk who still has a customer at the desk', async () => {
    const { serviceId, counterIds, staff } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    await join(app, serviceId, await createUserAndLogin(app));
    await callNext(app, staff[0], serviceId, counterIds[0]);

    const response = await request(app)
      .put(`/api/v1/staff/${staff[0].id}`)
      .set('Authorization', bearer(boss.token))
      .send({ status: 'inactive' });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('COUNTER_BUSY');
  });

  it('renaming a clerk onto an existing phone number is refused', async () => {
    const { staff } = await setupService(app, { counters: 2 });
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const [{ phone }] = await getDb().query<{ phone: string }>('SELECT phone FROM users WHERE id = ?', [staff[1].id]);

    const response = await request(app)
      .put(`/api/v1/staff/${staff[0].id}`)
      .set('Authorization', bearer(boss.token))
      .send({ phone });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('PHONE_TAKEN');
  });

  it('a name change alone leaves the status and the desk exactly as they were', async () => {
    const { counterIds, staff } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/staff/${staff[0].id}`)
      .set('Authorization', bearer(boss.token))
      .send({ firstName: 'Renamed' })
      .expect(200);

    expect(response.body.data.firstName).toBe('Renamed');
    expect(response.body.data.status).toBe('active');
    expect(response.body.data.posting.counterId).toBe(counterIds[0]);
  });

  it('moving a clerk to a second desk releases the first one', async () => {
    const { counterIds, staff } = await setupService(app, { counters: 2 });
    const boss = await createUserAndLogin(app, { role: 'admin' });

    // counterIds[1] belongs to staff[1]; free it first.
    await request(app)
      .delete(`/api/v1/counters/${counterIds[1]}/assign`)
      .set('Authorization', bearer(boss.token))
      .expect(200);

    await request(app)
      .post(`/api/v1/counters/${counterIds[1]}/assign`)
      .set('Authorization', bearer(boss.token))
      .send({ staffId: staff[0].id })
      .expect(200);

    const rows = await getDb().query<{ id: number; assigned_staff_id: number | null }>(
      'SELECT id, assigned_staff_id FROM service_counters ORDER BY counter_number',
    );
    expect(rows[0].assigned_staff_id).toBeNull();
    expect(rows[1].assigned_staff_id).toBe(staff[0].id);
  });

  it('unassigning a desk that nobody stands at is a no-op, not an error', async () => {
    const { counterIds } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const url = `/api/v1/counters/${counterIds[0]}/assign`;

    await request(app).delete(url).set('Authorization', bearer(boss.token)).expect(200);
    const second = await request(app).delete(url).set('Authorization', bearer(boss.token));

    expect(second.status).toBe(200);
    expect(second.body.data.staff).toBeNull();
  });
});

describe('roster: creating desks and clerks', () => {
  it('a new counter with nobody at it starts offline', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .post('/api/v1/counters')
      .set('Authorization', bearer(boss.token))
      .send({ serviceId, counterNumber: 7, name: 'Desk 7' })
      .expect(201);

    expect(response.body.data.status).toBe('offline');
    expect(response.body.data.staff).toBeNull();
  });

  it('a new counter can be opened with a clerk already at it', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const newcomer = await createUserAndLogin(app, { role: 'staff' });

    const response = await request(app)
      .post('/api/v1/counters')
      .set('Authorization', bearer(boss.token))
      .send({ serviceId, counterNumber: 8, name: 'Desk 8', staffId: newcomer.id })
      .expect(201);

    expect(response.body.data.status).toBe('available');
    expect(response.body.data.staff.id).toBe(newcomer.id);
  });

  it('a clerk cannot be put at two desks at once', async () => {
    const { serviceId, staff } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .post('/api/v1/counters')
      .set('Authorization', bearer(boss.token))
      .send({ serviceId, counterNumber: 9, name: 'Desk 9', staffId: staff[0].id });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('STAFF_ALREADY_ASSIGNED');
  });

  it('hiring a clerk straight onto a desk that belongs to another service is refused', async () => {
    const finance = await setupService(app, { code: 'FIN' });
    const registry = await setupService(app, { code: 'REG' });
    const boss = await createUserAndLogin(app, { role: 'admin' });

    // An empty desk in the *other* service, so the clash is about the service
    // and not about the desk already being occupied.
    const spare = await request(app)
      .post('/api/v1/counters')
      .set('Authorization', bearer(boss.token))
      .send({ serviceId: registry.serviceId, counterNumber: 4, name: 'Registry spare' })
      .expect(201);

    const response = await request(app)
      .post('/api/v1/staff')
      .set('Authorization', bearer(boss.token))
      .send({
        firstName: 'Mixed',
        lastName: 'Up',
        email: 'mixed.up@test.local',
        phone: '+254799111222',
        password: 'Password123',
        serviceId: finance.serviceId,
        counterId: spare.body.data.id,
      });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('CONFLICT');
  });

  it('hires a clerk with no posting at all', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .post('/api/v1/staff')
      .set('Authorization', bearer(boss.token))
      .send({
        firstName: 'Unposted',
        lastName: 'Clerk',
        email: 'unposted.clerk@test.local',
        phone: '+254799333444',
        password: 'Password123',
      })
      .expect(201);

    expect(response.body.data.posting).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Filters, defaults and optional arguments
// ---------------------------------------------------------------------------

describe('optional filters and defaults', () => {
  it('lists queues for an explicit date as well as for today', async () => {
    const { serviceId } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));
    const yesterday = addDays(todayDate(), -1);
    await insertQueue(serviceId, yesterday);

    const today = await request(app).get('/api/v1/queues').expect(200);
    expect(today.body.data).toHaveLength(1);
    expect(today.body.data[0].queueDate).toBe(todayDate());

    const historic = await request(app).get(`/api/v1/queues?date=${yesterday}`).expect(200);
    expect(historic.body.data).toHaveLength(1);
    expect(historic.body.data[0].queueDate).toBe(yesterday);
  });

  it('reports today\'s opening window on the service card', async () => {
    const { serviceId } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const today = new Date().getDay();

    // No hours configured at all: the service is simply always available.
    const always = await request(app).get(`/api/v1/services/${serviceId}`).expect(200);
    expect(always.body.data.hoursToday.opensAt).toBeNull();

    await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(boss.token))
      .send({ hours: [{ dayOfWeek: today, openingTime: '00:01', closingTime: '23:59', status: 'open' }] })
      .expect(200);

    const open = await request(app).get(`/api/v1/services/${serviceId}`).expect(200);
    expect(open.body.data.hoursToday).toEqual({ opensAt: '00:01', closesAt: '23:59', isOpenNow: true });

    await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(boss.token))
      .send({ hours: [{ dayOfWeek: today, openingTime: '09:00', closingTime: '17:00', status: 'closed' }] })
      .expect(200);

    const shut = await request(app).get(`/api/v1/services/${serviceId}`).expect(200);
    expect(shut.body.data.hoursToday).toEqual({ opensAt: '09:00', closesAt: '17:00', isOpenNow: false });
  });

  it('accepts an explicit date and window on the institution dashboard', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const { serviceId } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));

    const defaulted = await get(boss.token, '/dashboard/admin').expect(200);
    expect(defaulted.body.data.servedPerDay).toHaveLength(7);

    const explicit = await get(boss.token, `/dashboard/admin?date=${todayDate()}&days=14`).expect(200);
    expect(explicit.body.data.servedPerDay).toHaveLength(14);
    expect(explicit.body.data.today).toBe(todayDate());
    expect(explicit.body.data.ticketsIssuedToday).toBe(1);
  });

  it('an admin dashboard with no service chosen falls back to the first open one', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const { serviceId } = await setupService(app, { code: 'FIN', name: 'Finance Office' });
    await join(app, serviceId, await createUserAndLogin(app));

    const response = await get(boss.token, '/dashboard/staff').expect(200);
    expect(response.body.data.service.id).toBe(serviceId);
    expect(response.body.data.queue.waitingCount).toBe(1);
  });

  it('an admin can point the staff dashboard at a specific desk', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const { serviceId, counterIds } = await setupService(app);

    const response = await get(boss.token, `/dashboard/staff?serviceId=${serviceId}&counterId=${counterIds[0]}`).expect(200);
    expect(response.body.data.counter.id).toBe(counterIds[0]);
  });

  it('silently corrects a backwards date range instead of rejecting it', async () => {
    const { staff } = await setupService(app);
    const to = todayDate();
    const from = addDays(to, -3);

    const forwards = await get(staff[0].token, `/staff/me/statistics?from=${from}&to=${to}`).expect(200);
    const backwards = await get(staff[0].token, `/staff/me/statistics?from=${to}&to=${from}`).expect(200);

    expect(backwards.body.data.range).toEqual(forwards.body.data.range);
  });

  it('a customer cannot read the history of somebody else\'s ticket', async () => {
    const { serviceId } = await setupService(app);
    const owner = await createUserAndLogin(app);
    const nosy = await createUserAndLogin(app);
    const ticket = (await join(app, serviceId, owner)).body.data.ticket;

    expect((await get(owner.token, `/tickets/${ticket.id}/events`)).status).toBe(200);

    const response = await get(nosy.token, `/tickets/${ticket.id}/events`);
    expect(response.status).toBe(403);
    expect(response.body.code).toBe('FORBIDDEN');
  });

  it('marking a notification that does not exist is a 404', async () => {
    const shopper = await createUserAndLogin(app);
    const response = await request(app)
      .patch('/api/v1/notifications/999999/read')
      .set('Authorization', bearer(shopper.token));

    expect(response.status).toBe(404);
    expect(response.body.code).toBe('NOT_FOUND');
  });
});

// ---------------------------------------------------------------------------
// Guards that sit behind other guards
// ---------------------------------------------------------------------------

describe('defence in depth', () => {
  it('keeps at least one active super administrator (guard 4)', async () => {
    const boss = await createUserAndLogin(app, { role: 'super_admin' });

    // Guards 1–3 mean this can never be reached over HTTP: whoever asks is
    // themselves an active super administrator, so one always remains. The
    // guard is still there in case those rules are ever relaxed, so it is
    // proven directly against the service.
    const ghost: AuthUser = {
      id: boss.id + 10_000,
      firstName: 'Detached',
      lastName: 'Actor',
      email: 'detached@test.local',
      phone: '+254700000000',
      role: 'super_admin',
      status: 'active',
    };

    await expect(userService.setStatus(ghost, boss.id, 'inactive')).rejects.toMatchObject({
      statusCode: 409,
      code: 'CONFLICT',
    });
    await expect(userService.setRole(ghost, boss.id, 'admin')).rejects.toMatchObject({ code: 'CONFLICT' });
    await expect(userService.remove(ghost, boss.id)).rejects.toMatchObject({ code: 'CONFLICT' });
  });

  it('an ordinary administrator may not touch a super administrator (guard 3)', async () => {
    const boss = await createUserAndLogin(app, { role: 'super_admin' });
    const deputy = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .patch(`/api/v1/users/${boss.id}/status`)
      .set('Authorization', bearer(deputy.token))
      .send({ status: 'inactive' });

    expect(response.status).toBe(403);
  });

  it('a draft announcement is invisible on the public endpoint', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const shopper = await createUserAndLogin(app);

    const created = await request(app)
      .post('/api/v1/announcements')
      .set('Authorization', bearer(boss.token))
      .send({ title: 'Not ready yet', content: 'Still being written by the registrar.' })
      .expect(201);

    // The author can read it through the management endpoint…
    await get(boss.token, `/announcements/manage/${created.body.data.id}`).expect(200);

    // …but it does not exist as far as everybody else is concerned.
    const response = await get(shopper.token, `/announcements/${created.body.data.id}`);
    expect(response.status).toBe(404);
    expect(response.body.code).toBe('NOT_FOUND');
  });

  it('the institution dashboard defaults its own date and window', async () => {
    const { serviceId } = await setupService(app);
    await join(app, serviceId, await createUserAndLogin(app));

    // Called with no options at all, the way a future caller might.
    const dashboard = await adminService.getDashboard();

    expect(dashboard.today).toBe(todayDate());
    expect(dashboard.servedPerDay).toHaveLength(7);
    expect(dashboard.ticketsIssuedToday).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Reports — the shapes the Phase 8 fixture does not produce
// ---------------------------------------------------------------------------

describe('reports: unusual days', () => {
  it('describes a queue that opened and never issued a ticket', async () => {
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const { serviceId } = await setupService(app);
    await insertQueue(serviceId, todayDate());

    const response = await get(boss.token, `/reports/queues?from=${todayDate()}`).expect(200);
    const [row] = response.body.data.rows;

    expect(row.issued).toBe(0);
    expect(row.served).toBe(0);
    expect(row.peakQueue).toBe(0);
    expect(row.averageQueue).toBe(0);
    expect(row.utilisationPercent).toBe(0);
    expect(row.openedAt).not.toBeNull();
  });

  it('counts a clerk who handled tickets but completed none', async () => {
    const { serviceId, staff, counterIds } = await setupService(app);
    const boss = await createUserAndLogin(app, { role: 'admin' });
    const shopper = await createUserAndLogin(app);
    const ticket = (await join(app, serviceId, shopper)).body.data.ticket;

    await callNext(app, staff[0], serviceId, counterIds[0]);
    await act(app, staff[0], ticket.id, 'skip', { reason: 'Did not come forward' });

    const response = await get(boss.token, `/reports/staff?from=${todayDate()}`).expect(200);
    const row = response.body.data.rows.find((r: { staffId: number }) => r.staffId === staff[0].id);

    expect(row.ticketsHandled).toBeGreaterThan(0);
    expect(row.ticketsServed).toBe(0);
    expect(row.averageServiceMinutes).toBeNull();
    expect(response.body.data.totals.averageServiceMinutes).toBeNull();
  });
});
