import type { Category, MenuItem } from '@prisma/client';
import { json } from '../db.js';
import { badRequest } from '../lib/http.js';
import { PIZZA_OPTIONS, type ItemConfig, type PizzaOptions } from './catalog.js';

export type MenuItemWithCategory = MenuItem & { category: Category };

export interface PizzaSelection {
  size: string;
  crust: string;
  sauce: string;
  cheese: string;
  toppings: string[];
}

export interface CartLineInput {
  itemId: string;
  quantity: number;
  variantId?: string;
  choices?: Record<string, string>;
  pizza?: PizzaSelection;
  notes?: string;
}

export interface PricedLine {
  itemId: string;
  name: string;
  kind: string;
  categorySlug: string;
  art: string;
  quantity: number;
  unitPriceCents: number;
  totalCents: number;
  summary: string;
  config: Record<string, unknown>;
  prepMinutes: number;
}


/** Server-side source of truth for what a cart line costs. Clients only ever display prices. */
export function priceLine(item: MenuItemWithCategory, input: CartLineInput, options: PizzaOptions = PIZZA_OPTIONS): PricedLine {
  const toppingLabel = (id: string) => options.toppings.find((t) => t.id === id)?.label ?? id;
  if (!item.isAvailable) throw badRequest(`${item.name} is sold out right now`, 'unavailable');
  const quantity = Math.max(1, Math.min(25, Math.floor(input.quantity || 1)));
  const cfg = json.parse<ItemConfig>(item.configJson, {});
  const parts: string[] = [];
  const config: Record<string, unknown> = {};
  let unit = item.priceCents;

  if (cfg.pizza) {
    const base = cfg.pizza;
    const sel: PizzaSelection = input.pizza ?? {
      size: base.defaultSize,
      crust: base.crust,
      sauce: base.sauce,
      cheese: base.cheese,
      toppings: base.toppings,
    };
    const size = options.sizes.find((s) => s.id === sel.size);
    if (!size || base.sizePrices[size.id] == null) throw badRequest(`${item.name} isn't available in that size`);
    const crust = options.crusts.find((c) => c.id === sel.crust);
    if (!crust || !crust.sizes.includes(size.id)) {
      throw badRequest(`${crust?.label ?? 'That crust'} isn't available in ${size.label}`);
    }
    const sauce = options.sauces.find((s) => s.id === sel.sauce) ?? options.sauces[0]!;
    const cheese = options.cheeses.find((c) => c.id === sel.cheese) ?? options.cheeses.find((c) => c.id === 'regular') ?? options.cheeses[0]!;
    const known = new Set(options.toppings.map((t) => t.id));
    const toppings = [...new Set(sel.toppings ?? [])].filter((t) => known.has(t));
    if (toppings.length > 10) throw badRequest('Up to 10 toppings per pizza');

    const included = new Set(base.toppings);
    const extras = toppings.filter((t) => !included.has(t));
    const removed = base.toppings.filter((t) => !toppings.includes(t));
    const extraCheese = cheese.extra && base.cheese !== 'extra' ? size.toppingCents : 0;
    unit = base.sizePrices[size.id] + (crust.upcharges[size.id] ?? 0) + extras.length * size.toppingCents + extraCheese;

    parts.push(`${size.label} ${size.inches}"`, crust.label);
    if (sauce.id !== base.sauce) parts.push(sauce.id === 'none' ? 'No sauce' : sauce.label);
    if (cheese.id !== base.cheese) parts.push(cheese.id === 'none' ? 'No cheese' : `${cheese.label} cheese`);
    if (base.byo) {
      parts.push(toppings.length ? toppings.map(toppingLabel).join(', ') : 'Cheese only');
    } else {
      if (extras.length) parts.push(`Add ${extras.map(toppingLabel).join(', ')}`);
      if (removed.length) parts.push(`No ${removed.map(toppingLabel).join(', ')}`);
    }
    config.pizza = { size: size.id, crust: crust.id, sauce: sauce.id, cheese: cheese.id, toppings };
  } else if (cfg.variants?.length) {
    const variant = cfg.variants.find((v) => v.id === input.variantId) ?? cfg.variants[0]!;
    unit = variant.priceCents;
    parts.push(variant.label);
    config.variantId = variant.id;
  }

  if (cfg.choices?.length) {
    const chosen: Record<string, string> = {};
    for (const group of cfg.choices) {
      const pick = input.choices?.[group.id];
      const option = group.options.find((o) => o.id === pick) ?? (group.required ? group.options[0] : undefined);
      if (!option) continue;
      chosen[group.id] = option.id;
      parts.push(group.id.startsWith('pizza') ? `${group.label.replace(/ topping$/i, '')}: ${option.label}` : option.label);
    }
    config.choices = chosen;
  }

  const notes = input.notes?.trim().slice(0, 140);
  if (notes) config.notes = notes;

  return {
    itemId: item.id,
    name: item.name,
    kind: item.kind,
    categorySlug: item.category.slug,
    art: item.art,
    quantity,
    unitPriceCents: unit,
    totalCents: unit * quantity,
    summary: parts.join(' · '),
    config,
    prepMinutes: item.prepMinutes ?? item.category.prepMinutes,
  };
}

export function priceLines(items: MenuItemWithCategory[], inputs: CartLineInput[], options: PizzaOptions = PIZZA_OPTIONS) {
  if (!inputs.length) throw badRequest('Your order is empty');
  if (inputs.length > 40) throw badRequest('That is a lot of pizza! Please call the store for catering orders.');
  const byId = new Map(items.map((i) => [i.id, i]));
  const lines = inputs.map((input) => {
    const item = byId.get(input.itemId);
    if (!item) throw badRequest('One of the items in your order is no longer on the menu', 'unknown_item');
    return priceLine(item, input, options);
  });
  return {
    lines,
    subtotalCents: lines.reduce((sum, l) => sum + l.totalCents, 0),
    itemsCount: lines.reduce((sum, l) => sum + l.quantity, 0),
  };
}

export interface TotalsInput {
  subtotalCents: number;
  foodDiscountCents: number;
  deliveryFeeCents: number;
  deliveryDiscountCents: number;
  taxRate: number;
  tipCents: number;
}

export function computeTotals(t: TotalsInput) {
  const discountCents = t.foodDiscountCents + t.deliveryDiscountCents;
  const taxable = Math.max(0, t.subtotalCents - t.foodDiscountCents);
  const taxCents = Math.round(taxable * t.taxRate);
  const totalCents = Math.max(0, t.subtotalCents - discountCents + t.deliveryFeeCents + taxCents + t.tipCents);
  return { discountCents, taxCents, totalCents };
}
