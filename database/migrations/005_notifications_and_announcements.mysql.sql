-- ---------------------------------------------------------------------------
-- 005 · In-app notifications and administrator announcements
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS notifications (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  ticket_id  BIGINT UNSIGNED NULL,           -- deep link: tap → ticket screen
  title      VARCHAR(140)    NOT NULL,
  message    VARCHAR(500)    NOT NULL,
  type       ENUM('queue','system','announcement','service') NOT NULL DEFAULT 'queue',
  is_read    TINYINT(1)      NOT NULL DEFAULT 0,
  created_at DATETIME        NOT NULL,
  PRIMARY KEY (id),
  KEY ix_notifications_user_read (user_id, is_read, created_at),
  CONSTRAINT fk_notifications_user   FOREIGN KEY (user_id)   REFERENCES users (id)         ON DELETE CASCADE,
  CONSTRAINT fk_notifications_ticket FOREIGN KEY (ticket_id) REFERENCES queue_tickets (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- service_id NULL = a system-wide announcement.
CREATE TABLE IF NOT EXISTS announcements (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title        VARCHAR(140)    NOT NULL,
  content      TEXT            NOT NULL,
  service_id   BIGINT UNSIGNED NULL,
  created_by   BIGINT UNSIGNED NULL,
  published_at DATETIME        NULL,
  expires_at   DATETIME        NULL,
  status       ENUM('draft','published','archived') NOT NULL DEFAULT 'draft',
  created_at   DATETIME        NOT NULL,
  updated_at   DATETIME        NOT NULL,
  PRIMARY KEY (id),
  KEY ix_announcements_status_published (status, published_at),
  KEY ix_announcements_service (service_id),
  CONSTRAINT fk_announcements_service FOREIGN KEY (service_id) REFERENCES services (id) ON DELETE CASCADE,
  CONSTRAINT fk_announcements_author  FOREIGN KEY (created_by) REFERENCES users (id)    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
