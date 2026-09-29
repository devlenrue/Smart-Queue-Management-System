-- ---------------------------------------------------------------------------
-- 001 · Users and authentication support
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  first_name    VARCHAR(80)     NOT NULL,
  last_name     VARCHAR(80)     NOT NULL,
  email         VARCHAR(191)    NOT NULL,
  phone         VARCHAR(30)     NOT NULL,
  password_hash VARCHAR(255)    NOT NULL,
  role          ENUM('customer','staff','admin','super_admin') NOT NULL DEFAULT 'customer',
  status        ENUM('active','inactive','suspended')          NOT NULL DEFAULT 'active',
  created_at    DATETIME        NOT NULL,
  updated_at    DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_phone (phone),
  KEY ix_users_role (role),
  KEY ix_users_status (status),
  KEY ix_users_name (last_name, first_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Makes POST /auth/logout meaningful for a stateless JWT: the token's jti is
-- parked here until it would have expired anyway.
CREATE TABLE IF NOT EXISTS revoked_tokens (
  jti        CHAR(36)        NOT NULL,
  user_id    BIGINT UNSIGNED NOT NULL,
  expires_at DATETIME        NOT NULL,
  created_at DATETIME        NOT NULL,
  PRIMARY KEY (jti),
  KEY ix_revoked_expires (expires_at),
  CONSTRAINT fk_revoked_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS system_settings (
  setting_key   VARCHAR(80)  NOT NULL,
  setting_value VARCHAR(500) NOT NULL,
  description   VARCHAR(255) NULL,
  updated_at    DATETIME     NOT NULL,
  PRIMARY KEY (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
