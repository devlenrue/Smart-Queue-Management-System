/**
 * DTOs for the administrator console.
 *
 * Same contract as everywhere else: rows stay snake_case inside the
 * repositories, everything crossing the HTTP boundary is camelCase, and no
 * mapper ever copies a `password_hash`.
 */
import { toIso } from '../utils/datetime';
import { DAY_NAMES } from './service.serializer';
import type {
  DayAveragesRow,
  DayTotalsRow,
  ServedPerDayRow,
  ServiceBreakdownRow,
  UserActivityRow,
} from '../repositories/admin.repository';
import type { SettingRow } from '../repositories/settings.repository';
import type { StaffRosterRow } from '../repositories/user.repository';
import type { CounterStatus, Role, ServiceStatus, UserDto, UserStatus } from '../types/domain';

// ---------------------------------------------------------------------------
// Dashboard (§31, §42)
// ---------------------------------------------------------------------------

export interface AdminServiceRowDto {
  serviceId: number;
  name: string;
  code: string;
  status: ServiceStatus;
  issued: number;
  waiting: number;
  serving: number;
  completed: number;
  cancelled: number;
  averageWaitMinutes: number;
}

export interface ServedPointDto {
  date: string;
  label: string;
  served: number;
}

export interface StatusBreakdownDto {
  waiting: number;
  serving: number;
  completed: number;
  cancelled: number;
  skipped: number;
  noShow: number;
}

export interface AdminDashboardDto {
  today: string;
  activeServices: number;
  activeQueues: number;
  activeCounters: number;
  staffOnDuty: number;
  customersWaiting: number;
  customersServedToday: number;
  averageWaitMinutes: number;
  averageServiceMinutes: number;
  ticketsIssuedToday: number;
  cancelledToday: number;
  skippedToday: number;
  noShowToday: number;
  byService: AdminServiceRowDto[];
  servedPerDay: ServedPointDto[];
  statusBreakdown: StatusBreakdownDto;
}

const round1 = (value: number | null): number => (value == null ? 0 : Math.round(value * 10) / 10);

export function toAdminServiceRowDto(row: ServiceBreakdownRow): AdminServiceRowDto {
  return {
    serviceId: row.service_id,
    name: row.name,
    code: row.code,
    status: row.status,
    issued: row.issued,
    waiting: row.waiting,
    serving: row.serving,
    completed: row.completed,
    cancelled: row.cancelled,
    averageWaitMinutes: round1(row.wait_minutes),
  };
}

/**
 * Fills the gaps in a sparse per-day aggregate.
 *
 * SQL only returns the days that had a completion; a bar chart needs the quiet
 * Sundays too, otherwise seven bars silently become four and the axis lies.
 */
export function toServedSeries(rows: ServedPerDayRow[], days: string[]): ServedPointDto[] {
  const byDay = new Map(rows.map((row) => [row.day, row.served]));
  return days.map((date) => ({
    date,
    label: DAY_NAMES[new Date(`${date}T00:00:00`).getDay()] ?? '',
    served: byDay.get(date) ?? 0,
  }));
}

export function toStatusBreakdownDto(counts: Record<string, number>): StatusBreakdownDto {
  return {
    waiting: counts.waiting ?? 0,
    serving: (counts.called ?? 0) + (counts.serving ?? 0),
    completed: counts.completed ?? 0,
    cancelled: counts.cancelled ?? 0,
    skipped: counts.skipped ?? 0,
    noShow: counts.no_show ?? 0,
  };
}

export function toDashboardTotals(
  totals: DayTotalsRow,
  averages: DayAveragesRow,
): Pick<
  AdminDashboardDto,
  | 'customersWaiting'
  | 'customersServedToday'
  | 'averageWaitMinutes'
  | 'averageServiceMinutes'
  | 'ticketsIssuedToday'
  | 'cancelledToday'
  | 'skippedToday'
  | 'noShowToday'
> {
  return {
    customersWaiting: totals.waiting,
    customersServedToday: totals.served,
    averageWaitMinutes: round1(averages.averageWaitMinutes),
    averageServiceMinutes: round1(averages.averageServiceMinutes),
    ticketsIssuedToday: totals.issued,
    cancelledToday: totals.cancelled,
    skippedToday: totals.skipped,
    noShowToday: totals.no_show,
  };
}

// ---------------------------------------------------------------------------
// Staff roster (§55)
// ---------------------------------------------------------------------------

export interface RosterPostingDto {
  assignmentId: number;
  serviceId: number;
  serviceName: string | null;
  serviceCode: string | null;
  counterId: number | null;
  counterNumber: number | null;
  counterName: string | null;
  counterStatus: CounterStatus | null;
  assignedAt: string | null;
}

export interface StaffRosterDto {
  id: number;
  firstName: string;
  lastName: string;
  fullName: string;
  email: string;
  phone: string;
  role: Role;
  status: UserStatus;
  createdAt: string | null;
  /** Null when nobody has posted this person to a service yet. */
  posting: RosterPostingDto | null;
}

export function toStaffRosterDto(row: StaffRosterRow): StaffRosterDto {
  return {
    id: Number(row.id),
    firstName: row.first_name,
    lastName: row.last_name,
    fullName: `${row.first_name} ${row.last_name}`.trim(),
    email: row.email,
    phone: row.phone,
    role: row.role,
    status: row.status,
    createdAt: toIso(row.created_at),
    posting:
      row.assignment_id == null || row.assignment_service_id == null
        ? null
        : {
            assignmentId: Number(row.assignment_id),
            serviceId: Number(row.assignment_service_id),
            serviceName: row.service_name,
            serviceCode: row.service_code,
            counterId: row.assignment_counter_id == null ? null : Number(row.assignment_counter_id),
            counterNumber: row.counter_number == null ? null : Number(row.counter_number),
            counterName: row.counter_name,
            counterStatus: row.counter_status,
            assignedAt: toIso(row.assigned_at),
          },
  };
}

// ---------------------------------------------------------------------------
// User detail (§9) and system settings (§14)
// ---------------------------------------------------------------------------

export interface UserActivityDto {
  totalTickets: number;
  completed: number;
  cancelled: number;
  noShow: number;
  active: number;
  lastActivityAt: string | null;
}

export interface UserDetailDto extends UserDto {
  activity: UserActivityDto;
  posting: RosterPostingDto | null;
}

export function toUserActivityDto(row: UserActivityRow): UserActivityDto {
  // Two clocks: the last ticket taken as a customer, the last event caused as
  // a clerk. "Last seen" is whichever happened later.
  const candidates = [row.lastTicketAt, row.lastActionAt]
    .map((value) => toIso(value))
    .filter((value): value is string => value !== null)
    .sort();

  return {
    totalTickets: row.totalTickets,
    completed: row.completed,
    cancelled: row.cancelled,
    noShow: row.noShow,
    active: row.active,
    lastActivityAt: candidates.length ? candidates[candidates.length - 1] : null,
  };
}

export interface SystemSettingDto {
  key: string;
  value: string;
  description: string | null;
  updatedAt: string | null;
}

export function toSettingDto(row: SettingRow): SystemSettingDto {
  return {
    key: row.setting_key,
    value: row.setting_value,
    description: row.description,
    updatedAt: toIso(row.updated_at),
  };
}
