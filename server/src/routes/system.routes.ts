import { Router } from 'express';
import healthRoutes from './health.routes';
import { systemController } from '../controllers/admin.controller';
import { requireAuth } from '../middleware/auth';
import { requireSuperAdmin } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { systemSettingsSchema } from '../validators/admin.validators';

/**
 * Mounted at /api/v1/system.
 *
 * `/health` stays public — a monitoring probe has no credentials. The settings
 * table is the opposite extreme: it configures the whole installation, so it
 * is the one surface reserved for `super_admin`.
 */
const router = Router();

router.use('/', healthRoutes);

router.get('/settings', requireAuth, requireSuperAdmin, asyncHandler(systemController.listSettings));
router.put(
  '/settings',
  requireAuth,
  requireSuperAdmin,
  validate({ body: systemSettingsSchema }),
  asyncHandler(systemController.updateSettings),
);

export default router;
