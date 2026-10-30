import crypto from 'node:crypto';

const b64url = (input: string | Buffer) => Buffer.from(input).toString('base64url');

/** Signs an HS256 JWT. `header` lets callers add vendor fields (DoorDash needs `dd-ver`). */
export function signJwt(payload: object, secret: string | Buffer, header: Record<string, unknown> = {}): string {
  const head = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT', ...header }));
  const body = b64url(JSON.stringify(payload));
  const sig = crypto.createHmac('sha256', secret).update(`${head}.${body}`).digest('base64url');
  return `${head}.${body}.${sig}`;
}

export function verifyJwt<T extends object>(token: string, secret: string | Buffer): T | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [head, body, sig] = parts as [string, string, string];
  try {
    const header = JSON.parse(Buffer.from(head, 'base64url').toString('utf8')) as { alg?: string };
    if (header.alg !== 'HS256') return null;
    const expected = crypto.createHmac('sha256', secret).update(`${head}.${body}`).digest();
    const given = Buffer.from(sig, 'base64url');
    if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as T & { exp?: number };
    if (typeof payload.exp === 'number' && Date.now() / 1000 > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}
