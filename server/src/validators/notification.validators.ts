import { z } from 'zod';
import { paginationSchema } from './common.validators';
import { NOTIFICATION_TYPES } from '../types/domain';

/** `?isRead=false` arrives as a string, so it is coerced explicitly. */
const booleanFlag = z
  .enum(['true', 'false', '1', '0'])
  .transform((value) => value === 'true' || value === '1');

export const notificationListQuerySchema = paginationSchema.extend({
  isRead: booleanFlag.optional(),
  type: z.enum(NOTIFICATION_TYPES).optional(),
});

export const announcementListQuerySchema = paginationSchema.extend({
  serviceId: z.coerce.number().int().positive().optional(),
});

export type NotificationListQuery = z.infer<typeof notificationListQuerySchema>;
export type AnnouncementListQuery = z.infer<typeof announcementListQuerySchema>;
