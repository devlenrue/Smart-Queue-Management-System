/**
 * The administrator's read model (§31, §42) and the system-settings table.
 *
 * `GET /dashboard/admin` is deliberately one request: seven headline figures,
 * a per-service table, a seven-day bar series and a status donut all come from
 * the same snapshot, so the header can never contradict the table beneath it —
 * the same reasoning as the staff console in Phase 6.
 */
import { adminRepository } from '../repositories/admin.repository';
import { settingsRepository } from '../repositories/settings.repository';
import { addDays, todayDate } from '../utils/datetime';
import {
  toAdminServiceRowDto,
  toDashboardTotals,
  toServedSeries,
  toSettingDto,
  toStatusBreakdownDto,
  type AdminDashboardDto,
  type SystemSettingDto,
} from '../serializers/admin.serializer';

/** Inclusive list of 'YYYY-MM-DD' strings ending at `to`. */
function lastDays(to: string, days: number): string[] {
  const result: string[] = [];
  for (let offset = days - 1; offset >= 0; offset -= 1) result.push(addDays(to, -offset));
  return result;
}

export const adminService = {
  async getDashboard(options: { date?: string; days?: number } = {}): Promise<AdminDashboardDto> {
    const today = options.date ?? todayDate();
    const days = lastDays(today, options.days ?? 7);

    const [totals, averages, breakdown, series, statuses, headcount] = await Promise.all([
      adminRepository.dayTotals(today),
      adminRepository.dayAverages(today),
      adminRepository.serviceBreakdown(today),
      adminRepository.servedPerDay(days[0], today),
      adminRepository.statusBreakdown(today),
      adminRepository.headcount(today),
    ]);

    return {
      today,
      activeServices: headcount.activeServices,
      activeQueues: headcount.activeQueues,
      activeCounters: headcount.activeCounters,
      staffOnDuty: headcount.staffOnDuty,
      ...toDashboardTotals(totals, averages),
      byService: breakdown.map(toAdminServiceRowDto),
      servedPerDay: toServedSeries(series, days),
      statusBreakdown: toStatusBreakdownDto(statuses),
    };
  },

  async listSettings(): Promise<SystemSettingDto[]> {
    const rows = await settingsRepository.list();
    return rows.map(toSettingDto);
  },

  /**
   * Writes an open map of settings.
   *
   * Values are normalised to text on the way in — `true` becomes `'true'`,
   * `5` becomes `'5'` — so the column type never depends on what JSON happened
   * to carry. A `null` deletes the key.
   */
  async updateSettings(values: Record<string, string | number | boolean | null>): Promise<SystemSettingDto[]> {
    for (const [key, value] of Object.entries(values)) {
      if (value === null) {
        await settingsRepository.remove(key);
        continue;
      }
      await settingsRepository.upsert(key, String(value));
    }
    return this.listSettings();
  },
};
