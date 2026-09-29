/**
 * Re-export surface for error types, so middleware and services import from a
 * stable path rather than reaching into utils/.
 */
export { AppError, isAppError, ERROR_CATALOGUE, ERROR_CODES, statusForCode } from '../utils/AppError';
export type { ErrorCode, FieldError } from '../utils/AppError';

import type { ErrorCode, FieldError } from '../utils/AppError';

export interface ErrorBodyShape {
  success: false;
  message: string;
  code: ErrorCode;
  errors: FieldError[];
}
