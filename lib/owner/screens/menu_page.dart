import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/art/food_art.dart';
import '../../core/art/pizza_art.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';
import 'menu/item_editor.dart';
import 'menu/options_editor.dart';

enum _Tab { items, types, options }

/// Menu portal: items (photos, ingredients, options), menu types and the shared pizza options.
/// Prep time per menu type drives the pickup ETA customers see.
class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  List<MenuCategory> _categories = [];
  PizzaOptions? _options;
  bool _loading = true;
  _Tab _tab = _Tab.items;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<OwnerStore>().api.get('/owner/menu');
      if (!mounted) return;
      final options = PizzaOptions.fromJson(res['pizzaOptions'] as Json);
      registerToppingArt(options.toppings.map((t) => (id: t.id, art: t.art)));
      setState(() {
        _categories = ((res['categories'] as List?) ?? const []).map((e) => MenuCategory.fromJson(e as Json)).toList();
        _options = options;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _patch(String path, Json body, [String? done]) async {
    try {
      await context.read<OwnerStore>().api.patch(path, body);
      await _load();
      if (mounted && done != null) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openItem({MenuItem? item, String? categoryId}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ItemEditor(item: item, categories: _categories, options: _options!, categoryId: categoryId ?? _filter),
      ),
    );
    if (changed == true) {
      await _load();
      if (mounted) showToast(context, item == null ? 'Added to the menu' : 'Saved ${item.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return OwnerPageScaffold(
      title: 'Menu',
      subtitle: 'Items, photos, ingredients, options and menu types — changes show in the app right away',
      showFilters: false,
      actions: [
        if (!compact && _tab == _Tab.items && _options != null)
          AlsButton(label: 'New item', icon: Icons.add_rounded, expand: false, height: 46, onPressed: () => _openItem()),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AlsColors.orange)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (t, label, icon) in const [
                        (_Tab.items, 'Items', Icons.local_pizza_rounded),
                        (_Tab.types, 'Menu types', Icons.view_list_rounded),
                        (_Tab.options, 'Pizza options', Icons.tune_rounded),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoicePill(
                            label: label,
                            leading: Icon(icon, size: 18, color: _tab == t ? AlsColors.cream : AlsColors.brownSoft),
                            selected: _tab == t,
                            onTap: () => setState(() => _tab = t),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                switch (_tab) {
                  _Tab.items => _itemsTab(compact),
                  _Tab.types => _typesTab(),
                  _Tab.options => PizzaOptionsEditor(key: ValueKey(_options), options: _options!, onSaved: _load),
                },
              ],
            ),
    );
  }

  // ── Items ──────────────────────────────────────────────────────────────────
  Widget _itemsTab(bool compact) {
    final shown = _filter == null ? _categories : _categories.where((c) => c.id == _filter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[AlsButton(label: 'New item', icon: Icons.add_rounded, height: 48, onPressed: () => _openItem()), const SizedBox(height: 12)],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoicePill(label: 'All', selected: _filter == null, onTap: () => setState(() => _filter = null)),
              ),
              for (final c in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoicePill(label: '${c.name} · ${c.items.length}', selected: _filter == c.id, onTap: () => setState(() => _filter = c.id)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final c in shown) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                Expanded(child: Text(c.name, style: AlsText.display(20))),
                Text(
                  '${c.prepMinutes} min prep',
                  style: AlsText.body(12, color: AlsColors.muted, weight: FontWeight.w800),
                ),
                IconButton(
                  tooltip: 'Add to ${c.name}',
                  onPressed: () => _openItem(categoryId: c.id),
                  icon: const Icon(Icons.add_circle_rounded, color: AlsColors.orangeDeep),
                ),
              ],
            ),
          ),
          if (c.items.isEmpty)
            CardBox(
              child: Text('No items yet — tap + to add the first one.', style: AlsText.body(13, color: AlsColors.muted)),
            ),
          for (final item in c.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CardBox(
                onTap: () => _openItem(item: item),
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      padding: EdgeInsets.all(item.imageUrl == null ? 4 : 0),
                      decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(16)),
                      child: Opacity(opacity: item.isAvailable ? 1 : 0.4, child: FoodArt.item(item, radius: 16)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AlsText.body(15, weight: FontWeight.w900),
                                ),
                              ),
                              if (!item.isAvailable)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Badge2('SOLD OUT', color: AlsColors.red),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              item.hasOptions ? 'from ${money(item.priceCents)}' : money(item.priceCents),
                              if (item.isPizza) '${item.config.pizza!.toppings.length} toppings',
                              if (item.config.variants.length > 1) '${item.config.variants.length} sizes',
                              if (item.config.choices.isNotEmpty) '${item.config.choices.length} choices',
                              if (item.imageUrl == null) 'no photo',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AlsText.body(12, color: AlsColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: item.isAvailable ? 'Available — switch off when it runs out' : 'Sold out in the app',
                      child: Switch(
                        value: item.isAvailable,
                        onChanged: (v) => _patch('/owner/items/${item.id}', {'isAvailable': v}, v ? '${item.name} is back' : '${item.name} marked sold out'),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AlsColors.muted),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  // ── Menu types (categories) ────────────────────────────────────────────────
  Widget _typesTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Menu types are the sections customers browse (Pizzas, Wings, Desserts…). Prep time here sets the pickup ETA for everything in that section.',
        style: AlsText.body(13, color: AlsColors.muted),
      ),
      const SizedBox(height: 12),
      AlsButton(label: 'New menu type', icon: Icons.add_rounded, height: 48, style: AlsButtonStyle.dark, onPressed: () => _editType()),
      const SizedBox(height: 14),
      for (final (i, c) in _categories.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CardBox(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Column(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: i == 0 ? null : () => _move(c, 'up'),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: i == _categories.length - 1 ? null : () => _move(c, 'down'),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: AlsText.display(18)),
                      Text(
                        '${c.items.length} items${c.tagline.isEmpty ? '' : ' · ${c.tagline}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AlsText.body(12, color: AlsColors.muted),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text('${c.prepMinutes} min', style: AlsText.display(16, color: AlsColors.orangeDeep)),
                    QuantityStepper(
                      value: c.prepMinutes,
                      min: 1,
                      max: 120,
                      compact: true,
                      onChanged: (v) => _patch('/owner/categories/${c.id}', {'prepMinutes': v}),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? _editType(c) : _deleteType(c),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Rename / edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Future<void> _move(MenuCategory c, String direction) async {
    try {
      await context.read<OwnerStore>().api.post('/owner/categories/${c.id}/move', {'direction': direction});
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editType([MenuCategory? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final tagline = TextEditingController(text: c?.tagline ?? '');
    final prep = TextEditingController(text: '${c?.prepMinutes ?? 15}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'New menu type' : 'Edit ${c.name}', style: AlsText.display(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Calzones'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tagline,
              decoration: const InputDecoration(labelText: 'Tagline (optional)', hintText: 'Folded, stuffed, baked'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: prep,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Prep minutes'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(c == null ? 'Create' : 'Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final body = {'name': name.text.trim(), 'tagline': tagline.text.trim(), 'prepMinutes': (int.tryParse(prep.text) ?? 15).clamp(1, 120)};
    try {
      final api = context.read<OwnerStore>().api;
      if (c == null) {
        await api.post('/owner/categories', body);
      } else {
        await api.patch('/owner/categories/${c.id}', body);
      }
      await _load();
      if (mounted) showToast(context, c == null ? 'Created ${body['name']}' : 'Saved');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteType(MenuCategory c) async {
    try {
      await context.read<OwnerStore>().api.delete('/owner/categories/${c.id}');
      await _load();
      if (mounted) showToast(context, 'Deleted ${c.name}');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }
}
