/**
 * Starter menu modeled on a national pizza chain's structure (sizes, crusts,
 * specialty pizzas, wings, sides, pasta, desserts, drinks, combo deals) with
 * Al's own item names. The owner edits prices, availability and prep times
 * from the dashboard; this file only seeds the database.
 */

/** Size ids are owner-editable; the starter menu uses personal / medium / large / xl. */
export type SizeId = string;
export type ToppingGroup = 'meat' | 'veggie';

export interface PizzaSize {
  id: SizeId;
  label: string;
  inches: number;
  slices: number;
  toppingCents: number;
}

export interface Crust {
  id: string;
  label: string;
  description: string;
  sizes: SizeId[];
  upcharges: Partial<Record<SizeId, number>>;
}

export interface PizzaOptions {
  sizes: PizzaSize[];
  crusts: Crust[];
  sauces: { id: string; label: string }[];
  cheeses: { id: string; label: string; extra?: boolean }[];
  toppings: { id: string; label: string; group: ToppingGroup; art?: string }[];
}

export const PIZZA_OPTIONS: PizzaOptions = {
  sizes: [
    { id: 'personal', label: 'Personal', inches: 6, slices: 4, toppingCents: 100 },
    { id: 'medium', label: 'Medium', inches: 12, slices: 8, toppingCents: 175 },
    { id: 'large', label: 'Large', inches: 14, slices: 8, toppingCents: 225 },
    { id: 'xl', label: 'X-Large', inches: 16, slices: 12, toppingCents: 275 },
  ],
  crusts: [
    { id: 'pan', label: 'Original Pan', description: 'Thick & buttery with golden, crispy edges', sizes: ['personal', 'medium', 'large'], upcharges: {} },
    { id: 'hand-tossed', label: 'Hand-Tossed', description: 'Classic crust brushed with garlic butter', sizes: ['medium', 'large', 'xl'], upcharges: {} },
    { id: 'thin', label: 'Thin & Crispy', description: 'Cracker-thin, tavern cut into squares', sizes: ['medium', 'large'], upcharges: {} },
    { id: 'stuffed', label: 'Stuffed Crust', description: 'Melty mozzarella baked into the edge', sizes: ['large'], upcharges: { large: 300 } },
    { id: 'ny', label: 'New York Style', description: 'Big, foldable slices', sizes: ['xl'], upcharges: {} },
    { id: 'gluten-free', label: 'Gluten-Free', description: '10" crust made without gluten', sizes: ['medium'], upcharges: { medium: 200 } },
  ],
  sauces: [
    { id: 'marinara', label: 'Classic Marinara' },
    { id: 'garlic-parm', label: 'Creamy Garlic Parmesan' },
    { id: 'bbq', label: 'Smoky BBQ' },
    { id: 'buffalo', label: 'Buffalo' },
    { id: 'none', label: 'No Sauce' },
  ],
  cheeses: [
    { id: 'none', label: 'No Cheese' },
    { id: 'light', label: 'Light' },
    { id: 'regular', label: 'Regular' },
    { id: 'extra', label: 'Extra', extra: true },
  ],
  toppings: [
    { id: 'pepperoni', label: 'Pepperoni', group: 'meat' },
    { id: 'sausage', label: 'Italian Sausage', group: 'meat' },
    { id: 'beef', label: 'Seasoned Beef', group: 'meat' },
    { id: 'ham', label: 'Ham', group: 'meat' },
    { id: 'bacon', label: 'Bacon', group: 'meat' },
    { id: 'chicken', label: 'Grilled Chicken', group: 'meat' },
    { id: 'meatball', label: 'Meatballs', group: 'meat' },
    { id: 'mushroom', label: 'Mushrooms', group: 'veggie' },
    { id: 'green-pepper', label: 'Green Peppers', group: 'veggie' },
    { id: 'onion', label: 'Red Onions', group: 'veggie' },
    { id: 'olive', label: 'Black Olives', group: 'veggie' },
    { id: 'tomato', label: 'Roma Tomatoes', group: 'veggie' },
    { id: 'jalapeno', label: 'Jalapeños', group: 'veggie' },
    { id: 'banana-pepper', label: 'Banana Peppers', group: 'veggie' },
    { id: 'pineapple', label: 'Pineapple', group: 'veggie' },
    { id: 'spinach', label: 'Spinach', group: 'veggie' },
    { id: 'basil', label: 'Fresh Basil', group: 'veggie' },
  ],
};

export interface PizzaConfig {
  sizePrices: Record<SizeId, number>;
  toppings: string[];
  sauce: string;
  cheese: string;
  crust: string;
  defaultSize: SizeId;
  byo?: boolean;
  density?: number;
}

export interface Variant {
  id: string;
  label: string;
  priceCents: number;
  calories?: string;
}

export interface ChoiceGroup {
  id: string;
  label: string;
  required: boolean;
  options: { id: string; label: string }[];
}

export interface ItemConfig {
  pizza?: PizzaConfig;
  variants?: Variant[];
  choices?: ChoiceGroup[];
  includes?: string[];
}

export interface CatalogItem {
  slug: string;
  name: string;
  description: string;
  kind: 'pizza' | 'wings' | 'side' | 'pasta' | 'dessert' | 'drink' | 'dip' | 'deal';
  art: string;
  calories?: string;
  tags?: string[];
  config: ItemConfig;
  priceCents?: number;
}

export interface CatalogCategory {
  slug: string;
  name: string;
  tagline: string;
  prepMinutes: number;
  items: CatalogItem[];
}

const prices = (personal: number, medium: number, large: number, xl: number): Record<SizeId, number> => ({ personal, medium, large, xl });

const pizza = (
  slug: string,
  name: string,
  description: string,
  sizePrices: Record<SizeId, number>,
  toppings: string[],
  extra: Partial<PizzaConfig> & { tags?: string[]; calories?: string } = {},
): CatalogItem => {
  const { tags, calories, ...rest } = extra;
  return {
    slug,
    name,
    description,
    kind: 'pizza',
    art: 'pizza',
    calories: calories ?? '230–380 cal/slice',
    tags,
    config: {
      pizza: { sizePrices, toppings, sauce: 'marinara', cheese: 'regular', crust: 'hand-tossed', defaultSize: 'large', ...rest },
    },
  };
};

const WING_SAUCES: ChoiceGroup = {
  id: 'sauce',
  label: 'Wing sauce',
  required: true,
  options: [
    { id: 'buffalo-mild', label: 'Buffalo Mild' },
    { id: 'buffalo-medium', label: 'Buffalo Medium' },
    { id: 'buffalo-hot', label: "Buffalo Burnin' Hot" },
    { id: 'honey-bbq', label: 'Honey BBQ' },
    { id: 'garlic-parm', label: 'Garlic Parmesan' },
    { id: 'lemon-pepper', label: 'Lemon Pepper Dry Rub' },
    { id: 'spicy-garlic', label: 'Spicy Garlic' },
    { id: 'naked', label: 'Naked (no sauce)' },
  ],
};

const DIP_CHOICE: ChoiceGroup = {
  id: 'dip',
  label: 'Free dip',
  required: true,
  options: [
    { id: 'ranch', label: 'Ranch' },
    { id: 'blue-cheese', label: 'Blue Cheese' },
    { id: 'none', label: 'No dip' },
  ],
};

const ONE_TOPPING = (id: string, label: string): ChoiceGroup => ({
  id,
  label,
  required: true,
  options: [{ id: 'cheese', label: 'Just cheese' }, ...PIZZA_OPTIONS.toppings.map((t) => ({ id: t.id, label: t.label }))],
});

const SODA_CHOICE = (id: string, label: string): ChoiceGroup => ({
  id,
  label,
  required: true,
  options: [
    { id: 'cola', label: 'Cola' },
    { id: 'diet-cola', label: 'Diet Cola' },
    { id: 'lemon-lime', label: 'Lemon-Lime' },
    { id: 'orange', label: 'Orange Soda' },
    { id: 'root-beer', label: 'Root Beer' },
  ],
});

const soda = (slug: string, name: string, art: string, description: string, tags: string[] = []): CatalogItem => ({
  slug,
  name,
  description,
  kind: 'drink',
  art,
  tags,
  config: {
    variants: [
      { id: '20oz', label: '20 oz bottle', priceCents: 249, calories: '0–250 cal' },
      { id: '2l', label: '2-Liter', priceCents: 399, calories: '0–100 cal/8 oz' },
    ],
  },
});

const dip = (slug: string, name: string, art: string): CatalogItem => ({
  slug,
  name,
  description: 'Two-ounce dipping cup',
  kind: 'dip',
  art,
  priceCents: 99,
  config: {},
});

export const CATALOG: CatalogCategory[] = [
  {
    slug: 'deals',
    name: 'Deals & Combos',
    tagline: 'Feed the whole crew for less',
    prepMinutes: 20,
    items: [
      {
        slug: 'big-als-dinner-box',
        name: "Big Al's Dinner Box",
        description: '2 Medium 1-topping pizzas, 5 breadsticks and 6 bone-in wings in one box.',
        kind: 'deal',
        art: 'deal:dinnerbox',
        priceCents: 2799,
        tags: ['popular'],
        calories: '4,300–5,900 cal',
        config: { includes: ['2 Medium 1-Topping Pizzas', '5 Breadsticks', '6 Bone-In Wings'], choices: [ONE_TOPPING('pizza1', 'Pizza #1 topping'), ONE_TOPPING('pizza2', 'Pizza #2 topping'), WING_SAUCES] },
      },
      {
        slug: 'family-feast',
        name: 'Family Feast',
        description: '2 Large 1-topping pizzas, 5 breadsticks and a 2-liter.',
        kind: 'deal',
        art: 'deal:family',
        priceCents: 3299,
        tags: ['popular'],
        calories: '5,200–7,000 cal',
        config: { includes: ['2 Large 1-Topping Pizzas', '5 Breadsticks', '2-Liter Soda'], choices: [ONE_TOPPING('pizza1', 'Pizza #1 topping'), ONE_TOPPING('pizza2', 'Pizza #2 topping'), SODA_CHOICE('soda', '2-Liter flavor')] },
      },
      {
        slug: 'pizza-wings-duo',
        name: 'Pizza & Wings Duo',
        description: '1 Large 1-topping pizza plus 6 bone-in wings.',
        kind: 'deal',
        art: 'deal:duo',
        priceCents: 2199,
        tags: ['new'],
        calories: '2,500–3,400 cal',
        config: { includes: ['1 Large 1-Topping Pizza', '6 Bone-In Wings'], choices: [ONE_TOPPING('pizza1', 'Pizza topping'), WING_SAUCES] },
      },
      {
        slug: 'lunch-combo',
        name: 'Personal Pan Lunch Combo',
        description: 'Personal Pan 1-topping pizza and a 20 oz drink. Perfect for one.',
        kind: 'deal',
        art: 'deal:lunch',
        priceCents: 899,
        calories: '640–900 cal',
        config: { includes: ['Personal Pan 1-Topping Pizza', '20 oz Drink'], choices: [ONE_TOPPING('pizza1', 'Pizza topping'), SODA_CHOICE('soda', 'Drink')] },
      },
    ],
  },
  {
    slug: 'pizza',
    name: 'Pizzas',
    tagline: 'Hand-stretched daily, baked to order',
    prepMinutes: 16,
    items: [
      pizza('pepperoni-overload', 'Pepperoni Overload', 'Double layer of cupped pepperoni over extra mozzarella.', prices(799, 1599, 1899, 2199), ['pepperoni'], { cheese: 'extra', density: 1.7, tags: ['popular'] }),
      pizza('meat-mountain', 'Meat Mountain', 'Pepperoni, Italian sausage, ham, bacon and seasoned beef piled high.', prices(899, 1749, 2049, 2349), ['pepperoni', 'sausage', 'ham', 'bacon', 'beef'], { crust: 'pan', tags: ['popular'], calories: '300–460 cal/slice' }),
      pizza('als-supreme', "Al's Supreme", 'Pepperoni, sausage, mushrooms, green peppers and red onions.', prices(849, 1699, 1999, 2299), ['pepperoni', 'sausage', 'mushroom', 'green-pepper', 'onion'], { tags: ['popular'] }),
      pizza('classic-pepperoni', 'Classic Pepperoni', 'The one everybody agrees on. Pepperoni and mozzarella.', prices(649, 1299, 1599, 1899), ['pepperoni']),
      pizza('classic-cheese', 'Classic Cheese', 'Our signature marinara with a blanket of whole-milk mozzarella.', prices(599, 1199, 1499, 1799), [], { tags: ['veg'] }),
      pizza('bbq-chicken-ranch', 'BBQ Chicken Ranch', 'Smoky BBQ sauce, grilled chicken, bacon and red onions with a ranch drizzle.', prices(849, 1699, 1999, 2299), ['chicken', 'bacon', 'onion'], { sauce: 'bbq' }),
      pizza('buffalo-chicken-blaze', 'Buffalo Chicken Blaze', 'Buffalo sauce, grilled chicken, red onions and banana peppers.', prices(849, 1699, 1999, 2299), ['chicken', 'onion', 'banana-pepper'], { sauce: 'buffalo', tags: ['spicy'] }),
      pizza('chicken-bacon-parm', 'Chicken Bacon Parm', 'Creamy garlic parmesan sauce, grilled chicken, bacon and Roma tomatoes.', prices(849, 1699, 1999, 2299), ['chicken', 'bacon', 'tomato'], { sauce: 'garlic-parm', tags: ['new'] }),
      pizza('garden-veggie', 'Garden Veggie', 'Mushrooms, green peppers, red onions, black olives and Roma tomatoes.', prices(799, 1599, 1899, 2199), ['mushroom', 'green-pepper', 'onion', 'olive', 'tomato'], { tags: ['veg'] }),
      pizza('hawaiian-sunset', 'Hawaiian Sunset', 'Ham, bacon and sweet pineapple. Yes, pineapple.', prices(799, 1599, 1899, 2199), ['ham', 'bacon', 'pineapple']),
      pizza('basil-margherita', 'Basil Margherita', 'Roma tomatoes, fresh basil and mozzarella on a thin, crispy crust.', prices(749, 1499, 1799, 2099), ['tomato', 'basil'], { crust: 'thin', tags: ['veg'] }),
      pizza('jalapeno-popper', 'Jalapeño Popper', 'Creamy garlic parm, bacon, jalapeños and extra cheese.', prices(849, 1699, 1999, 2299), ['bacon', 'jalapeno'], { sauce: 'garlic-parm', cheese: 'extra', tags: ['spicy', 'new'] }),
      pizza('build-your-own', 'Build Your Own', 'Start with cheese and make it exactly how you like it.', prices(599, 1199, 1499, 1799), [], { byo: true, tags: ['popular'] }),
    ],
  },
  {
    slug: 'wings',
    name: 'Wings',
    tagline: 'Sauced, tossed & ready to share',
    prepMinutes: 14,
    items: [
      {
        slug: 'bone-in-wings',
        name: 'Bone-In Wings',
        description: 'Crispy, juicy traditional wings tossed in your favorite sauce.',
        kind: 'wings',
        art: 'wings:buffalo',
        tags: ['popular'],
        config: {
          variants: [
            { id: '6', label: '6 pc', priceCents: 899, calories: '480–720 cal' },
            { id: '12', label: '12 pc', priceCents: 1649, calories: '960–1,440 cal' },
            { id: '18', label: '18 pc', priceCents: 2399, calories: '1,440–2,160 cal' },
          ],
          choices: [WING_SAUCES, DIP_CHOICE],
        },
      },
      {
        slug: 'boneless-wings',
        name: 'Boneless Wings',
        description: 'All-white-meat bites, breaded and tossed in sauce.',
        kind: 'wings',
        art: 'wings:bbq',
        config: {
          variants: [
            { id: '8', label: '8 pc', priceCents: 799, calories: '560–800 cal' },
            { id: '16', label: '16 pc', priceCents: 1499, calories: '1,120–1,600 cal' },
            { id: '24', label: '24 pc', priceCents: 2149, calories: '1,680–2,400 cal' },
          ],
          choices: [WING_SAUCES, DIP_CHOICE],
        },
      },
    ],
  },
  {
    slug: 'sides',
    name: 'Sides',
    tagline: 'Every pizza needs a sidekick',
    prepMinutes: 10,
    items: [
      { slug: 'breadsticks', name: 'Breadsticks', description: '5 garlic-butter breadsticks with marinara.', kind: 'side', art: 'breadsticks', priceCents: 649, tags: ['popular'], calories: '700 cal', config: {} },
      { slug: 'cheese-sticks', name: 'Cheese Sticks', description: 'Our crust topped with garlic butter and mozzarella, cut into 10 sticks.', kind: 'side', art: 'cheesesticks', priceCents: 799, calories: '1,050 cal', config: {} },
      { slug: 'garlic-knots', name: 'Garlic Knots', description: '8 hand-tied knots brushed with garlic butter and parmesan.', kind: 'side', art: 'knots', priceCents: 699, tags: ['new'], calories: '760 cal', config: {} },
      { slug: 'mozzarella-sticks', name: 'Mozzarella Sticks', description: '6 breaded mozzarella sticks with marinara.', kind: 'side', art: 'mozz', priceCents: 749, calories: '620 cal', config: {} },
      { slug: 'seasoned-fries', name: 'Seasoned Fries', description: 'Crispy fries with our house seasoning.', kind: 'side', art: 'fries', priceCents: 499, calories: '480 cal', config: {} },
    ],
  },
  {
    slug: 'pasta',
    name: 'Pasta',
    tagline: 'Oven-baked, family-tray sized',
    prepMinutes: 14,
    items: [
      { slug: 'chicken-alfredo', name: 'Chicken Alfredo', description: 'Rotini in creamy alfredo with grilled chicken, baked with mozzarella.', kind: 'pasta', art: 'pasta:alfredo', priceCents: 1099, calories: '1,200 cal', config: {} },
      { slug: 'meaty-marinara', name: 'Meaty Marinara', description: 'Rotini with marinara, Italian sausage and meatballs, baked with mozzarella.', kind: 'pasta', art: 'pasta:marinara', priceCents: 1099, tags: ['popular'], calories: '1,300 cal', config: {} },
      { slug: 'veggie-primavera', name: 'Veggie Primavera', description: 'Rotini with marinara, spinach, mushrooms and tomatoes.', kind: 'pasta', art: 'pasta:veggie', priceCents: 999, tags: ['veg'], calories: '980 cal', config: {} },
    ],
  },
  {
    slug: 'desserts',
    name: 'Desserts',
    tagline: 'Save room. Trust us.',
    prepMinutes: 8,
    items: [
      { slug: 'cinnamon-twists', name: 'Cinnamon Twists', description: '10 twists dusted with cinnamon sugar with sweet icing for dipping.', kind: 'dessert', art: 'cinnamon', priceCents: 549, tags: ['popular'], calories: '920 cal', config: {} },
      { slug: 'triple-chocolate-brownie', name: 'Triple Chocolate Brownie', description: 'Fudgy brownie loaded with chocolate chunks, cut into 9 squares.', kind: 'dessert', art: 'brownie', priceCents: 799, calories: '1,800 cal', config: {} },
      { slug: 'giant-cookie', name: 'Giant Chocolate Chip Cookie', description: 'A warm, gooey 8-slice cookie baked fresh.', kind: 'dessert', art: 'cookie', priceCents: 799, tags: ['new'], calories: '1,500 cal', config: {} },
      { slug: 'mini-cinnamon-rolls', name: 'Mini Cinnamon Rolls', description: '10 mini rolls with cream cheese frosting.', kind: 'dessert', art: 'rolls', priceCents: 699, calories: '1,060 cal', config: {} },
    ],
  },
  {
    slug: 'drinks',
    name: 'Drinks',
    tagline: 'Ice cold, always',
    prepMinutes: 1,
    items: [
      soda('cola', 'Cola', 'soda:cola', 'Classic cola.', ['popular']),
      soda('diet-cola', 'Diet Cola', 'soda:diet', 'Zero sugar cola.'),
      soda('lemon-lime', 'Lemon-Lime Soda', 'soda:lemon', 'Crisp, caffeine-free citrus soda.'),
      soda('orange-soda', 'Orange Soda', 'soda:orange', 'Sweet orange fizz.'),
      soda('root-beer', 'Root Beer', 'soda:rootbeer', 'Creamy old-fashioned root beer.'),
      {
        slug: 'sweet-tea',
        name: 'Sweet Tea',
        description: 'Fresh brewed Southern-style sweet tea.',
        kind: 'drink',
        art: 'soda:tea',
        config: { variants: [{ id: '20oz', label: '20 oz bottle', priceCents: 249 }, { id: 'gallon', label: 'Gallon jug', priceCents: 599 }] },
      },
      { slug: 'bottled-water', name: 'Bottled Water', description: '16.9 oz spring water.', kind: 'drink', art: 'soda:water', priceCents: 199, config: {} },
    ],
  },
  {
    slug: 'dips',
    name: 'Dips & Sauces',
    tagline: 'Dunk responsibly',
    prepMinutes: 1,
    items: [
      dip('marinara-dip', 'Marinara', 'dip:marinara'),
      dip('ranch-dip', 'Ranch', 'dip:ranch'),
      dip('garlic-butter-dip', 'Garlic Butter', 'dip:garlic'),
      dip('blue-cheese-dip', 'Blue Cheese', 'dip:bluecheese'),
      dip('honey-bbq-dip', 'Honey BBQ', 'dip:bbq'),
    ],
  },
];

/** Items offered in the "Complete your meal" popup after adding something to the cart. */
export const UPSELL = {
  sides: ['breadsticks', 'garlic-knots', 'cheese-sticks', 'mozzarella-sticks'],
  desserts: ['cinnamon-twists', 'triple-chocolate-brownie', 'giant-cookie', 'mini-cinnamon-rolls'],
  drinks: ['cola', 'diet-cola', 'lemon-lime', 'root-beer', 'sweet-tea'],
};

export function catalogDisplayPrice(item: CatalogItem): number {
  if (item.config.pizza) return item.config.pizza.sizePrices.personal;
  if (item.config.variants?.length) return Math.min(...item.config.variants.map((v) => v.priceCents));
  return item.priceCents ?? 0;
}
