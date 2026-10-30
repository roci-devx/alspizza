import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/art/food_art.dart';
import '../../core/art/pizza_art.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../logic.dart';
import '../state/cart.dart';
import '../state/catalog.dart';
import 'upsell_sheet.dart';

const _sizeScale = {'personal': 0.62, 'medium': 0.8, 'large': 0.9, 'xl': 1.0};

/// Item builder: size → crust → sauce → cheese → toppings for pizzas; variants
/// and choices for everything else. The illustration updates live.
class ItemScreen extends StatefulWidget {
  const ItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> with TickerProviderStateMixin {
  MenuItem? _item;
  PizzaOptions? _opts;
  PizzaSelection? _pizza;
  String? _variantId;
  final _choices = <String, String>{};
  final _notes = TextEditingController();
  final _toppingAnim = <String, AnimationController>{};
  int _qty = 1;
  String _toppingTab = 'meat';
  bool _added = false;

  @override
  void initState() {
    super.initState();
    final catalog = context.read<CatalogStore>();
    if (catalog.menu == null) {
      catalog.load().then((_) {
        if (mounted) setState(_resolve);
      });
    }
    _resolve();
  }

  void _resolve() {
    final menu = context.read<CatalogStore>().menu;
    final item = menu?.item(widget.itemId);
    if (item == null || _item != null) return;
    _item = item;
    _opts = menu!.pizzaOptions;
    if (item.config.pizza != null) _pizza = PizzaSelection.defaults(item.config.pizza!);
    if (item.config.variants.isNotEmpty) _variantId = item.config.variants.first.id;
    for (final g in item.config.choices) {
      if (g.required && g.options.isNotEmpty) _choices[g.id] = g.options.first.id;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final c in _toppingAnim.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _unitPrice {
    final item = _item!;
    if (_pizza != null) return pizzaUnitPrice(item.config.pizza!, _pizza!, _opts!);
    if (item.config.variants.isNotEmpty) return item.config.variants.firstWhere((v) => v.id == _variantId, orElse: () => item.config.variants.first).priceCents;
    return item.priceCents;
  }

  void _setSize(String size) {
    final crust = _opts!.crust(_pizza!.crust);
    var crustId = _pizza!.crust;
    if (crust == null || !crust.sizes.contains(size)) {
      final options = _opts!.crusts.where((c) => c.sizes.contains(size)).toList();
      crustId = (options.where((c) => c.id == 'hand-tossed').firstOrNull ?? options.first).id;
    }
    setState(() => _pizza = _pizza!.copyWith(size: size, crust: crustId));
  }

  void _toggleTopping(String id) {
    final selected = _pizza!.toppings.contains(id);
    if (!selected && _pizza!.toppings.length >= 10) {
      showToast(context, 'Up to 10 toppings per pizza', icon: Icons.info_outline_rounded);
      return;
    }
    HapticFeedback.selectionClick();
    final ctrl = _toppingAnim.putIfAbsent(id, () => AnimationController(vsync: this, duration: const Duration(milliseconds: 650), value: selected ? 1 : 0));
    setState(() => _pizza = _pizza!.copyWith(toppings: selected ? (_pizza!.toppings.where((t) => t != id).toList()) : [..._pizza!.toppings, id]));
    if (selected) {
      ctrl.reverse().whenComplete(() {
        if (mounted && !_pizza!.toppings.contains(id)) setState(() {});
      });
    } else {
      ctrl.forward(from: 0);
    }
  }

  Future<void> _add() async {
    final item = _item!;
    final line = buildLine(item: item, options: _opts!, quantity: _qty, pizza: _pizza, variantId: _variantId, choices: _choices, notes: _notes.text);
    context.read<CartStore>().add(line);
    HapticFeedback.mediumImpact();
    setState(() => _added = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    final isMain = const ['pizza', 'deal', 'wings', 'pasta'].contains(item.kind);
    if (!isMain) {
      showToast(context, '${item.name} added to your order');
      context.pop();
      return;
    }
    final next = await showUpsell(context);
    if (!mounted) return;
    if (next == UpsellResult.viewCart) {
      context.pushReplacement('/cart');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null) {
      final catalog = context.watch<CatalogStore>();
      return Scaffold(
        body: Center(
          child: catalog.loading
              ? const CircularProgressIndicator(color: AlsColors.orange)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(catalog.error ?? 'That item is no longer on the menu.', style: AlsText.body(16)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => context.go('/menu'), child: const Text('Back to the menu')),
                  ],
                ),
        ),
      );
    }
    final pizza = _pizza;
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _hero(item)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.tags.isNotEmpty) Wrap(spacing: 6, children: [for (final t in item.tags) Tag.forKey(t)]),
                      const SizedBox(height: 8),
                      Text(item.name, style: AlsText.display(30)),
                      const SizedBox(height: 6),
                      Text(
                        item.description,
                        style: AlsText.body(15, color: AlsColors.brownSoft, weight: FontWeight.w600),
                      ),
                      if (item.calories != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(item.calories!, style: AlsText.body(13, color: AlsColors.muted)),
                        ),
                    ],
                  ),
                ),
              ),
              if (pizza != null) ..._pizzaSections(item.config.pizza!, pizza) else ..._itemSections(item),
              const SliverToBoxAdapter(child: SizedBox(height: 150)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TapScale(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: alsShadow),
                    child: const Icon(Icons.close_rounded, color: AlsColors.brown),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _addBar()),
        ],
      ),
    );
  }

  Widget _hero(MenuItem item) {
    final pizza = _pizza;
    final live = pizza == null
        ? null
        : AnimatedBuilder(
            animation: Listenable.merge(_toppingAnim.values.toList()),
            builder: (context, _) {
              final visible = [
                ...pizza.toppings,
                for (final e in _toppingAnim.entries)
                  if (!pizza.toppings.contains(e.key) && e.value.value > 0) e.key,
              ];
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                child: PizzaArt(
                  key: ValueKey('${pizza.crust}-${pizza.sauce}-${pizza.cheese}'),
                  toppings: visible,
                  crust: pizza.crust,
                  sauce: pizza.sauce,
                  cheese: pizza.cheese,
                  density: item.config.pizza!.density,
                  seed: item.id.hashCode,
                  toppingProgress: {for (final e in _toppingAnim.entries) e.key: e.value.value},
                ),
              );
            },
          );
    final scale = pizza == null ? 1.0 : _sizeScale[pizza.size] ?? 0.9;
    final hasPhoto = item.imageUrl?.isNotEmpty ?? false;
    final Widget content = hasPhoto
        // Real photo up top; the live illustration rides along so customizations stay visible.
        ? SizedBox(
            width: 300,
            height: 270,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Hero(
                    tag: 'art-${item.id}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: const [BoxShadow(color: Color(0x335A210F), blurRadius: 24, offset: Offset(0, 12))],
                      ),
                      child: FoodArt.item(item, radius: 32),
                    ),
                  ),
                ),
                if (live != null)
                  Positioned(
                    right: -16,
                    bottom: -22,
                    child: _LivePreview(scale: scale, child: live),
                  ),
              ],
            ),
          )
        : AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            child: SizedBox.square(
              dimension: 290,
              child: Hero(
                tag: 'art-${item.id}',
                child: live == null ? Floaty(child: FoodArt.item(item)) : Spin(period: const Duration(seconds: 60), child: live),
              ),
            ),
          );
    return Container(
      height: 340,
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, 0.1), radius: 0.9, colors: [Color(0xFFFFF0CF), AlsColors.cream]),
      ),
      child: SafeArea(bottom: false, child: Center(child: content)),
    );
  }

  Widget _section(String title, {String? subtitle, required Widget child}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: AlsText.display(20)),
            if (subtitle != null) ...[const SizedBox(width: 8), Text(subtitle, style: AlsText.body(13, color: AlsColors.muted))],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  List<Widget> _pizzaSections(PizzaConfig cfg, PizzaSelection sel) {
    final o = _opts!;
    final size = o.size(sel.size);
    final crust = o.crust(sel.crust);
    return [
      SliverToBoxAdapter(
        child: _section(
          'Size',
          child: Row(
            children: [
              for (final s in o.sizes.where((x) => cfg.sizePrices.containsKey(x.id))) ...[
                Expanded(
                  child: TapScale(
                    onTap: () => _setSize(s.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: sel.size == s.id ? AlsColors.brown : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: sel.size == s.id ? AlsColors.brown : AlsColors.line, width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.circle_outlined, size: 12.0 + s.inches, color: sel.size == s.id ? AlsColors.orangeLight : AlsColors.muted),
                          const SizedBox(height: 4),
                          Text(
                            s.label,
                            style: AlsText.body(13, color: sel.size == s.id ? AlsColors.cream : AlsColors.ink, weight: FontWeight.w900),
                          ),
                          Text(
                            '${s.inches}" · ${s.slices} sl',
                            style: AlsText.body(11, color: sel.size == s.id ? AlsColors.orangeLight : AlsColors.muted, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (s != o.sizes.where((x) => cfg.sizePrices.containsKey(x.id)).last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _section(
          'Crust',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in o.crusts)
                    ChoicePill(
                      label: c.label,
                      sublabel: !c.sizes.contains(size.id)
                          ? '${c.sizes.map((s) => o.size(s).label).join('/')} only'
                          : (c.upcharges[size.id] ?? 0) > 0
                          ? '+${money(c.upcharges[size.id]!)}'
                          : null,
                      selected: sel.crust == c.id,
                      enabled: c.sizes.contains(size.id),
                      onTap: () => setState(() => _pizza = sel.copyWith(crust: c.id)),
                    ),
                ],
              ),
              if (crust != null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Padding(
                    key: ValueKey(crust.id),
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(crust.description, style: AlsText.body(13, color: AlsColors.muted)),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _section(
          'Sauce',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in o.sauces)
                ChoicePill(
                  label: s.label,
                  selected: sel.sauce == s.id,
                  onTap: () => setState(() => _pizza = sel.copyWith(sauce: s.id)),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _section(
          'Cheese',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in o.cheeses)
                ChoicePill(
                  label: c.label,
                  sublabel: c.extra && cfg.cheese != 'extra' ? '+${money(size.toppingCents)}' : null,
                  selected: sel.cheese == c.id,
                  onTap: () => setState(() => _pizza = sel.copyWith(cheese: c.id)),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _section(
          'Toppings',
          subtitle: '${money(size.toppingCents)} each · up to 10',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final (id, label) in const [('meat', 'Meats'), ('veggie', 'Veggies')]) ...[
                    ChoicePill(label: label, selected: _toppingTab == id, onTap: () => setState(() => _toppingTab = id)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: GridView.count(
                  key: ValueKey(_toppingTab),
                  crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 5 : 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                  children: [
                    for (final t in o.toppings.where((t) => t.group == _toppingTab))
                      _ToppingTile(
                        id: t.id,
                        label: t.label,
                        selected: sel.toppings.contains(t.id),
                        price: cfg.toppings.contains(t.id) ? 'Included' : '+${money(size.toppingCents)}',
                        onTap: () => _toggleTopping(t.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _section(
          'Special instructions',
          subtitle: 'optional',
          child: TextField(
            controller: _notes,
            maxLength: 140,
            decoration: const InputDecoration(hintText: 'e.g. well done, extra crispy, cut in squares', counterText: ''),
          ),
        ),
      ),
    ];
  }

  List<Widget> _itemSections(MenuItem item) {
    final cfg = item.config;
    return [
      if (cfg.includes.isNotEmpty)
        SliverToBoxAdapter(
          child: _section(
            'What’s inside',
            child: Column(
              children: [
                for (final inc in cfg.includes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AlsColors.basil, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(inc, style: AlsText.body(15, weight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (cfg.variants.length > 1)
        SliverToBoxAdapter(
          child: _section(
            item.kind == 'wings' ? 'How many?' : 'Size',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final v in cfg.variants)
                  ChoicePill(label: v.label, sublabel: money(v.priceCents), selected: _variantId == v.id, onTap: () => setState(() => _variantId = v.id)),
              ],
            ),
          ),
        ),
      for (final g in cfg.choices)
        SliverToBoxAdapter(
          child: _section(
            g.label,
            subtitle: g.required ? null : 'optional',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final opt in g.options)
                  ChoicePill(label: opt.label, selected: _choices[g.id] == opt.id, onTap: () => setState(() => _choices[g.id] = opt.id)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _addBar() => Container(
    padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(context).bottom),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [BoxShadow(color: Color(0x225A210F), blurRadius: 24, offset: Offset(0, -6))],
    ),
    child: Row(
      children: [
        QuantityStepper(value: _qty, onChanged: (v) => setState(() => _qty = v)),
        const SizedBox(width: 14),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: _added
                ? Container(
                    key: const ValueKey('added'),
                    height: 56,
                    decoration: BoxDecoration(color: AlsColors.basil, borderRadius: BorderRadius.circular(28)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Added!',
                          style: AlsText.display(18, color: Colors.white, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : AlsButton(
                    key: const ValueKey('add'),
                    label: 'Add to order',
                    onPressed: _add,
                    trailing: AnimatedMoney(
                      _unitPrice * _qty,
                      style: AlsText.display(18, color: AlsColors.brown, weight: FontWeight.w600),
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}

class _ToppingTile extends StatelessWidget {
  const _ToppingTile({required this.id, required this.label, required this.selected, required this.price, required this.onTap});

  final String id;
  final String label;
  final bool selected;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    scale: 0.92,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF1D9) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? AlsColors.orange : AlsColors.line, width: selected ? 2 : 1.5),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: ToppingIcon(id, size: 40),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: AlsText.body(12, weight: FontWeight.w800, height: 1.15),
              ),
              Text(
                price,
                style: AlsText.body(11, color: AlsColors.muted, weight: FontWeight.w700),
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: AlsColors.orange, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 15, color: AlsColors.brown),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Circular "your pizza" badge that shows the live build on top of a stock photo.
class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AlsColors.brown, borderRadius: BorderRadius.circular(10)),
        child: Text('YOUR PIZZA', style: AlsText.label(10, color: AlsColors.cream)),
      ),
      const SizedBox(height: 4),
      Container(
        width: 128,
        height: 128,
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: AlsColors.cream,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x445A210F), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: AnimatedScale(
          scale: 0.7 + 0.3 * scale,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutBack,
          child: Spin(period: const Duration(seconds: 50), child: child),
        ),
      ),
    ],
  );
}
