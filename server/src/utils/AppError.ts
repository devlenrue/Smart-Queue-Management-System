/**
 * The single error type the application throws on purpose.
 *
 * Anything that is *not* an AppError reaching the error middleware is treated
 * as a bug: it is logged in full and reported to the client as a generic 500,
 * so raw exceptions never leak (§63).
 */

/**
 * Every error code the API can return, mapped to the HTTP status it is always
 * sent with. Keeping this as a runtime object rather than a bare type union
 * buys three things:
 *
 *   1. `docs/api.md` §15.3 is generated from the same list the code throws;
 *   2. `tests/errors.test.ts` enumerates it, so adding a code without adding a
 *      negative-path test fails the build;
 *   3. a code can never be returned with two different statuses, because the
 *      status is a property of the code.
 */
export const ERROR_CATALOGUE = {
  // 400 — the request itself is malformed.
  BAD_REQUEST: 400,

  // 401 — who are you?
  UNAUTHENTICATED: 401,
  INVALID_CREDENTIALS: 401,
  TOKEN_EXPIRED: 401,
  TOKEN_REVOKED: 401,

  // 403 — we know who you are, and you may not.
  FORBIDDEN: 403,
  ACCOUNT_INACTIVE: 403,
  ACCOUNT_SUSPENDED: 403,
  NOT_ASSIGNED_TO_SERVICE: 403,

  // 404 — no such thing.
  NOT_FOUND: 404,
  NO_WAITING_TICKETS: 404,

  // 409 — the request is well formed but conflicts with the current state.
  EMAIL_TAKEN: 409,
  PHONE_TAKEN: 409,
  SERVICE_CODE_TAKEN: 409,
  COUNTER_NUMBER_TAKEN: 409,
  STAFF_ALREADY_ASSIGNED: 409,
  DUPLICATE_ACTIVE_TICKET: 409,
  REJOIN_NOT_ALLOWED: 409,
  SERVICE_CLOSED: 409,
  SERVICE_INACTIVE: 409,
  OUTSIDE_SERVICE_HOURS: 409,
  QUEUE_PAUSED: 409,
  QUEUE_CLOSED: 409,
  QUEUE_FULL: 409,
  INVALID_STATE_TRANSITION: 409,
  CANCELLATION_NOT_ALLOWED: 409,
  COUNTER_BUSY: 409,
  COUNTER_OFFLINE: 409,
  CONFLICT: 409,

  // 413 — body-parser rejected the payload before we ever saw it.
  PAYLOAD_TOO_LARGE: 413,

  // 422 — well formed, understood, but the values are wrong.
  VALIDATION_ERROR: 422,

  // 429 — slow down.
  RATE_LIMITED: 429,

  // 500 — our fault.
  INTERNAL_ERROR: 500,
  DATABASE_ERROR: 500,
} as const;

export type ErrorCode = keyof typeof ERROR_CATALOGUE;

/** The catalogue as a list, for tests and documentation tooling. */
export const ERROR_CODES = Object.keys(ERROR_CATALOGUE) as ErrorCode[];

/** The one HTTP status a given code is ever returned with. */
export function statusForCode(code: ErrorCode): number {
  return ERROR_CATALOGUE[code];
}

export interface FieldError {
  field: string;
  message: string;
}

export class AppError extends Error {
  readonly statusCode: number;
  readonly code: ErrorCode;
  readonly errors: FieldError[];
  /** Safe to show a user verbatim. */
  readonly isOperational = true;

  constructor(statusCode: number, code: ErrorCode, message: string, errors: FieldError[] = []) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.errors = errors;
    Error.captureStackTrace?.(this, AppError);
  }

  static badRequest(message: string, code: ErrorCode = 'BAD_REQUEST'): AppError {
    return new AppError(400, code, message);
  }

  static unauthorized(message = 'You need to sign in to continue.', code: ErrorCode = 'UNAUTHENTICATED'): AppError {
    return new AppError(401, code, message);
  }

  static forbidden(message = 'You do not have permission to perform this action.', code: ErrorCode = 'FORBIDDEN'): AppError {
    return new AppError(403, code, message);
  }

  static notFound(message = 'The requested resource was not found.', code: ErrorCode = 'NOT_FOUND'): AppError {
    return new AppError(404, code, message);
  }

  static conflict(code: ErrorCode, message: string): AppError {
    return new AppError(409, code, message);
  }

  static validation(message: string, errors: FieldError[] = []): AppError {
    return new AppError(422, 'VALIDATION_ERROR', message, errors);
  }

  static internal(message = 'Something went wrong on our side. Please try again.'): AppError {
    return new AppError(500, 'INTERNAL_ERROR', message);
  }
}

export function isAppError(error: unknown): error is AppError {
  return error instanceof AppError;
}
