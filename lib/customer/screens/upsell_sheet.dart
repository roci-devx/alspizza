import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/art/food_art.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../logic.dart';
import '../state/cart.dart';
import '../state/catalog.dart';

enum UpsellResult { keepBrowsing, viewCart }

/// "Complete your meal?" — shown after adding a pizza/combo.
Future<UpsellResult?> showUpsell(BuildContext context) => showModalBottomSheet<UpsellResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AlsColors.cream,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
  builder: (_) => const UpsellSheet(),
);

class UpsellSheet extends StatefulWidget {
  const UpsellSheet({super.key});

  @override
  State<UpsellSheet> createState() => _UpsellSheetState();
}

class _UpsellSheetState extends State<UpsellSheet> {
  final _added = <String>{};

  void _add(MenuItem item, PizzaOptions options) {
    HapticFeedback.lightImpact();
    final variant = item.config.variants.where((v) => v.id == '2l').firstOrNull?.id;
    context.read<CartStore>().add(buildLine(item: item, options: options, variantId: variant));
    setState(() => _added.add(item.id));
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<CatalogStore>().menu!;
    final cart = context.watch<CartStore>();
    final groups = [('Sides', 'sides'), ('Desserts', 'desserts'), ('Drinks', 'drinks')];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: AlsColors.line, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Complete your meal?', style: AlsText.display(26)),
                      Text('Most people grab one of these with their pizza.', style: AlsText.body(14, color: AlsColors.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.celebration_rounded, color: AlsColors.orange, size: 34),
              ],
            ),
          ),
          for (final (gi, (title, key)) in groups.indexed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text(title, style: AlsText.display(18)),
            ),
            SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: menu.upsellFor(key).length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final item = menu.upsellFor(key)[i];
                  final added = _added.contains(item.id);
                  return Reveal(
                    delay: Reveal.stagger(gi * 3 + i, ms: 50),
                    offset: const Offset(0.3, 0),
                    child: _UpsellCard(item: item, added: added, onAdd: () => _add(item, menu.pizzaOptions)),
                  );
                },
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: AlsButton(label: 'Keep browsing', style: AlsButtonStyle.outline, onPressed: () => Navigator.pop(context, UpsellResult.keepBrowsing)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AlsButton(label: 'View order (${cart.count})', onPressed: () => Navigator.pop(context, UpsellResult.viewCart)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpsellCard extends StatelessWidget {
  const _UpsellCard({required this.item, required this.added, required this.onAdd});

  final MenuItem item;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final price = item.config.variants.where((v) => v.id == '2l').firstOrNull?.priceCents ?? item.priceCents;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 136,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: added ? AlsColors.basil : Colors.transparent, width: 2),
        boxShadow: alsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 78, child: Center(child: FoodArt.item(item))),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AlsText.body(13, weight: FontWeight.w900),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  money(price),
                  style: AlsText.body(13, color: AlsColors.orangeDeep, weight: FontWeight.w900),
                ),
              ),
              TapScale(
                onTap: added ? null : onAdd,
                scale: 0.85,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: added ? AlsColors.basil : AlsColors.orange, shape: BoxShape.circle),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (c, a) => RotationTransition(
                      turns: Tween(begin: 0.5, end: 1.0).animate(a),
                      child: ScaleTransition(scale: a, child: c),
                    ),
                    child: Icon(added ? Icons.check_rounded : Icons.add_rounded, key: ValueKey(added), size: 18, color: added ? Colors.white : AlsColors.brown),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
