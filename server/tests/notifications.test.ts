/**
 * The notification inbox and the public announcement feed (§37, §38) —
 * the two endpoint groups the customer app depends on.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { act, bearer, callNext, clearQueueData, createUserAndLogin, join, setupService } from './helpers/api';
import { getDb } from '../src/db';
import { toSqlDateTime } from '../src/utils/datetime';

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
  await getDb().execute('DELETE FROM announcements');
});

async function seedAnnouncement(overrides: Partial<{
  title: string;
  content: string;
  serviceId: number | null;
  status: string;
  publishedAt: string | null;
  expiresAt: string | null;
}> = {}): Promise<number> {
  const stamp = toSqlDateTime();
  const result = await getDb().execute(
    `INSERT INTO announcements (title, content, service_id, created_by, published_at, expires_at, status, created_at, updated_at)
     VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?)`,
    [
      overrides.title ?? 'Systems maintenance',
      overrides.content ?? 'The portal will be unavailable on Saturday morning.',
      overrides.serviceId ?? null,
      overrides.publishedAt === undefined ? stamp : overrides.publishedAt,
      overrides.expiresAt ?? null,
      overrides.status ?? 'published',
      stamp,
      stamp,
    ],
  );
  return result.insertId;
}

describe('the notification inbox', () => {
  it('requires a signed-in user', async () => {
    const response = await request(app).get('/api/v1/notifications');
    expect(response.status).toBe(401);
  });

  it('returns the notifications the queue engine produced', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);

    const response = await request(app).get('/api/v1/notifications').set('Authorization', bearer(customer.token));

    expect(response.status).toBe(200);
    expect(response.body.data.notifications).toHaveLength(1);
    expect(response.body.data.notifications[0]).toMatchObject({
      title: 'Ticket FIN-001 issued',
      type: 'queue',
      isRead: false,
    });
    expect(response.body.data.unreadCount).toBe(1);
    expect(response.body.meta.total).toBe(1);
  });

  it('never leaks another customer\'s notifications', async () => {
    const { serviceId } = await setupService(app);
    const first = await createUserAndLogin(app);
    const second = await createUserAndLogin(app);
    await join(app, serviceId, first);

    const response = await request(app).get('/api/v1/notifications').set('Authorization', bearer(second.token));

    expect(response.body.data.notifications).toHaveLength(0);
    expect(response.body.data.unreadCount).toBe(0);
  });

  it('accumulates one notification per step of the journey', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    const ticket = await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);
    await act(app, staff[0], ticket.body.data.ticket.id, 'start');
    await act(app, staff[0], ticket.body.data.ticket.id, 'complete');

    const response = await request(app).get('/api/v1/notifications').set('Authorization', bearer(customer.token));
    const titles = response.body.data.notifications.map((n: { title: string }) => n.title);

    expect(titles).toContain('Ticket FIN-001 issued');
    expect(titles).toContain('Ticket FIN-001 is being called');
    expect(titles).toContain('Service completed');
  });

  it('orders newest first', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);

    const response = await request(app).get('/api/v1/notifications').set('Authorization', bearer(customer.token));
    expect(response.body.data.notifications[0].title).toContain('being called');
  });

  it('filters by read state and by type', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);

    const unread = await request(app)
      .get('/api/v1/notifications?isRead=false')
      .set('Authorization', bearer(customer.token));
    const read = await request(app)
      .get('/api/v1/notifications?isRead=true')
      .set('Authorization', bearer(customer.token));
    const byType = await request(app)
      .get('/api/v1/notifications?type=system')
      .set('Authorization', bearer(customer.token));

    expect(unread.body.data.notifications).toHaveLength(1);
    expect(read.body.data.notifications).toHaveLength(0);
    expect(byType.body.data.notifications).toHaveLength(0);
  });

  it('rejects a nonsense isRead value', async () => {
    const customer = await createUserAndLogin(app);
    const response = await request(app)
      .get('/api/v1/notifications?isRead=maybe')
      .set('Authorization', bearer(customer.token));
    expect(response.status).toBe(422);
  });

  it('reports the unread count on its own endpoint', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);

    const response = await request(app)
      .get('/api/v1/notifications/unread-count')
      .set('Authorization', bearer(customer.token));

    expect(response.status).toBe(200);
    expect(response.body.data.count).toBe(1);
  });

  it('marks one notification as read', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);
    const list = await request(app).get('/api/v1/notifications').set('Authorization', bearer(customer.token));
    const id = list.body.data.notifications[0].id;

    const response = await request(app)
      .patch(`/api/v1/notifications/${id}/read`)
      .set('Authorization', bearer(customer.token));

    expect(response.status).toBe(200);
    expect(response.body.data.isRead).toBe(true);

    const after = await request(app)
      .get('/api/v1/notifications/unread-count')
      .set('Authorization', bearer(customer.token));
    expect(after.body.data.count).toBe(0);
  });

  it('is idempotent when marking the same one twice', async () => {
    const { serviceId } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);
    const list = await request(app).get('/api/v1/notifications').set('Authorization', bearer(customer.token));
    const id = list.body.data.notifications[0].id;

    await request(app).patch(`/api/v1/notifications/${id}/read`).set('Authorization', bearer(customer.token));
    const second = await request(app)
      .patch(`/api/v1/notifications/${id}/read`)
      .set('Authorization', bearer(customer.token));

    expect(second.status).toBe(200);
    expect(second.body.data.isRead).toBe(true);
  });

  it('refuses to mark somebody else\'s notification', async () => {
    const { serviceId } = await setupService(app);
    const owner = await createUserAndLogin(app);
    const stranger = await createUserAndLogin(app);
    await join(app, serviceId, owner);
    const list = await request(app).get('/api/v1/notifications').set('Authorization', bearer(owner.token));
    const id = list.body.data.notifications[0].id;

    const response = await request(app)
      .patch(`/api/v1/notifications/${id}/read`)
      .set('Authorization', bearer(stranger.token));

    expect(response.status).toBe(404);
  });

  it('marks everything read in one call', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);

    const response = await request(app)
      .patch('/api/v1/notifications/read-all')
      .set('Authorization', bearer(customer.token));

    expect(response.status).toBe(200);
    expect(response.body.data.updated).toBe(2);
    expect(response.body.data.unread).toBe(0);
  });

  it('paginates', async () => {
    const { serviceId, staff } = await setupService(app);
    const customer = await createUserAndLogin(app);
    await join(app, serviceId, customer);
    await callNext(app, staff[0], serviceId);

    const response = await request(app)
      .get('/api/v1/notifications?page=1&limit=1')
      .set('Authorization', bearer(customer.token));

    expect(response.body.data.notifications).toHaveLength(1);
    expect(response.body.meta).toMatchObject({ page: 1, limit: 1, total: 2, totalPages: 2 });
  });
});

describe('the announcement feed', () => {
  it('is readable without an account', async () => {
    await seedAnnouncement({ title: 'Graduation ceremony' });
    const response = await request(app).get('/api/v1/announcements');

    expect(response.status).toBe(200);
    expect(response.body.data).toHaveLength(1);
    expect(response.body.data[0]).toMatchObject({ title: 'Graduation ceremony', isGlobal: true });
  });

  it('hides drafts and archived items', async () => {
    await seedAnnouncement({ title: 'Draft one', status: 'draft', publishedAt: null });
    await seedAnnouncement({ title: 'Archived one', status: 'archived' });
    await seedAnnouncement({ title: 'Live one', status: 'published' });

    const response = await request(app).get('/api/v1/announcements');
    expect(response.body.data.map((a: { title: string }) => a.title)).toEqual(['Live one']);
  });

  it('hides an announcement whose expiry has passed', async () => {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    await seedAnnouncement({ title: 'Expired', expiresAt: toSqlDateTime(yesterday) });
    await seedAnnouncement({ title: 'Still valid' });

    const response = await request(app).get('/api/v1/announcements');
    expect(response.body.data.map((a: { title: string }) => a.title)).toEqual(['Still valid']);
  });

  it('hides an announcement scheduled for the future', async () => {
    const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
    await seedAnnouncement({ title: 'Scheduled', publishedAt: toSqlDateTime(tomorrow) });

    const response = await request(app).get('/api/v1/announcements');
    expect(response.body.data).toHaveLength(0);
  });

  it('returns global plus service announcements when filtered by service', async () => {
    const { serviceId } = await setupService(app);
    const other = await setupService(app, { code: 'OTH' });
    await seedAnnouncement({ title: 'Everyone' });
    await seedAnnouncement({ title: 'Finance only', serviceId });
    await seedAnnouncement({ title: 'Other only', serviceId: other.serviceId });

    const response = await request(app).get(`/api/v1/announcements?serviceId=${serviceId}`);
    const titles = response.body.data.map((a: { title: string }) => a.title).sort();

    expect(titles).toEqual(['Everyone', 'Finance only']);
  });

  it('names the service an announcement belongs to', async () => {
    const { serviceId } = await setupService(app, { code: 'FIN', name: 'Finance Office' });
    await seedAnnouncement({ title: 'Finance notice', serviceId });

    const response = await request(app).get('/api/v1/announcements');
    expect(response.body.data[0]).toMatchObject({
      serviceName: 'Finance Office',
      serviceCode: 'FIN',
      isGlobal: false,
    });
  });

  it('returns 404 for an unpublished announcement fetched directly', async () => {
    const id = await seedAnnouncement({ status: 'draft', publishedAt: null });
    const response = await request(app).get(`/api/v1/announcements/${id}`);
    expect(response.status).toBe(404);
  });
});
