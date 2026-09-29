import { Router } from 'express';
import healthRoutes from './health.routes';

const router = Router();

router.use('/system', healthRoutes);

export default router;
