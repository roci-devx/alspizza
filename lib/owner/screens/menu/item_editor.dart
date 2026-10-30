import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/art/food_art.dart';
import '../../../core/art/pizza_art.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/ui.dart';
import '../../owner_store.dart';
import 'photo_upload.dart';

const itemKinds = {
  'pizza': 'Pizza (sizes, crusts, toppings)',
  'deal': 'Combo / deal',
  'wings': 'Wings',
  'side': 'Side',
  'pasta': 'Pasta',
  'dessert': 'Dessert',
  'drink': 'Drink',
  'dip': 'Dip / sauce',
};
const _tagLabels = {'popular': 'Popular', 'new': 'New', 'veg': 'Veggie', 'spicy': 'Spicy'};

int _seq = 0;
String _key() => 'k${_seq++}';

class _Variant {
  _Variant(this.id, this.label, this.priceCents);
  final String key = _key();
  String? id;
  String label;
  int priceCents;
}

class _Option {
  _Option(this.id, this.label);
  final String key = _key();
  String? id;
  String label;
}

class _Choice {
  _Choice(this.id, this.label, this.required, this.options);
  final String key = _key();
  String? id;
  String label;
  bool required;
  List<_Option> options;
}

class _Line {
  _Line(this.text);
  final String key = _key();
  String text;
}

String _dollars(int cents) => (cents / 100).toStringAsFixed(2);
int _cents(String v) => ((double.tryParse(v.replaceAll(r'$', '').trim()) ?? 0) * 100).round();

/// Full-screen editor for a menu item (also used to create one).
class ItemEditor extends StatefulWidget {
  const ItemEditor({super.key, this.item, required this.categories, required this.options, this.categoryId});

  final MenuItem? item;
  final List<MenuCategory> categories;
  final PizzaOptions options;
  final String? categoryId;

  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final _form = GlobalKey<FormState>();
  late String _kind;
  late String _categoryId;
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _calories = TextEditingController(text: widget.item?.calories ?? '');
  late final _prep = TextEditingController(text: widget.item?.prepMinutes?.toString() ?? '');
  late int _priceCents = widget.item?.priceCents ?? 0;
  String? _imageUrl;
  late final Set<String> _tags = {...?widget.item?.tags};
  late bool _available = widget.item?.isAvailable ?? true;

  // Pizza
  final _sizePrices = <String, int?>{};
  final _toppings = <String>{};
  late String _sauce;
  late String _cheese;
  late String _crust;
  late String _defaultSize;
  bool _byo = false;

  // Everything else
  final _variants = <_Variant>[];
  final _choices = <_Choice>[];
  final _includes = <_Line>[];

  bool _saving = false;
  bool _uploading = false;

  PizzaOptions get o => widget.options;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final category = widget.categories.where((c) => c.id == (item?.raw['categoryId'] ?? widget.categoryId)).firstOrNull ?? widget.categories.first;
    _categoryId = category.id;
    _kind = item?.kind ?? (category.slug == 'pizza' ? 'pizza' : (category.slug == 'deals' ? 'deal' : 'side'));
    _imageUrl = item?.imageUrl;
    final p = item?.config.pizza;
    for (final s in o.sizes) {
      _sizePrices[s.id] = p == null ? (item == null ? _suggestedPrice(s.id) : null) : p.sizePrices[s.id];
    }
    _toppings.addAll(p?.toppings ?? const []);
    _sauce = p?.sauce ?? o.sauces.first.id;
    _cheese = p?.cheese ?? (o.cheeses.where((c) => c.id == 'regular').firstOrNull ?? o.cheeses.first).id;
    _crust = p?.crust ?? (o.crusts.where((c) => c.id == 'hand-tossed').firstOrNull ?? o.crusts.first).id;
    _defaultSize = p?.defaultSize ?? (o.sizes.where((s) => s.id == 'large').firstOrNull ?? o.sizes.first).id;
    _byo = p?.byo ?? false;
    for (final v in item?.config.variants ?? const <Variant>[]) {
      _variants.add(_Variant(v.id, v.label, v.priceCents));
    }
    for (final g in item?.config.choices ?? const <ChoiceGroup>[]) {
      _choices.add(_Choice(g.id, g.label, g.required, [for (final x in g.options) _Option(x.id, x.label)]));
    }
    for (final line in item?.config.includes ?? const <String>[]) {
      _includes.add(_Line(line));
    }
  }

  int? _suggestedPrice(String size) => const {'personal': 699, 'medium': 1299, 'large': 1599, 'xl': 1899}[size];

  @override
  void dispose() {
    for (final c in [_name, _description, _calories, _prep]) {
      c.dispose();
    }
    super.dispose();
  }

  Json get _body {
    final original = widget.item?.config.pizza;
    final config = <String, dynamic>{
      if (_kind == 'pizza')
        'pizza': {
          'sizePrices': {
            for (final e in _sizePrices.entries)
              if (e.value != null) e.key: e.value,
          },
          'toppings': _toppings.toList(),
          'sauce': _sauce,
          'cheese': _cheese,
          'crust': _crust,
          'defaultSize': _defaultSize,
          'byo': _byo,
          if (original != null && original.density != 1) 'density': original.density,
        },
      if (_kind != 'pizza' && _variants.isNotEmpty)
        'variants': [
          for (final v in _variants) {'id': ?v.id, 'label': v.label.trim(), 'priceCents': v.priceCents},
        ],
      if (_kind != 'pizza' && _choices.isNotEmpty)
        'choices': [
          for (final g in _choices)
            {
              'id': ?g.id,
              'label': g.label.trim(),
              'required': g.required,
              'options': [
                for (final x in g.options) {'id': ?x.id, 'label': x.label.trim()},
              ],
            },
        ],
      if (_includes.isNotEmpty) 'includes': [for (final l in _includes) l.text.trim()],
    };
    return {
      'categoryId': _categoryId,
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'kind': _kind,
      'priceCents': _priceCents,
      'calories': _calories.text.trim().isEmpty ? null : _calories.text.trim(),
      'imageUrl': _imageUrl,
      'tags': _tags.toList(),
      'isAvailable': _available,
      'prepMinutes': int.tryParse(_prep.text),
      'config': config,
    };
  }

  String? _problem() {
    if (_kind == 'pizza' && !_sizePrices.values.any((v) => v != null)) return 'Offer the pizza in at least one size';
    if (_kind == 'pizza' && _sizePrices[_defaultSize] == null) return 'The default size needs a price';
    if (_variants.any((v) => v.label.trim().isEmpty)) return 'Every size option needs a name';
    if (_choices.any((g) => g.label.trim().isEmpty || g.options.isEmpty || g.options.any((x) => x.label.trim().isEmpty))) {
      return 'Choice groups need a name and at least one option';
    }
    if (_includes.any((l) => l.text.trim().isEmpty)) return 'Remove empty “what’s inside” lines';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final problem = _problem();
    if (problem != null) return showToast(context, problem, icon: Icons.info_outline_rounded);
    setState(() => _saving = true);
    final api = context.read<OwnerStore>().api;
    try {
      if (widget.item == null) {
        await api.post('/owner/items', _body);
      } else {
        await api.patch('/owner/items/${widget.item!.id}', _body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.item!.name}?', style: AlsText.display(20)),
        content: Text(
          'It disappears from the app right away. Past orders keep their history. To hide it temporarily, mark it sold out instead.',
          style: AlsText.body(14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: AlsText.body(14, color: AlsColors.red, weight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<OwnerStore>().api.delete('/owner/items/${widget.item!.id}');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadPhoto(context, context.read<OwnerStore>().api);
      if (url != null) setState(() => _imageUrl = url);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showToast(context, 'Couldn’t open photos: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit item' : 'New item'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete item',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AlsColors.red),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _photoSection(),
                _card('Basics', [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Menu type'),
                    items: [for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                    onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Item type'),
                    items: [for (final e in itemKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _kind = v ?? _kind),
                  ),
                ]),
                if (_kind == 'pizza') ...[_pizzaPrices(), _ingredients()] else ...[_variantsSection(), _choicesSection()],
                if (_kind == 'deal' || _includes.isNotEmpty) _includesSection(),
                _card('Details', [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _tagLabels.entries)
                        ChoicePill(
                          label: e.value,
                          selected: _tags.contains(e.key),
                          onTap: () => setState(() => _tags.contains(e.key) ? _tags.remove(e.key) : _tags.add(e.key)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _calories,
                          decoration: const InputDecoration(labelText: 'Calories (optional)', hintText: '230–380 cal/slice'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _prep,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Prep minutes', hintText: 'Use menu type'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _available,
                    onChanged: (v) => setState(() => _available = v),
                    title: Text('Available in the app', style: AlsText.body(15, weight: FontWeight.w800)),
                    subtitle: Text(_available ? 'Customers can order it' : 'Shows as sold out', style: AlsText.body(12, color: AlsColors.muted)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AlsButton(label: editing ? 'Save changes' : 'Add to menu', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children, {String? subtitle, Widget? action}) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AlsText.display(18, weight: FontWeight.w600)),
                    if (subtitle != null) Text(subtitle, style: AlsText.body(12, color: AlsColors.muted)),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _photoSection() {
    final preview = MenuItem.fromJson({
      ...?widget.item?.raw,
      'id': widget.item?.id ?? 'new',
      'name': _name.text,
      'kind': _kind,
      'art': widget.item?.art ?? (_kind == 'pizza' ? 'pizza' : 'breadsticks'),
      'imageUrl': _imageUrl,
      'config': {
        if (_kind == 'pizza')
          'pizza': {'sizePrices': const {}, 'toppings': _toppings.toList(), 'sauce': _sauce, 'cheese': _cheese, 'crust': _crust, 'defaultSize': _defaultSize},
      },
    });
    return _card('Photo', [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 128,
            height: 128,
            padding: EdgeInsets.all(_imageUrl == null ? 8 : 0),
            decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(22)),
            child: _uploading ? const Center(child: CircularProgressIndicator(color: AlsColors.orange)) : FoodArt.item(preview, radius: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _imageUrl == null
                      ? 'No photo yet — the app shows an illustration that matches the toppings.'
                      : 'This photo shows on the menu and home screen.',
                  style: AlsText.body(13, color: AlsColors.muted),
                ),
                const SizedBox(height: 10),
                AlsButton(
                  label: _imageUrl == null ? 'Upload photo' : 'Replace photo',
                  icon: Icons.add_a_photo_rounded,
                  height: 44,
                  style: AlsButtonStyle.dark,
                  loading: _uploading,
                  onPressed: _upload,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final link = await askPhotoLink(context, _imageUrl);
                        if (link != null && link.isNotEmpty) setState(() => _imageUrl = link);
                      },
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Paste a link'),
                    ),
                    if (_imageUrl != null)
                      TextButton.icon(
                        onPressed: () => setState(() => _imageUrl = null),
                        icon: const Icon(Icons.hide_image_outlined, size: 18),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _money(String label, int? cents, ValueChanged<int> onChanged, {Key? key, bool enabled = true}) => TextFormField(
    key: key,
    initialValue: cents == null ? '' : _dollars(cents),
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, prefixText: r'$ ', isDense: true),
    onChanged: (v) => onChanged(_cents(v)),
  );

  Widget _pizzaPrices() => _card('Sizes & prices', subtitle: 'Switch a size off to not offer it for this pizza', [
    for (final s in o.sizes)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Switch(value: _sizePrices[s.id] != null, onChanged: (on) => setState(() => _sizePrices[s.id] = on ? (_suggestedPrice(s.id) ?? 1299) : null)),
            const SizedBox(width: 6),
            SizedBox(
              width: 110,
              child: Text('${s.label} ${s.inches}"', style: AlsText.body(14, weight: FontWeight.w800)),
            ),
            Expanded(
              child: _money(
                'Price',
                _sizePrices[s.id],
                (c) => _sizePrices[s.id] = c,
                key: ValueKey('size-${s.id}-${_sizePrices[s.id] != null}'),
                enabled: _sizePrices[s.id] != null,
              ),
            ),
          ],
        ),
      ),
    DropdownButtonFormField<String>(
      initialValue: _sizePrices[_defaultSize] != null ? _defaultSize : null,
      decoration: const InputDecoration(labelText: 'Starts on size'),
      items: [
        for (final s in o.sizes)
          if (_sizePrices[s.id] != null) DropdownMenuItem(value: s.id, child: Text(s.label)),
      ],
      onChanged: (v) => setState(() => _defaultSize = v ?? _defaultSize),
    ),
  ]);

  Widget _ingredients() => _card('Ingredients', subtitle: 'What comes on it — customers can still add or remove toppings', [
    for (final group in const [('meat', 'Meats'), ('veggie', 'Veggies')]) ...[
      Text(group.$2, style: AlsText.label(11)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in o.toppings.where((t) => (t.group ?? 'veggie') == group.$1))
            ChoicePill(
              label: t.label,
              leading: ToppingIcon(t.id, size: 26),
              selected: _toppings.contains(t.id),
              onTap: () => setState(() => _toppings.contains(t.id) ? _toppings.remove(t.id) : _toppings.add(t.id)),
            ),
        ],
      ),
      const SizedBox(height: 12),
    ],
    Row(
      children: [
        Expanded(child: _select('Sauce', _sauce, o.sauces, (v) => _sauce = v)),
        const SizedBox(width: 10),
        Expanded(child: _select('Cheese', _cheese, o.cheeses, (v) => _cheese = v)),
      ],
    ),
    const SizedBox(height: 10),
    _select('Crust', _crust, [for (final c in o.crusts) Option(c.id, c.label)], (v) => _crust = v),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _byo,
      onChanged: (v) => setState(() => _byo = v),
      title: Text('Build-your-own pizza', style: AlsText.body(15, weight: FontWeight.w800)),
      subtitle: Text('Every topping the customer picks is charged as an extra', style: AlsText.body(12, color: AlsColors.muted)),
    ),
  ]);

  Widget _select(String label, String value, List<Option> options, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
    initialValue: options.any((x) => x.id == value) ? value : options.first.id,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final x in options)
        DropdownMenuItem(
          value: x.id,
          child: Text(x.label, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) => setState(() => onChanged(v ?? value)),
  );

  Widget _variantsSection() => _card(
    _variants.isEmpty ? 'Price' : 'Sizes / counts',
    subtitle: _variants.isEmpty ? 'Add options like “6 pc / 12 pc” or “20 oz / 2-Liter” if it comes in sizes' : 'Customers pick one; each has its own price',
    action: TextButton.icon(
      onPressed: () => setState(() {
        if (_variants.isEmpty) _variants.add(_Variant(null, 'Regular', _priceCents));
        _variants.add(_Variant(null, '', _priceCents));
      }),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add size'),
    ),
    [
      if (_variants.isEmpty) _money('Price', _priceCents, (c) => _priceCents = c),
      for (final v in _variants)
        Padding(
          key: ValueKey(v.key),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: v.label,
                  decoration: const InputDecoration(labelText: 'Name', hintText: '12 pc', isDense: true),
                  onChanged: (x) => v.label = x,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _money('Price', v.priceCents, (c) => v.priceCents = c)),
              IconButton(
                onPressed: () => setState(() => _variants.remove(v)),
                icon: const Icon(Icons.close_rounded, color: AlsColors.muted),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _choicesSection() => _card(
    'Choices',
    subtitle: 'Things the customer picks, like wing sauce or a free dip',
    action: TextButton.icon(
      onPressed: () => setState(() => _choices.add(_Choice(null, '', true, [_Option(null, '')]))),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add group'),
    ),
    [
      if (_choices.isEmpty) Text('No choices — customers add it as is.', style: AlsText.body(13, color: AlsColors.muted)),
      for (final g in _choices)
        Container(
          key: ValueKey(g.key),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFBF5EA), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: g.label,
                      decoration: const InputDecoration(labelText: 'Group name', hintText: 'Wing sauce', isDense: true),
                      onChanged: (x) => g.label = x,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _choices.remove(g)),
                    icon: const Icon(Icons.delete_outline_rounded, color: AlsColors.muted),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: g.required,
                onChanged: (v) => setState(() => g.required = v),
                title: Text('Customer must choose one', style: AlsText.body(13, weight: FontWeight.w800)),
              ),
              for (final x in g.options)
                Padding(
                  key: ValueKey(x.key),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: x.label,
                          decoration: const InputDecoration(hintText: 'Option', isDense: true),
                          onChanged: (v) => x.label = v,
                        ),
                      ),
                      IconButton(
                        onPressed: g.options.length > 1 ? () => setState(() => g.options.remove(x)) : null,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => g.options.add(_Option(null, ''))),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add option'),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _includesSection() => _card(
    'What’s inside',
    subtitle: 'Shown as a checklist on combos',
    action: TextButton.icon(onPressed: () => setState(() => _includes.add(_Line(''))), icon: const Icon(Icons.add_rounded), label: const Text('Add line')),
    [
      for (final l in _includes)
        Padding(
          key: ValueKey(l.key),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AlsColors.basil, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: l.text,
                  decoration: const InputDecoration(hintText: '2 Medium 1-Topping Pizzas', isDense: true),
                  onChanged: (v) => l.text = v,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _includes.remove(l)),
                icon: const Icon(Icons.close_rounded, color: AlsColors.muted),
              ),
            ],
          ),
        ),
    ],
  );
}
