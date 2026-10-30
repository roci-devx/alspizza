import type { Order, OrderItem } from '@prisma/client';
import { prisma } from '../db.js';
import { addDays, daysBetween, localDate, localHour, startOfLocalDay } from '../lib/time.js';
import { ACTIVE_ORDER_STATUSES } from './order-core.js';

export const PAID = ['paid', 'pay_at_pickup'];

/** Net sales = food + delivery fees − discounts. Tax and driver tips are pass-through money. */
export const netSales = (o: Pick<Order, 'totalCents' | 'taxCents' | 'tipCents'>) => o.totalCents - o.taxCents - o.tipCents;

type OrderRow = Order & { items?: OrderItem[]; delivery?: { provider: string } | null };

export interface RangeSpec {
  storeIds: string[];
  timezone: string;
  from: string;
  to: string;
}

async function ordersBetween(storeIds: string[], start: Date, end: Date, withItems: boolean): Promise<OrderRow[]> {
  return prisma.order.findMany({
    where: { storeId: { in: storeIds }, createdAt: { gte: start, lt: end }, status: { not: 'pending_payment' } },
    include: withItems ? { items: true, delivery: { select: { provider: true } } } : undefined,
    orderBy: { createdAt: 'asc' },
  });
}

function summarize(orders: OrderRow[], firstOrderAt: Map<string, Date>, rangeStart: Date) {
  const counted = orders.filter((o) => o.status !== 'cancelled' && PAID.includes(o.paymentStatus));
  const sum = (f: (o: OrderRow) => number) => counted.reduce((s, o) => s + f(o), 0);
  const customers = new Map<string, number>();
  for (const o of counted) customers.set(o.customerKey, (customers.get(o.customerKey) ?? 0) + 1);
  let returning = 0;
  let fresh = 0;
  for (const [key, count] of customers) {
    const first = firstOrderAt.get(key);
    if ((first && first < rangeStart) || count > 1) returning++;
    else fresh++;
  }
  const net = sum(netSales);
  return {
    orders: counted.length,
    netSalesCents: net,
    grossSalesCents: sum((o) => o.subtotalCents),
    discountCents: sum((o) => o.discountCents),
    deliveryFeeCents: sum((o) => o.deliveryFeeCents),
    tipCents: sum((o) => o.tipCents),
    taxCents: sum((o) => o.taxCents),
    totalCollectedCents: sum((o) => o.totalCents),
    aovCents: counted.length ? Math.round(net / counted.length) : 0,
    cancelled: orders.filter((o) => o.status === 'cancelled').length,
    pickup: counted.filter((o) => o.fulfillment === 'pickup').length,
    delivery: counted.filter((o) => o.fulfillment === 'delivery').length,
    customers: customers.size,
    newCustomers: fresh,
    returningCustomers: returning,
    repeatRate: customers.size ? returning / customers.size : 0,
    counted,
  };
}

async function firstOrders(storeIds: string[]) {
  const rows = await prisma.order.groupBy({
    by: ['customerKey'],
    where: { storeId: { in: storeIds }, paymentStatus: { in: PAID }, status: { not: 'cancelled' } },
    _min: { createdAt: true },
  });
  return new Map(rows.map((r) => [r.customerKey, r._min.createdAt!]));
}

const pct = (cur: number, prev: number) => (prev ? (cur - prev) / prev : cur ? 1 : 0);

export async function dashboard(spec: RangeSpec) {
  const { storeIds, timezone: tz } = spec;
  const days = Math.max(1, daysBetween(spec.from, spec.to) + 1);
  const start = startOfLocalDay(spec.from, tz);
  const end = startOfLocalDay(addDays(spec.to, 1), tz);
  const prevStart = startOfLocalDay(addDays(spec.from, -days), tz);

  const [current, previous, firstOrderAt] = await Promise.all([
    ordersBetween(storeIds, start, end, true),
    ordersBetween(storeIds, prevStart, start, false),
    firstOrders(storeIds),
  ]);
  const cur = summarize(current, firstOrderAt, start);
  const prev = summarize(previous, firstOrderAt, prevStart);

  const [totalUsers, registeredUsers, newUsers, prevNewUsers, signupsBySource, inProgress, promos] = await Promise.all([
    prisma.user.count({ where: { role: 'customer' } }),
    prisma.user.count({ where: { role: 'customer', isGuest: false } }),
    prisma.user.count({ where: { role: 'customer', createdAt: { gte: start, lt: end } } }),
    prisma.user.count({ where: { role: 'customer', createdAt: { gte: prevStart, lt: start } } }),
    prisma.user.groupBy({ by: ['marketingSource'], where: { role: 'customer', isGuest: false, createdAt: { gte: start, lt: end } }, _count: { _all: true } }),
    prisma.order.count({ where: { storeId: { in: storeIds }, status: { in: ACTIVE_ORDER_STATUSES } } }),
    prisma.promoCode.findMany({ orderBy: { createdAt: 'asc' } }),
  ]);

  // Daily series + 12-point sparklines.
  const daily = Array.from({ length: days }, (_, i) => ({ date: addDays(spec.from, i), orders: 0, netSalesCents: 0 }));
  const dayIndex = new Map(daily.map((d, i) => [d.date, i]));
  const hourly = Array.from({ length: 24 }, (_, hour) => ({ hour, orders: 0, netSalesCents: 0 }));
  for (const o of cur.counted) {
    const d = daily[dayIndex.get(localDate(o.createdAt, tz)) ?? -1];
    if (d) {
      d.orders++;
      d.netSalesCents += netSales(o);
    }
    const h = hourly[localHour(o.createdAt, tz)]!;
    h.orders++;
    h.netSalesCents += netSales(o);
  }

  // Top items by revenue.
  const items = new Map<string, { name: string; kind: string; quantity: number; revenueCents: number }>();
  for (const o of cur.counted) {
    for (const i of o.items ?? []) {
      const row = items.get(i.name) ?? { name: i.name, kind: i.kind, quantity: 0, revenueCents: 0 };
      row.quantity += i.quantity;
      row.revenueCents += i.totalCents;
      items.set(i.name, row);
    }
  }

  const tally = (key: (o: OrderRow) => string | null | undefined) => {
    const out = new Map<string, { key: string; orders: number; netSalesCents: number }>();
    for (const o of cur.counted) {
      const k = key(o);
      if (!k) continue;
      const row = out.get(k) ?? { key: k, orders: 0, netSalesCents: 0 };
      row.orders++;
      row.netSalesCents += netSales(o);
      out.set(k, row);
    }
    return [...out.values()].sort((a, b) => b.orders - a.orders);
  };

  // Marketing: which promo codes / channels actually brought in orders and new customers.
  const isFirst = (o: OrderRow) => firstOrderAt.get(o.customerKey)?.getTime() === o.createdAt.getTime();
  const promoRows = promos
    .map((p) => {
      const used = cur.counted.filter((o) => o.promoCode === p.code);
      const sales = used.reduce((s, o) => s + netSales(o), 0);
      const discount = used.reduce((s, o) => s + o.discountCents, 0);
      return {
        code: p.code,
        channel: p.channel,
        campaign: p.campaign,
        isActive: p.isActive,
        uses: used.length,
        netSalesCents: sales,
        discountCents: discount,
        newCustomers: used.filter(isFirst).length,
        returnOnDiscount: discount ? sales / discount : null,
      };
    })
    .filter((r) => r.uses > 0 || r.isActive)
    .sort((a, b) => b.netSalesCents - a.netSalesCents);

  const channels = new Map<string, { channel: string; orders: number; netSalesCents: number; discountCents: number; newCustomers: number; signups: number }>();
  const channel = (name: string) => {
    let row = channels.get(name);
    if (!row) channels.set(name, (row = { channel: name, orders: 0, netSalesCents: 0, discountCents: 0, newCustomers: 0, signups: 0 }));
    return row;
  };
  for (const r of promoRows) {
    const row = channel(r.channel);
    row.orders += r.uses;
    row.netSalesCents += r.netSalesCents;
    row.discountCents += r.discountCents;
    row.newCustomers += r.newCustomers;
  }
  for (const s of signupsBySource) if (s.marketingSource) channel(s.marketingSource).signups += s._count._all;

  const sparkline = (f: (d: (typeof daily)[number]) => number) => {
    const n = Math.min(12, daily.length);
    return daily.slice(-n).map(f);
  };

  return {
    range: { from: spec.from, to: spec.to, days, timezone: tz },
    kpis: {
      netSalesCents: cur.netSalesCents,
      orders: cur.orders,
      aovCents: cur.aovCents,
      totalUsers,
      registeredUsers,
      newUsers,
      repeatRate: cur.repeatRate,
      returningCustomers: cur.returningCustomers,
      newCustomers: cur.newCustomers,
      customers: cur.customers,
      inProgress,
      cancelled: cur.cancelled,
      discountCents: cur.discountCents,
      tipCents: cur.tipCents,
      taxCents: cur.taxCents,
      deliveryFeeCents: cur.deliveryFeeCents,
      totalCollectedCents: cur.totalCollectedCents,
    },
    deltas: {
      netSales: pct(cur.netSalesCents, prev.netSalesCents),
      orders: pct(cur.orders, prev.orders),
      aov: pct(cur.aovCents, prev.aovCents),
      newUsers: pct(newUsers, prevNewUsers),
      repeatRate: cur.repeatRate - prev.repeatRate,
    },
    sparklines: {
      netSales: sparkline((d) => d.netSalesCents),
      orders: sparkline((d) => d.orders),
      aov: sparkline((d) => (d.orders ? Math.round(d.netSalesCents / d.orders) : 0)),
    },
    daily,
    hourly,
    topItems: [...items.values()].sort((a, b) => b.revenueCents - a.revenueCents).slice(0, 8),
    fulfillment: [
      { key: 'pickup', orders: cur.pickup },
      { key: 'delivery', orders: cur.delivery },
    ],
    platforms: tally((o) => o.platform),
    fleet: tally((o) => (o.fulfillment === 'delivery' ? (o.delivery?.provider ?? 'unassigned') : null)),
    payments: tally((o) => o.paymentMethod?.replace(/ \(demo\)$/, '').replace(/^(Visa|Mastercard|Amex|Discover) •••• \d+$/, 'Card')),
    promos: promoRows,
    channels: [...channels.values()].sort((a, b) => b.netSalesCents - a.netSalesCents),
  };
}

export async function customers(storeIds: string[], search?: string) {
  const grouped = await prisma.order.groupBy({
    by: ['customerKey'],
    where: { storeId: { in: storeIds }, paymentStatus: { in: PAID }, status: { not: 'cancelled' } },
    _count: { _all: true },
    _sum: { totalCents: true, taxCents: true, tipCents: true },
    _min: { createdAt: true },
    _max: { createdAt: true },
    orderBy: { _max: { createdAt: 'desc' } },
    take: 500,
  });
  const latest = await prisma.order.findMany({
    where: { customerKey: { in: grouped.map((g) => g.customerKey) } },
    orderBy: { createdAt: 'desc' },
    distinct: ['customerKey'],
    select: { customerKey: true, customerName: true, customerPhone: true, customerEmail: true, user: { select: { isGuest: true, marketingSource: true, email: true } } },
  });
  const byKey = new Map(latest.map((l) => [l.customerKey, l]));
  const q = search?.trim().toLowerCase();
  return grouped
    .map((g) => {
      const l = byKey.get(g.customerKey);
      const spent = (g._sum.totalCents ?? 0) - (g._sum.taxCents ?? 0) - (g._sum.tipCents ?? 0);
      return {
        customerKey: g.customerKey,
        name: l?.customerName ?? 'Guest',
        phone: l?.customerPhone ?? null,
        email: l?.customerEmail ?? l?.user?.email ?? null,
        registered: l?.user ? !l.user.isGuest : false,
        source: l?.user?.marketingSource ?? null,
        orders: g._count._all,
        netSalesCents: spent,
        firstOrderAt: g._min.createdAt,
        lastOrderAt: g._max.createdAt,
        repeat: g._count._all > 1,
      };
    })
    .filter((c) => !q || c.name.toLowerCase().includes(q) || c.phone?.includes(q) || c.email?.toLowerCase().includes(q));
}
