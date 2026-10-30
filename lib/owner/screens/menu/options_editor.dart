import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/art/pizza_art.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/ui.dart';
import '../../owner_store.dart';

int _seq = 0;

class _Row {
  _Row(this.data) : key = 'r${_seq++}';
  final String key;
  final Json data;
}

String _dollars(num cents) => (cents / 100).toStringAsFixed(2);
int _cents(String v) => ((double.tryParse(v.replaceAll(r'$', '').trim()) ?? 0) * 100).round();

/// Shared pizza builder options: sizes, crusts, sauces, cheeses and toppings.
class PizzaOptionsEditor extends StatefulWidget {
  const PizzaOptionsEditor({super.key, required this.options, required this.onSaved});

  final PizzaOptions options;
  final VoidCallback onSaved;

  @override
  State<PizzaOptionsEditor> createState() => _PizzaOptionsEditorState();
}

class _PizzaOptionsEditorState extends State<PizzaOptionsEditor> {
  late List<_Row> _sizes;
  late List<_Row> _crusts;
  late List<_Row> _sauces;
  late List<_Row> _cheeses;
  late List<_Row> _toppings;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final j = widget.options.toJson();
    List<_Row> rows(String key) => [for (final r in (j[key] as List)) _Row(Map<String, dynamic>.from(r as Map))];
    _sizes = rows('sizes');
    _crusts = rows('crusts');
    for (final c in _crusts) {
      c.data['sizes'] = List<String>.from(c.data['sizes'] as List);
      c.data['upcharges'] = Map<String, dynamic>.from(c.data['upcharges'] as Map);
    }
    _sauces = rows('sauces');
    _cheeses = rows('cheeses');
    _toppings = rows('toppings');
    _dirty = false;
  }

  void _touch(VoidCallback f) => setState(() {
    f();
    _dirty = true;
  });

  Future<void> _save() async {
    final all = [..._sizes, ..._crusts, ..._sauces, ..._cheeses, ..._toppings];
    if (all.any((r) => (r.data['label'] as String? ?? '').trim().isEmpty)) {
      return showToast(context, 'Every row needs a name', icon: Icons.info_outline_rounded);
    }
    setState(() => _saving = true);
    try {
      Json clean(_Row r) => {...r.data, 'label': (r.data['label'] as String).trim()};
      await context.read<OwnerStore>().api.put('/owner/pizza-options', {
        'sizes': _sizes.map(clean).toList(),
        'crusts': _crusts.map(clean).toList(),
        'sauces': _sauces.map(clean).toList(),
        'cheeses': _cheeses.map(clean).toList(),
        'toppings': _toppings.map(clean).toList(),
      });
      registerToppingArt(_toppings.map((t) => (id: (t.data['id'] as String?) ?? '', art: t.data['art'] as String?)));
      if (!mounted) return;
      setState(() => _dirty = false);
      showToast(context, 'Pizza options saved — the app updates on next menu load');
      widget.onSaved();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, String subtitle, VoidCallback onAdd, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
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
                    Text(subtitle, style: AlsText.body(12, color: AlsColors.muted)),
                  ],
                ),
              ),
              TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
            ],
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    ),
  );

  Widget _field(_Row r, String key, String label, {bool money = false, bool number = false, int flex = 3}) => Expanded(
    flex: flex,
    child: TextFormField(
      key: ValueKey('${r.key}-$key'),
      initialValue: money ? _dollars((r.data[key] as num?) ?? 0) : '${r.data[key] ?? ''}',
      keyboardType: money || number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label, prefixText: money ? r'$ ' : null, isDense: true),
      onChanged: (v) {
        _dirty = true;
        r.data[key] = money ? _cents(v) : (number ? (int.tryParse(v) ?? 0) : v);
      },
    ),
  );

  Widget _remove(List<_Row> list, _Row r, {int min = 1}) => IconButton(
    tooltip: 'Remove',
    onPressed: list.length > min ? () => _touch(() => list.remove(r)) : null,
    icon: const Icon(Icons.close_rounded, color: AlsColors.muted),
  );

  @override
  Widget build(BuildContext context) {
    final sizeIds = [for (final s in _sizes) (s.data['id'] as String?) ?? ''];
    final sizeLabel = {for (final s in _sizes) (s.data['id'] as String?) ?? '': s.data['label'] as String? ?? ''};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_dirty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(color: AlsColors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Text('Unsaved changes', style: AlsText.body(14, weight: FontWeight.w800)),
                ),
                TextButton(onPressed: () => setState(_reset), child: const Text('Discard')),
                AlsButton(label: 'Save', expand: false, height: 40, loading: _saving, onPressed: _save),
              ],
            ),
          ),
        _section(
          'Sizes',
          'Topping price is what each extra topping costs on that size',
          () => _touch(() => _sizes.add(_Row({'label': '', 'inches': 10, 'slices': 6, 'toppingCents': 150}))),
          [
            for (final r in _sizes)
              Padding(
                key: ValueKey(r.key),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    _field(r, 'label', 'Name'),
                    const SizedBox(width: 6),
                    _field(r, 'inches', 'Inches', number: true, flex: 2),
                    const SizedBox(width: 6),
                    _field(r, 'slices', 'Slices', number: true, flex: 2),
                    const SizedBox(width: 6),
                    _field(r, 'toppingCents', 'Topping', money: true, flex: 3),
                    _remove(_sizes, r),
                  ],
                ),
              ),
          ],
        ),
        _section(
          'Crusts',
          'Pick which sizes each crust comes in and any upcharge',
          () => _touch(
            () => _crusts.add(
              _Row({
                'label': '',
                'description': '',
                'sizes': [...sizeIds.where((s) => s.isNotEmpty)],
                'upcharges': <String, dynamic>{},
              }),
            ),
          ),
          [
            for (final r in _crusts)
              Container(
                key: ValueKey(r.key),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFBF5EA), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [_field(r, 'label', 'Crust name'), _remove(_crusts, r)]),
                    const SizedBox(height: 8),
                    Row(children: [_field(r, 'description', 'Short description')]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in sizeIds.where((s) => s.isNotEmpty))
                          ChoicePill(
                            label: sizeLabel[id] ?? id,
                            selected: (r.data['sizes'] as List).contains(id),
                            onTap: () => _touch(() {
                              final sizes = r.data['sizes'] as List;
                              sizes.contains(id) ? sizes.remove(id) : sizes.add(id);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in (r.data['sizes'] as List).cast<String>())
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              key: ValueKey('${r.key}-up-$id'),
                              initialValue: _dollars(((r.data['upcharges'] as Map)[id] as num?) ?? 0),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(labelText: '${sizeLabel[id] ?? id} upcharge', prefixText: r'$ ', isDense: true),
                              onChanged: (v) {
                                _dirty = true;
                                final c = _cents(v);
                                final up = r.data['upcharges'] as Map;
                                c == 0 ? up.remove(id) : up[id] = c;
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
        _section('Sauces', 'Offered on every pizza', () => _touch(() => _sauces.add(_Row({'label': ''}))), [
          for (final r in _sauces)
            Padding(
              key: ValueKey(r.key),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [_field(r, 'label', 'Sauce'), _remove(_sauces, r)]),
            ),
        ]),
        _section('Cheese levels', '“Extra” levels cost one topping price', () => _touch(() => _cheeses.add(_Row({'label': ''}))), [
          for (final r in _cheeses)
            Padding(
              key: ValueKey(r.key),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _field(r, 'label', 'Level'),
                  const SizedBox(width: 8),
                  Text('Extra', style: AlsText.body(13, weight: FontWeight.w800)),
                  Switch(value: r.data['extra'] == true, onChanged: (v) => _touch(() => v ? r.data['extra'] = true : r.data.remove('extra'))),
                  _remove(_cheeses, r),
                ],
              ),
            ),
        ]),
        _section(
          'Toppings',
          'New toppings borrow the look of an existing one on the pizza drawing',
          () => _touch(() => _toppings.add(_Row({'label': '', 'group': 'veggie', 'art': 'mushroom'}))),
          [
            for (final r in _toppings)
              Padding(
                key: ValueKey(r.key),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ToppingIcon((r.data['art'] as String?) ?? (r.data['id'] as String?) ?? 'mushroom', size: 34),
                    const SizedBox(width: 8),
                    _field(r, 'label', 'Topping'),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 104,
                      child: DropdownButtonFormField<String>(
                        initialValue: (r.data['group'] as String?) ?? 'veggie',
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Group', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'meat', child: Text('Meat')),
                          DropdownMenuItem(value: 'veggie', child: Text('Veggie')),
                        ],
                        onChanged: (v) => _touch(() => r.data['group'] = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 128,
                      child: DropdownButtonFormField<String>(
                        initialValue: toppingArtChoices.contains(r.data['art'] ?? r.data['id']) ? (r.data['art'] ?? r.data['id']) as String : 'mushroom',
                        isDense: true,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Looks like', isDense: true),
                        items: [
                          for (final a in toppingArtChoices)
                            DropdownMenuItem(
                              value: a,
                              child: Text(a.replaceAll('-', ' '), overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => _touch(() => r.data['art'] = v),
                      ),
                    ),
                    _remove(_toppings, r, min: 0),
                  ],
                ),
              ),
          ],
        ),
        AlsButton(label: 'Save pizza options', icon: Icons.save_rounded, loading: _saving, onPressed: _dirty ? _save : null),
      ],
    );
  }
}
