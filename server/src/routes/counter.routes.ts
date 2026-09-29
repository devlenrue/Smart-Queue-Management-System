import { Router } from 'express';
import { counterController } from '../controllers/staff.controller';
import { counterAdminController } from '../controllers/roster.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin, requireStaff } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import { counterListQuerySchema, counterStatusSchema } from '../validators/staff.validators';
import { counterAssignSchema, createCounterSchema, updateCounterSchema } from '../validators/admin.validators';

/**
 * Mounted at /api/v1/counters.
 *
 * Two audiences: a clerk who opens and closes their own desk (Phase 6), and an
 * administrator who creates desks and decides who stands at them (Phase 7).
 */
const router = Router();

// ---------------------------------------------------------------------- staff
router.get(
  '/',
  requireAuth,
  requireStaff,
  validate({ query: counterListQuerySchema }),
  asyncHandler(counterController.list),
);
router.patch(
  '/:id/status',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema, body: counterStatusSchema }),
  asyncHandler(counterController.setStatus),
);

// ---------------------------------------------------------------------- admin
router.post(
  '/',
  requireAuth,
  requireAdmin,
  validate({ body: createCounterSchema }),
  asyncHandler(counterAdminController.create),
);
router.put(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: updateCounterSchema }),
  asyncHandler(counterAdminController.update),
);
router.post(
  '/:id/assign',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: counterAssignSchema }),
  asyncHandler(counterAdminController.assign),
);
router.delete(
  '/:id/assign',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(counterAdminController.unassign),
);
router.delete(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(counterAdminController.remove),
);

export default router;
