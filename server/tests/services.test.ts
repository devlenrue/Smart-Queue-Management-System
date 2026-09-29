/**
 * Phase 4 verification — the service catalogue (§15, §28, §30) and the
 * admin-only configuration behind it.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { bearer, clearQueueData, createUserAndLogin, join, setupService } from './helpers/api';
import { getDb } from '../src/db';

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

const validService = {
  name: 'Examinations Office',
  code: 'EXM',
  description: 'Transcripts and result slips',
  category: 'Academic',
  averageServiceTime: 7,
  dailyCapacity: 150,
};

describe('browsing the catalogue', () => {
  it('is readable without signing in', async () => {
    await setupService(app, { code: 'FIN', name: 'Finance Office' });
    const response = await request(app).get('/api/v1/services');

    expect(response.status).toBe(200);
    expect(response.body.data).toHaveLength(1);
    expect(response.body.data[0].code).toBe('FIN');
  });

  it('attaches live queue figures to every service (§15)', async () => {
    const { serviceId } = await setupService(app, { averageServiceTime: 5, counters: 2 });
    await join(app, serviceId, await createUserAndLogin(app));
    await join(app, serviceId, await createUserAndLogin(app));

    const response = await request(app).get('/api/v1/services');
    const service = response.body.data[0];

    expect(service.queue.waitingCount).toBe(2);
    expect(service.queue.activeCounters).toBe(2);
    expect(service.queue.isAcceptingTickets).toBe(true);
    expect(service.queue.capacityRemaining).toBe(98);
    expect(service.queue.nowServing).toBeNull();
  });

  it('paginates and reports the totals', async () => {
    for (const code of ['AAA', 'BBB', 'CCC']) await setupService(app, { code, name: `Service ${code}` });

    const response = await request(app).get('/api/v1/services?page=1&limit=2');

    expect(response.body.data).toHaveLength(2);
    expect(response.body.meta).toEqual({ page: 1, limit: 2, total: 3, totalPages: 2 });
  });

  it('searches by name and by code (§39)', async () => {
    await setupService(app, { code: 'FIN', name: 'Finance Office' });
    await setupService(app, { code: 'LIB', name: 'Library Desk' });

    const byName = await request(app).get('/api/v1/services?search=librar');
    const byCode = await request(app).get('/api/v1/services?search=FIN');

    expect(byName.body.data.map((s: { code: string }) => s.code)).toEqual(['LIB']);
    expect(byCode.body.data.map((s: { code: string }) => s.code)).toEqual(['FIN']);
  });

  it('filters by status', async () => {
    await setupService(app, { code: 'OPN', status: 'open' });
    await setupService(app, { code: 'CLS', status: 'closed' });

    const response = await request(app).get('/api/v1/services?status=closed');
    expect(response.body.data.map((s: { code: string }) => s.code)).toEqual(['CLS']);
  });

  it('lists the distinct categories', async () => {
    await setupService(app, { code: 'AAA' });
    const response = await request(app).get('/api/v1/services/categories');

    expect(response.status).toBe(200);
    expect(response.body.data).toContain('Testing');
  });

  it('returns 404 for an unknown service', async () => {
    const response = await request(app).get('/api/v1/services/999999');
    expect(response.status).toBe(404);
  });

  it('gives staff the detailed view and customers the plain one', async () => {
    const { serviceId } = await setupService(app, { counters: 2 });
    const staffMember = await createUserAndLogin(app, { role: 'staff' });
    const customer = await createUserAndLogin(app);

    const forStaff = await request(app)
      .get(`/api/v1/services/${serviceId}`)
      .set('Authorization', bearer(staffMember.token));
    const forCustomer = await request(app)
      .get(`/api/v1/services/${serviceId}`)
      .set('Authorization', bearer(customer.token));

    expect(forStaff.body.data.counters).toHaveLength(2);
    expect(forStaff.body.data.settings).toBeDefined();
    expect(forCustomer.body.data.counters).toBeUndefined();
    expect(forCustomer.body.data.queue).toBeDefined();
  });
});

describe('managing services', () => {
  it('lets an admin create a service with its default settings', async () => {
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(admin.token))
      .send(validService);

    expect(response.status).toBe(201);
    expect(response.body.data.code).toBe('EXM');
    expect(response.body.data.settings.estimatedServiceTime).toBe(7);

    const settings = await getDb().query<{ n: number }>(
      'SELECT COUNT(*) AS n FROM queue_settings WHERE service_id = ?',
      [response.body.data.id],
    );
    expect(Number(settings[0].n)).toBe(1);
  });

  it('upper-cases the code', async () => {
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const response = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(admin.token))
      .send({ ...validService, code: 'exm' });

    expect(response.body.data.code).toBe('EXM');
  });

  it('refuses a duplicate code', async () => {
    const admin = await createUserAndLogin(app, { role: 'admin' });
    await request(app).post('/api/v1/services').set('Authorization', bearer(admin.token)).send(validService);

    const second = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(admin.token))
      .send({ ...validService, name: 'Another Office' });

    expect(second.status).toBe(409);
    expect(second.body.code).toBe('SERVICE_CODE_TAKEN');
  });

  it.each([
    ['a missing name', { ...validService, name: undefined }],
    ['a two-character name', { ...validService, name: 'Ex' }],
    ['a one-character code', { ...validService, code: 'E' }],
    ['a code with punctuation', { ...validService, code: 'EX-M' }],
    ['a zero service time', { ...validService, averageServiceTime: 0 }],
    ['a negative capacity', { ...validService, dailyCapacity: -5 }],
    ['an unknown status', { ...validService, status: 'sleeping' }],
  ])('rejects %s', async (_label, payload) => {
    const admin = await createUserAndLogin(app, { role: 'admin' });
    const response = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(admin.token))
      .send(payload);

    expect(response.status).toBe(422);
    expect(response.body.code).toBe('VALIDATION_ERROR');
    expect(response.body.errors.length).toBeGreaterThan(0);
  });

  it('blocks a customer from creating a service', async () => {
    const customer = await createUserAndLogin(app);
    const response = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(customer.token))
      .send(validService);

    expect(response.status).toBe(403);
  });

  it('blocks staff from creating a service', async () => {
    const staffMember = await createUserAndLogin(app, { role: 'staff' });
    const response = await request(app)
      .post('/api/v1/services')
      .set('Authorization', bearer(staffMember.token))
      .send(validService);

    expect(response.status).toBe(403);
  });

  it('updates a service', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/services/${serviceId}`)
      .set('Authorization', bearer(admin.token))
      .send({ name: 'Bursary Office', averageServiceTime: 12 });

    expect(response.status).toBe(200);
    expect(response.body.data.name).toBe('Bursary Office');
    expect(response.body.data.averageServiceTime).toBe(12);
  });

  it('deactivates rather than deletes, so history survives', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .delete(`/api/v1/services/${serviceId}`)
      .set('Authorization', bearer(admin.token));

    expect(response.status).toBe(200);
    expect(response.body.data.status).toBe('inactive');

    const rows = await getDb().query<{ n: number }>('SELECT COUNT(*) AS n FROM services WHERE id = ?', [serviceId]);
    expect(Number(rows[0].n)).toBe(1);
  });

  it('reserves a hard delete for a super administrator', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const refused = await request(app)
      .delete(`/api/v1/services/${serviceId}?hard=true`)
      .set('Authorization', bearer(admin.token));
    expect(refused.status).toBe(403);

    const superAdmin = await createUserAndLogin(app, { role: 'super_admin' });
    const allowed = await request(app)
      .delete(`/api/v1/services/${serviceId}?hard=true`)
      .set('Authorization', bearer(superAdmin.token));
    expect(allowed.status).toBe(204);

    const rows = await getDb().query<{ n: number }>('SELECT COUNT(*) AS n FROM services WHERE id = ?', [serviceId]);
    expect(Number(rows[0].n)).toBe(0);
  });

  it('hides an inactive service from joining', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    await request(app).delete(`/api/v1/services/${serviceId}`).set('Authorization', bearer(admin.token));

    const response = await join(app, serviceId, await createUserAndLogin(app));
    expect(response.body.code).toBe('SERVICE_INACTIVE');
  });
});

describe('opening hours and queue settings', () => {
  it('replaces the weekly timetable', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(admin.token))
      .send({
        hours: [
          { dayOfWeek: 1, openingTime: '08:00', closingTime: '17:00', status: 'open' },
          { dayOfWeek: 6, openingTime: '09:00', closingTime: '12:00', status: 'closed' },
        ],
      });

    expect(response.status).toBe(200);
    expect(response.body.data).toHaveLength(2);
    expect(response.body.data[0]).toMatchObject({ dayOfWeek: 1, dayName: 'Monday', openingTime: '08:00' });
    expect(response.body.data[1].status).toBe('closed');
  });

  it('rejects a closing time that is not after the opening time', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(admin.token))
      .send({ hours: [{ dayOfWeek: 1, openingTime: '17:00', closingTime: '08:00', status: 'open' }] });

    expect(response.status).toBe(422);
  });

  it('rejects a malformed time', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const response = await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(admin.token))
      .send({ hours: [{ dayOfWeek: 1, openingTime: '8am', closingTime: '17:00', status: 'open' }] });

    expect(response.status).toBe(422);
  });

  it('publishes the timetable to anyone', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });
    await request(app)
      .put(`/api/v1/services/${serviceId}/hours`)
      .set('Authorization', bearer(admin.token))
      .send({ hours: [{ dayOfWeek: 3, openingTime: '08:30', closingTime: '16:30', status: 'open' }] });

    const response = await request(app).get(`/api/v1/services/${serviceId}/hours`);
    expect(response.status).toBe(200);
    expect(response.body.data[0].dayName).toBe('Wednesday');
  });

  it('changes queue settings and the engine obeys immediately', async () => {
    const { serviceId } = await setupService(app);
    const admin = await createUserAndLogin(app, { role: 'admin' });

    const updated = await request(app)
      .put(`/api/v1/services/${serviceId}/settings`)
      .set('Authorization', bearer(admin.token))
      .send({ maxQueueSize: 1, allowCancellation: false });

    expect(updated.body.data.maxQueueSize).toBe(1);
    expect(updated.body.data.allowCancellation).toBe(false);

    expect((await join(app, serviceId, await createUserAndLogin(app))).status).toBe(201);
    const refused = await join(app, serviceId, await createUserAndLogin(app));
    expect(refused.body.code).toBe('QUEUE_FULL');
  });

  it('keeps queue settings away from customers', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);

    const response = await request(app)
      .get(`/api/v1/services/${serviceId}/settings`)
      .set('Authorization', bearer(customer.token));

    expect(response.status).toBe(403);
  });
});
