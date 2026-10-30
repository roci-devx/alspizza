import fs from 'node:fs';
import path from 'node:path';
import ExcelJS from 'exceljs';
import nodemailer from 'nodemailer';
import { config, integrations } from '../config.js';
import { prisma } from '../db.js';
import { addDays, localDate, localMinutesOfDay, startOfLocalDay } from '../lib/time.js';
import { dashboard, PAID } from './analytics.service.js';

const BROWN = 'FF5A210F';
const CREAM = 'FFFCF7EC';
const ORANGE = 'FFE8962A';
const MONEY = '"$"#,##0.00';
const dollars = (cents: number) => Math.round(cents) / 100;

function styleHeader(row: ExcelJS.Row) {
  row.font = { bold: true, color: { argb: CREAM } };
  row.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: BROWN } };
  row.alignment = { vertical: 'middle' };
  row.height = 22;
}

function addTable(ws: ExcelJS.Worksheet, columns: { header: string; key: string; width: number; fmt?: string }[], rows: Record<string, unknown>[]) {
  ws.columns = columns.map((c) => ({ header: c.header, key: c.key, width: c.width, style: c.fmt ? { numFmt: c.fmt } : {} }));
  styleHeader(ws.getRow(1));
  rows.forEach((r) => ws.addRow(r));
  ws.views = [{ state: 'frozen', ySplit: 1 }];
  if (rows.length) ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: columns.length } };
}

const timeFmt = (tz: string) => new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', minute: '2-digit' });
const minutesBetween = (a?: Date | null, b?: Date | null) => (a && b ? Math.round((b.getTime() - a.getTime()) / 60_000) : null);
const avg = (xs: (number | null)[]) => {
  const v = xs.filter((x): x is number => x != null && x >= 0);
  return v.length ? Math.round((v.reduce((s, x) => s + x, 0) / v.length) * 10) / 10 : null;
};

export async function generateDailyReport(storeId: string, date: string) {
  const store = await prisma.store.findUniqueOrThrow({ where: { id: storeId } });
  const tz = store.timezone;
  const start = startOfLocalDay(date, tz);
  const end = startOfLocalDay(addDays(date, 1), tz);
  const orders = await prisma.order.findMany({
    where: { storeId, createdAt: { gte: start, lt: end }, status: { not: 'pending_payment' } },
    include: { items: true, delivery: true },
    orderBy: { createdAt: 'asc' },
  });
  const stats = await dashboard({ storeIds: [storeId], timezone: tz, from: date, to: date });
  const k = stats.kpis;
  const counted = orders.filter((o) => o.status !== 'cancelled' && PAID.includes(o.paymentStatus));
  const courierFees = counted.reduce((s, o) => s + (o.delivery && o.delivery.provider !== 'own' ? o.delivery.providerFeeCents : 0), 0);
  const prepMinutes = avg(counted.map((o) => minutesBetween(o.paidAt, o.readyAt)));
  const deliveryMinutes = avg(counted.filter((o) => o.fulfillment === 'delivery').map((o) => minutesBetween(o.paidAt, o.completedAt)));
  const t = timeFmt(tz);
  const longDate = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' }).format(new Date(`${date}T12:00:00Z`));

  const wb = new ExcelJS.Workbook();
  wb.creator = "Al's Pizza";
  wb.created = new Date();

  // ── Summary ──
  const s = wb.addWorksheet('Summary', { properties: { tabColor: { argb: ORANGE } } });
  s.columns = [{ width: 34 }, { width: 18 }, { width: 4 }, { width: 30 }, { width: 18 }];
  s.mergeCells('A1:E1');
  s.getCell('A1').value = "Al's Pizza — End of Day Report";
  s.getCell('A1').font = { bold: true, size: 18, color: { argb: BROWN } };
  s.getCell('A2').value = `${store.name} · ${longDate}`;
  s.getCell('A2').font = { size: 12, color: { argb: 'FF7A5A48' } };
  s.getCell('A3').value = `Generated ${new Intl.DateTimeFormat('en-US', { timeZone: tz, dateStyle: 'medium', timeStyle: 'short' }).format(new Date())}`;
  s.getCell('A3').font = { italic: true, size: 10, color: { argb: 'FF9A8A7A' } };

  const money: [string, number][] = [
    ['Net sales (food + delivery − discounts)', k.netSalesCents],
    ['Gross food sales', counted.reduce((x, o) => x + o.subtotalCents, 0)],
    ['Discounts given', k.discountCents],
    ['Delivery fees charged', k.deliveryFeeCents],
    ['Driver tips (pass-through)', k.tipCents],
    ['Sales tax collected', k.taxCents],
    ['Total collected', k.totalCollectedCents],
    ['Courier fees (DoorDash / Uber)', courierFees],
    ['Net after courier fees', k.netSalesCents - courierFees],
    ['Average order (net)', k.aovCents],
  ];
  const counts: [string, number | string][] = [
    ['Orders', k.orders],
    ['Pickup orders', stats.fulfillment[0]!.orders],
    ['Delivery orders', stats.fulfillment[1]!.orders],
    ['Cancelled orders', k.cancelled],
    ['Unique customers', k.customers],
    ['New customers', k.newCustomers],
    ['Returning customers', k.returningCustomers],
    ['Repeat rate', `${Math.round(k.repeatRate * 100)}%`],
    ['Avg kitchen time (min)', prepMinutes ?? '—'],
    ['Avg delivery time (min)', deliveryMinutes ?? '—'],
  ];
  const head = s.getRow(5);
  head.values = ['Money', 'Amount', '', 'Orders & customers', 'Value'];
  styleHeader(head);
  money.forEach(([label, cents], i) => {
    const row = s.getRow(6 + i);
    row.getCell(1).value = label;
    row.getCell(2).value = dollars(cents);
    row.getCell(2).numFmt = MONEY;
  });
  counts.forEach(([label, value], i) => {
    const row = s.getRow(6 + i);
    row.getCell(4).value = label;
    row.getCell(5).value = value;
  });
  for (const r of [6, 12, 14]) s.getRow(r).font = { bold: true };

  // ── Orders ──
  addTable(
    wb.addWorksheet('Orders'),
    [
      { header: 'Order #', key: 'number', width: 10 },
      { header: 'Time', key: 'time', width: 10 },
      { header: 'Status', key: 'status', width: 16 },
      { header: 'Type', key: 'type', width: 10 },
      { header: 'Platform', key: 'platform', width: 10 },
      { header: 'Customer', key: 'customer', width: 22 },
      { header: 'Phone', key: 'phone', width: 15 },
      { header: 'Items', key: 'items', width: 7 },
      { header: 'Item details', key: 'details', width: 60 },
      { header: 'Subtotal', key: 'subtotal', width: 11, fmt: MONEY },
      { header: 'Discount', key: 'discount', width: 11, fmt: MONEY },
      { header: 'Promo', key: 'promo', width: 12 },
      { header: 'Delivery fee', key: 'deliveryFee', width: 12, fmt: MONEY },
      { header: 'Tip', key: 'tip', width: 9, fmt: MONEY },
      { header: 'Tax', key: 'tax', width: 9, fmt: MONEY },
      { header: 'Total', key: 'total', width: 11, fmt: MONEY },
      { header: 'Payment', key: 'payment', width: 20 },
      { header: 'Courier', key: 'courier', width: 12 },
      { header: 'Courier fee', key: 'courierFee', width: 12, fmt: MONEY },
      { header: 'Kitchen min', key: 'prep', width: 11 },
      { header: 'Done min', key: 'done', width: 10 },
    ],
    orders.map((o) => ({
      number: o.number,
      time: t.format(o.createdAt),
      status: o.status.replace(/_/g, ' '),
      type: o.fulfillment,
      platform: o.platform,
      customer: o.customerName,
      phone: o.customerPhone,
      items: o.itemsCount,
      details: o.items.map((i) => `${i.quantity}× ${i.name}${i.summary ? ` (${i.summary})` : ''}`).join('; '),
      subtotal: dollars(o.subtotalCents),
      discount: dollars(o.discountCents),
      promo: o.promoCode ?? '',
      deliveryFee: dollars(o.deliveryFeeCents),
      tip: dollars(o.tipCents),
      tax: dollars(o.taxCents),
      total: dollars(o.totalCents),
      payment: o.paymentMethod ?? o.paymentProvider,
      courier: o.delivery?.provider ?? '',
      courierFee: o.delivery && o.delivery.provider !== 'own' ? dollars(o.delivery.providerFeeCents) : 0,
      prep: minutesBetween(o.paidAt, o.readyAt) ?? '',
      done: minutesBetween(o.paidAt, o.completedAt) ?? '',
    })),
  );

  // ── Items ──
  const food = stats.topItems.length ? counted.reduce((x, o) => x + o.subtotalCents, 0) : 0;
  const allItems = new Map<string, { name: string; kind: string; qty: number; revenue: number }>();
  for (const o of counted) for (const i of o.items) {
    const row = allItems.get(i.name) ?? { name: i.name, kind: i.kind, qty: 0, revenue: 0 };
    row.qty += i.quantity;
    row.revenue += i.totalCents;
    allItems.set(i.name, row);
  }
  addTable(
    wb.addWorksheet('Items'),
    [
      { header: 'Item', key: 'name', width: 32 },
      { header: 'Type', key: 'kind', width: 12 },
      { header: 'Qty sold', key: 'qty', width: 10 },
      { header: 'Revenue', key: 'revenue', width: 12, fmt: MONEY },
      { header: '% of food sales', key: 'share', width: 15, fmt: '0.0%' },
    ],
    [...allItems.values()].sort((a, b) => b.revenue - a.revenue).map((i) => ({ ...i, revenue: dollars(i.revenue), share: food ? i.revenue / food : 0 })),
  );

  // ── Promo codes (marketing) ──
  addTable(
    wb.addWorksheet('Promo Codes'),
    [
      { header: 'Code', key: 'code', width: 14 },
      { header: 'Channel', key: 'channel', width: 14 },
      { header: 'Campaign', key: 'campaign', width: 24 },
      { header: 'Uses', key: 'uses', width: 8 },
      { header: 'Net sales', key: 'sales', width: 12, fmt: MONEY },
      { header: 'Discount', key: 'discount', width: 12, fmt: MONEY },
      { header: 'New customers', key: 'newCustomers', width: 14 },
    ],
    stats.promos.filter((p) => p.uses > 0).map((p) => ({ ...p, campaign: p.campaign ?? '', sales: dollars(p.netSalesCents), discount: dollars(p.discountCents) })),
  );

  // ── Hourly ──
  addTable(
    wb.addWorksheet('Hourly'),
    [
      { header: 'Hour', key: 'hour', width: 12 },
      { header: 'Orders', key: 'orders', width: 10 },
      { header: 'Net sales', key: 'sales', width: 12, fmt: MONEY },
    ],
    stats.hourly
      .filter((h) => h.orders > 0)
      .map((h) => ({ hour: `${h.hour % 12 || 12}:00 ${h.hour < 12 ? 'AM' : 'PM'}`, orders: h.orders, sales: dollars(h.netSalesCents) })),
  );

  // ── Payments ──
  addTable(
    wb.addWorksheet('Payments'),
    [
      { header: 'Method', key: 'key', width: 20 },
      { header: 'Orders', key: 'orders', width: 10 },
      { header: 'Net sales', key: 'sales', width: 12, fmt: MONEY },
    ],
    stats.payments.map((p) => ({ key: p.key, orders: p.orders, sales: dollars(p.netSalesCents) })),
  );

  const dir = path.join(config.reportsDir, store.slug);
  fs.mkdirSync(dir, { recursive: true });
  const fileName = `als-pizza-${store.slug}-${date}.xlsx`;
  await wb.xlsx.writeFile(path.join(dir, fileName));

  const summary = {
    orders: k.orders,
    netSalesCents: k.netSalesCents,
    totalCollectedCents: k.totalCollectedCents,
    aovCents: k.aovCents,
    newCustomers: k.newCustomers,
    returningCustomers: k.returningCustomers,
    courierFeesCents: courierFees,
    avgKitchenMinutes: prepMinutes,
  };
  return prisma.dailyReport.upsert({
    where: { storeId_date: { storeId, date } },
    update: { fileName, summaryJson: JSON.stringify(summary), createdAt: new Date() },
    create: { storeId, date, fileName, summaryJson: JSON.stringify(summary) },
  });
}

export function reportPath(storeSlug: string, fileName: string) {
  return path.join(config.reportsDir, storeSlug, path.basename(fileName));
}

async function emailReport(reportId: string) {
  const report = await prisma.dailyReport.findUnique({ where: { id: reportId }, include: { store: true } });
  if (!report || !report.store.reportEmail || !integrations.smtp) return;
  const summary = JSON.parse(report.summaryJson) as { orders: number; netSalesCents: number };
  const transport = nodemailer.createTransport(config.smtp.url);
  await transport.sendMail({
    from: config.smtp.from,
    to: report.store.reportEmail,
    subject: `${report.store.name} · ${report.date}: $${(summary.netSalesCents / 100).toFixed(2)} across ${summary.orders} orders`,
    text: `Your end-of-day report for ${report.store.name} (${report.date}) is attached.`,
    attachments: [{ filename: report.fileName, path: reportPath(report.store.slug, report.fileName) }],
  });
  await prisma.dailyReport.update({ where: { id: reportId }, data: { emailedAt: new Date() } });
}

/** Generates each store's report once its closing-report time passes (store-local), and backfills yesterday if the server was down. */
export function startReportScheduler() {
  const tick = async () => {
    const stores = await prisma.store.findMany();
    for (const store of stores) {
      const now = new Date();
      const today = localDate(now, store.timezone);
      const [h, m] = store.reportTime.split(':').map(Number) as [number, number];
      const due: string[] = [addDays(today, -1)];
      if (localMinutesOfDay(now, store.timezone) >= h * 60 + m) due.push(today);
      for (const date of due) {
        const existing = await prisma.dailyReport.findUnique({ where: { storeId_date: { storeId: store.id, date } } });
        if (existing) continue;
        try {
          const report = await generateDailyReport(store.id, date);
          console.log(`[reports] generated ${report.fileName}`);
          await emailReport(report.id).catch((err) => console.error('[reports] email failed', err));
        } catch (err) {
          console.error(`[reports] failed for ${store.slug} ${date}`, err);
        }
      }
    }
  };
  setTimeout(() => void tick(), 5_000);
  setInterval(() => void tick(), 60_000);
}

