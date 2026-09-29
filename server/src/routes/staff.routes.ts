import { Router } from 'express';
import { staffController } from '../controllers/staff.controller';
import { staffAdminController } from '../controllers/roster.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin, requireStaff } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import {
  staffIdParamSchema,
  staffStatisticsQuerySchema,
  staffTicketsQuerySchema,
} from '../validators/staff.validators';
import {
  assignStaffSchema,
  createStaffSchema,
  staffListQuerySchema,
  unassignStaffSchema,
  updateStaffSchema,
} from '../validators/admin.validators';

/**
 * Mounted at /api/v1/staff.
 *
 * Two halves. A clerk reads their *own* figures (`:id` may be the literal
 * `me`); an administrator manages the roster — who exists, and where they are
 * posted. The roster routes take a numeric id only: "me" is meaningless when
 * the caller is not the subject.
 */
const router = Router();

// ----------------------------------------------------------- self-service
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

// ------------------------------------------------------------------ roster
router.get(
  '/',
  requireAuth,
  requireAdmin,
  validate({ query: staffListQuerySchema }),
  asyncHandler(staffAdminController.list),
);

router.post(
  '/',
  requireAuth,
  requireAdmin,
  validate({ body: createStaffSchema }),
  asyncHandler(staffAdminController.create),
);

router.put(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: updateStaffSchema }),
  asyncHandler(staffAdminController.update),
);

router.post(
  '/:id/assign',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: assignStaffSchema }),
  asyncHandler(staffAdminController.assign),
);

router.post(
  '/:id/unassign',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: unassignStaffSchema }),
  asyncHandler(staffAdminController.unassign),
);

export default router;
