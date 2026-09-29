/**
 * Phase 9 — HTTP hardening.
 *
 * Everything here is middleware that never shows up in a feature test because
 * it works by *not* happening: security headers, CORS, and the three rate
 * limiters. The limiters are skipped under NODE_ENV=test everywhere else, so
 * this file switches them back on before the app is built — which is why it
 * requires the app lazily instead of importing it at the top.
 *
 * Each test uses its own X-Forwarded-For address so the per-IP counters stay
 * independent and the file has no ordering dependencies (`trust proxy` is 1,
 * so the header is what express-rate-limit keys on).
 */
import request from 'supertest';
import type { Express } from 'express';

process.env.RATE_LIMIT_IN_TESTS = 'true';
process.env.RATE_LIMIT_AUTH_MAX = '3';
process.env.RATE_LIMIT_JOIN_MAX = '2';
process.env.RATE_LIMIT_API_MAX = '40';
process.env.CORS_ORIGIN = 'https://queue.example.ac.ke';

/* eslint-disable @typescript-eslint/no-var-requires */
const { createApp } = require('../src/app') as typeof import('../src/app');
const { config } = require('../src/config/env') as typeof import('../src/config/env');
const { freshDatabase, closeDatabase } = require('./helpers/db') as typeof import('./helpers/db');
const { createUserAndLogin, setupService, bearer, TEST_PASSWORD } =
  require('./helpers/api') as typeof import('./helpers/api');
/* eslint-enable @typescript-eslint/no-var-requires */

let app: Express;

beforeAll(async () => {
  await freshDatabase();
  app = createApp();
});

afterAll(async () => {
  await closeDatabase();
});

/** A fresh client address, so one test's limit never leaks into another's. */
const from = (last: number) => ({ 'X-Forwarded-For': `10.1.0.${last}` });

describe('the limiters are actually enabled in this file', () => {
  it('reads the opt-in flag', () => {
    expect(config.rateLimit.enforceInTests).toBe(true);
    expect(config.rateLimit.authMax).toBe(3);
  });
});

describe('security headers', () => {
  it('sets the helmet defaults and hides the server technology', async () => {
    const response = await request(app).get('/api/v1/system/health').set(from(1));

    expect(response.status).toBe(200);
    expect(response.headers['x-content-type-options']).toBe('nosniff');
    expect(response.headers['x-frame-options']).toBeDefined();
    expect(response.headers['x-dns-prefetch-control']).toBeDefined();
    expect(response.headers['strict-transport-security']).toContain('max-age=');
    expect(response.headers['x-powered-by']).toBeUndefined();
  });
});

describe('CORS', () => {
  it('answers a preflight for the configured origin', async () => {
    const response = await request(app)
      .options('/api/v1/services')
      .set(from(2))
      .set('Origin', 'https://queue.example.ac.ke')
      .set('Access-Control-Request-Method', 'POST');

    expect(response.status).toBeLessThan(300);
    expect(response.headers['access-control-allow-origin']).toBe('https://queue.example.ac.ke');
    expect(response.headers['access-control-allow-methods']).toContain('PATCH');
    expect(response.headers['access-control-allow-headers']).toContain('Authorization');
  });

  it('does not echo an origin that is not on the allow-list', async () => {
    const response = await request(app)
      .get('/api/v1/services')
      .set(from(3))
      .set('Origin', 'https://not-us.example.com');

    // The request still succeeds — a browser, not the server, enforces CORS —
    // but no allow-origin header is handed back, so the browser blocks it.
    expect(response.status).toBe(200);
    expect(response.headers['access-control-allow-origin']).toBeUndefined();
  });
});

describe('rate limiting', () => {
  it('stops a password-guessing run on /auth/login (429 RATE_LIMITED)', async () => {
    const attempt = () =>
      request(app)
        .post('/api/v1/auth/login')
        .set(from(10))
        .send({ email: 'victim@test.local', password: 'wrong-guess' });

    // RATE_LIMIT_AUTH_MAX is 3 in this file.
    for (let i = 0; i < 3; i += 1) {
      expect((await attempt()).status).toBe(401);
    }

    const blocked = await attempt();
    expect(blocked.status).toBe(429);
    expect(blocked.body).toEqual({
      success: false,
      message: expect.any(String),
      code: 'RATE_LIMITED',
      errors: [],
    });
  });

  it('advertises the limit in standard headers so a client can back off', async () => {
    const response = await request(app).post('/api/v1/auth/login').set(from(11)).send({
      email: 'someone@test.local',
      password: TEST_PASSWORD,
    });

    expect(response.headers['ratelimit-limit']).toBe('3');
    expect(response.headers['ratelimit-remaining']).toBe('2');
    expect(response.headers['x-ratelimit-limit']).toBeUndefined();
  });

  it('caps repeated queue joins (Rule 8 is about the queue, this is about the client)', async () => {
    const { serviceId } = await setupService(app, { code: 'SEC', maxQueueSize: 50 });
    const shopper = await createUserAndLogin(app);
    const attempt = () =>
      request(app)
        .post(`/api/v1/services/${serviceId}/queue/join`)
        .set(from(12))
        .set('Authorization', bearer(shopper.token));

    expect((await attempt()).status).toBe(201);
    // Second attempt is refused by the queue engine (Rule 1), not the limiter…
    expect((await attempt()).status).toBe(409);
    // …and the third trips RATE_LIMIT_JOIN_MAX = 2.
    const blocked = await attempt();
    expect(blocked.status).toBe(429);
    expect(blocked.body.code).toBe('RATE_LIMITED');
  });

  it('has a backstop across the rest of the API', async () => {
    const hit = () => request(app).get('/api/v1/system/health').set(from(13));

    for (let i = 0; i < 40; i += 1) {
      expect((await hit()).status).toBe(200);
    }

    const blocked = await hit();
    expect(blocked.status).toBe(429);
    expect(blocked.body.code).toBe('RATE_LIMITED');
  });

  it('counts each client separately', async () => {
    // 10.1.0.13 is exhausted by the test above; a different address is not.
    expect((await request(app).get('/api/v1/system/health').set(from(14))).status).toBe(200);
  });
});
