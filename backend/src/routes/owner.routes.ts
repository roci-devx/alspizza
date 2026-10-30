import fs from 'node:fs';
import { Router, type Request } from 'express';
import { z } from 'zod';
import { config, integrations } from '../config.js';
import { json, prisma } from '../db.js';
import { issueDownloadToken, readToken, requireOwner } from '../lib/auth.js';
import { badRequest, notFound, unauthorized } from '../lib/http.js';
import { localDate } from '../lib/time.js';
import { POS_OPTIONS } from '../integrations/pos/index.js';
import { customers, dashboard, PAID } from '../services/analytics.service.js';
import { listMessages, postMessage } from '../services/chat.service.js';
import { assignOwnDriver, sendToCourier } from '../services/delivery.service.js';
import { ACTIVE_ORDER_STATUSES, loadOrder } from '../services/order-core.js';
import { cancelOrder, retryPos, updateStatusByStore } from '../services/orders.service.js';
import { describePromo } from '../services/promo.service.js';
import { generateDailyReport, reportPath } from '../services/report.service.js';
import { serializeOrder } from '../services/serialize.js';

export const ownerRoutes = Router();

// The download link is opened by the browser directly, so it authenticates with a short-lived token instead of the header.
ownerRoutes.get('/owner/reports/:id/download', async (req, res) => {
  const claims = readToken(String(req.query.token ?? ''));
  if (!claims || claims.purpose !== 'download' || claims.rid !== req.params.id) throw unauthorized('This download link expired — open it again from the dashboard');
  const report = await prisma.dailyReport.findUnique({ where: { id: req.params.id }, include: { store: true } });
  if (!report) throw notFound('Report not found');
  let file = reportPath(report.store.slug, report.fileName);
  if (!fs.existsSync(file)) {
    const regenerated = await generateDailyReport(report.storeId, report.date);
    file = reportPath(report.store.slug, regenerated.fileName);
  }
  res.download(file, report.fileName);
});

ownerRoutes.use('/owner', requireOwner);

async function storeScope(req: Request) {
  const storeId = String(req.query.storeId ?? req.body?.storeId ?? 'all');
  const stores = await prisma.store.findMany({ orderBy: { name: 'asc' } });
  const selected = storeId === 'all' ? stores : stores.filter((s) => s.id === storeId);
  if (!selected.length) throw notFound('Store not found');
  return { storeIds: selected.map((s) => s.id), timezone: selected[0]!.timezone, stores: selected };
}

ownerRoutes.get('/owner/me', async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.auth!.sub } });
  const stores = await prisma.store.findMany({ orderBy: { name: 'asc' }, select: { id: true, name: true, slug: true, timezone: true } });
  res.json({ user: { id: user?.id, name: user?.name, email: user?.email }, stores });
});

ownerRoutes.get('/owner/integrations', (_req, res) => {
  res.json({
    integrations,
    pos: POS_OPTIONS,
    demo: config.demo,
    webhooks: {
      stripe: `${config.publicApiUrl}/api/webhooks/stripe`,
      doordash: `${config.publicApiUrl}/api/webhooks/doordash`,
      uber: `${config.publicApiUrl}/api/webhooks/uber`,
      square: `${config.publicApiUrl}/api/webhooks/square`,
      twilioSms: `${config.publicApiUrl}/api/webhooks/twilio/sms`,
      twilioVoice: `${config.publicApiUrl}/api/webhooks/twilio/voice`,
    },
  });
});

// ── Analytics ─────────────────────────────────────────────────────────────────
ownerRoutes.get('/owner/dashboard', async (req, res) => {
  const scope = await storeScope(req);
  const today = localDate(new Date(), scope.timezone);
  const q = z.object({ from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).default(today), to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).default(today) }).parse(req.query);
  if (q.from > q.to) throw badRequest('Start date must be before end date');
  res.json(await dashboard({ storeIds: scope.storeIds, timezone: scope.timezone, from: q.from, to: q.to }));
});

ownerRoutes.get('/owner/customers', async (req, res) => {
  const scope = await storeScope(req);
  res.json({ customers: await customers(scope.storeIds, req.query.q ? String(req.query.q) : undefined) });
});

// ── Live orders ───────────────────────────────────────────────────────────────
ownerRoutes.get('/owner/orders', async (req, res) => {
  const scope = await storeScope(req);
  const view = String(req.query.view ?? 'board');
  const since = new Date(Date.now() - 12 * 3600_000);
  const where =
    view === 'board'
      ? { storeId: { in: scope.storeIds }, OR: [{ status: { in: ACTIVE_ORDER_STATUSES } }, { status: { in: ['completed', 'cancelled'] }, updatedAt: { gte: since } }] }
      : { storeId: { in: scope.storeIds }, status: { not: 'pending_payment' } };
  const orders = await prisma.order.findMany({
    where,
    include: { items: true, delivery: true, store: true, _count: { select: { messages: true } } },
    orderBy: { createdAt: view === 'board' ? 'asc' : 'desc' },
    take: view === 'board' ? 200 : 100,
  });
  res.json({ orders: orders.map((o) => ({ ...serializeOrder(o, 'owner'), messageCount: o._count.messages })) });
});

ownerRoutes.get('/owner/orders/:id', async (req, res) => {
  const order = await loadOrder(req.params.id);
  if (!order) throw notFound('Order not found');
  res.json({ order: serializeOrder(order, 'owner'), messages: await listMessages(order.id) });
});

ownerRoutes.patch('/owner/orders/:id/status', async (req, res) => {
  const { status } = z.object({ status: z.enum(['received', 'preparing', 'ready', 'out_for_delivery', 'completed']) }).parse(req.body);
  await updateStatusByStore(req.params.id, status);
  res.json({ order: serializeOrder((await loadOrder(req.params.id))!, 'owner') });
});

ownerRoutes.post('/owner/orders/:id/cancel', async (req, res) => {
  const { reason } = z.object({ reason: z.string().max(200).default('Your order was cancelled by the store') }).parse(req.body ?? {});
  const order = await cancelOrder(req.params.id, reason);
  res.json({ order: order ? serializeOrder(order, 'owner') : null });
});

ownerRoutes.post('/owner/orders/:id/assign-driver', async (req, res) => {
  const body = z.object({ name: z.string().trim().min(1).max(60), phone: z.string().max(20).optional() }).parse(req.body);
  await assignOwnDriver(req.params.id, body.name, body.phone);
  res.json({ order: serializeOrder((await loadOrder(req.params.id))!, 'owner') });
});

ownerRoutes.post('/owner/orders/:id/send-to-courier', async (req, res) => {
  await sendToCourier(req.params.id);
  res.json({ order: serializeOrder((await loadOrder(req.params.id))!, 'owner') });
});

ownerRoutes.post('/owner/orders/:id/retry-pos', async (req, res) => {
  const order = await retryPos(req.params.id);
  res.json({ order: order ? serializeOrder(order, 'owner') : null });
});

ownerRoutes.post('/owner/orders/:id/messages', async (req, res) => {
  const { body } = z.object({ body: z.string().trim().min(1).max(600) }).parse(req.body);
  res.status(201).json({ message: await postMessage(req.params.id, 'store', body) });
});

// ── Promo codes = marketing attribution ───────────────────────────────────────
const promoSchema = z.object({
  code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{3,20}$/, 'Use 3–20 letters/numbers'),
  description: z.string().trim().min(1).max(140),
  type: z.enum(['percent', 'fixed', 'free_delivery']),
  value: z.number().int().min(0).max(100_000),
  minSubtotalCents: z.number().int().min(0).default(0),
  channel: z.string().trim().min(1).max(30),
  campaign: z.string().trim().max(60).nullish(),
  isActive: z.boolean().default(true),
  isPublic: z.boolean().default(false),
  firstOrderOnly: z.boolean().default(false),
  maxUses: z.number().int().min(1).nullish(),
  startsAt: z.coerce.date().nullish(),
  endsAt: z.coerce.date().nullish(),
});

ownerRoutes.get('/owner/promos', async (_req, res) => {
  const promos = await prisma.promoCode.findMany({ orderBy: { createdAt: 'desc' } });
  const usage = await prisma.order.groupBy({
    by: ['promoCode'],
    where: { promoCode: { not: null }, paymentStatus: { in: PAID }, status: { not: 'cancelled' } },
    _count: { _all: true },
    _sum: { totalCents: true, taxCents: true, tipCents: true, discountCents: true },
  });
  const byCode = new Map(usage.map((u) => [u.promoCode!, u]));
  res.json({
    promos: promos.map((p) => {
      const u = byCode.get(p.code);
      return {
        ...p,
        label: describePromo(p),
        uses: u?._count._all ?? 0,
        netSalesCents: u ? (u._sum.totalCents ?? 0) - (u._sum.taxCents ?? 0) - (u._sum.tipCents ?? 0) : 0,
        discountCents: u?._sum.discountCents ?? 0,
      };
    }),
  });
});

ownerRoutes.post('/owner/promos', async (req, res) => {
  const body = promoSchema.parse(req.body);
  if (body.type === 'percent' && body.value > 100) throw badRequest('Percent off must be 100 or less');
  if (await prisma.promoCode.findUnique({ where: { code: body.code } })) throw badRequest('That code already exists');
  res.status(201).json({ promo: await prisma.promoCode.create({ data: body }) });
});

ownerRoutes.patch('/owner/promos/:id', async (req, res) => {
  const body = promoSchema.partial().omit({ code: true }).parse(req.body);
  res.json({ promo: await prisma.promoCode.update({ where: { id: req.params.id }, data: body }) });
});

// ── End-of-day reports (Excel) ────────────────────────────────────────────────
ownerRoutes.get('/owner/reports', async (req, res) => {
  const scope = await storeScope(req);
  const reports = await prisma.dailyReport.findMany({
    where: { storeId: { in: scope.storeIds } },
    include: { store: { select: { name: true } } },
    orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
    take: 120,
  });
  res.json({ reports: reports.map((r) => ({ id: r.id, storeId: r.storeId, storeName: r.store.name, date: r.date, fileName: r.fileName, summary: json.parse(r.summaryJson, {}), emailedAt: r.emailedAt, createdAt: r.createdAt })) });
});

ownerRoutes.post('/owner/reports', async (req, res) => {
  const body = z.object({ storeId: z.string(), date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }).parse(req.body);
  const report = await generateDailyReport(body.storeId, body.date);
  res.status(201).json({ report: { ...report, summary: json.parse(report.summaryJson, {}) } });
});

ownerRoutes.get('/owner/reports/:id/link', async (req, res) => {
  const report = await prisma.dailyReport.findUnique({ where: { id: req.params.id } });
  if (!report) throw notFound('Report not found');
  const token = issueDownloadToken(req.auth!.sub, report.id);
  res.json({ url: `${config.publicApiUrl}/api/owner/reports/${report.id}/download?token=${encodeURIComponent(token)}`, fileName: report.fileName });
});

// ── Store settings ────────────────────────────────────────────────────────────
ownerRoutes.get('/owner/stores/:id/settings', async (req, res) => {
  const store = await prisma.store.findUnique({ where: { id: req.params.id } });
  if (!store) throw notFound('Store not found');
  res.json({ store: { ...store, hours: json.parse(store.hoursJson, {}) } });
});

ownerRoutes.patch('/owner/stores/:id/settings', async (req, res) => {
  const hhmm = z.string().regex(/^\d{2}:\d{2}$/);
  const body = z
    .object({
      name: z.string().trim().min(1).max(80),
      phone: z.string().trim().min(7).max(20),
      acceptingOrders: z.boolean(),
      pickupEnabled: z.boolean(),
      deliveryEnabled: z.boolean(),
      taxRate: z.number().min(0).max(0.25),
      deliveryMode: z.enum(['auto', 'own', 'doordash', 'uber']),
      ownDriversOnDuty: z.number().int().min(0).max(50),
      ownDeliveryFeeCents: z.number().int().min(0).max(5000),
      deliveryFeeMode: z.enum(['flat', 'passthrough']),
      flatDeliveryFeeCents: z.number().int().min(0).max(5000),
      deliveryRadiusMiles: z.number().min(0.5).max(25),
      minDeliveryCents: z.number().int().min(0).max(10_000),
      queueMinutesPerOrder: z.number().int().min(0).max(15),
      posProvider: z.enum(['none', 'square', 'clover', 'toast']),
      posLocationId: z.string().trim().max(80).nullable(),
      cashEnabled: z.boolean(),
      reportTime: hhmm,
      reportEmail: z.string().trim().email().nullable().or(z.literal('').transform(() => null)),
      hours: z.record(z.tuple([hhmm, hhmm]).nullable()),
    })
    .partial()
    .parse(req.body);
  const { hours, ...rest } = body;
  const store = await prisma.store.update({ where: { id: req.params.id }, data: { ...rest, ...(hours ? { hoursJson: JSON.stringify(hours) } : {}) } });
  res.json({ store: { ...store, hours: json.parse(store.hoursJson, {}) } });
});

