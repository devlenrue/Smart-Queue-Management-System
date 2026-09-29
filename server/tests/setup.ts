/**
 * Jest bootstrap.
 *
 * Every test file gets its own in-memory SQLite database (Jest isolates the
 * module registry per file), so tests are fully independent and need no server
 * running anywhere.
 */
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = process.env.DATABASE_URL ?? 'sqlite://:memory:';
process.env.JWT_SECRET = process.env.JWT_SECRET ?? 'jest-only-secret-not-for-real-use';
process.env.TZ = process.env.TZ ?? 'Africa/Nairobi';
process.env.BCRYPT_ROUNDS = process.env.BCRYPT_ROUNDS ?? '4'; // keep hashing fast in tests

export {};
