import type { DeliveryUpdate } from '../../lib/bus.js';
import { driveMinutes, haversineMiles } from '../../lib/geo.js';
import type { DeliveryProvider, DispatchInput, QuoteInput, QuoteOutput } from './types.js';

/**
 * In-house drivers. Staff assign a driver and move the delivery along from the
 * owner dashboard (a driver app can plug into the same endpoints later).
 */
export const ownDrivers: DeliveryProvider = {
  name: 'own',

  async quote(input: QuoteInput): Promise<QuoteOutput> {
    const miles = haversineMiles(input.store, input.dropoff);
    const readyAt = Date.now() + input.readyInMinutes * 60_000;
    return {
      externalId: input.externalId,
      providerFeeCents: 0,
      pickupEta: new Date(readyAt),
      dropoffEta: new Date(readyAt + driveMinutes(miles) * 60_000),
      expiresAt: new Date(Date.now() + 30 * 60_000),
    };
  },

  async dispatch(input: DispatchInput): Promise<DeliveryUpdate> {
    return { externalId: `OWN-${input.order.number}-${Date.now().toString(36)}`, status: 'pending_driver' };
  },

  async cancel() {},
};
