import { toIso } from '../utils/datetime';
import type { NotificationRow } from '../repositories/notification.repository';
import type { AnnouncementDetailRow } from '../repositories/announcement.repository';
import type { AnnouncementStatus, NotificationType } from '../types/domain';

export interface NotificationDto {
  id: number;
  title: string;
  message: string;
  type: NotificationType;
  isRead: boolean;
  ticketId: number | null;
  createdAt: string | null;
}

export function toNotificationDto(row: NotificationRow): NotificationDto {
  return {
    id: Number(row.id),
    title: row.title,
    message: row.message,
    type: row.type,
    isRead: Number(row.is_read) === 1,
    ticketId: row.ticket_id == null ? null : Number(row.ticket_id),
    createdAt: toIso(row.created_at),
  };
}

export interface AnnouncementDto {
  id: number;
  title: string;
  content: string;
  status: AnnouncementStatus;
  serviceId: number | null;
  serviceName: string | null;
  serviceCode: string | null;
  authorName: string | null;
  publishedAt: string | null;
  expiresAt: string | null;
  /** True when it applies to the whole institution rather than one service. */
  isGlobal: boolean;
}

export function toAnnouncementDto(row: AnnouncementDetailRow): AnnouncementDto {
  return {
    id: Number(row.id),
    title: row.title,
    content: row.content,
    status: row.status,
    serviceId: row.service_id == null ? null : Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    authorName: row.author_first_name ? `${row.author_first_name} ${row.author_last_name ?? ''}`.trim() : null,
    publishedAt: toIso(row.published_at),
    expiresAt: toIso(row.expires_at),
    isGlobal: row.service_id == null,
  };
}
