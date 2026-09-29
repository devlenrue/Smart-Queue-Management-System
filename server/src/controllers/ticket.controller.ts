import type { Request, Response } from 'express';
import { ticketService } from '../services/ticket.service';
import { queueService } from '../services/queue.service';
import { buildPageMeta, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import type { CallNextBody, CallTicketBody, MyTicketsQuery, SkipTicketBody } from '../validators/queue.validators';

export const ticketController = {
  async myTickets(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const query = req.query as unknown as MyTicketsQuery;
    const { tickets, total } = await ticketService.listForUser(user.id, {
      status: query.status,
      serviceId: query.serviceId,
      page: query.page,
      limit: query.limit,
    });
    ok(res, 'Tickets retrieved', tickets, buildPageMeta(query.page, query.limit, total));
  },

  async myActiveTickets(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Active tickets retrieved', await ticketService.getActiveForUser(user.id));
  },

  async getOne(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Ticket retrieved', await ticketService.getById(Number(req.params.id), user));
  },

  /** Polled by the ticket screen; also triggers the "almost your turn" alert. */
  async position(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const ticketId = Number(req.params.id);
    await ticketService.getById(ticketId, user); // authorisation
    ok(res, 'Position retrieved', await queueService.getPositionFor(ticketId, { notify: true }));
  },

  async events(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Ticket history retrieved', await ticketService.getEvents(Number(req.params.id), user));
  },

  async cancel(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    ok(res, 'Ticket cancelled', await ticketService.cancel(Number(req.params.id), user));
  },

  // ----------------------------------------------------------------- staff

  async callNext(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const body = req.body as CallNextBody;
    const result = await ticketService.callNext(user, body.serviceId, body.counterId);
    ok(res, `Now calling ${result.ticket.ticketNumber}`, result);
  },

  async call(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const body = req.body as CallTicketBody;
    const result = await ticketService.call(Number(req.params.id), user, body.counterId);
    ok(res, `Now calling ${result.ticket.ticketNumber}`, result);
  },

  async recall(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const result = await ticketService.recall(Number(req.params.id), user);
    ok(res, `Recalled ${result.ticket.ticketNumber}`, result);
  },

  async start(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const result = await ticketService.start(Number(req.params.id), user);
    ok(res, `Serving ${result.ticket.ticketNumber}`, result);
  },

  async complete(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const result = await ticketService.complete(Number(req.params.id), user);
    ok(res, `Completed ${result.ticket.ticketNumber}`, result);
  },

  async skip(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const body = req.body as SkipTicketBody;
    const result = await ticketService.skip(Number(req.params.id), user, body.reason);
    ok(res, `Skipped ${result.ticket.ticketNumber}`, result);
  },

  async noShow(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const result = await ticketService.noShow(Number(req.params.id), user);
    ok(res, `Marked ${result.ticket.ticketNumber} as a no-show`, result);
  },
};
