import 'package:flutter_test/flutter_test.dart';

import 'package:als/core/models.dart';
import 'package:als/customer/logic.dart';

// Mirrors backend/src/menu/pricing.ts so the builder shows the price the server will charge.
void main() {
  const options = PizzaOptions(
    sizes: [PizzaSize('medium', 'Medium', 12, 8, 175), PizzaSize('large', 'Large', 14, 8, 225)],
    crusts: [
      Crust('hand-tossed', 'Hand-Tossed', '', ['medium', 'large'], {}),
      Crust('stuffed', 'Stuffed Crust', '', ['large'], {'large': 300}),
    ],
    sauces: [Option('marinara', 'Classic Marinara')],
    cheeses: [Option('regular', 'Regular'), Option('extra', 'Extra', extra: true)],
    toppings: [
      Option('pepperoni', 'Pepperoni', group: 'meat'),
      Option('mushroom', 'Mushrooms', group: 'veggie'),
      Option('onion', 'Red Onions', group: 'veggie'),
    ],
  );
  const supreme = PizzaConfig(
    sizePrices: {'medium': 1699, 'large': 1999},
    toppings: ['pepperoni', 'mushroom'],
    sauce: 'marinara',
    cheese: 'regular',
    crust: 'hand-tossed',
    defaultSize: 'large',
  );

  test('default build costs the size price', () {
    expect(pizzaUnitPrice(supreme, PizzaSelection.defaults(supreme), options), 1999);
  });

  test('stuffed crust, extra cheese and an extra topping add up', () {
    final sel = PizzaSelection.defaults(supreme).copyWith(crust: 'stuffed', cheese: 'extra', toppings: ['pepperoni', 'mushroom', 'onion']);
    // 19.99 + 3.00 stuffed + 2.25 extra cheese + 2.25 onion
    expect(pizzaUnitPrice(supreme, sel, options), 1999 + 300 + 225 + 225);
  });

  test('removing an included topping is free and shows in the summary', () {
    final sel = PizzaSelection.defaults(supreme).copyWith(size: 'medium', toppings: ['pepperoni']);
    expect(pizzaUnitPrice(supreme, sel, options), 1699);
    expect(pizzaSummary(supreme, sel, options), 'Medium 12" · Hand-Tossed · No Mushrooms');
  });
}
