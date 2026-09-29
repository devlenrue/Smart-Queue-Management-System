import type { AuthUser } from './domain';

declare global {
  namespace Express {
    interface Request {
      /** Set by requireAuth. Present on every protected route. */
      user?: AuthUser;
      /** The JWT id of the presented token, used by logout. */
      tokenId?: string;
      /** Unix seconds at which the presented token expires. */
      tokenExpiresAt?: number;
    }
  }
}

export {};
