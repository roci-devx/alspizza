import { EventEmitter } from 'node:events';

export interface DeliveryUpdate {
  externalId: string;
  status?: string;
  providerFeeCents?: number;
  trackingUrl?: string | null;
  driverName?: string | null;
  driverPhone?: string | null;
  driverVehicle?: string | null;
  driverLat?: number | null;
  driverLng?: number | null;
  pickupEta?: Date | null;
  dropoffEta?: Date | null;
  supportRef?: string | null;
  raw?: unknown;
}

interface BusEvents {
  'delivery.update': [DeliveryUpdate];
  'chat.customer': [{ orderId: string; body: string }];
  'chat.driver': [{ orderId: string; body: string; via: 'app' | 'sms' }];
}

/** In-process event bus so integrations (simulator, webhooks, pollers) stay decoupled from services. */
export const bus = new EventEmitter<BusEvents>();
bus.setMaxListeners(50);
