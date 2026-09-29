/**
 * HTTP in, HTTP out. No business rules, no SQL.
 */
import type { Request, Response } from 'express';
import { authService } from '../services/auth.service';
import { created, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import type { ChangePasswordInput, LoginInput, RegisterInput, UpdateProfileInput } from '../validators/auth.validators';

export const authController = {
  async register(req: Request, res: Response): Promise<void> {
    const result = await authService.register(req.body as RegisterInput);
    created(res, 'Registration successful', result);
  },

  async login(req: Request, res: Response): Promise<void> {
    const result = await authService.login(req.body as LoginInput);
    ok(res, 'Signed in successfully', result);
  },

  async me(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Profile retrieved', await authService.getProfile(user.id));
  },

  async logout(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    await authService.logout(user.id, req.tokenId, req.tokenExpiresAt);
    ok(res, 'Signed out successfully', null);
  },

  async updateProfile(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const updated = await authService.updateProfile(user.id, req.body as UpdateProfileInput);
    ok(res, 'Profile updated', updated);
  },

  async changePassword(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    await authService.changePassword(user.id, req.body as ChangePasswordInput);
    ok(res, 'Password changed successfully', null);
  },
};
