import type { RequestHandler } from 'express';
import { AppError } from '../utils/AppError';
import { extractBearerToken, verifyToken } from '../utils/jwt';
import { tokenRepository, userRepository } from '../repositories/user.repository';
import { toAuthUser } from '../serializers/user.serializer';
import type { AuthUser } from '../types/domain';

/**
 * Authenticates the request.
 *
 * Four things must hold, in this order:
 *   1. a bearer token is present and its signature verifies
 *   2. the token has not been revoked by a logout
 *   3. the user still exists
 *   4. the account is still active
 */
export const requireAuth: RequestHandler = async (req, _res, next) => {
  try {
    const token = extractBearerToken(req.headers.authorization);
    if (!token) throw AppError.unauthorized('You need to sign in to continue.');

    const payload = verifyToken(token);

    if (payload.jti && (await tokenRepository.isRevoked(payload.jti))) {
      throw AppError.unauthorized('You have been signed out. Please sign in again.', 'TOKEN_REVOKED');
    }

    const row = await userRepository.findById(Number(payload.sub));
    if (!row) throw AppError.unauthorized('Your account could not be found. Please sign in again.');

    if (row.status === 'suspended') {
      throw AppError.forbidden('Your account has been suspended. Please contact an administrator.', 'ACCOUNT_SUSPENDED');
    }
    if (row.status === 'inactive') {
      throw AppError.forbidden('Your account is not active. Please contact an administrator.', 'ACCOUNT_INACTIVE');
    }

    req.user = toAuthUser(row);
    req.tokenId = payload.jti;
    req.tokenExpiresAt = payload.exp;
    next();
  } catch (error) {
    next(error);
  }
};

/** Reads the user when a token is present, but does not demand one. */
export const optionalAuth: RequestHandler = async (req, _res, next) => {
  const token = extractBearerToken(req.headers.authorization);
  if (!token) return next();
  try {
    const payload = verifyToken(token);
    const row = await userRepository.findById(Number(payload.sub));
    if (row && row.status === 'active') {
      req.user = toAuthUser(row);
      req.tokenId = payload.jti;
    }
  } catch {
    /* an invalid token on an optional route is simply ignored */
  }
  next();
};

/**
 * Narrows `req.user` from optional to present.
 *
 * Controllers behind `requireAuth` always have a user; this turns that fact
 * into something the type checker knows, instead of a non-null assertion.
 */
export function requireUser(req: { user?: AuthUser }): AuthUser {
  if (!req.user) throw AppError.unauthorized('You need to sign in to continue.');
  return req.user;
}
