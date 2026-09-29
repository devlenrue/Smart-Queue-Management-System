import { minutesBetween, toIso } from '../utils/datetime';
import type { TicketDetailRow } from '../repositories/ticket.repository';
import type { EventWithActorRow } from '../repositories/event.repository';
import type { TicketStatus } from '../types/domain';

export interface CounterSummaryDto {
  id: number;
  counterNumber: number;
  name: string;
}

export interface CustomerSummaryDto {
  id: number;
  firstName: string;
  lastName: string;
  fullName: string;
  phone: string;
  email: string;
}

export interface TicketDto {
  id: number;
  ticketNumber: string;
  sequenceNumber: number;
  status: TicketStatus;
  queueId: number;
  queueDate: string;
  serviceId: number;
  serviceName: string;
  serviceCode: string;
  counter: CounterSummaryDto | null;
  estimatedWaitMinutes: number | null;
  joinedAt: string | null;
  calledAt: string | null;
  serviceStartedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  /** Minutes from joining until called (or until now, while still waiting). */
  waitedMinutes: number;
  /** Minutes spent at the counter, once the service has started. */
  serviceMinutes: number | null;
  customer?: CustomerSummaryDto;
}

export function toTicketDto(row: TicketDetailRow, options: { includeCustomer?: boolean } = {}): TicketDto {
  const dto: TicketDto = {
    id: Number(row.id),
    ticketNumber: row.ticket_number,
    sequenceNumber: Number(row.sequence_number),
    status: row.status,
    queueId: Number(row.queue_id),
    queueDate: String(row.queue_date).slice(0, 10),
    serviceId: Number(row.service_id),
    serviceName: row.service_name,
    serviceCode: row.service_code,
    counter:
      row.counter_id != null
        ? { id: Number(row.counter_id), counterNumber: Number(row.counter_number), name: row.counter_name ?? '' }
        : null,
    estimatedWaitMinutes: row.estimated_wait_minutes == null ? null : Number(row.estimated_wait_minutes),
    joinedAt: toIso(row.joined_at),
    calledAt: toIso(row.called_at),
    serviceStartedAt: toIso(row.service_started_at),
    completedAt: toIso(row.completed_at),
    cancelledAt: toIso(row.cancelled_at),
    waitedMinutes: minutesBetween(row.joined_at, row.called_at ?? new Date()),
    serviceMinutes: row.service_started_at ? minutesBetween(row.service_started_at, row.completed_at ?? new Date()) : null,
  };

  if (options.includeCustomer) {
    dto.customer = {
      id: Number(row.user_id),
      firstName: row.customer_first_name,
      lastName: row.customer_last_name,
      fullName: `${row.customer_first_name} ${row.customer_last_name}`.trim(),
      phone: row.customer_phone,
      email: row.customer_email,
    };
  }

  return dto;
}

export interface TicketEventDto {
  id: number;
  eventType: string;
  description: string | null;
  actorName: string | null;
  createdAt: string | null;
}

export function toEventDto(row: EventWithActorRow): TicketEventDto {
  return {
    id: Number(row.id),
    eventType: row.event_type,
    description: row.description,
    actorName: row.actor_first_name ? `${row.actor_first_name} ${row.actor_last_name ?? ''}`.trim() : null,
    createdAt: toIso(row.created_at),
  };
}

/** What the ticket screen polls for (§18, §44). */
export interface TicketPositionDto {
  ticketId: number;
  ticketNumber: string;
  status: TicketStatus;
  /** 1-based; null once the ticket is no longer waiting. */
  position: number | null;
  peopleAhead: number;
  nowServing: string | null;
  estimatedWaitMinutes: number;
  activeCounters: number;
  counter: CounterSummaryDto | null;
  queueStatus: string;
  updatedAt: string;
}
