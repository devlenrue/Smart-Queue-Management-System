/**
 * Waiting-time estimation (§19 of the brief, docs/queue-engine.md §5).
 *
 *     estimated_wait_minutes = ceil(people_ahead × effective_minutes / active_counters)
 *
 * Nothing here is hard-coded: `people_ahead` is counted from live rows,
 * `active_counters` is counted from live counter rows, and
 * `effective_minutes` blends today's *measured* service time with the
 * configured value.
 */
import { getDb } from '../db';
import type { DbConn } from '../db/types';
import { counterRepository } from '../repositories/counter.repository';
import { ticketRepository } from '../repositories/ticket.repository';
import { todayDate } from '../utils/datetime';

/** Below this many completed services today, measurement is not trusted. */
export const MIN_SAMPLE_SIZE = 5;
/** Weight given to the measured average once there is enough evidence. */
export const MEASURED_WEIGHT = 0.7;

export interface EstimationInputs {
  serviceId: number;
  /** queue_settings.estimated_service_time, falling back to services.average_service_time */
  configuredMinutes: number;
  queueDate?: string;
}

export interface EstimationBasis {
  effectiveMinutes: number;
  activeCounters: number;
  measuredMinutes: number | null;
  sampleSize: number;
}

/**
 * The per-customer service time to use right now.
 *
 * A constant would make the estimate fiction; a pure measurement would swing
 * wildly on the first ticket of the day. The blend is stable early and
 * reality-led later.
 */
export async function effectiveServiceMinutes(
  inputs: EstimationInputs,
  conn: DbConn = getDb(),
): Promise<{ effectiveMinutes: number; measuredMinutes: number | null; sampleSize: number }> {
  const queueDate = inputs.queueDate ?? todayDate();
  const { averageMinutes, sampleSize } = await ticketRepository.measuredServiceMinutes(inputs.serviceId, queueDate, conn);

  if (averageMinutes == null || sampleSize < MIN_SAMPLE_SIZE) {
    return { effectiveMinutes: inputs.configuredMinutes, measuredMinutes: averageMinutes, sampleSize };
  }

  const blended = MEASURED_WEIGHT * averageMinutes + (1 - MEASURED_WEIGHT) * inputs.configuredMinutes;
  return {
    effectiveMinutes: Math.max(1, Math.round(blended)),
    measuredMinutes: averageMinutes,
    sampleSize,
  };
}

/** Counters able to serve, floored at 1 so the formula never divides by zero. */
export async function activeCounterCount(serviceId: number, conn: DbConn = getDb()): Promise<number> {
    return Math.max(1, await counterRepository.countActive(serviceId, conn));
}

export async function estimationBasis(inputs: EstimationInputs, conn: DbConn = getDb()): Promise<EstimationBasis> {
  const [{ effectiveMinutes, measuredMinutes, sampleSize }, activeCounters] = await Promise.all([
    effectiveServiceMinutes(inputs, conn),
    activeCounterCount(inputs.serviceId, conn),
  ]);
  return { effectiveMinutes, activeCounters, measuredMinutes, sampleSize };
}

/** The formula itself, isolated so it can be unit-tested without a database. */
export function computeWaitMinutes(peopleAhead: number, effectiveMinutes: number, activeCounters: number): number {
  if (peopleAhead <= 0) return 0;
  const counters = Math.max(1, activeCounters);
  return Math.ceil((peopleAhead * effectiveMinutes) / counters);
}

export async function estimateWaitMinutes(
  peopleAhead: number,
  inputs: EstimationInputs,
  conn: DbConn = getDb(),
): Promise<{ estimatedWaitMinutes: number; basis: EstimationBasis }> {
  const basis = await estimationBasis(inputs, conn);
  return {
    estimatedWaitMinutes: computeWaitMinutes(peopleAhead, basis.effectiveMinutes, basis.activeCounters),
    basis,
  };
}
