import { Router, type Request } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { requireUser } from '../lib/auth.js';
import { forbidden, notFound } from '../lib/http.js';
import { listMessages, postMessage } from '../services/chat.service.js';
import { loadOrder } from '../services/order-core.js';
import { createOrder } from '../services/orders.service.js';
import { startPayment, syncPayment } from '../services/payment.service.js';
import { serializeOrder } from '../services/serialize.js';
import { createOrderSchema, paySchema } from './schemas.js';

export const orderRoutes = Router();
orderRoutes.use(requireUser);

async function ownedOrder(req: Request) {
  const order = await loadOrder(String(req.params.id));
  if (!order) throw notFound('Order not found');
  if (order.userId !== req.auth!.sub && req.auth!.role !== 'owner') throw forbidden('That order belongs to someone else');
  return order;
}

orderRoutes.post('/', async (req, res) => {
  const body = createOrderSchema.parse(req.body);
  const order = await createOrder(body, { id: req.auth!.sub });
  res.status(201).json({ order: serializeOrder(order, 'customer') });
});

orderRoutes.get('/', async (req, res) => {
  const orders = await prisma.order.findMany({
    where: { userId: req.auth!.sub, status: { not: 'pending_payment' } },
    include: { items: true, delivery: true, store: true },
    orderBy: { createdAt: 'desc' },
    take: 30,
  });
  res.json({ orders: orders.map((o) => serializeOrder(o, 'customer')) });
});

orderRoutes.get('/:id', async (req, res) => {
  res.json({ order: serializeOrder(await ownedOrder(req), 'customer') });
});

orderRoutes.post('/:id/pay', async (req, res) => {
  const order = await ownedOrder(req);
  const body = paySchema.parse(req.body);
  const result = await startPayment(order, body.provider, body.method, body.platform);
  const fresh = await loadOrder(order.id);
  res.json({ ...result, order: fresh ? serializeOrder(fresh, 'customer') : null });
});

orderRoutes.post('/:id/payment/sync', async (req, res) => {
  const order = await ownedOrder(req);
  const fresh = await syncPayment(order.id);
  res.json({ order: fresh ? serializeOrder(fresh, 'customer') : null });
});

orderRoutes.get('/:id/messages', async (req, res) => {
  const order = await ownedOrder(req);
  res.json({ messages: await listMessages(order.id) });
});

orderRoutes.post('/:id/messages', async (req, res) => {
  const order = await ownedOrder(req);
  const { body } = z.object({ body: z.string().trim().min(1).max(600) }).parse(req.body);
  res.status(201).json({ message: await postMessage(order.id, 'customer', body) });
});
