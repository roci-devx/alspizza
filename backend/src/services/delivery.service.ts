import type { Prisma, Store } from '@prisma/client';
import { config, integrations } from '../config.js';
import { json, prisma } from '../db.js';
import { bus, type DeliveryUpdate } from '../lib/bus.js';
import { driveMinutes, haversineMiles } from '../lib/geo.js';
import { badRequest, notFound } from '../lib/http.js';
import { doordash } from '../integrations/delivery/doordash.js';
import { ownDrivers } from '../integrations/delivery/own.js';
import { runSimulation, simulated } from '../integrations/delivery/simulated.js';
import { ACTIVE_DELIVERY_STATUSES, type DeliveryAddress, type DeliveryProvider, type ProviderName } from '../integrations/delivery/types.js';
import { uber } from '../integrations/delivery/uber.js';
import { publish } from '../realtime/hub.js';
import { publishOrder, setStatus } from './order-core.js';

const providers: Record<ProviderName, DeliveryProvider> = { doordash, uber, own: ownDrivers, simulated };

/**
 * Which courier to use, in order of preference (Settings → Delivery):
 *  auto     → store's own drivers when any are on duty, otherwise DoorDash, then Uber Direct
 *  own      → own drivers only
 *  doordash → DoorDash, Uber as fallback
 *  uber     → Uber, DoorDash as fallback
 * In development a simulated courier stands in for networks without credentials.
 */
export function providerChain(store: Store, opts: { excludeOwn?: boolean } = {}): DeliveryProvider[] {
  const network = (name: 'doordash' | 'uber') => (integrations[name] ? providers[name] : null);
  const sim = config.demo.simulateDelivery ? simulated : null;
  const networks = (first: 'doordash' | 'uber') => [network(first), network(first === 'doordash' ? 'uber' : 'doordash'), sim];
  let chain: (DeliveryProvider | null)[];
  switch (store.deliveryMode) {
    case 'own':
      chain = opts.excludeOwn ? networks('doordash') : [ownDrivers];
      break;
    case 'doordash':
      chain = networks('doordash');
      break;
    case 'uber':
      chain = networks('uber');
      break;
    default:
      chain = store.ownDriversOnDuty > 0 && !opts.excludeOwn ? [ownDrivers, ...networks('doordash')] : networks('doordash');
  }
  const seen = new Set<string>();
  return chain.filter((p): p is DeliveryProvider => !!p && !seen.has(p.name) && !!seen.add(p.name));
}

export async function quoteDelivery(input: {
  store: Store;
  address: DeliveryAddress;
  customerName?: string;
  customerPhone?: string;
  orderValueCents: number;
  readyInMinutes: number;
}) {
  const { store, address } = input;
  const miles = haversineMiles(store, address);
  if (miles > store.deliveryRadiusMiles) {
    throw badRequest(
      `That address is ${miles.toFixed(1)} mi from ${store.name}. We deliver within ${store.deliveryRadiusMiles} mi — pickup is always open!`,
      'out_of_range',
    );
  }
  const chain = providerChain(store);
  if (!chain.length) throw badRequest('Delivery is paused right now. Pickup is open!', 'delivery_unavailable');

  for (const provider of chain) {
    try {
      const externalId = `ALS-Q-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
      const q = await provider.quote({
        externalId,
        store,
        dropoff: address,
        customerName: input.customerName || 'Al’s Customer',
        customerPhone: input.customerPhone || store.phone,
        orderValueCents: Math.max(100, input.orderValueCents),
        readyInMinutes: input.readyInMinutes,
      });
      const customerFeeCents =
        provider.name === 'own' ? store.ownDeliveryFeeCents : store.deliveryFeeMode === 'passthrough' ? q.providerFeeCents : store.flatDeliveryFeeCents;
      // Never promise a drop-off before the food can be ready + driven over.
      const earliest = new Date(Date.now() + (input.readyInMinutes + driveMinutes(miles)) * 60_000);
      const dropoffEta = q.dropoffEta && q.dropoffEta > earliest ? q.dropoffEta : earliest;
      const quote = await prisma.deliveryQuote.create({
        data: {
          storeId: store.id,
          provider: provider.name,
          externalId: q.externalId,
          providerFeeCents: q.providerFeeCents,
          customerFeeCents,
          pickupEta: q.pickupEta ?? null,
          dropoffEta,
          expiresAt: q.expiresAt,
          addressJson: JSON.stringify(address),
        },
      });
      return { quote, miles };
    } catch (err) {
      console.warn(`[delivery] ${provider.name} quote failed`, err);
    }
  }
  throw badRequest("We couldn't find a driver for that address right now. Try pickup, or double-check the address.", 'quote_failed');
}

export async function dispatchDelivery(orderId: string, opts: { excludeOwn?: boolean } = {}) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { items: true, store: true, delivery: true } });
  if (!order || order.fulfillment !== 'delivery' || order.delivery) return;
  const dropoff = json.parse<DeliveryAddress | null>(order.addressJson, null);
  if (!dropoff) return;
  const quote = order.deliveryQuoteId ? await prisma.deliveryQuote.findUnique({ where: { id: order.deliveryQuoteId } }) : null;
  const chain = providerChain(order.store, opts);
  const ordered = quote ? [...chain.filter((p) => p.name === quote.provider), ...chain.filter((p) => p.name !== quote.provider)] : chain;

  for (const provider of ordered) {
    try {
      const relay = integrations.twilio && (provider.name === 'doordash' || provider.name === 'uber');
      const res = await provider.dispatch({
        order,
        store: order.store,
        dropoff,
        quote: quote?.provider === provider.name ? quote : null,
        tipCents: order.tipCents,
        contactPhone: relay ? config.twilio.fromNumber : order.customerPhone,
      });
      await prisma.delivery.create({
        data: {
          orderId,
          provider: provider.name,
          externalId: res.externalId,
          status: res.status ?? 'created',
          providerFeeCents: res.providerFeeCents ?? (quote?.provider === provider.name ? quote.providerFeeCents : 0),
          trackingUrl: res.trackingUrl ?? null,
          driverName: res.driverName ?? null,
          driverPhone: res.driverPhone ?? null,
          driverVehicle: res.driverVehicle ?? null,
          driverLat: res.driverLat ?? null,
          driverLng: res.driverLng ?? null,
          pickupEta: res.pickupEta ?? null,
          dropoffEta: res.dropoffEta ?? quote?.dropoffEta ?? null,
          supportRef: res.supportRef ?? null,
          lastEventJson: res.raw ? JSON.stringify(res.raw).slice(0, 20000) : null,
        },
      });
      const eta = res.dropoffEta ?? quote?.dropoffEta;
      if (eta) await prisma.order.update({ where: { id: orderId }, data: { estimatedDeliveryAt: eta } });
      await publishOrder(orderId);
      return;
    } catch (err) {
      console.error(`[delivery] ${provider.name} dispatch failed for #${order.number}`, err);
    }
  }

  await prisma.delivery.create({
    data: { orderId, provider: 'own', externalId: `UNASSIGNED-${order.number}-${Date.now().toString(36)}`, status: 'pending_driver' },
  });
  publish(`store:${order.storeId}`, 'alert', { orderId, message: `No courier accepted order #${order.number}. Assign one of your drivers.` });
  await publishOrder(orderId);
}

/** Owner action: hand an order that is waiting on an in-house driver to the courier network. */
export async function sendToCourier(orderId: string) {
  const delivery = await prisma.delivery.findUnique({ where: { orderId } });
  if (delivery && delivery.provider !== 'own') throw badRequest('This order already has a courier');
  if (delivery) await prisma.delivery.delete({ where: { id: delivery.id } });
  await dispatchDelivery(orderId, { excludeOwn: true });
}

/** Hands a delivery to one of the store's own drivers — taking it back from DoorDash/Uber if needed. */
export async function assignOwnDriver(orderId: string, driverName: string, driverPhone?: string) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { delivery: true } });
  if (!order) throw notFound('Order not found');
  if (order.fulfillment !== 'delivery') throw badRequest('Pickup orders don’t need a driver');
  const delivery = order.delivery;
  if (delivery && delivery.provider !== 'own' && ACTIVE_DELIVERY_STATUSES.includes(delivery.status)) {
    if (['picked_up', 'enroute_to_dropoff', 'arrived_at_dropoff'].includes(delivery.status)) throw badRequest('The courier already has this order');
    await providers[delivery.provider as ProviderName]?.cancel(delivery.externalId).catch((err) => console.error('[delivery] courier cancel failed', err));
  }
  const data = { provider: 'own', status: 'confirmed', driverName, driverPhone: driverPhone ?? null, driverLat: null, driverLng: null, providerFeeCents: 0 };
  if (delivery) await prisma.delivery.update({ where: { id: delivery.id }, data });
  else await prisma.delivery.create({ data: { ...data, orderId, externalId: `OWN-${order.number}-${Date.now().toString(36)}` } });
  await publishOrder(orderId);
}

/** Keeps in-house delivery status in step with the order status the kitchen sets. */
export async function syncOwnDelivery(orderId: string, orderStatus: string) {
  const delivery = await prisma.delivery.findUnique({ where: { orderId } });
  if (!delivery || delivery.provider !== 'own') return;
  const status = orderStatus === 'out_for_delivery' ? 'enroute_to_dropoff' : orderStatus === 'completed' ? 'delivered' : null;
  if (status) await prisma.delivery.update({ where: { id: delivery.id }, data: { status } });
}

export async function cancelDelivery(orderId: string) {
  const delivery = await prisma.delivery.findUnique({ where: { orderId } });
  if (!delivery || !ACTIVE_DELIVERY_STATUSES.includes(delivery.status)) return;
  try {
    await providers[delivery.provider as ProviderName]?.cancel(delivery.externalId);
  } catch (err) {
    console.error('[delivery] cancel failed', err);
  }
  await prisma.delivery.update({ where: { id: delivery.id }, data: { status: 'cancelled' } });
}

const RANK = ['quote', 'created', 'pending_driver', 'confirmed', 'enroute_to_pickup', 'arrived_at_pickup', 'picked_up', 'enroute_to_dropoff', 'arrived_at_dropoff', 'delivered'];
const FIELDS = ['providerFeeCents', 'trackingUrl', 'driverName', 'driverPhone', 'driverVehicle', 'driverLat', 'driverLng', 'pickupEta', 'dropoffEta', 'supportRef'] as const;

export async function applyDeliveryUpdate(u: DeliveryUpdate) {
  const d = await prisma.delivery.findUnique({ where: { externalId: u.externalId }, include: { order: true } });
  if (!d) return;
  const data: Record<string, unknown> = {};
  let newStatus: string | null = null;
  if (u.status && u.status !== d.status) {
    const terminal = ['delivered', 'cancelled', 'returned'].includes(d.status);
    const from = RANK.indexOf(d.status);
    const to = RANK.indexOf(u.status);
    if (!terminal && !(from !== -1 && to !== -1 && to < from)) newStatus = data.status = u.status;
  }
  for (const key of FIELDS) if (u[key] != null) data[key] = u[key];
  if (u.raw) data.lastEventJson = JSON.stringify(u.raw).slice(0, 20000);
  if (!Object.keys(data).length) return;
  await prisma.delivery.update({ where: { id: d.id }, data: data as Prisma.DeliveryUpdateInput });
  if (u.dropoffEta) await prisma.order.update({ where: { id: d.orderId }, data: { estimatedDeliveryAt: u.dropoffEta } });

  const order = d.order;
  if (newStatus) {
    try {
      if (['picked_up', 'enroute_to_dropoff', 'arrived_at_dropoff'].includes(newStatus) && ['received', 'preparing', 'ready'].includes(order.status)) {
        await setStatus(order.id, 'out_for_delivery');
      } else if (newStatus === 'delivered' && !['completed', 'cancelled'].includes(order.status)) {
        await setStatus(order.id, 'completed');
      } else {
        await publishOrder(order.id);
      }
    } catch (err) {
      console.warn('[delivery] order status sync skipped', err);
      await publishOrder(order.id);
    }
    if ((newStatus === 'cancelled' || newStatus === 'returned') && order.status !== 'cancelled') {
      publish(`store:${order.storeId}`, 'alert', { orderId: order.id, message: `Courier ${newStatus} order #${order.number}. Re-dispatch or assign a driver.` });
    }
  } else if (u.driverLat != null && u.driverLng != null) {
    const payload = { orderId: order.id, status: d.status, driverLat: u.driverLat, driverLng: u.driverLng };
    publish(`order:${order.id}`, 'driver.location', payload);
    publish(`store:${order.storeId}`, 'driver.location', payload);
  } else {
    await publishOrder(order.id);
  }
}

bus.on('delivery.update', (u) => {
  applyDeliveryUpdate(u).catch((err) => console.error('[delivery] update failed', err));
});

/** DoorDash sends webhooks on status changes; GPS between them comes from polling. */
export function startDeliveryWorkers() {
  if (integrations.doordash) {
    setInterval(async () => {
      const active = await prisma.delivery.findMany({ where: { provider: 'doordash', status: { in: ACTIVE_DELIVERY_STATUSES } }, take: 50 });
      for (const d of active) {
        try {
          const update = await doordash.fetch!(d.externalId);
          if (update) await applyDeliveryUpdate({ ...update, raw: undefined });
        } catch (err) {
          console.warn('[doordash] poll failed', d.externalId, err);
        }
      }
    }, config.doordash.pollSeconds * 1000);
  }

  // Resume simulated couriers that were mid-route when the server restarted.
  void (async () => {
    const pending = await prisma.delivery.findMany({ where: { provider: 'simulated', status: { in: ACTIVE_DELIVERY_STATUSES } }, include: { order: { include: { store: true } } } });
    for (const d of pending) {
      const dropoff = json.parse<DeliveryAddress | null>(d.order.addressJson, null);
      if (!dropoff || ['completed', 'cancelled'].includes(d.order.status)) continue;
      void runSimulation(d.externalId, d.orderId, d.order.store, dropoff, d.status);
    }
  })();
}
