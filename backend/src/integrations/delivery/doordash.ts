import { config } from '../../config.js';
import type { DeliveryUpdate } from '../../lib/bus.js';
import { toE164 } from '../../lib/geo.js';
import { signJwt } from '../../lib/jwt.js';
import { formatAddress, storeAddress, type DeliveryProvider, type DispatchInput, type QuoteInput, type QuoteOutput } from './types.js';

/**
 * DoorDash Drive v2 (white-label on-demand delivery).
 * Docs: https://developer.doordash.com/en-US/docs/drive/reference/
 * Flow: POST /quotes (fee + ETA, valid 5 min) → POST /quotes/{id}/accept on payment → webhooks + polling for status/GPS.
 * `dropoff_contact_send_notifications: false` keeps DoorDash from texting the customer — Al's app owns the experience.
 */

const BASE = 'https://openapi.doordash.com/drive/v2';

function token(): string {
  const now = Math.floor(Date.now() / 1000);
  return signJwt(
    { aud: 'doordash', iss: config.doordash.developerId, kid: config.doordash.keyId, exp: now + 300, iat: now },
    Buffer.from(config.doordash.signingSecret, 'base64'),
    { 'dd-ver': 'DD-JWT-V1' },
  );
}

async function call<T>(method: 'GET' | 'POST' | 'PUT' | 'PATCH', path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  if (!res.ok) {
    const detail = (data.message as string) ?? (data.field_errors ? JSON.stringify(data.field_errors) : text);
    throw new Error(`DoorDash ${method} ${path} → ${res.status}: ${detail}`);
  }
  return data as T;
}

interface DDDelivery {
  external_delivery_id: string;
  delivery_status?: string;
  fee?: number;
  tracking_url?: string;
  support_reference?: string;
  dasher_name?: string;
  dasher_dropoff_phone_number?: string;
  dasher_location?: { lat: number; lng: number };
  dasher_vehicle_make?: string;
  dasher_vehicle_model?: string;
  dasher_vehicle_year?: string;
  pickup_time_estimated?: string;
  dropoff_time_estimated?: string;
  expires_at?: string;
}

const STATUS: Record<string, string> = {
  quote: 'quote',
  created: 'created',
  confirmed: 'confirmed',
  enroute_to_pickup: 'enroute_to_pickup',
  arrived_at_pickup: 'arrived_at_pickup',
  picked_up: 'picked_up',
  enroute_to_dropoff: 'enroute_to_dropoff',
  arrived_at_dropoff: 'arrived_at_dropoff',
  delivered: 'delivered',
  enroute_to_return: 'returned',
  arrived_at_return: 'returned',
  returned: 'returned',
  cancelled: 'cancelled',
};

const EVENT_STATUS: Record<string, string> = {
  DASHER_CONFIRMED: 'confirmed',
  DASHER_ENROUTE_TO_PICKUP: 'enroute_to_pickup',
  DASHER_CONFIRMED_PICKUP_ARRIVAL: 'arrived_at_pickup',
  DASHER_PICKED_UP: 'picked_up',
  DASHER_ENROUTE_TO_DROPOFF: 'enroute_to_dropoff',
  DASHER_CONFIRMED_DROPOFF_ARRIVAL: 'arrived_at_dropoff',
  DASHER_DROPPED_OFF: 'delivered',
  DELIVERY_CANCELLED: 'cancelled',
  DELIVERY_RETURN_INITIALIZED: 'returned',
  DASHER_CONFIRMED_RETURN_ARRIVAL: 'returned',
  DELIVERY_RETURNED: 'returned',
};

export function doordashToUpdate(d: DDDelivery & { event_name?: string }): DeliveryUpdate {
  const status = (d.event_name && EVENT_STATUS[d.event_name]) || (d.delivery_status && STATUS[d.delivery_status]) || undefined;
  const vehicle = [d.dasher_vehicle_year, d.dasher_vehicle_make, d.dasher_vehicle_model].filter(Boolean).join(' ');
  return {
    externalId: d.external_delivery_id,
    status,
    providerFeeCents: d.fee,
    trackingUrl: d.tracking_url,
    supportRef: d.support_reference,
    driverName: d.dasher_name,
    driverPhone: d.dasher_dropoff_phone_number,
    driverVehicle: vehicle || undefined,
    driverLat: d.dasher_location?.lat,
    driverLng: d.dasher_location?.lng,
    pickupEta: d.pickup_time_estimated ? new Date(d.pickup_time_estimated) : undefined,
    dropoffEta: d.dropoff_time_estimated ? new Date(d.dropoff_time_estimated) : undefined,
    raw: d,
  };
}

function splitName(full: string) {
  const [given, ...rest] = full.trim().split(/\s+/);
  return { given: given || 'Customer', family: rest.join(' ') || undefined };
}

function deliveryBody(input: QuoteInput | DispatchInput, externalId: string, contactPhone: string) {
  const store = input.store;
  const name = splitName('customerName' in input ? input.customerName : input.order.customerName);
  return {
    external_delivery_id: externalId,
    pickup_address: storeAddress(store),
    pickup_business_name: store.name,
    pickup_phone_number: toE164(store.phone),
    pickup_instructions: 'Online order — ask the counter for the order number on the ticket.',
    dropoff_address: formatAddress(input.dropoff),
    dropoff_phone_number: toE164(contactPhone),
    dropoff_instructions: input.dropoff.instructions ?? undefined,
    dropoff_contact_given_name: name.given,
    dropoff_contact_family_name: name.family,
    dropoff_contact_send_notifications: false,
    order_value: 'orderValueCents' in input ? input.orderValueCents : input.order.subtotalCents,
    currency: 'USD',
  };
}

export const doordash: DeliveryProvider = {
  name: 'doordash',

  async quote(input: QuoteInput): Promise<QuoteOutput> {
    const res = await call<DDDelivery>('POST', '/quotes', deliveryBody(input, input.externalId, input.customerPhone));
    return {
      externalId: res.external_delivery_id,
      providerFeeCents: res.fee ?? 0,
      pickupEta: res.pickup_time_estimated ? new Date(res.pickup_time_estimated) : null,
      dropoffEta: res.dropoff_time_estimated ? new Date(res.dropoff_time_estimated) : null,
      expiresAt: res.expires_at ? new Date(res.expires_at) : new Date(Date.now() + 5 * 60_000),
    };
  },

  async dispatch(input: DispatchInput): Promise<DeliveryUpdate> {
    const quote = input.quote;
    const items = input.order.items.map((i) => ({ name: i.name, quantity: i.quantity, description: i.summary.slice(0, 120) }));
    if (quote && quote.expiresAt.getTime() - Date.now() > 15_000) {
      try {
        const accepted = await call<DDDelivery>('POST', `/quotes/${encodeURIComponent(quote.externalId)}/accept`, {
          tip: input.tipCents,
          dropoff_phone_number: toE164(input.contactPhone),
        });
        return doordashToUpdate(accepted);
      } catch (err) {
        console.warn('[doordash] quote accept failed, creating a fresh delivery', err);
      }
    }
    const externalId = `ALS-${input.order.number}-${Date.now().toString(36)}`;
    const created = await call<DDDelivery>('POST', '/deliveries', {
      ...deliveryBody(input, externalId, input.contactPhone),
      tip: input.tipCents,
      items,
    });
    return doordashToUpdate(created);
  },

  async cancel(externalId: string) {
    await call('PUT', `/deliveries/${encodeURIComponent(externalId)}/cancel`);
  },

  async fetch(externalId: string) {
    const d = await call<DDDelivery>('GET', `/deliveries/${encodeURIComponent(externalId)}`);
    return doordashToUpdate(d);
  },
};
