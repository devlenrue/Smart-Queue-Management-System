import type { Request, Response } from 'express';
import { rosterService } from '../services/roster.service';
import { buildPageMeta, created, noContent, ok } from '../utils/apiResponse';
import type {
  AssignStaffBody,
  CreateCounterBody,
  CreateStaffBody,
  StaffListQuery,
  UpdateCounterBody,
  UpdateStaffBody,
} from '../validators/admin.validators';

export const staffAdminController = {
  /** GET /api/v1/staff?serviceId=&status=&unassigned=&search= */
  async list(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as StaffListQuery;
    const { staff, total } = await rosterService.listStaff({
      serviceId: query.serviceId,
      status: query.status,
      unassigned: query.unassigned,
      search: query.search,
      page: query.page,
      limit: query.limit,
      sort: query.sort,
      order: query.order,
    });
    ok(res, 'Staff retrieved', staff, buildPageMeta(query.page, query.limit, total));
  },

  /** POST /api/v1/staff — the only way a staff account comes into existence. */
  async create(req: Request, res: Response): Promise<void> {
    const body = req.body as CreateStaffBody;
    const staff = await rosterService.createStaff(body);
    created(res, `${staff.fullName} was added to the team`, staff);
  },

  /** PUT /api/v1/staff/:id */
  async update(req: Request, res: Response): Promise<void> {
    const body = req.body as UpdateStaffBody;
    const staff = await rosterService.updateStaff(Number(req.params.id), body);
    ok(res, `${staff.fullName} was updated`, staff);
  },

  /** POST /api/v1/staff/:id/assign { serviceId, counterId? } */
  async assign(req: Request, res: Response): Promise<void> {
    const body = req.body as AssignStaffBody;
    const staff = await rosterService.assign(Number(req.params.id), {
      serviceId: body.serviceId,
      counterId: body.counterId ?? null,
    });
    const where = staff.posting?.counterName ?? staff.posting?.serviceName ?? 'their new posting';
    ok(res, `${staff.fullName} is now posted to ${where}`, staff);
  },

  /** POST /api/v1/staff/:id/unassign { assignmentId? } */
  async unassign(req: Request, res: Response): Promise<void> {
    const body = (req.body ?? {}) as { assignmentId?: number };
    const staff = await rosterService.unassign(Number(req.params.id), { assignmentId: body.assignmentId });
    ok(res, `${staff.fullName} is no longer posted to a counter`, staff);
  },
};

export const counterAdminController = {
  /** POST /api/v1/counters */
  async create(req: Request, res: Response): Promise<void> {
    const body = req.body as CreateCounterBody;
    const counter = await rosterService.createCounter(body);
    created(res, `${counter.name} was created`, counter);
  },

  /** PUT /api/v1/counters/:id */
  async update(req: Request, res: Response): Promise<void> {
    const body = req.body as UpdateCounterBody;
    const counter = await rosterService.updateCounter(Number(req.params.id), body);
    ok(res, `${counter.name} was updated`, counter);
  },

  /** POST /api/v1/counters/:id/assign { staffId } */
  async assign(req: Request, res: Response): Promise<void> {
    const body = req.body as { staffId: number };
    const counter = await rosterService.assignCounter(Number(req.params.id), body.staffId);
    ok(res, `${counter.staff?.fullName ?? 'A staff member'} is now at ${counter.name}`, counter);
  },

  /** DELETE /api/v1/counters/:id/assign */
  async unassign(req: Request, res: Response): Promise<void> {
    const counter = await rosterService.unassignCounter(Number(req.params.id));
    ok(res, `${counter.name} is now unstaffed`, counter);
  },

  /** DELETE /api/v1/counters/:id */
  async remove(req: Request, res: Response): Promise<void> {
    await rosterService.removeCounter(Number(req.params.id));
    noContent(res);
  },
};
