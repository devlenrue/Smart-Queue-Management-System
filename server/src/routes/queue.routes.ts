import { Router } from 'express';
import { queueController } from '../controllers/queue.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin, requireStaff } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { joinLimiter } from '../middleware/rateLimit';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import { queueListQuerySchema } from '../validators/queue.validators';

const router = Router();

// Public read-only views — the lobby display board needs no account.
router.get('/', validate({ query: queueListQuerySchema }), asyncHandler(queueController.list));
router.get('/:id', validate({ params: idParamSchema }), asyncHandler(queueController.statusForQueue));
router.get('/:id/status', validate({ params: idParamSchema }), asyncHandler(queueController.statusForQueue));

// Joining, addressed by queue. `POST /services/:id/queue/join` is the same operation.
router.post(
  '/:id/join',
  requireAuth,
  joinLimiter,
  validate({ params: idParamSchema }),
  asyncHandler(queueController.joinByQueue),
);

// Staff and admins see the full monitor, with customer names attached.
router.get(
  '/:id/monitor',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema }),
  asyncHandler(queueController.monitor),
);

// Only admins may pause, resume or close a queue (§29). Both verbs are accepted:
// PATCH reads as "amend this queue", POST as "perform this action".
const adminAction = [requireAuth, requireAdmin, validate({ params: idParamSchema })] as const;
router.route('/:id/pause').post(...adminAction, asyncHandler(queueController.pause)).patch(...adminAction, asyncHandler(queueController.pause));
router.route('/:id/resume').post(...adminAction, asyncHandler(queueController.resume)).patch(...adminAction, asyncHandler(queueController.resume));
router.route('/:id/close').post(...adminAction, asyncHandler(queueController.close)).patch(...adminAction, asyncHandler(queueController.close));

export default router;
