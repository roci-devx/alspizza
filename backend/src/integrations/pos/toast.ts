import { config } from '../../config.js';
import { json } from '../../db.js';
import type { DeliveryAddress } from '../delivery/types.js';
import type { PosAdapter } from './types.js';

/**
 * Toast Orders API (requires Toast partner approval).
 * Toast needs Toast menu GUIDs for every item, supplied via TOAST_ITEM_MAP
 * (JSON: {"<menu item slug or id>": "<toast item guid>"}).
 * Docs: https://doc.toasttab.com/doc/devguide/apiOrdersOverview.html
 */

let cached: { token: string; expires: number } | null = null;

async function accessToken(): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const res = await fetch(`${config.toast.host}/authentication/v1/authentication/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ clientId: config.toast.clientId, clientSecret: config.toast.clientSecret, userAccessType: 'TOAST_MACHINE_CLIENT' }),
  });
  const data = (await res.json()) as { token?: { accessToken: string; expiresIn: number } };
  if (!res.ok || !data.token) throw new Error(`Toast auth failed (${res.status})`);
  cached = { token: data.token.accessToken, expires: Date.now() + data.token.expiresIn * 1000 };
  return cached.token;
}

export const toast: PosAdapter = {
  id: 'toast',
  label: 'Toast',

  async pushOrder(order) {
    const itemMap = json.parse<Record<string, string>>(process.env.TOAST_ITEM_MAP, {});
    const missing = order.items.filter((i) => !itemMap[i.menuItemId]);
    if (missing.length) throw new Error(`Map these items to Toast GUIDs (TOAST_ITEM_MAP): ${missing.map((m) => m.name).join(', ')}`);
    const address = json.parse<DeliveryAddress | null>(order.addressJson, null);
    const [firstName, ...rest] = order.customerName.split(' ');
    const customer = { firstName, lastName: rest.join(' ') || '-', phone: order.customerPhone, email: order.customerEmail ?? 'orders@alspizza.com' };

    const res = await fetch(`${config.toast.host}/orders/v2/orders`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        'Toast-Restaurant-External-ID': config.toast.restaurantGuid,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        entityType: 'Order',
        externalId: order.id,
        diningOption: {
          guid: order.fulfillment === 'delivery' ? config.toast.deliveryDiningOptionGuid : config.toast.takeoutDiningOptionGuid,
          entityType: 'DiningOption',
        },
        deliveryInfo: address
          ? { address1: address.line1, address2: address.line2 ?? undefined, city: address.city, state: address.state, zipCode: address.zip, latitude: address.lat, longitude: address.lng, notes: address.instructions ?? undefined }
          : undefined,
        checks: [
          {
            entityType: 'Check',
            customer,
            selections: order.items.map((i) => ({
              entityType: 'MenuItemSelection',
              item: { guid: itemMap[i.menuItemId], entityType: 'MenuItem' },
              quantity: i.quantity,
              specialRequest: i.summary.slice(0, 255),
            })),
          },
        ],
      }),
    });
    const data = (await res.json().catch(() => ({}))) as { guid?: string; message?: string };
    if (!res.ok || !data.guid) throw new Error(`Toast order failed (${res.status}): ${data.message ?? 'error'}`);
    return data.guid;
  },
};
