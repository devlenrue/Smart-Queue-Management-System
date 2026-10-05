const { httpError } = require('./validation');

function toNumber(value) {
  return value === null || value === undefined ? null : Number(value);
}

function formatService(row) {
  return {
    id: Number(row.id),
    name: row.name,
    description: row.description,
    averageServiceMinutes: Number(row.average_service_minutes),
    isActive: Boolean(row.is_active),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function formatTicket(row) {
  return {
    id: Number(row.id),
    serviceId: Number(row.service_id),
    userId: Number(row.user_id),
    ticketNumber: Number(row.ticket_number),
    ticketDate: row.ticket_date,
    status: row.status,
    joinedAt: row.joined_at,
    calledAt: row.called_at,
    servedAt: row.served_at,
    cancelledAt: row.cancelled_at,
    skippedAt: row.skipped_at,
    calledBy: toNumber(row.called_by),
    completedBy: toNumber(row.completed_by),
    customerName: row.customer_name || undefined,
    customerEmail: row.customer_email || undefined
  };
}

async function getService(connection, serviceId, { includeInactive = false } = {}) {
  const whereActive = includeInactive ? '' : 'AND is_active = TRUE';
  const [rows] = await connection.execute(
    `SELECT id, name, description, average_service_minutes, is_active,
            created_at, updated_at
       FROM services
      WHERE id = ? ${whereActive}`,
    [serviceId]
  );

  if (!rows.length) {
    throw httpError(404, includeInactive ? 'Service was not found.' : 'Service was not found or is inactive.');
  }
  return rows[0];
}

async function getAverageServiceMinutes(connection, serviceId, fallbackMinutes) {
  const [rows] = await connection.execute(
    `SELECT AVG(TIMESTAMPDIFF(SECOND, called_at, served_at)) / 60 AS calculated_minutes
       FROM tickets
      WHERE service_id = ?
        AND status = 'served'
        AND called_at IS NOT NULL
        AND served_at IS NOT NULL
        AND ticket_date >= (CURRENT_DATE - INTERVAL 30 DAY)`,
    [serviceId]
  );

  const calculated = rows[0].calculated_minutes;
  return Number(calculated === null ? fallbackMinutes : calculated);
}

async function getActiveTickets(connection, serviceId) {
  const [rows] = await connection.execute(
    `SELECT t.id, t.service_id, t.user_id, t.ticket_number, t.ticket_date,
            t.status, t.joined_at, t.called_at, t.served_at, t.cancelled_at,
            t.skipped_at, t.called_by, t.completed_by,
            u.full_name AS customer_name, u.email AS customer_email
       FROM tickets t
       JOIN users u ON u.id = t.user_id
      WHERE t.service_id = ?
        AND t.ticket_date = CURRENT_DATE
        AND t.status IN ('waiting', 'serving')
      ORDER BY CASE WHEN t.status = 'serving' THEN 0 ELSE 1 END,
               t.ticket_number ASC`,
    [serviceId]
  );
  return rows;
}

async function getQueueSnapshot(connection, serviceRow) {
  const rows = await getActiveTickets(connection, serviceRow.id);
  const tickets = rows.map(formatTicket);
  const currentServing = tickets.find((ticket) => ticket.status === 'serving') || null;
  const waitingTickets = tickets.filter((ticket) => ticket.status === 'waiting');
  const averageServiceMinutes = await getAverageServiceMinutes(
    connection,
    serviceRow.id,
    serviceRow.average_service_minutes
  );

  return {
    service: formatService(serviceRow),
    currentServing,
    waitingCount: waitingTickets.length,
    totalActiveTickets: tickets.length,
    averageServiceMinutes: Number(averageServiceMinutes.toFixed(2)),
    tickets
  };
}

async function getCustomerQueueStatus(connection, serviceRow, userId) {
  const snapshot = await getQueueSnapshot(connection, serviceRow);
  const myTicket = snapshot.tickets.find((ticket) => ticket.userId === Number(userId)) || null;

  if (!myTicket) {
    return {
      ...snapshot,
      myTicket: null,
      peopleAhead: 0,
      currentPosition: null,
      estimatedWaitMinutes: 0
    };
  }

  const peopleWaitingAhead = snapshot.tickets.filter(
    (ticket) => ticket.status === 'waiting' && ticket.ticketNumber < myTicket.ticketNumber
  ).length;
  const peopleAhead = myTicket.status === 'serving'
    ? 0
    : peopleWaitingAhead + (snapshot.currentServing ? 1 : 0);

  return {
    ...snapshot,
    myTicket,
    peopleAhead,
    currentPosition: myTicket.status === 'serving' ? 1 : peopleAhead + 1,
    estimatedWaitMinutes: Math.max(
      0,
      Math.round(peopleAhead * snapshot.averageServiceMinutes)
    )
  };
}

module.exports = {
  formatService,
  formatTicket,
  getService,
  getAverageServiceMinutes,
  getActiveTickets,
  getQueueSnapshot,
  getCustomerQueueStatus
};
