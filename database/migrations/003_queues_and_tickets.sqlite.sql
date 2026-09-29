-- ---------------------------------------------------------------------------
-- 003 · Daily queues, tickets and the ticket audit trail
--
-- MySQL expresses Rules 1 and 5 with STORED generated columns plus a unique
-- key. SQLite has no equivalent that ALTER can add, but it supports partial
-- unique indexes, which give exactly the same guarantee.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS queues (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  service_id         INTEGER NOT NULL REFERENCES services (id) ON DELETE CASCADE,
  queue_date         TEXT    NOT NULL,
  status             TEXT    NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting','paused','closed')),
  current_number     INTEGER NOT NULL DEFAULT 0,
  last_issued_number INTEGER NOT NULL DEFAULT 0,
  total_served       INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT    NOT NULL,
  updated_at         TEXT    NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_queues_service_date ON queues (service_id, queue_date);
CREATE INDEX        IF NOT EXISTS ix_queues_date_status  ON queues (queue_date, status);

CREATE TABLE IF NOT EXISTS queue_tickets (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  queue_id               INTEGER NOT NULL REFERENCES queues (id)           ON DELETE CASCADE,
  service_id             INTEGER NOT NULL REFERENCES services (id)         ON DELETE CASCADE,
  user_id                INTEGER NOT NULL REFERENCES users (id)            ON DELETE CASCADE,
  ticket_number          TEXT    NOT NULL,
  sequence_number        INTEGER NOT NULL,
  status                 TEXT    NOT NULL DEFAULT 'waiting'
                           CHECK (status IN ('waiting','called','serving','completed','cancelled','skipped','no_show')),
  counter_id             INTEGER NULL REFERENCES service_counters (id)     ON DELETE SET NULL,
  estimated_wait_minutes INTEGER NULL,
  joined_at              TEXT    NOT NULL,
  called_at              TEXT    NULL,
  service_started_at     TEXT    NULL,
  completed_at           TEXT    NULL,
  cancelled_at           TEXT    NULL,
  created_at             TEXT    NOT NULL,
  updated_at             TEXT    NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_queue_sequence ON queue_tickets (queue_id, sequence_number);
CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_queue_number   ON queue_tickets (queue_id, ticket_number);

-- Rule 1: one active ticket per user per service.
CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_active_per_user
  ON queue_tickets (user_id, service_id)
  WHERE status IN ('waiting','called','serving');

-- Rule 5: one actively served ticket per counter.
CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_active_counter
  ON queue_tickets (counter_id)
  WHERE status IN ('called','serving');

CREATE INDEX IF NOT EXISTS ix_tickets_queue_status_seq ON queue_tickets (queue_id, status, sequence_number);
CREATE INDEX IF NOT EXISTS ix_tickets_user_status      ON queue_tickets (user_id, status);
CREATE INDEX IF NOT EXISTS ix_tickets_service_joined   ON queue_tickets (service_id, joined_at);
CREATE INDEX IF NOT EXISTS ix_tickets_counter_status   ON queue_tickets (counter_id, status);
CREATE INDEX IF NOT EXISTS ix_tickets_status           ON queue_tickets (status);

CREATE TABLE IF NOT EXISTS queue_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id   INTEGER NOT NULL REFERENCES queue_tickets (id) ON DELETE CASCADE,
  user_id     INTEGER NULL     REFERENCES users (id)         ON DELETE SET NULL,
  event_type  TEXT    NOT NULL CHECK (event_type IN ('joined','called','recalled','service_started',
                                                     'completed','cancelled','skipped','no_show','threshold_notified')),
  description TEXT    NULL,
  created_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_events_ticket       ON queue_events (ticket_id, created_at);
CREATE INDEX IF NOT EXISTS ix_events_type_created ON queue_events (event_type, created_at);
CREATE INDEX IF NOT EXISTS ix_events_user         ON queue_events (user_id);
