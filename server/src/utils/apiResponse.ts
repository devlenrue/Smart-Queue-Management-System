/**
 * The one place the success envelope of docs/api.md §1 is constructed.
 */
import type { Response } from 'express';
import type { ErrorCode, FieldError } from './AppError';

export interface PageMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export interface SuccessBody<T> {
  success: true;
  message: string;
  data: T;
  meta?: PageMeta;
}

export interface ErrorBody {
  success: false;
  message: string;
  code: ErrorCode;
  errors: FieldError[];
}

export function ok<T>(res: Response, message: string, data: T, meta?: PageMeta): Response {
  const body: SuccessBody<T> = { success: true, message, data };
  if (meta) body.meta = meta;
  return res.status(200).json(body);
}

export function created<T>(res: Response, message: string, data: T): Response {
  return res.status(201).json({ success: true, message, data } satisfies SuccessBody<T>);
}

export function noContent(res: Response): Response {
  return res.status(204).send();
}

export function buildPageMeta(page: number, limit: number, total: number): PageMeta {
  return { page, limit, total, totalPages: limit > 0 ? Math.ceil(total / limit) : 0 };
}
