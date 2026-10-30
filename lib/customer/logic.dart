import 'dart:math' as math;

import '../core/models.dart';

final _rnd = math.Random();
String newLineKey() => '${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1 << 32)}';

String pizzaSummary(PizzaConfig cfg, PizzaSelection sel, PizzaOptions o) {
  final size = o.size(sel.size);
  final parts = <String>['${size.label} ${size.inches}"', o.crust(sel.crust)?.label ?? sel.crust];
  if (sel.sauce != cfg.sauce) {
    parts.add(sel.sauce == 'none' ? 'No sauce' : o.sauces.firstWhere((s) => s.id == sel.sauce, orElse: () => Option(sel.sauce, sel.sauce)).label);
  }
  if (sel.cheese != cfg.cheese) {
    final label = o.cheeses.firstWhere((c) => c.id == sel.cheese, orElse: () => Option(sel.cheese, sel.cheese)).label;
    parts.add(sel.cheese == 'none' ? 'No cheese' : '$label cheese');
  }
  if (cfg.byo) {
    parts.add(sel.toppings.isEmpty ? 'Cheese only' : sel.toppings.map(o.toppingLabel).join(', '));
  } else {
    final extras = sel.toppings.where((t) => !cfg.toppings.contains(t)).toList();
    final removed = cfg.toppings.where((t) => !sel.toppings.contains(t)).toList();
    if (extras.isNotEmpty) parts.add('Add ${extras.map(o.toppingLabel).join(', ')}');
    if (removed.isNotEmpty) parts.add('No ${removed.map(o.toppingLabel).join(', ')}');
  }
  return parts.join(' · ');
}

/// Builds a cart line with display price + summary (the server re-prices at checkout).
CartLine buildLine({
  required MenuItem item,
  required PizzaOptions options,
  int quantity = 1,
  PizzaSelection? pizza,
  String? variantId,
  Map<String, String> choices = const {},
  String? notes,
}) {
  final cfg = item.config;
  var unit = item.priceCents;
  final parts = <String>[];
  if (cfg.pizza != null) {
    final sel = pizza ?? PizzaSelection.defaults(cfg.pizza!);
    unit = pizzaUnitPrice(cfg.pizza!, sel, options);
    parts.add(pizzaSummary(cfg.pizza!, sel, options));
    pizza = sel;
  } else if (cfg.variants.isNotEmpty) {
    final v = cfg.variants.firstWhere((v) => v.id == variantId, orElse: () => cfg.variants.first);
    unit = v.priceCents;
    variantId = v.id;
    parts.add(v.label);
  }
  final chosen = <String, String>{};
  for (final g in cfg.choices) {
    final pick = g.options.where((o) => o.id == choices[g.id]).firstOrNull ?? (g.required ? g.options.first : null);
    if (pick == null) continue;
    chosen[g.id] = pick.id;
    parts.add(g.id.startsWith('pizza') ? '${g.label.replaceAll(RegExp(r' topping$', caseSensitive: false), '')}: ${pick.label}' : pick.label);
  }
  return CartLine(
    key: newLineKey(),
    itemId: item.id,
    name: item.name,
    art: item.art,
    kind: item.kind,
    quantity: quantity,
    unitPriceCents: unit,
    summary: parts.join(' · '),
    variantId: variantId,
    choices: chosen,
    pizza: pizza,
    notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
  );
}

/// Recreates cart lines from a past order ("Order it again").
List<CartLine> linesFromOrder(Order order, MenuData menu) => [
  for (final l in order.items)
    if (menu.item(l.menuItemId) case final item? when item.isAvailable)
      buildLine(
        item: item,
        options: menu.pizzaOptions,
        quantity: l.quantity,
        pizza: l.config['pizza'] == null ? null : PizzaSelection.fromJson(l.config['pizza'] as Map<String, dynamic>),
        variantId: l.config['variantId'] as String?,
        choices: ((l.config['choices'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
        notes: l.config['notes'] as String?,
      ),
];

const statusCopy = {
  'pending_payment': ('Waiting for payment', 'Finish paying to send it to the kitchen.'),
  'received': ('Order received', 'The kitchen has your ticket.'),
  'preparing': ('In the oven', 'Your pizza is baking right now.'),
  'ready': ('Ready for pickup', 'Come grab it while it’s hot!'),
  'out_for_delivery': ('On the way', 'Your driver is headed to you.'),
  'completed': ('Enjoy!', 'Thanks for ordering from Al’s.'),
  'cancelled': ('Cancelled', 'This order was cancelled.'),
};
