import type { Request, Response } from 'express';
import { adminService } from '../services/admin.service';
import { ok } from '../utils/apiResponse';
import type { AdminDashboardQuery, SystemSettingsBody } from '../validators/admin.validators';

export const adminController = {
  /** GET /api/v1/dashboard/admin — the whole overview screen in one request. */
  async dashboard(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as AdminDashboardQuery;
    const data = await adminService.getDashboard({ date: query.date, days: query.days });
    ok(res, 'Admin dashboard retrieved', data);
  },
};

export const systemController = {
  /** GET /api/v1/system/settings */
  async listSettings(_req: Request, res: Response): Promise<void> {
    ok(res, 'System settings retrieved', await adminService.listSettings());
  },

  /** PUT /api/v1/system/settings — an open `{ key: value }` map. */
  async updateSettings(req: Request, res: Response): Promise<void> {
    const body = req.body as SystemSettingsBody;
    ok(res, 'System settings updated', await adminService.updateSettings(body));
  },
};
