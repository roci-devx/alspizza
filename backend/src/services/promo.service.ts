import type { PromoCode } from '@prisma/client';
import { prisma } from '../db.js';

export interface PromoContext {
  subtotalCents: number;
  deliveryFeeCents: number;
  fulfillment?: 'pickup' | 'delivery';
  customerKey?: string;
}

export interface PromoResult {
  code: string;
  promo: PromoCode | null;
  foodDiscountCents: number;
  deliveryDiscountCents: number;
  label?: string;
  error?: string;
}

const money = (cents: number) => `$${(cents / 100).toFixed(2)}`;

export function describePromo(p: Pick<PromoCode, 'type' | 'value' | 'minSubtotalCents'>): string {
  const min = p.minSubtotalCents > 0 ? ` on ${money(p.minSubtotalCents)}+` : '';
  if (p.type === 'percent') return `${p.value}% off${min}`;
  if (p.type === 'fixed') return `${money(p.value)} off${min}`;
  return `Free delivery${min}`;
}

export async function evaluatePromo(rawCode: string | undefined | null, ctx: PromoContext): Promise<PromoResult | null> {
  const code = rawCode?.trim().toUpperCase();
  if (!code) return null;
  const fail = (error: string, promo: PromoCode | null = null): PromoResult => ({ code, promo, foodDiscountCents: 0, deliveryDiscountCents: 0, error });

  const promo = await prisma.promoCode.findUnique({ where: { code } });
  if (!promo || !promo.isActive) return fail("That code isn't valid");
  const now = new Date();
  if (promo.startsAt && promo.startsAt > now) return fail("That code isn't active yet", promo);
  if (promo.endsAt && promo.endsAt < now) return fail('That code has expired', promo);
  if (ctx.subtotalCents < promo.minSubtotalCents) return fail(`Add ${money(promo.minSubtotalCents - ctx.subtotalCents)} more to use ${code}`, promo);

  if (promo.maxUses != null) {
    const used = await prisma.order.count({ where: { promoCode: code, paymentStatus: { in: ['paid', 'pay_at_pickup'] } } });
    if (used >= promo.maxUses) return fail('That code has been fully redeemed', promo);
  }
  if (promo.firstOrderOnly && ctx.customerKey) {
    const previous = await prisma.order.count({ where: { customerKey: ctx.customerKey, paymentStatus: { in: ['paid', 'pay_at_pickup'] } } });
    if (previous > 0) return fail(`${code} is for first orders only`, promo);
  }

  let foodDiscountCents = 0;
  let deliveryDiscountCents = 0;
  if (promo.type === 'percent') foodDiscountCents = Math.round((ctx.subtotalCents * Math.min(100, promo.value)) / 100);
  else if (promo.type === 'fixed') foodDiscountCents = Math.min(promo.value, ctx.subtotalCents);
  else if (promo.type === 'free_delivery') {
    if (ctx.fulfillment && ctx.fulfillment !== 'delivery') return fail(`${code} works on delivery orders`, promo);
    deliveryDiscountCents = ctx.deliveryFeeCents;
  }
  return { code, promo, foodDiscountCents, deliveryDiscountCents, label: describePromo(promo) };
}
