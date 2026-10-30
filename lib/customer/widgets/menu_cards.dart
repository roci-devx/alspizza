import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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

String fromPrice(MenuItem item) => item.hasOptions ? 'from ${money(item.priceCents)}' : money(item.priceCents);

void openItem(BuildContext context, MenuItem item) {
  if (!item.isAvailable) {
    showToast(context, '${item.name} is sold out right now', icon: Icons.info_outline_rounded);
    return;
  }
  if (item.isQuickAdd) {
    quickAdd(context, item);
  } else {
    context.push('/item/${item.id}');
  }
}

void quickAdd(BuildContext context, MenuItem item) {
  final menu = context.read<CatalogStore>().menu;
  if (menu == null) return;
  HapticFeedback.mediumImpact();
  context.read<CartStore>().add(buildLine(item: item, options: menu.pizzaOptions));
  showToast(context, '${item.name} added to your order');
}

/// Row card used on the Menu tab.
class MenuItemTile extends StatelessWidget {
  const MenuItemTile({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) => CardBox(
    onTap: () => openItem(context, item),
    padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
    child: Opacity(
      opacity: item.isAvailable ? 1 : 0.5,
      child: Row(
        children: [
          Hero(
            tag: 'art-${item.id}',
            child: Container(
              width: 104,
              height: 104,
              padding: EdgeInsets.all(item.imageUrl == null ? 6 : 0),
              decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(20)),
              child: FoodArt.item(item),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.tags.isNotEmpty || !item.isAvailable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (!item.isAvailable) const Tag('SOLD OUT', color: AlsColors.muted),
                        for (final t in item.tags.take(2)) Tag.forKey(t),
                      ],
                    ),
                  ),
                Text(item.name, style: AlsText.display(18), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AlsText.body(13, color: AlsColors.muted, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                // Long calorie ranges ("4,300–5,900 cal") drop to their own line instead of being cut off.
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      fromPrice(item),
                      style: AlsText.display(16, color: AlsColors.orangeDeep, weight: FontWeight.w600),
                    ),
                    if (item.calories != null) Text(item.calories!, style: AlsText.body(12, color: AlsColors.muted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AddButton(onTap: () => openItem(context, item)),
        ],
      ),
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    scale: 0.85,
    child: Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: AlsColors.orange,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x33E8962A), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: const Icon(Icons.add_rounded, color: AlsColors.brown),
    ),
  );
}

/// Tall card for horizontal carousels (Home → Popular).
class PopularCard extends StatelessWidget {
  const PopularCard({super.key, required this.item, this.width = 168});

  final MenuItem item;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: CardBox(
      onTap: () => openItem(context, item),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Hero(
                tag: 'art-${item.id}',
                child: Container(
                  height: width - 24,
                  padding: EdgeInsets.all(item.imageUrl == null ? 8 : 0),
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(colors: [Color(0xFFFFF1D2), AlsColors.creamDeep]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(child: FoodArt.item(item, radius: 20)),
                ),
              ),
              if (item.tags.isNotEmpty) Positioned(left: 8, top: 8, child: Tag.forKey(item.tags.first)),
            ],
          ),
          const SizedBox(height: 10),
          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AlsText.display(16)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  fromPrice(item),
                  style: AlsText.body(13, color: AlsColors.orangeDeep, weight: FontWeight.w800),
                ),
              ),
              _AddButton(onTap: () => openItem(context, item)),
            ],
          ),
        ],
      ),
    ),
  );
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, required this.onTap});

  final MenuCategory category;
  final VoidCallback onTap;

  static const _art = {
    'deals': 'deal:dinnerbox',
    'pizza': 'pizza',
    'wings': 'wings:buffalo',
    'sides': 'breadsticks',
    'pasta': 'pasta:marinara',
    'desserts': 'cookie',
    'drinks': 'soda:cola',
    'dips': 'dip:ranch',
  };

  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: alsShadow),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(category.name, style: AlsText.display(17), maxLines: 2),
                const SizedBox(height: 2),
                Text('${category.items.length} items', style: AlsText.body(12, color: AlsColors.muted)),
              ],
            ),
          ),
          SizedBox.square(
            dimension: 58,
            child: FoodArt(
              art: _art[category.slug] ?? 'pizza',
              pizza: category.slug == 'pizza' && category.items.isNotEmpty ? category.items.first.config.pizza : null,
            ),
          ),
        ],
      ),
    ),
  );
}
