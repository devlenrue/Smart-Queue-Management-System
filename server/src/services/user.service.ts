/**
 * User administration (§9).
 *
 * The interesting part of this file is not the CRUD — it is the four guards
 * that stop an administrator locking everybody, including themselves, out of
 * the system:
 *
 *   1. nobody may change their own status or role      (no self-demotion)
 *   2. nobody may delete their own account
 *   3. only a super_admin may touch another super_admin
 *   4. the last active super_admin may not be removed or demoted
 */
import { AppError } from '../utils/AppError';
import { adminRepository } from '../repositories/admin.repository';
import { assignmentRepository } from '../repositories/assignment.repository';
import { counterRepository } from '../repositories/counter.repository';
import { userRepository } from '../repositories/user.repository';
import { toUserDto } from '../serializers/user.serializer';
import { toStaffRosterDto, toUserActivityDto, type UserDetailDto } from '../serializers/admin.serializer';
import type { AuthUser, Role, UserDto, UserStatus } from '../types/domain';

async function requireUserRow(id: number) {
  const row = await userRepository.findById(id);
  if (!row) throw AppError.notFound('That user could not be found.');
  return row;
}

/** Guard 3: an ordinary admin may not administer a super_admin. */
function assertMayAdminister(actor: AuthUser, targetRole: Role): void {
  if (targetRole === 'super_admin' && actor.role !== 'super_admin') {
    throw AppError.forbidden('Only a super administrator can manage another super administrator.');
  }
}

/** Guard 4: the system must keep at least one active super administrator. */
async function assertNotLastSuperAdmin(targetId: number): Promise<void> {
  const { rows } = await userRepository.list({ role: 'super_admin', status: 'active', page: 1, limit: 100 });
  const remaining = rows.filter((row) => Number(row.id) !== targetId);
  if (remaining.length === 0) {
    throw AppError.conflict('CONFLICT', 'This is the last active super administrator, so it cannot be removed.');
  }
}

export const userService = {
  async list(filters: {
    role?: Role;
    status?: UserStatus;
    search?: string;
    page: number;
    limit: number;
    sort?: string;
    order?: string;
  }): Promise<{ users: UserDto[]; total: number }> {
    const { rows, total } = await userRepository.list(filters);
    return { users: rows.map(toUserDto), total };
  },

  /** Profile + what they have done + where they are posted, in one payload. */
  async getById(id: number): Promise<UserDetailDto> {
    const row = await requireUserRow(id);
    const [activity, staffRow] = await Promise.all([
      adminRepository.userActivity(id),
      row.role === 'staff' ? userRepository.findStaffRow(id) : Promise.resolve(null),
    ]);

    return {
      ...toUserDto(row),
      activity: toUserActivityDto(activity),
      posting: staffRow ? toStaffRosterDto(staffRow).posting : null,
    };
  },

  async setStatus(actor: AuthUser, id: number, status: UserStatus): Promise<UserDto> {
    const row = await requireUserRow(id);
    if (Number(row.id) === actor.id) {
      throw AppError.conflict('CONFLICT', 'You cannot change the status of your own account.');
    }
    assertMayAdminister(actor, row.role);
    if (row.role === 'super_admin' && status !== 'active') await assertNotLastSuperAdmin(id);

    await userRepository.updateStatus(id, status);

    // A suspended clerk must not keep a counter reserved behind them.
    if (status !== 'active' && row.role === 'staff') {
      const counter = await counterRepository.findByStaff(id);
      if (counter) await counterRepository.assignStaff(Number(counter.id), null);
      await assignmentRepository.endAllForStaff(id);
    }

    return toUserDto(await requireUserRow(id));
  },

  async setRole(actor: AuthUser, id: number, role: Role): Promise<UserDto> {
    const row = await requireUserRow(id);
    if (Number(row.id) === actor.id) {
      throw AppError.conflict('CONFLICT', 'You cannot change your own role.');
    }
    assertMayAdminister(actor, row.role);
    if (row.role === 'super_admin' && role !== 'super_admin') await assertNotLastSuperAdmin(id);

    await userRepository.updateRole(id, role);

    // Somebody who is no longer staff cannot hold a counter or a posting.
    if (row.role === 'staff' && role !== 'staff') {
      const counter = await counterRepository.findByStaff(id);
      if (counter) await counterRepository.assignStaff(Number(counter.id), null);
      await assignmentRepository.endAllForStaff(id);
    }

    return toUserDto(await requireUserRow(id));
  },

  /**
   * Hard delete, super_admin only.
   *
   * Every dependent row cascades (see the foreign keys in migration 001–005),
   * which is why this is offered at all: a mis-registered account can be
   * removed cleanly rather than lingering as a suspended ghost.
   */
  async remove(actor: AuthUser, id: number): Promise<void> {
    const row = await requireUserRow(id);
    if (Number(row.id) === actor.id) {
      throw AppError.conflict('CONFLICT', 'You cannot delete your own account.');
    }
    assertMayAdminister(actor, row.role);
    if (row.role === 'super_admin') await assertNotLastSuperAdmin(id);

    const counter = await counterRepository.findByStaff(id);
    if (counter) await counterRepository.assignStaff(Number(counter.id), null);

    await userRepository.remove(id);
  },
};
