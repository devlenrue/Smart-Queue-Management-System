import type { Request, Response } from 'express';
import { staffService } from '../services/staff.service';
import { buildPageMeta, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import { toCounterDto } from '../serializers/service.serializer';
import { toStaffCounterDto } from '../serializers/staff.serializer';
import type {
  CounterListQuery,
  StaffDashboardQuery,
  StaffStatisticsQuery,
  StaffTicketsQuery,
} from '../validators/staff.validators';

/**
 * Resolves the `:id` of a /staff route. `me` is accepted so the Flutter client
 * does not have to interpolate its own user id into every URL.
 */
function staffIdOf(req: Request): number {
  const raw = String(req.params.id ?? '');
  if (raw === 'me') return requireUser(req).id;
  return Number(raw);
}

export const staffController = {
  /** GET /api/v1/dashboard/staff — everything the console's first screen needs. */
  async dashboard(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const query = req.query as unknown as StaffDashboardQuery;
    const data = await staffService.getDashboard(user, {
      serviceId: query.serviceId,
      counterId: query.counterId,
    });
    ok(res, 'Staff dashboard retrieved', data);
  },

  /** GET /api/v1/staff/:id/statistics */
  async statistics(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const query = req.query as unknown as StaffStatisticsQuery;
    const data = await staffService.getStatistics(staffIdOf(req), user, { from: query.from, to: query.to });
    ok(res, 'Staff statistics retrieved', data);
  },

  /** GET /api/v1/staff/:id/tickets — the counter's own handling history. */
  async handledTickets(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const query = req.query as unknown as StaffTicketsQuery;
    const { tickets, total, range } = await staffService.getHandledTickets(staffIdOf(req), user, {
      from: query.from,
      to: query.to,
      status: query.status,
      page: query.page,
      limit: query.limit,
    });
    ok(res, 'Handled tickets retrieved', { tickets, range }, buildPageMeta(query.page, query.limit, total));
  },
};

export const counterController = {
  /** GET /api/v1/counters?serviceId=&status= */
  async list(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const query = req.query as unknown as CounterListQuery;
    const rows = await staffService.listCounters(user, { serviceId: query.serviceId, status: query.status });
    ok(res, 'Counters retrieved', rows.map(toCounterDto));
  },

  /** PATCH /api/v1/counters/:id/status — a clerk going on or off duty. */
  async setStatus(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const body = req.body as { status: 'available' | 'busy' | 'offline' };
    const counter = await staffService.setCounterStatus(Number(req.params.id), user, body.status);
    ok(res, `${counter.name} is now ${counter.status}`, toStaffCounterDto(counter));
  },
};
