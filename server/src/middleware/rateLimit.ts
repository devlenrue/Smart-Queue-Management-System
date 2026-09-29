import rateLimit, { type RateLimitRequestHandler } from 'express-rate-limit';
import { config } from '../config/env';
import type { ErrorBodyShape } from '../types/errors';

const limitedBody: ErrorBodyShape = {
  success: false,
  message: 'Too many requests. Please wait a moment and try again.',
  code: 'RATE_LIMITED',
  errors: [],
};

/**
 * Limits would make the rest of the suite flaky and prove nothing there, so
 * they are skipped under NODE_ENV=test — except for the one test file that
 * sets RATE_LIMIT_IN_TESTS=true specifically to exercise them.
 */
const enforced = !config.isTest || config.rateLimit.enforceInTests;

function build(max: number): RateLimitRequestHandler {
  return rateLimit({
    windowMs: config.rateLimit.windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => !enforced,
    handler: (_req, res) => {
      res.status(429).json(limitedBody);
    },
  });
}

/** Brute-force protection on the credential endpoints. */
export const authLimiter = build(config.rateLimit.authMax);

/** Stops a stuck client from spamming the queue with join attempts. */
export const joinLimiter = build(config.rateLimit.joinMax);

/**
 * Backstop across the whole API. Generous enough that a polling client never
 * notices it (see RATE_LIMIT_API_MAX in config/env.ts) and low enough that a
 * runaway script is cut off.
 */
export const apiLimiter = build(config.rateLimit.apiMax);
