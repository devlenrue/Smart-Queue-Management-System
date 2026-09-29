import { z } from 'zod';

/** A positive integer path parameter, e.g. /tickets/:id */
export const idParamSchema = z.object({
  id: z.coerce.number().int().positive({ message: 'A valid id is required' }),
});

export const paginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
  sort: z.string().max(40).optional(),
  order: z.enum(['asc', 'desc']).optional(),
  search: z.string().trim().max(120).optional(),
});

export const emailField = z
  .string({ required_error: 'Email is required' })
  .trim()
  .toLowerCase()
  .min(5, 'Email is required')
  .max(191, 'Email is too long')
  .email('Enter a valid email address');

export const phoneField = z
  .string({ required_error: 'Phone number is required' })
  .trim()
  .min(7, 'Enter a valid phone number')
  .max(30, 'Phone number is too long')
  .regex(/^\+?[0-9][0-9\s-]{5,}$/, 'Enter a valid phone number');

export const passwordField = z
  .string({ required_error: 'Password is required' })
  .min(8, 'Password must be at least 8 characters')
  .max(72, 'Password must be at most 72 characters')
  .regex(/[A-Za-z]/, 'Password must contain at least one letter')
  .regex(/[0-9]/, 'Password must contain at least one number');

export const nameField = (label: string) =>
  z
    .string({ required_error: `${label} is required` })
    .trim()
    .min(2, `${label} must be at least 2 characters`)
    .max(80, `${label} is too long`);

/** 'YYYY-MM-DD' */
export const dateField = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Use the date format YYYY-MM-DD');

/** 'HH:mm' or 'HH:mm:ss' */
export const timeField = z
  .string()
  .regex(/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/, 'Use the time format HH:mm');
