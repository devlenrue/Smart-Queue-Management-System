-- Smart Queue Management System
-- MySQL 8.0+
--
-- This script creates the database and its three core tables.
-- It is safe to run repeatedly because CREATE TABLE IF NOT EXISTS is used.
-- For a completely clean local reset, uncomment the DROP statements below.

CREATE DATABASE IF NOT EXISTS smart_queue_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE smart_queue_db;

-- Uncomment these lines only when you intentionally want to erase local data.
-- DROP TABLE IF EXISTS tickets;
-- DROP TABLE IF EXISTS services;
-- DROP TABLE IF EXISTS users;

CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('customer', 'staff', 'admin') NOT NULL DEFAULT 'customer',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email),
  KEY idx_users_role (role),
  KEY idx_users_active (is_active)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS services (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  description VARCHAR(255) NULL,
  -- Fallback/configuration value used before enough real service times exist.
  average_service_minutes DECIMAL(6,2) NOT NULL DEFAULT 5.00,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_services_name (name),
  KEY idx_services_active (is_active),
  CONSTRAINT chk_services_average_time CHECK (average_service_minutes > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tickets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  ticket_number INT UNSIGNED NOT NULL,
  ticket_date DATE NOT NULL,
  status ENUM('waiting', 'serving', 'served', 'cancelled', 'skipped')
    NOT NULL DEFAULT 'waiting',
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  called_at DATETIME NULL,
  served_at DATETIME NULL,
  cancelled_at DATETIME NULL,
  skipped_at DATETIME NULL,
  called_by BIGINT UNSIGNED NULL,
  completed_by BIGINT UNSIGNED NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  -- MySQL has no partial unique indexes. This generated key prevents a
  -- customer from holding two active tickets for the same service on the
  -- same day while still allowing unlimited historical tickets.
  active_user_service_key VARCHAR(120)
    GENERATED ALWAYS AS (
      CASE
        WHEN status IN ('waiting', 'serving') THEN
          CONCAT(user_id, ':', service_id, ':', ticket_date)
        ELSE NULL
      END
    ) STORED,
  PRIMARY KEY (id),
  -- Ticket numbers restart for each service on each operating day.
  UNIQUE KEY uq_tickets_service_number (service_id, ticket_date, ticket_number),
  UNIQUE KEY uq_tickets_one_active_per_user_service (active_user_service_key),
  KEY idx_tickets_queue_order (service_id, ticket_date, status, ticket_number),
  KEY idx_tickets_user_history (user_id, joined_at),
  KEY idx_tickets_status (status),
  KEY idx_tickets_called_by (called_by),
  KEY idx_tickets_completed_by (completed_by),
  CONSTRAINT fk_tickets_service
    FOREIGN KEY (service_id) REFERENCES services (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_tickets_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_tickets_called_by
    FOREIGN KEY (called_by) REFERENCES users (id)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_tickets_completed_by
    FOREIGN KEY (completed_by) REFERENCES users (id)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT chk_tickets_ticket_number CHECK (ticket_number > 0),
  CONSTRAINT chk_tickets_called_time CHECK (called_at IS NULL OR called_at >= joined_at),
  CONSTRAINT chk_tickets_served_time CHECK (served_at IS NULL OR called_at IS NOT NULL),
  CONSTRAINT chk_tickets_cancelled_time CHECK (cancelled_at IS NULL OR status = 'cancelled'),
  CONSTRAINT chk_tickets_skipped_time CHECK (skipped_at IS NULL OR status = 'skipped')
) ENGINE=InnoDB;

