/**
 * Phase 3 verification — registration, login, sessions and authorisation.
 */
import request from 'supertest';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { closeDatabase, freshDatabase } from './helpers/db';
import { getDb } from '../src/db';
import { hashPassword } from '../src/utils/password';
import { userRepository } from '../src/repositories/user.repository';

let app: Express;

const validRegistration = {
  firstName: 'John',
  lastName: 'Doe',
  email: 'john.doe@example.com',
  phone: '+254712345678',
  password: 'Password123',
  confirmPassword: 'Password123',
};

beforeAll(async () => {
  await freshDatabase();
  app = createApp();
});

afterAll(async () => {
  await closeDatabase();
});

beforeEach(async () => {
  await getDb().execute('DELETE FROM revoked_tokens');
  await getDb().execute('DELETE FROM users');
});

async function seedUser(overrides: Partial<{ email: string; role: string; status: string; password: string }> = {}) {
  const password = overrides.password ?? 'Password123';
  const id = await userRepository.create({
    firstName: 'Test',
    lastName: 'Person',
    email: overrides.email ?? 'person@example.com',
    phone: `+2547${Math.floor(10_000_000 + Math.random() * 80_000_000)}`,
    passwordHash: await hashPassword(password),
    role: (overrides.role ?? 'customer') as 'customer',
    status: (overrides.status ?? 'active') as 'active',
  });
  return { id, email: overrides.email ?? 'person@example.com', password };
}

async function login(email: string, password: string): Promise<string> {
  const response = await request(app).post('/api/v1/auth/login').send({ email, password });
  return response.body.data.token as string;
}

describe('POST /api/v1/auth/register', () => {
  it('creates a customer and returns a token', async () => {
    const response = await request(app).post('/api/v1/auth/register').send(validRegistration);

    expect(response.status).toBe(201);
    expect(response.body.success).toBe(true);
    expect(response.body.message).toBe('Registration successful');
    expect(typeof response.body.data.token).toBe('string');
    expect(response.body.data.user).toMatchObject({
      firstName: 'John',
      lastName: 'Doe',
      email: 'john.doe@example.com',
      role: 'customer',
      status: 'active',
    });
  });

  it('never returns the password hash', async () => {
    const response = await request(app).post('/api/v1/auth/register').send(validRegistration);
    expect(JSON.stringify(response.body)).not.toContain('password_hash');
    expect(JSON.stringify(response.body)).not.toContain('$2a$');
  });

  it('stores the password hashed, not in plain text', async () => {
    await request(app).post('/api/v1/auth/register').send(validRegistration);
    const row = await userRepository.findByEmail('john.doe@example.com');
    expect(row).not.toBeNull();
    expect(row?.password_hash).not.toBe('Password123');
    expect(row?.password_hash.startsWith('$2')).toBe(true);
  });

  it('rejects a duplicate email with 409', async () => {
    await request(app).post('/api/v1/auth/register').send(validRegistration);
    const response = await request(app)
      .post('/api/v1/auth/register')
      .send({ ...validRegistration, phone: '+254799999999' });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('EMAIL_TAKEN');
  });

  it('rejects a duplicate phone with 409', async () => {
    await request(app).post('/api/v1/auth/register').send(validRegistration);
    const response = await request(app)
      .post('/api/v1/auth/register')
      .send({ ...validRegistration, email: 'other@example.com' });

    expect(response.status).toBe(409);
    expect(response.body.code).toBe('PHONE_TAKEN');
  });

  it.each([
    ['a missing first name', { firstName: '' }, 'firstName'],
    ['an invalid email', { email: 'not-an-email' }, 'email'],
    ['an invalid phone', { phone: 'abc' }, 'phone'],
    ['a short password', { password: 'Ab1', confirmPassword: 'Ab1' }, 'password'],
    ['a password with no digit', { password: 'Password', confirmPassword: 'Password' }, 'password'],
    ['a mismatched confirmation', { confirmPassword: 'Different123' }, 'confirmPassword'],
  ])('rejects %s with 422', async (_label, patch, field) => {
    const response = await request(app)
      .post('/api/v1/auth/register')
      .send({ ...validRegistration, ...patch });

    expect(response.status).toBe(422);
    expect(response.body.code).toBe('VALIDATION_ERROR');
    expect(response.body.errors.map((e: { field: string }) => e.field)).toContain(field);
  });

  it('ignores an attempt to self-assign a privileged role', async () => {
    const response = await request(app)
      .post('/api/v1/auth/register')
      .send({ ...validRegistration, role: 'super_admin' });

    expect(response.status).toBe(201);
    expect(response.body.data.user.role).toBe('customer');
  });
});

describe('POST /api/v1/auth/login', () => {
  it('returns a token for valid credentials', async () => {
    const user = await seedUser({ email: 'valid@example.com' });
    const response = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: user.password });

    expect(response.status).toBe(200);
    expect(response.body.data.token).toBeDefined();
    expect(response.body.data.user.email).toBe('valid@example.com');
  });

  it('rejects a wrong password with 401', async () => {
    const user = await seedUser({ email: 'wrong@example.com' });
    const response = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: 'Nope12345' });

    expect(response.status).toBe(401);
    expect(response.body.code).toBe('INVALID_CREDENTIALS');
  });

  it('gives an identical answer for an unknown email, to prevent enumeration', async () => {
    const user = await seedUser({ email: 'known@example.com' });
    const wrongPassword = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: 'Nope12345' });
    const unknownEmail = await request(app).post('/api/v1/auth/login').send({ email: 'ghost@example.com', password: 'Nope12345' });

    expect(unknownEmail.status).toBe(wrongPassword.status);
    expect(unknownEmail.body.message).toBe(wrongPassword.body.message);
    expect(unknownEmail.body.code).toBe(wrongPassword.body.code);
  });

  it('refuses a suspended account with 403', async () => {
    const user = await seedUser({ email: 'suspended@example.com', status: 'suspended' });
    const response = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: user.password });

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('ACCOUNT_SUSPENDED');
  });

  it('refuses an inactive account with 403', async () => {
    const user = await seedUser({ email: 'inactive@example.com', status: 'inactive' });
    const response = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: user.password });

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('ACCOUNT_INACTIVE');
  });
});

describe('GET /api/v1/auth/me', () => {
  it('returns the signed-in user', async () => {
    const user = await seedUser({ email: 'me@example.com' });
    const token = await login(user.email, user.password);

    const response = await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
    expect(response.status).toBe(200);
    expect(response.body.data.email).toBe('me@example.com');
  });

  it('rejects a request with no token', async () => {
    const response = await request(app).get('/api/v1/auth/me');
    expect(response.status).toBe(401);
    expect(response.body.code).toBe('UNAUTHENTICATED');
  });

  it('rejects a malformed token', async () => {
    const response = await request(app).get('/api/v1/auth/me').set('Authorization', 'Bearer not.a.jwt');
    expect(response.status).toBe(401);
  });

  it('rejects a token whose user was deleted', async () => {
    const user = await seedUser({ email: 'ghosted@example.com' });
    const token = await login(user.email, user.password);
    await userRepository.remove(user.id);

    const response = await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
    expect(response.status).toBe(401);
  });

  it('rejects a token belonging to a now-suspended account', async () => {
    const user = await seedUser({ email: 'later-suspended@example.com' });
    const token = await login(user.email, user.password);
    await userRepository.updateStatus(user.id, 'suspended');

    const response = await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
    expect(response.status).toBe(403);
    expect(response.body.code).toBe('ACCOUNT_SUSPENDED');
  });
});

describe('POST /api/v1/auth/logout', () => {
  it('revokes the token so it cannot be replayed', async () => {
    const user = await seedUser({ email: 'logout@example.com' });
    const token = await login(user.email, user.password);

    const before = await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
    expect(before.status).toBe(200);

    const logout = await request(app).post('/api/v1/auth/logout').set('Authorization', `Bearer ${token}`);
    expect(logout.status).toBe(200);

    const after = await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
    expect(after.status).toBe(401);
    expect(after.body.code).toBe('TOKEN_REVOKED');
  });

  it('leaves other sessions of the same user working', async () => {
    const user = await seedUser({ email: 'two-sessions@example.com' });
    const tokenA = await login(user.email, user.password);
    const tokenB = await login(user.email, user.password);

    await request(app).post('/api/v1/auth/logout').set('Authorization', `Bearer ${tokenA}`);

    const stillValid = await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${tokenB}`);
    expect(stillValid.status).toBe(200);
  });
});

describe('profile and password', () => {
  it('updates the profile', async () => {
    const user = await seedUser({ email: 'profile@example.com' });
    const token = await login(user.email, user.password);

    const response = await request(app)
      .put('/api/v1/profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ firstName: 'Updated', lastName: 'Name' });

    expect(response.status).toBe(200);
    expect(response.body.data.fullName).toBe('Updated Name');
  });

  it('changes the password and invalidates the old one', async () => {
    const user = await seedUser({ email: 'pwd@example.com' });
    const token = await login(user.email, user.password);

    const change = await request(app)
      .post('/api/v1/auth/change-password')
      .set('Authorization', `Bearer ${token}`)
      .send({ currentPassword: user.password, newPassword: 'BrandNew123', confirmPassword: 'BrandNew123' });
    expect(change.status).toBe(200);

    const oldLogin = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: user.password });
    expect(oldLogin.status).toBe(401);

    const newLogin = await request(app).post('/api/v1/auth/login').send({ email: user.email, password: 'BrandNew123' });
    expect(newLogin.status).toBe(200);
  });

  it('rejects a wrong current password', async () => {
    const user = await seedUser({ email: 'pwd2@example.com' });
    const token = await login(user.email, user.password);

    const response = await request(app)
      .post('/api/v1/auth/change-password')
      .set('Authorization', `Bearer ${token}`)
      .send({ currentPassword: 'WrongOne123', newPassword: 'BrandNew123', confirmPassword: 'BrandNew123' });

    expect(response.status).toBe(422);
    expect(response.body.errors[0].field).toBe('currentPassword');
  });
});

describe('role-based access control', () => {
  it('lets an admin through an admin-only guard', async () => {
    const { requireRole } = await import('../src/middleware/rbac');
    const next = jest.fn();
    const handler = requireRole('admin', 'super_admin');
    handler({ user: { role: 'admin' } } as never, {} as never, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('blocks a customer at an admin-only guard with 403', async () => {
    const { requireRole } = await import('../src/middleware/rbac');
    const next = jest.fn();
    const handler = requireRole('admin', 'super_admin');
    handler({ user: { role: 'customer' } } as never, {} as never, next);
    const error = next.mock.calls[0][0] as { statusCode: number; code: string };
    expect(error.statusCode).toBe(403);
    expect(error.code).toBe('FORBIDDEN');
  });

  it('blocks an unauthenticated request at any guard with 401', async () => {
    const { requireRole } = await import('../src/middleware/rbac');
    const next = jest.fn();
    requireRole('customer')({} as never, {} as never, next);
    const error = next.mock.calls[0][0] as { statusCode: number };
    expect(error.statusCode).toBe(401);
  });
});
