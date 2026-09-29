/**
 * Deterministic, idempotent seed data (§73 of the brief).
 *
 * Deterministic: a fixed-seed PRNG, so screenshots, demos and report numbers
 * are reproducible between runs.
 * Idempotent: every table is cleared first, inside one transaction.
 *
 * It deliberately produces three days of history so the reports and charts of
 * Phase 8 have something real to aggregate.
 */
import bcrypt from 'bcryptjs';
import { config } from '../config/env';
import { logger } from '../utils/logger';
import { addDays, toSqlDate, toSqlDateTime, todayDate } from '../utils/datetime';
import { getDb } from './index';
import type { DbConn } from './types';

// --------------------------------------------------------------------------
// Deterministic pseudo-random helpers
// --------------------------------------------------------------------------

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const random = mulberry32(20260929);
const intBetween = (min: number, max: number): number => min + Math.floor(random() * (max - min + 1));
const pick = <T>(items: readonly T[]): T => items[Math.floor(random() * items.length)];

function shuffled<T>(items: readonly T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

/** A Date at a given time on a 'YYYY-MM-DD' day. */
function at(day: string, hour: number, minute: number): Date {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(y, m - 1, d, hour, minute, intBetween(0, 59));
}

function plusMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}

// --------------------------------------------------------------------------
// Static seed definitions
// --------------------------------------------------------------------------

interface SeedUser {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  role: 'customer' | 'staff' | 'admin' | 'super_admin';
  status?: 'active' | 'inactive' | 'suspended';
}

const STAFF_USERS: SeedUser[] = [
  { firstName: 'Jane', lastName: 'Wanjiku', email: 'jane.staff@smartqueue.test', phone: '+254700000011', role: 'staff' },
  { firstName: 'Peter', lastName: 'Otieno', email: 'peter.staff@smartqueue.test', phone: '+254700000012', role: 'staff' },
  { firstName: 'Mary', lastName: 'Achieng', email: 'mary.staff@smartqueue.test', phone: '+254700000013', role: 'staff' },
  { firstName: 'David', lastName: 'Kamau', email: 'david.staff@smartqueue.test', phone: '+254700000014', role: 'staff' },
  { firstName: 'Grace', lastName: 'Njeri', email: 'grace.staff@smartqueue.test', phone: '+254700000015', role: 'staff' },
];

const CUSTOMER_NAMES: Array<[string, string]> = [
  ['John', 'Doe'], ['Mary', 'Atieno'], ['Brian', 'Mutua'], ['Faith', 'Chebet'], ['Kevin', 'Omondi'],
  ['Alice', 'Nduta'], ['Samuel', 'Kiprop'], ['Cynthia', 'Wambui'], ['Dennis', 'Mwangi'], ['Esther', 'Akinyi'],
  ['Victor', 'Barasa'], ['Nancy', 'Wairimu'], ['Collins', 'Ochieng'], ['Diana', 'Moraa'], ['Felix', 'Kariuki'],
];

interface SeedService {
  name: string;
  code: string;
  description: string;
  category: string;
  averageServiceTime: number;
  dailyCapacity: number;
  counters: number;
  maxQueueSize: number;
}

const SERVICES: SeedService[] = [
  { name: 'Finance Office', code: 'FIN', description: 'Fee payments, statements, refunds and financial clearance.', category: 'Administration', averageServiceTime: 6, dailyCapacity: 200, counters: 3, maxQueueSize: 120 },
  { name: 'Registrar', code: 'REG', description: 'Transcripts, certificates, unit registration and student records.', category: 'Academic', averageServiceTime: 8, dailyCapacity: 150, counters: 3, maxQueueSize: 100 },
  { name: 'Admissions', code: 'ADM', description: 'Applications, admission letters, deferments and readmission.', category: 'Academic', averageServiceTime: 10, dailyCapacity: 100, counters: 2, maxQueueSize: 80 },
  { name: 'Student Affairs', code: 'STA', description: 'Accommodation, welfare, clubs, identity cards and counselling.', category: 'Student Services', averageServiceTime: 7, dailyCapacity: 120, counters: 2, maxQueueSize: 90 },
  { name: 'Library', code: 'LIB', description: 'Membership, borrowing, fines, research help and study rooms.', category: 'Student Services', averageServiceTime: 4, dailyCapacity: 180, counters: 3, maxQueueSize: 140 },
];

/**
 * staff index → [service index, counter number]
 *
 * The brief asks for five staff and five services, so one service is
 * deliberately left unstaffed (Library). That is realistic, and it exercises
 * the "no active counters" branch of the waiting-time estimate.
 */
const STAFF_POSTINGS: Array<[number, number]> = [
  [0, 1], // Jane   → Finance Counter 1
  [0, 2], // Peter  → Finance Counter 2
  [1, 1], // Mary   → Registrar Counter 1
  [2, 1], // David  → Admissions Counter 1
  [3, 1], // Grace  → Student Affairs Counter 1
];

// --------------------------------------------------------------------------
// Seed runner
// --------------------------------------------------------------------------

const TABLES_IN_DELETE_ORDER = [
  'announcements',
  'notifications',
  'queue_events',
  'queue_tickets',
  'queues',
  'staff_assignments',
  'queue_settings',
  'service_hours',
  'service_counters',
  'services',
  'revoked_tokens',
  'system_settings',
  'users',
];

async function clearAll(tx: DbConn): Promise<void> {
  if (tx.dialect === 'mysql') await tx.execute('SET FOREIGN_KEY_CHECKS = 0');
  for (const table of TABLES_IN_DELETE_ORDER) {
    await tx.execute(`DELETE FROM ${table}`);
  }
  if (tx.dialect === 'mysql') {
    await tx.execute('SET FOREIGN_KEY_CHECKS = 1');
    for (const table of TABLES_IN_DELETE_ORDER) {
      await tx.execute(`ALTER TABLE ${table} AUTO_INCREMENT = 1`);
    }
  } else {
    await tx.execute("DELETE FROM sqlite_sequence WHERE name IN ('" + TABLES_IN_DELETE_ORDER.join("','") + "')");
  }
}

export interface SeedSummary {
  users: number;
  services: number;
  counters: number;
  queues: number;
  tickets: number;
  events: number;
  notifications: number;
  announcements: number;
}

export async function runSeed(): Promise<SeedSummary> {
  const db = getDb();
  const passwordHash = await bcrypt.hash(config.seedPassword, config.bcryptRounds);
  const now = new Date();
  const nowSql = toSqlDateTime(now);

  return db.transaction(async (tx) => {
    await clearAll(tx);

    // ---------------------------------------------------------------- users
    const insertUser = async (user: SeedUser): Promise<number> => {
      const result = await tx.execute(
        `INSERT INTO users (first_name, last_name, email, phone, password_hash, role, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [user.firstName, user.lastName, user.email, user.phone, passwordHash, user.role, user.status ?? 'active', nowSql, nowSql],
      );
      return result.insertId;
    };

    await insertUser({ firstName: 'Sarah', lastName: 'Kimani', email: 'super@smartqueue.test', phone: '+254700000001', role: 'super_admin' });
    await insertUser({ firstName: 'Michael', lastName: 'Odhiambo', email: 'admin@smartqueue.test', phone: '+254700000002', role: 'admin' });
    const secondAdminId = await insertUser({ firstName: 'Lucy', lastName: 'Mwende', email: 'lucy.admin@smartqueue.test', phone: '+254700000003', role: 'admin' });

    const staffIds: number[] = [];
    for (const staff of STAFF_USERS) staffIds.push(await insertUser(staff));

    const customerIds: number[] = [];
    for (let i = 0; i < CUSTOMER_NAMES.length; i += 1) {
      const [firstName, lastName] = CUSTOMER_NAMES[i];
      const email = i === 0 ? 'john.doe@smartqueue.test' : `${firstName}.${lastName}@smartqueue.test`.toLowerCase();
      customerIds.push(
        await insertUser({
          firstName,
          lastName,
          email,
          phone: `+2547111000${String(i + 10).padStart(2, '0')}`,
          role: 'customer',
          status: i === 14 ? 'inactive' : 'active',
        }),
      );
    }

    // ------------------------------------------------------------- services
    const serviceIds: number[] = [];
    const counterIdsByService: number[][] = [];

    for (const service of SERVICES) {
      const serviceResult = await tx.execute(
        `INSERT INTO services (name, code, description, category, average_service_time, daily_capacity, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?)`,
        [service.name, service.code, service.description, service.category, service.averageServiceTime, service.dailyCapacity, nowSql, nowSql],
      );
      const serviceId = serviceResult.insertId;
      serviceIds.push(serviceId);

      await tx.execute(
        `INSERT INTO queue_settings (service_id, max_queue_size, allow_cancellation, allow_rejoin, notification_threshold, estimated_service_time, created_at, updated_at)
         VALUES (?, ?, 1, 1, ?, ?, ?, ?)`,
        [serviceId, service.maxQueueSize, config.queue.defaultNotifyThreshold, service.averageServiceTime, nowSql, nowSql],
      );

      // Mon–Thu 08:00–17:00, Fri 08:00–16:00, weekends closed.
      for (let day = 0; day <= 6; day += 1) {
        const isWeekend = day === 0 || day === 6;
        await tx.execute(
          `INSERT INTO service_hours (service_id, day_of_week, opening_time, closing_time, status)
           VALUES (?, ?, ?, ?, ?)`,
          [serviceId, day, '08:00:00', day === 5 ? '16:00:00' : '17:00:00', isWeekend ? 'closed' : 'open'],
        );
      }

      const counterIds: number[] = [];
      for (let n = 1; n <= service.counters; n += 1) {
        const counterResult = await tx.execute(
          `INSERT INTO service_counters (service_id, counter_number, name, status, assigned_staff_id, created_at, updated_at)
           VALUES (?, ?, ?, 'offline', NULL, ?, ?)`,
          [serviceId, n, `${service.name} Counter ${n}`, nowSql, nowSql],
        );
        counterIds.push(counterResult.insertId);
      }
      counterIdsByService.push(counterIds);
    }

    // ---------------------------------------------------- staff assignments
    for (let i = 0; i < STAFF_POSTINGS.length; i += 1) {
      const [serviceIndex, counterNumber] = STAFF_POSTINGS[i];
      const staffId = staffIds[i];
      const serviceId = serviceIds[serviceIndex];
      const counterId = counterIdsByService[serviceIndex][counterNumber - 1];

      await tx.execute('UPDATE service_counters SET assigned_staff_id = ?, status = ?, updated_at = ? WHERE id = ?', [
        staffId,
        'available',
        nowSql,
        counterId,
      ]);
      await tx.execute(
        `INSERT INTO staff_assignments (staff_id, service_id, counter_id, assigned_at, unassigned_at, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, NULL, 'active', ?, ?)`,
        [staffId, serviceId, counterId, nowSql, nowSql, nowSql],
      );
    }

    // ------------------------------------------------ queues + tickets + events
    const today = todayDate();
    const days = [addDays(today, -2), addDays(today, -1), today];

    let ticketCount = 0;
    let eventCount = 0;
    let notificationCount = 0;
    let queueCount = 0;

    const addEvent = async (ticketId: number, userId: number | null, type: string, description: string, when: Date): Promise<void> => {
      await tx.execute(
        'INSERT INTO queue_events (ticket_id, user_id, event_type, description, created_at) VALUES (?, ?, ?, ?, ?)',
        [ticketId, userId, type, description, toSqlDateTime(when)],
      );
      eventCount += 1;
    };

    const addNotification = async (
      userId: number,
      ticketId: number | null,
      title: string,
      message: string,
      type: string,
      isRead: boolean,
      when: Date,
    ): Promise<void> => {
      await tx.execute(
        'INSERT INTO notifications (user_id, ticket_id, title, message, type, is_read, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [userId, ticketId, title, message, type, isRead ? 1 : 0, toSqlDateTime(when)],
      );
      notificationCount += 1;
    };

    for (let serviceIndex = 0; serviceIndex < SERVICES.length; serviceIndex += 1) {
      const service = SERVICES[serviceIndex];
      const serviceId = serviceIds[serviceIndex];
      const counterIds = counterIdsByService[serviceIndex];
      const staffForService = STAFF_POSTINGS.map((posting, i) => (posting[0] === serviceIndex ? staffIds[i] : null)).filter(
        (id): id is number => id !== null,
      );
      // Only a counter with a staff member behind it can hold a live ticket.
      const staffedCounterIds = STAFF_POSTINGS.filter((posting) => posting[0] === serviceIndex).map(
        (posting) => counterIds[posting[1] - 1],
      );

      for (const day of days) {
        const isToday = day === today;
        const totalTickets = isToday ? intBetween(8, 14) : intBetween(14, 22);
        const queueResult = await tx.execute(
          `INSERT INTO queues (service_id, queue_date, status, current_number, last_issued_number, total_served, created_at, updated_at)
           VALUES (?, ?, ?, 0, 0, 0, ?, ?)`,
          [serviceId, day, isToday ? 'waiting' : 'closed', `${day} 07:55:00`, nowSql],
        );
        const queueId = queueResult.insertId;
        queueCount += 1;

        // Each customer takes at most one ticket per service per day, which is
        // also what business Rule 1 requires for the active ones.
        const dayCustomers = shuffled(customerIds).slice(0, Math.min(totalTickets, customerIds.length));
        const ticketTotal = dayCustomers.length;

        // How today's queue is laid out: some done, up to 2 at counters, rest waiting.
        const completedTarget = isToday ? Math.max(2, Math.floor(ticketTotal * 0.45)) : ticketTotal;
        const activeCounterIds = staffedCounterIds.slice(0, 2);

        let served = 0;
        let lastCalledSequence = 0;
        let joinClock = at(day, 8, 5);

        for (let index = 0; index < ticketTotal; index += 1) {
          const sequence = index + 1;
          const userId = dayCustomers[index];
          const ticketNumber = `${service.code}-${String(sequence).padStart(3, '0')}`;
          joinClock = plusMinutes(joinClock, intBetween(2, 9));
          const joinedAt = joinClock;
          const estimated = Math.max(1, Math.round(((ticketTotal - index) * service.averageServiceTime) / Math.max(1, activeCounterIds.length)));

          let status: string;
          let counterId: number | null = null;
          let calledAt: Date | null = null;
          let startedAt: Date | null = null;
          let completedAt: Date | null = null;
          let cancelledAt: Date | null = null;

          const inCompletedBand = index < completedTarget;

          if (inCompletedBand) {
            // A realistic tail of outcomes among the finished tickets.
            const roll = random();
            if (roll < 0.08) {
              status = 'cancelled';
              cancelledAt = plusMinutes(joinedAt, intBetween(2, 15));
            } else if (roll < 0.13) {
              status = 'skipped';
              calledAt = plusMinutes(joinedAt, intBetween(8, 30));
            } else if (roll < 0.17) {
              status = 'no_show';
              calledAt = plusMinutes(joinedAt, intBetween(8, 30));
            } else {
              status = 'completed';
              counterId = staffedCounterIds.length > 0 ? pick(staffedCounterIds) : pick(counterIds);
              calledAt = plusMinutes(joinedAt, intBetween(6, 28));
              startedAt = plusMinutes(calledAt, intBetween(0, 2));
              completedAt = plusMinutes(startedAt, Math.max(1, service.averageServiceTime + intBetween(-2, 4)));
              served += 1;
              lastCalledSequence = sequence;
            }
          } else if (isToday && index === completedTarget && activeCounterIds.length > 0) {
            status = 'serving';
            counterId = activeCounterIds[0];
            calledAt = plusMinutes(joinedAt, intBetween(6, 20));
            startedAt = plusMinutes(calledAt, 1);
            lastCalledSequence = sequence;
          } else if (isToday && index === completedTarget + 1 && activeCounterIds.length > 1) {
            status = 'called';
            counterId = activeCounterIds[1];
            calledAt = plusMinutes(joinedAt, intBetween(6, 20));
            lastCalledSequence = sequence;
          } else {
            status = 'waiting';
          }

          const ticketResult = await tx.execute(
            `INSERT INTO queue_tickets
               (queue_id, service_id, user_id, ticket_number, sequence_number, status, counter_id,
                estimated_wait_minutes, joined_at, called_at, service_started_at, completed_at, cancelled_at,
                created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              queueId, serviceId, userId, ticketNumber, sequence, status, counterId, estimated,
              toSqlDateTime(joinedAt),
              calledAt ? toSqlDateTime(calledAt) : null,
              startedAt ? toSqlDateTime(startedAt) : null,
              completedAt ? toSqlDateTime(completedAt) : null,
              cancelledAt ? toSqlDateTime(cancelledAt) : null,
              toSqlDateTime(joinedAt), toSqlDateTime(completedAt ?? calledAt ?? joinedAt),
            ],
          );
          const ticketId = ticketResult.insertId;
          ticketCount += 1;

          const actingStaffId = staffForService.length > 0 ? pick(staffForService) : null;

          await addEvent(ticketId, userId, 'joined', `Joined the ${service.name} queue`, joinedAt);
          if (calledAt) await addEvent(ticketId, actingStaffId, 'called', `Called to a ${service.name} counter`, calledAt);
          if (startedAt) await addEvent(ticketId, actingStaffId, 'service_started', 'Service started', startedAt);
          if (completedAt) await addEvent(ticketId, actingStaffId, 'completed', 'Service completed', completedAt);
          if (cancelledAt) await addEvent(ticketId, userId, 'cancelled', 'Cancelled by the customer', cancelledAt);
          if (status === 'skipped' && calledAt) await addEvent(ticketId, actingStaffId, 'skipped', 'Skipped — customer not present', plusMinutes(calledAt, 2));
          if (status === 'no_show' && calledAt) await addEvent(ticketId, actingStaffId, 'no_show', 'Marked as a no-show', plusMinutes(calledAt, 3));

          // Notifications only for today, so the demo inbox is believable.
          if (isToday) {
            await addNotification(userId, ticketId, `Ticket ${ticketNumber} issued`, `You are in the ${service.name} queue. Estimated wait ~${estimated} minutes.`, 'queue', true, joinedAt);
            if (status === 'called' || status === 'serving') {
              const counterNumber = counterIds.indexOf(counterId ?? -1) + 1;
              await addNotification(userId, ticketId, `Ticket ${ticketNumber} is being called`, `Please proceed to Counter ${counterNumber}.`, 'queue', false, calledAt ?? joinedAt);
            }
            if (status === 'completed') {
              await addNotification(userId, ticketId, 'Service completed', `Your ${service.name} service is complete. Thank you.`, 'queue', random() < 0.5, completedAt ?? joinedAt);
            }
          }
        }

        await tx.execute(
          'UPDATE queues SET current_number = ?, last_issued_number = ?, total_served = ?, updated_at = ? WHERE id = ?',
          [lastCalledSequence, ticketTotal, served, nowSql, queueId],
        );

        // Counters serving a ticket right now must read as busy.
        if (isToday) {
          for (const counterId of activeCounterIds) {
            const busy = await tx.query<{ n: number }>(
              "SELECT COUNT(*) AS n FROM queue_tickets WHERE counter_id = ? AND status IN ('called','serving')",
              [counterId],
            );
            if (Number(busy[0]?.n ?? 0) > 0) {
              await tx.execute('UPDATE service_counters SET status = ?, updated_at = ? WHERE id = ? AND assigned_staff_id IS NOT NULL', ['busy', nowSql, counterId]);
            }
          }
        }
      }
    }

    // -------------------------------------------------------- announcements
    const announcements = [
      {
        title: 'System maintenance on Saturday',
        content: 'SmartQueue will be unavailable between 10:00 PM and 11:00 PM on Saturday for scheduled maintenance. No tickets can be issued during that window.',
        serviceId: null as number | null,
      },
      {
        title: 'Finance Office closes at 3 PM today',
        content: 'The Finance Office will close at 3:00 PM today for a departmental meeting. Please collect your ticket before 2:30 PM.',
        serviceId: serviceIds[0],
      },
      {
        title: 'Library extended hours during exams',
        content: 'The Library service desk will stay open until 8:00 PM for the duration of the examination period.',
        serviceId: serviceIds[4],
      },
    ];

    for (const announcement of announcements) {
      await tx.execute(
        `INSERT INTO announcements (title, content, service_id, created_by, published_at, expires_at, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'published', ?, ?)`,
        [announcement.title, announcement.content, announcement.serviceId, secondAdminId, nowSql, `${addDays(today, 7)} 23:59:59`, nowSql, nowSql],
      );
    }

    // ------------------------------------------------------ system settings
    const settings: Array<[string, string, string]> = [
      ['system_name', 'SmartQueue', 'Name shown in the application header'],
      ['institution_name', 'University Service Centre', 'Institution operating the queues'],
      ['default_notification_threshold', String(config.queue.defaultNotifyThreshold), 'Notify a customer when this many people remain ahead'],
      ['allow_registration', 'true', 'Whether new customers may self-register'],
      ['support_email', 'support@smartqueue.test', 'Contact address shown to users'],
    ];
    for (const [key, value, description] of settings) {
      await tx.execute(
        'INSERT INTO system_settings (setting_key, setting_value, description, updated_at) VALUES (?, ?, ?, ?)',
        [key, value, description, nowSql],
      );
    }

    const summary: SeedSummary = {
      users: 3 + staffIds.length + customerIds.length,
      services: serviceIds.length,
      counters: counterIdsByService.reduce((total, ids) => total + ids.length, 0),
      queues: queueCount,
      tickets: ticketCount,
      events: eventCount,
      notifications: notificationCount,
      announcements: announcements.length,
    };

    logger.info(
      `Seed complete — ${summary.users} users, ${summary.services} services, ${summary.counters} counters, ` +
        `${summary.queues} queues, ${summary.tickets} tickets, ${summary.events} events, ` +
        `${summary.notifications} notifications, ${summary.announcements} announcements.`,
    );
    logger.info(`Demo password for every seeded account: ${config.seedPassword}`);
    logger.info('  super@smartqueue.test · admin@smartqueue.test · jane.staff@smartqueue.test · john.doe@smartqueue.test');

    return summary;
  });
}

/** Exposed for tests that need a known "today". */
export const seedToday = (): string => toSqlDate(new Date());
