const express = require('express');

const pool = require('../config/db');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate, authorize } = require('../middleware/auth');
const { positiveInteger, httpError } = require('../utils/validation');
const {
  formatTicket,
  getService,
  getQueueSnapshot
} = require('../utils/queue');

const router = express.Router();
const staffOnly = [authenticate, authorize('staff', 'admin')];

router.get('/queues/:serviceId', ...staffOnly, asyncHandler(async (req, res) => {
  const serviceId = positiveInteger(req.params.serviceId, 'Service ID');
  const service = await getService(pool, serviceId);
  return res.json(await getQueueSnapshot(pool, service));
}));

router.post('/queues/:serviceId/call-next', ...staffOnly, asyncHandler(async (req, res) => {
  const serviceId = positiveInteger(req.params.serviceId, 'Service ID');
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

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

    const [servingRows] = await connection.execute(
      `SELECT id, ticket_number
         FROM tickets
        WHERE service_id = ?
          AND ticket_date = CURRENT_DATE
          AND status = 'serving'
        LIMIT 1
        FOR UPDATE`,
      [serviceId]
    );
    if (servingRows.length) {
      throw httpError(409, `Ticket ${servingRows[0].ticket_number} is still being served.`);
    }

    const [waitingRows] = await connection.execute(
      `SELECT id
         FROM tickets
        WHERE service_id = ?
          AND ticket_date = CURRENT_DATE
          AND status = 'waiting'
        ORDER BY ticket_number ASC
        LIMIT 1
        FOR UPDATE`,
      [serviceId]
    );
    if (!waitingRows.length) {
      throw httpError(404, 'There are no waiting customers for this service.');
    }

    const ticketId = waitingRows[0].id;
    await connection.execute(
      `UPDATE tickets
          SET status = 'serving', called_at = NOW(), called_by = ?
        WHERE id = ?`,
      [req.user.id, ticketId]
    );

    const [ticketRows] = await connection.execute(
      `SELECT id, service_id, user_id, ticket_number, ticket_date, status,
              joined_at, called_at, served_at, cancelled_at, skipped_at,
              called_by, completed_by
         FROM tickets
        WHERE id = ?`,
      [ticketId]
    );

    await connection.commit();
    return res.json({
      message: `Ticket ${ticketRows[0].ticket_number} is now being served.`,
      ticket: formatTicket(ticketRows[0])
    });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

router.post('/tickets/:ticketId/complete', ...staffOnly, asyncHandler(async (req, res) => {
  return updateTicketStatus(req, res, 'complete');
}));

router.post('/tickets/:ticketId/skip', ...staffOnly, asyncHandler(async (req, res) => {
  return updateTicketStatus(req, res, 'skip');
}));

async function updateTicketStatus(req, res, action) {
  const ticketId = positiveInteger(req.params.ticketId, 'Ticket ID');
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();
    const [rows] = await connection.execute(
      `SELECT id, service_id, user_id, ticket_number, ticket_date, status,
              joined_at, called_at, served_at, cancelled_at, skipped_at,
              called_by, completed_by
         FROM tickets
        WHERE id = ?
        FOR UPDATE`,
      [ticketId]
    );
    if (!rows.length) {
      throw httpError(404, 'Ticket was not found.');
    }

    const ticket = rows[0];
    if (action === 'complete' && ticket.status !== 'serving') {
      throw httpError(409, 'Only a currently serving ticket can be completed.');
    }
    if (action === 'skip' && !['waiting', 'serving'].includes(ticket.status)) {
      throw httpError(409, 'Only waiting or serving tickets can be skipped.');
    }

    const nextStatus = action === 'complete' ? 'served' : 'skipped';
    const timestampColumn = action === 'complete' ? 'served_at' : 'skipped_at';
    const extraColumn = action === 'complete' ? 'completed_by' : 'called_by';

    await connection.execute(
      `UPDATE tickets
          SET status = ?, ${timestampColumn} = NOW(), ${extraColumn} = ?
        WHERE id = ?`,
      [nextStatus, req.user.id, ticketId]
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
      message: action === 'complete'
        ? `Ticket ${ticket.ticket_number} was marked as served.`
        : `Ticket ${ticket.ticket_number} was skipped.`,
      ticket: formatTicket(updatedRows[0])
    });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

module.exports = router;
