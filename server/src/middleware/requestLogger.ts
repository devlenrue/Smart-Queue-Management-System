import type { RequestHandler } from 'express';
import { logger } from '../utils/logger';
import { config } from '../config/env';

/** Minimal request log: method, path, status, duration. No bodies, no tokens. */
export const requestLogger: RequestHandler = (req, res, next) => {
  if (config.isTest) return next();
  const startedAt = process.hrtime.bigint();
  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
    logger.debug(`${req.method} ${req.originalUrl} ${res.statusCode} ${ms.toFixed(1)}ms`);
  });
  next();
};
