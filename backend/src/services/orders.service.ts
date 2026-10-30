import type { Store } from '@prisma/client';
import { config } from '../config.js';
import { json, nextCounter, prisma } from '../db.js';
import { toE164 } from '../lib/geo.js';
import { badRequest, notFound } from '../lib/http.js';
import { isOpenAt, type WeeklyHours } from '../lib/time.js';
import { refund as stripeRefund } from '../integrations/payments/stripe.js';
import { refundPaypalCapture } from '../integrations/payments/paypal.js';
import { pushOrderToPos } from '../integrations/pos/index.js';
import type { DeliveryAddress } from '../integrations/delivery/types.js';
import { getPizzaOptions } from '../menu/options.js';
import { computeTotals, priceLines, type CartLineInput } from '../menu/pricing.js';
import { postMessage } from './chat.service.js';
import { cancelDelivery, dispatchDelivery, syncOwnDelivery } from './delivery.service.js';
import { minutesFromNow, pickupEtaMinutes } from './eta.service.js';
import { loadOrder, orderInclude, publishOrder, setStatus } from './order-core.js';
import { evaluatePromo } from './promo.service.js';

export type Fulfillment = 'pickup' | 'delivery';

export interface PriceInput {
  storeId: string;
  items: CartLineInput[];
  fulfillment?: Fulfillment;
  promoCode?: string | null;
  deliveryQuoteId?: string | null;
  tipCents?: number;
}

/** Repeat customers are recognized by phone number first (what pizza shops have always done), then account. */
export function customerKeyFor(userId: string, phone?: string | null) {
  const digits = phone?.replace(/\D/g, '').slice(-10);
  return digits && digits.length === 10 ? `phone:${digits}` : `user:${userId}`;
}

export async function priceCart(input: PriceInput, customerKey?: string) {
  const store = await prisma.store.findUnique({ where: { id: input.storeId } });
  if (!store) throw notFound('Store not found');
  const ids = [...new Set(input.items.map((i) => i.itemId))];
  const menuItems = await prisma.menuItem.findMany({ where: { id: { in: ids } }, include: { category: true } });
  const { lines, subtotalCents, itemsCount } = priceLines(menuItems, input.items, await getPizzaOptions());

  let deliveryFeeCents = 0;
  const quote =
    input.fulfillment === 'delivery' && input.deliveryQuoteId ? await prisma.deliveryQuote.findUnique({ where: { id: input.deliveryQuoteId } }) : null;
  if (input.fulfillment === 'delivery' && input.deliveryQuoteId && (!quote || quote.storeId !== store.id)) {
    throw badRequest('Please confirm your delivery address again', 'quote_invalid');
  }
  if (quote) deliveryFeeCents = quote.customerFeeCents;

  const promo = await evaluatePromo(input.promoCode, { subtotalCents, deliveryFeeCents, fulfillment: input.fulfillment, customerKey });
  const valid = promo && !promo.error ? promo : null;
  const tipCents = input.fulfillment === 'delivery' ? Math.max(0, Math.min(20_000, Math.round(input.tipCents ?? 0))) : 0;
  const totals = computeTotals({
    subtotalCents,
    foodDiscountCents: valid?.foodDiscountCents ?? 0,
    deliveryFeeCents,
    deliveryDiscountCents: valid?.deliveryDiscountCents ?? 0,
    taxRate: store.taxRate,
    tipCents,
  });
  const pickupEta = await pickupEtaMinutes(store, lines.map((l) => l.prepMinutes));
  const deliveryEta = quote?.dropoffEta ? Math.max(pickupEta + 8, Math.round((quote.dropoffEta.getTime() - Date.now()) / 60_000)) : null;

  return { store, lines, itemsCount, subtotalCents, deliveryFeeCents, tipCents, promo, quote, pickupEtaMinutes: pickupEta, deliveryEtaMinutes: deliveryEta, ...totals };
}

export interface CreateOrderInput extends PriceInput {
  fulfillment: Fulfillment;
  customer: { name: string; phone: string; email?: string | null };
  notes?: string | null;
  dropoffInstructions?: string | null;
  addressLine2?: string | null;
  platform: 'ios' | 'android' | 'web';
}

function assertStoreCanTake(store: Store, fulfillment: Fulfillment) {
  if (!store.acceptingOrders) throw badRequest(`${store.name} isn't taking online orders right now. Please call the store.`, 'store_paused');
  if (config.enforceStoreHours && !isOpenAt(json.parse<WeeklyHours>(store.hoursJson, {}), store.timezone)) {
    throw badRequest(`${store.name} is closed right now`, 'store_closed');
  }
  if (fulfillment === 'pickup' && !store.pickupEnabled) throw badRequest('Pickup is paused at this store', 'pickup_disabled');
  if (fulfillment === 'delivery' && !store.deliveryEnabled) throw badRequest('Delivery is paused at this store — pickup is open!', 'delivery_disabled');
}

export async function createOrder(input: CreateOrderInput, user: { id: string }) {
  const customerKey = customerKeyFor(user.id, input.customer.phone);
  const priced = await priceCart(input, customerKey);
  const { store } = priced;
  assertStoreCanTake(store, input.fulfillment);
  if (priced.promo?.error) throw badRequest(priced.promo.error, 'promo_invalid');

  let address: DeliveryAddress | null = null;
  if (input.fulfillment === 'delivery') {
    if (!priced.quote) throw badRequest('Add a delivery address first', 'address_required');
    if (priced.subtotalCents < store.minDeliveryCents) {
      throw badRequest(`Delivery orders start at $${(store.minDeliveryCents / 100).toFixed(2)}`, 'delivery_minimum');
    }
    address = json.parse<DeliveryAddress>(priced.quote.addressJson, null as unknown as DeliveryAddress);
    if (input.addressLine2 !== undefined) address.line2 = input.addressLine2 || null;
    if (input.dropoffInstructions !== undefined) address.instructions = input.dropoffInstructions || null;
  }

  const number = await nextCounter('order_number', 1001);
  const order = await prisma.order.create({
    data: {
      number,
      storeId: store.id,
      userId: user.id,
      customerKey,
      status: 'pending_payment',
      fulfillment: input.fulfillment,
      customerName: input.customer.name.trim(),
      customerPhone: toE164(input.customer.phone),
      customerEmail: input.customer.email?.trim().toLowerCase() || null,
      addressJson: address ? JSON.stringify(address) : null,
      itemsCount: priced.itemsCount,
      subtotalCents: priced.subtotalCents,
      discountCents: priced.discountCents,
      deliveryFeeCents: priced.deliveryFeeCents,
      taxCents: priced.taxCents,
      tipCents: priced.tipCents,
      totalCents: priced.totalCents,
      promoCode: priced.promo?.code ?? null,
      promoChannel: priced.promo?.promo?.channel ?? null,
      deliveryQuoteId: priced.quote?.id ?? null,
      paymentProvider: 'pending',
      platform: input.platform,
      notes: input.notes?.trim().slice(0, 300) || null,
      estimatedReadyAt: minutesFromNow(priced.pickupEtaMinutes),
      estimatedDeliveryAt: priced.deliveryEtaMinutes ? minutesFromNow(priced.deliveryEtaMinutes) : null,
      items: {
        create: priced.lines.map((l) => ({
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
      },
    },
    include: orderInclude,
  });

  // Remember contact details for next time.
  await prisma.user.update({
    where: { id: user.id },
    data: { name: input.customer.name.trim(), phone: order.customerPhone, lastSeenAt: new Date() },
  });
  return order;
}

export interface PaymentResult {
  provider: 'stripe' | 'paypal' | 'cash' | 'demo';
  ref?: string | null;
  method?: string | null;
  status?: 'paid' | 'pay_at_pickup';
}

/** Idempotent: webhooks, client sync calls and return URLs may all report the same payment. */
export async function markPaid(orderId: string, payment: PaymentResult) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { items: true, store: true } });
  if (!order) throw notFound('Order not found');
  if (order.paymentStatus === 'paid' || order.paymentStatus === 'pay_at_pickup') return;
  if (order.status === 'cancelled') {
    console.warn(`[orders] payment received for cancelled order #${order.number} — refund manually`);
    return;
  }

  const menuItems = await prisma.menuItem.findMany({ where: { id: { in: order.items.map((i) => i.menuItemId) } }, include: { category: true } });
  const eta = await pickupEtaMinutes(order.store, menuItems.map((m) => m.prepMinutes ?? m.category.prepMinutes));
  await prisma.order.update({
    where: { id: orderId },
    data: {
      status: 'received',
      paymentStatus: payment.status ?? 'paid',
      paymentProvider: payment.provider,
      paymentRef: payment.ref ?? order.paymentRef,
      paymentMethod: payment.method ?? order.paymentMethod,
      paidAt: new Date(),
      estimatedReadyAt: minutesFromNow(eta),
    },
  });
  await publishOrder(orderId, 'order.new');

  void sendToPos(orderId);
  if (order.fulfillment === 'delivery') {
    dispatchDelivery(orderId).catch((err) => console.error('[orders] dispatch failed', err));
  }
  if (config.demo.autoKitchen) runDemoKitchen(orderId, order.fulfillment);
}

async function sendToPos(orderId: string) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { items: true, store: true } });
  if (!order) return;
  try {
    const { provider, posOrderId } = await pushOrderToPos(order, order.store);
    if (provider !== 'none') await prisma.order.update({ where: { id: orderId }, data: { posProvider: provider, posOrderId, posError: null } });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[pos] push failed for #${order.number}`, message);
    await prisma.order.update({ where: { id: orderId }, data: { posProvider: order.store.posProvider, posError: message.slice(0, 500) } });
    await publishOrder(orderId);
  }
}

export async function retryPos(orderId: string) {
  await sendToPos(orderId);
  return loadOrder(orderId);
}

/** Demo only: moves fresh orders through the kitchen so the tracker animates without staff. */
function runDemoKitchen(orderId: string, fulfillment: string) {
  const s = config.demo.simSpeed;
  const advance = async (from: string, to: string) => {
    const o = await prisma.order.findUnique({ where: { id: orderId }, select: { status: true } });
    if (o?.status === from) await setStatus(orderId, to).catch(() => {});
  };
  setTimeout(() => void advance('received', 'preparing'), 6_000 / s);
  setTimeout(() => void advance('preparing', 'ready'), 45_000 / s);
  if (fulfillment === 'pickup') setTimeout(() => void advance('ready', 'completed'), 120_000 / s);
}

export async function updateStatusByStore(orderId: string, status: string) {
  await setStatus(orderId, status);
  await syncOwnDelivery(orderId, status);
  await publishOrder(orderId);
}

export async function cancelOrder(orderId: string, reason = 'Cancelled by the store') {
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) throw notFound('Order not found');
  if (order.status === 'completed') throw badRequest('Completed orders cannot be cancelled — issue a refund from your payment dashboard');
  if (order.status === 'cancelled') return loadOrder(orderId);

  let paymentStatus = order.paymentStatus;
  if (order.paymentStatus === 'paid' && order.paymentRef) {
    try {
      if (order.paymentProvider === 'stripe') await stripeRefund(order.paymentRef);
      if (order.paymentProvider === 'paypal') await refundPaypalCapture(order.paymentRef);
      paymentStatus = 'refunded';
    } catch (err) {
      console.error('[orders] refund failed', err);
      throw badRequest('Refund failed — the order was not cancelled. Check your payment dashboard.');
    }
  } else if (order.paymentProvider === 'demo') {
    paymentStatus = 'refunded';
  }
  await cancelDelivery(orderId);
  await prisma.order.update({ where: { id: orderId }, data: { paymentStatus } });
  await setStatus(orderId, 'cancelled');
  await postMessage(orderId, 'system', `${reason}. ${paymentStatus === 'refunded' ? 'Your payment has been refunded.' : ''}`.trim());
  return loadOrder(orderId);
}
