-- ---------------------------------------------------------------------------
-- 004 · Staff assignments
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_assignments (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  staff_id      INTEGER NOT NULL REFERENCES users (id)            ON DELETE CASCADE,
  service_id    INTEGER NOT NULL REFERENCES services (id)         ON DELETE CASCADE,
  counter_id    INTEGER NULL     REFERENCES service_counters (id) ON DELETE SET NULL,
  assigned_at   TEXT    NOT NULL,
  unassigned_at TEXT    NULL,
  status        TEXT    NOT NULL DEFAULT 'active' CHECK (status IN ('active','ended')),
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_assign_staff_status   ON staff_assignments (staff_id, status);
CREATE INDEX IF NOT EXISTS ix_assign_service_status ON staff_assignments (service_id, status);
CREATE INDEX IF NOT EXISTS ix_assign_counter_status ON staff_assignments (counter_id, status);
