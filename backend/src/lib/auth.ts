import type { RequestHandler } from 'express';
import { config } from '../config.js';
import { forbidden, unauthorized } from './http.js';
import { signJwt, verifyJwt } from './jwt.js';

export type Role = 'customer' | 'owner';

export interface AuthClaims {
  sub: string;
  role: Role;
  guest?: boolean;
  purpose?: 'session' | 'download';
  rid?: string; // resource id for scoped tokens
  exp: number;
  iat: number;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AuthClaims;
      rawBody?: Buffer;
    }
  }
}

export function issueSessionToken(user: { id: string; role: string; isGuest: boolean }, ttlDays = 90): string {
  const now = Math.floor(Date.now() / 1000);
  return signJwt(
    { sub: user.id, role: user.role as Role, guest: user.isGuest, purpose: 'session', iat: now, exp: now + ttlDays * 86400 },
    config.jwtSecret,
  );
}

/** Short-lived token embedded in download links (Excel reports) so the main session token never lands in a URL. */
export function issueDownloadToken(userId: string, resourceId: string, ttlSeconds = 300): string {
  const now = Math.floor(Date.now() / 1000);
  return signJwt({ sub: userId, role: 'owner', purpose: 'download', rid: resourceId, iat: now, exp: now + ttlSeconds }, config.jwtSecret);
}

export function readToken(token: string | undefined | null): AuthClaims | null {
  if (!token) return null;
  return verifyJwt<AuthClaims>(token, config.jwtSecret);
}

function bearer(header: string | undefined): string | undefined {
  if (!header) return undefined;
  const [scheme, value] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' ? value : undefined;
}

export const optionalAuth: RequestHandler = (req, _res, next) => {
  const claims = readToken(bearer(req.headers.authorization));
  if (claims && claims.purpose !== 'download') req.auth = claims;
  next();
};

export const requireUser: RequestHandler = (req, _res, next) => {
  const claims = readToken(bearer(req.headers.authorization));
  if (!claims || claims.purpose === 'download') return next(unauthorized());
  req.auth = claims;
  next();
};

export const requireOwner: RequestHandler = (req, _res, next) => {
  const claims = readToken(bearer(req.headers.authorization));
  if (!claims || claims.purpose === 'download') return next(unauthorized());
  if (claims.role !== 'owner') return next(forbidden('Owner access only'));
  req.auth = claims;
  next();
};
