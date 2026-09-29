import { Router } from 'express';
import { userController } from '../controllers/user.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin, requireSuperAdmin } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import { userListQuerySchema, userRoleSchema, userStatusSchema } from '../validators/admin.validators';

/**
 * Mounted at /api/v1/users — administration of *other people's* accounts.
 * Everybody's own profile lives at /api/v1/profile and needs no role at all.
 *
 * Changing a role and deleting an account are super_admin only: they are the
 * two operations that can hand out, or take away, the keys to everything else.
 */
const router = Router();

router.get('/', requireAuth, requireAdmin, validate({ query: userListQuerySchema }), asyncHandler(userController.list));

router.get(
  '/:id',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(userController.getOne),
);

router.patch(
  '/:id/status',
  requireAuth,
  requireAdmin,
  validate({ params: idParamSchema, body: userStatusSchema }),
  asyncHandler(userController.setStatus),
);

router.patch(
  '/:id/role',
  requireAuth,
  requireSuperAdmin,
  validate({ params: idParamSchema, body: userRoleSchema }),
  asyncHandler(userController.setRole),
);

router.delete(
  '/:id',
  requireAuth,
  requireSuperAdmin,
  validate({ params: idParamSchema }),
  asyncHandler(userController.remove),
);

export default router;
