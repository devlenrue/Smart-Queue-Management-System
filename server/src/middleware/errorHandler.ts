import type { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError } from 'zod';
import { AppError, isAppError, type ErrorBodyShape } from '../types/errors';
import { logger } from '../utils/logger';
import { config } from '../config/env';

/** The shape body-parser / http-errors throw with. */
interface BodyParserError extends Error {
  type: string;
  status?: number;
  statusCode?: number;
}

function isBodyParserError(err: unknown): err is BodyParserError {
  return (
    err instanceof Error &&
    typeof (err as Partial<BodyParserError>).type === 'string' &&
    (err as BodyParserError).type.startsWith('entity.')
  );
}

export const notFoundHandler: RequestHandler = (req, res) => {
  const body: ErrorBodyShape = {
    success: false,
    message: `Route ${req.method} ${req.originalUrl} does not exist.`,
    code: 'NOT_FOUND',
    errors: [],
  };
  res.status(404).json(body);
};

/**
 * Terminal error middleware. Converts anything thrown anywhere in the stack
 * into the error envelope of docs/api.md §1.
 *
 * Only AppError messages are shown to the user. Everything else is logged with
 * its stack and reported as a generic 500 (§63).
 */
export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  let status = 500;
  let body: ErrorBodyShape = {
    success: false,
    message: 'Something went wrong on our side. Please try again.',
    code: 'INTERNAL_ERROR',
    errors: [],
  };

  if (isAppError(err)) {
    status = err.statusCode;
    body = { success: false, message: err.message, code: err.code, errors: err.errors };
  } else if (err instanceof ZodError) {
    status = 422;
    body = {
      success: false,
      message: 'Some of the information provided is not valid.',
      code: 'VALIDATION_ERROR',
      errors: err.issues.map((issue) => ({ field: issue.path.join('.') || 'body', message: issue.message })),
    };
  } else if (isBodyParserError(err)) {
    // body-parser rejects a payload before any route runs, and throws an
    // http-errors object rather than an AppError. Without this branch an
    // oversized or malformed body would be reported as a 500 "our fault".
    if (err.type === 'entity.too.large') {
      status = 413;
      body = {
        success: false,
        message: 'That request is too large. Please send less data.',
        code: 'PAYLOAD_TOO_LARGE',
        errors: [],
      };
    } else {
      status = 400;
      body = { success: false, message: 'The request body could not be read as JSON.', code: 'BAD_REQUEST', errors: [] };
    }
  } else if (err instanceof SyntaxError && 'body' in err) {
    status = 400;
    body = { success: false, message: 'The request body is not valid JSON.', code: 'BAD_REQUEST', errors: [] };
  }

  if (status >= 500) {
    logger.error(`Unhandled error on ${req.method} ${req.originalUrl}`, {
      message: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });
    // Development convenience only — never in production, never for a client.
    if (!config.isProduction && err instanceof Error) {
      (body as ErrorBodyShape & { debug?: string }).debug = err.message;
    }
  } else if (status >= 400 && !config.isTest) {
    logger.debug(`${status} ${body.code} on ${req.method} ${req.originalUrl}: ${body.message}`);
  }

  res.status(status).json(body);
};

export { AppError };
