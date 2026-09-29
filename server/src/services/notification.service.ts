/**
 * Every message the queue engine sends lives here, so the wording is
 * consistent and the templates can be reviewed in one place (§38).
 */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { notificationRepository } from '../repositories/notification.repository';
import { announcementRepository } from '../repositories/announcement.repository';
import { eventRepository } from '../repositories/event.repository';
import { AppError } from '../utils/AppError';
import { toAnnouncementDto, toNotificationDto, type NotificationDto } from '../serializers/notification.serializer';
import type { NotificationType } from '../types/domain';

interface TicketContext {
  ticketId: number;
  userId: number;
  ticketNumber: string;
  serviceName: string;
  counterNumber?: number | null;
}

async function send(
  conn: DbConn,
  userId: number,
  ticketId: number | null,
  title: string,
  message: string,
  type: NotificationType = 'queue',
): Promise<void> {
  await notificationRepository.insert({ userId, ticketId, title, message, type }, conn);
}

export const notificationService = {
  async ticketIssued(conn: DbConn, context: TicketContext, position: number, estimatedWaitMinutes: number): Promise<void> {
    await send(
      conn,
      context.userId,
      context.ticketId,
      `Ticket ${context.ticketNumber} issued`,
      `You are number ${position} in the ${context.serviceName} queue. Estimated wait is about ${estimatedWaitMinutes} minute${estimatedWaitMinutes === 1 ? '' : 's'}.`,
    );
  },

  async ticketCalled(conn: DbConn, context: TicketContext): Promise<void> {
    await send(
      conn,
      context.userId,
      context.ticketId,
      `Ticket ${context.ticketNumber} is being called`,
      context.counterNumber
        ? `Please proceed to Counter ${context.counterNumber}.`
        : 'Please proceed to the service counter.',
    );
  },

  async ticketRecalled(conn: DbConn, context: TicketContext): Promise<void> {
    await send(
      conn,
      context.userId,
      context.ticketId,
      `Ticket ${context.ticketNumber} is being called again`,
      context.counterNumber
        ? `Please proceed to Counter ${context.counterNumber}.`
        : 'Please proceed to the service counter.',
    );
  },

  async serviceCompleted(conn: DbConn, context: TicketContext): Promise<void> {
    await send(
      conn,
      context.userId,
      context.ticketId,
      'Service completed',
      `Your ${context.serviceName} service is complete. Thank you for using SmartQueue.`,
    );
  },

  async ticketSkipped(conn: DbConn, context: TicketContext): Promise<void> {
    await send(
      conn,
      context.userId,
      context.ticketId,
      `Ticket ${context.ticketNumber} was skipped`,
      `You were not at the counter when ${context.ticketNumber} was called. Please request a new ticket for ${context.serviceName}.`,
    );
  },

  async ticketNoShow(conn: DbConn, context: TicketContext): Promise<void> {
    await send(
      conn,
      context.userId,
      context.ticketId,
      `Ticket ${context.ticketNumber} was marked as a no-show`,
      `You did not respond when ${context.ticketNumber} was called. Please request a new ticket for ${context.serviceName}.`,
    );
  },

  /**
   * "Your turn is approaching."
   *
   * Sent at most once per ticket: a polling client hits the position endpoint
   * every few seconds, so the `threshold_notified` event is used as the
   * de-duplication marker rather than a timer.
   */
  async maybeNotifyApproaching(
    context: TicketContext,
    peopleAhead: number,
    threshold: number,
    conn: DbConn = getDb(),
  ): Promise<boolean> {
    if (peopleAhead > threshold || peopleAhead <= 0) return false;
    if (await eventRepository.existsForTicket(context.ticketId, 'threshold_notified', conn)) return false;

    await send(
      conn,
      context.userId,
      context.ticketId,
      'Your turn is approaching',
      `There ${peopleAhead === 1 ? 'is' : 'are'} ${peopleAhead} ${peopleAhead === 1 ? 'person' : 'people'} ahead of you in the ${context.serviceName} queue. Please stay nearby.`,
    );
    await eventRepository.insert(conn, context.ticketId, null, 'threshold_notified', `Notified at ${peopleAhead} ahead`);
    return true;
  },

  async announcementPublished(conn: DbConn, userIds: number[], title: string, message: string): Promise<void> {
    for (const userId of userIds) {
      await send(conn, userId, null, title, message, 'announcement');
    }
  },
};

// ---------------------------------------------------------------------------
// Reads — what the notification screen and the unread badge call (§37)
// ---------------------------------------------------------------------------

export const notificationQueryService = {
  async list(
    userId: number,
    filters: { isRead?: boolean; type?: NotificationType; page: number; limit: number },
  ): Promise<{ notifications: NotificationDto[]; total: number; unread: number }> {
    const [{ rows, total }, unread] = await Promise.all([
      notificationRepository.list({ userId, ...filters }),
      notificationRepository.unreadCount(userId),
    ]);
    return { notifications: rows.map(toNotificationDto), total, unread };
  },

  async unreadCount(userId: number): Promise<number> {
    return notificationRepository.unreadCount(userId);
  },

  /** Marking someone else's notification read is a 404, not a 403 — it simply isn't theirs. */
  async markRead(id: number, userId: number): Promise<NotificationDto> {
    const affected = await notificationRepository.markRead(id, userId);
    if (affected === 0) {
      const existing = await notificationRepository.findById(id);
      if (!existing || Number(existing.user_id) !== userId) {
        throw AppError.notFound('That notification could not be found.');
      }
    }
    const row = await notificationRepository.findById(id);
    if (!row) throw AppError.notFound('That notification could not be found.');
    return toNotificationDto(row);
  },

  async markAllRead(userId: number): Promise<{ updated: number; unread: number }> {
    const updated = await notificationRepository.markAllRead(userId);
    return { updated, unread: await notificationRepository.unreadCount(userId) };
  },
};

export const announcementQueryService = {
  async listPublished(filters: { serviceId?: number; page: number; limit: number }) {
    const { rows, total } = await announcementRepository.listPublished(filters);
    return { announcements: rows.map(toAnnouncementDto), total };
  },

  async getById(id: number) {
    const row = await announcementRepository.findById(id);
    if (!row || row.status !== 'published') {
      throw AppError.notFound('That announcement could not be found.');
    }
    return toAnnouncementDto(row);
  },
};
