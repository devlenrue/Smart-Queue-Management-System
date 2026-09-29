import type { RequestHandler } from 'express';
import { ZodError, type ZodTypeAny } from 'zod';
import { AppError } from '../utils/AppError';

export interface ValidationSchemas {
  body?: ZodTypeAny;
  query?: ZodTypeAny;
  params?: ZodTypeAny;
}

/**
 * Parses and *replaces* the request parts with their validated, coerced
 * versions, so controllers receive typed data and never re-check anything.
 *
 * `req.query` is a prototype getter in Express 4, hence defineProperty.
 */
export function validate(schemas: ValidationSchemas): RequestHandler {
  return (req, _res, next) => {
    try {
      if (schemas.body) req.body = schemas.body.parse(req.body ?? {});
      if (schemas.params) {
        Object.defineProperty(req, 'params', {
          value: schemas.params.parse(req.params ?? {}),
          writable: true,
          configurable: true,
          enumerable: true,
        });
      }
      if (schemas.query) {
        Object.defineProperty(req, 'query', {
          value: schemas.query.parse(req.query ?? {}),
          writable: true,
          configurable: true,
          enumerable: true,
        });
      }
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        next(
          AppError.validation(
            'Some of the information provided is not valid.',
            error.issues.map((issue) => ({
              field: issue.path.join('.') || 'body',
              message: issue.message,
            })),
          ),
        );
        return;
      }
      next(error);
    }
  };
}
