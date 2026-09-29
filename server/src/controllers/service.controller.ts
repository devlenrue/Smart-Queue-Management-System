import type { Request, Response } from 'express';
import { serviceCatalogService } from '../services/service.service';
import { buildPageMeta, created, noContent, ok } from '../utils/apiResponse';
import { AppError } from '../utils/AppError';
import type {
  CreateServiceBody,
  QueueSettingsBody,
  ServiceHoursBody,
  ServiceListQuery,
  UpdateServiceBody,
} from '../validators/queue.validators';

export const serviceController = {
  async list(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as ServiceListQuery;
    const { services, total } = await serviceCatalogService.list({
      page: query.page,
      limit: query.limit,
      search: query.search,
      status: query.status,
      category: query.category,
      sort: query.sort,
      order: query.order,
    });
    ok(res, 'Services retrieved', services, buildPageMeta(query.page, query.limit, total));
  },

  async categories(_req: Request, res: Response): Promise<void> {
    ok(res, 'Categories retrieved', await serviceCatalogService.categories());
  },

  async getOne(req: Request, res: Response): Promise<void> {
    const id = Number(req.params.id);
    const detailed = req.user ? req.user.role !== 'customer' : false;
    ok(res, 'Service retrieved', await serviceCatalogService.getById(id, { detailed }));
  },

  async create(req: Request, res: Response): Promise<void> {
    const body = req.body as CreateServiceBody;
    created(res, 'Service created', await serviceCatalogService.create(body));
  },

  async update(req: Request, res: Response): Promise<void> {
    const body = req.body as UpdateServiceBody;
    ok(res, 'Service updated', await serviceCatalogService.update(Number(req.params.id), body));
  },

  /**
   * DELETE deactivates by default, because queue history must survive.
   * `?hard=true` really removes the row and is restricted to super_admin.
   */
  async remove(req: Request, res: Response): Promise<void> {
    const id = Number(req.params.id);

    if (String(req.query.hard) === 'true') {
      if (req.user?.role !== 'super_admin') {
        throw AppError.forbidden('Only a super administrator can permanently delete a service.');
      }
      await serviceCatalogService.remove(id);
      noContent(res);
      return;
    }

    ok(res, 'Service deactivated', await serviceCatalogService.deactivate(id));
  },

  async getHours(req: Request, res: Response): Promise<void> {
    ok(res, 'Service hours retrieved', await serviceCatalogService.getHours(Number(req.params.id)));
  },

  async setHours(req: Request, res: Response): Promise<void> {
    const body = req.body as ServiceHoursBody;
    ok(res, 'Service hours updated', await serviceCatalogService.replaceHours(Number(req.params.id), body.hours));
  },

  async getSettings(req: Request, res: Response): Promise<void> {
    ok(res, 'Queue settings retrieved', await serviceCatalogService.getSettings(Number(req.params.id)));
  },

  async updateSettings(req: Request, res: Response): Promise<void> {
    const body = req.body as QueueSettingsBody;
    ok(res, 'Queue settings updated', await serviceCatalogService.updateSettings(Number(req.params.id), body));
  },
};
