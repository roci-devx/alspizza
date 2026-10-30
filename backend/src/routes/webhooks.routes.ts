import crypto from 'node:crypto';
import express, { Router } from 'express';
import { config, integrations } from '../config.js';
import { prisma } from '../db.js';
import { bus } from '../lib/bus.js';
import { doordashToUpdate } from '../integrations/delivery/doordash.js';
import { ACTIVE_DELIVERY_STATUSES } from '../integrations/delivery/types.js';
import { uberToUpdate } from '../integrations/delivery/uber.js';
import { escapeXml, isValidTwilioRequest, twiml } from '../integrations/messaging/twilio.js';
import { capturePaypalOrder } from '../integrations/payments/paypal.js';
import { describeCharge, retrieveIntent, stripe } from '../integrations/payments/stripe.js';
import { isValidSquareWebhook, SQUARE_FULFILLMENT_TO_STATUS } from '../integrations/pos/square.js';
import { setStatus } from '../services/order-core.js';
import { markPaid } from '../services/orders.service.js';

export const webhookRoutes = Router();

// ── Stripe ────────────────────────────────────────────────────────────────────
webhookRoutes.post('/webhooks/stripe', async (req, res) => {
  if (!integrations.stripe || !config.stripe.webhookSecret || !req.rawBody) {
    res.status(400).json({ error: 'Stripe webhooks are not configured' });
    return;
  }
  let event;
  try {
    event = stripe().webhooks.constructEvent(req.rawBody, String(req.headers['stripe-signature']), config.stripe.webhookSecret);
  } catch {
    res.status(400).json({ error: 'Bad signature' });
    return;
  }
  if (event.type === 'payment_intent.succeeded') {
    const pi = event.data.object;
    if (pi.metadata?.orderId) {
      const full = await retrieveIntent(pi.id);
      await markPaid(pi.metadata.orderId, { provider: 'stripe', ref: pi.id, method: describeCharge(full.latest_charge) });
    }
  } else if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    if (session.payment_status === 'paid' && session.metadata?.orderId) {
      const piId = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id;
      const pi = piId ? await retrieveIntent(piId) : null;
      await markPaid(session.metadata.orderId, { provider: 'stripe', ref: piId ?? session.id, method: describeCharge(pi?.latest_charge) });
    }
  } else if (event.type === 'charge.refunded') {
    const charge = event.data.object;
    const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : charge.payment_intent?.id;
    if (piId) await prisma.order.updateMany({ where: { paymentRef: piId }, data: { paymentStatus: 'refunded' } });
  }
  res.json({ received: true });
});

// ── DoorDash Drive ────────────────────────────────────────────────────────────
webhookRoutes.post('/webhooks/doordash', (req, res) => {
  if (config.doordash.webhookAuth && req.headers.authorization !== config.doordash.webhookAuth) {
    res.status(401).end();
    return;
  }
  const body = req.body as { external_delivery_id?: string } | undefined;
  if (body?.external_delivery_id) bus.emit('delivery.update', doordashToUpdate(body as Parameters<typeof doordashToUpdate>[0]));
  res.json({ ok: true });
});

// ── Uber Direct ───────────────────────────────────────────────────────────────
webhookRoutes.post('/webhooks/uber', (req, res) => {
  if (config.uber.webhookSigningKey) {
    const signature = String(req.headers['x-uber-signature'] ?? req.headers['x-postmates-signature'] ?? '');
    const expected = crypto.createHmac('sha256', config.uber.webhookSigningKey).update(req.rawBody ?? Buffer.alloc(0)).digest('hex');
    if (signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
      res.status(401).end();
      return;
    }
  }
  const body = req.body as { delivery_id?: string; status?: string; data?: Record<string, unknown> & { id?: string; status?: string } };
  const id = body.delivery_id ?? body.data?.id;
  if (id) bus.emit('delivery.update', uberToUpdate({ ...(body.data ?? {}), id, status: body.status ?? body.data?.status } as Parameters<typeof uberToUpdate>[0]));
  res.json({ ok: true });
});

// ── Twilio (driver chat relay) ────────────────────────────────────────────────
const form = express.urlencoded({ extended: false });

webhookRoutes.post('/webhooks/twilio/sms', form, async (req, res) => {
  const params = req.body as Record<string, string>;
  if (!isValidTwilioRequest(`${config.publicApiUrl}${req.originalUrl}`, params, req.headers['x-twilio-signature'] as string | undefined)) {
    res.status(403).end();
    return;
  }
  const delivery = await prisma.delivery.findFirst({
    where: { driverPhone: params.From, status: { in: ACTIVE_DELIVERY_STATUSES } },
    orderBy: { updatedAt: 'desc' },
  });
  if (delivery && params.Body) bus.emit('chat.driver', { orderId: delivery.orderId, body: params.Body, via: 'sms' });
  res.type('text/xml').send(twiml());
});

webhookRoutes.post('/webhooks/twilio/voice', form, async (req, res) => {
  const params = req.body as Record<string, string>;
  if (!isValidTwilioRequest(`${config.publicApiUrl}${req.originalUrl}`, params, req.headers['x-twilio-signature'] as string | undefined)) {
    res.status(403).end();
    return;
  }
  const caller = params.From ?? '';
  const active = { status: { in: ACTIVE_DELIVERY_STATUSES } };
  const asDriver = await prisma.delivery.findFirst({ where: { driverPhone: caller, ...active }, include: { order: true }, orderBy: { updatedAt: 'desc' } });
  const asCustomer = asDriver
    ? null
    : await prisma.delivery.findFirst({ where: { order: { customerPhone: caller }, driverPhone: { not: null }, ...active }, orderBy: { updatedAt: 'desc' } });
  const dial = (to: string) => `<Dial callerId="${escapeXml(config.twilio.fromNumber)}">${escapeXml(to)}</Dial>`;
  if (asDriver) res.type('text/xml').send(twiml(dial(asDriver.order.customerPhone)));
  else if (asCustomer?.driverPhone) res.type('text/xml').send(twiml(`<Say>Connecting you to your Al's Pizza driver.</Say>${dial(asCustomer.driverPhone)}`));
  else res.type('text/xml').send(twiml("<Say>Thanks for calling Al's Pizza. There is no active delivery for this number.</Say>"));
});

// ── Square (POS → app status sync) ────────────────────────────────────────────
webhookRoutes.post('/webhooks/square', async (req, res) => {
  const url = `${config.publicApiUrl}${req.originalUrl}`;
  if (!req.rawBody || !isValidSquareWebhook(req.rawBody, req.headers['x-square-hmacsha256-signature'] as string | undefined, url)) {
    res.status(403).end();
    return;
  }
  const body = req.body as {
    type?: string;
    data?: { object?: { order_fulfillment_updated?: { order_id?: string; fulfillment_update?: { new_state?: string }[] } } };
  };
  const update = body.data?.object?.order_fulfillment_updated;
  const state = update?.fulfillment_update?.at(-1)?.new_state;
  if (body.type === 'order.fulfillment.updated' && update?.order_id && state && SQUARE_FULFILLMENT_TO_STATUS[state]) {
    const order = await prisma.order.findFirst({ where: { posOrderId: update.order_id } });
    if (order) await setStatus(order.id, SQUARE_FULFILLMENT_TO_STATUS[state]!).catch((err) => console.warn('[square] status skipped', err));
  }
  res.json({ ok: true });
});

// ── PayPal return URLs (shopper's browser lands here after approving) ─────────
const returnPage = (title: string, message: string, deepLink: string) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · Al's Pizza</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#FCF7EC;font-family:system-ui,-apple-system,Segoe UI,sans-serif;color:#5A210F;text-align:center}
main{padding:32px;max-width:360px}h1{font-size:28px;margin:0 0 8px}p{color:#7A5A48;line-height:1.5}
a{display:inline-block;margin-top:20px;background:#E8962A;color:#5A210F;font-weight:800;padding:14px 28px;border-radius:999px;text-decoration:none}</style></head>
<body><main><div style="font-size:56px">🍕</div><h1>${title}</h1><p>${message}</p><a href="${deepLink}">Back to Al's Pizza</a></main></body></html>`;

webhookRoutes.get('/payments/paypal/return', async (req, res) => {
  const orderId = String(req.query.orderId ?? '');
  const token = String(req.query.token ?? '');
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) {
    res.status(404).send('Order not found');
    return;
  }
  let ok = order.paymentStatus === 'paid';
  if (!ok && integrations.paypal) {
    try {
      const capture = await capturePaypalOrder(token || order.paymentRef || '');
      if (capture.completed) {
        await markPaid(order.id, { provider: 'paypal', ref: capture.captureId, method: 'PayPal' });
        ok = true;
      }
    } catch (err) {
      console.error('[paypal] capture failed', err);
    }
  }
  if (order.platform === 'web') {
    res.redirect(`${config.webAppUrl}/#/order/${order.id}${ok ? '?paid=paypal' : ''}`);
    return;
  }
  res
    .type('html')
    .send(
      ok
        ? returnPage('Payment complete!', `Order #${order.number} is headed to the kitchen. You can close this window.`, `alspizza://app/order/${order.id}`)
        : returnPage('Payment not finished', 'PayPal did not confirm the payment. Head back to the app to try again.', 'alspizza://app/checkout'),
    );
});

webhookRoutes.get('/payments/paypal/cancel', async (req, res) => {
  const orderId = String(req.query.orderId ?? '');
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (order?.platform === 'web') {
    res.redirect(`${config.webAppUrl}/#/checkout?cancelled=${orderId}`);
    return;
  }
  res.type('html').send(returnPage('Payment cancelled', 'No charge was made. Head back to the app to pick another way to pay.', 'alspizza://app/checkout'));
});
