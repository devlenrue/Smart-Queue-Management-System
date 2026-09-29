/** Domain vocabulary shared by repositories, services and controllers. */

export const ROLES = ['customer', 'staff', 'admin', 'super_admin'] as const;
export type Role = (typeof ROLES)[number];

export const USER_STATUSES = ['active', 'inactive', 'suspended'] as const;
export type UserStatus = (typeof USER_STATUSES)[number];

export const SERVICE_STATUSES = ['open', 'closed', 'inactive'] as const;
export type ServiceStatus = (typeof SERVICE_STATUSES)[number];

export const COUNTER_STATUSES = ['available', 'busy', 'offline'] as const;
export type CounterStatus = (typeof COUNTER_STATUSES)[number];

export const QUEUE_STATUSES = ['waiting', 'paused', 'closed'] as const;
export type QueueStatus = (typeof QUEUE_STATUSES)[number];

export const TICKET_STATUSES = ['waiting', 'called', 'serving', 'completed', 'cancelled', 'skipped', 'no_show'] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];

/** Statuses that occupy a place in the queue (docs/queue-engine.md §1.2). */
export const ACTIVE_TICKET_STATUSES: readonly TicketStatus[] = ['waiting', 'called', 'serving'];
/** The only status counted in "people ahead". */
export const BLOCKING_TICKET_STATUSES: readonly TicketStatus[] = ['waiting'];
export const TERMINAL_TICKET_STATUSES: readonly TicketStatus[] = ['completed', 'cancelled', 'skipped', 'no_show'];

export const EVENT_TYPES = [
  'joined',
  'called',
  'recalled',
  'service_started',
  'completed',
  'cancelled',
  'skipped',
  'no_show',
  'threshold_notified',
] as const;
export type EventType = (typeof EVENT_TYPES)[number];

export const NOTIFICATION_TYPES = ['queue', 'system', 'announcement', 'service'] as const;
export type NotificationType = (typeof NOTIFICATION_TYPES)[number];

export const ANNOUNCEMENT_STATUSES = ['draft', 'published', 'archived'] as const;
export type AnnouncementStatus = (typeof ANNOUNCEMENT_STATUSES)[number];

export function isTerminal(status: TicketStatus): boolean {
  return TERMINAL_TICKET_STATUSES.includes(status);
}

export function isActive(status: TicketStatus): boolean {
  return ACTIVE_TICKET_STATUSES.includes(status);
}

// ---------------------------------------------------------------------------
// Row shapes (snake_case, exactly as stored)
// ---------------------------------------------------------------------------

export interface UserRow {
  id: number;
  first_name: string;
  last_name: string;
  email: string;
  phone: string;
  password_hash: string;
  role: Role;
  status: UserStatus;
  created_at: string;
  updated_at: string;
}

/** The authenticated principal attached to every protected request. */
export interface AuthUser {
  id: number;
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  role: Role;
  status: UserStatus;
}

// ---------------------------------------------------------------------------
// DTO shapes (camelCase, exactly as returned by the API)
// ---------------------------------------------------------------------------

export interface UserDto {
  id: number;
  firstName: string;
  lastName: string;
  fullName: string;
  email: string;
  phone: string;
  role: Role;
  status: UserStatus;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface PaginationInput {
  page: number;
  limit: number;
}
