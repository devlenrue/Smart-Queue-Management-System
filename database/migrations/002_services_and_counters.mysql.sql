-- ---------------------------------------------------------------------------
-- 002 · Services, counters, operating hours and per-service queue settings
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS services (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name                 VARCHAR(120)    NOT NULL,
  code                 VARCHAR(8)      NOT NULL,  -- ticket prefix, e.g. FIN
  description          TEXT            NULL,
  category             VARCHAR(60)     NULL,
  average_service_time INT UNSIGNED    NOT NULL DEFAULT 5,   -- minutes
  daily_capacity       INT UNSIGNED    NOT NULL DEFAULT 200,
  status               ENUM('open','closed','inactive') NOT NULL DEFAULT 'open',
  created_at           DATETIME        NOT NULL,
  updated_at           DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_services_code (code),
  KEY ix_services_status (status),
  KEY ix_services_category (category),
  CONSTRAINT ck_services_avg_time CHECK (average_service_time > 0),
  CONSTRAINT ck_services_capacity CHECK (daily_capacity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS service_counters (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_id        BIGINT UNSIGNED NOT NULL,
  counter_number    INT UNSIGNED    NOT NULL,
  name              VARCHAR(80)     NOT NULL,
  status            ENUM('available','busy','offline') NOT NULL DEFAULT 'offline',
  assigned_staff_id BIGINT UNSIGNED NULL,
  created_at        DATETIME        NOT NULL,
  updated_at        DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_counters_service_number (service_id, counter_number),
  -- A staff member mans at most one counter. MySQL allows repeated NULLs in a
  -- unique index, so any number of counters may be unstaffed.
  UNIQUE KEY uq_counters_staff (assigned_staff_id),
  KEY ix_counters_status (status),
  CONSTRAINT fk_counters_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE,
  CONSTRAINT fk_counters_staff   FOREIGN KEY (assigned_staff_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- day_of_week: 0 = Sunday … 6 = Saturday (matches JavaScript Date#getDay).
CREATE TABLE IF NOT EXISTS service_hours (
  id           BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  service_id   BIGINT UNSIGNED  NOT NULL,
  day_of_week  TINYINT UNSIGNED NOT NULL,
  opening_time TIME             NOT NULL,
  closing_time TIME             NOT NULL,
  status       ENUM('open','closed') NOT NULL DEFAULT 'open',
  PRIMARY KEY (id),
  UNIQUE KEY uq_hours_service_day (service_id, day_of_week),
  CONSTRAINT fk_hours_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE,
  CONSTRAINT ck_hours_day     CHECK (day_of_week BETWEEN 0 AND 6),
  CONSTRAINT ck_hours_window  CHECK (closing_time > opening_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS queue_settings (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_id             BIGINT UNSIGNED NOT NULL,
  max_queue_size         INT UNSIGNED    NOT NULL DEFAULT 100,
  allow_cancellation     TINYINT(1)      NOT NULL DEFAULT 1,
  allow_rejoin           TINYINT(1)      NOT NULL DEFAULT 1,
  notification_threshold INT UNSIGNED    NOT NULL DEFAULT 3,
  estimated_service_time INT UNSIGNED    NOT NULL DEFAULT 5,
  created_at             DATETIME        NOT NULL,
  updated_at             DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_settings_service (service_id),
  CONSTRAINT fk_settings_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE,
  CONSTRAINT ck_settings_size    CHECK (max_queue_size > 0),
  CONSTRAINT ck_settings_est     CHECK (estimated_service_time > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
