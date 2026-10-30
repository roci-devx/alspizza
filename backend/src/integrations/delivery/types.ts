import type { DeliveryQuote, Order, OrderItem, Store } from '@prisma/client';
import type { DeliveryUpdate } from '../../lib/bus.js';

export interface DeliveryAddress {
  line1: string;
  line2?: string | null;
  city: string;
  state: string;
  zip: string;
  lat: number;
  lng: number;
  instructions?: string | null;
}

export const formatAddress = (a: Omit<DeliveryAddress, 'lat' | 'lng'>) =>
  `${a.line1}${a.line2 ? `, ${a.line2}` : ''}, ${a.city}, ${a.state} ${a.zip}`;

export const storeAddress = (s: Store) => `${s.line1}, ${s.city}, ${s.state} ${s.zip}`;

export type ProviderName = 'doordash' | 'uber' | 'own' | 'simulated';

export const ACTIVE_DELIVERY_STATUSES = [
  'created',
  'pending_driver',
  'confirmed',
  'enroute_to_pickup',
  'arrived_at_pickup',
  'picked_up',
  'enroute_to_dropoff',
  'arrived_at_dropoff',
];

export interface QuoteInput {
  externalId: string;
  store: Store;
  dropoff: DeliveryAddress;
  customerName: string;
  customerPhone: string;
  orderValueCents: number;
  readyInMinutes: number;
}

export interface QuoteOutput {
  externalId: string;
  providerFeeCents: number;
  pickupEta?: Date | null;
  dropoffEta?: Date | null;
  expiresAt: Date;
}

export interface DispatchInput {
  order: Order & { items: OrderItem[] };
  store: Store;
  dropoff: DeliveryAddress;
  quote?: DeliveryQuote | null;
  tipCents: number;
  /** Phone the courier will text/call. With Twilio enabled this is our relay number. */
  contactPhone: string;
}

export interface DeliveryProvider {
  readonly name: ProviderName;
  quote(input: QuoteInput): Promise<QuoteOutput>;
  dispatch(input: DispatchInput): Promise<DeliveryUpdate>;
  cancel(externalId: string): Promise<void>;
  fetch?(externalId: string): Promise<DeliveryUpdate | null>;
}
