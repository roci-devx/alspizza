import crypto from 'node:crypto';
import { config } from '../../config.js';
import { json } from '../../db.js';
import type { DeliveryAddress } from '../delivery/types.js';
import type { PosAdapter, PosOrder } from './types.js';

/**
 * Square Orders API. The order lands in Square POS / KDS as a paid online order
 * with a PICKUP or DELIVERY fulfillment. Payment is recorded as EXTERNAL because
 * the money was collected by Stripe/PayPal in the app.
 * Docs: https://developer.squareup.com/reference/square/orders-api/create-order
 */

async function call<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${config.square.baseUrl}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.square.accessToken}`,
      'Square-Version': config.square.version,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const data = (await res.json().catch(() => ({}))) as { errors?: { detail: string }[] } & Record<string, unknown>;
  if (!res.ok) throw new Error(`Square ${path} → ${res.status}: ${data.errors?.map((e) => e.detail).join('; ') ?? 'error'}`);
  return data as T;
}

const money = (amount: number) => ({ amount, currency: 'USD' });

export const square: PosAdapter = {
  id: 'square',
  label: 'Square',

  async pushOrder(order: PosOrder, store) {
    if (!store.posLocationId) throw new Error('Add your Square location ID in Settings → POS');
    const address = json.parse<DeliveryAddress | null>(order.addressJson, null);
    const recipient = { display_name: order.customerName, phone_number: order.customerPhone, email_address: order.customerEmail ?? undefined };
    const fulfillment =
      order.fulfillment === 'delivery' && address
        ? {
            type: 'DELIVERY',
            state: 'PROPOSED',
            delivery_details: {
              schedule_type: 'ASAP',
              note: address.instructions ?? undefined,
              recipient: {
                ...recipient,
                address: {
                  address_line_1: address.line1,
                  address_line_2: address.line2 ?? undefined,
                  locality: address.city,
                  administrative_district_level_1: address.state,
                  postal_code: address.zip,
                  country: 'US',
                },
              },
            },
          }
        : {
            type: 'PICKUP',
            state: 'PROPOSED',
            pickup_details: {
              schedule_type: 'ASAP',
              pickup_at: (order.estimatedReadyAt ?? new Date()).toISOString(),
              note: order.notes ?? undefined,
              recipient,
            },
          };

    const service_charges = [
      order.deliveryFeeCents > 0 && { name: 'Delivery fee', amount_money: money(order.deliveryFeeCents), calculation_phase: 'TOTAL_PHASE' },
      order.tipCents > 0 && { name: 'Driver tip', amount_money: money(order.tipCents), calculation_phase: 'TOTAL_PHASE' },
    ].filter(Boolean);

    const created = await call<{ order: { id: string; total_money?: { amount: number } } }>('/v2/orders', {
      idempotency_key: `als-${order.id}`,
      order: {
        location_id: store.posLocationId,
        reference_id: `ALS-${order.number}`,
        source: { name: "Al's Pizza App" },
        line_items: order.items.map((i) => ({
          name: i.name,
          quantity: String(i.quantity),
          note: i.summary.slice(0, 500),
          base_price_money: money(i.unitPriceCents),
        })),
        discounts: order.discountCents > 0 ? [{ uid: 'promo', name: order.promoCode ?? 'Promo', amount_money: money(order.discountCents), scope: 'ORDER' }] : undefined,
        taxes: [{ uid: 'sales-tax', name: 'Sales tax', percentage: (store.taxRate * 100).toFixed(3), scope: 'ORDER' }],
        service_charges: service_charges.length ? service_charges : undefined,
        fulfillments: [fulfillment],
        metadata: { als_order_id: order.id },
      },
    });

    if (order.paymentStatus === 'paid') {
      await call('/v2/payments', {
        idempotency_key: crypto.createHash('sha256').update(`als-pay-${order.id}`).digest('hex').slice(0, 40),
        source_id: 'EXTERNAL',
        external_details: { type: 'OTHER', source: `Al's Pizza App · ${order.paymentMethod ?? order.paymentProvider}` },
        amount_money: money(created.order.total_money?.amount ?? order.totalCents),
        order_id: created.order.id,
        location_id: store.posLocationId,
      });
    }
    return created.order.id;
  },
};

/** Square webhooks (order.fulfillment.updated) let the kitchen drive app status from Square KDS. */
export function isValidSquareWebhook(rawBody: Buffer, signature: string | undefined, notificationUrl: string): boolean {
  if (!config.square.webhookSignatureKey) return !config.isProd;
  if (!signature) return false;
  const expected = crypto.createHmac('sha256', config.square.webhookSignatureKey).update(notificationUrl + rawBody.toString('utf8')).digest('base64');
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export const SQUARE_FULFILLMENT_TO_STATUS: Record<string, string> = {
  RESERVED: 'preparing',
  PREPARED: 'ready',
  COMPLETED: 'completed',
  CANCELED: 'cancelled',
};
