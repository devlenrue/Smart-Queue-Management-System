import { Router } from 'express';
import { serviceController } from '../controllers/service.controller';
import { queueController } from '../controllers/queue.controller';
import { optionalAuth, requireAuth } from '../middleware/auth';
import { requireAdmin } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { joinLimiter } from '../middleware/rateLimit';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import {
  createServiceSchema,
  queueSettingsSchema,
  serviceHoursSchema,
  serviceListQuerySchema,
  updateServiceSchema,
} from '../validators/queue.validators';

const router = Router();

// ------------------------------------------------------------------- public
// Browsing the catalogue and the live board needs no account (§15, §33);
// optionalAuth still populates req.user so staff get the richer payload.
router.get('/', optionalAuth, validate({ query: serviceListQuerySchema }), asyncHandler(serviceController.list));
router.get('/categories', asyncHandler(serviceController.categories));
router.get('/:id', optionalAuth, validate({ params: idParamSchema }), asyncHandler(serviceController.getOne));
router.get('/:id/hours', validate({ params: idParamSchema }), asyncHandler(serviceController.getHours));
router.get('/:id/queue', validate({ params: idParamSchema }), asyncHandler(queueController.statusForService));

// -------------------------------------------------------------- authenticated
router.post(
  '/:id/queue/join',
  requireAuth,
  joinLimiter,
  validate({ params: idParamSchema }),
  asyncHandler(queueController.join),
);

// --------------------------------------------------------------------- admin
router.post('/', requireAuth, requireAdmin, validate({ body: createServiceSchema }), asyncHandler(serviceController.create));
router.put(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: updateServiceSchema }),
  asyncHandler(serviceController.update),
);
router.delete('/:id', requireAuth, requireAdmin, validate({ params: idParamSchema }), asyncHandler(serviceController.remove));
router.put(
  '/:id/hours',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: serviceHoursSchema }),
  asyncHandler(serviceController.setHours),
);
router.get(
  '/:id/settings',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(serviceController.getSettings),
);
router.put(
  '/:id/settings',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: queueSettingsSchema }),
  asyncHandler(serviceController.updateSettings),
);

export default router;
