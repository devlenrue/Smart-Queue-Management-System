/**
 * Phase 7 verification — the administrator console.
 *
 * Three things are being proved here, in this order of importance:
 *
 *   1. **The role matrix of docs/api.md §2 is real.** Every admin route is
 *      probed anonymously, as a customer, as a clerk and as an admin, and the
 *      three super-admin-only routes are probed as an admin too.
 *   2. **Search and filter are correct (§40)** — not merely "returns 200", but
 *      "returns exactly the rows that match and none of the ones that do not".
 *   3. **The roster writes keep `service_counters` and `staff_assignments` in
 *      step.** The proof is behavioural rather than structural: after an
 *      assignment the new clerk can actually call a ticket, and after an
 *      unassignment they get 403 NOT_ASSIGNED_TO_SERVICE.
 *
 * Plus the queue monitor, which must agree with the database after a scripted
 * sequence of staff actions.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { getDb } from '../src/db';
import { todayDate } from '../src/utils/datetime';
import { closeDatabase, freshDatabase } from './helpers/db';
import {
  act,
  bearer,
  callNext,
  clearQueueData,
  createUserAndLogin,
  join,
  setupService,
  TEST_PASSWORD,
} from './helpers/api';
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
  // clearQueueData leaves these two alone; the admin suite writes to both.
  await getDb().execute('DELETE FROM announcements');
  await getDb().execute('DELETE FROM system_settings');
});

// --------------------------------------------------------------------- shorthands

const get = (user: TestUser | null, path: string) => {
  const req = request(app).get(`/api/v1${path}`);
  return user ? req.set('Authorization', bearer(user.token)) : req;
};

const post = (user: TestUser | null, path: string, body: object = {}) => {
  const req = request(app).post(`/api/v1${path}`).send(body);
  return user ? req.set('Authorization', bearer(user.token)) : req;
};

const put = (user: TestUser | null, path: string, body: object = {}) => {
  const req = request(app).put(`/api/v1${path}`).send(body);
  return user ? req.set('Authorization', bearer(user.token)) : req;
};

const patch = (user: TestUser | null, path: string, body: object = {}) => {
  const req = request(app).patch(`/api/v1${path}`).send(body);
  return user ? req.set('Authorization', bearer(user.token)) : req;
};

const del = (user: TestUser | null, path: string) => {
  const req = request(app).delete(`/api/v1${path}`);
  return user ? req.set('Authorization', bearer(user.token)) : req;
};

const admin = () => createUserAndLogin(app, { role: 'admin', firstName: 'Ada', lastName: 'Admin' });
const superAdmin = () => createUserAndLogin(app, { role: 'super_admin', firstName: 'Sam', lastName: 'Super' });
const customer = (overrides: { firstName?: string; lastName?: string; email?: string } = {}) =>
  createUserAndLogin(app, { role: 'customer', ...overrides });

/** Joins, calls, starts and completes one ticket. Returns the ticket id. */
async function serveOne(service: TestService, staff: TestUser, who: TestUser): Promise<number> {
  expect((await join(app, service.serviceId, who)).status).toBe(201);
  const called = await callNext(app, staff, service.serviceId);
  expect(called.status).toBe(200);
  const ticketId = called.body.data.ticket.id;
  expect((await act(app, staff, ticketId, 'start')).status).toBe(200);
  expect((await act(app, staff, ticketId, 'complete')).status).toBe(200);
  return ticketId;
}

// ===========================================================================
// 1. Role matrix (§2)
// ===========================================================================

describe('admin role matrix', () => {
  it('refuses the admin dashboard to anonymous, customer and staff callers', async () => {
    const service = await setupService(app, { counters: 1 });
    const shopper = await customer();

    expect((await get(null, '/dashboard/admin')).status).toBe(401);
    expect((await get(shopper, '/dashboard/admin')).status).toBe(403);
    expect((await get(service.staff[0], '/dashboard/admin')).status).toBe(403);
  });

  it('allows an admin and a super admin onto the dashboard', async () => {
    expect((await get(await admin(), '/dashboard/admin')).status).toBe(200);
    expect((await get(await superAdmin(), '/dashboard/admin')).status).toBe(200);
  });

  it('keeps every /users route away from customers and staff', async () => {
    const service = await setupService(app, { counters: 1 });
    const shopper = await customer();
    const clerk = service.staff[0];

    for (const user of [shopper, clerk]) {
      expect((await get(user, '/users')).status).toBe(403);
      expect((await get(user, `/users/${shopper.id}`)).status).toBe(403);
      expect((await patch(user, `/users/${shopper.id}/status`, { status: 'suspended' })).status).toBe(403);
      expect((await patch(user, `/users/${shopper.id}/role`, { role: 'staff' })).status).toBe(403);
      expect((await del(user, `/users/${shopper.id}`)).status).toBe(403);
    }
  });

  it('keeps the roster and counter writes away from clerks', async () => {
    const service = await setupService(app, { counters: 1 });
    const clerk = service.staff[0];

    expect((await get(clerk, '/staff')).status).toBe(403);
    expect((await post(clerk, '/staff', {})).status).toBe(403);
    expect((await put(clerk, `/staff/${clerk.id}`, { firstName: 'Nope' })).status).toBe(403);
    expect((await post(clerk, `/staff/${clerk.id}/assign`, { serviceId: service.serviceId })).status).toBe(403);
    expect((await post(clerk, `/staff/${clerk.id}/unassign`, {})).status).toBe(403);

    expect((await post(clerk, '/counters', {})).status).toBe(403);
    expect((await put(clerk, `/counters/${service.counterIds[0]}`, { name: 'Nope' })).status).toBe(403);
    expect((await post(clerk, `/counters/${service.counterIds[0]}/assign`, { staffId: clerk.id })).status).toBe(403);
    expect((await del(clerk, `/counters/${service.counterIds[0]}/assign`)).status).toBe(403);
    expect((await del(clerk, `/counters/${service.counterIds[0]}`)).status).toBe(403);
  });

  it('reserves role changes, deletions and system settings for a super admin', async () => {
    const boss = await admin();
    const shopper = await customer();

    expect((await patch(boss, `/users/${shopper.id}/role`, { role: 'staff' })).status).toBe(403);
    expect((await del(boss, `/users/${shopper.id}`)).status).toBe(403);
    expect((await get(boss, '/system/settings')).status).toBe(403);
    expect((await put(boss, '/system/settings', { 'queue.banner': 'hi' })).status).toBe(403);

    const chief = await superAdmin();
    expect((await patch(chief, `/users/${shopper.id}/role`, { role: 'staff' })).status).toBe(200);
    expect((await get(chief, '/system/settings')).status).toBe(200);
  });

  it('keeps the announcement composer away from customers', async () => {
    const shopper = await customer();
    expect((await get(shopper, '/announcements/manage')).status).toBe(403);
    expect((await post(shopper, '/announcements', { title: 'Hello', content: 'World' })).status).toBe(403);
  });

  it('still lets anyone read the published announcement board', async () => {
    expect((await get(null, '/announcements')).status).toBe(200);
  });
});

// ===========================================================================
// 2. Dashboard (§31, §42)
// ===========================================================================

describe('GET /dashboard/admin', () => {
  it('reports zeroes for a day with no tickets, but still counts the services', async () => {
    await setupService(app, { counters: 2 });
    const boss = await admin();

    const response = await get(boss, '/dashboard/admin');
    expect(response.status).toBe(200);

    const data = response.body.data;
    expect(data.today).toBe(todayDate());
    expect(data.activeServices).toBe(1);
    expect(data.activeCounters).toBe(2);
    expect(data.staffOnDuty).toBe(2);
    expect(data.ticketsIssuedToday).toBe(0);
    expect(data.customersWaiting).toBe(0);
    expect(data.customersServedToday).toBe(0);
    expect(data.averageWaitMinutes).toBe(0);
    expect(data.statusBreakdown).toEqual({
      waiting: 0,
      serving: 0,
      completed: 0,
      cancelled: 0,
      skipped: 0,
      noShow: 0,
    });
  });

  it('counts a scripted day exactly', async () => {
    const service = await setupService(app, { counters: 1 });
    const clerk = service.staff[0];
    const [a, b, c, d] = await Promise.all([customer(), customer(), customer(), customer()]);

    await serveOne(service, clerk, a); // completed
    await join(app, service.serviceId, b); // waiting
    await join(app, service.serviceId, c); // waiting → cancelled below
    await join(app, service.serviceId, d); // waiting → called, then skipped

    const cTicket = (await get(c, '/tickets/my')).body.data[0];
    expect((await act(app, c, cTicket.id, 'cancel')).status).toBe(200);

    const called = await callNext(app, clerk, service.serviceId); // takes b
    expect(called.status).toBe(200);
    expect((await act(app, clerk, called.body.data.ticket.id, 'skip')).status).toBe(200);

    const data = (await get(await admin(), '/dashboard/admin')).body.data;

    expect(data.ticketsIssuedToday).toBe(4);
    expect(data.customersServedToday).toBe(1);
    expect(data.cancelledToday).toBe(1);
    expect(data.skippedToday).toBe(1);
    expect(data.customersWaiting).toBe(1); // only d is still waiting
    expect(data.statusBreakdown).toEqual({
      waiting: 1,
      serving: 0,
      completed: 1,
      cancelled: 1,
      skipped: 1,
      noShow: 0,
    });
  });

  it('breaks the day down per service, including a service that issued nothing', async () => {
    const finance = await setupService(app, { code: 'FIN', name: 'Finance Office', counters: 1 });
    await setupService(app, { code: 'LIB', name: 'Library', counters: 1 });
    await serveOne(finance, finance.staff[0], await customer());

    const rows = (await get(await admin(), '/dashboard/admin')).body.data.byService;
    expect(rows).toHaveLength(2);

    const fin = rows.find((row: { code: string }) => row.code === 'FIN');
    const lib = rows.find((row: { code: string }) => row.code === 'LIB');

    expect(fin).toMatchObject({ name: 'Finance Office', issued: 1, completed: 1, waiting: 0, status: 'open' });
    expect(lib).toMatchObject({ name: 'Library', issued: 0, completed: 0, waiting: 0 });
  });

  it('returns a dense served-per-day series ending today', async () => {
    const service = await setupService(app, { counters: 1 });
    await serveOne(service, service.staff[0], await customer());
    const boss = await admin();

    const week = (await get(boss, '/dashboard/admin')).body.data.servedPerDay;
    expect(week).toHaveLength(7);
    expect(week[6].date).toBe(todayDate());
    expect(week[6].served).toBe(1);
    expect(week[6].label).toEqual(expect.any(String));
    // The six quiet days are present with zeroes rather than missing.
    expect(week.slice(0, 6).every((point: { served: number }) => point.served === 0)).toBe(true);

    const threeDays = (await get(boss, '/dashboard/admin?days=3')).body.data.servedPerDay;
    expect(threeDays).toHaveLength(3);
    expect(threeDays[2].date).toBe(todayDate());
  });

  it('honours ?date= by reporting on that queue day', async () => {
    const service = await setupService(app, { counters: 1 });
    await serveOne(service, service.staff[0], await customer());

    const data = (await get(await admin(), '/dashboard/admin?date=2020-01-02')).body.data;
    expect(data.today).toBe('2020-01-02');
    expect(data.ticketsIssuedToday).toBe(0);
    expect(data.customersServedToday).toBe(0);
    // Live figures are about "now", not about the day being reported.
    expect(data.activeServices).toBe(1);
  });

  it('rejects a malformed date or day count with 422', async () => {
    const boss = await admin();
    expect((await get(boss, '/dashboard/admin?date=29-09-2026')).status).toBe(422);
    expect((await get(boss, '/dashboard/admin?days=0')).status).toBe(422);
    expect((await get(boss, '/dashboard/admin?days=99')).status).toBe(422);
  });

  it('counts only counters that are available or busy', async () => {
    const service = await setupService(app, { counters: 2 });
    const boss = await admin();
    expect((await get(boss, '/dashboard/admin')).body.data.activeCounters).toBe(2);

    await patch(service.staff[0], `/counters/${service.counterIds[0]}/status`, { status: 'offline' });
    expect((await get(boss, '/dashboard/admin')).body.data.activeCounters).toBe(1);
  });
});

// ===========================================================================
// 3. Users (§9, §40)
// ===========================================================================

describe('GET /users', () => {
  it('filters by role and by status, and pages', async () => {
    const service = await setupService(app, { counters: 2 });
    await customer();
    await customer();
    const boss = await admin();

    const customers = await get(boss, '/users?role=customer');
    expect(customers.status).toBe(200);
    expect(customers.body.data).toHaveLength(2);
    expect(customers.body.data.every((row: { role: string }) => row.role === 'customer')).toBe(true);
    expect(customers.body.meta).toMatchObject({ page: 1, limit: 20, total: 2, totalPages: 1 });

    const staff = await get(boss, '/users?role=staff');
    expect(staff.body.data).toHaveLength(service.staff.length);

    const firstPage = await get(boss, '/users?limit=2&page=1');
    expect(firstPage.body.data).toHaveLength(2);
    expect(firstPage.body.meta.total).toBe(5); // 2 clerks + 2 customers + 1 admin
    expect(firstPage.body.meta.totalPages).toBe(3);
  });

  it('searches names, emails and phone numbers — and excludes the rest', async () => {
    await customer({ firstName: 'Mary', lastName: 'Atieno', email: 'mary.atieno@test.local' });
    await customer({ firstName: 'Peter', lastName: 'Kamau', email: 'peter.kamau@test.local' });
    const boss = await admin();

    const byName = await get(boss, '/users?search=atieno');
    expect(byName.body.data).toHaveLength(1);
    expect(byName.body.data[0].fullName).toBe('Mary Atieno');

    const byEmail = await get(boss, '/users?search=peter.kamau@test.local');
    expect(byEmail.body.data).toHaveLength(1);
    expect(byEmail.body.data[0].firstName).toBe('Peter');

    expect((await get(boss, '/users?search=nobody-by-that-name')).body.data).toHaveLength(0);
  });

  it('never leaks a password hash', async () => {
    await customer();
    const body = (await get(await admin(), '/users')).text;
    expect(body).not.toContain('password');
    expect(body).not.toContain('$2');
  });

  it('describes one user with their activity and posting', async () => {
    const service = await setupService(app, { counters: 1 });
    const shopper = await customer({ firstName: 'Nia', lastName: 'Mwangi' });
    await serveOne(service, service.staff[0], shopper);
    const boss = await admin();

    const detail = await get(boss, `/users/${shopper.id}`);
    expect(detail.status).toBe(200);
    expect(detail.body.data).toMatchObject({ fullName: 'Nia Mwangi', role: 'customer', posting: null });
    expect(detail.body.data.activity).toMatchObject({ totalTickets: 1, completed: 1, cancelled: 0, active: 0 });
    expect(detail.body.data.activity.lastActivityAt).toEqual(expect.any(String));

    const clerk = await get(boss, `/users/${service.staff[0].id}`);
    expect(clerk.body.data.posting).toMatchObject({ serviceId: service.serviceId, counterNumber: 1 });
  });

  it('404s for a user who does not exist', async () => {
    expect((await get(await admin(), '/users/999999')).status).toBe(404);
  });
});

describe('PATCH /users/:id/status', () => {
  it('suspends an account, and the suspended token stops working', async () => {
    const shopper = await customer();
    const boss = await admin();

    const response = await patch(boss, `/users/${shopper.id}/status`, { status: 'suspended' });
    expect(response.status).toBe(200);
    expect(response.body.data.status).toBe('suspended');

    const blocked = await get(shopper, '/profile');
    expect(blocked.status).toBe(403);
    expect(blocked.body.code).toBe('ACCOUNT_SUSPENDED');
  });

  it('releases the counter and the posting of a suspended clerk', async () => {
    const service = await setupService(app, { counters: 1 });
    const clerk = service.staff[0];
    const boss = await admin();

    expect((await patch(boss, `/users/${clerk.id}/status`, { status: 'suspended' })).status).toBe(200);

    const counters = (await get(boss, `/counters?serviceId=${service.serviceId}`)).body.data;
    expect(counters[0].staff).toBeNull();
    expect((await get(boss, `/staff?serviceId=${service.serviceId}`)).body.data).toHaveLength(0);
  });

  it('refuses to let an administrator lock themselves out', async () => {
    const boss = await admin();
    const response = await patch(boss, `/users/${boss.id}/status`, { status: 'suspended' });
    expect(response.status).toBe(409);
    expect(response.body.message).toMatch(/your own account/i);
  });

  it('refuses to let an ordinary admin touch a super admin', async () => {
    const chief = await superAdmin();
    const boss = await admin();
    expect((await patch(boss, `/users/${chief.id}/status`, { status: 'suspended' })).status).toBe(403);
  });

  it('rejects an unknown status with 422', async () => {
    const shopper = await customer();
    expect((await patch(await admin(), `/users/${shopper.id}/status`, { status: 'banished' })).status).toBe(422);
  });
});

describe('PATCH /users/:id/role and DELETE /users/:id', () => {
  it('promotes a customer to staff', async () => {
    const shopper = await customer();
    const chief = await superAdmin();

    const response = await patch(chief, `/users/${shopper.id}/role`, { role: 'staff' });
    expect(response.status).toBe(200);
    expect(response.body.data.role).toBe('staff');
    expect((await get(chief, '/staff')).body.data).toHaveLength(1);
  });

  it('strips the counter from someone who stops being staff', async () => {
    const service = await setupService(app, { counters: 1 });
    const chief = await superAdmin();

    expect((await patch(chief, `/users/${service.staff[0].id}/role`, { role: 'customer' })).status).toBe(200);
    expect((await get(chief, `/counters?serviceId=${service.serviceId}`)).body.data[0].staff).toBeNull();
  });

  it('will not let a super admin demote or delete themselves', async () => {
    const chief = await superAdmin();
    expect((await patch(chief, `/users/${chief.id}/role`, { role: 'customer' })).status).toBe(409);
    expect((await del(chief, `/users/${chief.id}`)).status).toBe(409);
  });

  it('deletes an account and everything that hangs off it', async () => {
    const service = await setupService(app, { counters: 1 });
    const shopper = await customer();
    await serveOne(service, service.staff[0], shopper);
    const chief = await superAdmin();

    expect((await del(chief, `/users/${shopper.id}`)).status).toBe(204);
    expect((await get(chief, `/users/${shopper.id}`)).status).toBe(404);

    const tickets = await getDb().query('SELECT id FROM queue_tickets WHERE user_id = ?', [shopper.id]);
    expect(tickets).toHaveLength(0);
  });
});

// ===========================================================================
// 4. Staff roster (§55)
// ===========================================================================

describe('GET /staff', () => {
  it('lists clerks with the posting they are working', async () => {
    const service = await setupService(app, { counters: 2 });
    await customer(); // must not appear

    const response = await get(await admin(), '/staff');
    expect(response.status).toBe(200);
    expect(response.body.data).toHaveLength(2);
    expect(response.body.data.every((row: { role: string }) => row.role === 'staff')).toBe(true);
    expect(response.body.data[0].posting).toMatchObject({
      serviceId: service.serviceId,
      serviceCode: 'FIN',
      counterNumber: expect.any(Number),
    });
    expect(response.body.meta).toMatchObject({ page: 1, limit: 20, total: 2 });
  });

  it('filters by service, by status and by "unassigned"', async () => {
    const finance = await setupService(app, { code: 'FIN', counters: 1 });
    const library = await setupService(app, { code: 'LIB', counters: 1 });
    const boss = await admin();

    const spare = await post(boss, '/staff', {
      firstName: 'Spare',
      lastName: 'Clerk',
      email: 'spare.clerk@test.local',
      phone: '+254799111222',
      password: TEST_PASSWORD,
    });
    expect(spare.status).toBe(201);

    expect((await get(boss, `/staff?serviceId=${finance.serviceId}`)).body.data).toHaveLength(1);
    expect((await get(boss, `/staff?serviceId=${library.serviceId}`)).body.data).toHaveLength(1);

    const unassigned = await get(boss, '/staff?unassigned=true');
    expect(unassigned.body.data).toHaveLength(1);
    expect(unassigned.body.data[0].fullName).toBe('Spare Clerk');
    expect(unassigned.body.data[0].posting).toBeNull();

    expect((await get(boss, '/staff?status=suspended')).body.data).toHaveLength(0);
  });

  it('searches the roster by name and email', async () => {
    const boss = await admin();
    await post(boss, '/staff', {
      firstName: 'Jane',
      lastName: 'Wanjiku',
      email: 'jane.wanjiku@test.local',
      phone: '+254799333444',
      password: TEST_PASSWORD,
    });
    await post(boss, '/staff', {
      firstName: 'Brian',
      lastName: 'Otieno',
      email: 'brian.otieno@test.local',
      phone: '+254799555666',
      password: TEST_PASSWORD,
    });

    expect((await get(boss, '/staff?search=wanjiku')).body.data).toHaveLength(1);
    expect((await get(boss, '/staff?search=brian.otieno@test.local')).body.data[0].firstName).toBe('Brian');
    expect((await get(boss, '/staff?search=zzz')).body.data).toHaveLength(0);
  });
});

describe('POST /staff', () => {
  it('creates a working staff account', async () => {
    const boss = await admin();

    const response = await post(boss, '/staff', {
      firstName: 'New',
      lastName: 'Clerk',
      email: 'new.clerk@test.local',
      phone: '+254700111000',
      password: TEST_PASSWORD,
    });

    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({ role: 'staff', status: 'active', posting: null });

    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'new.clerk@test.local', password: TEST_PASSWORD });
    expect(login.status).toBe(200);
    expect(login.body.data.user.role).toBe('staff');
  });

  it('posts the new clerk to a counter, and that clerk can immediately call a ticket', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();

    const counter = await post(boss, '/counters', {
      serviceId: service.serviceId,
      counterNumber: 2,
      name: 'Counter 2',
    });
    expect(counter.status).toBe(201);

    const created = await post(boss, '/staff', {
      firstName: 'Ready',
      lastName: 'ToWork',
      email: 'ready.towork@test.local',
      phone: '+254700111001',
      password: TEST_PASSWORD,
      counterId: counter.body.data.id,
    });
    expect(created.status).toBe(201);
    expect(created.body.data.posting).toMatchObject({
      serviceId: service.serviceId,
      counterId: counter.body.data.id,
      counterNumber: 2,
    });

    // The behavioural proof: both tables agree, so Rule 4 and Rule 5 pass.
    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'ready.towork@test.local', password: TEST_PASSWORD });
    const clerk: TestUser = { id: created.body.data.id, email: 'ready.towork@test.local', token: login.body.data.token };

    await join(app, service.serviceId, await customer());
    const called = await callNext(app, clerk, service.serviceId);
    expect(called.status).toBe(200);
    expect(called.body.data.ticket.counter.counterNumber).toBe(2);
  });

  it('rejects a duplicate email, a duplicate phone and a weak password', async () => {
    const boss = await admin();
    const base = {
      firstName: 'Dup',
      lastName: 'Clerk',
      email: 'dup.clerk@test.local',
      phone: '+254700111002',
      password: TEST_PASSWORD,
    };
    expect((await post(boss, '/staff', base)).status).toBe(201);

    const sameEmail = await post(boss, '/staff', { ...base, phone: '+254700111003' });
    expect(sameEmail.status).toBe(409);
    expect(sameEmail.body.code).toBe('EMAIL_TAKEN');

    const samePhone = await post(boss, '/staff', { ...base, email: 'other.clerk@test.local' });
    expect(samePhone.status).toBe(409);
    expect(samePhone.body.code).toBe('PHONE_TAKEN');

    const weak = await post(boss, '/staff', { ...base, email: 'weak@test.local', phone: '+254700111004', password: 'abc' });
    expect(weak.status).toBe(422);
    expect(weak.body.errors.some((error: { field: string }) => error.field === 'password')).toBe(true);
  });

  it('refuses a counter that already has somebody at it', async () => {
    const service = await setupService(app, { counters: 1 });
    const response = await post(await admin(), '/staff', {
      firstName: 'Second',
      lastName: 'Clerk',
      email: 'second.clerk@test.local',
      phone: '+254700111005',
      password: TEST_PASSWORD,
      counterId: service.counterIds[0],
    });
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('STAFF_ALREADY_ASSIGNED');
  });
});

describe('staff postings', () => {
  it('moves a clerk between counters and leaves exactly one active assignment', async () => {
    const service = await setupService(app, { counters: 1 });
    const clerk = service.staff[0];
    const boss = await admin();

    const second = await post(boss, '/counters', {
      serviceId: service.serviceId,
      counterNumber: 2,
      name: 'Counter 2',
    });

    const moved = await post(boss, `/staff/${clerk.id}/assign`, {
      serviceId: service.serviceId,
      counterId: second.body.data.id,
    });
    expect(moved.status).toBe(200);
    expect(moved.body.data.posting.counterNumber).toBe(2);

    const counters = (await get(boss, `/counters?serviceId=${service.serviceId}`)).body.data;
    expect(counters.find((row: { counterNumber: number }) => row.counterNumber === 1).staff).toBeNull();
    expect(counters.find((row: { counterNumber: number }) => row.counterNumber === 2).staff.id).toBe(clerk.id);

    const active = await getDb().query(
      "SELECT id FROM staff_assignments WHERE staff_id = ? AND status = 'active'",
      [clerk.id],
    );
    expect(active).toHaveLength(1);
  });

  it('will not move a clerk who is mid-customer', async () => {
    const service = await setupService(app, { counters: 1 });
    const clerk = service.staff[0];
    const boss = await admin();

    await join(app, service.serviceId, await customer());
    const called = await callNext(app, clerk, service.serviceId);
    expect(called.status).toBe(200);

    const second = await post(boss, '/counters', { serviceId: service.serviceId, counterNumber: 2, name: 'Counter 2' });
    const blocked = await post(boss, `/staff/${clerk.id}/assign`, {
      serviceId: service.serviceId,
      counterId: second.body.data.id,
    });
    expect(blocked.status).toBe(409);
    expect(blocked.body.code).toBe('COUNTER_BUSY');

    // Finish the customer and the move goes through.
    expect((await act(app, clerk, called.body.data.ticket.id, 'skip')).status).toBe(200);
    expect((await post(boss, `/staff/${clerk.id}/assign`, {
      serviceId: service.serviceId,
      counterId: second.body.data.id,
    })).status).toBe(200);
  });

  it('refuses a counter belonging to another service', async () => {
    const finance = await setupService(app, { code: 'FIN', counters: 1 });
    const library = await setupService(app, { code: 'LIB', counters: 1 });

    const response = await post(await admin(), `/staff/${finance.staff[0].id}/assign`, {
      serviceId: finance.serviceId,
      counterId: library.counterIds[0],
    });
    expect(response.status).toBe(409);
    expect(response.body.message).toMatch(/different service/i);
  });

  it('refuses to post somebody who is not staff', async () => {
    const service = await setupService(app, { counters: 1 });
    const shopper = await customer();
    const response = await post(await admin(), `/staff/${shopper.id}/assign`, { serviceId: service.serviceId });
    expect(response.status).toBe(409);
    expect(response.body.message).toMatch(/not a staff member/i);
  });

  it('unassigns a clerk, who then cannot call anything', async () => {
    const service = await setupService(app, { counters: 1 });
    const clerk = service.staff[0];
    const boss = await admin();

    await join(app, service.serviceId, await customer());

    const response = await post(boss, `/staff/${clerk.id}/unassign`, {});
    expect(response.status).toBe(200);
    expect(response.body.data.posting).toBeNull();

    const refused = await callNext(app, clerk, service.serviceId);
    expect(refused.status).toBe(403);
    expect(refused.body.code).toBe('NOT_ASSIGNED_TO_SERVICE');

    // Their dashboard degrades gracefully rather than erroring.
    const dashboard = await get(clerk, '/dashboard/staff');
    expect(dashboard.status).toBe(200);
    expect(dashboard.body.data.assigned).toBe(false);
  });

  it('updates a clerk profile and 404s for an unknown id', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();

    const updated = await put(boss, `/staff/${service.staff[0].id}`, { firstName: 'Renamed', phone: '+254700999888' });
    expect(updated.status).toBe(200);
    expect(updated.body.data.firstName).toBe('Renamed');
    expect(updated.body.data.phone).toBe('+254700999888');

    expect((await put(boss, '/staff/999999', { firstName: 'Ghost' })).status).toBe(404);
    expect((await put(boss, `/staff/${service.staff[0].id}`, {})).status).toBe(422);
  });
});

// ===========================================================================
// 5. Counters (§54)
// ===========================================================================

describe('counter administration', () => {
  it('creates an unstaffed counter offline', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();

    const response = await post(boss, '/counters', {
      serviceId: service.serviceId,
      counterNumber: 7,
      name: 'Express Desk',
    });

    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({
      serviceId: service.serviceId,
      counterNumber: 7,
      name: 'Express Desk',
      status: 'offline',
      staff: null,
    });
  });

  it('refuses a duplicate counter number in the same service', async () => {
    const service = await setupService(app, { counters: 1 });
    const response = await post(await admin(), '/counters', {
      serviceId: service.serviceId,
      counterNumber: 1,
      name: 'Clash',
    });
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('COUNTER_NUMBER_TAKEN');
  });

  it('allows the same number in a different service', async () => {
    await setupService(app, { code: 'FIN', counters: 1 });
    const library = await setupService(app, { code: 'LIB', counters: 1 });
    // LIB already has counter 1; 2 is free in LIB even though FIN has one too.
    const response = await post(await admin(), '/counters', {
      serviceId: library.serviceId,
      counterNumber: 2,
      name: 'Library Desk 2',
    });
    expect(response.status).toBe(201);
  });

  it('renames a counter and blocks a clashing renumber', async () => {
    const service = await setupService(app, { counters: 2 });
    const boss = await admin();

    const renamed = await put(boss, `/counters/${service.counterIds[0]}`, { name: 'Renamed Desk' });
    expect(renamed.status).toBe(200);
    expect(renamed.body.data.name).toBe('Renamed Desk');

    const clash = await put(boss, `/counters/${service.counterIds[0]}`, { counterNumber: 2 });
    expect(clash.status).toBe(409);
    expect(clash.body.code).toBe('COUNTER_NUMBER_TAKEN');
  });

  it('will not take a counter offline while it is holding a ticket', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();

    await join(app, service.serviceId, await customer());
    expect((await callNext(app, service.staff[0], service.serviceId)).status).toBe(200);

    const blocked = await put(boss, `/counters/${service.counterIds[0]}`, { status: 'offline' });
    expect(blocked.status).toBe(409);
    expect(blocked.body.code).toBe('COUNTER_BUSY');
  });

  it('assigns and frees a counter from the counter side', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();

    const spare = await post(boss, '/staff', {
      firstName: 'Relief',
      lastName: 'Clerk',
      email: 'relief.clerk@test.local',
      phone: '+254700222111',
      password: TEST_PASSWORD,
    });

    const reassigned = await post(boss, `/counters/${service.counterIds[0]}/assign`, { staffId: spare.body.data.id });
    expect(reassigned.status).toBe(200);
    expect(reassigned.body.data.staff.id).toBe(spare.body.data.id);
    expect(reassigned.body.data.status).toBe('available');

    // The clerk who used to hold it has lost the posting.
    const previous = await get(boss, `/users/${service.staff[0].id}`);
    expect(previous.body.data.posting).toBeNull();

    const freed = await del(boss, `/counters/${service.counterIds[0]}/assign`);
    expect(freed.status).toBe(200);
    expect(freed.body.data.staff).toBeNull();
    expect(freed.body.data.status).toBe('offline');
  });

  it('deletes an idle counter and refuses a busy one', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();

    await join(app, service.serviceId, await customer());
    const called = await callNext(app, service.staff[0], service.serviceId);
    expect(called.status).toBe(200);

    const blocked = await del(boss, `/counters/${service.counterIds[0]}`);
    expect(blocked.status).toBe(409);
    expect(blocked.body.code).toBe('COUNTER_BUSY');

    expect((await act(app, service.staff[0], called.body.data.ticket.id, 'skip')).status).toBe(200);
    expect((await del(boss, `/counters/${service.counterIds[0]}`)).status).toBe(204);
    expect((await get(boss, `/counters?serviceId=${service.serviceId}`)).body.data).toHaveLength(0);
  });

  it('404s for an unknown counter and 422s for a bad body', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();
    expect((await put(boss, '/counters/999999', { name: 'Ghost' })).status).toBe(404);
    expect((await post(boss, '/counters', { serviceId: service.serviceId, name: 'No number' })).status).toBe(422);
    expect((await post(boss, '/counters', { serviceId: 999999, counterNumber: 3, name: 'Orphan' })).status).toBe(404);
  });
});

// ===========================================================================
// 6. Announcements (§11)
// ===========================================================================

describe('announcement composer', () => {
  it('keeps a draft off the public board until it is published', async () => {
    const boss = await admin();
    const shopper = await customer();

    const draft = await post(boss, '/announcements', { title: 'Systems upgrade', content: 'Saturday, 8am–noon.' });
    expect(draft.status).toBe(201);
    expect(draft.body.data).toMatchObject({ status: 'draft', isGlobal: true, publishedAt: null });

    expect((await get(shopper, '/announcements')).body.data).toHaveLength(0);
    expect((await get(boss, '/announcements/manage')).body.data).toHaveLength(1);

    const published = await patch(boss, `/announcements/${draft.body.data.id}/publish`);
    expect(published.status).toBe(200);
    expect(published.body.data.status).toBe('published');
    expect(published.body.data.publishedAt).toEqual(expect.any(String));

    const board = await get(shopper, '/announcements');
    expect(board.body.data).toHaveLength(1);
    expect(board.body.data[0].title).toBe('Systems upgrade');
  });

  it('notifies every active customer once, on the transition into published', async () => {
    const boss = await admin();
    const one = await customer();
    const two = await customer();

    const draft = await post(boss, '/announcements', { title: 'Holiday hours', content: 'Closed on Monday.' });
    expect((await get(one, '/notifications')).body.data.notifications).toHaveLength(0);

    await patch(boss, `/announcements/${draft.body.data.id}/publish`);

    for (const shopper of [one, two]) {
      const inbox = (await get(shopper, '/notifications')).body.data.notifications;
      expect(inbox).toHaveLength(1);
      expect(inbox[0]).toMatchObject({ title: 'Holiday hours', type: 'announcement' });
    }

    // Publishing again is a no-op, not a second round of messages.
    await patch(boss, `/announcements/${draft.body.data.id}/publish`);
    expect((await get(one, '/notifications')).body.data.notifications).toHaveLength(1);
  });

  it('publishes straight away when asked to, and attaches to a service', async () => {
    const service = await setupService(app, { counters: 1 });
    const boss = await admin();
    const shopper = await customer();

    const response = await post(boss, '/announcements', {
      title: 'Finance desk closed',
      content: 'Counter 1 is closed this afternoon.',
      serviceId: service.serviceId,
      status: 'published',
    });

    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({ status: 'published', serviceId: service.serviceId, isGlobal: false });
    expect((await get(shopper, '/notifications')).body.data.notifications).toHaveLength(1);
    expect((await get(shopper, `/announcements?serviceId=${service.serviceId}`)).body.data).toHaveLength(1);
  });

  it('edits, filters, archives and deletes', async () => {
    const boss = await admin();
    const first = await post(boss, '/announcements', { title: 'First', content: 'One' });
    await post(boss, '/announcements', { title: 'Second', content: 'Two', status: 'published' });

    const edited = await put(boss, `/announcements/${first.body.data.id}`, { title: 'First, edited' });
    expect(edited.status).toBe(200);
    expect(edited.body.data.title).toBe('First, edited');

    expect((await get(boss, '/announcements/manage?status=draft')).body.data).toHaveLength(1);
    expect((await get(boss, '/announcements/manage?status=published')).body.data).toHaveLength(1);
    expect((await get(boss, '/announcements/manage?search=second')).body.data).toHaveLength(1);

    const archived = await patch(boss, `/announcements/${first.body.data.id}/archive`);
    expect(archived.body.data.status).toBe('archived');

    expect((await del(boss, `/announcements/${first.body.data.id}`)).status).toBe(204);
    expect((await get(boss, '/announcements/manage')).body.data).toHaveLength(1);
    expect((await get(boss, `/announcements/manage/${first.body.data.id}`)).status).toBe(404);
  });

  it('validates the composer form', async () => {
    const boss = await admin();
    expect((await post(boss, '/announcements', { title: 'x', content: 'too short a title' })).status).toBe(422);
    expect((await post(boss, '/announcements', { title: 'Fine title', content: '' })).status).toBe(422);
    expect(
      (await post(boss, '/announcements', { title: 'Fine title', content: 'Fine content', expiresAt: 'whenever' }))
        .status,
    ).toBe(422);
    expect(
      (await post(boss, '/announcements', { title: 'Fine title', content: 'Fine content', serviceId: 999999 })).status,
    ).toBe(404);
  });
});

// ===========================================================================
// 7. System settings (§14)
// ===========================================================================

describe('system settings', () => {
  it('stores, reads back and removes settings', async () => {
    const chief = await superAdmin();

    const written = await put(chief, '/system/settings', {
      'queue.banner': 'Welcome to SmartQueue',
      'queue.max_daily': 250,
      'queue.allow_rejoin': false,
    });
    expect(written.status).toBe(200);

    const settings = (await get(chief, '/system/settings')).body.data;
    const byKey = Object.fromEntries(settings.map((row: { key: string; value: string }) => [row.key, row.value]));
    expect(byKey['queue.banner']).toBe('Welcome to SmartQueue');
    // Everything is stored as text, so the reader decides the type.
    expect(byKey['queue.max_daily']).toBe('250');
    expect(byKey['queue.allow_rejoin']).toBe('false');

    await put(chief, '/system/settings', { 'queue.banner': 'Updated' });
    expect((await get(chief, '/system/settings')).body.data.find((row: { key: string }) => row.key === 'queue.banner').value).toBe(
      'Updated',
    );

    await put(chief, '/system/settings', { 'queue.banner': null });
    expect((await get(chief, '/system/settings')).body.data.some((row: { key: string }) => row.key === 'queue.banner')).toBe(
      false,
    );
  });

  it('rejects an empty body or an illegal key', async () => {
    const chief = await superAdmin();
    expect((await put(chief, '/system/settings', {})).status).toBe(422);
    expect((await put(chief, '/system/settings', { 'bad key!': 'x' })).status).toBe(422);
  });

  it('leaves /system/health public', async () => {
    const health = await request(app).get('/api/v1/system/health');
    expect(health.status).toBe(200);
    expect(health.body.data.status).toBe('ok');
  });
});

// ===========================================================================
// 8. Queue monitor (§35) — the board must match the database
// ===========================================================================

describe('GET /queues/:id/monitor', () => {
  it('matches the database after a scripted sequence of staff actions', async () => {
    const service = await setupService(app, { counters: 2 });
    const [one, two] = service.staff;
    const boss = await admin();
    const shoppers = await Promise.all([customer(), customer(), customer(), customer()]);

    const joined = await Promise.all(shoppers.map((who) => join(app, service.serviceId, who)));
    joined.forEach((response) => expect(response.status).toBe(201));
    const queueId = joined[0].body.data.position.queueId ?? joined[0].body.data.ticket.queueId;

    // Clerk one completes the first ticket; clerk two is left mid-service.
    const firstCall = await callNext(app, one, service.serviceId);
    expect(firstCall.status).toBe(200);
    await act(app, one, firstCall.body.data.ticket.id, 'start');
    await act(app, one, firstCall.body.data.ticket.id, 'complete');

    const secondCall = await callNext(app, two, service.serviceId);
    expect(secondCall.status).toBe(200);
    await act(app, two, secondCall.body.data.ticket.id, 'start');

    const monitor = await get(boss, `/queues/${queueId}/monitor`);
    expect(monitor.status).toBe(200);

    const data = monitor.body.data;
    expect(data.service.code).toBe('FIN');
    expect(data.stats).toMatchObject({ waiting: 2, serving: 1, completed: 1, cancelled: 0, skipped: 0, noShow: 0 });
    expect(data.waiting).toHaveLength(2);
    expect(data.serving).toHaveLength(1);
    expect(data.nowServing).toBe(secondCall.body.data.ticket.ticketNumber);

    // Counters: one idle, one holding the ticket it is serving.
    const busy = data.counters.find((row: { currentTicket: string | null }) => row.currentTicket !== null);
    expect(busy.currentTicket).toBe(secondCall.body.data.ticket.ticketNumber);
    expect(busy.staff.id).toBe(two.id);

    // And the board agrees with a direct count of the table behind it.
    const rows = await getDb().query<{ status: string; n: number }>(
      'SELECT status, COUNT(*) AS n FROM queue_tickets WHERE queue_id = ? GROUP BY status',
      [queueId],
    );
    const byStatus = Object.fromEntries(rows.map((row) => [row.status, Number(row.n)]));
    expect(byStatus.waiting).toBe(data.stats.waiting);
    expect(byStatus.completed).toBe(data.stats.completed);
    expect(byStatus.serving).toBe(data.stats.serving);
  });

  it('is closed to customers', async () => {
    const service = await setupService(app, { counters: 1 });
    const shopper = await customer();
    const joined = await join(app, service.serviceId, shopper);
    const queueId = joined.body.data.position.queueId ?? joined.body.data.ticket.queueId;
    expect((await get(shopper, `/queues/${queueId}/monitor`)).status).toBe(403);
  });
});
