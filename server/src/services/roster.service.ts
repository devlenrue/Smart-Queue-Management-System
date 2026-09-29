/**
 * Who works where (§54, §55).
 *
 * Two tables model the same fact from different angles, and they must never
 * disagree:
 *
 *   service_counters.assigned_staff_id  — "this desk belongs to Jane"
 *   staff_assignments (status='active') — "Jane is posted to Finance, desk 1"
 *
 * The first is what the queue engine reads on every call-next (Rule 4/Rule 5);
 * the second is the audit trail an administrator reads. Every write in this
 * file therefore updates *both*, inside one transaction, so a crash can never
 * leave a clerk holding a counter they are not posted to.
 *
 * A posting is also never taken away mid-customer: if the counter is holding a
 * called or serving ticket the operation answers 409 COUNTER_BUSY rather than
 * stranding somebody at a desk that has just been reassigned.
 */
import { withTransaction } from '../db';
import { AppError } from '../utils/AppError';
import { hashPassword } from '../utils/password';
import { assignmentRepository } from '../repositories/assignment.repository';
import { counterRepository, type CounterRow } from '../repositories/counter.repository';
import { serviceRepository } from '../repositories/service.repository';
import { ticketRepository } from '../repositories/ticket.repository';
import { userRepository, type StaffListFilters } from '../repositories/user.repository';
import { toCounterDto, type CounterDto } from '../serializers/service.serializer';
import { toStaffRosterDto, type StaffRosterDto } from '../serializers/admin.serializer';
import type { DbConn } from '../db/types';
import type { CounterStatus } from '../types/domain';

async function requireCounter(id: number): Promise<CounterRow> {
  const counter = await counterRepository.findById(id);
  if (!counter) throw AppError.notFound('That counter could not be found.');
  return counter;
}

async function requireService(id: number) {
  const service = await serviceRepository.findById(id);
  if (!service) throw AppError.notFound('That service could not be found.');
  return service;
}

async function requireStaff(id: number) {
  const row = await userRepository.findById(id);
  if (!row) throw AppError.notFound('That staff member could not be found.');
  if (row.role !== 'staff') {
    throw AppError.conflict('CONFLICT', 'That user is not a staff member, so they cannot be posted to a counter.');
  }
  return row;
}

/** Refuses to move a desk that is mid-customer. */
async function assertCounterIdle(counter: CounterRow, verb: string): Promise<void> {
  const active = await ticketRepository.findActiveAtCounter(Number(counter.id));
  if (active) {
    throw AppError.conflict(
      'COUNTER_BUSY',
      `${counter.name} is still handling ticket ${active.ticket_number}, so it cannot be ${verb} yet.`,
    );
  }
}

/** Reads a roster row back after a write, so the client never has to re-fetch. */
async function rosterRow(staffId: number): Promise<StaffRosterDto> {
  const row = await userRepository.findStaffRow(staffId);
  if (!row) throw AppError.notFound('That staff member could not be found.');
  return toStaffRosterDto(row);
}

async function counterDto(id: number): Promise<CounterDto> {
  const counter = await requireCounter(id);
  const rows = await counterRepository.listDetailed({ serviceId: Number(counter.service_id) });
  const row = rows.find((candidate) => Number(candidate.id) === id);
  if (!row) throw AppError.notFound('That counter could not be found.');
  return toCounterDto(row);
}

/**
 * The single place a posting is created.
 *
 * Ends whatever the staff member was doing, frees the desk they were holding,
 * then attaches the new one — in that order, so the unique key on
 * `service_counters.assigned_staff_id` is never violated half-way through.
 */
async function post(
  tx: DbConn,
  staffId: number,
  serviceId: number,
  counterId: number | null,
): Promise<void> {
  const previous = await counterRepository.findByStaff(staffId, tx);
  if (previous && Number(previous.id) !== counterId) {
    await counterRepository.assignStaff(Number(previous.id), null, tx);
  }

  await assignmentRepository.endAllForStaff(staffId, tx);

  if (counterId != null) {
    await assignmentRepository.endAllForCounter(counterId, tx);
    await counterRepository.assignStaff(counterId, staffId, tx);
  }

  await assignmentRepository.create({ staffId, serviceId, counterId }, tx);
}

export const rosterService = {
  // -------------------------------------------------------------------- staff

  async listStaff(filters: StaffListFilters): Promise<{ staff: StaffRosterDto[]; total: number }> {
    const { rows, total } = await userRepository.listStaff(filters);
    return { staff: rows.map(toStaffRosterDto), total };
  },

  async getStaff(id: number): Promise<StaffRosterDto> {
    await requireStaff(id);
    return rosterRow(id);
  },

  /**
   * Creates a counter clerk. Staff accounts are never self-registered — §13
   * only ever produces customers — so this is the one way one comes into
   * existence, and it may post them to a desk in the same transaction.
   */
  async createStaff(input: {
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    password: string;
    serviceId?: number;
    counterId?: number;
  }): Promise<StaffRosterDto> {
    if (await userRepository.emailExists(input.email)) {
      throw AppError.conflict('EMAIL_TAKEN', 'An account with this email address already exists.');
    }
    if (await userRepository.phoneExists(input.phone)) {
      throw AppError.conflict('PHONE_TAKEN', 'An account with this phone number already exists.');
    }

    let serviceId = input.serviceId ?? null;
    if (input.counterId != null) {
      const counter = await requireCounter(input.counterId);
      if (counter.assigned_staff_id != null) {
        throw AppError.conflict('STAFF_ALREADY_ASSIGNED', `${counter.name} already has a staff member.`);
      }
      if (serviceId != null && Number(counter.service_id) !== serviceId) {
        throw AppError.conflict('CONFLICT', 'That counter belongs to a different service.');
      }
      serviceId = Number(counter.service_id);
    }
    if (serviceId != null) await requireService(serviceId);

    const passwordHash = await hashPassword(input.password);

    const staffId = await withTransaction(async (tx) => {
      const id = await userRepository.create(
        {
          firstName: input.firstName,
          lastName: input.lastName,
          email: input.email,
          phone: input.phone,
          passwordHash,
          role: 'staff',
          status: 'active',
        },
        tx,
      );
      if (serviceId != null) await post(tx, id, serviceId, input.counterId ?? null);
      return id;
    });

    return rosterRow(staffId);
  },

  async updateStaff(
    id: number,
    input: { firstName?: string; lastName?: string; phone?: string; status?: 'active' | 'inactive' | 'suspended' },
  ): Promise<StaffRosterDto> {
    const row = await requireStaff(id);

    if (input.phone && input.phone !== row.phone && (await userRepository.phoneExists(input.phone, id))) {
      throw AppError.conflict('PHONE_TAKEN', 'An account with this phone number already exists.');
    }

    // A clerk who is about to be deactivated must not keep a desk reserved —
    // and must not be deactivated at all while a customer is still at it.
    const deactivating = input.status != null && input.status !== 'active' && input.status !== row.status;
    const heldCounter = deactivating ? await counterRepository.findByStaff(id) : null;
    if (heldCounter) await assertCounterIdle(heldCounter, 'released');

    await userRepository.updateProfile(id, {
      firstName: input.firstName,
      lastName: input.lastName,
      phone: input.phone,
    });

    if (input.status && input.status !== row.status) {
      await withTransaction(async (tx) => {
        await userRepository.updateStatus(id, input.status!, tx);
        if (deactivating) {
          if (heldCounter) await counterRepository.assignStaff(Number(heldCounter.id), null, tx);
          await assignmentRepository.endAllForStaff(id, tx);
        }
      });
    }

    return rosterRow(id);
  },

  /** `POST /staff/:id/assign { serviceId, counterId? }` */
  async assign(staffId: number, input: { serviceId: number; counterId?: number | null }): Promise<StaffRosterDto> {
    await requireStaff(staffId);
    await requireService(input.serviceId);

    const previous = await counterRepository.findByStaff(staffId);
    if (previous && Number(previous.id) !== input.counterId) await assertCounterIdle(previous, 'reassigned');

    if (input.counterId != null) {
      const counter = await requireCounter(input.counterId);
      if (Number(counter.service_id) !== input.serviceId) {
        throw AppError.conflict('CONFLICT', 'That counter belongs to a different service.');
      }
      if (counter.assigned_staff_id != null && Number(counter.assigned_staff_id) !== staffId) {
        throw AppError.conflict('STAFF_ALREADY_ASSIGNED', `${counter.name} already has a staff member.`);
      }
    }

    await withTransaction((tx) => post(tx, staffId, input.serviceId, input.counterId ?? null));
    return rosterRow(staffId);
  },

  /**
   * `POST /staff/:id/unassign`.
   *
   * The posting is *ended*, never deleted: `staff_assignments` is the record
   * of who was responsible for a desk on a given day, and the queue events
   * already written still point at it.
   */
  async unassign(staffId: number, input: { assignmentId?: number } = {}): Promise<StaffRosterDto> {
    await requireStaff(staffId);

    const counter = await counterRepository.findByStaff(staffId);
    if (counter) await assertCounterIdle(counter, 'released');

    await withTransaction(async (tx) => {
      if (counter) await counterRepository.assignStaff(Number(counter.id), null, tx);
      if (input.assignmentId) await assignmentRepository.endById(input.assignmentId, tx);
      else await assignmentRepository.endAllForStaff(staffId, tx);
    });

    return rosterRow(staffId);
  },

  // ------------------------------------------------------------------ counters

  async createCounter(input: {
    serviceId: number;
    counterNumber: number;
    name: string;
    status?: CounterStatus;
    staffId?: number;
  }): Promise<CounterDto> {
    await requireService(input.serviceId);

    if (await counterRepository.numberExists(input.serviceId, input.counterNumber)) {
      throw AppError.conflict(
        'COUNTER_NUMBER_TAKEN',
        `This service already has a counter numbered ${input.counterNumber}.`,
      );
    }

    if (input.staffId != null) {
      await requireStaff(input.staffId);
      const held = await counterRepository.findByStaff(input.staffId);
      if (held) {
        throw AppError.conflict('STAFF_ALREADY_ASSIGNED', 'That staff member already holds another counter.');
      }
    }

    const counterId = await withTransaction(async (tx) => {
      const id = await counterRepository.create(
        {
          serviceId: input.serviceId,
          counterNumber: input.counterNumber,
          name: input.name,
          // A counter with nobody at it is offline, whatever the request says.
          status: input.staffId != null ? (input.status ?? 'available') : 'offline',
          assignedStaffId: input.staffId ?? null,
        },
        tx,
      );
      if (input.staffId != null) await post(tx, input.staffId, input.serviceId, id);
      return id;
    });

    return counterDto(counterId);
  },

  async updateCounter(
    id: number,
    input: { counterNumber?: number; name?: string; status?: CounterStatus },
  ): Promise<CounterDto> {
    const counter = await requireCounter(id);

    if (input.counterNumber != null && input.counterNumber !== Number(counter.counter_number)) {
      if (await counterRepository.numberExists(Number(counter.service_id), input.counterNumber, id)) {
        throw AppError.conflict(
          'COUNTER_NUMBER_TAKEN',
          `This service already has a counter numbered ${input.counterNumber}.`,
        );
      }
    }

    if (input.status && input.status !== 'busy') await assertCounterIdle(counter, 'changed');

    await counterRepository.update(id, input);
    return counterDto(id);
  },

  /** `POST /counters/:id/assign { staffId }` — the same posting, from the desk's side. */
  async assignCounter(counterId: number, staffId: number): Promise<CounterDto> {
    const counter = await requireCounter(counterId);
    await requireStaff(staffId);

    if (counter.assigned_staff_id != null && Number(counter.assigned_staff_id) !== staffId) {
      await assertCounterIdle(counter, 'reassigned');
    }

    const held = await counterRepository.findByStaff(staffId);
    if (held && Number(held.id) !== counterId) {
      await assertCounterIdle(held, 'released');
    }

    await withTransaction((tx) => post(tx, staffId, Number(counter.service_id), counterId));
    return counterDto(counterId);
  },

  /** `DELETE /counters/:id/assign` — frees the desk and ends the posting. */
  async unassignCounter(counterId: number): Promise<CounterDto> {
    const counter = await requireCounter(counterId);
    if (counter.assigned_staff_id == null) return counterDto(counterId);

    await assertCounterIdle(counter, 'released');

    await withTransaction(async (tx) => {
      await assignmentRepository.endAllForCounter(counterId, tx);
      await counterRepository.assignStaff(counterId, null, tx);
    });

    return counterDto(counterId);
  },

  async removeCounter(counterId: number): Promise<void> {
    const counter = await requireCounter(counterId);
    await assertCounterIdle(counter, 'deleted');

    await withTransaction(async (tx) => {
      await assignmentRepository.endAllForCounter(counterId, tx);
      await counterRepository.remove(counterId, tx);
    });
  },
};
