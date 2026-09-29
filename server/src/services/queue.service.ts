/**
 * THE QUEUE ENGINE — joining, guards, daily queue instances and queue state.
 *
 * Read docs/queue-engine.md alongside this file; every guard here maps to a
 * numbered business rule from §59 of the brief.
 */
import { getDb, withRetryableTransaction, withTransaction } from '../db';
import type { DbConn } from '../db/types';
import { AppError } from '../utils/AppError';
import {
  dayOfWeek,
  formatTime12h,
  minutesSinceMidnight,
  shortTime,
  toSqlDateTime,
  todayDate,
} from '../utils/datetime';
import { serviceRepository, type ServiceWithSettings } from '../repositories/service.repository';
import { queueRepository, type QueueRow } from '../repositories/queue.repository';
import { ticketRepository } from '../repositories/ticket.repository';
import { eventRepository } from '../repositories/event.repository';
import { counterRepository } from '../repositories/counter.repository';
import { notificationService } from './notification.service';
import { estimateWaitMinutes, estimationBasis } from './estimation.service';
import { toTicketDto, type TicketDto, type TicketPositionDto } from '../serializers/ticket.serializer';
import { toCounterDto, type QueueSummaryDto } from '../serializers/service.serializer';
import type { QueueStatus } from '../types/domain';

/** FIN + 23 → "FIN-023" (§17). */
export function formatTicketNumber(serviceCode: string, sequenceNumber: number): string {
  return `${serviceCode.toUpperCase()}-${String(sequenceNumber).padStart(3, '0')}`;
}

export interface JoinResult {
  ticket: TicketDto;
  position: TicketPositionDto;
}

export interface QueueStatusDto {
  queueId: number;
  serviceId: number;
  serviceName: string;
  serviceCode: string;
  queueDate: string;
  status: QueueStatus;
  nowServing: string | null;
  currentNumber: number;
  waitingCount: number;
  servingCount: number;
  completedToday: number;
  cancelledToday: number;
  skippedToday: number;
  noShowToday: number;
  ticketsIssuedToday: number;
  activeCounters: number;
  averageWaitMinutes: number;
  averageServiceMinutes: number;
  estimatedWaitMinutes: number;
  isAcceptingTickets: boolean;
  capacityRemaining: number;
  updatedAt: string;
}

export const queueService = {
  /** Today's queue row for a service, created lazily on first use. */
  async getOrCreateTodayQueue(serviceId: number, queueDate = todayDate()): Promise<QueueRow> {
    return withTransaction((tx) => queueRepository.getOrCreate(serviceId, queueDate, tx));
  },

  /** Loads a queue by id or raises the standard 404. */
  async requireQueue(queueId: number): Promise<QueueRow> {
    const queue = await queueRepository.findById(queueId);
    if (!queue) throw AppError.notFound('That queue could not be found.');
    return queue;
  },

  /**
   * Rule 2 + §30. Throws when the service itself is unavailable.
   * Evaluated both before and inside the join transaction.
   */
  async assertServiceOpen(service: ServiceWithSettings, conn: DbConn = getDb(), when = new Date()): Promise<void> {
    if (service.status === 'inactive') {
      throw AppError.conflict('SERVICE_INACTIVE', `${service.name} is not currently available.`);
    }
    if (service.status === 'closed') {
      throw AppError.conflict('SERVICE_CLOSED', `${service.name} is currently closed.`);
    }

    const hours = await serviceRepository.findHoursForDay(Number(service.id), dayOfWeek(when), conn);

    // No row configured for today → treat the service as always available.
    if (!hours) return;

    if (hours.status === 'closed') {
      throw AppError.conflict('OUTSIDE_SERVICE_HOURS', `${service.name} is closed today.`);
    }

    const nowMinutes = minutesSinceMidnight(when);
    const opening = minutesSinceMidnight(hours.opening_time);
    const closing = minutesSinceMidnight(hours.closing_time);

    if (nowMinutes < opening) {
      throw AppError.conflict(
        'OUTSIDE_SERVICE_HOURS',
        `${service.name} is currently closed. It opens at ${formatTime12h(hours.opening_time)}.`,
      );
    }
    if (nowMinutes >= closing) {
      throw AppError.conflict(
        'OUTSIDE_SERVICE_HOURS',
        `${service.name} is closed for today. It closed at ${formatTime12h(hours.closing_time)}.`,
      );
    }
  },

  /** §29 — queue-level gate, separate from the service-level one. */
  assertQueueAcceptsTickets(queue: QueueRow, serviceName: string): void {
    if (queue.status === 'paused') {
      throw AppError.conflict('QUEUE_PAUSED', `The ${serviceName} queue is paused and is not accepting new tickets.`);
    }
    if (queue.status === 'closed') {
      throw AppError.conflict('QUEUE_CLOSED', `The ${serviceName} queue is closed for today.`);
    }
  },

  /**
   * Join a queue — the most important operation in the system.
   *
   * The whole body runs inside ONE transaction that begins by taking a row
   * lock on the queue. Every guard is re-checked *after* the lock, so a
   * check-then-act race cannot slip a ticket past a full or closed queue.
   * See docs/queue-engine.md §3.
   */
  async joinQueue(userId: number, serviceId: number): Promise<JoinResult> {
    const service = await serviceRepository.findWithSettings(serviceId);
    if (!service) throw AppError.notFound('That service could not be found.');

    // Cheap pre-flight so an obviously closed service never takes a lock.
    await this.assertServiceOpen(service);

    // Created outside the main transaction to keep the locked section short.
    const queue = await this.getOrCreateTodayQueue(serviceId);

    const ticketId = await withRetryableTransaction(async (tx) => {
      // ① serialise every concurrent joiner for this service
      const locked = await queueRepository.lockForUpdate(tx, Number(queue.id));
      if (!locked) throw AppError.notFound('That queue could not be found.');

      // ② re-evaluate every guard inside the lock
      await this.assertServiceOpen(service, tx);
      this.assertQueueAcceptsTickets(locked, service.name);

      // Rule 1 — one active ticket per user per service
      const existing = await ticketRepository.findActiveForUserService(userId, serviceId, tx);
      if (existing) {
        throw AppError.conflict(
          'DUPLICATE_ACTIVE_TICKET',
          `You already have an active ticket (${existing.ticket_number}) for ${service.name}.`,
        );
      }

      // Optional policy: may a customer take a second ticket after being served today?
      if (Number(service.allow_rejoin) === 0) {
        const servedAlready = await ticketRepository.hasTerminalTicketToday(userId, Number(locked.id), tx);
        if (servedAlready) {
          throw AppError.conflict('REJOIN_NOT_ALLOWED', `You have already been served by ${service.name} today.`);
        }
      }

      // Rule 3 — capacity is the stricter of the queue setting and the daily cap
      const capacity = Math.min(Number(service.max_queue_size), Number(service.daily_capacity));
      if (Number(locked.last_issued_number) >= capacity) {
        throw AppError.conflict('QUEUE_FULL', `The ${service.name} queue has reached its capacity for today.`);
      }

      // ③ allocate the next number under the lock
      const sequenceNumber = Number(locked.last_issued_number) + 1;
      await queueRepository.setIssuedNumber(tx, Number(locked.id), sequenceNumber);

      const peopleAhead = await ticketRepository.countAhead(Number(locked.id), sequenceNumber, tx);
      const { estimatedWaitMinutes } = await estimateWaitMinutes(
        peopleAhead,
        {
          serviceId,
          configuredMinutes: Number(service.estimated_service_time) || Number(service.average_service_time),
          queueDate: locked.queue_date,
        },
        tx,
      );

      // ④ the unique keys on (queue_id, sequence_number) and
      //    (queue_id, ticket_number) are the safety net here
      const newTicketId = await ticketRepository.insert(
        {
          queueId: Number(locked.id),
          serviceId,
          userId,
          ticketNumber: formatTicketNumber(service.code, sequenceNumber),
          sequenceNumber,
          estimatedWaitMinutes,
          joinedAt: toSqlDateTime(),
        },
        tx,
      );

      // ⑤ audit trail and notification, same transaction (Rule 14)
      await eventRepository.insert(tx, newTicketId, userId, 'joined', `Joined the ${service.name} queue`);
      await notificationService.ticketIssued(
        tx,
        {
          ticketId: newTicketId,
          userId,
          ticketNumber: formatTicketNumber(service.code, sequenceNumber),
          serviceName: service.name,
        },
        peopleAhead + 1,
        estimatedWaitMinutes,
      );

      return newTicketId;
    });

    const ticketRow = await ticketRepository.findDetailById(ticketId);
    if (!ticketRow) throw AppError.internal();

    return {
      ticket: toTicketDto(ticketRow),
      position: await this.getPositionFor(ticketId),
    };
  },

  /**
   * Live position for a ticket (Rule 13). Recomputed from rows on every call —
   * this is the endpoint the ticket screen polls.
   */
  async getPositionFor(ticketId: number, options: { notify?: boolean } = {}): Promise<TicketPositionDto> {
    const ticket = await ticketRepository.findDetailById(ticketId);
    if (!ticket) throw AppError.notFound('That ticket could not be found.');

    const service = await serviceRepository.findWithSettings(Number(ticket.service_id));
    if (!service) throw AppError.notFound('That service could not be found.');

    const isWaiting = ticket.status === 'waiting';
    const peopleAhead = isWaiting
      ? await ticketRepository.countAhead(Number(ticket.queue_id), Number(ticket.sequence_number))
      : 0;

    const nowServing = await ticketRepository.findNowServing(Number(ticket.queue_id));
    const { estimatedWaitMinutes, basis } = await estimateWaitMinutes(peopleAhead, {
      serviceId: Number(ticket.service_id),
      configuredMinutes: Number(service.estimated_service_time) || Number(service.average_service_time),
      queueDate: ticket.queue_date,
    });

    // Polling is what drives the "your turn is approaching" notification; the
    // notification service de-duplicates it so this is safe to call often.
    if (options.notify && isWaiting) {
      await notificationService.maybeNotifyApproaching(
        {
          ticketId: Number(ticket.id),
          userId: Number(ticket.user_id),
          ticketNumber: ticket.ticket_number,
          serviceName: ticket.service_name,
        },
        peopleAhead,
        Number(service.notification_threshold),
      );
    }

    return {
      ticketId: Number(ticket.id),
      ticketNumber: ticket.ticket_number,
      status: ticket.status,
      position: isWaiting ? peopleAhead + 1 : null,
      peopleAhead,
      nowServing: nowServing?.ticket_number ?? null,
      estimatedWaitMinutes,
      activeCounters: basis.activeCounters,
      counter:
        ticket.counter_id != null
          ? { id: Number(ticket.counter_id), counterNumber: Number(ticket.counter_number), name: ticket.counter_name ?? '' }
          : null,
      queueStatus: ticket.queue_status,
      updatedAt: new Date().toISOString(),
    };
  },

  /** The cheap polling payload for a whole queue. */
  async getQueueStatus(queueId: number): Promise<QueueStatusDto> {
    const queue = await queueRepository.findWithService(queueId);
    if (!queue) throw AppError.notFound('That queue could not be found.');

    const service = await serviceRepository.findWithSettings(Number(queue.service_id));
    if (!service) throw AppError.notFound('That service could not be found.');

    const [counts, nowServing, basis, averageWait] = await Promise.all([
      ticketRepository.countByStatus(queueId),
      ticketRepository.findNowServing(queueId),
      estimationBasis({
        serviceId: Number(queue.service_id),
        configuredMinutes: Number(service.estimated_service_time) || Number(service.average_service_time),
        queueDate: queue.queue_date,
      }),
      ticketRepository.measuredWaitMinutes(queueId),
    ]);

    const capacity = Math.min(Number(service.max_queue_size), Number(service.daily_capacity));
    const issued = Number(queue.last_issued_number);

    return {
      queueId: Number(queue.id),
      serviceId: Number(queue.service_id),
      serviceName: queue.service_name,
      serviceCode: queue.service_code,
      queueDate: String(queue.queue_date).slice(0, 10),
      status: queue.status,
      nowServing: nowServing?.ticket_number ?? null,
      currentNumber: Number(queue.current_number),
      waitingCount: counts.waiting,
      servingCount: counts.called + counts.serving,
      completedToday: counts.completed,
      cancelledToday: counts.cancelled,
      skippedToday: counts.skipped,
      noShowToday: counts.no_show,
      ticketsIssuedToday: issued,
      activeCounters: basis.activeCounters,
      averageWaitMinutes: averageWait == null ? 0 : Math.round(averageWait),
      averageServiceMinutes: basis.measuredMinutes == null ? basis.effectiveMinutes : Math.round(basis.measuredMinutes),
      estimatedWaitMinutes: Math.ceil((counts.waiting * basis.effectiveMinutes) / basis.activeCounters),
      isAcceptingTickets: queue.status === 'waiting' && service.status === 'open' && issued < capacity,
      capacityRemaining: Math.max(0, capacity - issued),
      updatedAt: new Date().toISOString(),
    };
  },

  /** Compact summary embedded in each service card (§15). */
  async getQueueSummary(serviceId: number): Promise<QueueSummaryDto> {
    const queue = await this.getOrCreateTodayQueue(serviceId);
    const status = await this.getQueueStatus(Number(queue.id));
    return {
      queueId: status.queueId,
      status: status.status,
      waitingCount: status.waitingCount,
      servingCount: status.servingCount,
      completedToday: status.completedToday,
      nowServing: status.nowServing,
      estimatedWaitMinutes: status.estimatedWaitMinutes,
      activeCounters: status.activeCounters,
      isAcceptingTickets: status.isAcceptingTickets,
      capacityRemaining: status.capacityRemaining,
    };
  },

  /** §35 — the administrator's live board for one service. */
  async getMonitor(queueId: number) {
    const queue = await queueRepository.findWithService(queueId);
    if (!queue) throw AppError.notFound('That queue could not be found.');

    const [status, counters, waiting, live] = await Promise.all([
      this.getQueueStatus(queueId),
      counterRepository.listDetailed({ serviceId: Number(queue.service_id) }),
      ticketRepository.listWaiting(queueId, 50),
      ticketRepository.listLive(queueId),
    ]);

    return {
      service: { id: Number(queue.service_id), name: queue.service_name, code: queue.service_code },
      queue: status,
      nowServing: status.nowServing,
      counters: counters.map(toCounterDto),
      serving: live.map((row) => toTicketDto(row, { includeCustomer: true })),
      waiting: waiting.map((row) => toTicketDto(row, { includeCustomer: true })),
      stats: {
        waiting: status.waitingCount,
        serving: status.servingCount,
        completed: status.completedToday,
        cancelled: status.cancelledToday,
        skipped: status.skippedToday,
        noShow: status.noShowToday,
        averageWaitMinutes: status.averageWaitMinutes,
        averageServiceMinutes: status.averageServiceMinutes,
      },
    };
  },

  async setStatus(queueId: number, status: QueueStatus): Promise<QueueStatusDto> {
    const queue = await queueRepository.findById(queueId);
    if (!queue) throw AppError.notFound('That queue could not be found.');
    await queueRepository.setStatus(queueId, status);
    return this.getQueueStatus(queueId);
  },

  async listForDate(filters: { queueDate?: string; serviceId?: number; status?: QueueStatus }) {
    const queueDate = filters.queueDate ?? todayDate();
    const rows = await queueRepository.listForDate({ ...filters, queueDate });
    return Promise.all(rows.map((row) => this.getQueueStatus(Number(row.id))));
  },

  /** Today's opening window, used by the service cards. */
  async getTodayHours(serviceId: number, when = new Date()) {
    const hours = await serviceRepository.findHoursForDay(serviceId, dayOfWeek(when));
    if (!hours || hours.status === 'closed') {
      return { opensAt: hours ? shortTime(hours.opening_time) : null, closesAt: hours ? shortTime(hours.closing_time) : null, isOpenNow: false };
    }
    const nowMinutes = minutesSinceMidnight(when);
    return {
      opensAt: shortTime(hours.opening_time),
      closesAt: shortTime(hours.closing_time),
      isOpenNow: nowMinutes >= minutesSinceMidnight(hours.opening_time) && nowMinutes < minutesSinceMidnight(hours.closing_time),
    };
  },
};
