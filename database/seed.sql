-- Smart Queue Management System sample data
-- Run schema.sql before this file.
--
-- Demo password for every sample account: password
-- The value below is a bcrypt hash, not plaintext. In the real app, users
-- register through the API and the API creates the bcrypt hash.

USE smart_queue_db;

INSERT INTO users (full_name, email, password_hash, role)
VALUES
  ('System Admin', 'admin@example.com',
   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'admin'),
  ('Front Desk Staff', 'staff@example.com',
   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'staff'),
  ('Alice Customer', 'alice@example.com',
   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'customer'),
  ('Bob Customer', 'bob@example.com',
   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'customer'),
  ('Carol Customer', 'carol@example.com',
   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'customer'),
  ('David Customer', 'david@example.com',
   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'customer')
ON DUPLICATE KEY UPDATE
  full_name = VALUES(full_name),
  password_hash = VALUES(password_hash),
  role = VALUES(role),
  is_active = TRUE;

INSERT INTO services (name, description, average_service_minutes)
VALUES
  ('Cashier', 'Deposits, withdrawals, payments, and account transactions.', 5.00),
  ('Customer Service', 'Account support, profile updates, and general assistance.', 8.00),
  ('Enquiries', 'Information desk and product enquiries.', 4.00)
ON DUPLICATE KEY UPDATE
  description = VALUES(description),
  average_service_minutes = VALUES(average_service_minutes),
  is_active = TRUE;

SET @staff_id = (SELECT id FROM users WHERE email = 'staff@example.com');
SET @alice_id = (SELECT id FROM users WHERE email = 'alice@example.com');
SET @bob_id = (SELECT id FROM users WHERE email = 'bob@example.com');
SET @carol_id = (SELECT id FROM users WHERE email = 'carol@example.com');
SET @david_id = (SELECT id FROM users WHERE email = 'david@example.com');
SET @cashier_id = (SELECT id FROM services WHERE name = 'Cashier');
SET @customer_service_id = (SELECT id FROM services WHERE name = 'Customer Service');

-- One customer currently being served at Cashier.
INSERT INTO tickets (
  service_id, user_id, ticket_number, ticket_date, status,
  joined_at, called_at, called_by
)
SELECT @cashier_id, @bob_id, 1, CURRENT_DATE, 'serving',
       NOW() - INTERVAL 12 MINUTE,
       NOW() - INTERVAL 4 MINUTE,
       @staff_id
WHERE NOT EXISTS (
  SELECT 1 FROM tickets
  WHERE service_id = @cashier_id AND user_id = @bob_id AND ticket_date = CURRENT_DATE
);

-- One customer waiting behind the serving ticket.
INSERT INTO tickets (
  service_id, user_id, ticket_number, ticket_date, status, joined_at
)
SELECT @cashier_id, @alice_id, 2, CURRENT_DATE, 'waiting',
       NOW() - INTERVAL 7 MINUTE
WHERE NOT EXISTS (
  SELECT 1 FROM tickets
  WHERE service_id = @cashier_id AND user_id = @alice_id AND ticket_date = CURRENT_DATE
);

-- A recently completed ticket, useful for the average-time calculation.
INSERT INTO tickets (
  service_id, user_id, ticket_number, ticket_date, status,
  joined_at, called_at, served_at, called_by, completed_by
)
SELECT @cashier_id, @carol_id, 3, CURRENT_DATE, 'served',
       NOW() - INTERVAL 28 MINUTE,
       NOW() - INTERVAL 22 MINUTE,
       NOW() - INTERVAL 15 MINUTE,
       @staff_id,
       @staff_id
WHERE NOT EXISTS (
  SELECT 1 FROM tickets
  WHERE service_id = @cashier_id AND user_id = @carol_id AND ticket_date = CURRENT_DATE
);

-- A second service with a waiting customer, to demonstrate service filtering.
INSERT INTO tickets (
  service_id, user_id, ticket_number, ticket_date, status, joined_at
)
SELECT @customer_service_id, @david_id, 1, CURRENT_DATE, 'waiting',
       NOW() - INTERVAL 3 MINUTE
WHERE NOT EXISTS (
  SELECT 1 FROM tickets
  WHERE service_id = @customer_service_id AND user_id = @david_id AND ticket_date = CURRENT_DATE
);

SELECT 'Seed complete. Demo password for all sample users: password' AS message;
SELECT id, full_name, email, role FROM users ORDER BY id;
SELECT id, name, average_service_minutes, is_active FROM services ORDER BY id;
