import bcrypt from 'bcryptjs';
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { requireOwner } from '../lib/auth.js';
import { toE164 } from '../lib/geo.js';
import { HttpError, badRequest, notFound } from '../lib/http.js';
import { endShift, openShift, runDispatch, settleShift, teamOverview, unsettledCash } from '../services/drivers.service.js';

/** Owner app → Staff: kitchen and driver accounts, who's on the clock, and cash to settle. */
export const ownerStaffRoutes = Router();
ownerStaffRoutes.use('/owner', requireOwner);

async function scope(storeId: unknown) {
  const id = String(storeId ?? 'all');
  const stores = await prisma.store.findMany({ orderBy: { name: 'asc' }, select: { id: true } });
  const ids = id === 'all' ? stores.map((s) => s.id) : stores.filter((s) => s.id === id).map((s) => s.id);
  if (!ids.length) throw notFound('Store not found');
  return ids;
}

ownerStaffRoutes.get('/owner/staff', async (req, res) => {
  const storeIds = await scope(req.query.storeId);
  const staff = await prisma.user.findMany({
    where: { role: { in: ['kitchen', 'driver'] }, storeId: { in: storeIds } },
    include: { driver: true },
    orderBy: [{ isActive: 'desc' }, { role: 'asc' }, { name: 'asc' }],
  });
  const team = await teamOverview(storeIds);
  const onShift = new Set(team.onShift.map((d) => d.driverId));
  res.json({
    staff: await Promise.all(
      staff.map(async (u) => ({
        id: u.id,
        role: u.role,
        name: u.name,
        email: u.email,
        phone: u.phone,
        storeId: u.storeId,
        isActive: u.isActive,
        lastSeenAt: u.lastSeenAt,
        onShift: onShift.has(u.id),
        cashOwedCents: u.role === 'driver' ? (await unsettledCash(u.id)).cents : 0,
        driver: u.driver ? { maxActive: u.driver.maxActive, maxBacklog: u.driver.maxBacklog, cashEnabled: u.driver.cashEnabled, vehicle: u.driver.vehicle } : null,
      })),
    ),
    ...team,
  });
});

ownerStaffRoutes.get('/owner/drivers', async (req, res) => {
  res.json({ drivers: (await teamOverview(await scope(req.query.storeId))).onShift });
});

const staffFields = {
  name: z.string().trim().min(1).max(60),
  email: z.string().trim().toLowerCase().email().nullish().or(z.literal('').transform(() => null)),
  phone: z.string().trim().max(20).nullish().or(z.literal('').transform(() => null)),
  password: z.string().min(6, 'Use at least 6 characters').max(100),
  storeId: z.string().min(1),
  isActive: z.boolean(),
  maxActive: z.number().int().min(1).max(10),
  maxBacklog: z.number().int().min(0).max(20),
  cashEnabled: z.boolean(),
  vehicle: z.string().trim().max(60).nullish(),
};

async function checkLogin(email: string | null | undefined, phone: string | null | undefined, exceptId?: string) {
  if (email) {
    const taken = await prisma.user.findUnique({ where: { email } });
    if (taken && taken.id !== exceptId) throw new HttpError(409, 'Another account already uses that email', 'email_taken');
  }
  if (phone) {
    const taken = await prisma.user.findFirst({ where: { phone, role: { in: ['owner', 'kitchen', 'driver'] }, ...(exceptId ? { id: { not: exceptId } } : {}) } });
    if (taken) throw new HttpError(409, 'Another staff account already uses that phone number', 'phone_taken');
  }
}

ownerStaffRoutes.post('/owner/staff', async (req, res) => {
  const body = z
    .object({ role: z.enum(['kitchen', 'driver']), ...staffFields })
    .partial({ isActive: true, maxActive: true, maxBacklog: true, cashEnabled: true, vehicle: true })
    .parse(req.body);
  const phone = body.phone ? toE164(body.phone) : null;
  if (!body.email && !phone) throw badRequest('Add an email or a phone number — that’s what they sign in with');
  await checkLogin(body.email, phone);
  const store = await prisma.store.findUnique({ where: { id: body.storeId } });
  if (!store) throw notFound('Store not found');
  const user = await prisma.user.create({
    data: {
      role: body.role,
      name: body.name,
      email: body.email ?? null,
      phone,
      passwordHash: await bcrypt.hash(body.password, 10),
      storeId: store.id,
      isActive: body.isActive ?? true,
      isGuest: false,
      ...(body.role === 'driver'
        ? {
            driver: {
              create: {
                maxActive: body.maxActive ?? store.driverMaxActive,
                maxBacklog: body.maxBacklog ?? store.driverMaxBacklog,
                cashEnabled: body.cashEnabled ?? false,
                vehicle: body.vehicle ?? null,
              },
            },
          }
        : {}),
    },
  });
  res.status(201).json({ id: user.id });
});

ownerStaffRoutes.patch('/owner/staff/:id', async (req, res) => {
  const body = z.object(staffFields).partial().parse(req.body);
  const user = await prisma.user.findUnique({ where: { id: req.params.id }, include: { driver: true } });
  if (!user || !['kitchen', 'driver'].includes(user.role)) throw notFound('Staff member not found');
  const phone = body.phone === undefined ? undefined : body.phone ? toE164(body.phone) : null;
  await checkLogin(body.email, phone, user.id);
  const nextEmail = body.email !== undefined ? body.email : user.email;
  const nextPhone = phone !== undefined ? phone : user.phone;
  if (!nextEmail && !nextPhone) throw badRequest('Keep an email or a phone number — that’s what they sign in with');
  if (body.storeId && !(await prisma.store.findUnique({ where: { id: body.storeId } }))) throw notFound('Store not found');
  // Switched off or moved to another store mid-shift: clock them out first (queued orders go back to the store).
  if ((body.isActive === false || (body.storeId && body.storeId !== user.storeId)) && (await openShift(user.id))) {
    await endShift(user.id, { force: true });
  }
  await prisma.user.update({
    where: { id: user.id },
    data: {
      ...(body.name !== undefined ? { name: body.name } : {}),
      ...(body.email !== undefined ? { email: body.email } : {}),
      ...(phone !== undefined ? { phone } : {}),
      ...(body.password ? { passwordHash: await bcrypt.hash(body.password, 10) } : {}),
      ...(body.storeId ? { storeId: body.storeId } : {}),
      ...(body.isActive !== undefined ? { isActive: body.isActive } : {}),
    },
  });
  if (user.role === 'driver') {
    const limits = {
      ...(body.maxActive !== undefined ? { maxActive: body.maxActive } : {}),
      ...(body.maxBacklog !== undefined ? { maxBacklog: body.maxBacklog } : {}),
      ...(body.cashEnabled !== undefined ? { cashEnabled: body.cashEnabled } : {}),
      ...(body.vehicle !== undefined ? { vehicle: body.vehicle } : {}),
    };
    await prisma.driverProfile.upsert({ where: { userId: user.id }, create: { userId: user.id, ...limits }, update: limits });
    if (user.storeId) await runDispatch(body.storeId ?? user.storeId); // more room may let waiting orders through
  }
  res.json({ ok: true });
});

ownerStaffRoutes.post('/owner/staff/:id/end-shift', async (req, res) => {
  const shift = await endShift(req.params.id, { force: true });
  res.json({ shift });
});

ownerStaffRoutes.post('/owner/shifts/:id/settle', async (req, res) => {
  const body = z.object({ receivedCents: z.number().int().min(0).max(10_000_000), note: z.string().max(200).nullish() }).parse(req.body);
  res.json({ shift: await settleShift(req.params.id, req.auth!.sub, body.receivedCents, body.note) });
});
