import { config } from '../../config.js';
import type { PosAdapter } from './types.js';

/**
 * Clover Atomic Order API — creates an order with custom line items that prints
 * on Clover devices/kitchen printers.
 * Docs: https://docs.clover.com/dev/reference/ordercreateatomicorder
 */
export const clover: PosAdapter = {
  id: 'clover',
  label: 'Clover',

  async pushOrder(order) {
    const res = await fetch(`${config.clover.baseUrl}/v3/merchants/${config.clover.merchantId}/atomic_order/orders`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.clover.accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        orderCart: {
          title: `ALS-${order.number}`,
          note: `${order.fulfillment.toUpperCase()} · ${order.customerName} ${order.customerPhone}${order.notes ? ` · ${order.notes}` : ''}`,
          lineItems: order.items.flatMap((i) =>
            Array.from({ length: i.quantity }, () => ({ name: i.name, price: i.unitPriceCents, note: i.summary.slice(0, 255) })),
          ),
          discounts: order.discountCents > 0 ? [{ name: order.promoCode ?? 'Promo', amount: -order.discountCents }] : [],
        },
      }),
    });
    const data = (await res.json().catch(() => ({}))) as { id?: string; message?: string };
    if (!res.ok || !data.id) throw new Error(`Clover order failed (${res.status}): ${data.message ?? 'error'}`);
    return data.id;
  },
};
