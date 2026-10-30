import type { Order } from '@prisma/client';
import type Stripe from 'stripe';
import { config, integrations } from '../config.js';
import { prisma } from '../db.js';
import { badRequest } from '../lib/http.js';
import { capturePaypalOrder, createPaypalOrder } from '../integrations/payments/paypal.js';
import { createCheckoutSession, createPaymentIntent, describeCharge, retrieveIntent, retrieveSession } from '../integrations/payments/stripe.js';
import { loadOrder } from './order-core.js';
import { markPaid } from './orders.service.js';

export type PayProvider = 'stripe' | 'paypal' | 'cash' | 'demo';
export type PayMethod = 'apple_pay' | 'google_pay' | 'card' | 'paypal' | 'cash';

const DEMO_LABEL: Record<PayMethod, string> = {
  apple_pay: 'Apple Pay',
  google_pay: 'Google Pay',
  card: 'Visa •••• 4242',
  paypal: 'PayPal',
  cash: 'Cash at pickup',
};

export function paymentOptions() {
  return {
    stripe: integrations.stripe,
    paypal: integrations.paypal,
    demo: config.demo.payments,
    stripePublishableKey: integrations.stripe ? config.stripe.publishableKey : null,
    appleMerchantId: config.stripe.appleMerchantId,
    merchantDisplayName: config.merchantName,
    merchantCountryCode: 'US',
  };
}

export async function startPayment(order: Order, provider: PayProvider, method: PayMethod, platform: string) {
  if (order.status !== 'pending_payment') throw badRequest('This order is already placed', 'already_paid');

  switch (provider) {
    case 'cash': {
      const store = await prisma.store.findUniqueOrThrow({ where: { id: order.storeId } });
      if (order.fulfillment !== 'pickup' || !store.cashEnabled) throw badRequest('Pay at pickup is not available for this order');
      await markPaid(order.id, { provider: 'cash', method: 'Pay at pickup', status: 'pay_at_pickup' });
      return { status: 'confirmed' as const };
    }
    case 'demo': {
      if (!config.demo.payments) throw badRequest('Demo payments are disabled');
      await markPaid(order.id, { provider: 'demo', method: `${DEMO_LABEL[method] ?? 'Card'} (demo)`, ref: `demo_${Date.now()}` });
      return { status: 'confirmed' as const };
    }
    case 'stripe': {
      if (!integrations.stripe) throw badRequest('Card payments are not configured');
      if (platform === 'web') {
        const session = await createCheckoutSession(order);
        await prisma.order.update({ where: { id: order.id }, data: { paymentProvider: 'stripe', paymentRef: session.id } });
        return { status: 'redirect' as const, url: session.url };
      }
      const intent = await createPaymentIntent(order);
      await prisma.order.update({ where: { id: order.id }, data: { paymentProvider: 'stripe', paymentRef: intent.id } });
      return {
        status: 'requires_action' as const,
        clientSecret: intent.client_secret,
        publishableKey: config.stripe.publishableKey,
        merchantDisplayName: config.merchantName,
        merchantCountryCode: 'US',
        appleMerchantId: config.stripe.appleMerchantId,
        testEnv: config.stripe.secretKey.startsWith('sk_test'),
      };
    }
    case 'paypal': {
      if (!integrations.paypal) throw badRequest('PayPal is not configured');
      const pp = await createPaypalOrder(order);
      await prisma.order.update({ where: { id: order.id }, data: { paymentProvider: 'paypal', paymentRef: pp.id } });
      return { status: 'redirect' as const, url: pp.approvalUrl };
    }
    default:
      throw badRequest('Unknown payment option');
  }
}

/** Called by the app after returning from a payment sheet/redirect; webhooks do the same server-to-server. */
export async function syncPayment(orderId: string) {
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order || order.status !== 'pending_payment' || !order.paymentRef) return loadOrder(orderId);

  if (order.paymentProvider === 'stripe' && integrations.stripe) {
    if (order.paymentRef.startsWith('cs_')) {
      const session = await retrieveSession(order.paymentRef);
      if (session.payment_status === 'paid') {
        const pi = session.payment_intent as Stripe.PaymentIntent | null;
        await markPaid(orderId, { provider: 'stripe', ref: pi?.id ?? session.id, method: describeCharge(pi?.latest_charge) });
      }
    } else if (order.paymentRef.startsWith('pi_')) {
      const pi = await retrieveIntent(order.paymentRef);
      if (pi.status === 'succeeded') await markPaid(orderId, { provider: 'stripe', ref: pi.id, method: describeCharge(pi.latest_charge) });
    }
  }
  if (order.paymentProvider === 'paypal' && integrations.paypal) {
    try {
      const capture = await capturePaypalOrder(order.paymentRef);
      if (capture.completed) await markPaid(orderId, { provider: 'paypal', ref: capture.captureId, method: 'PayPal' });
    } catch {
      // Not approved yet — the shopper is still on PayPal.
    }
  }
  return loadOrder(orderId);
}
