import { prisma } from '../db.js';
import { PIZZA_OPTIONS, type PizzaOptions } from './catalog.js';

/** Pizza builder options (sizes, crusts, sauces, cheeses, toppings) — owner-editable, cached in memory. */
const KEY = 'pizzaOptions';
let cached: PizzaOptions | null = null;

export async function getPizzaOptions(): Promise<PizzaOptions> {
  if (cached) return cached;
  const row = await prisma.setting.findUnique({ where: { key: KEY } });
  cached = row ? (JSON.parse(row.value) as PizzaOptions) : PIZZA_OPTIONS;
  return cached;
}

export async function savePizzaOptions(options: PizzaOptions) {
  await prisma.setting.upsert({ where: { key: KEY }, update: { value: JSON.stringify(options) }, create: { key: KEY, value: JSON.stringify(options) } });
  cached = options;
  return options;
}

export const slugify = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40) || 'item';
