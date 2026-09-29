/**
 * The announcement composer (§11, §34).
 *
 * Reads for customers live in `notification.service.ts`
 * (`announcementQueryService`) and only ever return published, unexpired rows.
 * This file is the administrator's half: drafts are visible, and publishing is
 * the moment the message fans out into everybody's inbox.
 *
 * Publishing is idempotent by construction — the fan-out only runs on the
 * transition *into* `published`, so editing a live announcement does not
 * notify the same customer twice.
 */
import { withTransaction } from '../db';
import { AppError } from '../utils/AppError';
import { toSqlDateTime } from '../utils/datetime';
import { announcementRepository } from '../repositories/announcement.repository';
import { serviceRepository } from '../repositories/service.repository';
import { userRepository } from '../repositories/user.repository';
import { notificationService } from './notification.service';
import { toAnnouncementDto, type AnnouncementDto } from '../serializers/notification.serializer';
import type { DbConn } from '../db/types';
import type { AnnouncementStatus } from '../types/domain';

async function requireAnnouncement(id: number) {
  const row = await announcementRepository.findById(id);
  if (!row) throw AppError.notFound('That announcement could not be found.');
  return row;
}

/** ISO-8601 or 'YYYY-MM-DD HH:mm:ss' in → the stored DATETIME format out. */
function toStoredTimestamp(value: string | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw AppError.validation('Some of the information provided is not valid.', [
      { field: 'expiresAt', message: 'Enter a valid date and time' },
    ]);
  }
  return toSqlDateTime(parsed);
}

/**
 * Every active customer hears about it.
 *
 * A service-scoped announcement could in principle be narrowed to the people
 * who use that service, but "customers of the Finance Office" is not a fact
 * the schema records — only past tickets are — and a stale-ticket heuristic
 * would quietly miss the person who needs the notice most. With a campus-sized
 * user table, telling everyone is both simpler and correct.
 */
async function fanOut(tx: DbConn, title: string, content: string): Promise<number> {
  const recipients = await userRepository.idsByRole('customer', 'active', tx);
  await notificationService.announcementPublished(tx, recipients, title, content);
  return recipients.length;
}

export const announcementAdminService = {
  async list(filters: { status?: AnnouncementStatus; serviceId?: number; search?: string; page: number; limit: number }) {
    const { rows, total } = await announcementRepository.listAll(filters);
    return { announcements: rows.map(toAnnouncementDto), total };
  },

  /** Unlike the public read, an administrator may open a draft. */
  async getById(id: number): Promise<AnnouncementDto> {
    return toAnnouncementDto(await requireAnnouncement(id));
  },

  async create(
    createdBy: number,
    input: {
      title: string;
      content: string;
      serviceId?: number | null;
      expiresAt?: string | null;
      status: 'draft' | 'published';
    },
  ): Promise<AnnouncementDto> {
    if (input.serviceId != null) {
      const service = await serviceRepository.findById(input.serviceId);
      if (!service) throw AppError.notFound('That service could not be found.');
    }

    const expiresAt = toStoredTimestamp(input.expiresAt);
    const publishing = input.status === 'published';

    const id = await withTransaction(async (tx) => {
      const newId = await announcementRepository.create(
        {
          title: input.title,
          content: input.content,
          serviceId: input.serviceId ?? null,
          createdBy,
          expiresAt,
          status: input.status,
          publishedAt: publishing ? toSqlDateTime() : null,
        },
        tx,
      );
      if (publishing) await fanOut(tx, input.title, input.content);
      return newId;
    });

    return toAnnouncementDto(await requireAnnouncement(id));
  },

  async update(
    id: number,
    input: {
      title?: string;
      content?: string;
      serviceId?: number | null;
      expiresAt?: string | null;
      status?: AnnouncementStatus;
    },
  ): Promise<AnnouncementDto> {
    const existing = await requireAnnouncement(id);

    if (input.serviceId != null) {
      const service = await serviceRepository.findById(input.serviceId);
      if (!service) throw AppError.notFound('That service could not be found.');
    }

    const becomingPublished = input.status === 'published' && existing.status !== 'published';

    await withTransaction(async (tx) => {
      await announcementRepository.update(
        id,
        {
          title: input.title,
          content: input.content,
          serviceId: input.serviceId === undefined ? undefined : input.serviceId,
          expiresAt: input.expiresAt === undefined ? undefined : toStoredTimestamp(input.expiresAt),
          status: input.status,
          publishedAt: becomingPublished ? toSqlDateTime() : undefined,
        },
        tx,
      );
      if (becomingPublished) {
        await fanOut(tx, input.title ?? existing.title, input.content ?? existing.content);
      }
    });

    return toAnnouncementDto(await requireAnnouncement(id));
  },

  /** `PATCH /announcements/:id/publish` — the one-tap version of the update above. */
  async publish(id: number): Promise<AnnouncementDto> {
    const existing = await requireAnnouncement(id);
    if (existing.status === 'published') return toAnnouncementDto(existing);

    await withTransaction(async (tx) => {
      await announcementRepository.update(id, { status: 'published', publishedAt: toSqlDateTime() }, tx);
      await fanOut(tx, existing.title, existing.content);
    });

    return toAnnouncementDto(await requireAnnouncement(id));
  },

  /** Taking one down leaves the notifications already delivered alone. */
  async archive(id: number): Promise<AnnouncementDto> {
    await requireAnnouncement(id);
    await announcementRepository.update(id, { status: 'archived' });
    return toAnnouncementDto(await requireAnnouncement(id));
  },

  async remove(id: number): Promise<void> {
    await requireAnnouncement(id);
    await announcementRepository.remove(id);
  },
};
