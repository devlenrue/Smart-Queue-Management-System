import bcrypt from 'bcryptjs';
import { config } from '../config/env';

/** Never store or log a plaintext password. */
export function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, config.bcryptRounds);
}

export function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}
