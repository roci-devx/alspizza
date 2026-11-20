import bcrypt from 'bcryptjs';
import { Router, type Request } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { STAFF_ROLES, issueSessionToken, requireRole, type Role } from '../lib/auth.js';
import { toE164 } from '../lib/geo.js';
import { badRequest, forbidden, notFound, unauthorized } from '../lib/http.js';
import { driverState, endShift, markDelivered, pickUp, reportProblem, startShift, updateLocation } from '../services/drivers.service.js';
import { ACTIVE_ORDER_STATUSES, loadOrder } from '../services/order-core.js';
import { updateStatusByStore } from '../services/orders.service.js';
import { serializeOrder } from '../services/serialize.js';

/** Al's Kitchen (tablet) and Al's Driver (phone). The owner manages these accounts in the owner app → Staff. */
export const staffRoutes = Router();

// ── Sign-in: email or phone + password ────────────────────────────────────────
const APP_ROLES: Record<'kitchen' | 'driver', Role[]> = { kitchen: ['kitchen', 'owner'], driver: ['driver'] };

staffRoutes.post('/staff/login', async (req, res) => {
  const body = z
    .object({ login: z.string().trim().min(3).max(120), password: z.string().min(1).max(100), app: z.enum(['kitchen', 'driver']) })
    .parse(req.body);
  const login = body.login.toLowerCase();
  const user = login.includes('@')
    ? await prisma.user.findUnique({ where: { email: login } })
    : await prisma.user.findFirst({ where: { phone: toE164(body.login), role: { in: [...STAFF_ROLES] } } });
  if (!user?.passwordHash || !(await bcrypt.compare(body.password, user.passwordHash))) throw unauthorized('Wrong login or password');
  if (!APP_ROLES[body.app].includes(user.role as Role)) throw forbidden(body.app === 'driver' ? 'This isn’t a driver account' : 'This isn’t a kitchen account');
  if (!user.isActive) throw forbidden('This account is switched off — talk to the owner');
  await prisma.user.update({ where: { id: user.id }, data: { lastSeenAt: new Date() } });
  res.json({ token: issueSessionToken(user), user: { id: user.id, name: user.name, role: user.role, storeId: user.storeId } });
});

// ── Kitchen tablet ────────────────────────────────────────────────────────────
/** A kitchen account sees its own store; the owner can open any store's kitchen view. */
async function kitchenStoreId(req: Request) {
  const me = await prisma.user.findUnique({ where: { id: req.auth!.sub } });
  if (!me?.isActive) throw forbidden('This account is switched off — talk to the owner');
  if (me.role === 'kitchen') {
    if (!me.storeId) throw badRequest('The owner hasn’t picked a store for this kitchen account');
    return me.storeId;
  }
  const wanted = String(req.query.storeId ?? '');
  const store = wanted ? await prisma.store.findUnique({ where: { id: wanted } }) : await prisma.store.findFirst({ orderBy: { name: 'asc' } });
  if (!store) throw notFound('Store not found');
  return store.id;
}

staffRoutes.get('/kitchen/state', requireRole('kitchen', 'owner'), async (req, res) => {
  const storeId = await kitchenStoreId(req);
  const store = await prisma.store.findUniqueOrThrow({ where: { id: storeId } });
  const since = new Date(Date.now() - 2 * 3600_000);
  const orders = await prisma.order.findMany({
    where: { storeId, OR: [{ status: { in: ACTIVE_ORDER_STATUSES } }, { status: { in: ['completed', 'cancelled'] }, updatedAt: { gte: since } }] },
    include: { items: true, delivery: true, store: true },
    orderBy: { createdAt: 'asc' },
    take: 200,
  });
  const stores = req.auth!.role === 'owner' ? await prisma.store.findMany({ orderBy: { name: 'asc' }, select: { id: true, name: true } }) : null;
  res.json({ store: { id: store.id, name: store.name, timezone: store.timezone }, stores, orders: orders.map((o) => serializeOrder(o, 'owner')) });
});

staffRoutes.patch('/kitchen/orders/:id/status', requireRole('kitchen', 'owner'), async (req, res) => {
  const { status } = z.object({ status: z.enum(['preparing', 'ready', 'completed']) }).parse(req.body);
  const order = await prisma.order.findUnique({ where: { id: String(req.params.id) } });
  if (!order) throw notFound('Order not found');
  if (req.auth!.role === 'kitchen' && order.storeId !== (await kitchenStoreId(req))) throw notFound('Order not found');
  if (status === 'completed' && order.fulfillment !== 'pickup') throw badRequest('Delivery orders are completed by the driver');
  await updateStatusByStore(order.id, status);
  res.json({ order: serializeOrder((await loadOrder(order.id))!, 'owner') });
});

// ── Driver app ────────────────────────────────────────────────────────────────
staffRoutes.use('/driver', requireRole('driver'));

const me = (req: Request) => req.auth!.sub;

staffRoutes.get('/driver/state', async (req, res) => {
  res.json(await driverState(me(req)));
});

staffRoutes.post('/driver/shift/start', async (req, res) => {
  await startShift(me(req));
  res.json(await driverState(me(req)));
});

staffRoutes.post('/driver/shift/end', async (req, res) => {
  await endShift(me(req));
  res.json(await driverState(me(req)));
});

staffRoutes.post('/driver/pickup', async (req, res) => {
  const { count } = z.object({ count: z.number().int().min(1).max(20).optional() }).parse(req.body ?? {});
  const taken = await pickUp(me(req), count);
  res.json({ ...(await driverState(me(req))), pickedUp: taken });
});

staffRoutes.post('/driver/deliveries/:id/delivered', async (req, res) => {
  const { cashCollected } = z.object({ cashCollected: z.boolean().default(false) }).parse(req.body ?? {});
  await markDelivered(me(req), req.params.id, cashCollected);
  res.json(await driverState(me(req)));
});

staffRoutes.post('/driver/deliveries/:id/problem', async (req, res) => {
  const { reason } = z.object({ reason: z.string().trim().min(3).max(200) }).parse(req.body);
  await reportProblem(me(req), req.params.id, reason);
  res.json(await driverState(me(req)));
});

staffRoutes.post('/driver/location', async (req, res) => {
  const { lat, lng } = z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }).parse(req.body);
  await updateLocation(me(req), lat, lng);
  res.json({ ok: true });
});
