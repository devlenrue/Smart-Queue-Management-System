/** Shared scaffolding for the queue-engine tests. */
import request from 'supertest';
import type { Express } from 'express';
import { getDb } from '../../src/db';
import { hashPassword } from '../../src/utils/password';
import { userRepository } from '../../src/repositories/user.repository';
import { assignmentRepository } from '../../src/repositories/assignment.repository';
import { toSqlDateTime } from '../../src/utils/datetime';
import type { Role } from '../../src/types/domain';

export const TEST_PASSWORD = 'Password123';

let phoneCounter = 700_000_000;
const nextPhone = (): string => `+254${++phoneCounter}`;

export interface TestUser {
  id: number;
  email: string;
  token: string;
}

/** Creates a real user (properly hashed password) and signs them in. */
export async function createUserAndLogin(
  app: Express,
  overrides: { role?: Role; email?: string; firstName?: string; lastName?: string } = {},
): Promise<TestUser> {
  const email = overrides.email ?? `u${Date.now()}${Math.floor(Math.random() * 10_000)}@test.local`;
  const id = await userRepository.create({
    firstName: overrides.firstName ?? 'Test',
    lastName: overrides.lastName ?? 'Person',
    email,
    phone: nextPhone(),
    passwordHash: await hashPassword(TEST_PASSWORD),
    role: overrides.role ?? 'customer',
    status: 'active',
  });

  const response = await request(app).post('/api/v1/auth/login').send({ email, password: TEST_PASSWORD });
  if (response.status !== 200) {
    throw new Error(`Test login failed (${response.status}): ${JSON.stringify(response.body)}`);
  }
  return { id, email, token: response.body.data.token };
}

export const bearer = (token: string): string => `Bearer ${token}`;

export interface TestService {
  serviceId: number;
  counterIds: number[];
  staff: TestUser[];
}

/**
 * A service with N counters, each with its own staff member assigned to both
 * the counter and the service — the arrangement every staff action needs.
 */
export async function setupService(
  app: Express,
  options: {
    code?: string;
    name?: string;
    counters?: number;
    averageServiceTime?: number;
    dailyCapacity?: number;
    status?: 'open' | 'closed' | 'inactive';
    maxQueueSize?: number;
    allowCancellation?: boolean;
    allowRejoin?: boolean;
    notificationThreshold?: number;
  } = {},
): Promise<TestService> {
  const stamp = toSqlDateTime();
  const db = getDb();

  const service = await db.execute(
    `INSERT INTO services (name, code, description, category, average_service_time, daily_capacity, status, created_at, updated_at)
     VALUES (?, ?, 'Test service', 'Testing', ?, ?, ?, ?, ?)`,
    [
      options.name ?? 'Finance Office',
      options.code ?? 'FIN',
      options.averageServiceTime ?? 5,
      options.dailyCapacity ?? 200,
      options.status ?? 'open',
      stamp,
      stamp,
    ],
  );
  const serviceId = service.insertId;

  await db.execute(
    `INSERT INTO queue_settings (service_id, max_queue_size, allow_cancellation, allow_rejoin, notification_threshold, estimated_service_time, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      serviceId,
      options.maxQueueSize ?? 100,
      options.allowCancellation === false ? 0 : 1,
      options.allowRejoin === false ? 0 : 1,
      options.notificationThreshold ?? 3,
      options.averageServiceTime ?? 5,
      stamp,
      stamp,
    ],
  );

  const counterIds: number[] = [];
  const staff: TestUser[] = [];

  for (let i = 1; i <= (options.counters ?? 1); i += 1) {
    const member = await createUserAndLogin(app, { role: 'staff', firstName: 'Staff', lastName: `Number${i}` });
    const counter = await db.execute(
      `INSERT INTO service_counters (service_id, counter_number, name, status, assigned_staff_id, created_at, updated_at)
       VALUES (?, ?, ?, 'available', ?, ?, ?)`,
      [serviceId, i, `Counter ${i}`, member.id, stamp, stamp],
    );
    await assignmentRepository.create({ staffId: member.id, serviceId, counterId: counter.insertId });
    counterIds.push(counter.insertId);
    staff.push(member);
  }

  return { serviceId, counterIds, staff };
}

/** POST /services/:id/queue/join as a given user. */
export async function join(app: Express, serviceId: number, user: TestUser) {
  return request(app).post(`/api/v1/services/${serviceId}/queue/join`).set('Authorization', bearer(user.token));
}

export async function callNext(app: Express, staff: TestUser, serviceId: number, counterId?: number) {
  return request(app)
    .post('/api/v1/tickets/call-next')
    .set('Authorization', bearer(staff.token))
    .send(counterId ? { serviceId, counterId } : { serviceId });
}

export async function act(app: Express, user: TestUser, ticketId: number, action: string, body: object = {}) {
  return request(app)
    .post(`/api/v1/tickets/${ticketId}/${action}`)
    .set('Authorization', bearer(user.token))
    .send(body);
}

export async function position(app: Express, user: TestUser, ticketId: number) {
  return request(app).get(`/api/v1/tickets/${ticketId}/position`).set('Authorization', bearer(user.token));
}

/** Clears every queue-related table, leaving users in place. */
export async function clearQueueData(): Promise<void> {
  const db = getDb();
  await db.execute('DELETE FROM notifications');
  await db.execute('DELETE FROM queue_events');
  await db.execute('DELETE FROM queue_tickets');
  await db.execute('DELETE FROM queues');
  await db.execute('DELETE FROM staff_assignments');
  await db.execute('DELETE FROM service_counters');
  await db.execute('DELETE FROM service_hours');
  await db.execute('DELETE FROM queue_settings');
  await db.execute('DELETE FROM services');
  await db.execute('DELETE FROM users');
}
