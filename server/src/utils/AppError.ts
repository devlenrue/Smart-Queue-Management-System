/**
 * The single error type the application throws on purpose.
 *
 * Anything that is *not* an AppError reaching the error middleware is treated
 * as a bug: it is logged in full and reported to the client as a generic 500,
 * so raw exceptions never leak (§63).
 */

export type ErrorCode =
  // 400
  | 'BAD_REQUEST'
  // 401
  | 'UNAUTHENTICATED'
  | 'INVALID_CREDENTIALS'
  | 'TOKEN_EXPIRED'
  | 'TOKEN_REVOKED'
  // 403
  | 'FORBIDDEN'
  | 'ACCOUNT_INACTIVE'
  | 'ACCOUNT_SUSPENDED'
  | 'NOT_ASSIGNED_TO_SERVICE'
  // 404
  | 'NOT_FOUND'
  | 'NO_WAITING_TICKETS'
  // 409
  | 'EMAIL_TAKEN'
  | 'PHONE_TAKEN'
  | 'SERVICE_CODE_TAKEN'
  | 'COUNTER_NUMBER_TAKEN'
  | 'STAFF_ALREADY_ASSIGNED'
  | 'DUPLICATE_ACTIVE_TICKET'
  | 'REJOIN_NOT_ALLOWED'
  | 'SERVICE_CLOSED'
  | 'SERVICE_INACTIVE'
  | 'OUTSIDE_SERVICE_HOURS'
  | 'QUEUE_PAUSED'
  | 'QUEUE_CLOSED'
  | 'QUEUE_FULL'
  | 'INVALID_STATE_TRANSITION'
  | 'CANCELLATION_NOT_ALLOWED'
  | 'COUNTER_BUSY'
  | 'COUNTER_OFFLINE'
  | 'CONFLICT'
  // 422
  | 'VALIDATION_ERROR'
  // 429
  | 'RATE_LIMITED'
  // 500
  | 'INTERNAL_ERROR'
  | 'DATABASE_ERROR';

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
