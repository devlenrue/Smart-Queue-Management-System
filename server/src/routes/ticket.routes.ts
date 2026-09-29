import { Router } from 'express';
import { ticketController } from '../controllers/ticket.controller';
import { requireAuth } from '../middleware/auth';
import { requireStaff } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/asyncHandler';
import { idParamSchema } from '../validators/common.validators';
import { callNextSchema, callTicketSchema, myTicketsQuerySchema, skipTicketSchema } from '../validators/queue.validators';

const router = Router();

// ------------------------------------------------------------------ customer
// '/my' is the name used in docs/api.md; '/' is the same list.
router.get('/', requireAuth, validate({ query: myTicketsQuerySchema }), asyncHandler(ticketController.myTickets));
router.get('/my', requireAuth, validate({ query: myTicketsQuerySchema }), asyncHandler(ticketController.myTickets));
router.get('/active', requireAuth, asyncHandler(ticketController.myActiveTickets));

// Declared before '/:id' so these words are never read as an id.
const callNextHandlers = [
  requireAuth,
  requireStaff,
  validate({ body: callNextSchema }),
  asyncHandler(ticketController.callNext),
] as const;
router.post('/next', ...callNextHandlers);
router.post('/call-next', ...callNextHandlers);

router.get('/:id', requireAuth, validate({ params: idParamSchema }), asyncHandler(ticketController.getOne));
router.get('/:id/position', requireAuth, validate({ params: idParamSchema }), asyncHandler(ticketController.position));
router.get('/:id/events', requireAuth, validate({ params: idParamSchema }), asyncHandler(ticketController.events));
router.post('/:id/cancel', requireAuth, validate({ params: idParamSchema }), asyncHandler(ticketController.cancel));

// --------------------------------------------------------------------- staff
router.post(
  '/:id/call',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema, body: callTicketSchema }),
  asyncHandler(ticketController.call),
);
router.post(
  '/:id/recall',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema }),
  asyncHandler(ticketController.recall),
);
router.post('/:id/start', requireAuth, requireStaff, validate({ params: idParamSchema }), asyncHandler(ticketController.start));
router.post(
  '/:id/complete',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema }),
  asyncHandler(ticketController.complete),
);
router.post(
  '/:id/skip',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema, body: skipTicketSchema }),
  asyncHandler(ticketController.skip),
);
router.post(
  '/:id/no-show',
  requireAuth,
  requireStaff,
  validate({ params: idParamSchema }),
  asyncHandler(ticketController.noShow),
);

export default router;
