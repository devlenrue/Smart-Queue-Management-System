/**
 * The staff console's read model (§20, §37) and the one write a staff member
 * owns outside the ticket lifecycle: opening and closing their own counter.
 *
 * Everything a counter clerk sees comes from here, so the Flutter app needs a
 * single request per screen rather than stitching five together.
 */
import { AppError } from '../utils/AppError';
import { addDays, todayDate } from '../utils/datetime';
import { isAdmin } from '../middleware/rbac';
import { assignmentRepository } from '../repositories/assignment.repository';
import { counterRepository, type CounterRow } from '../repositories/counter.repository';
import { queueRepository } from '../repositories/queue.repository';
import { serviceRepository } from '../repositories/service.repository';
import { statisticsRepository, type DateRange } from '../repositories/statistics.repository';
import { ticketRepository } from '../repositories/ticket.repository';
import { userRepository } from '../repositories/user.repository';
import { queueService } from './queue.service';
import { toTicketDto } from '../serializers/ticket.serializer';
import {
  toStaffAssignmentDto,
  toStaffCounterDto,
  type StaffDashboardDto,
  type StaffStatisticsDto,
} from '../serializers/staff.serializer';
import type { AuthUser, CounterStatus, TicketStatus } from '../types/domain';

/** How many of the next tickets the dashboard previews. */
const UP_NEXT_LIMIT = 5;

/** Default statistics window: the last 7 days, inclusive of today. */
const DEFAULT_RANGE_DAYS = 6;

export const staffService = {
  /**
   * Which service and counter is this person working?
   *
   * Staff get their active assignment. Admins have none — they supervise every
   * service — so they may name a service explicitly, and default to the first
   * open one. Returning `null` rather than throwing lets the dashboard render
   * a useful "ask an administrator to assign you" state.
   */
  async resolveContext(
    actor: AuthUser,
    overrides: { serviceId?: number; counterId?: number } = {},
  ): Promise<{ serviceId: number | null; counter: CounterRow | null; assignmentId: number | null }> {
    if (isAdmin(actor.role)) {
      let serviceId = overrides.serviceId ?? null;
      if (serviceId == null) {
        const { rows } = await serviceRepository.list({ status: 'open', page: 1, limit: 1 });
        serviceId = rows[0] ? Number(rows[0].id) : null;
      }
      const counter = overrides.counterId ? await counterRepository.findById(overrides.counterId) : null;
      return { serviceId, counter, assignmentId: null };
    }

    const assignment = await assignmentRepository.findActiveForStaff(actor.id);
    if (!assignment) return { serviceId: null, counter: null, assignmentId: null };

    const serviceId = Number(assignment.service_id);
    // A staff member may only look at their own service, whatever they ask for.
    if (overrides.serviceId && Number(overrides.serviceId) !== serviceId) {
      throw AppError.forbidden(
        'You are not assigned to this service, so you cannot manage its queue.',
        'NOT_ASSIGNED_TO_SERVICE',
      );
    }

    const counter =
      (await counterRepository.findByStaff(actor.id)) ??
      (assignment.counter_id ? await counterRepository.findById(Number(assignment.counter_id)) : null);

    return { serviceId, counter, assignmentId: Number(assignment.id) };
  },

  /**
   * `GET /dashboard/staff` — the whole first screen in one round trip:
   * who I am serving, who is next, and how the day is going.
   */
  async getDashboard(actor: AuthUser, overrides: { serviceId?: number; counterId?: number } = {}): Promise<StaffDashboardDto> {
    const context = await this.resolveContext(actor, overrides);
    const assignment = isAdmin(actor.role) ? null : await assignmentRepository.findActiveForStaff(actor.id);

    if (context.serviceId == null) {
      return {
        today: todayDate(),
        assigned: false,
        assignment: null,
        service: null,
        counter: null,
        queue: null,
        currentTicket: null,
        upNext: [],
        stats: {
          waiting: 0,
          servedToday: 0,
          skippedToday: 0,
          noShowToday: 0,
          cancelledToday: 0,
          averageServiceMinutes: 0,
          averageWaitMinutes: 0,
        },
      };
    }

    const service = await serviceRepository.findById(context.serviceId);
    if (!service) throw AppError.notFound('That service could not be found.');

    const queue = await queueRepository.getOrCreate(context.serviceId);
    const queueId = Number(queue.id);
    const today = String(queue.queue_date).slice(0, 10);

    const [status, waiting, currentRow, totals, averages, tally] = await Promise.all([
      queueService.getQueueStatus(queueId),
      ticketRepository.listWaiting(queueId, UP_NEXT_LIMIT),
      context.counter ? ticketRepository.findActiveAtCounter(Number(context.counter.id)) : Promise.resolve(null),
      statisticsRepository.staffTotals(actor.id, { from: today, to: today }),
      statisticsRepository.staffAverages(actor.id, { from: today, to: today }),
      context.counter
        ? statisticsRepository.counterTallyForDate(Number(context.counter.id), today)
        : Promise.resolve(null),
    ]);

    // The ticket at the counter is read through the detail projection so the
    // card can show the customer's name and phone without a second request.
    const currentTicket = currentRow ? await ticketRepository.findDetailById(Number(currentRow.id)) : null;

    return {
      today,
      assigned: true,
      assignment: assignment ? toStaffAssignmentDto(assignment) : null,
      service: { id: Number(service.id), name: service.name, code: service.code, status: service.status },
      counter: context.counter ? toStaffCounterDto(context.counter) : null,
      queue: status,
      currentTicket: currentTicket ? toTicketDto(currentTicket, { includeCustomer: true }) : null,
      upNext: waiting.map((row) => toTicketDto(row, { includeCustomer: true })),
      stats: {
        waiting: status.waitingCount,
        // "Served today" is what *this* person completed, not the service total.
        servedToday: totals.served,
        skippedToday: totals.skipped,
        noShowToday: totals.no_show,
        cancelledToday: tally?.cancelled ?? 0,
        averageServiceMinutes:
          averages.averageServiceMinutes == null ? 0 : Math.round(averages.averageServiceMinutes),
        averageWaitMinutes: averages.averageWaitMinutes == null ? 0 : Math.round(averages.averageWaitMinutes),
      },
    };
  },

  /**
   * `GET /staff/:id/statistics` (§37). A staff member may read their own
   * figures; admins may read anyone's.
   */
  async getStatistics(staffId: number, actor: AuthUser, range: Partial<DateRange> = {}): Promise<StaffStatisticsDto> {
    this.assertSelfOrAdmin(staffId, actor);

    const staff = await userRepository.findById(staffId);
    if (!staff) throw AppError.notFound('That staff member could not be found.');

    const resolved = resolveRange(range);
    const [totals, averages, byDay] = await Promise.all([
      statisticsRepository.staffTotals(staffId, resolved),
      statisticsRepository.staffAverages(staffId, resolved),
      statisticsRepository.staffByDay(staffId, resolved),
    ]);

    const handled = totals.served + totals.skipped + totals.no_show;

    return {
      staff: {
        id: Number(staff.id),
        name: `${staff.first_name} ${staff.last_name}`.trim(),
        email: staff.email,
        role: staff.role,
      },
      range: resolved,
      ticketsServed: totals.served,
      ticketsSkipped: totals.skipped,
      ticketsNoShow: totals.no_show,
      ticketsRecalled: totals.recalled,
      ticketsHandled: handled,
      // Share of dispositions that ended in a completed service. A counter that
      // skips half its queue is doing something wrong, and this shows it.
      completionRate: handled === 0 ? 0 : Math.round((totals.served / handled) * 100),
      averageServiceMinutes:
        averages.averageServiceMinutes == null ? 0 : round1(averages.averageServiceMinutes),
      averageWaitMinutes: averages.averageWaitMinutes == null ? 0 : round1(averages.averageWaitMinutes),
      byDay: byDay.map((row) => ({
        date: row.day,
        served: row.served,
        averageServiceMinutes: row.averageServiceMinutes == null ? 0 : round1(row.averageServiceMinutes),
      })),
    };
  },

  /**
   * `GET /staff/:id/tickets` — the counter's own history. Not in the original
   * endpoint list; added in Phase 6 because the "what did I handle today?"
   * screen cannot be built from `/tickets`, which is scoped to the caller's
   * *own* tickets as a customer.
   */
  async getHandledTickets(
    staffId: number,
    actor: AuthUser,
    filters: { from?: string; to?: string; status?: TicketStatus; page: number; limit: number },
  ) {
    this.assertSelfOrAdmin(staffId, actor);

    const range = resolveRange({ from: filters.from, to: filters.to });
    const { rows, total } = await statisticsRepository.staffHandledTickets(staffId, {
      range,
      statuses: filters.status ? [filters.status] : undefined,
      page: filters.page,
      limit: filters.limit,
    });

    return { tickets: rows.map((row) => toTicketDto(row, { includeCustomer: true })), total, range };
  },

  /**
   * `PATCH /counters/:id/status` — a clerk going on or off duty.
   *
   * Refusing to go offline mid-service is what stops a customer being
   * abandoned at a counter that no longer exists (Rule 5's neighbour).
   */
  async setCounterStatus(counterId: number, actor: AuthUser, status: CounterStatus): Promise<CounterRow> {
    const counter = await counterRepository.findById(counterId);
    if (!counter) throw AppError.notFound('That counter could not be found.');

    if (!isAdmin(actor.role)) {
      if (counter.assigned_staff_id == null || Number(counter.assigned_staff_id) !== actor.id) {
        throw AppError.forbidden('You can only change the status of your own counter.');
      }
    }

    if (status !== 'busy') {
      const active = await ticketRepository.findActiveAtCounter(counterId);
      if (active) {
        throw AppError.conflict(
          'COUNTER_BUSY',
          `${counter.name} is still handling ticket ${active.ticket_number}. Finish or skip it first.`,
        );
      }
    }

    await counterRepository.setStatus(counterId, status);
    const updated = await counterRepository.findById(counterId);
    return updated ?? counter;
  },

  /** `GET /counters?serviceId=` — the picker behind "call to which counter?". */
  async listCounters(actor: AuthUser, filters: { serviceId?: number; status?: CounterStatus }) {
    if (!isAdmin(actor.role) && filters.serviceId) {
      const assigned = await assignmentRepository.isAssignedToService(actor.id, filters.serviceId);
      if (!assigned) {
        throw AppError.forbidden(
          'You are not assigned to this service, so you cannot manage its queue.',
          'NOT_ASSIGNED_TO_SERVICE',
        );
      }
    }
    return counterRepository.listDetailed(filters);
  },

  /** Staff read their own figures; admins read anyone's. */
  assertSelfOrAdmin(staffId: number, actor: AuthUser): void {
    if (isAdmin(actor.role)) return;
    if (Number(staffId) !== actor.id) {
      throw AppError.forbidden('You can only view your own statistics.');
    }
  },
};

/** Defaults to the last seven days when the client sends no range. */
function resolveRange(range: Partial<DateRange>): DateRange {
  const to = range.to ?? todayDate();
  const from = range.from ?? addDays(to, -DEFAULT_RANGE_DAYS);
  // A reversed range is a client mistake, not an error worth a 422.
  return from <= to ? { from, to } : { from: to, to: from };
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}
