import 'dart:async';

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
import '../state/ordering.dart';
import '../state/session.dart';
import '../widgets/menu_cards.dart';
import '../widgets/places.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogStore>();
    final menu = catalog.menu;
    final orders = context.watch<OrdersStore>();
    return Scaffold(
      body: RefreshIndicator(
        color: AlsColors.orange,
        onRefresh: () async {
          await Future.wait([catalog.load(force: true), orders.refresh()]);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SafeArea(bottom: false, child: _Header())),
            const SliverToBoxAdapter(child: _ContextCard()),
            if (orders.active != null) SliverToBoxAdapter(child: _ActiveOrderBanner(order: orders.active!)),
            if (menu == null)
              SliverToBoxAdapter(
                child: _LoadingHome(error: catalog.error, onRetry: () => catalog.load(force: true)),
              )
            else ...[
              SliverToBoxAdapter(
                child: _HeroCarousel(menu: menu, deals: catalog.deals),
              ),
              const SliverToBoxAdapter(child: SectionHeader('Popular right now', subtitle: 'What the neighborhood is ordering')),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 252,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: menu.popular.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => Reveal(
                      delay: Reveal.stagger(i),
                      offset: const Offset(0.2, 0),
                      child: PopularCard(item: menu.popular[i]),
                    ),
                  ),
                ),
              ),
              if (orders.lastCompleted != null)
                SliverToBoxAdapter(
                  child: _ReorderCard(order: orders.lastCompleted!, menu: menu),
                ),
              const SliverToBoxAdapter(child: SectionHeader('What are you craving?')),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 84,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final c = menu.categories[i];
                    return Reveal(
                      delay: Reveal.stagger(i, ms: 45),
                      child: CategoryTile(category: c, onTap: () => context.go('/menu?category=${c.slug}')),
                    );
                  }, childCount: menu.categories.length),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 170)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionStore>().user;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final name = (user?.isGuest ?? true) ? '' : ', ${user!.firstName}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Row(
        children: [
          const AlsLogo(height: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting$name',
                  style: AlsText.body(14, color: AlsColors.muted, weight: FontWeight.w700),
                ),
                Text('What are we eating?', style: AlsText.display(22)),
              ],
            ),
          ),
          TapScale(
            onTap: () => context.go('/account'),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AlsColors.brown,
              child: (user?.isGuest ?? true)
                  ? const Icon(Icons.person_rounded, color: AlsColors.cream)
                  : Text(user!.firstName.isEmpty ? '?' : user.firstName[0].toUpperCase(), style: AlsText.display(18, color: AlsColors.cream)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pickup ⇄ Delivery toggle with the current store / address underneath.
class _ContextCard extends StatelessWidget {
  const _ContextCard();

  @override
  Widget build(BuildContext context) {
    final ordering = context.watch<OrderingStore>();
    final store = ordering.store;
    final delivery = ordering.isDelivery;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: CardBox(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            FulfillmentToggle(value: ordering.fulfillment, onChanged: ordering.setFulfillment),
            TapScale(
              scale: 0.98,
              onTap: () async {
                if (delivery) {
                  final a = await pickAddress(context);
                  if (a != null) await ordering.setAddress(a);
                } else {
                  final s = await pickStore(context);
                  if (s != null) await ordering.setStore(s);
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 6, 6),
                child: Row(
                  children: [
                    Icon(delivery ? Icons.place_rounded : Icons.storefront_rounded, color: AlsColors.orangeDeep),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          key: ValueKey('$delivery${store?.id}${ordering.address?.line1}'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              delivery
                                  ? (ordering.address == null ? 'Add a delivery address' : 'Deliver to ${ordering.address!.line1}')
                                  : (store == null ? 'Choose a store' : 'Pickup at ${store.shortName}'),
                              style: AlsText.body(15, weight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              delivery
                                  ? 'From ${store?.shortName ?? 'your nearest Al’s'} · usually 30–45 min'
                                  : store == null
                                  ? 'Tap to find your nearest Al’s'
                                  : '${store.distanceMiles != null ? '${store.distanceMiles!.toStringAsFixed(1)} mi · ' : ''}Ready in ~${store.pickupEtaMinutes ?? 20} min',
                              style: AlsText.body(13, color: AlsColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, color: AlsColors.muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FulfillmentToggle extends StatelessWidget {
  const FulfillmentToggle({super.key, required this.value, required this.onChanged, this.height = 48});

  final Fulfillment? value;
  final ValueChanged<Fulfillment> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(height / 2)),
    child: Stack(
      children: [
        if (value != null)
          AnimatedAlign(
            alignment: value == Fulfillment.delivery ? Alignment.centerRight : Alignment.centerLeft,
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutBack,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: AlsColors.brown,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: const [BoxShadow(color: Color(0x335A210F), blurRadius: 10, offset: Offset(0, 4))],
                ),
              ),
            ),
          ),
        Row(
          children: [
            for (final (f, icon, label) in const [
              (Fulfillment.pickup, Icons.shopping_bag_rounded, 'Pickup'),
              (Fulfillment.delivery, Icons.delivery_dining_rounded, 'Delivery'),
            ])
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(f),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 19, color: value == f ? AlsColors.cream : AlsColors.brownSoft),
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: AlsText.body(15, color: value == f ? AlsColors.cream : AlsColors.brownSoft, weight: FontWeight.w900),
                        child: Text(label),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _ActiveOrderBanner extends StatelessWidget {
  const _ActiveOrderBanner({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final (title, _) = statusCopy[order.status] ?? ('In progress', '');
    final steps = order.isDelivery ? ['received', 'preparing', 'out_for_delivery', 'completed'] : ['received', 'preparing', 'ready', 'completed'];
    final progress = (steps.indexOf(order.status) + 1) / steps.length;
    final eta = order.isDelivery ? (order.delivery?.dropoffEta ?? order.estimatedDeliveryAt) : order.estimatedReadyAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Reveal(
        child: TapScale(
          scale: 0.98,
          onTap: () => context.push('/order/${order.id}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF8A3B1F), AlsColors.brown]),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x445A210F), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _LiveDot(),
                    const SizedBox(width: 8),
                    Text('ORDER #${order.number}', style: AlsText.label(12, color: AlsColors.orangeLight)),
                    const Spacer(),
                    if (eta != null)
                      Text(
                        'ETA ${clock(eta)}',
                        style: AlsText.body(13, color: AlsColors.cream, weight: FontWeight.w800),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(title, style: AlsText.display(22, color: AlsColors.cream)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: Colors.white24, color: AlsColors.orange),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Tap to track your order', style: AlsText.body(12, color: AlsColors.cream.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 14,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 6 + 8 * _c.value,
            height: 6 + 8 * _c.value,
            decoration: BoxDecoration(
              color: AlsColors.orange.withValues(alpha: 1 - _c.value),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AlsColors.orange, shape: BoxShape.circle),
          ),
        ],
      ),
    ),
  );
}

class _Slide {
  const _Slide({required this.title, required this.subtitle, required this.cta, required this.colors, required this.art, required this.onTap});

  final String title;
  final String subtitle;
  final String cta;
  final List<Color> colors;
  final Widget art;
  final void Function(BuildContext) onTap;
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.menu, required this.deals});

  final MenuData menu;
  final List<Deal> deals;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _page = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_page.hasClients) return;
      final next = (_index + 1) % _slides.length;
      _page.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  List<_Slide> get _slides {
    final combos = widget.menu.categories.where((c) => c.slug == 'deals').expand((c) => c.items).where((i) => i.isAvailable).toList();
    final stuffed = widget.menu.allItems.where((i) => i.slug == 'pepperoni-overload').firstOrNull;
    final palettes = [
      [const Color(0xFFE8962A), const Color(0xFFC9461C)],
      [const Color(0xFF8A3B1F), AlsColors.brown],
      [const Color(0xFF4E8A34), const Color(0xFF2C5E24)],
    ];
    final slides = <_Slide>[
      if (combos.isNotEmpty)
        _Slide(
          title: combos.first.name,
          subtitle: '${combos.first.description.split('.').first} · ${money(combos.first.priceCents)}',
          cta: 'Order now',
          colors: palettes[0],
          art: FoodArt.item(combos.first),
          onTap: (c) => c.push('/item/${combos.first.id}'),
        ),
      for (final d in widget.deals.take(2))
        _Slide(
          title: d.label,
          subtitle: '${d.description} · code ${d.code}',
          cta: 'Use code',
          colors: palettes[1],
          art: const PizzaArt(toppings: ['pepperoni', 'basil'], cheese: 'extra', seed: 21),
          onTap: (c) {
            c.read<CartStore>().setPromo(d.code);
            showToast(c, '${d.code} will be applied at checkout');
          },
        ),
      if (stuffed != null)
        _Slide(
          title: 'Stuffed Crust is here',
          subtitle: 'Mozzarella baked right into the edge. Large only.',
          cta: 'Build yours',
          colors: palettes[2],
          art: const PizzaArt(toppings: ['pepperoni'], crust: 'stuffed', density: 1.5, seed: 8),
          onTap: (c) => c.push('/item/${stuffed.id}'),
        ),
      for (final combo in combos.skip(1).take(2))
        _Slide(
          title: combo.name,
          subtitle: '${combo.description.split('.').first} · ${money(combo.priceCents)}',
          cta: 'Order now',
          colors: palettes[0],
          art: FoodArt.item(combo),
          onTap: (c) => c.push('/item/${combo.id}'),
        ),
    ];
    return slides;
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    if (slides.isEmpty) return const SizedBox(height: 12);
    return Column(
      children: [
        const SizedBox(height: 14),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _page,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _page,
              builder: (context, child) {
                final page = _page.hasClients && _page.position.haveDimensions ? (_page.page ?? 0) : 0.0;
                final delta = (page - i).abs().clamp(0.0, 1.0);
                return Transform.scale(scale: 1 - delta * 0.06, child: child);
              },
              child: _SlideCard(slide: slides[i]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(color: i == _index ? AlsColors.orange : AlsColors.line, borderRadius: BorderRadius.circular(4)),
              ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: TapScale(
      scale: 0.98,
      onTap: () => slide.onTap(context),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: slide.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x335A210F), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -10,
              bottom: -10,
              child: AspectRatio(aspectRatio: 1, child: Floaty(amplitude: 5, rotate: 0.08, child: slide.art)),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 220,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slide.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AlsText.display(24, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      slide.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AlsText.body(13, color: Colors.white.withValues(alpha: 0.88)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(color: AlsColors.cream, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        slide.cta,
                        style: AlsText.body(14, color: AlsColors.brown, weight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReorderCard extends StatelessWidget {
  const _ReorderCard({required this.order, required this.menu});

  final Order order;
  final MenuData menu;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SectionHeader('Order it again', subtitle: 'One tap, same as last time'),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: CardBox(
          child: Row(
            children: [
              SizedBox(
                width: 86,
                height: 64,
                child: Stack(
                  children: [
                    for (final (i, l) in order.items.take(3).indexed)
                      Positioned(
                        left: i * 18.0,
                        top: 0,
                        width: 56,
                        height: 56,
                        child: FoodArt.line(l.art, l.config, seed: i),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.items.map((l) => l.name).join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AlsText.body(14, weight: FontWeight.w800),
                    ),
                    Text('${dayLabel(order.createdAt)} · ${money(order.totalCents)}', style: AlsText.body(12, color: AlsColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AlsButton(
                label: 'Reorder',
                height: 42,
                expand: false,
                style: AlsButtonStyle.dark,
                onPressed: () {
                  final cart = context.read<CartStore>();
                  for (final l in linesFromOrder(order, menu)) {
                    cart.add(l);
                  }
                  showToast(context, 'Added your last order to the bag');
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _LoadingHome extends StatelessWidget {
  const _LoadingHome({this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: error != null
        ? CardBox(
            child: Column(
              children: [
                const Icon(Icons.wifi_off_rounded, size: 40, color: AlsColors.muted),
                const SizedBox(height: 10),
                Text(error!, textAlign: TextAlign.center, style: AlsText.body(15)),
                const SizedBox(height: 12),
                AlsButton(label: 'Try again', style: AlsButtonStyle.dark, onPressed: onRetry),
              ],
            ),
          )
        : const Column(
            children: [
              Skeleton(height: 190, radius: 28),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Skeleton(height: 220, radius: 24)),
                  SizedBox(width: 14),
                  Expanded(child: Skeleton(height: 220, radius: 24)),
                ],
              ),
            ],
          ),
  );
}
