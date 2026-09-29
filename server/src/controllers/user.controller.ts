import type { Request, Response } from 'express';
import { userService } from '../services/user.service';
import { buildPageMeta, noContent, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import type { UserListQuery } from '../validators/admin.validators';

export const userController = {
  /** GET /api/v1/users?role=&status=&search=&page=&limit= */
  async list(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as UserListQuery;
    const { users, total } = await userService.list({
      role: query.role,
      status: query.status,
      search: query.search,
      page: query.page,
      limit: query.limit,
      sort: query.sort,
      order: query.order,
    });
    ok(res, 'Users retrieved', users, buildPageMeta(query.page, query.limit, total));
  },

  /** GET /api/v1/users/:id — profile, activity and posting. */
  async getOne(req: Request, res: Response): Promise<void> {
    ok(res, 'User retrieved', await userService.getById(Number(req.params.id)));
  },

  /** PATCH /api/v1/users/:id/status */
  async setStatus(req: Request, res: Response): Promise<void> {
    const actor = requireUser(req);
    const body = req.body as { status: 'active' | 'inactive' | 'suspended' };
    const user = await userService.setStatus(actor, Number(req.params.id), body.status);
    ok(res, `${user.fullName} is now ${user.status}`, user);
  },

  /** PATCH /api/v1/users/:id/role — super_admin only. */
  async setRole(req: Request, res: Response): Promise<void> {
    const actor = requireUser(req);
    const body = req.body as { role: 'customer' | 'staff' | 'admin' | 'super_admin' };
    const user = await userService.setRole(actor, Number(req.params.id), body.role);
    ok(res, `${user.fullName} is now ${user.role.replace('_', ' ')}`, user);
  },

  /** DELETE /api/v1/users/:id — super_admin only. */
  async remove(req: Request, res: Response): Promise<void> {
    const actor = requireUser(req);
    await userService.remove(actor, Number(req.params.id));
    noContent(res);
  },
};
