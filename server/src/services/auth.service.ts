/**
 * Authentication business logic. Knows nothing about Express.
 */
import { AppError } from '../utils/AppError';
import { hashPassword, verifyPassword } from '../utils/password';
import { signToken } from '../utils/jwt';
import { tokenRepository, userRepository } from '../repositories/user.repository';
import { toUserDto } from '../serializers/user.serializer';
import { withTransaction } from '../db';
import type { UserDto, UserRow } from '../types/domain';
import type { ChangePasswordInput, LoginInput, RegisterInput, UpdateProfileInput } from '../validators/auth.validators';

export interface AuthResult {
  token: string;
  expiresAt: string;
  user: UserDto;
}

function issue(row: UserRow): AuthResult {
  const { token, expiresAt } = signToken(Number(row.id), row.role);
  return { token, expiresAt: expiresAt.toISOString(), user: toUserDto(row) };
}

export const authService = {
  /** Self-registration. Always produces a `customer`. */
  async register(input: RegisterInput): Promise<AuthResult> {
    if (await userRepository.emailExists(input.email)) {
      throw AppError.conflict('EMAIL_TAKEN', 'An account with this email address already exists.');
    }
    if (await userRepository.phoneExists(input.phone)) {
      throw AppError.conflict('PHONE_TAKEN', 'An account with this phone number already exists.');
    }

    const passwordHash = await hashPassword(input.password);
    const id = await withTransaction((tx) =>
      userRepository.create(
        {
          firstName: input.firstName,
          lastName: input.lastName,
          email: input.email,
          phone: input.phone,
          passwordHash,
          role: 'customer',
          status: 'active',
        },
        tx,
      ),
    );

    const row = await userRepository.findById(id);
    if (!row) throw AppError.internal();
    return issue(row);
  },

  async login(input: LoginInput): Promise<AuthResult> {
    const row = await userRepository.findByEmail(input.email);

    // Identical response for "no such user" and "wrong password" so the
    // endpoint cannot be used to enumerate registered email addresses.
    if (!row || !(await verifyPassword(input.password, row.password_hash))) {
      throw AppError.unauthorized('The email or password you entered is incorrect.', 'INVALID_CREDENTIALS');
    }
    if (row.status === 'suspended') {
      throw AppError.forbidden('Your account has been suspended. Please contact an administrator.', 'ACCOUNT_SUSPENDED');
    }
    if (row.status === 'inactive') {
      throw AppError.forbidden('Your account is not active. Please contact an administrator.', 'ACCOUNT_INACTIVE');
    }

    return issue(row);
  },

  /** Revokes the presented token so it cannot be replayed. */
  async logout(userId: number, jti: string | undefined, expiresAtUnix: number | undefined): Promise<void> {
    if (!jti) return;
    const expiresAt = expiresAtUnix ? new Date(expiresAtUnix * 1000) : new Date(Date.now() + 86_400_000);
    if (!(await tokenRepository.isRevoked(jti))) {
      await tokenRepository.revoke(jti, userId, expiresAt);
    }
    await tokenRepository.pruneExpired();
  },

  async getProfile(userId: number): Promise<UserDto> {
    const row = await userRepository.findById(userId);
    if (!row) throw AppError.notFound('Your account could not be found.');
    return toUserDto(row);
  },

  async updateProfile(userId: number, input: UpdateProfileInput): Promise<UserDto> {
    if (input.phone && (await userRepository.phoneExists(input.phone, userId))) {
      throw AppError.conflict('PHONE_TAKEN', 'Another account already uses this phone number.');
    }
    await userRepository.updateProfile(userId, input);
    return this.getProfile(userId);
  },

  async changePassword(userId: number, input: ChangePasswordInput): Promise<void> {
    const row = await userRepository.findById(userId);
    if (!row) throw AppError.notFound('Your account could not be found.');

    if (!(await verifyPassword(input.currentPassword, row.password_hash))) {
      throw AppError.validation('Your current password is incorrect.', [
        { field: 'currentPassword', message: 'Your current password is incorrect' },
      ]);
    }

    await userRepository.updatePassword(userId, await hashPassword(input.newPassword));
  },
};
