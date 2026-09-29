import { Router } from 'express';
import { reportController } from '../controllers/report.controller';
import { requireAuth } from '../middleware/auth';
import { requireAdmin } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { reportQuerySchema } from '../validators/report.validators';

/**
 * Mounted at /api/v1/reports — administrators and super administrators only
 * (§41). A clerk gets their own figures from `/staff/me/statistics`; these
 * endpoints cross the whole institution, which is a management view.
 *
 * All four share the same query contract, so the guard stack is identical.
 */
const router = Router();

const guards = [requireAuth, requireAdmin, validate({ query: reportQuerySchema })];

router.get('/daily', ...guards, asyncHandler(reportController.daily));
router.get('/services', ...guards, asyncHandler(reportController.services));
router.get('/staff', ...guards, asyncHandler(reportController.staff));
router.get('/queues', ...guards, asyncHandler(reportController.queues));

export default router;
