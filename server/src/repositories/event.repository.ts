/** SQL for `queue_events` — the append-only audit trail. */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { toSqlDateTime } from '../utils/datetime';
import type { EventType } from '../types/domain';

export interface EventRow {
  id: number;
  ticket_id: number;
  user_id: number | null;
  event_type: EventType;
  description: string | null;
  created_at: string;
}

export interface EventWithActorRow extends EventRow {
  actor_first_name: string | null;
  actor_last_name: string | null;
}

export const eventRepository = {
  /** `actorId` is who caused the event — the customer or the staff member. */
  async insert(
    tx: DbConn,
    ticketId: number,
    actorId: number | null,
    eventType: EventType,
    description: string | null = null,
  ): Promise<number> {
    const result = await tx.execute(
      'INSERT INTO queue_events (ticket_id, user_id, event_type, description, created_at) VALUES (?, ?, ?, ?, ?)',
      [ticketId, actorId, eventType, description, toSqlDateTime()],
    );
    return result.insertId;
  },

  async existsForTicket(ticketId: number, eventType: EventType, conn: DbConn = getDb()): Promise<boolean> {
    const rows = await conn.query<{ id: number }>(
      'SELECT id FROM queue_events WHERE ticket_id = ? AND event_type = ? LIMIT 1',
      [ticketId, eventType],
    );
    return rows.length > 0;
  },

  /** Ticket timeline. `threshold_notified` is internal and filtered out. */
  async listForTicket(ticketId: number, conn: DbConn = getDb()): Promise<EventWithActorRow[]> {
    return conn.query<EventWithActorRow>(
      `SELECT e.*, u.first_name AS actor_first_name, u.last_name AS actor_last_name
         FROM queue_events e
         LEFT JOIN users u ON u.id = e.user_id
        WHERE e.ticket_id = ? AND e.event_type <> 'threshold_notified'
        ORDER BY e.created_at ASC, e.id ASC`,
      [ticketId],
    );
  },

  async countByTypeForStaff(
    staffId: number,
    eventType: EventType,
    range: { from: string; to: string },
    conn: DbConn = getDb(),
  ): Promise<number> {
    const rows = await conn.query<{ n: number }>(
      `SELECT COUNT(*) AS n
         FROM queue_events e
         JOIN queue_tickets t ON t.id = e.ticket_id
         JOIN queues q ON q.id = t.queue_id
        WHERE e.user_id = ? AND e.event_type = ? AND q.queue_date BETWEEN ? AND ?`,
      [staffId, eventType, range.from, range.to],
    );
    return Number(rows[0]?.n ?? 0);
  },
};
