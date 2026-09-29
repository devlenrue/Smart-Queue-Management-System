import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler';
import { ok } from '../utils/apiResponse';
import { config } from '../config/env';
import { getDb } from '../db';

const router = Router();

/**
 * GET /api/v1/system/health — public liveness + database reachability probe.
 */
router.get(
  '/health',
  asyncHandler(async (_req, res) => {
    let database: 'up' | 'down' = 'down';
    try {
      await getDb().query('SELECT 1 AS ok');
      database = 'up';
    } catch {
      database = 'down';
    }

    ok(res, 'SmartQueue API is running', {
      status: database === 'up' ? 'ok' : 'degraded',
      version: '1.0.0',
      environment: config.env,
      timezone: config.timezone,
      database,
      dialect: config.database.dialect,
      uptimeSeconds: Math.round(process.uptime()),
      time: new Date().toISOString(),
    });
  }),
);

export default router;
