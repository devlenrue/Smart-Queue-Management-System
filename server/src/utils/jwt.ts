import { randomUUID } from 'node:crypto';
import jwt, { type SignOptions } from 'jsonwebtoken';
import { config } from '../config/env';
import { AppError } from './AppError';
import type { Role } from '../types/domain';

export interface TokenPayload {
  /** user id */
  sub: string;
  role: Role;
  /** token id, so an individual token can be revoked on logout */
  jti: string;
  iat?: number;
  exp?: number;
}

export interface IssuedToken {
  token: string;
  jti: string;
  expiresAt: Date;
}

export function signToken(userId: number, role: Role): IssuedToken {
  const jti = randomUUID();
  const options = { expiresIn: config.jwt.expiresIn, jwtid: jti } as SignOptions;
  const token = jwt.sign({ sub: String(userId), role }, config.jwt.secret, options);
  const decoded = jwt.decode(token) as TokenPayload | null;
  const expiresAt = decoded?.exp ? new Date(decoded.exp * 1000) : new Date(Date.now() + 7 * 24 * 3600 * 1000);
  return { token, jti, expiresAt };
}

export function verifyToken(token: string): TokenPayload {
  try {
    return jwt.verify(token, config.jwt.secret) as TokenPayload;
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw AppError.unauthorized('Your session has expired. Please sign in again.', 'TOKEN_EXPIRED');
    }
    throw AppError.unauthorized('Your session is not valid. Please sign in again.', 'UNAUTHENTICATED');
  }
}

/** Pulls the bearer token out of the Authorization header. */
export function extractBearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const [scheme, value] = header.split(' ');
  if (!value || scheme.toLowerCase() !== 'bearer') return null;
  return value.trim() || null;
}
