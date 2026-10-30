import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/art/food_art.dart';
import '../../core/art/pizza_art.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/cart.dart';
import '../state/catalog.dart';
import '../state/ordering.dart';
import '../widgets/menu_cards.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reprice());
  }

  void _reprice() {
    final store = context.read<OrderingStore>().store;
    if (store != null) context.read<CartStore>().reprice(storeId: store.id);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final store = context.watch<OrderingStore>().store;
    final menu = context.watch<CatalogStore>().menu;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30), onPressed: () => context.pop()),
        title: Column(
          children: [
            const Text('Your order'),
            if (store != null) Text(store.shortName, style: AlsText.body(12, color: AlsColors.muted)),
          ],
        ),
      ),
      body: cart.isEmpty
          ? _EmptyCart(onBrowse: () => context.go('/menu'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
              children: [
                for (final (i, line) in cart.lines.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Reveal(
                      delay: Reveal.stagger(i, ms: 45),
                      child: Dismissible(
                        key: ValueKey(line.key),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(color: AlsColors.red, borderRadius: BorderRadius.circular(24)),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
                        ),
                        onDismissed: (_) {
                          final removed = cart.remove(line.key);
                          _reprice();
                          if (removed == null) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('Removed ${removed.name}'),
                                action: SnackBarAction(
                                  label: 'UNDO',
                                  textColor: AlsColors.orangeLight,
                                  onPressed: () {
                                    cart.restore(removed, i);
                                    _reprice();
                                  },
                                ),
                              ),
                            );
                        },
                        child: _LineCard(
                          line: line,
                          onQuantity: (q) {
                            cart.setQuantity(line.key, q);
                            _reprice();
                          },
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                _PromoField(onApplied: _reprice),
                if (menu != null) ...[
                  const SizedBox(height: 18),
                  Text('Add something extra', style: AlsText.display(18)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: [...menu.upsellFor('sides'), ...menu.upsellFor('desserts')].length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final item = [...menu.upsellFor('sides'), ...menu.upsellFor('desserts')][i];
                        return CardBox(
                          padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                          radius: 20,
                          onTap: () {
                            quickAdd(context, item);
                            _reprice();
                          },
                          child: Row(
                            children: [
                              SizedBox.square(dimension: 56, child: FoodArt.item(item)),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: AlsText.body(13, weight: FontWeight.w900)),
                                  Text(
                                    '+ ${money(item.priceCents)}',
                                    style: AlsText.body(12, color: AlsColors.orangeDeep, weight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _Totals(quote: cart.priced, estimate: cart.estimateCents, pricing: cart.pricing),
                if (cart.priceError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(cart.priceError!, style: AlsText.body(14, color: AlsColors.red)),
                  ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: AlsButton(
                  label: 'Checkout',
                  icon: Icons.lock_rounded,
                  onPressed: store == null ? null : () => context.push('/checkout'),
                  trailing: AnimatedMoney(
                    cart.priced?.subtotalCents ?? cart.estimateCents,
                    style: AlsText.display(18, color: AlsColors.brown, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.onQuantity});

  final CartLine line;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) => CardBox(
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 74,
          height: 74,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(18)),
          child: line.pizza != null
              ? PizzaArt(
                  toppings: line.pizza!.toppings,
                  crust: line.pizza!.crust,
                  sauce: line.pizza!.sauce,
                  cheese: line.pizza!.cheese,
                  seed: line.itemId.hashCode,
                )
              : FoodArt(art: line.art),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.name, style: AlsText.display(17)),
              const SizedBox(height: 3),
              if (line.summary.isNotEmpty)
                Text(
                  line.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AlsText.body(12, color: AlsColors.muted),
                ),
              if (line.notes != null) Text('“${line.notes}”', style: AlsText.body(12, color: AlsColors.brownSoft)),
              const SizedBox(height: 8),
              Row(
                children: [
                  AnimatedMoney(
                    line.totalCents,
                    style: AlsText.display(16, color: AlsColors.orangeDeep, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  QuantityStepper(value: line.quantity, min: 0, compact: true, onChanged: onQuantity),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PromoField extends StatefulWidget {
  const _PromoField({required this.onApplied});

  final VoidCallback onApplied;

  @override
  State<_PromoField> createState() => _PromoFieldState();
}

class _PromoFieldState extends State<_PromoField> with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _code.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final cart = context.read<CartStore>();
    final store = context.read<OrderingStore>().store;
    if (store == null || _code.text.trim().isEmpty) return;
    cart.setPromo(_code.text);
    final q = await cart.reprice(storeId: store.id, immediate: true);
    if (q?.promoError != null) _shake.forward(from: 0);
    if (q?.promoLabel != null && q?.promoError == null) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final q = cart.priced;
    final applied = cart.promoCode != null && q?.promoError == null && q?.promoLabel != null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: applied
          ? Container(
              key: const ValueKey('applied'),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: AlsColors.basil.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AlsColors.basil.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded, color: AlsColors.basil),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${cart.promoCode} · ${q!.promoLabel}',
                      style: AlsText.body(14, color: AlsColors.basil, weight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AlsColors.basil),
                    onPressed: () {
                      cart.setPromo(null);
                      widget.onApplied();
                    },
                  ),
                ],
              ),
            )
          : AnimatedBuilder(
              key: const ValueKey('field'),
              animation: _shake,
              builder: (context, child) => Transform.translate(offset: Offset(math.sin(_shake.value * math.pi * 6) * 8 * (1 - _shake.value), 0), child: child),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: (_) => _apply(),
                          decoration: const InputDecoration(hintText: 'Promo code', prefixIcon: Icon(Icons.local_offer_outlined)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AlsButton(label: 'Apply', expand: false, height: 50, style: AlsButtonStyle.dark, onPressed: _apply),
                    ],
                  ),
                  if (cart.promoCode != null && q?.promoError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text(q!.promoError!, style: AlsText.body(13, color: AlsColors.red)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.quote, required this.estimate, required this.pricing});

  final PriceQuote? quote;
  final int estimate;
  final bool pricing;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    Widget row(String label, int cents, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AlsText.body(bold ? 17 : 15, weight: bold ? FontWeight.w900 : FontWeight.w700, color: color ?? AlsColors.ink),
          ),
          const Spacer(),
          AnimatedMoney(
            cents,
            style: bold ? AlsText.display(20) : AlsText.body(15, weight: FontWeight.w800, color: color ?? AlsColors.ink),
          ),
        ],
      ),
    );
    return CardBox(
      child: AnimatedOpacity(
        opacity: pricing ? 0.55 : 1,
        duration: const Duration(milliseconds: 200),
        child: Column(
          children: [
            row('Subtotal', q?.subtotalCents ?? estimate),
            if ((q?.discountCents ?? 0) > 0) row('Promo savings', -(q!.discountCents), color: AlsColors.basil),
            row('Estimated tax', q?.taxCents ?? 0),
            const Divider(height: 20),
            row('Estimated total', q?.totalCents ?? estimate, bold: true),
            const SizedBox(height: 4),
            Text('Delivery fee and tip (if any) are added at checkout.', style: AlsText.body(12, color: AlsColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Floaty(
            child: Opacity(
              opacity: 0.85,
              child: SizedBox.square(
                dimension: 170,
                child: const PizzaArt(toppings: [], cheese: 'none', sauce: 'none', seed: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Your bag is empty', style: AlsText.display(26)),
          const SizedBox(height: 6),
          Text(
            'That pizza isn’t going to order itself.',
            textAlign: TextAlign.center,
            style: AlsText.body(15, color: AlsColors.muted),
          ),
          const SizedBox(height: 22),
          AlsButton(label: 'Browse the menu', expand: false, onPressed: onBrowse),
        ],
      ),
    ),
  );
}
