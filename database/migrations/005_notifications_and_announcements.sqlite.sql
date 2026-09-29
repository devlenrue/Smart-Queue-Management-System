-- ---------------------------------------------------------------------------
-- 005 · In-app notifications and administrator announcements
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS notifications (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users (id)         ON DELETE CASCADE,
  ticket_id  INTEGER NULL     REFERENCES queue_tickets (id) ON DELETE SET NULL,
  title      TEXT    NOT NULL,
  message    TEXT    NOT NULL,
  type       TEXT    NOT NULL DEFAULT 'queue' CHECK (type IN ('queue','system','announcement','service')),
  is_read    INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_notifications_user_read ON notifications (user_id, is_read, created_at);

CREATE TABLE IF NOT EXISTS announcements (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  title        TEXT    NOT NULL,
  content      TEXT    NOT NULL,
  service_id   INTEGER NULL REFERENCES services (id) ON DELETE CASCADE,
  created_by   INTEGER NULL REFERENCES users (id)    ON DELETE SET NULL,
  published_at TEXT    NULL,
  expires_at   TEXT    NULL,
  status       TEXT    NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
  created_at   TEXT    NOT NULL,
  updated_at   TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_announcements_status_published ON announcements (status, published_at);
CREATE INDEX IF NOT EXISTS ix_announcements_service          ON announcements (service_id);
