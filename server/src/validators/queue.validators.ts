import { z } from 'zod';
import { dateField, paginationSchema, timeField } from './common.validators';
import { QUEUE_STATUSES, SERVICE_STATUSES, TICKET_STATUSES } from '../types/domain';

// --------------------------------------------------------------------- services

export const createServiceSchema = z.object({
  name: z.string().trim().min(3, 'Service name must be at least 3 characters').max(120),
  code: z
    .string()
    .trim()
    .toUpperCase()
    .min(2, 'Service code must be at least 2 characters')
    .max(8, 'Service code must be at most 8 characters')
    .regex(/^[A-Z0-9]+$/, 'Service code may contain only letters and numbers'),
  description: z.string().trim().max(2000).optional().nullable(),
  category: z.string().trim().max(60).optional().nullable(),
  averageServiceTime: z.coerce.number().int().min(1, 'Average service time must be at least 1 minute').max(240),
  dailyCapacity: z.coerce.number().int().min(1).max(10_000),
  status: z.enum(SERVICE_STATUSES).optional(),
});

export const updateServiceSchema = createServiceSchema.partial();

export const serviceListQuerySchema = paginationSchema.extend({
  status: z.enum(SERVICE_STATUSES).optional(),
  category: z.string().trim().max(60).optional(),
});

export const serviceHoursSchema = z.object({
  hours: z
    .array(
      z
        .object({
          dayOfWeek: z.coerce.number().int().min(0).max(6),
          openingTime: timeField,
          closingTime: timeField,
          status: z.enum(['open', 'closed']).default('open'),
        })
        .refine((entry) => entry.closingTime > entry.openingTime, {
          message: 'Closing time must be after opening time',
          path: ['closingTime'],
        }),
    )
    .min(1, 'Provide at least one day')
    .max(7, 'A week has only seven days'),
});

export const queueSettingsSchema = z.object({
  maxQueueSize: z.coerce.number().int().min(1).max(10_000).optional(),
  allowCancellation: z.coerce.boolean().optional(),
  allowRejoin: z.coerce.boolean().optional(),
  notificationThreshold: z.coerce.number().int().min(1).max(50).optional(),
  estimatedServiceTime: z.coerce.number().int().min(1).max(240).optional(),
});

// ----------------------------------------------------------------------- queues

export const queueListQuerySchema = z.object({
  date: dateField.optional(),
  serviceId: z.coerce.number().int().positive().optional(),
  status: z.enum(QUEUE_STATUSES).optional(),
});

export const joinQueueSchema = z.object({}).passthrough();

// ---------------------------------------------------------------------- tickets

export const myTicketsQuerySchema = paginationSchema.extend({
  status: z.union([z.literal('active'), z.enum(TICKET_STATUSES)]).optional(),
  serviceId: z.coerce.number().int().positive().optional(),
});

export const callNextSchema = z.object({
  serviceId: z.coerce.number().int().positive({ message: 'A service is required' }),
  counterId: z.coerce.number().int().positive().optional(),
});

export const callTicketSchema = z.object({
  counterId: z.coerce.number().int().positive().optional(),
});

export const skipTicketSchema = z.object({
  reason: z.string().trim().max(200).optional(),
});

export type CreateServiceBody = z.infer<typeof createServiceSchema>;
export type UpdateServiceBody = z.infer<typeof updateServiceSchema>;
export type ServiceListQuery = z.infer<typeof serviceListQuerySchema>;
export type ServiceHoursBody = z.infer<typeof serviceHoursSchema>;
export type QueueSettingsBody = z.infer<typeof queueSettingsSchema>;
export type QueueListQuery = z.infer<typeof queueListQuerySchema>;
export type MyTicketsQuery = z.infer<typeof myTicketsQuerySchema>;
export type CallNextBody = z.infer<typeof callNextSchema>;
export type CallTicketBody = z.infer<typeof callTicketSchema>;
export type SkipTicketBody = z.infer<typeof skipTicketSchema>;
