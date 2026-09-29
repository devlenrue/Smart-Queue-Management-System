/**
 * THE TICKET STATE MACHINE.
 *
 * Every transition in docs/queue-engine.md §1.1 is implemented here, each one
 * inside a single transaction that writes the ticket, the counter, the queue
 * counters, the audit event and the notification together (Rule 14).
 *
 * No transition is reachable except through `applyTransition`, which is where
 * Rules 6–10 are enforced.
 */
import { getDb, withTransaction } from '../db';
import type { DbConn } from '../db/types';
import { AppError } from '../utils/AppError';
import { ticketRepository, type TicketRow } from '../repositories/ticket.repository';
import { queueRepository } from '../repositories/queue.repository';
import { counterRepository, type CounterRow } from '../repositories/counter.repository';
import { assignmentRepository } from '../repositories/assignment.repository';
import { eventRepository } from '../repositories/event.repository';
import { notificationService } from './notification.service';
import { queueService } from './queue.service';
import { toEventDto, toTicketDto, type TicketDto } from '../serializers/ticket.serializer';
import { isAdmin } from '../middleware/rbac';
import type { AuthUser, TicketStatus } from '../types/domain';

/** The legal edges of the state machine. Anything absent is a 409. */
const ALLOWED_TRANSITIONS: Record<TicketStatus, readonly TicketStatus[]> = {
  waiting: ['called', 'cancelled', 'skipped'],
  called: ['serving', 'skipped', 'no_show', 'called'],
  serving: ['completed'],
  completed: [],
  cancelled: [],
  skipped: [],
  no_show: [],
};

/** "Ticket FIN-001 is <being served> …" */
const HUMAN_STATUS: Record<TicketStatus, string> = {
  waiting: 'waiting',
  called: 'called',
  serving: 'being served',
  completed: 'completed',
  cancelled: 'cancelled',
  skipped: 'skipped',
  no_show: 'a no-show',
};

/** "… and cannot be <started>." — the action, not the state name. */
const ATTEMPTED_ACTION: Record<TicketStatus, string> = {
  waiting: 'returned to the queue',
  called: 'called',
  serving: 'started',
  completed: 'completed',
  cancelled: 'cancelled',
  skipped: 'skipped',
  no_show: 'marked as a no-show',
};

/** Terminal tickets get a plainer sentence than a state-machine complaint. */
const ALREADY_FINISHED: Partial<Record<TicketStatus, string>> = {
  completed: 'has already been completed',
  cancelled: 'has already been cancelled',
  skipped: 'was skipped',
  no_show: 'was marked as a no-show',
};

export function canTransition(from: TicketStatus, to: TicketStatus): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}

function assertTransition(ticket: TicketRow, to: TicketStatus): void {
  if (canTransition(ticket.status, to)) return;

  const finished = ALREADY_FINISHED[ticket.status];
  throw AppError.conflict(
    'INVALID_STATE_TRANSITION',
    finished
      ? `Ticket ${ticket.ticket_number} ${finished} and can no longer be changed.`
      : `Ticket ${ticket.ticket_number} is ${HUMAN_STATUS[ticket.status]} and cannot be ${ATTEMPTED_ACTION[to]}.`,
  );
}

export interface TicketActionResult {
  ticket: TicketDto;
  queue: { waitingCount: number; nowServing: string | null; completedToday: number };
}

export const ticketService = {
  // -------------------------------------------------------------------------
  // Authorisation helpers
  // -------------------------------------------------------------------------

  /**
   * Rule 4 — only staff with an active assignment to the service may act on
   * its tickets. Admins supervise all services, so they are exempt.
   */
  async assertStaffOwnsService(actor: AuthUser, serviceId: number, conn: DbConn = getDb()): Promise<void> {
    if (isAdmin(actor.role)) return;
    if (!(await assignmentRepository.isAssignedToService(actor.id, serviceId, conn))) {
      throw AppError.forbidden(
        'You are not assigned to this service, so you cannot manage its queue.',
        'NOT_ASSIGNED_TO_SERVICE',
      );
    }
  },

  /** Resolves the counter to act at: the one asked for, or the staff's own. */
  async resolveCounter(actor: AuthUser, serviceId: number, counterId?: number, conn: DbConn = getDb()): Promise<CounterRow> {
    let counter: CounterRow | null = null;

    if (counterId) {
      counter = await counterRepository.findById(counterId, conn);
      if (!counter) throw AppError.notFound('That counter could not be found.');
    } else {
      counter = await counterRepository.findByStaff(actor.id, conn);
      if (!counter) {
        throw AppError.badRequest('You are not assigned to a counter. Ask an administrator to assign you to one.');
      }
    }

    if (Number(counter.service_id) !== Number(serviceId)) {
      throw AppError.badRequest('That counter belongs to a different service.');
    }
    if (counter.status === 'offline') {
      throw AppError.conflict('COUNTER_OFFLINE', `${counter.name} is offline. Set it to available before calling a ticket.`);
    }
    return counter;
  },

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  async getById(ticketId: number, actor: AuthUser): Promise<TicketDto> {
    const row = await ticketRepository.findDetailById(ticketId);
    if (!row) throw AppError.notFound('That ticket could not be found.');

    const isOwner = Number(row.user_id) === actor.id;
    const isStaffOrAdmin = actor.role !== 'customer';
    if (!isOwner && !isStaffOrAdmin) throw AppError.forbidden('You can only view your own tickets.');

    return toTicketDto(row, { includeCustomer: isStaffOrAdmin });
  },

  async getEvents(ticketId: number, actor: AuthUser) {
    const row = await ticketRepository.findDetailById(ticketId);
    if (!row) throw AppError.notFound('That ticket could not be found.');
    if (Number(row.user_id) !== actor.id && actor.role === 'customer') {
      throw AppError.forbidden('You can only view your own tickets.');
    }
    const events = await eventRepository.listForTicket(ticketId);
    return events.map(toEventDto);
  },

  async listForUser(
    userId: number,
    filters: { status?: 'active' | TicketStatus; page: number; limit: number; serviceId?: number },
  ) {
    const statuses =
      filters.status === 'active'
        ? (['waiting', 'called', 'serving'] as TicketStatus[])
        : filters.status
          ? ([filters.status] as TicketStatus[])
          : undefined;

    const { rows, total } = await ticketRepository.list({
      userId,
      serviceId: filters.serviceId,
      statuses,
      page: filters.page,
      limit: filters.limit,
    });
    return { tickets: rows.map((row) => toTicketDto(row)), total };
  },

  /** The customer dashboard's "do I have a live ticket?" question. */
  async getActiveForUser(userId: number): Promise<TicketDto[]> {
    const rows = await ticketRepository.findActiveForUser(userId);
    return rows.map((row) => toTicketDto(row));
  },

  // -------------------------------------------------------------------------
  // Customer transition
  // -------------------------------------------------------------------------

  /** waiting → cancelled (§27). Only the owner, only while waiting. */
  async cancel(ticketId: number, actor: AuthUser): Promise<TicketActionResult> {
    return this.runTransition(ticketId, async (tx, ticket) => {
      const isOwner = Number(ticket.user_id) === actor.id;
      if (!isOwner && !isAdmin(actor.role)) {
        throw AppError.forbidden('You can only cancel your own ticket.');
      }

      const service = await this.loadServiceSettings(tx, Number(ticket.service_id));
      if (Number(service.allow_cancellation) === 0) {
        throw AppError.conflict('CANCELLATION_NOT_ALLOWED', `${service.name} does not allow tickets to be cancelled.`);
      }

      assertTransition(ticket, 'cancelled');
      await ticketRepository.transition(tx, Number(ticket.id), 'cancelled', { timestampColumn: 'cancelled_at' });
      await eventRepository.insert(tx, Number(ticket.id), actor.id, 'cancelled', 'Cancelled by the customer');
      return 'Ticket cancelled';
    });
  },

  // -------------------------------------------------------------------------
  // Staff transitions
  // -------------------------------------------------------------------------

  /**
   * §21 — Call Next.
   *
   * Locks the queue, then locks the lowest waiting ticket, so two staff
   * pressing the button at the same instant receive different tickets.
   */
  async callNext(actor: AuthUser, serviceId: number, counterId?: number): Promise<TicketActionResult> {
    await this.assertStaffOwnsService(actor, serviceId);
    const counter = await this.resolveCounter(actor, serviceId, counterId);
    const queue = await queueService.getOrCreateTodayQueue(serviceId);

    const ticketId = await withTransaction(async (tx) => {
      const locked = await queueRepository.lockForUpdate(tx, Number(queue.id));
      if (!locked) throw AppError.notFound('That queue could not be found.');

      await this.assertCounterFree(tx, counter);

      const next = await ticketRepository.lockNextWaiting(tx, Number(locked.id));
      if (!next) {
        throw AppError.notFound('There are no customers waiting in this queue.', 'NO_WAITING_TICKETS');
      }

      await this.applyCall(tx, next, counter, actor);
      return Number(next.id);
    });

    return this.buildResult(ticketId, 'called');
  },

  /** Call one specific waiting ticket rather than the next in line. */
  async call(ticketId: number, actor: AuthUser, counterId?: number): Promise<TicketActionResult> {
    const ticket = await ticketRepository.findById(ticketId);
    if (!ticket) throw AppError.notFound('That ticket could not be found.');
    await this.assertStaffOwnsService(actor, Number(ticket.service_id));
    const counter = await this.resolveCounter(actor, Number(ticket.service_id), counterId);

    await withTransaction(async (tx) => {
      const locked = await ticketRepository.lockById(tx, ticketId);
      if (!locked) throw AppError.notFound('That ticket could not be found.');
      assertTransition(locked, 'called');
      await this.assertCounterFree(tx, counter);
      await this.applyCall(tx, locked, counter, actor);
    });

    return this.buildResult(ticketId, 'called');
  },

  /** §26 — recall. The ticket stays `called`; only an event + notification. */
  async recall(ticketId: number, actor: AuthUser): Promise<TicketActionResult> {
    return this.runTransition(ticketId, async (tx, ticket) => {
      await this.assertStaffOwnsService(actor, Number(ticket.service_id), tx);
      if (ticket.status !== 'called') {
        throw AppError.conflict(
          'INVALID_STATE_TRANSITION',
          `Only a ticket that has been called can be recalled. ${ticket.ticket_number} is ${HUMAN_STATUS[ticket.status]}.`,
        );
      }

      const detail = await ticketRepository.findDetailById(Number(ticket.id), tx);
      await eventRepository.insert(tx, Number(ticket.id), actor.id, 'recalled', 'Recalled to the counter');
      await notificationService.ticketRecalled(tx, {
        ticketId: Number(ticket.id),
        userId: Number(ticket.user_id),
        ticketNumber: ticket.ticket_number,
        serviceName: detail?.service_name ?? 'the service',
        counterNumber: detail?.counter_number ?? null,
      });
      return `Ticket ${ticket.ticket_number} recalled`;
    });
  },

  /** §22 — called → serving. */
  async start(ticketId: number, actor: AuthUser): Promise<TicketActionResult> {
    return this.runTransition(ticketId, async (tx, ticket) => {
      await this.assertStaffOwnsService(actor, Number(ticket.service_id), tx);
      assertTransition(ticket, 'serving');

      await ticketRepository.transition(tx, Number(ticket.id), 'serving', { timestampColumn: 'service_started_at' });
      await eventRepository.insert(tx, Number(ticket.id), actor.id, 'service_started', 'Service started');
      return `Service started for ${ticket.ticket_number}`;
    });
  },

  /** §23 — serving → completed. Also bumps the queue's served counter. */
  async complete(ticketId: number, actor: AuthUser): Promise<TicketActionResult> {
    return this.runTransition(ticketId, async (tx, ticket) => {
      await this.assertStaffOwnsService(actor, Number(ticket.service_id), tx);
      assertTransition(ticket, 'completed');

      await ticketRepository.transition(tx, Number(ticket.id), 'completed', { timestampColumn: 'completed_at' });
      await queueRepository.incrementServed(tx, Number(ticket.queue_id));
      await this.releaseCounter(tx, ticket.counter_id);
      await eventRepository.insert(tx, Number(ticket.id), actor.id, 'completed', 'Service completed');

      const detail = await ticketRepository.findDetailById(Number(ticket.id), tx);
      await notificationService.serviceCompleted(tx, {
        ticketId: Number(ticket.id),
        userId: Number(ticket.user_id),
        ticketNumber: ticket.ticket_number,
        serviceName: detail?.service_name ?? 'the service',
      });
      return `Service completed for ${ticket.ticket_number}`;
    });
  },

  /** §24 — skip. Allowed from waiting or called. */
  async skip(ticketId: number, actor: AuthUser, reason?: string): Promise<TicketActionResult> {
    return this.runTransition(ticketId, async (tx, ticket) => {
      await this.assertStaffOwnsService(actor, Number(ticket.service_id), tx);
      assertTransition(ticket, 'skipped');

      await ticketRepository.transition(tx, Number(ticket.id), 'skipped');
      await this.releaseCounter(tx, ticket.counter_id);
      await eventRepository.insert(tx, Number(ticket.id), actor.id, 'skipped', reason ?? 'Skipped by staff');

      const detail = await ticketRepository.findDetailById(Number(ticket.id), tx);
      await notificationService.ticketSkipped(tx, {
        ticketId: Number(ticket.id),
        userId: Number(ticket.user_id),
        ticketNumber: ticket.ticket_number,
        serviceName: detail?.service_name ?? 'the service',
      });
      return `Ticket ${ticket.ticket_number} skipped`;
    });
  },

  /** §25 — no-show. Only meaningful for a ticket that was actually called. */
  async noShow(ticketId: number, actor: AuthUser): Promise<TicketActionResult> {
    return this.runTransition(ticketId, async (tx, ticket) => {
      await this.assertStaffOwnsService(actor, Number(ticket.service_id), tx);
      assertTransition(ticket, 'no_show');

      await ticketRepository.transition(tx, Number(ticket.id), 'no_show');
      await this.releaseCounter(tx, ticket.counter_id);
      await eventRepository.insert(tx, Number(ticket.id), actor.id, 'no_show', 'Customer did not respond');

      const detail = await ticketRepository.findDetailById(Number(ticket.id), tx);
      await notificationService.ticketNoShow(tx, {
        ticketId: Number(ticket.id),
        userId: Number(ticket.user_id),
        ticketNumber: ticket.ticket_number,
        serviceName: detail?.service_name ?? 'the service',
      });
      return `Ticket ${ticket.ticket_number} marked as a no-show`;
    });
  },

  // -------------------------------------------------------------------------
  // Shared internals
  // -------------------------------------------------------------------------

  /** Rule 5 — a counter may hold only one live ticket. */
  async assertCounterFree(tx: DbConn, counter: CounterRow): Promise<void> {
    const occupied = await ticketRepository.findActiveAtCounter(Number(counter.id), tx);
    if (occupied) {
      throw AppError.conflict(
        'COUNTER_BUSY',
        `${counter.name} is already serving ticket ${occupied.ticket_number}. Complete or skip it first.`,
      );
    }
  },

  async releaseCounter(tx: DbConn, counterId: number | null): Promise<void> {
    if (counterId == null) return;
    const counter = await counterRepository.findById(counterId, tx);
    // A counter with nobody behind it stays offline.
    if (!counter || counter.assigned_staff_id == null) return;
    await counterRepository.setStatus(counterId, 'available', tx);
  },

  /** The shared body of "call" — used by both callNext and call. */
  async applyCall(tx: DbConn, ticket: TicketRow, counter: CounterRow, actor: AuthUser): Promise<void> {
    await ticketRepository.transition(tx, Number(ticket.id), 'called', {
      counterId: Number(counter.id),
      timestampColumn: 'called_at',
    });
    await counterRepository.setStatus(Number(counter.id), 'busy', tx);
    await queueRepository.setCurrentNumber(tx, Number(ticket.queue_id), Number(ticket.sequence_number));
    await eventRepository.insert(tx, Number(ticket.id), actor.id, 'called', `Called to ${counter.name}`);

    const detail = await ticketRepository.findDetailById(Number(ticket.id), tx);
    await notificationService.ticketCalled(tx, {
      ticketId: Number(ticket.id),
      userId: Number(ticket.user_id),
      ticketNumber: ticket.ticket_number,
      serviceName: detail?.service_name ?? 'the service',
      counterNumber: Number(counter.counter_number),
    });
  },

  async loadServiceSettings(conn: DbConn, serviceId: number) {
    const { serviceRepository } = await import('../repositories/service.repository');
    const service = await serviceRepository.findWithSettings(serviceId, conn);
    if (!service) throw AppError.notFound('That service could not be found.');
    return service;
  },

  /**
   * Wraps a transition: open a transaction, lock the ticket, run the body,
   * then return the refreshed ticket plus a queue snapshot so the staff UI
   * needs a single round trip.
   */
  async runTransition(
    ticketId: number,
    body: (tx: DbConn, ticket: TicketRow) => Promise<string>,
  ): Promise<TicketActionResult> {
    const message = await withTransaction(async (tx) => {
      const ticket = await ticketRepository.lockById(tx, ticketId);
      if (!ticket) throw AppError.notFound('That ticket could not be found.');
      return body(tx, ticket);
    });
    return this.buildResult(ticketId, message);
  },

  async buildResult(ticketId: number, _message: string): Promise<TicketActionResult> {
    const row = await ticketRepository.findDetailById(ticketId);
    if (!row) throw AppError.internal();

    const [counts, nowServing] = await Promise.all([
      ticketRepository.countByStatus(Number(row.queue_id)),
      ticketRepository.findNowServing(Number(row.queue_id)),
    ]);

    return {
      ticket: toTicketDto(row, { includeCustomer: true }),
      queue: {
        waitingCount: counts.waiting,
        nowServing: nowServing?.ticket_number ?? null,
        completedToday: counts.completed,
      },
    };
  },
};
