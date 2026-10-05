const express = require('express');

const pool = require('../config/db');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate } = require('../middleware/auth');
const {
  positiveInteger,
  httpError
} = require('../utils/validation');
const {
  formatService,
  formatTicket,
  getService,
  getCustomerQueueStatus
} = require('../utils/queue');

const router = express.Router();

router.post('/join', authenticate, asyncHandler(async (req, res) => {
  const serviceId = positiveInteger(req.body.serviceId, 'Service ID');
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    // Locking the service row serializes ticket-number allocation for this
    // service. This prevents two simultaneous joins from receiving the same
    // daily ticket number.
    const [serviceRows] = await connection.execute(
      `SELECT id, name, description, average_service_minutes, is_active,
              created_at, updated_at
         FROM services
        WHERE id = ? AND is_active = TRUE
        FOR UPDATE`,
      [serviceId]
    );
    if (!serviceRows.length) {
      throw httpError(404, 'Service was not found or is inactive.');
    }
    const service = serviceRows[0];

    const [existingRows] = await connection.execute(
      `SELECT t.id, t.service_id, t.user_id, t.ticket_number, t.ticket_date,
              t.status, t.joined_at, t.called_at, t.served_at, t.cancelled_at,
              t.skipped_at, t.called_by, t.completed_by
         FROM tickets t
        WHERE t.service_id = ?
          AND t.user_id = ?
          AND t.ticket_date = CURRENT_DATE
          AND t.status IN ('waiting', 'serving')
        LIMIT 1`,
      [serviceId, req.user.id]
    );
    if (existingRows.length) {
      await connection.rollback();
      return res.status(409).json({
        message: 'You already have an active ticket for this service today.',
        ticket: formatTicket(existingRows[0])
      });
    }

    const [nextRows] = await connection.execute(
      `SELECT COALESCE(MAX(ticket_number), 0) + 1 AS next_ticket_number
         FROM tickets
        WHERE service_id = ? AND ticket_date = CURRENT_DATE`,
      [serviceId]
    );
    const nextTicketNumber = Number(nextRows[0].next_ticket_number);

    const [insertResult] = await connection.execute(
      `INSERT INTO tickets (service_id, user_id, ticket_number, ticket_date, status)
       VALUES (?, ?, ?, CURRENT_DATE, 'waiting')`,
      [serviceId, req.user.id, nextTicketNumber]
    );

    const [ticketRows] = await connection.execute(
      `SELECT id, service_id, user_id, ticket_number, ticket_date, status,
              joined_at, called_at, served_at, cancelled_at, skipped_at,
              called_by, completed_by
         FROM tickets
        WHERE id = ?`,
      [insertResult.insertId]
    );

    await connection.commit();
    return res.status(201).json({
      message: 'You joined the queue successfully.',
      service: formatService(service),
      ticket: formatTicket(ticketRows[0])
    });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

router.get('/service/:serviceId/status', authenticate, asyncHandler(async (req, res) => {
  const serviceId = positiveInteger(req.params.serviceId, 'Service ID');
  const service = await getService(pool, serviceId);
  const status = await getCustomerQueueStatus(pool, service, req.user.id);
  return res.json(status);
}));

router.get('/history', authenticate, asyncHandler(async (req, res) => {
  const requestedLimit = req.query.limit == null ? 50 : Number(req.query.limit);
  if (!Number.isInteger(requestedLimit) || requestedLimit < 1 || requestedLimit > 100) {
    throw httpError(400, 'Limit must be a whole number between 1 and 100.');
  }

  const [rows] = await pool.execute(
    `SELECT t.id, t.service_id, t.user_id, t.ticket_number, t.ticket_date,
            t.status, t.joined_at, t.called_at, t.served_at, t.cancelled_at,
            t.skipped_at, t.called_by, t.completed_by,
            s.name AS service_name
       FROM tickets t
       JOIN services s ON s.id = t.service_id
      WHERE t.user_id = ?
      ORDER BY t.joined_at DESC
      LIMIT ${requestedLimit}`,
    [req.user.id]
  );

  return res.json({
    tickets: rows.map((row) => ({
      ...formatTicket(row),
      serviceName: row.service_name
    }))
  });
}));

router.post('/:ticketId/cancel', authenticate, asyncHandler(async (req, res) => {
  const ticketId = positiveInteger(req.params.ticketId, 'Ticket ID');
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();
    const [rows] = await connection.execute(
      `SELECT id, service_id, user_id, ticket_number, ticket_date, status,
              joined_at, called_at, served_at, cancelled_at, skipped_at,
              called_by, completed_by
         FROM tickets
        WHERE id = ? AND user_id = ?
        FOR UPDATE`,
      [ticketId, req.user.id]
    );
    if (!rows.length) {
      throw httpError(404, 'Ticket was not found.');
    }

    const ticket = rows[0];
    if (!['waiting', 'serving'].includes(ticket.status)) {
      throw httpError(409, 'Only waiting or serving tickets can be cancelled.');
    }

    await connection.execute(
      `UPDATE tickets
          SET status = 'cancelled', cancelled_at = NOW()
        WHERE id = ?`,
      [ticketId]
    );

    const [updatedRows] = await connection.execute(
      `SELECT id, service_id, user_id, ticket_number, ticket_date, status,
              joined_at, called_at, served_at, cancelled_at, skipped_at,
              called_by, completed_by
         FROM tickets
        WHERE id = ?`,
      [ticketId]
    );

    await connection.commit();
    return res.json({
      message: 'Ticket cancelled successfully.',
      ticket: formatTicket(updatedRows[0])
    });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

module.exports = router;
