import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/catalog.dart';
import '../state/ordering.dart';
import '../widgets/menu_cards.dart';

/// Full menu with sticky category chips that track the scroll position.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.category});

  final String? category;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _scroll = ScrollController();
  final _chips = ScrollController();
  final _viewport = GlobalKey();
  final _sectionKeys = <String, GlobalKey>{};
  final _chipKeys = <String, GlobalKey>{};
  String? _active;
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(widget.category, animate: false));
  }

  @override
  void didUpdateWidget(MenuScreen old) {
    super.didUpdateWidget(old);
    if (widget.category != old.category) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(widget.category));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _chips.dispose();
    super.dispose();
  }

  GlobalKey _key(Map<String, GlobalKey> map, String slug) => map.putIfAbsent(slug, GlobalKey.new);

  Future<void> _jumpTo(String? slug, {bool animate = true}) async {
    final ctx = slug == null ? null : _sectionKeys[slug]?.currentContext;
    if (ctx == null) return;
    setState(() => _active = slug);
    _centerChip(slug!);
    _jumping = true;
    await Scrollable.ensureVisible(ctx, duration: animate ? const Duration(milliseconds: 520) : Duration.zero, curve: Curves.easeInOutCubic);
    _jumping = false;
  }

  void _centerChip(String slug) {
    final ctx = _chipKeys[slug]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 300));
  }

  void _onScroll() {
    if (_jumping) return;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    final top = viewport.localToGlobal(Offset.zero).dy + 24;
    String? current;
    for (final entry in _sectionKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      if (box.localToGlobal(Offset.zero).dy <= top) current = entry.key;
    }
    current ??= _sectionKeys.keys.firstOrNull;
    if (current != _active) {
      setState(() => _active = current);
      if (current != null) _centerChip(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<CatalogStore>().menu;
    final store = context.watch<OrderingStore>().store;
    final categories = menu?.categories ?? const <MenuCategory>[];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Row(
                children: [
                  Expanded(child: Text('Menu', style: AlsText.display(30))),
                  if (store != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: alsShadow),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storefront_rounded, size: 16, color: AlsColors.orangeDeep),
                          const SizedBox(width: 6),
                          Text(store.shortName, style: AlsText.body(13, weight: FontWeight.w800)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 50,
              child: ListView.separated(
                controller: _chips,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final c = categories[i];
                  final selected = (_active ?? categories.first.slug) == c.slug;
                  return TapScale(
                    key: _key(_chipKeys, c.slug),
                    onTap: () => _jumpTo(c.slug),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AlsColors.brown : Colors.white,
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(color: selected ? AlsColors.brown : AlsColors.line),
                      ),
                      child: Text(
                        c.name,
                        style: AlsText.body(14, color: selected ? AlsColors.cream : AlsColors.brownSoft, weight: FontWeight.w800),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              key: _viewport,
              child: menu == null
                  ? ListView(
                      padding: const EdgeInsets.all(20),
                      children: [for (var i = 0; i < 5; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: Skeleton(height: 120, radius: 24))],
                    )
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final c in categories) ...[
                            Padding(
                              key: _key(_sectionKeys, c.slug),
                              padding: const EdgeInsets.only(top: 14, bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.name, style: AlsText.display(24)),
                                        Text(c.tagline, style: AlsText.body(13, color: AlsColors.muted)),
                                      ],
                                    ),
                                  ),
                                  if (c.prepMinutes > 2)
                                    Row(
                                      children: [
                                        const Icon(Icons.timer_outlined, size: 15, color: AlsColors.muted),
                                        const SizedBox(width: 4),
                                        Text(
                                          '~${c.prepMinutes} min',
                                          style: AlsText.body(12, color: AlsColors.muted, weight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            for (final (i, item) in c.items.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Reveal(
                                  delay: Reveal.stagger(i, ms: 40, max: 6),
                                  child: MenuItemTile(item: item),
                                ),
                              ),
                          ],
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
