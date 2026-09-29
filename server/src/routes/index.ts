import { Router } from 'express';
import systemRoutes from './system.routes';
import authRoutes, { profileRouter } from './auth.routes';
import serviceRoutes from './service.routes';
import queueRoutes from './queue.routes';
import ticketRoutes from './ticket.routes';
import notificationRoutes from './notification.routes';
import announcementRoutes from './announcement.routes';
import counterRoutes from './counter.routes';
import staffRoutes from './staff.routes';
import userRoutes from './user.routes';
import dashboardRoutes from './dashboard.routes';

const router = Router();

router.use('/system', systemRoutes);
router.use('/auth', authRoutes);
router.use('/profile', profileRouter);
router.use('/services', serviceRoutes);
router.use('/queues', queueRoutes);
router.use('/tickets', ticketRoutes);
router.use('/notifications', notificationRoutes);
router.use('/announcements', announcementRoutes);
router.use('/counters', counterRoutes);
router.use('/staff', staffRoutes);
router.use('/users', userRoutes);
router.use('/dashboard', dashboardRoutes);

export default router;
