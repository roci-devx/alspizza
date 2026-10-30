import type { Server } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { prisma } from '../db.js';
import { readToken, type AuthClaims } from '../lib/auth.js';

/**
 * Tiny pub/sub over WebSockets.
 *   client → {"type":"subscribe","channel":"order:<id>"}   (customer who owns the order, or owner)
 *   client → {"type":"subscribe","channel":"store:<id>"}   (owner dashboard)
 *   server → {"channel":"order:<id>","event":"order.updated","data":{…}}
 */

interface Client extends WebSocket {
  claims?: AuthClaims | null;
  alive?: boolean;
  channels?: Set<string>;
}

const channels = new Map<string, Set<Client>>();

async function canJoin(claims: AuthClaims | null | undefined, channel: string): Promise<boolean> {
  if (!claims) return false;
  const [kind, id] = channel.split(':');
  if (!id) return false;
  if (claims.role === 'owner') return kind === 'order' || kind === 'store';
  if (kind !== 'order') return false;
  const order = await prisma.order.findUnique({ where: { id }, select: { userId: true } });
  return order?.userId === claims.sub;
}

function join(ws: Client, channel: string) {
  let set = channels.get(channel);
  if (!set) channels.set(channel, (set = new Set()));
  set.add(ws);
  ws.channels!.add(channel);
}

function leave(ws: Client, channel: string) {
  channels.get(channel)?.delete(ws);
  if (channels.get(channel)?.size === 0) channels.delete(channel);
  ws.channels?.delete(channel);
}

export function attachRealtime(server: Server) {
  const wss = new WebSocketServer({ server, path: '/ws' });

  wss.on('connection', (socket, req) => {
    const ws = socket as Client;
    const url = new URL(req.url ?? '/ws', 'http://localhost');
    ws.claims = readToken(url.searchParams.get('token'));
    ws.alive = true;
    ws.channels = new Set();
    ws.on('pong', () => (ws.alive = true));

    ws.on('message', async (raw) => {
      let msg: { type?: string; channel?: string; token?: string };
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (msg.type === 'auth' && msg.token) ws.claims = readToken(msg.token);
      if (msg.type === 'ping') ws.send(JSON.stringify({ event: 'pong' }));
      if (msg.type === 'subscribe' && msg.channel) {
        if (await canJoin(ws.claims, msg.channel)) {
          join(ws, msg.channel);
          ws.send(JSON.stringify({ event: 'subscribed', channel: msg.channel }));
        } else {
          ws.send(JSON.stringify({ event: 'error', channel: msg.channel, data: { error: 'Not allowed' } }));
        }
      }
      if (msg.type === 'unsubscribe' && msg.channel) leave(ws, msg.channel);
    });

    ws.on('close', () => {
      for (const c of [...(ws.channels ?? [])]) leave(ws, c);
    });
  });

  const heartbeat = setInterval(() => {
    for (const socket of wss.clients) {
      const ws = socket as Client;
      if (!ws.alive) {
        ws.terminate();
        continue;
      }
      ws.alive = false;
      ws.ping();
    }
  }, 30_000);
  wss.on('close', () => clearInterval(heartbeat));
  return wss;
}

export function publish(channel: string, event: string, data: unknown) {
  const set = channels.get(channel);
  if (!set?.size) return;
  const payload = JSON.stringify({ channel, event, data });
  for (const ws of set) if (ws.readyState === WebSocket.OPEN) ws.send(payload);
}
