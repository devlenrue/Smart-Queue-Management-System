import type { Request, Response } from 'express';
import { announcementQueryService, notificationQueryService } from '../services/notification.service';
import { buildPageMeta, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import type { AnnouncementListQuery, NotificationListQuery } from '../validators/notification.validators';

export const notificationController = {
  async list(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const query = req.query as unknown as NotificationListQuery;
    const { notifications, total, unread } = await notificationQueryService.list(user.id, {
      isRead: query.isRead,
      type: query.type,
      page: query.page,
      limit: query.limit,
    });
    ok(
      res,
      'Notifications retrieved',
      { notifications, unreadCount: unread },
      buildPageMeta(query.page, query.limit, total),
    );
  },

  async unreadCount(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Unread count retrieved', { count: await notificationQueryService.unreadCount(user.id) });
  },

  async markRead(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Notification marked as read', await notificationQueryService.markRead(Number(req.params.id), user.id));
  },

  async markAllRead(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'All notifications marked as read', await notificationQueryService.markAllRead(user.id));
  },
};

export const announcementController = {
  async list(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as AnnouncementListQuery;
    const { announcements, total } = await announcementQueryService.listPublished({
      serviceId: query.serviceId,
      page: query.page,
      limit: query.limit,
    });
    ok(res, 'Announcements retrieved', announcements, buildPageMeta(query.page, query.limit, total));
  },

  async getOne(req: Request, res: Response): Promise<void> {
    ok(res, 'Announcement retrieved', await announcementQueryService.getById(Number(req.params.id)));
  },
};
