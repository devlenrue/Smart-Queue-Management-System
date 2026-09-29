import { z } from 'zod';
import {
  dateField,
  emailField,
  nameField,
  paginationSchema,
  passwordField,
  phoneField,
} from './common.validators';
import {
  ANNOUNCEMENT_STATUSES,
  COUNTER_STATUSES,
  ROLES,
  USER_STATUSES,
} from '../types/domain';

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

/** `GET /dashboard/admin?date=&days=` — `days` sizes the served-per-day chart. */
export const adminDashboardQuerySchema = z.object({
  date: dateField.optional(),
  days: z.coerce.number().int().min(1).max(31).default(7),
});

// ---------------------------------------------------------------------------
// Users (§9)
// ---------------------------------------------------------------------------

export const userListQuerySchema = paginationSchema.extend({
  role: z.enum(ROLES).optional(),
  status: z.enum(USER_STATUSES).optional(),
});

export const userStatusSchema = z.object({
  status: z.enum(USER_STATUSES, {
    required_error: 'A status is required',
    invalid_type_error: 'Status must be active, inactive or suspended',
  }),
});

export const userRoleSchema = z.object({
  role: z.enum(ROLES, {
    required_error: 'A role is required',
    invalid_type_error: 'Role must be customer, staff, admin or super_admin',
  }),
});

// ---------------------------------------------------------------------------
// Staff roster (§55)
// ---------------------------------------------------------------------------

/** `?unassigned=true` arrives as a string, so it is coerced explicitly. */
const booleanFlag = z.enum(['true', 'false', '1', '0']).transform((value) => value === 'true' || value === '1');

export const staffListQuerySchema = paginationSchema.extend({
  serviceId: z.coerce.number().int().positive().optional(),
  status: z.enum(USER_STATUSES).optional(),
  unassigned: booleanFlag.optional(),
});

export const createStaffSchema = z.object({
  firstName: nameField('First name'),
  lastName: nameField('Last name'),
  email: emailField,
  phone: phoneField,
  password: passwordField,
  serviceId: z.coerce.number().int().positive().optional(),
  counterId: z.coerce.number().int().positive().optional(),
});

export const updateStaffSchema = z
  .object({
    firstName: nameField('First name').optional(),
    lastName: nameField('Last name').optional(),
    phone: phoneField.optional(),
    status: z.enum(USER_STATUSES).optional(),
  })
  .refine((body) => Object.values(body).some((value) => value !== undefined), {
    message: 'Provide at least one field to update',
  });

export const assignStaffSchema = z.object({
  serviceId: z.coerce.number().int().positive({ message: 'A service is required' }),
  counterId: z.coerce.number().int().positive().nullish(),
});

export const unassignStaffSchema = z.object({
  assignmentId: z.coerce.number().int().positive().optional(),
});

// ---------------------------------------------------------------------------
// Counters (§54)
// ---------------------------------------------------------------------------

export const createCounterSchema = z.object({
  serviceId: z.coerce.number().int().positive({ message: 'A service is required' }),
  counterNumber: z.coerce
    .number()
    .int()
    .min(1, 'Counter number must be 1 or greater')
    .max(999, 'Counter number is too large'),
  name: nameField('Counter name'),
  status: z.enum(COUNTER_STATUSES).optional(),
  staffId: z.coerce.number().int().positive().optional(),
});

export const updateCounterSchema = z
  .object({
    counterNumber: z.coerce.number().int().min(1).max(999).optional(),
    name: nameField('Counter name').optional(),
    status: z.enum(COUNTER_STATUSES).optional(),
  })
  .refine((body) => Object.values(body).some((value) => value !== undefined), {
    message: 'Provide at least one field to update',
  });

export const counterAssignSchema = z.object({
  staffId: z.coerce.number().int().positive({ message: 'A staff member is required' }),
});

// ---------------------------------------------------------------------------
// Announcements (§11)
// ---------------------------------------------------------------------------

/** Accepts anything `Date` can parse; stored as a SQL DATETIME by the service. */
const timestampField = z
  .string()
  .trim()
  .min(1)
  .refine((value) => !Number.isNaN(Date.parse(value)), { message: 'Enter a valid date and time' });

export const announcementAdminListQuerySchema = paginationSchema.extend({
  serviceId: z.coerce.number().int().positive().optional(),
  status: z.enum(ANNOUNCEMENT_STATUSES).optional(),
});

export const createAnnouncementSchema = z.object({
  title: z.string().trim().min(3, 'Title must be at least 3 characters').max(160, 'Title is too long'),
  content: z.string().trim().min(3, 'Content must be at least 3 characters').max(4000, 'Content is too long'),
  serviceId: z.coerce.number().int().positive().nullish(),
  expiresAt: timestampField.nullish(),
  status: z.enum(['draft', 'published']).default('draft'),
});

export const updateAnnouncementSchema = z
  .object({
    title: z.string().trim().min(3).max(160).optional(),
    content: z.string().trim().min(3).max(4000).optional(),
    serviceId: z.coerce.number().int().positive().nullish(),
    expiresAt: timestampField.nullish(),
    status: z.enum(ANNOUNCEMENT_STATUSES).optional(),
  })
  .refine((body) => Object.values(body).some((value) => value !== undefined), {
    message: 'Provide at least one field to update',
  });

// ---------------------------------------------------------------------------
// System settings (§14)
// ---------------------------------------------------------------------------

/**
 * `PUT /system/settings { key: value, … }` — an open map rather than a fixed
 * schema, so adding a setting never needs a migration. Keys are constrained to
 * the shape a settings key may take; values are stored as text.
 */
export const systemSettingsSchema = z
  .record(
    z.string().regex(/^[a-z0-9_.]{2,64}$/i, 'Setting keys may contain letters, numbers, dots and underscores'),
    z.union([z.string().max(500), z.number(), z.boolean(), z.null()]),
  )
  .refine((body) => Object.keys(body).length > 0, { message: 'Provide at least one setting' });

export type AdminDashboardQuery = z.infer<typeof adminDashboardQuerySchema>;
export type UserListQuery = z.infer<typeof userListQuerySchema>;
export type StaffListQuery = z.infer<typeof staffListQuerySchema>;
export type CreateStaffBody = z.infer<typeof createStaffSchema>;
export type UpdateStaffBody = z.infer<typeof updateStaffSchema>;
export type AssignStaffBody = z.infer<typeof assignStaffSchema>;
export type CreateCounterBody = z.infer<typeof createCounterSchema>;
export type UpdateCounterBody = z.infer<typeof updateCounterSchema>;
export type AnnouncementAdminListQuery = z.infer<typeof announcementAdminListQuerySchema>;
export type CreateAnnouncementBody = z.infer<typeof createAnnouncementSchema>;
export type UpdateAnnouncementBody = z.infer<typeof updateAnnouncementSchema>;
export type SystemSettingsBody = z.infer<typeof systemSettingsSchema>;
