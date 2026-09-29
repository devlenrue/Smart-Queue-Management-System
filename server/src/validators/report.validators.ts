import { z } from 'zod';
import { dateField } from './common.validators';

/**
 * `GET /reports/*?from=&to=&serviceId=&staffId=&format=`
 *
 * Every report shares one query shape, so the four endpoints cannot drift
 * apart. Omitting the range means today — the same default the consoles
 * open with. The span is capped at a year: a report is a report, not an
 * export of the whole database, and the sweep in `report.service.ts` holds
 * one row per ticket in memory while it runs.
 */
const MAX_RANGE_DAYS = 366;

const DAY_MS = 86_400_000;

export const reportQuerySchema = z
  .object({
    from: dateField.optional(),
    to: dateField.optional(),
    serviceId: z.coerce.number().int().positive().optional(),
    staffId: z.coerce.number().int().positive().optional(),
    format: z.enum(['json', 'csv']).default('json'),
  })
  .superRefine((value, ctx) => {
    if (!value.from || !value.to) return;

    if (value.to < value.from) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['to'],
        message: 'The end date cannot be before the start date',
      });
      return;
    }

    const span = (Date.parse(`${value.to}T00:00:00Z`) - Date.parse(`${value.from}T00:00:00Z`)) / DAY_MS + 1;
    if (span > MAX_RANGE_DAYS) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['to'],
        message: `A report can cover at most ${MAX_RANGE_DAYS} days`,
      });
    }
  });

export type ReportQueryInput = z.infer<typeof reportQuerySchema>;
