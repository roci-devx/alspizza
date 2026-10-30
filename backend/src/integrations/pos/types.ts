import type { Order, OrderItem, Store } from '@prisma/client';

export type PosProviderId = 'none' | 'square' | 'clover' | 'toast';

export type PosOrder = Order & { items: OrderItem[] };

export interface PosAdapter {
  readonly id: PosProviderId;
  readonly label: string;
  /** Sends a paid app order into the restaurant's POS / kitchen display. Returns the POS order id. */
  pushOrder(order: PosOrder, store: Store): Promise<string | null>;
}
