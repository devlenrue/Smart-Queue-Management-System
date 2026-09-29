/**
 * Row → DTO mapping.
 *
 * This is the boundary that guarantees `password_hash` can never leave the
 * API: the DTO type has no such field and the mapper never copies it.
 */
import { toIso } from '../utils/datetime';
import type { AuthUser, UserDto, UserRow } from '../types/domain';

export function toUserDto(row: UserRow): UserDto {
  return {
    id: Number(row.id),
    firstName: row.first_name,
    lastName: row.last_name,
    fullName: `${row.first_name} ${row.last_name}`.trim(),
    email: row.email,
    phone: row.phone,
    role: row.role,
    status: row.status,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

export function toAuthUser(row: UserRow): AuthUser {
  return {
    id: Number(row.id),
    firstName: row.first_name,
    lastName: row.last_name,
    email: row.email,
    phone: row.phone,
    role: row.role,
    status: row.status,
  };
}
