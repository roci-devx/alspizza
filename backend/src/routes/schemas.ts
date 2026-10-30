import { z } from 'zod';

export const platformSchema = z.enum(['ios', 'android', 'web']).default('web');

export const cartLineSchema = z.object({
  itemId: z.string().min(1),
  quantity: z.number().int().min(1).max(25),
  variantId: z.string().max(40).optional(),
  choices: z.record(z.string().max(40)).optional(),
  pizza: z
    .object({
      size: z.string().max(20),
      crust: z.string().max(20),
      sauce: z.string().max(20),
      cheese: z.string().max(20),
      toppings: z.array(z.string().max(30)).max(17),
    })
    .optional(),
  notes: z.string().max(140).optional(),
});

export const priceSchema = z.object({
  storeId: z.string().min(1),
  items: z.array(cartLineSchema).min(1).max(40),
  fulfillment: z.enum(['pickup', 'delivery']).optional(),
  promoCode: z.string().max(30).nullish(),
  deliveryQuoteId: z.string().nullish(),
  tipCents: z.number().int().min(0).max(20_000).optional(),
});

export const addressSchema = z.object({
  line1: z.string().min(3).max(120),
  line2: z.string().max(60).nullish(),
  city: z.string().min(1).max(60),
  state: z.string().min(2).max(30),
  zip: z.string().min(3).max(12),
  lat: z.number().min(-90).max(90).nullish(),
  lng: z.number().min(-180).max(180).nullish(),
  instructions: z.string().max(200).nullish(),
});

export const createOrderSchema = priceSchema.extend({
  fulfillment: z.enum(['pickup', 'delivery']),
  customer: z.object({
    name: z.string().trim().min(1, 'Add your name').max(80),
    phone: z.string().trim().min(7, 'Add a phone number so we can reach you').max(20),
    email: z.string().trim().email().max(120).nullish(),
  }),
  notes: z.string().max(300).nullish(),
  addressLine2: z.string().max(60).nullish(),
  dropoffInstructions: z.string().max(200).nullish(),
  platform: platformSchema,
});

export const paySchema = z.object({
  provider: z.enum(['stripe', 'paypal', 'cash', 'demo']),
  method: z.enum(['apple_pay', 'google_pay', 'card', 'paypal', 'cash']).default('card'),
  platform: platformSchema,
});
