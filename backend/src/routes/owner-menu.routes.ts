import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import express, { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { json, prisma } from '../db.js';
import { requireOwner } from '../lib/auth.js';
import { badRequest, notFound } from '../lib/http.js';
import type { ItemConfig, PizzaOptions } from '../menu/catalog.js';
import { getPizzaOptions, savePizzaOptions, slugify } from '../menu/options.js';
import { serializeMenuItem } from '../services/serialize.js';

/**
 * Owner menu editor: menu types (categories), items (photos, ingredients,
 * sizes/variants, choice groups, combo contents) and the shared pizza options.
 */
export const ownerMenuRoutes = Router();

export const MEDIA_DIR = path.resolve(process.cwd(), 'public');
const UPLOADS = path.join(MEDIA_DIR, 'uploads');

const id = z.string().trim().min(1).max(40);
const label = z.string().trim().min(1).max(60);
const cents = z.number().int().min(0).max(100_000);
const imageUrl = z
  .string()
  .trim()
  .max(500)
  .refine((v) => /^https?:\/\/\S+$/.test(v) || v.startsWith('/media/'), 'Use an https:// link or upload a photo')
  .nullable();

const itemConfigSchema = z.object({
  pizza: z
    .object({
      sizePrices: z.record(cents),
      toppings: z.array(z.string().max(40)).max(17),
      sauce: z.string().max(40),
      cheese: z.string().max(40),
      crust: z.string().max(40),
      defaultSize: z.string().max(40),
      byo: z.boolean().optional(),
      density: z.number().min(0.5).max(2.5).optional(),
    })
    .optional(),
  variants: z.array(z.object({ id: id.optional(), label, priceCents: cents, calories: z.string().max(40).optional() })).max(12).optional(),
  choices: z
    .array(z.object({ id: id.optional(), label, required: z.boolean(), options: z.array(z.object({ id: id.optional(), label })).min(1).max(40) }))
    .max(8)
    .optional(),
  includes: z.array(z.string().trim().min(1).max(80)).max(12).optional(),
});

const itemSchema = z.object({
  categoryId: z.string().min(1),
  name: z.string().trim().min(1).max(80),
  description: z.string().trim().max(300).default(''),
  kind: z.enum(['pizza', 'wings', 'side', 'pasta', 'dessert', 'drink', 'dip', 'deal']),
  priceCents: cents.default(0),
  calories: z.string().trim().max(40).nullable().optional(),
  imageUrl: imageUrl.optional(),
  art: z.string().trim().max(40).optional(),
  tags: z.array(z.enum(['popular', 'new', 'veg', 'spicy'])).max(4).default([]),
  isAvailable: z.boolean().default(true),
  prepMinutes: z.number().int().min(1).max(120).nullable().optional(),
  config: itemConfigSchema.default({}),
});

/** Gives every variant / choice / option a stable id (new rows from the editor arrive without one). */
function normalizeConfig(cfg: z.infer<typeof itemConfigSchema>, kind: string, options: PizzaOptions): ItemConfig {
  const claim = (used: Set<string>, given: string | undefined, text: string) => {
    if (given && !used.has(given)) {
      used.add(given);
      return given;
    }
    let candidate = slugify(text);
    for (let n = 2; used.has(candidate); n++) candidate = `${slugify(text)}-${n}`;
    used.add(candidate);
    return candidate;
  };
  const out: ItemConfig = {};
  if (kind === 'pizza') {
    const p = cfg.pizza;
    if (!p) throw badRequest('Pizzas need size prices');
    const sizePrices = Object.fromEntries(Object.entries(p.sizePrices).filter(([k]) => options.sizes.some((s) => s.id === k)));
    if (!Object.keys(sizePrices).length) throw badRequest('Give the pizza a price for at least one size');
    out.pizza = { ...p, sizePrices, defaultSize: sizePrices[p.defaultSize] != null ? p.defaultSize : Object.keys(sizePrices)[0]! };
  }
  if (cfg.variants?.length) {
    const used = new Set<string>();
    out.variants = cfg.variants.map((v) => ({ ...v, id: claim(used, v.id, v.label) }));
  }
  if (cfg.choices?.length) {
    const used = new Set<string>();
    out.choices = cfg.choices.map((g) => {
      const optionIds = new Set<string>();
      return { id: claim(used, g.id, g.label), label: g.label, required: g.required, options: g.options.map((o) => ({ id: claim(optionIds, o.id, o.label), label: o.label })) };
    });
  }
  if (cfg.includes?.length) out.includes = cfg.includes;
  return out;
}

const fromPrice = (cfg: ItemConfig, fallback: number) =>
  cfg.pizza ? Math.min(...Object.values(cfg.pizza.sizePrices)) : cfg.variants?.length ? Math.min(...cfg.variants.map((v) => v.priceCents)) : fallback;

const defaultArt: Record<string, string> = {
  pizza: 'pizza',
  wings: 'wings:buffalo',
  side: 'breadsticks',
  pasta: 'pasta:marinara',
  dessert: 'cookie',
  drink: 'soda:cola',
  dip: 'dip:ranch',
  deal: 'deal:dinnerbox',
};

async function uniqueSlug(table: 'category' | 'menuItem', name: string, excludeId?: string) {
  const base = slugify(name);
  let slug = base;
  for (let n = 2; ; n++) {
    const hit = table === 'category' ? await prisma.category.findUnique({ where: { slug } }) : await prisma.menuItem.findUnique({ where: { slug } });
    if (!hit || hit.id === excludeId) return slug;
    slug = `${base}-${n}`;
  }
}

// ── Whole menu ────────────────────────────────────────────────────────────────
ownerMenuRoutes.get('/owner/menu', requireOwner, async (_req, res) => {
  const categories = await prisma.category.findMany({ orderBy: { sortOrder: 'asc' }, include: { items: { orderBy: { sortOrder: 'asc' } } } });
  res.json({
    categories: categories.map((c) => ({ id: c.id, slug: c.slug, name: c.name, tagline: c.tagline, prepMinutes: c.prepMinutes, sortOrder: c.sortOrder, items: c.items.map((i) => serializeMenuItem({ ...i, category: c })) })),
    pizzaOptions: await getPizzaOptions(),
  });
});

// ── Menu types (categories) ───────────────────────────────────────────────────
const categorySchema = z.object({ name: z.string().trim().min(1).max(40), tagline: z.string().trim().max(80).default(''), prepMinutes: z.number().int().min(1).max(120).default(15) });

ownerMenuRoutes.post('/owner/categories', requireOwner, async (req, res) => {
  const body = categorySchema.parse(req.body);
  const last = await prisma.category.aggregate({ _max: { sortOrder: true } });
  const category = await prisma.category.create({ data: { ...body, slug: await uniqueSlug('category', body.name), sortOrder: (last._max.sortOrder ?? 0) + 1 } });
  res.status(201).json({ category });
});

ownerMenuRoutes.patch('/owner/categories/:id', requireOwner, async (req, res) => {
  const body = categorySchema.partial().extend({ sortOrder: z.number().int().min(0).max(1000).optional() }).parse(req.body);
  res.json({ category: await prisma.category.update({ where: { id: String(req.params.id) }, data: body }) });
});

/** Moves a category up/down by swapping sort positions with its neighbor. */
ownerMenuRoutes.post('/owner/categories/:id/move', requireOwner, async (req, res) => {
  const { direction } = z.object({ direction: z.enum(['up', 'down']) }).parse(req.body);
  const all = await prisma.category.findMany({ orderBy: { sortOrder: 'asc' } });
  const i = all.findIndex((c) => c.id === String(req.params.id));
  const j = direction === 'up' ? i - 1 : i + 1;
  if (i < 0) throw notFound('Category not found');
  if (j >= 0 && j < all.length) {
    const order = all.map((c) => c.id);
    [order[i], order[j]] = [order[j]!, order[i]!];
    await prisma.$transaction(order.map((cid, idx) => prisma.category.update({ where: { id: cid }, data: { sortOrder: idx } })));
  }
  res.json({ ok: true });
});

ownerMenuRoutes.delete('/owner/categories/:id', requireOwner, async (req, res) => {
  const count = await prisma.menuItem.count({ where: { categoryId: String(req.params.id) } });
  if (count) throw badRequest(`Move or delete its ${count} item${count === 1 ? '' : 's'} first`);
  await prisma.category.delete({ where: { id: String(req.params.id) } });
  res.json({ ok: true });
});

// ── Items ─────────────────────────────────────────────────────────────────────
ownerMenuRoutes.post('/owner/items', requireOwner, async (req, res) => {
  const body = itemSchema.parse(req.body);
  const category = await prisma.category.findUnique({ where: { id: body.categoryId } });
  if (!category) throw notFound('Pick a menu type for this item');
  const cfg = normalizeConfig(body.config, body.kind, await getPizzaOptions());
  const last = await prisma.menuItem.aggregate({ where: { categoryId: category.id }, _max: { sortOrder: true } });
  const item = await prisma.menuItem.create({
    data: {
      categoryId: category.id,
      slug: await uniqueSlug('menuItem', body.name),
      name: body.name,
      description: body.description,
      kind: body.kind,
      priceCents: fromPrice(cfg, body.priceCents),
      calories: body.calories ?? null,
      imageUrl: body.imageUrl ?? null,
      art: body.art || defaultArt[body.kind]!,
      tags: body.tags.join(','),
      isAvailable: body.isAvailable,
      prepMinutes: body.prepMinutes ?? null,
      configJson: JSON.stringify(cfg),
      sortOrder: (last._max.sortOrder ?? 0) + 1,
    },
    include: { category: true },
  });
  res.status(201).json({ item: serializeMenuItem(item) });
});

ownerMenuRoutes.patch('/owner/items/:id', requireOwner, async (req, res) => {
  const body = itemSchema
    .partial()
    .extend({
      // Quick edits from the item list.
      sizePrices: z.record(cents).optional(),
      variantPrices: z.record(cents).optional(),
      sortOrder: z.number().int().min(0).max(1000).optional(),
    })
    .parse(req.body);
  const item = await prisma.menuItem.findUnique({ where: { id: String(req.params.id) } });
  if (!item) throw notFound('Item not found');
  const kind = body.kind ?? item.kind;
  let cfg = json.parse<ItemConfig>(item.configJson, {});
  if (body.config) cfg = normalizeConfig(body.config, kind, await getPizzaOptions());
  if (body.sizePrices && cfg.pizza) Object.assign(cfg.pizza.sizePrices, body.sizePrices);
  if (body.variantPrices && cfg.variants) for (const v of cfg.variants) if (body.variantPrices[v.id] != null) v.priceCents = body.variantPrices[v.id]!;
  if (body.categoryId && !(await prisma.category.findUnique({ where: { id: body.categoryId } }))) throw notFound('Menu type not found');
  const updated = await prisma.menuItem.update({
    where: { id: item.id },
    data: {
      categoryId: body.categoryId,
      name: body.name,
      slug: body.name && body.name !== item.name ? await uniqueSlug('menuItem', body.name, item.id) : undefined,
      description: body.description,
      kind: body.kind,
      calories: body.calories,
      imageUrl: body.imageUrl,
      art: body.art || (body.kind && body.kind !== item.kind ? defaultArt[body.kind] : undefined),
      tags: body.tags?.join(','),
      isAvailable: body.isAvailable,
      prepMinutes: body.prepMinutes,
      sortOrder: body.sortOrder,
      configJson: JSON.stringify(cfg),
      priceCents: fromPrice(cfg, body.priceCents ?? item.priceCents),
    },
    include: { category: true },
  });
  res.json({ item: serializeMenuItem(updated) });
});

ownerMenuRoutes.delete('/owner/items/:id', requireOwner, async (req, res) => {
  await prisma.menuItem.delete({ where: { id: String(req.params.id) } });
  res.json({ ok: true });
});

// ── Shared pizza options (sizes, crusts, sauces, cheeses, toppings) ───────────
const optionRow = z.object({ id: id.optional(), label });
const optionsSchema = z.object({
  sizes: z.array(optionRow.extend({ inches: z.number().int().min(4).max(36), slices: z.number().int().min(1).max(24), toppingCents: cents })).min(1).max(8),
  crusts: z.array(optionRow.extend({ description: z.string().trim().max(120).default(''), sizes: z.array(z.string()).min(1), upcharges: z.record(cents).default({}) })).min(1).max(12),
  sauces: z.array(optionRow).min(1).max(12),
  cheeses: z.array(optionRow.extend({ extra: z.boolean().optional() })).min(1).max(8),
  toppings: z.array(optionRow.extend({ group: z.enum(['meat', 'veggie']), art: z.string().max(40).optional() })).max(60),
});

ownerMenuRoutes.put('/owner/pizza-options', requireOwner, async (req, res) => {
  const body = optionsSchema.parse(req.body);
  const withIds = <T extends { id?: string; label: string }>(rows: T[]) => {
    const used = new Set<string>();
    return rows.map((r) => {
      let rid = r.id || slugify(r.label);
      for (let n = 2; used.has(rid); n++) rid = `${slugify(r.label)}-${n}`;
      used.add(rid);
      return { ...r, id: rid };
    });
  };
  const sizes = withIds(body.sizes);
  const sizeIds = new Set(sizes.map((s) => s.id));
  const options = {
    sizes,
    crusts: withIds(body.crusts).map((c) => ({ ...c, sizes: c.sizes.filter((s) => sizeIds.has(s)) })),
    sauces: withIds(body.sauces),
    cheeses: withIds(body.cheeses),
    toppings: withIds(body.toppings),
  } as PizzaOptions;
  if (options.crusts.some((c) => !c.sizes.length)) throw badRequest('Every crust needs at least one size');
  res.json({ pizzaOptions: await savePizzaOptions(options) });
});

// ── Photo uploads (base64 JSON keeps the API dependency-free) ─────────────────
const MAGIC: Record<string, (b: Buffer) => boolean> = {
  'image/jpeg': (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/png': (b) => b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])),
  'image/webp': (b) => b.subarray(0, 4).toString('ascii') === 'RIFF' && b.subarray(8, 12).toString('ascii') === 'WEBP',
  'image/gif': (b) => b.subarray(0, 4).toString('ascii') === 'GIF8',
};
const EXT: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif' };

ownerMenuRoutes.post('/owner/media', requireOwner, express.json({ limit: '12mb' }), async (req, res) => {
  const body = z.object({ contentType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/gif']), data: z.string().min(16) }).parse(req.body);
  const buf = Buffer.from(body.data, 'base64');
  if (buf.length > 8 * 1024 * 1024) throw badRequest('Photos must be under 8 MB');
  if (!MAGIC[body.contentType]!(buf)) throw badRequest('That file isn’t a valid image');
  fs.mkdirSync(UPLOADS, { recursive: true });
  const name = `${Date.now().toString(36)}-${crypto.randomBytes(5).toString('hex')}.${EXT[body.contentType]}`;
  fs.writeFileSync(path.join(UPLOADS, name), buf);
  res.status(201).json({ url: `/media/uploads/${name}`, absoluteUrl: `${config.publicApiUrl}/media/uploads/${name}` });
});
