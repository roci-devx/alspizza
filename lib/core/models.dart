import 'api.dart';
import 'format.dart';

List<T> _list<T>(dynamic v, T Function(Json) f) => ((v as List?) ?? const []).map((e) => f(e as Json)).toList();
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
double? _dbl(dynamic v) => (v as num?)?.toDouble();

class AppUser {
  const AppUser({required this.id, this.name, this.email, this.phone, required this.isGuest, this.role = 'customer'});

  final String id;
  final String? name;
  final String? email;
  final String? phone;
  final bool isGuest;
  final String role;

  String get firstName => (name ?? '').split(' ').first;

  factory AppUser.fromJson(Json j) => AppUser(
    id: j['id'] as String,
    name: j['name'] as String?,
    email: j['email'] as String?,
    phone: j['phone'] as String?,
    isGuest: j['isGuest'] as bool? ?? true,
    role: j['role'] as String? ?? 'customer',
  );

  Json toJson() => {'id': id, 'name': name, 'email': email, 'phone': phone, 'isGuest': isGuest, 'role': role};
}

class PlaceAddress {
  const PlaceAddress({
    required this.line1,
    this.line2,
    required this.city,
    required this.state,
    required this.zip,
    this.lat,
    this.lng,
    this.instructions,
    this.label,
  });

  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String zip;
  final double? lat;
  final double? lng;
  final String? instructions;
  final String? label;

  String get short => line1;
  String get full => '$line1${line2 != null && line2!.isNotEmpty ? ', $line2' : ''}, $city, $state $zip';

  PlaceAddress copyWith({String? line2, String? instructions}) => PlaceAddress(
    line1: line1,
    line2: line2 ?? this.line2,
    city: city,
    state: state,
    zip: zip,
    lat: lat,
    lng: lng,
    instructions: instructions ?? this.instructions,
    label: label,
  );

  factory PlaceAddress.fromJson(Json j) => PlaceAddress(
    line1: j['line1'] as String? ?? '',
    line2: j['line2'] as String?,
    city: j['city'] as String? ?? '',
    state: j['state'] as String? ?? '',
    zip: j['zip'] as String? ?? '',
    lat: _dbl(j['lat']),
    lng: _dbl(j['lng']),
    instructions: j['instructions'] as String?,
    label: j['label'] as String?,
  );

  Json toJson() => {
    'line1': line1,
    'line2': line2,
    'city': city,
    'state': state,
    'zip': zip,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    'instructions': instructions,
    if (label != null) 'label': label,
  };
}

class StoreInfo {
  const StoreInfo({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.lat,
    required this.lng,
    required this.isOpen,
    required this.hoursToday,
    required this.acceptingOrders,
    required this.pickupEnabled,
    required this.deliveryEnabled,
    required this.cashEnabled,
    required this.minDeliveryCents,
    this.distanceMiles,
    this.deliversToYou,
    this.pickupEtaMinutes,
  });

  final String id;
  final String name;
  final String phone;
  final PlaceAddress address;
  final double lat;
  final double lng;
  final bool isOpen;
  final String hoursToday;
  final bool acceptingOrders;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final bool cashEnabled;
  final int minDeliveryCents;
  final double? distanceMiles;
  final bool? deliversToYou;
  final int? pickupEtaMinutes;

  /// "Lincoln Park" from "Al's Pizza — Lincoln Park".
  String get shortName => name.contains('—') ? name.split('—').last.trim() : name;

  factory StoreInfo.fromJson(Json j) => StoreInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String? ?? '',
    address: PlaceAddress.fromJson(j['address'] as Json),
    lat: _dbl(j['lat']) ?? 0,
    lng: _dbl(j['lng']) ?? 0,
    isOpen: j['isOpen'] as bool? ?? true,
    hoursToday: j['hoursToday'] as String? ?? '',
    acceptingOrders: j['acceptingOrders'] as bool? ?? true,
    pickupEnabled: j['pickupEnabled'] as bool? ?? true,
    deliveryEnabled: j['deliveryEnabled'] as bool? ?? true,
    cashEnabled: j['cashEnabled'] as bool? ?? false,
    minDeliveryCents: _int(j['minDeliveryCents']),
    distanceMiles: _dbl(j['distanceMiles']),
    deliversToYou: j['deliversToYou'] as bool?,
    pickupEtaMinutes: (j['pickupEtaMinutes'] as num?)?.toInt(),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address.toJson(),
    'lat': lat,
    'lng': lng,
    'isOpen': isOpen,
    'hoursToday': hoursToday,
    'acceptingOrders': acceptingOrders,
    'pickupEnabled': pickupEnabled,
    'deliveryEnabled': deliveryEnabled,
    'cashEnabled': cashEnabled,
    'minDeliveryCents': minDeliveryCents,
    'distanceMiles': distanceMiles,
    'deliversToYou': deliversToYou,
    'pickupEtaMinutes': pickupEtaMinutes,
  };
}

// ── Menu ──────────────────────────────────────────────────────────────────────

class PizzaSize {
  const PizzaSize(this.id, this.label, this.inches, this.slices, this.toppingCents);
  final String id;
  final String label;
  final int inches;
  final int slices;
  final int toppingCents;
  factory PizzaSize.fromJson(Json j) => PizzaSize(j['id'] as String, j['label'] as String, _int(j['inches']), _int(j['slices']), _int(j['toppingCents']));
  Json toJson() => {'id': id, 'label': label, 'inches': inches, 'slices': slices, 'toppingCents': toppingCents};
}

class Crust {
  const Crust(this.id, this.label, this.description, this.sizes, this.upcharges);
  final String id;
  final String label;
  final String description;
  final List<String> sizes;
  final Map<String, int> upcharges;
  factory Crust.fromJson(Json j) => Crust(
    j['id'] as String,
    j['label'] as String,
    j['description'] as String? ?? '',
    ((j['sizes'] as List?) ?? const []).cast<String>(),
    ((j['upcharges'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, _int(v))),
  );
  Json toJson() => {'id': id, 'label': label, 'description': description, 'sizes': sizes, 'upcharges': upcharges};
}

class Option {
  const Option(this.id, this.label, {this.extra = false, this.group, this.art});
  final String id;
  final String label;
  final bool extra;
  final String? group;

  /// For toppings: which built-in topping drawing to use (lets owners add new toppings).
  final String? art;
  factory Option.fromJson(Json j) =>
      Option(j['id'] as String, j['label'] as String, extra: j['extra'] as bool? ?? false, group: j['group'] as String?, art: j['art'] as String?);
  Json toJson() => {'id': id, 'label': label, if (extra) 'extra': true, 'group': ?group, 'art': ?art};
}

class PizzaOptions {
  const PizzaOptions({required this.sizes, required this.crusts, required this.sauces, required this.cheeses, required this.toppings});
  final List<PizzaSize> sizes;
  final List<Crust> crusts;
  final List<Option> sauces;
  final List<Option> cheeses;
  final List<Option> toppings;

  PizzaSize size(String id) => sizes.firstWhere((s) => s.id == id, orElse: () => sizes.first);
  Json toJson() => {
    'sizes': sizes.map((s) => s.toJson()).toList(),
    'crusts': crusts.map((c) => c.toJson()).toList(),
    'sauces': sauces.map((s) => s.toJson()).toList(),
    'cheeses': cheeses.map((c) => c.toJson()).toList(),
    'toppings': toppings.map((t) => t.toJson()).toList(),
  };
  Crust? crust(String id) => crusts.where((c) => c.id == id).firstOrNull;
  String toppingLabel(String id) => toppings.where((t) => t.id == id).firstOrNull?.label ?? id;

  factory PizzaOptions.fromJson(Json j) => PizzaOptions(
    sizes: _list(j['sizes'], PizzaSize.fromJson),
    crusts: _list(j['crusts'], Crust.fromJson),
    sauces: _list(j['sauces'], Option.fromJson),
    cheeses: _list(j['cheeses'], Option.fromJson),
    toppings: _list(j['toppings'], Option.fromJson),
  );
}

class PizzaConfig {
  const PizzaConfig({
    required this.sizePrices,
    required this.toppings,
    required this.sauce,
    required this.cheese,
    required this.crust,
    required this.defaultSize,
    this.byo = false,
    this.density = 1,
  });
  final Map<String, int> sizePrices;
  final List<String> toppings;
  final String sauce;
  final String cheese;
  final String crust;
  final String defaultSize;
  final bool byo;
  final double density;

  factory PizzaConfig.fromJson(Json j) => PizzaConfig(
    sizePrices: ((j['sizePrices'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, _int(v))),
    toppings: ((j['toppings'] as List?) ?? const []).cast<String>(),
    sauce: j['sauce'] as String? ?? 'marinara',
    cheese: j['cheese'] as String? ?? 'regular',
    crust: j['crust'] as String? ?? 'hand-tossed',
    defaultSize: j['defaultSize'] as String? ?? 'large',
    byo: j['byo'] as bool? ?? false,
    density: _dbl(j['density']) ?? 1,
  );
}

class Variant {
  const Variant(this.id, this.label, this.priceCents, this.calories);
  final String id;
  final String label;
  final int priceCents;
  final String? calories;
  factory Variant.fromJson(Json j) => Variant(j['id'] as String, j['label'] as String, _int(j['priceCents']), j['calories'] as String?);
}

class ChoiceGroup {
  const ChoiceGroup(this.id, this.label, this.required, this.options);
  final String id;
  final String label;
  final bool required;
  final List<Option> options;
  factory ChoiceGroup.fromJson(Json j) =>
      ChoiceGroup(j['id'] as String, j['label'] as String, j['required'] as bool? ?? true, _list(j['options'], Option.fromJson));
}

class ItemConfig {
  const ItemConfig({this.pizza, this.variants = const [], this.choices = const [], this.includes = const []});
  final PizzaConfig? pizza;
  final List<Variant> variants;
  final List<ChoiceGroup> choices;
  final List<String> includes;

  factory ItemConfig.fromJson(Json j) => ItemConfig(
    pizza: j['pizza'] == null ? null : PizzaConfig.fromJson(j['pizza'] as Json),
    variants: _list(j['variants'], Variant.fromJson),
    choices: _list(j['choices'], ChoiceGroup.fromJson),
    includes: ((j['includes'] as List?) ?? const []).cast<String>(),
  );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.slug,
    required this.categorySlug,
    required this.name,
    required this.description,
    required this.kind,
    required this.priceCents,
    required this.art,
    required this.tags,
    required this.isAvailable,
    required this.config,
    required this.raw,
    this.calories,
    this.imageUrl,
    this.prepMinutes,
  });

  final String id;
  final String slug;
  final String categorySlug;
  final String name;
  final String description;
  final String kind;
  final int priceCents;
  final String art;
  final List<String> tags;
  final bool isAvailable;
  final ItemConfig config;
  final Json raw;
  final String? calories;
  final String? imageUrl;
  final int? prepMinutes;

  bool get isPizza => config.pizza != null;

  /// Items with nothing to choose can be added in one tap.
  bool get isQuickAdd => !isPizza && config.choices.isEmpty && config.variants.length <= 1;

  bool get hasOptions => !isQuickAdd;

  factory MenuItem.fromJson(Json j) => MenuItem(
    id: j['id'] as String,
    slug: j['slug'] as String? ?? '',
    categorySlug: j['categorySlug'] as String? ?? '',
    name: j['name'] as String,
    description: j['description'] as String? ?? '',
    kind: j['kind'] as String? ?? 'side',
    priceCents: _int(j['priceCents']),
    art: j['art'] as String? ?? 'pizza',
    tags: ((j['tags'] as List?) ?? const []).cast<String>(),
    isAvailable: j['isAvailable'] as bool? ?? true,
    config: ItemConfig.fromJson((j['config'] as Json?) ?? const {}),
    calories: j['calories'] as String?,
    imageUrl: j['imageUrl'] as String?,
    prepMinutes: (j['prepMinutes'] as num?)?.toInt(),
    raw: j,
  );
}

class MenuCategory {
  const MenuCategory({required this.id, required this.slug, required this.name, required this.tagline, required this.prepMinutes, required this.items});
  final String id;
  final String slug;
  final String name;
  final String tagline;
  final int prepMinutes;
  final List<MenuItem> items;

  factory MenuCategory.fromJson(Json j) => MenuCategory(
    id: j['id'] as String,
    slug: j['slug'] as String,
    name: j['name'] as String,
    tagline: j['tagline'] as String? ?? '',
    prepMinutes: _int(j['prepMinutes']),
    items: _list(j['items'], MenuItem.fromJson),
  );
}

class MenuData {
  const MenuData({required this.categories, required this.pizzaOptions, required this.upsell});
  final List<MenuCategory> categories;
  final PizzaOptions pizzaOptions;
  final Map<String, List<String>> upsell;

  Iterable<MenuItem> get allItems => categories.expand((c) => c.items);
  MenuItem? item(String id) => allItems.where((i) => i.id == id).firstOrNull;
  List<MenuItem> upsellFor(String group) => (upsell[group] ?? const []).map(item).whereType<MenuItem>().where((i) => i.isAvailable).toList();
  List<MenuItem> get popular => allItems.where((i) => i.tags.contains('popular') && i.isAvailable).toList();

  factory MenuData.fromJson(Json j) => MenuData(
    categories: _list(j['categories'], MenuCategory.fromJson),
    pizzaOptions: PizzaOptions.fromJson(j['pizzaOptions'] as Json),
    upsell: ((j['upsell'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
  );
}

// ── Cart ──────────────────────────────────────────────────────────────────────

class PizzaSelection {
  const PizzaSelection({required this.size, required this.crust, required this.sauce, required this.cheese, required this.toppings});
  final String size;
  final String crust;
  final String sauce;
  final String cheese;
  final List<String> toppings;

  factory PizzaSelection.defaults(PizzaConfig c) =>
      PizzaSelection(size: c.defaultSize, crust: c.crust, sauce: c.sauce, cheese: c.cheese, toppings: [...c.toppings]);

  PizzaSelection copyWith({String? size, String? crust, String? sauce, String? cheese, List<String>? toppings}) => PizzaSelection(
    size: size ?? this.size,
    crust: crust ?? this.crust,
    sauce: sauce ?? this.sauce,
    cheese: cheese ?? this.cheese,
    toppings: toppings ?? this.toppings,
  );

  factory PizzaSelection.fromJson(Json j) => PizzaSelection(
    size: j['size'] as String,
    crust: j['crust'] as String,
    sauce: j['sauce'] as String,
    cheese: j['cheese'] as String,
    toppings: ((j['toppings'] as List?) ?? const []).cast<String>(),
  );

  Json toJson() => {'size': size, 'crust': crust, 'sauce': sauce, 'cheese': cheese, 'toppings': toppings};
}

/// Display price for a configured pizza (mirrors the server's pricing rules).
int pizzaUnitPrice(PizzaConfig cfg, PizzaSelection sel, PizzaOptions opts) {
  final size = opts.size(sel.size);
  final crust = opts.crust(sel.crust);
  final extras = sel.toppings.where((t) => !cfg.toppings.contains(t)).length;
  final cheese = opts.cheeses.where((c) => c.id == sel.cheese).firstOrNull;
  final extraCheese = (cheese?.extra ?? false) && cfg.cheese != 'extra' ? size.toppingCents : 0;
  return (cfg.sizePrices[size.id] ?? 0) + (crust?.upcharges[size.id] ?? 0) + extras * size.toppingCents + extraCheese;
}

class CartLine {
  const CartLine({
    required this.key,
    required this.itemId,
    required this.name,
    required this.art,
    required this.kind,
    required this.quantity,
    required this.unitPriceCents,
    required this.summary,
    this.variantId,
    this.choices = const {},
    this.pizza,
    this.notes,
  });

  final String key;
  final String itemId;
  final String name;
  final String art;
  final String kind;
  final int quantity;
  final int unitPriceCents;
  final String summary;
  final String? variantId;
  final Map<String, String> choices;
  final PizzaSelection? pizza;
  final String? notes;

  int get totalCents => unitPriceCents * quantity;

  /// Same item + same options = same line (quantities merge).
  String get signature => '$itemId|$variantId|${choices.entries.map((e) => '${e.key}=${e.value}').join(',')}|${pizza?.toJson()}|$notes';

  CartLine copyWith({int? quantity, int? unitPriceCents, String? summary}) => CartLine(
    key: key,
    itemId: itemId,
    name: name,
    art: art,
    kind: kind,
    quantity: quantity ?? this.quantity,
    unitPriceCents: unitPriceCents ?? this.unitPriceCents,
    summary: summary ?? this.summary,
    variantId: variantId,
    choices: choices,
    pizza: pizza,
    notes: notes,
  );

  Json toApi() => {
    'itemId': itemId,
    'quantity': quantity,
    if (variantId != null) 'variantId': variantId,
    if (choices.isNotEmpty) 'choices': choices,
    if (pizza != null) 'pizza': pizza!.toJson(),
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };

  Json toJson() => {...toApi(), 'key': key, 'name': name, 'art': art, 'kind': kind, 'unitPriceCents': unitPriceCents, 'summary': summary};

  factory CartLine.fromJson(Json j) => CartLine(
    key: j['key'] as String,
    itemId: j['itemId'] as String,
    name: j['name'] as String,
    art: j['art'] as String,
    kind: j['kind'] as String? ?? '',
    quantity: _int(j['quantity']),
    unitPriceCents: _int(j['unitPriceCents']),
    summary: j['summary'] as String? ?? '',
    variantId: j['variantId'] as String?,
    choices: ((j['choices'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
    pizza: j['pizza'] == null ? null : PizzaSelection.fromJson(j['pizza'] as Json),
    notes: j['notes'] as String?,
  );
}

class PriceQuote {
  const PriceQuote({
    required this.subtotalCents,
    required this.discountCents,
    required this.deliveryFeeCents,
    required this.taxCents,
    required this.tipCents,
    required this.totalCents,
    required this.pickupEtaMinutes,
    required this.lineSummaries,
    this.deliveryEtaMinutes,
    this.promoCode,
    this.promoLabel,
    this.promoError,
    this.minDeliveryCents = 0,
  });

  final int subtotalCents;
  final int discountCents;
  final int deliveryFeeCents;
  final int taxCents;
  final int tipCents;
  final int totalCents;
  final int pickupEtaMinutes;
  final int? deliveryEtaMinutes;
  final String? promoCode;
  final String? promoLabel;
  final String? promoError;
  final int minDeliveryCents;
  final List<({String summary, int unitPriceCents})> lineSummaries;

  factory PriceQuote.fromJson(Json j) {
    final promo = j['promo'] as Json?;
    return PriceQuote(
      subtotalCents: _int(j['subtotalCents']),
      discountCents: _int(j['discountCents']),
      deliveryFeeCents: _int(j['deliveryFeeCents']),
      taxCents: _int(j['taxCents']),
      tipCents: _int(j['tipCents']),
      totalCents: _int(j['totalCents']),
      pickupEtaMinutes: _int(j['pickupEtaMinutes']),
      deliveryEtaMinutes: (j['deliveryEtaMinutes'] as num?)?.toInt(),
      promoCode: promo?['code'] as String?,
      promoLabel: promo?['label'] as String?,
      promoError: promo?['error'] as String?,
      minDeliveryCents: _int(j['minDeliveryCents']),
      lineSummaries: ((j['lines'] as List?) ?? const [])
          .map((l) => (summary: (l as Json)['summary'] as String? ?? '', unitPriceCents: _int(l['unitPriceCents'])))
          .toList(),
    );
  }
}

class DeliveryQuote {
  const DeliveryQuote({
    required this.quoteId,
    required this.feeCents,
    required this.etaMinutes,
    required this.expiresAt,
    required this.miles,
    required this.address,
    this.approximate = false,
  });
  final String quoteId;
  final int feeCents;
  final int etaMinutes;
  final DateTime expiresAt;
  final double miles;
  final PlaceAddress address;
  final bool approximate;

  bool get isFresh => expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 20)));

  factory DeliveryQuote.fromJson(Json j) => DeliveryQuote(
    quoteId: j['quoteId'] as String,
    feeCents: _int(j['feeCents']),
    etaMinutes: _int(j['etaMinutes']),
    expiresAt: parseDate(j['expiresAt']) ?? DateTime.now(),
    miles: _dbl(j['miles']) ?? 0,
    address: PlaceAddress.fromJson(j['address'] as Json),
    approximate: j['approximate'] as bool? ?? false,
  );
}

// ── Orders ────────────────────────────────────────────────────────────────────

class DeliveryInfo {
  const DeliveryInfo({
    required this.status,
    this.driverName,
    this.driverPhone,
    this.driverVehicle,
    this.driverLat,
    this.driverLng,
    this.dropoffEta,
    this.provider,
    this.providerFeeCents,
    this.trackingUrl,
  });
  final String status;
  final String? driverName;
  final String? driverPhone;
  final String? driverVehicle;
  final double? driverLat;
  final double? driverLng;
  final DateTime? dropoffEta;
  final String? provider; // owner view only
  final int? providerFeeCents;
  final String? trackingUrl;

  bool get hasDriver => driverName != null;

  DeliveryInfo withLocation(double lat, double lng, String status) => DeliveryInfo(
    status: status,
    driverName: driverName,
    driverPhone: driverPhone,
    driverVehicle: driverVehicle,
    driverLat: lat,
    driverLng: lng,
    dropoffEta: dropoffEta,
    provider: provider,
    providerFeeCents: providerFeeCents,
    trackingUrl: trackingUrl,
  );

  factory DeliveryInfo.fromJson(Json j) => DeliveryInfo(
    status: j['status'] as String? ?? 'created',
    driverName: j['driverName'] as String?,
    driverPhone: j['driverPhone'] as String?,
    driverVehicle: j['driverVehicle'] as String?,
    driverLat: _dbl(j['driverLat']),
    driverLng: _dbl(j['driverLng']),
    dropoffEta: parseDate(j['dropoffEta']),
    provider: j['provider'] as String?,
    providerFeeCents: (j['providerFeeCents'] as num?)?.toInt(),
    trackingUrl: j['trackingUrl'] as String?,
  );
}

class OrderLine {
  const OrderLine({
    required this.menuItemId,
    required this.name,
    required this.art,
    required this.kind,
    required this.quantity,
    required this.totalCents,
    required this.unitPriceCents,
    required this.summary,
    required this.config,
  });
  final String menuItemId;
  final String name;
  final String art;
  final String kind;
  final int quantity;
  final int unitPriceCents;
  final int totalCents;
  final String summary;
  final Json config;

  factory OrderLine.fromJson(Json j) => OrderLine(
    menuItemId: j['menuItemId'] as String? ?? '',
    name: j['name'] as String,
    art: j['art'] as String? ?? 'pizza',
    kind: j['kind'] as String? ?? '',
    quantity: _int(j['quantity']),
    unitPriceCents: _int(j['unitPriceCents']),
    totalCents: _int(j['totalCents']),
    summary: j['summary'] as String? ?? '',
    config: (j['config'] as Json?) ?? const {},
  );
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.status,
    required this.fulfillment,
    required this.storeId,
    required this.storeName,
    required this.storePhone,
    required this.storeAddress,
    required this.storeLat,
    required this.storeLng,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.itemsCount,
    required this.subtotalCents,
    required this.discountCents,
    required this.deliveryFeeCents,
    required this.taxCents,
    required this.tipCents,
    required this.totalCents,
    required this.paymentStatus,
    required this.createdAt,
    required this.raw,
    this.customerEmail,
    this.address,
    this.promoCode,
    this.paymentMethod,
    this.paymentProvider,
    this.platform,
    this.notes,
    this.estimatedReadyAt,
    this.estimatedDeliveryAt,
    this.paidAt,
    this.readyAt,
    this.completedAt,
    this.delivery,
    this.messageCount = 0,
    this.posProvider,
    this.posError,
    this.promoChannel,
  });

  final String id;
  final int number;
  final String status;
  final String fulfillment;
  final String storeId;
  final String storeName;
  final String storePhone;
  final PlaceAddress storeAddress;
  final double storeLat;
  final double storeLng;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final PlaceAddress? address;
  final List<OrderLine> items;
  final int itemsCount;
  final int subtotalCents;
  final int discountCents;
  final int deliveryFeeCents;
  final int taxCents;
  final int tipCents;
  final int totalCents;
  final String? promoCode;
  final String paymentStatus;
  final String? paymentMethod;
  final String? paymentProvider;
  final String? platform;
  final String? notes;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? estimatedReadyAt;
  final DateTime? estimatedDeliveryAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final DeliveryInfo? delivery;
  final int messageCount;
  final String? posProvider;
  final String? posError;
  final String? promoChannel;
  final Json raw;

  bool get isDelivery => fulfillment == 'delivery';
  bool get isActive => const ['received', 'preparing', 'ready', 'out_for_delivery'].contains(status);
  bool get isDone => status == 'completed' || status == 'cancelled';

  Order withDriverLocation(double lat, double lng, String deliveryStatus) {
    final d = delivery;
    if (d == null) return this;
    return Order.fromJson({
      ...raw,
      'delivery': {...?(raw['delivery'] as Json?), 'driverLat': lat, 'driverLng': lng, 'status': deliveryStatus},
    });
  }

  factory Order.fromJson(Json j) {
    final store = (j['store'] as Json?) ?? const {};
    return Order(
      id: j['id'] as String,
      number: _int(j['number']),
      status: j['status'] as String,
      fulfillment: j['fulfillment'] as String,
      storeId: j['storeId'] as String? ?? '',
      storeName: store['name'] as String? ?? "Al's Pizza",
      storePhone: store['phone'] as String? ?? '',
      storeAddress: PlaceAddress.fromJson((store['address'] as Json?) ?? const {}),
      storeLat: _dbl(store['lat']) ?? 0,
      storeLng: _dbl(store['lng']) ?? 0,
      customerName: j['customerName'] as String? ?? '',
      customerPhone: j['customerPhone'] as String? ?? '',
      customerEmail: j['customerEmail'] as String?,
      address: j['address'] == null ? null : PlaceAddress.fromJson(j['address'] as Json),
      items: _list(j['items'], OrderLine.fromJson),
      itemsCount: _int(j['itemsCount']),
      subtotalCents: _int(j['subtotalCents']),
      discountCents: _int(j['discountCents']),
      deliveryFeeCents: _int(j['deliveryFeeCents']),
      taxCents: _int(j['taxCents']),
      tipCents: _int(j['tipCents']),
      totalCents: _int(j['totalCents']),
      promoCode: j['promoCode'] as String?,
      paymentStatus: j['paymentStatus'] as String? ?? 'unpaid',
      paymentMethod: j['paymentMethod'] as String?,
      paymentProvider: j['paymentProvider'] as String?,
      platform: j['platform'] as String?,
      notes: j['notes'] as String?,
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
      paidAt: parseDate(j['paidAt']),
      estimatedReadyAt: parseDate(j['estimatedReadyAt']),
      estimatedDeliveryAt: parseDate(j['estimatedDeliveryAt']),
      readyAt: parseDate(j['readyAt']),
      completedAt: parseDate(j['completedAt']),
      delivery: j['delivery'] == null ? null : DeliveryInfo.fromJson(j['delivery'] as Json),
      messageCount: _int(j['messageCount']),
      posProvider: j['posProvider'] as String?,
      posError: j['posError'] as String?,
      promoChannel: j['promoChannel'] as String?,
      raw: j,
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.id, required this.sender, required this.body, required this.createdAt});
  final String id;
  final String sender;
  final String body;
  final DateTime createdAt;
  factory ChatMessage.fromJson(Json j) =>
      ChatMessage(id: j['id'] as String, sender: j['sender'] as String, body: j['body'] as String, createdAt: parseDate(j['createdAt']) ?? DateTime.now());
}

class Deal {
  const Deal({required this.code, required this.description, required this.label, required this.minSubtotalCents, this.endsAt, this.firstOrderOnly = false});
  final String code;
  final String description;
  final String label;
  final int minSubtotalCents;
  final DateTime? endsAt;
  final bool firstOrderOnly;
  factory Deal.fromJson(Json j) => Deal(
    code: j['code'] as String,
    description: j['description'] as String? ?? '',
    label: j['label'] as String? ?? '',
    minSubtotalCents: _int(j['minSubtotalCents']),
    endsAt: parseDate(j['endsAt']),
    firstOrderOnly: j['firstOrderOnly'] as bool? ?? false,
  );
}

class PaymentSetup {
  const PaymentSetup({
    required this.stripe,
    required this.paypal,
    required this.demo,
    this.stripePublishableKey,
    this.appleMerchantId,
    this.merchantName = "Al's Pizza",
  });
  final bool stripe;
  final bool paypal;
  final bool demo;
  final String? stripePublishableKey;
  final String? appleMerchantId;
  final String merchantName;

  factory PaymentSetup.fromJson(Json j) => PaymentSetup(
    stripe: j['stripe'] as bool? ?? false,
    paypal: j['paypal'] as bool? ?? false,
    demo: j['demo'] as bool? ?? false,
    stripePublishableKey: j['stripePublishableKey'] as String?,
    appleMerchantId: j['appleMerchantId'] as String?,
    merchantName: j['merchantDisplayName'] as String? ?? "Al's Pizza",
  );
}
