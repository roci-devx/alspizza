import type { Category, ChatMessage, Delivery, MenuItem, Order, OrderItem, Store } from '@prisma/client';
import { config, integrations } from '../config.js';
import { json } from '../db.js';
import { haversineMiles, type LatLng } from '../lib/geo.js';
import { hoursLabel, isOpenAt, type WeeklyHours } from '../lib/time.js';

export type OrderFull = Order & { items: OrderItem[]; delivery: Delivery | null; store: Store };
export type View = 'customer' | 'owner';

export function serializeStore(store: Store, near?: LatLng | null) {
  const hours = json.parse<WeeklyHours>(store.hoursJson, {});
  const distanceMiles = near ? Math.round(haversineMiles(near, store) * 10) / 10 : null;
  return {
    id: store.id,
    slug: store.slug,
    name: store.name,
    phone: store.phone,
    address: { line1: store.line1, city: store.city, state: store.state, zip: store.zip },
    lat: store.lat,
    lng: store.lng,
    timezone: store.timezone,
    isOpen: isOpenAt(hours, store.timezone),
    hoursToday: hoursLabel(hours, store.timezone),
    acceptingOrders: store.acceptingOrders,
    pickupEnabled: store.pickupEnabled,
    deliveryEnabled: store.deliveryEnabled,
    cashEnabled: store.cashEnabled,
    taxRate: store.taxRate,
    minDeliveryCents: store.minDeliveryCents,
    deliveryRadiusMiles: store.deliveryRadiusMiles,
    distanceMiles,
    deliversToYou: distanceMiles == null ? null : distanceMiles <= store.deliveryRadiusMiles,
  };
}

export function serializeMenuItem(item: MenuItem & { category?: Category }) {
  return {
    id: item.id,
    slug: item.slug,
    categoryId: item.categoryId,
    categorySlug: item.category?.slug,
    name: item.name,
    description: item.description,
    kind: item.kind,
    priceCents: item.priceCents,
    calories: item.calories,
    imageUrl: item.imageUrl,
    art: item.art,
    tags: item.tags ? item.tags.split(',').filter(Boolean) : [],
    isAvailable: item.isAvailable,
    prepMinutes: item.prepMinutes,
    config: json.parse(item.configJson, {}),
  };
}

export function serializeMessage(m: ChatMessage) {
  return { id: m.id, orderId: m.orderId, sender: m.sender, body: m.body, via: m.via, createdAt: m.createdAt };
}

/** The courier network is an implementation detail customers never see. */
function customerDriverPhone(d: Delivery): string | null {
  if (!d.driverPhone) return null;
  if (integrations.twilio && (d.provider === 'doordash' || d.provider === 'uber')) return config.twilio.fromNumber;
  return d.driverPhone;
}

export function serializeOrder(o: OrderFull, view: View) {
  const owner = view === 'owner';
  return {
    id: o.id,
    number: o.number,
    status: o.status,
    fulfillment: o.fulfillment,
    storeId: o.storeId,
    store: {
      id: o.store.id,
      name: o.store.name,
      phone: o.store.phone,
      address: { line1: o.store.line1, city: o.store.city, state: o.store.state, zip: o.store.zip },
      lat: o.store.lat,
      lng: o.store.lng,
    },
    customerName: o.customerName,
    customerPhone: o.customerPhone,
    customerEmail: o.customerEmail,
    address: json.parse(o.addressJson, null),
    items: o.items.map((i) => ({
      id: i.id,
      menuItemId: i.menuItemId,
      name: i.name,
      kind: i.kind,
      art: i.art,
      quantity: i.quantity,
      unitPriceCents: i.unitPriceCents,
      totalCents: i.totalCents,
      summary: i.summary,
      config: json.parse(i.configJson, {}),
    })),
    itemsCount: o.itemsCount,
    subtotalCents: o.subtotalCents,
    discountCents: o.discountCents,
    deliveryFeeCents: o.deliveryFeeCents,
    taxCents: o.taxCents,
    tipCents: o.tipCents,
    totalCents: o.totalCents,
    promoCode: o.promoCode,
    paymentProvider: o.paymentProvider,
    paymentStatus: o.paymentStatus,
    paymentMethod: o.paymentMethod,
    platform: o.platform,
    notes: o.notes,
    createdAt: o.createdAt,
    paidAt: o.paidAt,
    preparingAt: o.preparingAt,
    readyAt: o.readyAt,
    outForDeliveryAt: o.outForDeliveryAt,
    completedAt: o.completedAt,
    cancelledAt: o.cancelledAt,
    estimatedReadyAt: o.estimatedReadyAt,
    estimatedDeliveryAt: o.estimatedDeliveryAt,
    delivery: o.delivery
      ? {
          status: o.delivery.status,
          driverName: o.delivery.driverName,
          driverPhone: owner ? o.delivery.driverPhone : customerDriverPhone(o.delivery),
          driverVehicle: o.delivery.driverVehicle,
          driverLat: o.delivery.driverLat,
          driverLng: o.delivery.driverLng,
          pickupEta: o.delivery.pickupEta,
          dropoffEta: o.delivery.dropoffEta,
          ...(owner
            ? {
                provider: o.delivery.provider,
                externalId: o.delivery.externalId,
                providerFeeCents: o.delivery.providerFeeCents,
                trackingUrl: o.delivery.trackingUrl,
                supportRef: o.delivery.supportRef,
              }
            : {}),
        }
      : null,
    ...(owner
      ? {
          customerKey: o.customerKey,
          promoChannel: o.promoChannel,
          posProvider: o.posProvider,
          posOrderId: o.posOrderId,
          posError: o.posError,
          paymentRef: o.paymentRef,
        }
      : {}),
  };
}
