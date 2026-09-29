import { Router } from 'express';
import healthRoutes from './health.routes';
import authRoutes, { profileRouter } from './auth.routes';
import serviceRoutes from './service.routes';
import queueRoutes from './queue.routes';
import ticketRoutes from './ticket.routes';
import notificationRoutes, { announcementRouter } from './notification.routes';
import staffRoutes, { counterRouter, dashboardRouter } from './staff.routes';

const router = Router();

router.use('/system', healthRoutes);
router.use('/auth', authRoutes);
router.use('/profile', profileRouter);
router.use('/services', serviceRoutes);
router.use('/queues', queueRoutes);
router.use('/tickets', ticketRoutes);
router.use('/notifications', notificationRoutes);
router.use('/announcements', announcementRouter);
router.use('/counters', counterRouter);
router.use('/staff', staffRoutes);
router.use('/dashboard', dashboardRouter);

export default router;
