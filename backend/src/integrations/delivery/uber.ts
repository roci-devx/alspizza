import { config } from '../../config.js';
import type { DeliveryUpdate } from '../../lib/bus.js';
import { toE164 } from '../../lib/geo.js';
import type { DeliveryProvider, DispatchInput, QuoteInput, QuoteOutput } from './types.js';

/**
 * Uber Direct (DaaS) — fallback courier network.
 * Docs: https://developer.uber.com/docs/deliveries/overview
 * Auth is OAuth client-credentials with the `eats.deliveries` scope.
 */

const API = () => `https://api.uber.com/v1/customers/${config.uber.customerId}`;
let cached: { token: string; expires: number } | null = null;

async function accessToken(): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const res = await fetch('https://auth.uber.com/oauth/v2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: config.uber.clientId,
      client_secret: config.uber.clientSecret,
      grant_type: 'client_credentials',
      scope: 'eats.deliveries',
    }).toString(),
  });
  const data = (await res.json()) as { access_token?: string; expires_in?: number; error?: string };
  if (!res.ok || !data.access_token) throw new Error(`Uber auth failed: ${data.error ?? res.status}`);
  cached = { token: data.access_token, expires: Date.now() + (data.expires_in ?? 3600) * 1000 };
  return cached.token;
}

async function call<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${API()}${path}`, {
    method,
    headers: { Authorization: `Bearer ${await accessToken()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) throw new Error(`Uber ${method} ${path} → ${res.status}: ${(data.message as string) ?? JSON.stringify(data)}`);
  return data as T;
}

const structuredAddress = (a: { line1: string; line2?: string | null; city: string; state: string; zip: string }) =>
  JSON.stringify({ street_address: [a.line1, a.line2].filter(Boolean), city: a.city, state: a.state, zip_code: a.zip, country: 'US' });

const STATUS: Record<string, string> = {
  pending: 'created',
  pickup: 'enroute_to_pickup',
  pickup_complete: 'picked_up',
  dropoff: 'enroute_to_dropoff',
  delivered: 'delivered',
  canceled: 'cancelled',
  returned: 'returned',
};

interface UberDelivery {
  id: string;
  status?: string;
  fee?: number;
  tracking_url?: string;
  pickup_eta?: string;
  dropoff_eta?: string;
  courier?: { name?: string; phone_number?: string; vehicle_type?: string; vehicle_make?: string; vehicle_model?: string; location?: { lat: number; lng: number } };
}

export function uberToUpdate(d: UberDelivery): DeliveryUpdate {
  return {
    externalId: d.id,
    status: d.status ? STATUS[d.status] : undefined,
    providerFeeCents: d.fee,
    trackingUrl: d.tracking_url,
    driverName: d.courier?.name,
    driverPhone: d.courier?.phone_number,
    driverVehicle: [d.courier?.vehicle_make, d.courier?.vehicle_model].filter(Boolean).join(' ') || d.courier?.vehicle_type,
    driverLat: d.courier?.location?.lat,
    driverLng: d.courier?.location?.lng,
    pickupEta: d.pickup_eta ? new Date(d.pickup_eta) : undefined,
    dropoffEta: d.dropoff_eta ? new Date(d.dropoff_eta) : undefined,
    raw: d,
  };
}

export const uber: DeliveryProvider = {
  name: 'uber',

  async quote(input: QuoteInput): Promise<QuoteOutput> {
    const s = input.store;
    const q = await call<{ id: string; fee: number; dropoff_eta?: string; expires?: string }>('POST', '/delivery_quotes', {
      pickup_address: structuredAddress(s),
      dropoff_address: structuredAddress(input.dropoff),
      pickup_latitude: s.lat,
      pickup_longitude: s.lng,
      dropoff_latitude: input.dropoff.lat,
      dropoff_longitude: input.dropoff.lng,
      pickup_phone_number: toE164(s.phone),
      dropoff_phone_number: toE164(input.customerPhone),
      manifest_total_value: input.orderValueCents,
    });
    return {
      externalId: q.id,
      providerFeeCents: q.fee,
      dropoffEta: q.dropoff_eta ? new Date(q.dropoff_eta) : null,
      expiresAt: q.expires ? new Date(q.expires) : new Date(Date.now() + 10 * 60_000),
    };
  },

  async dispatch(input: DispatchInput): Promise<DeliveryUpdate> {
    const s = input.store;
    const d = await call<UberDelivery>('POST', '/deliveries', {
      quote_id: input.quote?.provider === 'uber' ? input.quote.externalId : undefined,
      pickup_name: s.name,
      pickup_address: structuredAddress(s),
      pickup_phone_number: toE164(s.phone),
      pickup_latitude: s.lat,
      pickup_longitude: s.lng,
      pickup_notes: `Al's online order #${input.order.number}`,
      dropoff_name: input.order.customerName,
      dropoff_address: structuredAddress(input.dropoff),
      dropoff_phone_number: toE164(input.contactPhone),
      dropoff_latitude: input.dropoff.lat,
      dropoff_longitude: input.dropoff.lng,
      dropoff_notes: input.dropoff.instructions ?? undefined,
      manifest_items: input.order.items.map((i) => ({ name: i.name, quantity: i.quantity, size: 'small' })),
      manifest_total_value: input.order.subtotalCents,
      external_id: input.order.id,
      tip: input.tipCents,
    });
    return uberToUpdate(d);
  },

  async cancel(externalId: string) {
    await call('POST', `/deliveries/${encodeURIComponent(externalId)}/cancel`);
  },

  async fetch(externalId: string) {
    return uberToUpdate(await call<UberDelivery>('GET', `/deliveries/${encodeURIComponent(externalId)}`));
  },
};
