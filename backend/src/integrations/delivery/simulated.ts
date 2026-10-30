import { config } from '../../config.js';
import { prisma } from '../../db.js';
import { bus } from '../../lib/bus.js';
import { driveMinutes, haversineMiles, lerp, type LatLng } from '../../lib/geo.js';
import type { DeliveryProvider, DispatchInput, QuoteInput, QuoteOutput } from './types.js';

/**
 * Local stand-in for DoorDash/Uber so the full tracking experience (courier
 * assignment, live GPS, chat) works without credentials. Timeline is compressed;
 * tune with DELIVERY_SIM_SPEED.
 */

const DRIVERS = [
  { name: 'Marcus T.', vehicle: 'Silver Honda Civic' },
  { name: 'Priya K.', vehicle: 'Blue Toyota Prius' },
  { name: 'Diego R.', vehicle: 'Red Vespa scooter' },
  { name: 'Hannah L.', vehicle: 'White Kia Soul' },
  { name: 'Jamal W.', vehicle: 'Black Ford Fusion' },
];

const REPLIES: [RegExp, string][] = [
  [/door|leave|porch|front/i, "Got it — I'll leave it right at the door and snap a photo."],
  [/call|phone/i, "Sure thing, I'll give you a ring when I'm outside."],
  [/gate|code|buzz|apartment|apt|unit/i, 'Thanks! What’s the gate or buzzer code?'],
  [/coming|down|outside|meet/i, 'Perfect, see you in a minute!'],
  [/how long|eta|where/i, "I'm on my way — the map in the app is live, so you can watch me roll in."],
  [/thank/i, 'Anytime! Enjoy your pizza 🍕'],
];

const runs = new Map<string, { cancelled: boolean }>();
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms / config.demo.simSpeed));

function offset(from: LatLng, miles: number, bearingDeg: number): LatLng {
  const rad = (bearingDeg * Math.PI) / 180;
  return {
    lat: from.lat + (miles / 69) * Math.cos(rad),
    lng: from.lng + (miles / (69 * Math.cos((from.lat * Math.PI) / 180))) * Math.sin(rad),
  };
}

async function drive(externalId: string, from: LatLng, to: LatLng, seconds: number, status: string, run: { cancelled: boolean }) {
  const steps = Math.max(4, Math.round(seconds / 2));
  for (let i = 1; i <= steps && !run.cancelled; i++) {
    // Ease in/out so the marker accelerates away and slows on arrival like a real car.
    const t = i / steps;
    const eased = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
    const wobble = Math.sin(t * Math.PI) * 0.0012;
    const p = lerp(from, to, eased);
    bus.emit('delivery.update', { externalId, status, driverLat: p.lat + wobble, driverLng: p.lng - wobble });
    await sleep(2000);
  }
}

async function waitForKitchen(orderId: string, run: { cancelled: boolean }) {
  for (let i = 0; i < 180 && !run.cancelled; i++) {
    const order = await prisma.order.findUnique({ where: { id: orderId }, select: { status: true } });
    if (!order || ['ready', 'out_for_delivery', 'completed'].includes(order.status)) return;
    if (order.status === 'cancelled') {
      run.cancelled = true;
      return;
    }
    await sleep(2000);
  }
}

export async function runSimulation(externalId: string, orderId: string, store: LatLng, dropoff: LatLng, fromStatus = 'created') {
  if (runs.has(externalId)) return;
  const run = { cancelled: false };
  runs.set(externalId, run);
  const driver = DRIVERS[Math.floor(Math.random() * DRIVERS.length)]!;
  const start = offset(store, 0.7, Math.random() * 360);
  const miles = haversineMiles(store, dropoff);
  const order = ['created', 'confirmed', 'enroute_to_pickup', 'arrived_at_pickup', 'picked_up', 'enroute_to_dropoff', 'arrived_at_dropoff'];
  const at = (s: string) => order.indexOf(fromStatus) <= order.indexOf(s);

  try {
    if (at('confirmed')) {
      await sleep(4000);
      bus.emit('delivery.update', {
        externalId,
        status: 'confirmed',
        driverName: driver.name,
        driverVehicle: driver.vehicle,
        driverPhone: '+13125550199',
        driverLat: start.lat,
        driverLng: start.lng,
      });
      await sleep(3000);
    }
    if (at('enroute_to_pickup') && !run.cancelled) await drive(externalId, start, store, 18, 'enroute_to_pickup', run);
    if (at('arrived_at_pickup') && !run.cancelled) {
      bus.emit('delivery.update', { externalId, status: 'arrived_at_pickup', driverLat: store.lat, driverLng: store.lng });
      await waitForKitchen(orderId, run);
    }
    if (at('picked_up') && !run.cancelled) {
      await sleep(3000);
      bus.emit('delivery.update', {
        externalId,
        status: 'picked_up',
        dropoffEta: new Date(Date.now() + driveMinutes(miles) * 60_000),
      });
      await sleep(2000);
    }
    if (at('enroute_to_dropoff') && !run.cancelled) {
      await drive(externalId, store, dropoff, Math.min(70, 24 + miles * 10), 'enroute_to_dropoff', run);
    }
    if (!run.cancelled) {
      bus.emit('delivery.update', { externalId, status: 'arrived_at_dropoff', driverLat: dropoff.lat, driverLng: dropoff.lng });
      await sleep(7000);
    }
    if (!run.cancelled) bus.emit('delivery.update', { externalId, status: 'delivered' });
  } finally {
    runs.delete(externalId);
  }
}

/** Canned courier replies so the chat feels alive in demo mode. */
bus.on('chat.customer', async ({ orderId, body }) => {
  const delivery = await prisma.delivery.findUnique({ where: { orderId } });
  if (!delivery || delivery.provider !== 'simulated' || !delivery.driverName) return;
  if (['delivered', 'cancelled'].includes(delivery.status)) return;
  const reply = REPLIES.find(([re]) => re.test(body))?.[1] ?? 'Got your message! Heading your way 👍';
  setTimeout(() => bus.emit('chat.driver', { orderId, body: reply, via: 'app' }), 2500 / config.demo.simSpeed);
});

export const simulated: DeliveryProvider = {
  name: 'simulated',

  async quote(input: QuoteInput): Promise<QuoteOutput> {
    const miles = haversineMiles(input.store, input.dropoff);
    const readyAt = Date.now() + input.readyInMinutes * 60_000;
    return {
      externalId: input.externalId,
      // Roughly what DoorDash Drive charges a restaurant for a short hop.
      providerFeeCents: Math.round(675 + miles * 125),
      pickupEta: new Date(readyAt),
      dropoffEta: new Date(readyAt + driveMinutes(miles) * 60_000),
      expiresAt: new Date(Date.now() + 5 * 60_000),
    };
  },

  async dispatch(input: DispatchInput) {
    const externalId = `SIM-${input.order.number}-${Date.now().toString(36)}`;
    setTimeout(() => {
      void runSimulation(externalId, input.order.id, input.store, input.dropoff);
    }, 500);
    return { externalId, status: 'created' };
  },

  async cancel(externalId: string) {
    const run = runs.get(externalId);
    if (run) run.cancelled = true;
  },
};
