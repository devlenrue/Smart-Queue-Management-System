import { Router } from 'express';
import { counterController, staffController } from '../controllers/staff.controller';
import { requireAuth } from '../middleware/auth';
import { requireStaff } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import {
  counterListQuerySchema,
  counterStatusSchema,
  staffDashboardQuerySchema,
  staffIdParamSchema,
  staffStatisticsQuerySchema,
  staffTicketsQuerySchema,
} from '../validators/staff.validators';

/**
 * Mounted at /api/v1/staff.
 *
 * Phase 6 covers what a staff member needs about *themselves*; the admin-only
 * roster endpoints (create staff, assign, unassign) arrive with Phase 7.
 */
const router = Router();

router.get(
  '/:id/statistics',
  requireAuth,
  requireStaff,
  validate({ params: staffIdParamSchema, query: staffStatisticsQuerySchema }),
  asyncHandler(staffController.statistics),
);

router.get(
  '/:id/tickets',
  requireAuth,
  requireStaff,
  validate({ params: staffIdParamSchema, query: staffTicketsQuerySchema }),
  asyncHandler(staffController.handledTickets),
);

export default router;

/** Mounted at /api/v1/dashboard. The admin dashboard joins it in Phase 7. */
export const dashboardRouter = Router();
dashboardRouter.get(
  '/staff',
  requireAuth,
  requireStaff,
  validate({ query: staffDashboardQuerySchema }),
  asyncHandler(staffController.dashboard),
);

/**
 * Mounted at /api/v1/counters.
 *
 * Only the two operations a counter clerk performs. Counter CRUD belongs to
 * the administrator and is written in Phase 7.
 */
export const counterRouter = Router();
counterRouter.get(
  '/',
  requireAuth,
  requireStaff,
  validate({ query: counterListQuerySchema }),
  asyncHandler(counterController.list),
);
counterRouter.patch(
  '/:id/status',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema, body: counterStatusSchema }),
  asyncHandler(counterController.setStatus),
);
