-- ---------------------------------------------------------------------------
-- 002 · Services, counters, operating hours and per-service queue settings
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS services (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  name                 TEXT    NOT NULL,
  code                 TEXT    NOT NULL,
  description          TEXT    NULL,
  category             TEXT    NULL,
  average_service_time INTEGER NOT NULL DEFAULT 5,
  daily_capacity       INTEGER NOT NULL DEFAULT 200,
  status               TEXT    NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','inactive')),
  created_at           TEXT    NOT NULL,
  updated_at           TEXT    NOT NULL,
  CHECK (average_service_time > 0),
  CHECK (daily_capacity > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_services_code   ON services (code);
CREATE INDEX        IF NOT EXISTS ix_services_status ON services (status);
CREATE INDEX        IF NOT EXISTS ix_services_category ON services (category);

CREATE TABLE IF NOT EXISTS service_counters (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  service_id        INTEGER NOT NULL REFERENCES services (id) ON DELETE CASCADE,
  counter_number    INTEGER NOT NULL,
  name              TEXT    NOT NULL,
  status            TEXT    NOT NULL DEFAULT 'offline' CHECK (status IN ('available','busy','offline')),
  assigned_staff_id INTEGER NULL REFERENCES users (id) ON DELETE SET NULL,
  created_at        TEXT    NOT NULL,
  updated_at        TEXT    NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_counters_service_number ON service_counters (service_id, counter_number);
CREATE UNIQUE INDEX IF NOT EXISTS uq_counters_staff          ON service_counters (assigned_staff_id);
CREATE INDEX        IF NOT EXISTS ix_counters_status         ON service_counters (status);

CREATE TABLE IF NOT EXISTS service_hours (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  service_id   INTEGER NOT NULL REFERENCES services (id) ON DELETE CASCADE,
  day_of_week  INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  opening_time TEXT    NOT NULL,
  closing_time TEXT    NOT NULL,
  status       TEXT    NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  CHECK (closing_time > opening_time)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_hours_service_day ON service_hours (service_id, day_of_week);

CREATE TABLE IF NOT EXISTS queue_settings (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  service_id             INTEGER NOT NULL REFERENCES services (id) ON DELETE CASCADE,
  max_queue_size         INTEGER NOT NULL DEFAULT 100,
  allow_cancellation     INTEGER NOT NULL DEFAULT 1,
  allow_rejoin           INTEGER NOT NULL DEFAULT 1,
  notification_threshold INTEGER NOT NULL DEFAULT 3,
  estimated_service_time INTEGER NOT NULL DEFAULT 5,
  created_at             TEXT    NOT NULL,
  updated_at             TEXT    NOT NULL,
  CHECK (max_queue_size > 0),
  CHECK (estimated_service_time > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_settings_service ON queue_settings (service_id);
