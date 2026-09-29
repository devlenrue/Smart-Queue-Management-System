import { Router } from 'express';
import { notificationController } from '../controllers/notification.controller';
import { requireAuth } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import { notificationListQuerySchema } from '../validators/notification.validators';

const router = Router();

// A notification belongs to exactly one user, so every route here is scoped
// to the caller — there is no "read anyone's inbox" endpoint.
router.get('/', requireAuth, validate({ query: notificationListQuerySchema }), asyncHandler(notificationController.list));
router.get('/unread-count', requireAuth, asyncHandler(notificationController.unreadCount));

const markAll = [requireAuth, asyncHandler(notificationController.markAllRead)] as const;
router.patch('/read-all', ...markAll);
router.post('/read-all', ...markAll);

const markOne = [requireAuth, validate({ params: idParamSchema }), asyncHandler(notificationController.markRead)] as const;
router.patch('/:id/read', ...markOne);
router.post('/:id/read', ...markOne);

export default router;

// Announcements moved to their own `announcement.routes.ts` in Phase 7, when
// the composer joined the two public reads.
