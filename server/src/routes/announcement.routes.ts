import { Router } from 'express';
import { announcementController } from '../controllers/notification.controller';
import { announcementAdminController } from '../controllers/announcement.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import { announcementListQuerySchema } from '../validators/notification.validators';
import {
  announcementAdminListQuerySchema,
  createAnnouncementSchema,
  updateAnnouncementSchema,
} from '../validators/admin.validators';

/**
 * Mounted at /api/v1/announcements.
 *
 * The public list and the administrator's list answer different questions —
 * "what is on the board?" versus "what have we written?" — so they are
 * different paths rather than one path that changes shape with the caller's
 * role. `/manage` is declared first so that `manage` is never parsed as an id.
 */
const router = Router();

// --------------------------------------------------------------- admin (list)
router.get(
  '/manage',
  requireAuth,
  requireAdmin,
  validate({ query: announcementAdminListQuerySchema }),
  asyncHandler(announcementAdminController.list),
);
router.get(
  '/manage/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(announcementAdminController.getOne),
);

// --------------------------------------------------------------------- public
router.get('/', validate({ query: announcementListQuerySchema }), asyncHandler(announcementController.list));
router.get('/:id', validate({ params: idParamSchema }), asyncHandler(announcementController.getOne));

// -------------------------------------------------------------- admin (writes)
router.post(
  '/',
  requireAuth,
  requireAdmin,
  validate({ body: createAnnouncementSchema }),
  asyncHandler(announcementAdminController.create),
);
router.put(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: updateAnnouncementSchema }),
  asyncHandler(announcementAdminController.update),
);
router.patch(
  '/:id/publish',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(announcementAdminController.publish),
);
router.patch(
  '/:id/archive',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(announcementAdminController.archive),
);
router.delete(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(announcementAdminController.remove),
);

export default router;
