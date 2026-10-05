const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const pool = require('../config/db');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate } = require('../middleware/auth');
const {
  requiredString,
  email,
  password,
  httpError
} = require('../utils/validation');

const router = express.Router();

function publicUser(row) {
  return {
    id: Number(row.id),
    fullName: row.full_name,
    email: row.email,
    role: row.role
  };
}

function createToken(user) {
  return jwt.sign(
    {
      id: Number(user.id),
      email: user.email,
      role: user.role,
      fullName: user.full_name
    },
    process.env.JWT_SECRET || 'development-only-secret',
    { expiresIn: process.env.JWT_EXPIRES_IN || '1d' }
  );
}

router.post('/register', asyncHandler(async (req, res) => {
  const fullName = requiredString(req.body.fullName, 'Full name', { min: 2, max: 100 });
  const normalizedEmail = email(req.body.email);
  const plainPassword = password(req.body.password);
  const rounds = Number(process.env.BCRYPT_ROUNDS || 10);

  const [existing] = await pool.execute(
    'SELECT id FROM users WHERE email = ?',
    [normalizedEmail]
  );
  if (existing.length) {
    throw httpError(409, 'An account with that email already exists.');
  }

  const passwordHash = await bcrypt.hash(plainPassword, rounds);
  const [result] = await pool.execute(
    `INSERT INTO users (full_name, email, password_hash, role)
     VALUES (?, ?, ?, 'customer')`,
    [fullName, normalizedEmail, passwordHash]
  );

  const [rows] = await pool.execute(
    `SELECT id, full_name, email, role
       FROM users
      WHERE id = ?`,
    [result.insertId]
  );
  const user = rows[0];

  return res.status(201).json({
    message: 'Registration successful.',
    user: publicUser(user),
    token: createToken(user)
  });
}));

router.post('/login', asyncHandler(async (req, res) => {
  const normalizedEmail = email(req.body.email);
  const plainPassword = password(req.body.password);

  const [rows] = await pool.execute(
    `SELECT id, full_name, email, password_hash, role
       FROM users
      WHERE email = ? AND is_active = TRUE`,
    [normalizedEmail]
  );

  if (!rows.length || !(await bcrypt.compare(plainPassword, rows[0].password_hash))) {
    throw httpError(401, 'Email or password is incorrect.');
  }

  const user = rows[0];
  return res.json({
    message: 'Login successful.',
    user: publicUser(user),
    token: createToken(user)
  });
}));

router.get('/me', authenticate, asyncHandler(async (req, res) => {
  const [rows] = await pool.execute(
    `SELECT id, full_name, email, role
       FROM users
      WHERE id = ? AND is_active = TRUE`,
    [req.user.id]
  );

  if (!rows.length) {
    throw httpError(404, 'User account was not found or is inactive.');
  }

  return res.json({ user: publicUser(rows[0]) });
}));

module.exports = router;
