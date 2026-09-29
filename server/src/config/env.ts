/**
 * Typed, validated environment configuration.
 *
 * Nothing else in the codebase reads `process.env` directly — every setting is
 * parsed and range-checked once, here, so a misconfigured deployment fails at
 * boot with a readable message instead of at 2 a.m. with a stack trace.
 */
import path from 'node:path';
import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const isTest = process.env.NODE_ENV === 'test';

// Zero-config test runs: an in-memory database and a throwaway signing key.
if (isTest) {
  process.env.DATABASE_URL = process.env.DATABASE_URL ?? 'sqlite://:memory:';
  process.env.JWT_SECRET = process.env.JWT_SECRET ?? 'jest-only-secret-not-for-real-use';
}

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(5000),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  TZ: z.string().min(1).default('Africa/Nairobi'),

  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  DB_POOL_SIZE: z.coerce.number().int().positive().max(100).default(10),

  JWT_SECRET: z.string().min(16, 'JWT_SECRET must be at least 16 characters'),
  JWT_EXPIRES_IN: z.string().min(1).default('7d'),
  BCRYPT_ROUNDS: z.coerce.number().int().min(4).max(15).default(10),

  CORS_ORIGIN: z.string().default('*'),
  RATE_LIMIT_WINDOW_MINUTES: z.coerce.number().int().positive().default(15),
  RATE_LIMIT_AUTH_MAX: z.coerce.number().int().positive().default(30),
  RATE_LIMIT_JOIN_MAX: z.coerce.number().int().positive().default(20),

  QUEUE_DEFAULT_SERVICE_MINUTES: z.coerce.number().int().positive().default(5),
  QUEUE_NOTIFY_THRESHOLD: z.coerce.number().int().positive().default(3),
  QUEUE_DEFAULT_MAX_SIZE: z.coerce.number().int().positive().default(100),

  SEED_PASSWORD: z.string().min(6).default('Password123!'),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  const details = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`).join('\n');
  // eslint-disable-next-line no-console
  console.error(`\nInvalid environment configuration:\n${details}\n\nCopy .env.example to .env and fill it in.\n`);
  process.exit(1);
}

const raw = parsed.data;

/** Every date the server computes (queue_date, service hours) uses this zone. */
process.env.TZ = raw.TZ;

export type DbDialect = 'mysql' | 'sqlite';

export interface MysqlConnectionConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  database: string;
}

export interface DatabaseConfig {
  dialect: DbDialect;
  /** Present when dialect === 'mysql'. */
  mysql?: MysqlConnectionConfig;
  /** Present when dialect === 'sqlite'. Either ':memory:' or a file path. */
  sqliteFile?: string;
  poolSize: number;
}

/**
 * Selecting the driver from the URL scheme is the whole of the portability
 * story: `mysql://…` → the MySQL pool, `sqlite://…` → the local file driver.
 * See docs/roadmap.md "Verification strategy".
 */
function parseDatabaseUrl(url: string, poolSize: number): DatabaseConfig {
  if (url.startsWith('sqlite:') || url.startsWith('file:')) {
    const file = url.replace(/^sqlite:\/\//, '').replace(/^sqlite:/, '').replace(/^file:/, '');
    return { dialect: 'sqlite', sqliteFile: file || ':memory:', poolSize: 1 };
  }

  if (url.startsWith('mysql://') || url.startsWith('mariadb://')) {
    const parsedUrl = new URL(url);
    const database = decodeURIComponent(parsedUrl.pathname.replace(/^\//, ''));
    if (!database) throw new Error('DATABASE_URL must include a database name, e.g. mysql://user:pass@host:3306/smart_queue');
    return {
      dialect: 'mysql',
      mysql: {
        host: parsedUrl.hostname,
        port: parsedUrl.port ? Number(parsedUrl.port) : 3306,
        user: decodeURIComponent(parsedUrl.username || 'root'),
        password: decodeURIComponent(parsedUrl.password || ''),
        database,
      },
      poolSize,
    };
  }

  throw new Error(`Unsupported DATABASE_URL scheme. Expected mysql:// or sqlite://, received "${url.split(':')[0]}:"`);
}

export const config = {
  port: raw.PORT,
  env: raw.NODE_ENV,
  isProduction: raw.NODE_ENV === 'production',
  isTest: raw.NODE_ENV === 'test',
  timezone: raw.TZ,

  database: parseDatabaseUrl(raw.DATABASE_URL, raw.DB_POOL_SIZE),

  jwt: {
    secret: raw.JWT_SECRET,
    expiresIn: raw.JWT_EXPIRES_IN,
  },
  bcryptRounds: raw.BCRYPT_ROUNDS,

  cors: {
    origins: raw.CORS_ORIGIN === '*' ? '*' : raw.CORS_ORIGIN.split(',').map((o) => o.trim()).filter(Boolean),
  },
  rateLimit: {
    windowMs: raw.RATE_LIMIT_WINDOW_MINUTES * 60 * 1000,
    authMax: raw.RATE_LIMIT_AUTH_MAX,
    joinMax: raw.RATE_LIMIT_JOIN_MAX,
  },

  queue: {
    defaultServiceMinutes: raw.QUEUE_DEFAULT_SERVICE_MINUTES,
    defaultNotifyThreshold: raw.QUEUE_NOTIFY_THRESHOLD,
    defaultMaxQueueSize: raw.QUEUE_DEFAULT_MAX_SIZE,
  },

  seedPassword: raw.SEED_PASSWORD,
} as const;

export type AppConfig = typeof config;
