require('dotenv').config();

const express = require('express');
const cors = require('cors');

const pool = require('./config/db');
const authRoutes = require('./routes/auth');
const serviceRoutes = require('./routes/services');
const queueRoutes = require('./routes/queues');
const adminRoutes = require('./routes/admin');

const app = express();

app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/api/health', async (req, res, next) => {
  try {
    await pool.query('SELECT 1');
    return res.json({ status: 'ok', database: 'connected' });
  } catch (error) {
    return next(error);
  }
});

app.use('/api/auth', authRoutes);
app.use('/api/services', serviceRoutes);
app.use('/api/queues', queueRoutes);
app.use('/api/admin', adminRoutes);

app.use((req, res) => {
  res.status(404).json({ message: 'API route was not found.' });
});

app.use((error, req, res, next) => {
  // MySQL duplicate and foreign-key errors are converted to useful client errors.
  if (error.code === 'ER_DUP_ENTRY') {
    return res.status(409).json({ message: 'That record already exists.' });
  }
  if (error.code === 'ER_NO_REFERENCED_ROW_2' || error.code === 'ER_ROW_IS_REFERENCED_2') {
    return res.status(400).json({ message: 'The related record does not exist or cannot be removed.' });
  }

  const status = error.status || 500;
  if (status >= 500) {
    console.error(error);
  }
  return res.status(status).json({
    message: status >= 500 ? 'An unexpected server error occurred.' : error.message
  });
});

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  app.listen(port, '0.0.0.0', () => {
    console.log(`Smart Queue API listening on http://0.0.0.0:${port}`);
  });
}

module.exports = app;
