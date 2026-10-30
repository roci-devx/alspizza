import bcrypt from 'bcryptjs';
import { Router } from 'express';
import { z } from 'zod';
import { DEMO_ACCOUNTS, config, integrations } from '../config.js';
import { prisma } from '../db.js';
import { issueSessionToken, optionalAuth, requireUser } from '../lib/auth.js';
import { HttpError, badRequest, notFound, unauthorized } from '../lib/http.js';
import { formatAddress, type DeliveryAddress } from '../integrations/delivery/types.js';
import { UPSELL } from '../menu/catalog.js';
import { getPizzaOptions } from '../menu/options.js';
import { quoteDelivery } from '../services/delivery.service.js';
import { pickupEtaMinutes } from '../services/eta.service.js';
import { reverseGeocode, searchAddress } from '../services/geocode.service.js';
import { customerKeyFor, priceCart } from '../services/orders.service.js';
import { paymentOptions } from '../services/payment.service.js';
import { describePromo } from '../services/promo.service.js';
import { serializeMenuItem, serializeStore } from '../services/serialize.js';
import { addressSchema, platformSchema, priceSchema } from './schemas.js';

export const publicRoutes = Router();

type UserRow = { id: string; name: string | null; email: string | null; phone: string | null; isGuest: boolean; role: string; marketingSource: string | null };
const serializeUser = (u: UserRow) => ({ id: u.id, name: u.name, email: u.email, phone: u.phone, isGuest: u.isGuest, role: u.role, marketingSource: u.marketingSource });

publicRoutes.get('/health', (_req, res) => {
  res.json({ ok: true, time: new Date().toISOString() });
});

publicRoutes.get('/config', (_req, res) => {
  res.json({
    merchantName: config.merchantName,
    payments: paymentOptions(),
    demo: { payments: config.demo.payments, delivery: config.demo.simulateDelivery && !integrations.doordash && !integrations.uber },
    features: { googleMaps: integrations.googleMaps, driverChatRelay: integrations.twilio },
    demoAccounts: config.demo.accounts
      ? { customer: { email: DEMO_ACCOUNTS.customer.email, password: DEMO_ACCOUNTS.customer.password }, owner: { email: DEMO_ACCOUNTS.owner.email, password: DEMO_ACCOUNTS.owner.password } }
      : null,
  });
});

// ── Accounts (all optional: guests can order without one) ─────────────────────

publicRoutes.post('/auth/guest', async (req, res) => {
  const { platform } = z.object({ platform: platformSchema }).parse(req.body ?? {});
  const user = await prisma.user.create({ data: { isGuest: true, platform } });
  res.status(201).json({ token: issueSessionToken(user), user: serializeUser(user) });
});

publicRoutes.post('/auth/register', optionalAuth, async (req, res) => {
  const body = z
    .object({
      name: z.string().trim().min(1, 'Add your name').max(80),
      email: z.string().trim().toLowerCase().email('Enter a valid email'),
      password: z.string().min(8, 'Use at least 8 characters').max(100),
      phone: z.string().trim().max(20).optional(),
      marketingSource: z.string().max(40).optional(),
      platform: platformSchema,
    })
    .parse(req.body);
  if (await prisma.user.findUnique({ where: { email: body.email } })) {
    throw new HttpError(409, 'That email already has an account — sign in instead', 'email_taken');
  }
  const passwordHash = await bcrypt.hash(body.password, 10);
  const data = { name: body.name, email: body.email, phone: body.phone || null, passwordHash, isGuest: false, marketingSource: body.marketingSource ?? null };
  const guest = req.auth?.guest ? await prisma.user.findUnique({ where: { id: req.auth.sub } }) : null;
  // Upgrading the guest keeps any orders placed before signing up.
  const user = guest?.isGuest
    ? await prisma.user.update({ where: { id: guest.id }, data })
    : await prisma.user.create({ data: { ...data, platform: body.platform } });
  res.status(201).json({ token: issueSessionToken(user), user: serializeUser(user) });
});

publicRoutes.post('/auth/login', optionalAuth, async (req, res) => {
  const body = z.object({ email: z.string().trim().toLowerCase().email(), password: z.string().min(1) }).parse(req.body);
  const user = await prisma.user.findUnique({ where: { email: body.email } });
  if (!user?.passwordHash || !(await bcrypt.compare(body.password, user.passwordHash))) throw unauthorized('Wrong email or password');
  if (req.auth?.guest && req.auth.sub !== user.id) {
    await prisma.order.updateMany({ where: { userId: req.auth.sub }, data: { userId: user.id } });
  }
  await prisma.user.update({ where: { id: user.id }, data: { lastSeenAt: new Date() } });
  res.json({ token: issueSessionToken(user), user: serializeUser(user) });
});

publicRoutes.get('/auth/me', requireUser, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.auth!.sub } });
  if (!user) throw unauthorized();
  res.json({ user: serializeUser(user) });
});

publicRoutes.patch('/auth/me', requireUser, async (req, res) => {
  const body = z.object({ name: z.string().trim().min(1).max(80).optional(), phone: z.string().trim().max(20).optional() }).parse(req.body);
  const user = await prisma.user.update({ where: { id: req.auth!.sub }, data: body });
  res.json({ user: serializeUser(user) });
});

publicRoutes.get('/me/addresses', requireUser, async (req, res) => {
  res.json({ addresses: await prisma.address.findMany({ where: { userId: req.auth!.sub }, orderBy: { createdAt: 'desc' } }) });
});

publicRoutes.post('/me/addresses', requireUser, async (req, res) => {
  const body = addressSchema.extend({ label: z.string().max(20).default('Home'), lat: z.number(), lng: z.number() }).parse(req.body);
  const address = await prisma.address.create({ data: { ...body, line2: body.line2 ?? null, instructions: body.instructions ?? null, userId: req.auth!.sub } });
  res.status(201).json({ address });
});

publicRoutes.delete('/me/addresses/:id', requireUser, async (req, res) => {
  await prisma.address.deleteMany({ where: { id: String(req.params.id), userId: req.auth!.sub } });
  res.json({ ok: true });
});

// ── Stores, menu & deals ──────────────────────────────────────────────────────

publicRoutes.get('/stores', async (req, res) => {
  const q = z.object({ lat: z.coerce.number().optional(), lng: z.coerce.number().optional() }).parse(req.query);
  const near = q.lat != null && q.lng != null ? { lat: q.lat, lng: q.lng } : null;
  const stores = await prisma.store.findMany();
  const list = await Promise.all(stores.map(async (s) => ({ ...serializeStore(s, near), pickupEtaMinutes: await pickupEtaMinutes(s, []) })));
  list.sort((a, b) => (a.distanceMiles ?? 0) - (b.distanceMiles ?? 0) || a.name.localeCompare(b.name));
  res.json({ stores: list });
});

publicRoutes.get('/stores/:id', async (req, res) => {
  const store = await prisma.store.findUnique({ where: { id: req.params.id } });
  if (!store) throw notFound('Store not found');
  res.json({ store: { ...serializeStore(store), pickupEtaMinutes: await pickupEtaMinutes(store, []) } });
});

publicRoutes.get('/menu', async (_req, res) => {
  const categories = await prisma.category.findMany({ orderBy: { sortOrder: 'asc' }, include: { items: { orderBy: { sortOrder: 'asc' } } } });
  const idBySlug = new Map(categories.flatMap((c) => c.items.map((i) => [i.slug, i.id] as const)));
  const ids = (slugs: string[]) => slugs.map((s) => idBySlug.get(s)).filter(Boolean);
  res.json({
    categories: categories.map((c) => ({
      id: c.id,
      slug: c.slug,
      name: c.name,
      tagline: c.tagline,
      prepMinutes: c.prepMinutes,
      items: c.items.map((i) => serializeMenuItem({ ...i, category: c })),
    })),
    pizzaOptions: await getPizzaOptions(),
    upsell: { sides: ids(UPSELL.sides), desserts: ids(UPSELL.desserts), drinks: ids(UPSELL.drinks) },
  });
});

publicRoutes.get('/deals', async (_req, res) => {
  const now = new Date();
  const promos = await prisma.promoCode.findMany({
    where: { isActive: true, isPublic: true, OR: [{ endsAt: null }, { endsAt: { gt: now } }] },
    orderBy: { createdAt: 'desc' },
  });
  res.json({
    deals: promos
      .filter((p) => !p.startsAt || p.startsAt <= now)
      .map((p) => ({ code: p.code, description: p.description, label: describePromo(p), type: p.type, value: p.value, minSubtotalCents: p.minSubtotalCents, firstOrderOnly: p.firstOrderOnly, endsAt: p.endsAt })),
  });
});

// ── Location ──────────────────────────────────────────────────────────────────

publicRoutes.get('/geo/search', async (req, res) => {
  const q = z.object({ q: z.string().max(200), lat: z.coerce.number().optional(), lng: z.coerce.number().optional() }).parse(req.query);
  const near = q.lat != null && q.lng != null ? { lat: q.lat, lng: q.lng } : undefined;
  res.json({ results: await searchAddress(q.q, near) });
});

publicRoutes.get('/geo/reverse', async (req, res) => {
  const q = z.object({ lat: z.coerce.number(), lng: z.coerce.number() }).parse(req.query);
  res.json({ result: await reverseGeocode(q.lat, q.lng) });
});

// ── Cart & delivery quotes ────────────────────────────────────────────────────

publicRoutes.post('/cart/price', optionalAuth, async (req, res) => {
  const body = priceSchema.parse(req.body);
  const user = req.auth ? await prisma.user.findUnique({ where: { id: req.auth.sub }, select: { id: true, phone: true } }) : null;
  const p = await priceCart(body, user ? customerKeyFor(user.id, user.phone) : undefined);
  res.json({
    lines: p.lines.map(({ prepMinutes: _prep, ...l }) => l),
    itemsCount: p.itemsCount,
    subtotalCents: p.subtotalCents,
    discountCents: p.discountCents,
    deliveryFeeCents: p.deliveryFeeCents,
    taxCents: p.taxCents,
    tipCents: p.tipCents,
    totalCents: p.totalCents,
    promo: p.promo ? { code: p.promo.code, label: p.promo.label ?? null, error: p.promo.error ?? null } : null,
    pickupEtaMinutes: p.pickupEtaMinutes,
    deliveryEtaMinutes: p.deliveryEtaMinutes,
    quoteExpiresAt: p.quote?.expiresAt ?? null,
    minDeliveryCents: p.store.minDeliveryCents,
  });
});

publicRoutes.post('/delivery/quote', optionalAuth, async (req, res) => {
  const body = z
    .object({
      storeId: z.string(),
      address: addressSchema,
      subtotalCents: z.number().int().min(0).default(2500),
      customerName: z.string().max(80).optional(),
      customerPhone: z.string().max(20).optional(),
    })
    .parse(req.body);
  const store = await prisma.store.findUnique({ where: { id: body.storeId } });
  if (!store) throw notFound('Store not found');
  if (!store.deliveryEnabled) throw badRequest('This store is pickup-only right now', 'delivery_disabled');

  let { lat, lng } = body.address;
  let approximate = false;
  if (lat == null || lng == null) {
    const hit = (await searchAddress(formatAddress(body.address), store))[0];
    if (hit) ({ lat, lng } = hit);
    else if (!config.isProd) {
      // Offline/dev fallback so the flow is testable without a geocoder.
      lat = store.lat + 0.012;
      lng = store.lng - 0.01;
      approximate = true;
    } else throw badRequest("We couldn't find that address. Check the street and ZIP.", 'address_not_found');
  }
  const address: DeliveryAddress = { ...body.address, line2: body.address.line2 ?? null, instructions: body.address.instructions ?? null, lat, lng };
  const readyIn = await pickupEtaMinutes(store, []);
  const { quote, miles } = await quoteDelivery({
    store,
    address,
    customerName: body.customerName,
    customerPhone: body.customerPhone,
    orderValueCents: body.subtotalCents,
    readyInMinutes: readyIn,
  });
  res.json({
    quoteId: quote.id,
    feeCents: quote.customerFeeCents,
    etaMinutes: quote.dropoffEta ? Math.max(readyIn + 8, Math.round((quote.dropoffEta.getTime() - Date.now()) / 60_000)) : readyIn + 20,
    dropoffEta: quote.dropoffEta,
    expiresAt: quote.expiresAt,
    miles: Math.round(miles * 10) / 10,
    minDeliveryCents: store.minDeliveryCents,
    address,
    approximate,
  });
});
