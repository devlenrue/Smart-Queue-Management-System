/**
 * DTOs for the staff console. Row shapes stay snake_case inside the
 * repositories; everything crossing the HTTP boundary is camelCase.
 */
import { toIso } from '../utils/datetime';
import type { AssignmentDetailRow } from '../repositories/assignment.repository';
import type { CounterRow, CounterWithStaffRow } from '../repositories/counter.repository';
import type { QueueStatusDto } from '../services/queue.service';
import type { TicketDto } from './ticket.serializer';
import type { CounterStatus, Role, ServiceStatus } from '../types/domain';

export interface StaffAssignmentDto {
  id: number;
  serviceId: number;
  serviceName: string;
  serviceCode: string;
  counterId: number | null;
  counterNumber: number | null;
  counterName: string | null;
  assignedAt: string | null;
  status: 'active' | 'ended';
}

export interface StaffCounterDto {
  id: number;
  serviceId: number;
  counterNumber: number;
  name: string;
  status: CounterStatus;
  assignedStaffId: number | null;
}

export interface StaffDashboardStatsDto {
  waiting: number;
  servedToday: number;
  skippedToday: number;
  noShowToday: number;
  cancelledToday: number;
  averageServiceMinutes: number;
  averageWaitMinutes: number;
}

export interface StaffDashboardDto {
  today: string;
  /** False when nobody has put this person on a service yet. */
  assigned: boolean;
  assignment: StaffAssignmentDto | null;
  service: { id: number; name: string; code: string; status: ServiceStatus } | null;
  counter: StaffCounterDto | null;
  queue: QueueStatusDto | null;
  currentTicket: TicketDto | null;
  upNext: TicketDto[];
  stats: StaffDashboardStatsDto;
}

export interface StaffStatisticsDto {
  staff: { id: number; name: string; email: string; role: Role };
  range: { from: string; to: string };
  ticketsServed: number;
  ticketsSkipped: number;
  ticketsNoShow: number;
  ticketsRecalled: number;
  ticketsHandled: number;
  completionRate: number;
  averageServiceMinutes: number;
  averageWaitMinutes: number;
  byDay: Array<{ date: string; served: number; averageServiceMinutes: number }>;
}

export function toStaffAssignmentDto(row: AssignmentDetailRow): StaffAssignmentDto {
  return {
    id: Number(row.id),
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    counterId: row.counter_id == null ? null : Number(row.counter_id),
    counterNumber: row.counter_number == null ? null : Number(row.counter_number),
    counterName: row.counter_name,
    assignedAt: toIso(row.assigned_at),
    status: row.status,
  };
}

export function toStaffCounterDto(row: CounterRow | CounterWithStaffRow): StaffCounterDto {
  return {
    id: Number(row.id),
    serviceId: Number(row.service_id),
    counterNumber: Number(row.counter_number),
    name: row.name,
    status: row.status,
    assignedStaffId: row.assigned_staff_id == null ? null : Number(row.assigned_staff_id),
  };
}
