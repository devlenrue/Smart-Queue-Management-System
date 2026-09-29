/** Service catalogue: CRUD plus the live queue figures each card shows. */
import { withTransaction } from '../db';
import { AppError } from '../utils/AppError';
import { serviceRepository, type CreateServiceInput, type ServiceListFilters } from '../repositories/service.repository';
import { counterRepository } from '../repositories/counter.repository';
import { queueService } from './queue.service';
import {
  toCounterDto,
  toHoursDto,
  toServiceDto,
  toSettingsDto,
  type ServiceDto,
} from '../serializers/service.serializer';
import type { ServiceStatus } from '../types/domain';

export const serviceCatalogService = {
  /** Service list with live queue figures — never client-computed (§15). */
  async list(filters: ServiceListFilters & { withQueue?: boolean }): Promise<{ services: ServiceDto[]; total: number }> {
    const { rows, total } = await serviceRepository.list(filters);

    const services = await Promise.all(
      rows.map(async (row) => {
        const dto = toServiceDto(row);
        if (filters.withQueue === false || row.status === 'inactive') return dto;
        dto.queue = await queueService.getQueueSummary(Number(row.id));
        dto.hoursToday = await queueService.getTodayHours(Number(row.id));
        return dto;
      }),
    );

    return { services, total };
  },

  async getById(id: number, options: { detailed?: boolean } = {}): Promise<ServiceDto> {
    const row = await serviceRepository.findById(id);
    if (!row) throw AppError.notFound('That service could not be found.');

    const dto = toServiceDto(row);
    if (row.status !== 'inactive') {
      dto.queue = await queueService.getQueueSummary(id);
      dto.hoursToday = await queueService.getTodayHours(id);
    }

    if (options.detailed) {
      const [hours, settings, counters] = await Promise.all([
        serviceRepository.findHours(id),
        serviceRepository.findSettings(id),
        counterRepository.listDetailed({ serviceId: id }),
      ]);
      dto.hours = hours.map(toHoursDto);
      if (settings) dto.settings = toSettingsDto(settings);
      dto.counters = counters.map(toCounterDto);
    }

    return dto;
  },

  /** Creates the service and its default settings row in one transaction. */
  async create(input: CreateServiceInput): Promise<ServiceDto> {
    if (await serviceRepository.codeExists(input.code)) {
      throw AppError.conflict('SERVICE_CODE_TAKEN', `The service code ${input.code.toUpperCase()} is already in use.`);
    }

    const id = await withTransaction(async (tx) => {
      const serviceId = await serviceRepository.create(input, tx);
      await serviceRepository.createDefaultSettings(serviceId, input.averageServiceTime, tx);
      return serviceId;
    });

    return this.getById(id, { detailed: true });
  },

  async update(id: number, input: Partial<CreateServiceInput>): Promise<ServiceDto> {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');

    if (input.code && (await serviceRepository.codeExists(input.code, id))) {
      throw AppError.conflict('SERVICE_CODE_TAKEN', `The service code ${input.code.toUpperCase()} is already in use.`);
    }

    await serviceRepository.update(id, input);
    return this.getById(id, { detailed: true });
  },

  /** Soft delete by default — history must survive (docs/database.md §6). */
  async deactivate(id: number): Promise<ServiceDto> {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');
    await serviceRepository.update(id, { status: 'inactive' as ServiceStatus });
    return this.getById(id);
  },

  async remove(id: number): Promise<void> {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');
    await serviceRepository.remove(id);
  },

  async getHours(id: number) {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');
    return (await serviceRepository.findHours(id)).map(toHoursDto);
  },

  async replaceHours(
    id: number,
    hours: Array<{ dayOfWeek: number; openingTime: string; closingTime: string; status: 'open' | 'closed' }>,
  ) {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');
    await withTransaction((tx) => serviceRepository.replaceHours(id, hours, tx));
    return this.getHours(id);
  },

  async getSettings(id: number) {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');
    let settings = await serviceRepository.findSettings(id);
    if (!settings) {
      await serviceRepository.createDefaultSettings(id, existing.average_service_time);
      settings = await serviceRepository.findSettings(id);
    }
    return toSettingsDto(settings!);
  },

  async updateSettings(
    id: number,
    input: Partial<{
      maxQueueSize: number;
      allowCancellation: boolean;
      allowRejoin: boolean;
      notificationThreshold: number;
      estimatedServiceTime: number;
    }>,
  ) {
    const existing = await serviceRepository.findById(id);
    if (!existing) throw AppError.notFound('That service could not be found.');
    await serviceRepository.updateSettings(id, input);
    return this.getSettings(id);
  },

  async categories(): Promise<string[]> {
    return serviceRepository.distinctCategories();
  },
};
