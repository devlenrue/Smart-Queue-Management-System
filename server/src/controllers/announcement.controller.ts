import type { Request, Response } from 'express';
import { announcementAdminService } from '../services/announcement.service';
import { buildPageMeta, created, noContent, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import type {
  AnnouncementAdminListQuery,
  CreateAnnouncementBody,
  UpdateAnnouncementBody,
} from '../validators/admin.validators';

/**
 * The composer. Public reads stay in `notification.controller.ts` — they are a
 * different audience with a different visibility rule (published + unexpired).
 */
export const announcementAdminController = {
  /** GET /api/v1/announcements/manage?status=&serviceId=&search= */
  async list(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as AnnouncementAdminListQuery;
    const { announcements, total } = await announcementAdminService.list({
      status: query.status,
      serviceId: query.serviceId,
      search: query.search,
      page: query.page,
      limit: query.limit,
    });
    ok(res, 'Announcements retrieved', announcements, buildPageMeta(query.page, query.limit, total));
  },

  /** GET /api/v1/announcements/manage/:id — drafts included. */
  async getOne(req: Request, res: Response): Promise<void> {
    ok(res, 'Announcement retrieved', await announcementAdminService.getById(Number(req.params.id)));
  },

  /** POST /api/v1/announcements */
  async create(req: Request, res: Response): Promise<void> {
    const actor = requireUser(req);
    const body = req.body as CreateAnnouncementBody;
    const announcement = await announcementAdminService.create(actor.id, {
      title: body.title,
      content: body.content,
      serviceId: body.serviceId ?? null,
      expiresAt: body.expiresAt ?? null,
      status: body.status,
    });
    created(
      res,
      announcement.status === 'published' ? 'Announcement published' : 'Announcement saved as a draft',
      announcement,
    );
  },

  /** PUT /api/v1/announcements/:id */
  async update(req: Request, res: Response): Promise<void> {
    const body = req.body as UpdateAnnouncementBody;
    ok(res, 'Announcement updated', await announcementAdminService.update(Number(req.params.id), body));
  },

  /** PATCH /api/v1/announcements/:id/publish */
  async publish(req: Request, res: Response): Promise<void> {
    ok(res, 'Announcement published', await announcementAdminService.publish(Number(req.params.id)));
  },

  /** PATCH /api/v1/announcements/:id/archive */
  async archive(req: Request, res: Response): Promise<void> {
    ok(res, 'Announcement archived', await announcementAdminService.archive(Number(req.params.id)));
  },

  /** DELETE /api/v1/announcements/:id */
  async remove(req: Request, res: Response): Promise<void> {
    await announcementAdminService.remove(Number(req.params.id));
    noContent(res);
  },
};
