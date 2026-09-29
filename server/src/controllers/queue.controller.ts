import type { Request, Response } from 'express';
import { queueService } from '../services/queue.service';
import { created, ok } from '../utils/apiResponse';
import { requireUser } from '../middleware/auth';
import type { QueueListQuery } from '../validators/queue.validators';

export const queueController = {
  /**
   * POST /api/v1/services/:id/queue/join — the single busiest endpoint.
   *
   * Addressed by service because that is what a customer has in hand: a card
   * in the catalogue, a deep link, a QR code. The queue for today is resolved
   * (and created on first use) inside the engine.
   */
  async join(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const serviceId = Number(req.params.id);
    const result = await queueService.joinQueue(user.id, serviceId);
    created(res, `Ticket ${result.ticket.ticketNumber} issued`, result);
  },

  /** POST /api/v1/queues/:id/join — same operation, addressed by queue. */
  async joinByQueue(req: Request, res: Response): Promise<void> {
    const user = requireUser(req);
    const queue = await queueService.requireQueue(Number(req.params.id));
    const result = await queueService.joinQueue(user.id, Number(queue.service_id));
    created(res, `Ticket ${result.ticket.ticketNumber} issued`, result);
  },

  /** Public — the waiting-room display needs no account. */
  async statusForService(req: Request, res: Response): Promise<void> {
    const queue = await queueService.getOrCreateTodayQueue(Number(req.params.id));
    ok(res, 'Queue status retrieved', await queueService.getQueueStatus(Number(queue.id)));
  },

  async statusForQueue(req: Request, res: Response): Promise<void> {
    ok(res, 'Queue status retrieved', await queueService.getQueueStatus(Number(req.params.id)));
  },

  async list(req: Request, res: Response): Promise<void> {
    const query = req.query as unknown as QueueListQuery;
    const queues = await queueService.listForDate({
      queueDate: query.date,
      serviceId: query.serviceId,
      status: query.status,
    });
    ok(res, 'Queues retrieved', queues);
  },

  async monitor(req: Request, res: Response): Promise<void> {
    ok(res, 'Queue monitor retrieved', await queueService.getMonitor(Number(req.params.id)));
  },

  async pause(req: Request, res: Response): Promise<void> {
    ok(res, 'Queue paused', await queueService.setStatus(Number(req.params.id), 'paused'));
  },

  async resume(req: Request, res: Response): Promise<void> {
    ok(res, 'Queue resumed', await queueService.setStatus(Number(req.params.id), 'waiting'));
  },

  async close(req: Request, res: Response): Promise<void> {
    ok(res, 'Queue closed', await queueService.setStatus(Number(req.params.id), 'closed'));
  },
};
