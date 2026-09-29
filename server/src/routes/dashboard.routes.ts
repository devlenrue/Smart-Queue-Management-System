import { Router } from 'express';
import { staffController } from '../controllers/staff.controller';
import { adminController } from '../controllers/admin.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin, requireStaff } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { staffDashboardQuerySchema } from '../validators/staff.validators';
import { adminDashboardQuerySchema } from '../validators/admin.validators';

/**
 * Mounted at /api/v1/dashboard.
 *
 * One endpoint per console, each returning everything its first screen needs,
 * so a figure in a header can never disagree with the list beneath it.
 */
const router = Router();

router.get(
  '/staff',
  requireAuth,
  requireStaff,
  validate({ query: staffDashboardQuerySchema }),
  asyncHandler(staffController.dashboard),
);

router.get(
  '/admin',
  requireAuth,
  requireAdmin,
  validate({ query: adminDashboardQuerySchema }),
  asyncHandler(adminController.dashboard),
);

export default router;
