import Stripe from 'stripe';
import type { Order } from '@prisma/client';
import { config } from '../../config.js';

/**
 * Stripe powers cards, Apple Pay and Google Pay.
 *  - iOS/Android: PaymentIntent + native PaymentSheet (flutter_stripe) with wallet buttons.
 *  - Web: hosted Checkout Session (wallets appear automatically in Safari/Chrome).
 */

let client: Stripe | null = null;
export function stripe(): Stripe {
  if (!client) client = new Stripe(config.stripe.secretKey);
  return client;
}

export async function createPaymentIntent(order: Order) {
  return stripe().paymentIntents.create(
    {
      amount: order.totalCents,
      currency: 'usd',
      automatic_payment_methods: { enabled: true },
      description: `Al's Pizza order #${order.number}`,
      receipt_email: order.customerEmail ?? undefined,
      metadata: { orderId: order.id, orderNumber: String(order.number) },
    },
    { idempotencyKey: `pi-${order.id}-${order.totalCents}` },
  );
}

export async function createCheckoutSession(order: Order) {
  return stripe().checkout.sessions.create({
    mode: 'payment',
    line_items: [
      {
        quantity: 1,
        price_data: {
          currency: 'usd',
          unit_amount: order.totalCents,
          product_data: {
            name: `Al's Pizza order #${order.number}`,
            description: `${order.itemsCount} item${order.itemsCount === 1 ? '' : 's'} · ${order.fulfillment === 'delivery' ? 'Delivery' : 'Pickup'}`,
          },
        },
      },
    ],
    customer_email: order.customerEmail ?? undefined,
    success_url: `${config.webAppUrl}/#/order/${order.id}?checkout=success`,
    cancel_url: `${config.webAppUrl}/#/checkout?cancelled=${order.id}`,
    metadata: { orderId: order.id },
    payment_intent_data: { metadata: { orderId: order.id, orderNumber: String(order.number) } },
  });
}

/** Human label for the receipt / dashboard, e.g. "Apple Pay" or "Visa •••• 4242". */
export function describeCharge(charge: Stripe.Charge | string | null | undefined): string {
  if (!charge || typeof charge === 'string') return 'Card';
  const details = charge.payment_method_details;
  const card = details?.card;
  if (card?.wallet?.type === 'apple_pay') return 'Apple Pay';
  if (card?.wallet?.type === 'google_pay') return 'Google Pay';
  if (card) return `${card.brand ? card.brand[0]!.toUpperCase() + card.brand.slice(1) : 'Card'} •••• ${card.last4 ?? ''}`.trim();
  if (details?.type === 'link') return 'Link';
  if (details?.type === 'paypal') return 'PayPal';
  if (details?.type === 'cashapp') return 'Cash App Pay';
  return details?.type ?? 'Card';
}

export async function retrieveIntent(id: string) {
  return stripe().paymentIntents.retrieve(id, { expand: ['latest_charge'] });
}

export async function retrieveSession(id: string) {
  return stripe().checkout.sessions.retrieve(id, { expand: ['payment_intent.latest_charge'] });
}

export async function refund(paymentIntentId: string) {
  return stripe().refunds.create({ payment_intent: paymentIntentId });
}
