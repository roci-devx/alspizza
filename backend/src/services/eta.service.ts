import type { Store } from '@prisma/client';
import { prisma } from '../db.js';

/**
 * Pickup ETA = slowest item's prep time (owner-set per food type, overridable per item)
 * plus a queue penalty for every order already in the kitchen.
 * Later this can be replaced with a model trained on actual ready times (order.readyAt - order.paidAt).
 */
export async function pickupEtaMinutes(store: Pick<Store, 'id' | 'queueMinutesPerOrder'>, prepMinutes: number[]): Promise<number> {
  let base = prepMinutes.length ? Math.max(...prepMinutes) : 0;
  if (!base) {
    const pizza = await prisma.category.findUnique({ where: { slug: 'pizza' } });
    base = pizza?.prepMinutes ?? 15;
  }
  const inKitchen = await prisma.order.count({ where: { storeId: store.id, status: { in: ['received', 'preparing'] } } });
  const queue = Math.min(30, inKitchen * store.queueMinutesPerOrder);
  return Math.max(5, Math.round(base + queue));
}

export const minutesFromNow = (minutes: number) => new Date(Date.now() + minutes * 60_000);
