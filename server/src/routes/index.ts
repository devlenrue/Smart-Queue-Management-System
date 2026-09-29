import { Router } from 'express';
import healthRoutes from './health.routes';
import authRoutes, { profileRouter } from './auth.routes';
import serviceRoutes from './service.routes';
import queueRoutes from './queue.routes';
import ticketRoutes from './ticket.routes';

const router = Router();

router.use('/system', healthRoutes);
router.use('/auth', authRoutes);
router.use('/profile', profileRouter);
router.use('/services', serviceRoutes);
router.use('/queues', queueRoutes);
router.use('/tickets', ticketRoutes);

export default router;
