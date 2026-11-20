import type { Delivery, DriverProfile, Order, OrderItem, Shift, Store, User } from '@prisma/client';
import { config, integrations } from '../config.js';
import { json, prisma } from '../db.js';
import { HttpError, badRequest, forbidden, notFound } from '../lib/http.js';
import type { DeliveryAddress } from '../integrations/delivery/types.js';
import { publish } from '../realtime/hub.js';
import { cancelCourier, sendToCourier } from './delivery.service.js';
import { publishOrder, setStatus } from './order-core.js';

/**
 * The store's own drivers (Al's Driver app).
 *
 *  - While anyone is on the clock, delivery orders go to own drivers.
 *  - Each driver has a queue ("backlog", default max 6) and a run (orders on the road, default max 4).
 *  - Strictly first in, first out: orders are assigned oldest first and leave the store oldest first.
 *  - A new order goes to the driver with the shortest queue, then the fewest orders on the road,
 *    then whoever has been waiting at the store longest.
 *  - Nobody has room: the order waits for the next free driver. Once its food is ready it goes to
 *    DoorDash/Uber instead, if the owner allows overflow (never cash orders — couriers can't collect cash).
 *  - Cash-on-delivery orders only go to drivers who opted in. Cash they collect is settled with the owner;
 *    until then they can't start their next shift.
 *
 * Own-driver delivery statuses: pending_driver (no driver yet) → confirmed (in a driver's queue)
 * → enroute_to_dropoff (on the road) → delivered.
 */

export const ON_THE_ROAD = ['enroute_to_dropoff', 'arrived_at_dropoff'];
const KITCHEN_STATUSES = ['received', 'preparing', 'ready'];

type DeliveryWithOrder = Delivery & { order: Order };

export interface DriverLoad {
  user: User;
  profile: DriverProfile;
  shift: Shift;
  run: DeliveryWithOrder[];
  backlog: DeliveryWithOrder[];
}

const orderTime = (o: Order) => (o.paidAt ?? o.createdAt).getTime();
const fifo = (a: DeliveryWithOrder, b: DeliveryWithOrder) => orderTime(a.order) - orderTime(b.order);
const money = (cents: number) => `$${(cents / 100).toFixed(2)}`;

export function openShift(driverId: string) {
  return prisma.shift.findFirst({ where: { driverId, endedAt: null }, orderBy: { startedAt: 'desc' } });
}

/** Everyone on the clock at a store, with what they're carrying and what's queued for them (oldest first). */
export async function driverLoads(storeId: string): Promise<DriverLoad[]> {
  const shifts = await prisma.shift.findMany({
    where: { storeId, endedAt: null, driver: { isActive: true, role: 'driver' } },
    include: { driver: { include: { driver: true } } },
    orderBy: { startedAt: 'asc' },
  });
  const ids = shifts.map((s) => s.driverId);
  const deliveries = ids.length
    ? await prisma.delivery.findMany({
        where: { driverId: { in: ids }, provider: 'own', status: { in: ['confirmed', ...ON_THE_ROAD] } },
        include: { order: true },
      })
    : [];
  return shifts
    .filter((s) => s.driver.driver)
    .map((s) => {
      const mine = deliveries.filter((d) => d.driverId === s.driverId).sort(fifo);
      return {
        user: s.driver,
        profile: s.driver.driver!,
        shift: s,
        run: mine.filter((d) => ON_THE_ROAD.includes(d.status)),
        backlog: mine.filter((d) => d.status === 'confirmed'),
      };
    });
}

export function driversOnShiftCount(storeId: string) {
  return prisma.shift.count({ where: { storeId, endedAt: null, driver: { isActive: true, role: 'driver' } } });
}

/** Checkout offers cash on delivery only while a cash-enabled driver on the clock has room in their queue. */
export async function cashOnDeliveryAvailable(store: Store) {
  if (!store.cashOnDelivery || !store.deliveryEnabled) return false;
  return (await driverLoads(store.id)).some((x) => x.profile.cashEnabled && x.backlog.length < x.profile.maxBacklog);
}

// ── Dispatch ──────────────────────────────────────────────────────────────────

const locks = new Map<string, Promise<void>>();
const alerted = new Set<string>();

/** Assigns waiting orders to drivers. Runs one at a time per store so two orders never race for a slot. */
export function runDispatch(storeId: string): Promise<void> {
  const next = (locks.get(storeId) ?? Promise.resolve()).then(() => dispatchOnce(storeId)).catch((err) => console.error('[drivers] dispatch failed', err));
  locks.set(storeId, next);
  return next;
}

async function dispatchOnce(storeId: string) {
  const waiting = await prisma.delivery.findMany({
    where: { provider: 'own', driverId: null, status: 'pending_driver', order: { storeId, status: { in: KITCHEN_STATUSES } } },
    include: { order: true },
  });
  if (!waiting.length) return;
  waiting.sort(fifo);
  const drivers = await driverLoads(storeId);
  const leftovers: DeliveryWithOrder[] = [];

  for (const d of waiting) {
    const eligible = drivers.filter((x) => x.backlog.length < x.profile.maxBacklog && (d.cashDueCents === 0 || x.profile.cashEnabled));
    if (!eligible.length) {
      leftovers.push(d);
      continue;
    }
    eligible.sort(
      (a, b) =>
        a.backlog.length - b.backlog.length ||
        a.run.length - b.run.length ||
        (a.profile.availableSince?.getTime() ?? Number.MAX_SAFE_INTEGER) - (b.profile.availableSince?.getTime() ?? Number.MAX_SAFE_INTEGER),
    );
    const pick = eligible[0]!;
    await assign(d, pick);
    pick.backlog.push(d);
  }

  if (!leftovers.length || !drivers.length) return; // nobody on the clock: manual assignment from the board, as before
  const store = await prisma.store.findUnique({ where: { id: storeId } });
  const couriers = integrations.doordash || integrations.uber || config.demo.simulateDelivery;
  for (const d of leftovers) {
    if (d.cashDueCents === 0 && store?.overflowToCouriers && couriers && d.order.status === 'ready') {
      alerted.delete(d.id);
      await sendToCourier(d.orderId).catch((err) => console.error('[drivers] overflow to courier failed', err));
      publish(`store:${storeId}`, 'alert', { orderId: d.orderId, message: `All drivers are full — order #${d.order.number} went to a courier.` });
    } else if (!alerted.has(d.id)) {
      alerted.add(d.id);
      const why = d.cashDueCents > 0 ? 'no driver who takes cash has room' : 'every driver’s queue is full';
      publish(`store:${storeId}`, 'alert', { orderId: d.orderId, message: `Order #${d.order.number} is waiting for a driver — ${why}.` });
    }
  }
}

async function assign(d: DeliveryWithOrder, x: DriverLoad) {
  alerted.delete(d.id);
  await prisma.delivery.update({
    where: { id: d.id },
    data: {
      driverId: x.user.id,
      shiftId: x.shift.id,
      status: 'confirmed',
      assignedAt: new Date(),
      driverName: x.user.name ?? 'Your driver',
      driverPhone: x.user.phone,
      driverVehicle: x.profile.vehicle,
      problem: null,
    },
  });
  publish(`driver:${x.user.id}`, 'driver.assigned', { orderId: d.orderId, number: d.order.number });
  publishDriverQueue(x.user.id);
  await publishOrder(d.orderId);
}

/** Driver apps refetch their state on this; the owner's live view refreshes its driver list. */
export function publishDriverQueue(driverId: string, storeId?: string) {
  publish(`driver:${driverId}`, 'driver.queue', { at: Date.now() });
  if (storeId) publish(`store:${storeId}`, 'drivers.updated', { driverId });
}

async function changed(storeId: string, driverId: string) {
  publishDriverQueue(driverId, storeId);
  await runDispatch(storeId);
}

/** Safety net: picks up anything a missed event left waiting (also covers server restarts). */
export function startDriverDispatchSweep() {
  setInterval(async () => {
    try {
      const stores = await prisma.delivery.findMany({
        where: { provider: 'own', driverId: null, status: 'pending_driver' },
        select: { order: { select: { storeId: true } } },
        distinct: ['orderId'],
      });
      for (const storeId of new Set(stores.map((s) => s.order.storeId))) await runDispatch(storeId);
    } catch (err) {
      console.error('[drivers] sweep failed', err);
    }
  }, 30_000);
}

// ── Shifts & cash ─────────────────────────────────────────────────────────────

export async function unsettledCash(driverId: string) {
  const shifts = await prisma.shift.findMany({ where: { driverId, endedAt: { not: null }, settledAt: null, cashCollectedCents: { gt: 0 } }, orderBy: { startedAt: 'asc' } });
  return { cents: shifts.reduce((sum, s) => sum + s.cashCollectedCents, 0), shifts };
}

async function activeDriver(driverId: string) {
  const user = await prisma.user.findUnique({ where: { id: driverId }, include: { driver: true } });
  if (!user || user.role !== 'driver' || !user.isActive) throw forbidden('This driver account is switched off — talk to the owner');
  if (!user.storeId) throw badRequest('The owner hasn’t picked your store yet');
  return user as typeof user & { storeId: string };
}

export async function startShift(driverId: string) {
  const user = await activeDriver(driverId);
  const open = await openShift(driverId);
  if (open) return open;
  const owed = await unsettledCash(driverId);
  if (owed.cents > 0) {
    throw new HttpError(409, `Hand in ${money(owed.cents)} cash from your last shift to the owner before you start`, 'cash_unsettled');
  }
  const shift = await prisma.shift.create({ data: { driverId, storeId: user.storeId } });
  const store = await prisma.store.findUniqueOrThrow({ where: { id: user.storeId } });
  await prisma.driverProfile.upsert({
    where: { userId: driverId },
    create: { userId: driverId, maxActive: store.driverMaxActive, maxBacklog: store.driverMaxBacklog, availableSince: new Date() },
    update: { availableSince: new Date() },
  });
  await changed(user.storeId, driverId);
  return shift;
}

/** Ends a shift. Queued orders go back to the store for another driver; `force` (owner) also works mid-run. */
export async function endShift(driverId: string, opts: { force?: boolean } = {}) {
  const shift = await openShift(driverId);
  if (!shift) return null;
  const out = await prisma.delivery.count({ where: { driverId, provider: 'own', status: { in: ON_THE_ROAD } } });
  if (out && !opts.force) throw badRequest(`Deliver the ${out === 1 ? 'order' : `${out} orders`} you’re carrying before you clock out`);
  const queued = await prisma.delivery.findMany({ where: { driverId, provider: 'own', status: 'confirmed' }, select: { orderId: true } });
  await prisma.delivery.updateMany({
    where: { driverId, provider: 'own', status: 'confirmed' },
    data: { driverId: null, shiftId: null, status: 'pending_driver', assignedAt: null, driverName: null, driverPhone: null, driverVehicle: null },
  });
  const ended = await prisma.shift.update({ where: { id: shift.id }, data: { endedAt: new Date() } });
  await prisma.driverProfile.updateMany({ where: { userId: driverId }, data: { availableSince: null } });
  for (const q of queued) await publishOrder(q.orderId);
  await changed(shift.storeId, driverId);
  return ended;
}

export async function settleShift(shiftId: string, ownerId: string, receivedCents: number, note?: string | null) {
  const shift = await prisma.shift.findUnique({ where: { id: shiftId } });
  if (!shift) throw notFound('Shift not found');
  if (!shift.endedAt) throw badRequest('End the shift before settling its cash');
  if (shift.settledAt) return shift;
  const settled = await prisma.shift.update({
    where: { id: shiftId },
    data: { cashSettledCents: receivedCents, settledAt: new Date(), settledBy: ownerId, note: note?.trim() || null },
  });
  publishDriverQueue(shift.driverId, shift.storeId);
  return settled;
}

// ── Driver actions ────────────────────────────────────────────────────────────

/** Takes the oldest ready orders from the queue, up to the driver's run limit. FIFO: stops at the first one that isn't ready. */
export async function pickUp(driverId: string, count?: number) {
  const user = await activeDriver(driverId);
  const me = (await driverLoads(user.storeId)).find((x) => x.user.id === driverId);
  if (!me) throw badRequest('Start your shift first');
  const room = me.profile.maxActive - me.run.length;
  if (room <= 0) throw badRequest(`You’re already carrying ${me.run.length} orders — deliver those first`);
  const ready: DeliveryWithOrder[] = [];
  for (const d of me.backlog) {
    if (d.order.status !== 'ready') break;
    ready.push(d);
  }
  const take = ready.slice(0, Math.max(1, Math.min(room, count ?? room)));
  if (!take.length) {
    const next = me.backlog[0];
    throw badRequest(next ? `Order #${next.order.number} isn’t ready yet — orders leave oldest first` : 'Nothing in your queue yet');
  }
  for (const d of take) {
    await prisma.delivery.update({ where: { id: d.id }, data: { status: 'enroute_to_dropoff', pickedUpAt: new Date() } });
    await setStatus(d.orderId, 'out_for_delivery');
  }
  await prisma.driverProfile.update({ where: { userId: driverId }, data: { availableSince: null } });
  await changed(user.storeId, driverId);
  return take.length;
}

export async function markDelivered(driverId: string, deliveryId: string, cashCollected: boolean) {
  const d = await prisma.delivery.findUnique({ where: { id: deliveryId }, include: { order: true } });
  if (!d || d.driverId !== driverId) throw notFound('That delivery isn’t yours');
  if (!ON_THE_ROAD.includes(d.status)) throw badRequest('Pick this order up first');
  if (d.cashDueCents > 0 && !cashCollected) throw badRequest(`Collect ${money(d.cashDueCents)} cash before marking it delivered`, 'cash_required');
  await prisma.delivery.update({ where: { id: d.id }, data: { status: 'delivered', deliveredAt: new Date(), problem: null } });
  if (d.cashDueCents > 0) {
    if (d.shiftId) await prisma.shift.update({ where: { id: d.shiftId }, data: { cashCollectedCents: { increment: d.cashDueCents } } });
    await prisma.order.update({ where: { id: d.orderId }, data: { paymentStatus: 'paid', paymentMethod: 'Cash on delivery' } });
  }
  await setStatus(d.orderId, 'completed');
  const stillOut = await prisma.delivery.count({ where: { driverId, provider: 'own', status: { in: ON_THE_ROAD } } });
  if (!stillOut) await prisma.driverProfile.updateMany({ where: { userId: driverId }, data: { availableSince: new Date() } });
  await changed(d.order.storeId, driverId);
}

export async function reportProblem(driverId: string, deliveryId: string, reason: string) {
  const d = await prisma.delivery.findUnique({ where: { id: deliveryId }, include: { order: true, driver: true } });
  if (!d || d.driverId !== driverId) throw notFound('That delivery isn’t yours');
  await prisma.delivery.update({ where: { id: d.id }, data: { problem: reason } });
  publish(`store:${d.order.storeId}`, 'alert', {
    orderId: d.orderId,
    message: `${d.driver?.name ?? 'A driver'} can’t deliver order #${d.order.number}: ${reason}. Call the customer, reassign or cancel it.`,
  });
  await publishOrder(d.orderId);
  publishDriverQueue(driverId, d.order.storeId);
}

export async function updateLocation(driverId: string, lat: number, lng: number) {
  await prisma.driverProfile.updateMany({ where: { userId: driverId }, data: { lastLat: lat, lastLng: lng, lastSeenAt: new Date() } });
  const out = await prisma.delivery.findMany({
    where: { driverId, provider: 'own', status: { in: ON_THE_ROAD } },
    select: { id: true, orderId: true, status: true, order: { select: { storeId: true } } },
  });
  if (!out.length) return;
  await prisma.delivery.updateMany({ where: { id: { in: out.map((d) => d.id) } }, data: { driverLat: lat, driverLng: lng } });
  for (const d of out) {
    const payload = { orderId: d.orderId, status: d.status, driverLat: lat, driverLng: lng };
    publish(`order:${d.orderId}`, 'driver.location', payload);
    publish(`store:${d.order.storeId}`, 'driver.location', payload);
  }
}

// ── Owner actions ─────────────────────────────────────────────────────────────

/** Owner override: puts an order in a specific driver's queue (ignores the queue limit, not the cash opt-in). */
export async function assignToDriver(orderId: string, driverId: string) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { delivery: true } });
  if (!order) throw notFound('Order not found');
  if (order.fulfillment !== 'delivery') throw badRequest('Pickup orders don’t need a driver');
  const load = (await driverLoads(order.storeId)).find((x) => x.user.id === driverId);
  if (!load) throw badRequest('That driver isn’t on the clock');
  const d = order.delivery;
  if (d && ON_THE_ROAD.includes(d.status) && d.provider === 'own') throw badRequest('This order is already on the road');
  if (d && d.provider !== 'own') await cancelCourier(d); // taking it back from DoorDash/Uber
  const cashDueCents = order.paymentStatus === 'pay_on_delivery' ? order.totalCents : 0;
  if (cashDueCents > 0 && !load.profile.cashEnabled) throw badRequest(`${load.user.name ?? 'That driver'} doesn’t take cash orders`);
  const previous = d?.provider === 'own' ? d.driverId : null;
  const data = {
    provider: 'own',
    status: 'confirmed',
    driverId,
    shiftId: load.shift.id,
    assignedAt: new Date(),
    driverName: load.user.name ?? 'Your driver',
    driverPhone: load.user.phone,
    driverVehicle: load.profile.vehicle,
    driverLat: null,
    driverLng: null,
    providerFeeCents: 0,
    cashDueCents,
    problem: null,
  };
  if (d) await prisma.delivery.update({ where: { id: d.id }, data });
  else await prisma.delivery.create({ data: { ...data, orderId, externalId: `OWN-${order.number}-${Date.now().toString(36)}` } });
  publish(`driver:${driverId}`, 'driver.assigned', { orderId, number: order.number });
  if (previous && previous !== driverId) publishDriverQueue(previous);
  await publishOrder(orderId);
  await changed(order.storeId, driverId);
}

// ── What the driver app sees ──────────────────────────────────────────────────

type DriverDelivery = Delivery & { order: Order & { items: OrderItem[] } };

export function serializeDriverDelivery(d: DriverDelivery) {
  const address = json.parse<DeliveryAddress | null>(d.order.addressJson, null);
  return {
    id: d.id,
    orderId: d.orderId,
    number: d.order.number,
    status: d.status,
    orderStatus: d.order.status,
    ready: d.order.status === 'ready',
    onTheRoad: ON_THE_ROAD.includes(d.status),
    customerName: d.order.customerName,
    customerPhone: d.order.customerPhone,
    address,
    notes: d.order.notes,
    items: d.order.items.map((i) => ({ name: i.name, quantity: i.quantity, summary: i.summary })),
    itemsCount: d.order.itemsCount,
    totalCents: d.order.totalCents,
    tipCents: d.order.tipCents,
    cashDueCents: d.cashDueCents,
    paidAt: d.order.paidAt,
    estimatedReadyAt: d.order.estimatedReadyAt,
    assignedAt: d.assignedAt,
    pickedUpAt: d.pickedUpAt,
    problem: d.problem,
  };
}

export async function driverState(driverId: string) {
  const user = await prisma.user.findUnique({ where: { id: driverId }, include: { driver: true } });
  if (!user || user.role !== 'driver') throw forbidden('Driver accounts only');
  const store = user.storeId ? await prisma.store.findUnique({ where: { id: user.storeId } }) : null;
  const shift = await openShift(driverId);
  const owed = await unsettledCash(driverId);
  const mine = await prisma.delivery.findMany({
    where: { driverId, provider: 'own', status: { in: ['confirmed', ...ON_THE_ROAD] } },
    include: { order: { include: { items: true } } },
  });
  mine.sort(fifo);
  const waitingAtStore = store
    ? await prisma.delivery.count({ where: { provider: 'own', driverId: null, status: 'pending_driver', order: { storeId: store.id, status: { in: KITCHEN_STATUSES } } } })
    : 0;
  return {
    user: { id: user.id, name: user.name, phone: user.phone, email: user.email, isActive: user.isActive },
    store: store ? { id: store.id, name: store.name, phone: store.phone, address: `${store.line1}, ${store.city}, ${store.state} ${store.zip}`, lat: store.lat, lng: store.lng } : null,
    profile: {
      maxActive: user.driver?.maxActive ?? store?.driverMaxActive ?? 4,
      maxBacklog: user.driver?.maxBacklog ?? store?.driverMaxBacklog ?? 6,
      cashEnabled: user.driver?.cashEnabled ?? false,
      vehicle: user.driver?.vehicle ?? null,
    },
    shift: shift ? { id: shift.id, startedAt: shift.startedAt, cashCollectedCents: shift.cashCollectedCents } : null,
    cashOwedCents: owed.cents,
    run: mine.filter((d) => ON_THE_ROAD.includes(d.status)).map(serializeDriverDelivery),
    queue: mine.filter((d) => d.status === 'confirmed').map(serializeDriverDelivery),
    waitingAtStore,
  };
}

/** Owner's live view: who's on the clock, how full they are, and cash waiting to be settled. */
export async function teamOverview(storeIds: string[]) {
  const loads = (await Promise.all(storeIds.map((id) => driverLoads(id)))).flat();
  const unsettled = await prisma.shift.findMany({
    where: { storeId: { in: storeIds }, endedAt: { not: null }, settledAt: null, cashCollectedCents: { gt: 0 } },
    include: { driver: { select: { id: true, name: true } } },
    orderBy: { endedAt: 'asc' },
  });
  return {
    onShift: loads.map((x) => ({
      driverId: x.user.id,
      name: x.user.name,
      phone: x.user.phone,
      storeId: x.shift.storeId,
      shiftId: x.shift.id,
      startedAt: x.shift.startedAt,
      cashCollectedCents: x.shift.cashCollectedCents,
      cashEnabled: x.profile.cashEnabled,
      maxActive: x.profile.maxActive,
      maxBacklog: x.profile.maxBacklog,
      lastLat: x.profile.lastLat,
      lastLng: x.profile.lastLng,
      lastSeenAt: x.profile.lastSeenAt,
      atStore: x.run.length === 0,
      run: x.run.map((d) => ({ orderId: d.orderId, number: d.order.number })),
      queue: x.backlog.map((d) => ({ orderId: d.orderId, number: d.order.number, ready: d.order.status === 'ready' })),
    })),
    unsettled: unsettled.map((s) => ({
      shiftId: s.id,
      driverId: s.driverId,
      name: s.driver.name,
      storeId: s.storeId,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      cashCollectedCents: s.cashCollectedCents,
    })),
  };
}
