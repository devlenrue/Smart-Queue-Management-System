import { z } from 'zod';
import { dateField, paginationSchema } from './common.validators';
import { COUNTER_STATUSES, TICKET_STATUSES } from '../types/domain';

/**
 * `/staff/:id/…` where `:id` may be the literal `me`, so the client never has
 * to interpolate its own user id into a URL it already authenticates.
 */
export const staffIdParamSchema = z.object({
  id: z.union([z.literal('me'), z.coerce.number().int().positive()], {
    errorMap: () => ({ message: 'A valid staff id (or "me") is required' }),
  }),
});

/** `GET /dashboard/staff?serviceId=&counterId=` — both only meaningful for admins. */
export const staffDashboardQuerySchema = z.object({
  serviceId: z.coerce.number().int().positive().optional(),
  counterId: z.coerce.number().int().positive().optional(),
});

/** `GET /staff/:id/statistics?from=&to=` */
export const staffStatisticsQuerySchema = z.object({
  from: dateField.optional(),
  to: dateField.optional(),
});

/** `GET /staff/:id/tickets?from=&to=&status=&page=&limit=` */
export const staffTicketsQuerySchema = paginationSchema.extend({
  from: dateField.optional(),
  to: dateField.optional(),
  status: z.enum(TICKET_STATUSES).optional(),
});

/** `GET /counters?serviceId=&status=` */
export const counterListQuerySchema = z.object({
  serviceId: z.coerce.number().int().positive().optional(),
  status: z.enum(COUNTER_STATUSES).optional(),
});

/** `PATCH /counters/:id/status` */
export const counterStatusSchema = z.object({
  status: z.enum(COUNTER_STATUSES, {
    required_error: 'A counter status is required',
    invalid_type_error: 'Status must be available, busy or offline',
  }),
});

export type StaffDashboardQuery = z.infer<typeof staffDashboardQuerySchema>;
export type StaffStatisticsQuery = z.infer<typeof staffStatisticsQuerySchema>;
export type StaffTicketsQuery = z.infer<typeof staffTicketsQuerySchema>;
export type CounterListQuery = z.infer<typeof counterListQuerySchema>;
