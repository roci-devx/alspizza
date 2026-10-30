import type { Store } from '@prisma/client';
import { integrations } from '../../config.js';
import { clover } from './clover.js';
import { square } from './square.js';
import { toast } from './toast.js';
import type { PosAdapter, PosOrder, PosProviderId } from './types.js';

/** "none" = the owner dashboard's Live Orders board is the kitchen display. */
const none: PosAdapter = {
  id: 'none',
  label: 'Al’s dashboard (no POS)',
  async pushOrder() {
    return null;
  },
};

const adapters: Record<PosProviderId, PosAdapter> = { none, square, clover, toast };

export const POS_OPTIONS = [
  { id: 'none', label: 'No POS — use the dashboard as kitchen display', configured: true },
  { id: 'square', label: 'Square', configured: integrations.square },
  { id: 'clover', label: 'Clover', configured: integrations.clover },
  { id: 'toast', label: 'Toast (partner API)', configured: integrations.toast },
];

export function posFor(store: Store): PosAdapter {
  const id = store.posProvider as PosProviderId;
  if (id !== 'none' && !integrations[id]) return none;
  return adapters[id] ?? none;
}

export async function pushOrderToPos(order: PosOrder, store: Store) {
  const adapter = posFor(store);
  return { provider: adapter.id, posOrderId: await adapter.pushOrder(order, store) };
}
