const express = require('express');

const pool = require('../config/db');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate, authorize } = require('../middleware/auth');
const {
  requiredString,
  positiveNumber,
  positiveInteger,
  httpError
} = require('../utils/validation');
const { formatService, getService } = require('../utils/queue');

const router = express.Router();

// Customers and staff only see services that can currently accept tickets.
router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await pool.execute(
    `SELECT id, name, description, average_service_minutes, is_active,
            created_at, updated_at
       FROM services
      WHERE is_active = TRUE
      ORDER BY name ASC`
  );
  return res.json({ services: rows.map(formatService) });
}));

router.post('/', authenticate, authorize('admin'), asyncHandler(async (req, res) => {
  const name = requiredString(req.body.name, 'Service name', { min: 2, max: 100 });
  const description = req.body.description == null
    ? null
    : requiredString(req.body.description, 'Description', { min: 1, max: 255 });
  const averageServiceMinutes = req.body.averageServiceMinutes == null
    ? 5
    : positiveNumber(req.body.averageServiceMinutes, 'Average service time');

  const [result] = await pool.execute(
    `INSERT INTO services (name, description, average_service_minutes)
     VALUES (?, ?, ?)`,
    [name, description, averageServiceMinutes]
  );
  const service = await getService(pool, result.insertId, { includeInactive: true });

  return res.status(201).json({
    message: 'Service created successfully.',
    service: formatService(service)
  });
}));

// Services are soft-deleted so ticket history and foreign-key references remain intact.
router.delete('/:serviceId', authenticate, authorize('admin'), asyncHandler(async (req, res) => {
  const serviceId = positiveInteger(req.params.serviceId, 'Service ID');
  const service = await getService(pool, serviceId, { includeInactive: true });

  if (!service.is_active) {
    throw httpError(400, 'Service is already inactive.');
  }

  const [activeTickets] = await pool.execute(
    `SELECT COUNT(*) AS count
       FROM tickets
      WHERE service_id = ?
        AND ticket_date = CURRENT_DATE
        AND status IN ('waiting', 'serving')`,
    [serviceId]
  );
  if (Number(activeTickets[0].count) > 0) {
    throw httpError(409, 'A service with active queue tickets cannot be removed.');
  }

  await pool.execute(
    'UPDATE services SET is_active = FALSE WHERE id = ?',
    [serviceId]
  );

  return res.json({
    message: 'Service removed successfully.',
    service: { ...formatService(service), isActive: false }
  });
}));

module.exports = router;
