import type { Request, Response } from 'express';
import { reportService } from '../services/report.service';
import type { ReportKind } from '../services/report.service';
import { reportToCsv } from '../serializers/report.csv';
import type { AnyReport } from '../serializers/report.csv';
import { ok } from '../utils/apiResponse';
import { csvFilename } from '../utils/csv';
import type { ReportQueryInput } from '../validators/report.validators';

/**
 * The four reports (§41). Each endpoint answers in one of two formats:
 *
 *   ?format=json  the usual envelope — `{ range, rows, totals }`
 *   ?format=csv   the same rows as a downloadable file
 *
 * The CSV branch is the only place in the API that does not return the
 * envelope of docs/api.md §1, because a spreadsheet cannot open one. It is
 * documented as an exception rather than quietly special-cased.
 */
function send(req: Request, res: Response, kind: ReportKind, message: string, report: AnyReport): void {
  const query = req.query as unknown as ReportQueryInput;

  if (query.format === 'csv') {
    // `attachment()` also sets a Content-Type from the extension, so the
    // explicit charset has to come after it, not before.
    res
      .status(200)
      .attachment(csvFilename(kind, report.range.from, report.range.to))
      .type('text/csv; charset=utf-8')
      .send(reportToCsv(kind, report));
    return;
  }

  ok(res, message, report);
}

export const reportController = {
  /** GET /api/v1/reports/daily */
  async daily(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as ReportQueryInput;
    send(req, res, 'daily', 'Daily report generated', await reportService.daily(query));
  },

  /** GET /api/v1/reports/services */
  async services(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as ReportQueryInput;
    send(req, res, 'services', 'Service report generated', await reportService.services(query));
  },

  /** GET /api/v1/reports/staff */
  async staff(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as ReportQueryInput;
    send(req, res, 'staff', 'Staff report generated', await reportService.staff(query));
  },

  /** GET /api/v1/reports/queues */
  async queues(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as ReportQueryInput;
    send(req, res, 'queues', 'Queue report generated', await reportService.queues(query));
  },
};
