import rateLimit, { type RateLimitRequestHandler } from 'express-rate-limit';
import { config } from '../config/env';
import type { ErrorBodyShape } from '../types/errors';

const limitedBody: ErrorBodyShape = {
  success: false,
  message: 'Too many requests. Please wait a moment and try again.',
  code: 'RATE_LIMITED',
  errors: [],
};

function build(max: number): RateLimitRequestHandler {
  return rateLimit({
    windowMs: config.rateLimit.windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    // Limits would make the test suite flaky and mean nothing there.
    skip: () => config.isTest,
    handler: (_req, res) => {
      res.status(429).json(limitedBody);
    },
  });
}

/** Brute-force protection on the credential endpoints. */
export const authLimiter = build(config.rateLimit.authMax);

/** Stops a stuck client from spamming the queue with join attempts. */
export const joinLimiter = build(config.rateLimit.joinMax);
