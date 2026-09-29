-- ---------------------------------------------------------------------------
-- 004 · Staff assignments
--       Which staff member works which service/counter, and when.
--       Rule 4 ("only staff assigned to the service may call its tickets")
--       is answered from this table.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS staff_assignments (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  staff_id      BIGINT UNSIGNED NOT NULL,
  service_id    BIGINT UNSIGNED NOT NULL,
  counter_id    BIGINT UNSIGNED NULL,
  assigned_at   DATETIME        NOT NULL,
  unassigned_at DATETIME        NULL,
  status        ENUM('active','ended') NOT NULL DEFAULT 'active',
  created_at    DATETIME        NOT NULL,
  updated_at    DATETIME        NOT NULL,
  PRIMARY KEY (id),
  KEY ix_assign_staff_status   (staff_id, status),
  KEY ix_assign_service_status (service_id, status),
  KEY ix_assign_counter_status (counter_id, status),
  CONSTRAINT fk_assign_staff   FOREIGN KEY (staff_id)   REFERENCES users (id)            ON DELETE CASCADE,
  CONSTRAINT fk_assign_service FOREIGN KEY (service_id) REFERENCES services (id)         ON DELETE CASCADE,
  CONSTRAINT fk_assign_counter FOREIGN KEY (counter_id) REFERENCES service_counters (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
