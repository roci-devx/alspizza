/**
 * Seeds a realistic demo: 3 stores, the full menu, marketing promo codes,
 * ~400 customers and 60 days of order history (so the owner dashboard and
 * Excel reports have something to show), plus a few live orders.
 *
 *   npm run db:reset      # wipe + seed
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import bcrypt from 'bcryptjs';
import type { Prisma, Store } from '@prisma/client';
import { DEMO_ACCOUNTS } from '../config.js';
import { prisma } from '../db.js';
import { addDays, localDate, startOfLocalDay } from '../lib/time.js';
import { CATALOG, PIZZA_OPTIONS, catalogDisplayPrice, type SizeId } from '../menu/catalog.js';
import { computeTotals, priceLine, type CartLineInput, type MenuItemWithCategory } from '../menu/pricing.js';
import { customerKeyFor } from '../services/orders.service.js';
import { generateDailyReport } from '../services/report.service.js';

// Deterministic randomness so every reset produces the same demo.
let seedState = 20261029;
const rand = () => {
  seedState |= 0;
  seedState = (seedState + 0x6d2b79f5) | 0;
  let t = Math.imul(seedState ^ (seedState >>> 15), 1 | seedState);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = <T>(xs: readonly T[]) => xs[Math.floor(rand() * xs.length)]!;
const weighted = <T>(pairs: readonly (readonly [T, number])[]) => {
  const total = pairs.reduce((s, [, w]) => s + w, 0);
  let r = rand() * total;
  for (const [v, w] of pairs) if ((r -= w) <= 0) return v;
  return pairs[pairs.length - 1]![0];
};
const between = (a: number, b: number) => a + rand() * (b - a);
const minutes = (d: Date, m: number) => new Date(d.getTime() + m * 60_000);

const HOURS: Record<string, [string, string] | null> = {
  mon: ['11:00', '23:00'],
  tue: ['11:00', '23:00'],
  wed: ['11:00', '23:00'],
  thu: ['11:00', '23:00'],
  fri: ['11:00', '01:00'],
  sat: ['11:00', '01:00'],
  sun: ['11:00', '22:00'],
};

const STORES = [
  { slug: 'lincoln-park', name: "Al's Pizza — Lincoln Park", phone: '+13125550101', line1: '2418 N Clark St', city: 'Chicago', state: 'IL', zip: '60614', lat: 41.9262, lng: -87.6408, volume: 1.0, ownDrivers: 0 },
  { slug: 'wicker-park', name: "Al's Pizza — Wicker Park", phone: '+13125550102', line1: '1550 N Milwaukee Ave', city: 'Chicago', state: 'IL', zip: '60622', lat: 41.9097, lng: -87.6772, volume: 0.8, ownDrivers: 0 },
  { slug: 'south-loop', name: "Al's Pizza — South Loop", phone: '+13125550103', line1: '1200 S Michigan Ave', city: 'Chicago', state: 'IL', zip: '60605', lat: 41.867, lng: -87.6243, volume: 0.65, ownDrivers: 0 },
];

const PROMOS: Prisma.PromoCodeCreateInput[] = [
  { code: 'WELCOME15', description: '15% off your first app order', type: 'percent', value: 15, channel: 'In-App', campaign: 'App onboarding', isPublic: true, firstOrderOnly: true },
  { code: 'INSTA20', description: '20% off orders $25+', type: 'percent', value: 20, minSubtotalCents: 2500, channel: 'Instagram', campaign: 'Fall cheese-pull reels' },
  { code: 'TIKTOK5', description: '$5 off orders $20+', type: 'fixed', value: 500, minSubtotalCents: 2000, channel: 'TikTok', campaign: 'Stuffed crust challenge' },
  { code: 'FLYER10', description: '$10 off orders $40+', type: 'fixed', value: 1000, minSubtotalCents: 4000, channel: 'Flyer', campaign: 'Campus move-in flyers' },
  { code: 'FREEDEL', description: 'Free delivery on $20+', type: 'free_delivery', value: 0, minSubtotalCents: 2000, channel: 'Email', campaign: 'October newsletter', isPublic: true },
  { code: 'GAMEDAY', description: '$6 off orders $35+ on game day', type: 'fixed', value: 600, minSubtotalCents: 3500, channel: 'Facebook', campaign: 'Sunday football', isPublic: true },
  { code: 'REFER10', description: '10% off when a friend sent you', type: 'percent', value: 10, channel: 'Referral', campaign: 'Refer-a-friend' },
  { code: 'RADIO25', description: '25% off orders $30+', type: 'percent', value: 25, minSubtotalCents: 3000, channel: 'Radio', campaign: 'Morning show spot', isActive: false },
];

const FIRST = ['James', 'Maria', 'Ahmed', 'Sofia', 'Liam', 'Aaliyah', 'Noah', 'Mei', 'Ethan', 'Fatima', 'Lucas', 'Grace', 'Mateo', 'Chloe', 'Daniel', 'Zara', 'Jackson', 'Priya', 'Owen', 'Imani', 'Caleb', 'Nora', 'Elijah', 'Hana', 'Isaac', 'Ruby', 'Marcus', 'Leila', 'Tyler', 'Ava', 'Jordan', 'Sam', 'Riley', 'Alex', 'Kenji', 'Abena', 'Diego', 'Olivia', 'Yusuf', 'Emma'];
const LAST = ['Johnson', 'Garcia', 'Nguyen', 'Patel', 'Kim', 'Okafor', 'Rossi', 'Murphy', 'Cohen', 'Silva', 'Novak', 'Haddad', 'Brooks', 'Lopez', 'Tanaka', 'Mensah', 'Walsh', 'Ivanova', 'Reyes', 'Bennett', 'Shah', 'Adeyemi', 'Kowalski', 'Moreau'];
const STREETS = ['W Armitage Ave', 'N Halsted St', 'W Fullerton Ave', 'N Sheffield Ave', 'W Division St', 'N Damen Ave', 'W North Ave', 'S Wabash Ave', 'S State St', 'W Roosevelt Rd', 'N Wells St', 'W Belden Ave'];
const SOURCES = [['Instagram', 30], ['Friend', 22], ['Google', 16], ['TikTok', 14], ['Flyer', 8], ['Facebook', 6], ['Other', 4]] as const;
const AREA = ['312', '773', '872', '708', '630', '847'];
const DRIVERS = ['Marcus T.', 'Priya K.', 'Diego R.', 'Hannah L.', 'Jamal W.', 'Chen Y.', 'Sasha B.'];

async function main() {
  console.log('🧹 clearing database…');
  await prisma.$transaction([
    prisma.chatMessage.deleteMany(),
    prisma.delivery.deleteMany(),
    prisma.orderItem.deleteMany(),
    prisma.order.deleteMany(),
    prisma.deliveryQuote.deleteMany(),
    prisma.dailyReport.deleteMany(),
    prisma.address.deleteMany(),
    prisma.user.deleteMany(),
    prisma.menuItem.deleteMany(),
    prisma.category.deleteMany(),
    prisma.promoCode.deleteMany(),
    prisma.store.deleteMany(),
    prisma.counter.deleteMany(),
    prisma.setting.deleteMany(),
  ]);

  console.log('🏪 stores, menu, promos…');
  // The real owner password only ever lives in .env; without one, a random password is printed below.
  const ownerPassword = process.env.OWNER_PASSWORD?.trim() || crypto.randomBytes(9).toString('base64url');
  await prisma.user.create({
    data: { email: 'owner@alspizza.com', name: 'Al', role: 'owner', passwordHash: await bcrypt.hash(ownerPassword, 10), createdAt: new Date('2025-01-01') },
  });
  // One-tap demo owner (the sign-in screen shows a "Use demo account" button outside production).
  await prisma.user.create({
    data: { email: DEMO_ACCOUNTS.owner.email, name: DEMO_ACCOUNTS.owner.name, role: 'owner', passwordHash: await bcrypt.hash(DEMO_ACCOUNTS.owner.password, 10), createdAt: new Date('2025-01-01') },
  });
  await prisma.setting.create({ data: { key: 'pizzaOptions', value: JSON.stringify(PIZZA_OPTIONS) } });
  // Stock photos live in public/stock/<item-slug>.jpg and are served at /media/stock/….
  const stockDir = path.resolve(process.cwd(), 'public', 'stock');
  const photo = (slug: string) => (fs.existsSync(path.join(stockDir, `${slug}.jpg`)) ? `/media/stock/${slug}.jpg` : null);
  const stores: Store[] = [];
  for (const s of STORES) {
    stores.push(
      await prisma.store.create({
        data: {
          slug: s.slug,
          name: s.name,
          phone: s.phone,
          line1: s.line1,
          city: s.city,
          state: s.state,
          zip: s.zip,
          lat: s.lat,
          lng: s.lng,
          timezone: 'America/Chicago',
          hoursJson: JSON.stringify(HOURS),
          ownDriversOnDuty: s.ownDrivers,
          reportEmail: 'owner@alspizza.com',
        },
      }),
    );
  }
  for (const [ci, c] of CATALOG.entries()) {
    await prisma.category.create({
      data: {
        slug: c.slug,
        name: c.name,
        tagline: c.tagline,
        sortOrder: ci,
        prepMinutes: c.prepMinutes,
        items: {
          create: c.items.map((i, ii) => ({
            slug: i.slug,
            name: i.name,
            description: i.description,
            kind: i.kind,
            art: i.art,
            calories: i.calories ?? null,
            imageUrl: photo(i.slug),
            tags: (i.tags ?? []).join(','),
            priceCents: catalogDisplayPrice(i),
            configJson: JSON.stringify(i.config),
            sortOrder: ii,
          })),
        },
      },
    });
  }
  const now = new Date();
  for (const p of PROMOS) {
    await prisma.promoCode.create({
      data: { ...p, createdAt: addDaysDate(now, -75), endsAt: p.code === 'RADIO25' ? addDaysDate(now, -38) : null },
    });
  }
  const promos = new Map((await prisma.promoCode.findMany()).map((p) => [p.code, p]));
  const menu: MenuItemWithCategory[] = await prisma.menuItem.findMany({ include: { category: true } });
  const byId = new Map(menu.map((m) => [m.id, m]));
  const inCategory = (slug: string) => menu.filter((m) => m.category.slug === slug);

  console.log('👥 customers…');
  const people: { id: string; name: string; phone: string; email: string | null; guest: boolean; source: string | null; weight: number; joinAt: Date }[] = [];
  const launch = minutes(now, -60 * 24 * 61);
  for (let i = 0; i < 420; i++) {
    const name = `${pick(FIRST)} ${pick(LAST)}`;
    const guest = i % 3 === 2;
    people.push({
      id: crypto.randomUUID(),
      name,
      // Fictional 555-01xx numbers spread across Chicago-area codes (6 × 100 unique).
      phone: `+1${AREA[i % AREA.length]}55501${String(Math.floor(i / AREA.length) % 100).padStart(2, '0')}`,
      email: guest ? null : `${name.toLowerCase().replace(/[^a-z]+/g, '.')}${i}@example.com`,
      guest,
      source: guest ? null : weighted(SOURCES),
      // Power-law loyalty: a few regulars order constantly, most order once or twice.
      weight: 1 / Math.pow(i + 3, 0.85),
      // A core of regulars from day one, then a steady stream of new app customers.
      joinAt: i < 90 ? launch : minutes(launch, rand() * 60 * 24 * 60),
    });
  }
  const demoCustomer = { id: crypto.randomUUID(), name: DEMO_ACCOUNTS.customer.name, phone: '+13125550150', email: DEMO_ACCOUNTS.customer.email, guest: false, source: 'Instagram', weight: 0.05, joinAt: launch };
  people.unshift(demoCustomer);
  const choosePerson = (at: Date) => {
    const active = people.filter((p) => p.joinAt <= at);
    // Brand-new customers are likeliest to order right after they join (that's what the promo was for).
    const fresh = active.filter((p) => at.getTime() - p.joinAt.getTime() < 3 * 86_400_000 && !firstSeenKeys.has(p.id));
    if (fresh.length && rand() < 0.35) return pick(fresh);
    const total = active.reduce((s, p) => s + p.weight, 0);
    let r = rand() * total;
    for (const p of active) if ((r -= p.weight) <= 0) return p;
    return active[active.length - 1]!;
  };
  const firstSeenKeys = new Set<string>();

  console.log('🍕 60 days of orders…');
  type Draft = { order: Prisma.OrderCreateManyInput; items: Prisma.OrderItemCreateManyInput[]; delivery?: Prisma.DeliveryCreateManyInput };
  const drafts: Draft[] = [];
  const firstOrder = new Map<string, Date>();
  const tz = 'America/Chicago';
  const today = localDate(now, tz);
  const DAY_VOLUME: Record<number, number> = { 0: 26, 1: 17, 2: 21, 3: 18, 4: 21, 5: 33, 6: 35 };
  const HOUR_WEIGHTS: [number, number][] = [[11, 4], [12, 8], [13, 6], [14, 3], [15, 2], [16, 4], [17, 9], [18, 12], [19, 11], [20, 8], [21, 5], [22, 3]];

  const buildLines = (): CartLineInput[] => {
    const lines: CartLineInput[] = [];
    const pizzaCount = weighted([[1, 60], [2, 28], [3, 8], [0, 4]] as const);
    for (let i = 0; i < pizzaCount; i++) {
      const item = weighted(inCategory('pizza').map((p, idx) => [p, [9, 8, 7, 9, 7, 5, 4, 4, 4, 3, 3, 3, 6][idx] ?? 3] as const));
      const size = weighted([['large', 50], ['medium', 30], ['xl', 12], ['personal', 8]] as const) as SizeId;
      const crust = size === 'personal' ? 'pan' : size === 'xl' ? weighted([['hand-tossed', 6], ['ny', 4]] as const) : weighted([['hand-tossed', 45], ['pan', 30], ['thin', 15], ...(size === 'large' ? ([['stuffed', 18]] as const) : []), ...(size === 'medium' ? ([['gluten-free', 3]] as const) : [])]);
      const cfg = JSON.parse(item.configJson).pizza as { toppings: string[]; sauce: string; cheese: string };
      const extra = rand() < 0.3 ? [pick(['mushroom', 'jalapeno', 'onion', 'bacon', 'sausage', 'olive', 'pineapple'])] : [];
      lines.push({ itemId: item.id, quantity: 1, pizza: { size, crust, sauce: cfg.sauce, cheese: cfg.cheese, toppings: [...new Set([...cfg.toppings, ...extra])] } });
    }
    if (pizzaCount === 0 || rand() < 0.22) {
      const deal = pick(inCategory('deals'));
      lines.push({ itemId: deal.id, quantity: 1, choices: { pizza1: pick(['pepperoni', 'sausage', 'cheese', 'mushroom']), pizza2: pick(['pepperoni', 'cheese', 'bacon']) } });
    }
    if (rand() < 0.32) lines.push({ itemId: pick(inCategory('wings')).id, quantity: 1, variantId: pick(['6', '12', '8', '16']), choices: { sauce: pick(['buffalo-medium', 'honey-bbq', 'garlic-parm', 'lemon-pepper', 'buffalo-hot']), dip: pick(['ranch', 'blue-cheese']) } });
    if (rand() < 0.45) lines.push({ itemId: weighted(inCategory('sides').map((s, i) => [s, [10, 5, 4, 3, 3][i] ?? 2] as const)).id, quantity: 1 });
    if (rand() < 0.08) lines.push({ itemId: pick(inCategory('pasta')).id, quantity: 1 });
    if (rand() < 0.2) lines.push({ itemId: pick(inCategory('desserts')).id, quantity: 1 });
    if (rand() < 0.4) lines.push({ itemId: weighted(inCategory('drinks').map((d, i) => [d, [10, 5, 4, 3, 3, 3, 2][i] ?? 2] as const)).id, quantity: weighted([[1, 7], [2, 3]] as const), variantId: rand() < 0.7 ? '2l' : '20oz' });
    if (rand() < 0.18) lines.push({ itemId: pick(inCategory('dips')).id, quantity: weighted([[1, 6], [2, 3], [3, 1]] as const) });
    return lines;
  };

  const makeOrder = (store: (typeof stores)[number], createdAt: Date, opts: { status?: string; activeStage?: string } = {}) => {
    const person = choosePerson(createdAt);
    firstSeenKeys.add(person.id);
    const priced = buildLines().map((l) => priceLine(byId.get(l.itemId)!, l));
    const subtotal = priced.reduce((s, l) => s + l.totalCents, 0);
    const delivery = rand() < 0.56;
    const key = customerKeyFor(person.id, person.phone);
    const isFirst = !firstOrder.has(key);
    const daysAgo = (now.getTime() - createdAt.getTime()) / 86_400_000;

    let promoCode: string | null = null;
    if (rand() < 0.2) {
      const candidate = weighted([
        ['INSTA20', 30], ['WELCOME15', isFirst ? 26 : 0], ['FREEDEL', delivery ? 15 : 0], ['TIKTOK5', 13],
        ['FLYER10', subtotal >= 4000 ? 9 : 0], ['GAMEDAY', createdAt.getUTCDay() === 0 ? 30 : 4], ['REFER10', 6], ['RADIO25', daysAgo > 40 ? 22 : 0],
      ] as const);
      const p = promos.get(candidate)!;
      if (subtotal >= p.minSubtotalCents) promoCode = candidate;
    }
    const promo = promoCode ? promos.get(promoCode)! : null;
    const deliveryFee = delivery ? 399 : 0;
    const foodDiscount = !promo ? 0 : promo.type === 'percent' ? Math.round((subtotal * promo.value) / 100) : promo.type === 'fixed' ? Math.min(promo.value, subtotal) : 0;
    const deliveryDiscount = promo?.type === 'free_delivery' ? deliveryFee : 0;
    const tip = delivery ? Math.round(subtotal * weighted([[0.15, 4], [0.18, 3], [0.2, 3], [0.1, 1]] as const) / 25) * 25 : 0;
    const totals = computeTotals({ subtotalCents: subtotal, foodDiscountCents: foodDiscount, deliveryFeeCents: deliveryFee, deliveryDiscountCents: deliveryDiscount, taxRate: store.taxRate, tipCents: tip });

    const platform = weighted([['ios', 46], ['android', 34], ['web', 20]] as const);
    const cash = !delivery && rand() < 0.12;
    const method = cash
      ? 'Pay at pickup'
      : platform === 'ios'
        ? weighted([['Apple Pay', 62], ['Visa •••• 4242', 22], ['PayPal', 9], ['Mastercard •••• 4444', 7]] as const)
        : platform === 'android'
          ? weighted([['Google Pay', 55], ['Visa •••• 1881', 25], ['PayPal', 10], ['Mastercard •••• 5100', 10]] as const)
          : weighted([['Visa •••• 4242', 40], ['Apple Pay', 18], ['Google Pay', 15], ['PayPal', 15], ['Amex •••• 0005', 12]] as const);
    const status = opts.status ?? (rand() < 0.02 ? 'cancelled' : 'completed');
    const paidAt = minutes(createdAt, 0.5);
    const prep = between(12, 24);
    const stageIndex = ['received', 'preparing', 'ready', 'out_for_delivery'].indexOf(opts.activeStage ?? '');
    const done = status === 'completed';
    const readyAt = done || stageIndex >= 2 ? minutes(paidAt, prep) : null;
    const outAt = delivery && (done || stageIndex >= 3) ? minutes(paidAt, prep + between(2, 8)) : null;
    const completedAt = done ? (delivery ? minutes(outAt!, between(9, 24)) : minutes(readyAt!, between(2, 14))) : null;
    const orderId = crypto.randomUUID();
    const customerLat = store.lat + between(-0.035, 0.035);
    const customerLng = store.lng + between(-0.04, 0.04);
    if (!firstOrder.has(key) && status !== 'cancelled') firstOrder.set(key, createdAt);

    const draft: Draft = {
      order: {
        id: orderId,
        number: 0,
        storeId: store.id,
        userId: person.id,
        customerKey: key,
        status: opts.activeStage ?? status,
        fulfillment: delivery ? 'delivery' : 'pickup',
        customerName: person.name,
        customerPhone: person.phone,
        customerEmail: person.email,
        addressJson: delivery
          ? JSON.stringify({ line1: `${Math.floor(between(600, 2900))} ${pick(STREETS)}`, line2: rand() < 0.4 ? `Apt ${Math.floor(between(1, 40))}${pick(['A', 'B', 'C', 'F'])}` : null, city: 'Chicago', state: 'IL', zip: store.zip, lat: customerLat, lng: customerLng, instructions: rand() < 0.3 ? pick(['Leave at the door', 'Ring buzzer 2', 'Call when outside', 'Side entrance']) : null })
          : null,
        itemsCount: priced.reduce((s, l) => s + l.quantity, 0),
        subtotalCents: subtotal,
        discountCents: totals.discountCents,
        deliveryFeeCents: deliveryFee,
        taxCents: totals.taxCents,
        tipCents: tip,
        totalCents: totals.totalCents,
        promoCode,
        promoChannel: promo?.channel ?? null,
        paymentProvider: cash ? 'cash' : 'stripe',
        paymentStatus: status === 'cancelled' ? 'refunded' : cash ? 'pay_at_pickup' : 'paid',
        paymentMethod: method === 'PayPal' ? 'PayPal' : method,
        paymentRef: cash ? null : `pi_seed_${orderId.slice(0, 8)}`,
        platform,
        estimatedReadyAt: minutes(paidAt, 18),
        createdAt,
        updatedAt: completedAt ?? now,
        paidAt,
        preparingAt: done || stageIndex >= 1 ? minutes(paidAt, between(1, 4)) : null,
        readyAt,
        outForDeliveryAt: outAt,
        completedAt,
        cancelledAt: status === 'cancelled' ? minutes(createdAt, 6) : null,
      },
      items: priced.map((l) => ({
        orderId,
        menuItemId: l.itemId,
        name: l.name,
        kind: l.kind,
        categorySlug: l.categorySlug,
        art: l.art,
        quantity: l.quantity,
        unitPriceCents: l.unitPriceCents,
        totalCents: l.totalCents,
        summary: l.summary,
        configJson: JSON.stringify(l.config),
      })),
    };
    if (delivery && status !== 'cancelled') {
      const live = !!opts.activeStage;
      const provider = live ? 'simulated' : weighted([['doordash', 58], ['own', 32], ['uber', 10]] as const);
      const atStore = stageIndex < 3;
      draft.delivery = {
        orderId,
        provider,
        externalId: `${provider.toUpperCase()}-SEED-${orderId.slice(0, 8)}`,
        status: done ? 'delivered' : stageIndex >= 3 ? 'enroute_to_dropoff' : stageIndex >= 1 ? 'enroute_to_pickup' : 'created',
        providerFeeCents: provider === 'own' ? 0 : Math.round(between(675, 1150)),
        driverName: !live || stageIndex >= 1 ? pick(DRIVERS) : null,
        driverVehicle: !live || stageIndex >= 1 ? pick(['Silver Honda Civic', 'Blue Toyota Prius', 'Red Vespa scooter', 'White Kia Soul']) : null,
        driverPhone: !live || stageIndex >= 1 ? '+13125550199' : null,
        driverLat: live && stageIndex >= 1 ? (atStore ? store.lat + 0.006 : (store.lat + customerLat) / 2) : null,
        driverLng: live && stageIndex >= 1 ? (atStore ? store.lng - 0.004 : (store.lng + customerLng) / 2) : null,
        dropoffEta: minutes(paidAt, prep + 22),
        createdAt: paidAt,
        updatedAt: completedAt ?? now,
      };
      draft.order.estimatedDeliveryAt = minutes(paidAt, prep + 22);
    }
    drafts.push(draft);
  };

  for (let d = 59; d >= 0; d--) {
    const date = addDays(today, -d);
    const dayStart = startOfLocalDay(date, tz);
    const weekday = new Date(`${date}T12:00:00Z`).getUTCDay();
    const trend = 0.82 + (0.28 * (59 - d)) / 59; // gentle growth since the app launched
    for (const [si, store] of stores.entries()) {
      const count = Math.round(DAY_VOLUME[weekday]! * STORES[si]!.volume * trend * between(0.8, 1.2));
      for (let n = 0; n < count; n++) {
        const hour = weighted(HOUR_WEIGHTS);
        const at = minutes(dayStart, hour * 60 + between(0, 59));
        if (at > minutes(now, -50)) continue; // today: only history up to ~an hour ago
        makeOrder(store, at);
      }
    }
  }
  // A handful of live orders so the kitchen board and trackers have something moving.
  const stages = ['received', 'received', 'preparing', 'preparing', 'preparing', 'ready', 'out_for_delivery', 'out_for_delivery'];
  stages.forEach((stage, i) => makeOrder(stores[i % stores.length]!, minutes(now, -(4 + i * 4)), { activeStage: stage }));

  drafts.sort((a, b) => (a.order.createdAt as Date).getTime() - (b.order.createdAt as Date).getTime());
  drafts.forEach((d, i) => (d.order.number = 1001 + i));

  // Users get created just before their first order; the rest signed up but never ordered.
  const firstSeen = new Map<string, Date>();
  for (const d of drafts) if (!firstSeen.has(d.order.userId!)) firstSeen.set(d.order.userId!, d.order.createdAt as Date);
  const demoHash = await bcrypt.hash(DEMO_ACCOUNTS.customer.password, 10);
  await prisma.user.createMany({
    data: people.map((p) => ({
      id: p.id,
      name: p.name,
      phone: p.phone,
      email: p.email,
      isGuest: p.guest,
      marketingSource: p.source,
      passwordHash: p.id === demoCustomer.id ? demoHash : null,
      platform: pick(['ios', 'android', 'web']),
      createdAt: firstSeen.has(p.id) ? minutes(firstSeen.get(p.id)!, -between(3, 240)) : p.joinAt,
    })),
  });

  const chunk = <T>(xs: T[], n: number) => Array.from({ length: Math.ceil(xs.length / n) }, (_, i) => xs.slice(i * n, i * n + n));
  for (const part of chunk(drafts, 400)) {
    await prisma.order.createMany({ data: part.map((d) => d.order) });
    await prisma.orderItem.createMany({ data: part.flatMap((d) => d.items) });
    const deliveries = part.flatMap((d) => (d.delivery ? [d.delivery] : []));
    if (deliveries.length) await prisma.delivery.createMany({ data: deliveries });
  }
  await prisma.counter.create({ data: { id: 'order_number', value: 1000 + drafts.length } });
  await prisma.address.create({
    data: { userId: demoCustomer.id, label: 'Home', line1: '2230 N Lincoln Ave', city: 'Chicago', state: 'IL', zip: '60614', lat: 41.9228, lng: -87.6496, instructions: 'Ring buzzer 3' },
  });

  console.log(`   ${drafts.length} orders, ${people.length} customers`);
  console.log('📊 end-of-day reports for the last 3 days…');
  for (const store of stores) for (const d of [3, 2, 1]) await generateDailyReport(store.id, addDays(today, -d));

  console.log('\n✅ Seeded!');
  console.log(`   Owner dashboard login:  owner@alspizza.com / ${process.env.OWNER_PASSWORD?.trim() ? '(OWNER_PASSWORD from .env)' : ownerPassword}`);
  console.log(`   Demo owner login:       ${DEMO_ACCOUNTS.owner.email} / ${DEMO_ACCOUNTS.owner.password}`);
  console.log(`   Demo customer login:    ${DEMO_ACCOUNTS.customer.email} / ${DEMO_ACCOUNTS.customer.password}`);
}

function addDaysDate(d: Date, days: number) {
  return new Date(d.getTime() + days * 86_400_000);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
