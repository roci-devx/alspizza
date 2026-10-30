import type { Prisma } from '@prisma/client';
import { prisma } from '../db.js';
import { badRequest, notFound } from '../lib/http.js';
import { publish } from '../realtime/hub.js';
import { serializeOrder, type OrderFull } from './serialize.js';

export const orderInclude = { items: true, delivery: true, store: true } as const;

export const ACTIVE_ORDER_STATUSES = ['received', 'preparing', 'ready', 'out_for_delivery'];

export function loadOrder(id: string): Promise<OrderFull | null> {
  return prisma.order.findUnique({ where: { id }, include: orderInclude });
}

export async function publishOrder(id: string, extraEvent?: string) {
  const order = await loadOrder(id);
  if (!order) return;
  publish(`order:${id}`, 'order.updated', serializeOrder(order, 'customer'));
  const ownerView = serializeOrder(order, 'owner');
  publish(`store:${order.storeId}`, 'order.updated', ownerView);
  if (extraEvent) publish(`store:${order.storeId}`, extraEvent, ownerView);
}

const TIMESTAMPS: Record<string, keyof Prisma.OrderUpdateInput> = {
  preparing: 'preparingAt',
  ready: 'readyAt',
  out_for_delivery: 'outForDeliveryAt',
  completed: 'completedAt',
  cancelled: 'cancelledAt',
};

const STEPS = ['received', 'preparing', 'ready', 'out_for_delivery', 'completed'];

export async function setStatus(id: string, status: string) {
  const order = await prisma.order.findUnique({ where: { id } });
  if (!order) throw notFound('Order not found');
  if (order.status === status) return;
  if (order.status === 'completed' || order.status === 'cancelled') throw badRequest(`Order is already ${order.status}`);
  if (order.status === 'pending_payment' && status !== 'cancelled') throw badRequest('Order has not been paid yet');
  if (status === 'out_for_delivery' && order.fulfillment !== 'delivery') throw badRequest('Pickup orders are never out for delivery');

  const data: Record<string, unknown> = { status };
  const stamp = TIMESTAMPS[status];
  if (stamp) data[stamp] = new Date();
  // Skipping ahead (e.g. received → ready) still fills earlier milestones for reporting.
  const target = STEPS.indexOf(status);
  for (const step of STEPS.slice(1, Math.max(1, target))) {
    const key = TIMESTAMPS[step];
    if (key && !order[key as keyof typeof order] && !(step === 'out_for_delivery' && order.fulfillment !== 'delivery')) data[key] = new Date();
  }
  await prisma.order.update({ where: { id }, data: data as Prisma.OrderUpdateInput });
  await publishOrder(id);
}
