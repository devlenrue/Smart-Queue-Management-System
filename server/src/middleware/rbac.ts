import type { RequestHandler } from 'express';
import { AppError } from '../utils/AppError';
import type { Role } from '../types/domain';

/**
 * Role-based authorisation. Always used *after* requireAuth.
 *
 *   router.post('/services', requireAuth, requireRole('admin', 'super_admin'), …)
 */
export function requireRole(...allowed: Role[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) {
      next(AppError.unauthorized('You need to sign in to continue.'));
      return;
    }
    if (!allowed.includes(req.user.role)) {
      next(AppError.forbidden('You do not have permission to perform this action.'));
      return;
    }
    next();
  };
}

/** Shorthands for the three common groupings. */
export const requireCustomer = requireRole('customer');
export const requireStaff = requireRole('staff', 'admin', 'super_admin');
export const requireAdmin = requireRole('admin', 'super_admin');
export const requireSuperAdmin = requireRole('super_admin');

export function isAdmin(role: Role): boolean {
  return role === 'admin' || role === 'super_admin';
}
