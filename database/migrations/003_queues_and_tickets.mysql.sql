-- ---------------------------------------------------------------------------
-- 003 · Daily queues, tickets and the ticket audit trail
--       This is the core of the system. See docs/queue-engine.md.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS queues (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_id         BIGINT UNSIGNED NOT NULL,
  queue_date         DATE            NOT NULL,
  status             ENUM('waiting','paused','closed') NOT NULL DEFAULT 'waiting',
  -- sequence number most recently CALLED — the "NOW SERVING" board number
  current_number     INT UNSIGNED    NOT NULL DEFAULT 0,
  -- highest sequence number ISSUED today — the allocation counter, only ever
  -- touched inside the SELECT … FOR UPDATE join transaction
  last_issued_number INT UNSIGNED    NOT NULL DEFAULT 0,
  total_served       INT UNSIGNED    NOT NULL DEFAULT 0,
  created_at         DATETIME        NOT NULL,
  updated_at         DATETIME        NOT NULL,
  PRIMARY KEY (id),
  -- exactly one queue instance per service per day (Rule 12)
  UNIQUE KEY uq_queues_service_date (service_id, queue_date),
  KEY ix_queues_date_status (queue_date, status),
  CONSTRAINT fk_queues_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS queue_tickets (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  queue_id               BIGINT UNSIGNED NOT NULL,
  -- denormalised from queues.service_id so the two unique keys below can exist;
  -- written once at insert and never updated (docs/database.md §2.4)
  service_id             BIGINT UNSIGNED NOT NULL,
  user_id                BIGINT UNSIGNED NOT NULL,
  ticket_number          VARCHAR(16)     NOT NULL,   -- FIN-023
  sequence_number        INT UNSIGNED    NOT NULL,   -- 23
  status                 ENUM('waiting','called','serving','completed','cancelled','skipped','no_show')
                                         NOT NULL DEFAULT 'waiting',
  counter_id             BIGINT UNSIGNED NULL,
  estimated_wait_minutes INT UNSIGNED    NULL,       -- snapshot at join time
  joined_at              DATETIME        NOT NULL,
  called_at              DATETIME        NULL,
  service_started_at     DATETIME        NULL,
  completed_at           DATETIME        NULL,
  cancelled_at           DATETIME        NULL,
  created_at             DATETIME        NOT NULL,
  updated_at             DATETIME        NOT NULL,

  -- Rule 1 as a storage guarantee: NULL for terminal statuses, so a user may
  -- hold unlimited finished tickets but only one active ticket per service.
  active_service_id BIGINT UNSIGNED
    GENERATED ALWAYS AS (CASE WHEN status IN ('waiting','called','serving') THEN service_id END) STORED,

  -- Rule 5 as a storage guarantee: one actively served ticket per counter.
  active_counter_id BIGINT UNSIGNED
    GENERATED ALWAYS AS (CASE WHEN status IN ('called','serving') THEN counter_id END) STORED,

  PRIMARY KEY (id),
  UNIQUE KEY uq_tickets_queue_sequence  (queue_id, sequence_number),   -- Rule 12
  UNIQUE KEY uq_tickets_queue_number    (queue_id, ticket_number),     -- Rule 12
  UNIQUE KEY uq_tickets_active_per_user (user_id, active_service_id),  -- Rule 1
  UNIQUE KEY uq_tickets_active_counter  (active_counter_id),           -- Rule 5
  KEY ix_tickets_queue_status_seq (queue_id, status, sequence_number), -- position + call-next
  KEY ix_tickets_user_status      (user_id, status),
  KEY ix_tickets_service_joined   (service_id, joined_at),
  KEY ix_tickets_counter_status   (counter_id, status),
  KEY ix_tickets_status           (status),
  CONSTRAINT fk_tickets_queue   FOREIGN KEY (queue_id)   REFERENCES queues (id)           ON DELETE CASCADE,
  CONSTRAINT fk_tickets_service FOREIGN KEY (service_id) REFERENCES services (id)         ON DELETE CASCADE,
  CONSTRAINT fk_tickets_user    FOREIGN KEY (user_id)    REFERENCES users (id)            ON DELETE CASCADE,
  CONSTRAINT fk_tickets_counter FOREIGN KEY (counter_id) REFERENCES service_counters (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only audit trail. user_id is the ACTOR (customer or staff), nullable
-- for system-generated entries.
CREATE TABLE IF NOT EXISTS queue_events (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_id   BIGINT UNSIGNED NOT NULL,
  user_id     BIGINT UNSIGNED NULL,
  event_type  ENUM('joined','called','recalled','service_started','completed',
                   'cancelled','skipped','no_show','threshold_notified') NOT NULL,
  description VARCHAR(255)    NULL,
  created_at  DATETIME        NOT NULL,
  PRIMARY KEY (id),
  KEY ix_events_ticket       (ticket_id, created_at),
  KEY ix_events_type_created (event_type, created_at),
  KEY ix_events_user         (user_id),
  CONSTRAINT fk_events_ticket FOREIGN KEY (ticket_id) REFERENCES queue_tickets (id) ON DELETE CASCADE,
  CONSTRAINT fk_events_user   FOREIGN KEY (user_id)   REFERENCES users (id)         ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
