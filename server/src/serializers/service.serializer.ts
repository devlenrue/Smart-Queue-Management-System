import { shortTime, toIso } from '../utils/datetime';
import type { QueueSettingsRow, ServiceHoursRow, ServiceRow } from '../repositories/service.repository';
import type { CounterWithStaffRow } from '../repositories/counter.repository';
import type { ServiceStatus, QueueStatus, CounterStatus } from '../types/domain';

export interface QueueSummaryDto {
  queueId: number;
  status: QueueStatus;
  waitingCount: number;
  servingCount: number;
  completedToday: number;
  nowServing: string | null;
  estimatedWaitMinutes: number;
  activeCounters: number;
  isAcceptingTickets: boolean;
  capacityRemaining: number;
}

export interface ServiceHoursDto {
  dayOfWeek: number;
  dayName: string;
  openingTime: string | null;
  closingTime: string | null;
  status: 'open' | 'closed';
}

export interface ServiceDto {
  id: number;
  name: string;
  code: string;
  description: string | null;
  category: string | null;
  averageServiceTime: number;
  dailyCapacity: number;
  status: ServiceStatus;
  createdAt: string | null;
  updatedAt: string | null;
  queue?: QueueSummaryDto;
  hoursToday?: { opensAt: string | null; closesAt: string | null; isOpenNow: boolean };
  hours?: ServiceHoursDto[];
  settings?: QueueSettingsDto;
  counters?: CounterDto[];
}

export interface QueueSettingsDto {
  maxQueueSize: number;
  allowCancellation: boolean;
  allowRejoin: boolean;
  notificationThreshold: number;
  estimatedServiceTime: number;
}

export interface CounterDto {
  id: number;
  serviceId: number;
  serviceName?: string;
  serviceCode?: string;
  counterNumber: number;
  name: string;
  status: CounterStatus;
  staff: { id: number; fullName: string } | null;
  currentTicket: string | null;
}

export const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export function toServiceDto(row: ServiceRow): ServiceDto {
  return {
    id: Number(row.id),
    name: row.name,
    code: row.code,
    description: row.description,
    category: row.category,
    averageServiceTime: Number(row.average_service_time),
    dailyCapacity: Number(row.daily_capacity),
    status: row.status,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

export function toHoursDto(row: ServiceHoursRow): ServiceHoursDto {
  return {
    dayOfWeek: Number(row.day_of_week),
    dayName: DAY_NAMES[Number(row.day_of_week)] ?? '',
    openingTime: shortTime(row.opening_time),
    closingTime: shortTime(row.closing_time),
    status: row.status,
  };
}

export function toSettingsDto(row: QueueSettingsRow): QueueSettingsDto {
  return {
    maxQueueSize: Number(row.max_queue_size),
    allowCancellation: Number(row.allow_cancellation) === 1,
    allowRejoin: Number(row.allow_rejoin) === 1,
    notificationThreshold: Number(row.notification_threshold),
    estimatedServiceTime: Number(row.estimated_service_time),
  };
}

export function toCounterDto(row: CounterWithStaffRow): CounterDto {
  return {
    id: Number(row.id),
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    counterNumber: Number(row.counter_number),
    name: row.name,
    status: row.status,
    staff:
      row.assigned_staff_id != null
        ? {
            id: Number(row.assigned_staff_id),
            fullName: `${row.staff_first_name ?? ''} ${row.staff_last_name ?? ''}`.trim(),
          }
        : null,
    currentTicket: row.current_ticket,
  };
}
