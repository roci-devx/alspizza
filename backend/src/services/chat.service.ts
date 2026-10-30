import { integrations } from '../config.js';
import { prisma } from '../db.js';
import { bus } from '../lib/bus.js';
import { badRequest, notFound } from '../lib/http.js';
import { sendSms } from '../integrations/messaging/twilio.js';
import { publish } from '../realtime/hub.js';
import { serializeMessage } from './serialize.js';

export type Sender = 'customer' | 'driver' | 'store' | 'system';

export async function listMessages(orderId: string) {
  const rows = await prisma.chatMessage.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' }, take: 200 });
  return rows.map(serializeMessage);
}

export async function postMessage(orderId: string, sender: Sender, rawBody: string, via: 'app' | 'sms' = 'app') {
  const body = rawBody.trim().slice(0, 600);
  if (!body) throw badRequest('Message is empty');
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { delivery: true } });
  if (!order) throw notFound('Order not found');

  const msg = await prisma.chatMessage.create({ data: { orderId, sender, body, via } });
  const payload = serializeMessage(msg);
  publish(`order:${orderId}`, 'chat.message', payload);
  publish(`store:${order.storeId}`, 'chat.message', payload);

  if (sender === 'customer') {
    const d = order.delivery;
    if (d?.driverPhone && integrations.twilio && (d.provider === 'doordash' || d.provider === 'uber')) {
      sendSms(d.driverPhone, `Al's Pizza customer (order #${order.number}): ${body}`).catch((err) => console.error('[chat] SMS relay failed', err));
    }
    bus.emit('chat.customer', { orderId, body });
  }
  return payload;
}

bus.on('chat.driver', ({ orderId, body, via }) => {
  postMessage(orderId, 'driver', body, via).catch((err) => console.error('[chat] driver message failed', err));
});
