import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';

const _channels = ['Instagram', 'TikTok', 'Facebook', 'Flyer', 'Email', 'Radio', 'Google', 'Referral', 'In-App', 'Other'];

/// Every promo code is tagged with the channel it was shared on, so the
/// dashboard can show which marketing actually brought in orders.
class PromosPage extends StatefulWidget {
  const PromosPage({super.key});

  @override
  State<PromosPage> createState() => _PromosPageState();
}

class _PromosPageState extends State<PromosPage> {
  List<Json> _promos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await context.read<OwnerStore>().api.get('/owner/promos');
    if (mounted) {
      setState(() {
        _promos = ((res['promos'] as List?) ?? const []).cast<Json>();
        _loading = false;
      });
    }
  }

  Future<void> _toggle(Json p, String field, bool v) async {
    try {
      await context.read<OwnerStore>().api.patch('/owner/promos/${p['id']}', {field: v});
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => OwnerPageScaffold(
    title: 'Promo codes',
    subtitle: 'Create a code per campaign — results show up on the dashboard under “Which marketing worked”',
    showFilters: false,
    actions: [AlsButton(label: 'New promo code', icon: Icons.add_rounded, expand: false, height: 46, onPressed: _create)],
    child: _loading
        ? const Center(child: CircularProgressIndicator(color: AlsColors.orange))
        : Panel(
            title: 'All codes',
            subtitle: 'Lifetime results',
            child: SimpleTable(
              columns: const ['Code', 'Offer', 'Channel', 'Campaign', 'Uses', 'Net sales', 'Discount', 'In app', 'Active'],
              numeric: const {4, 5, 6},
              flex: const [2, 3, 2, 3, 1, 2, 2, 1, 1],
              rows: [
                for (final p in _promos)
                  [
                    Text(p['code'] as String, style: AlsText.body(13, weight: FontWeight.w900)),
                    Text('${p['label']}${p['firstOrderOnly'] == true ? ' · first order' : ''}', overflow: TextOverflow.ellipsis),
                    Text(p['channel'] as String),
                    Text((p['campaign'] as String?) ?? '—', overflow: TextOverflow.ellipsis),
                    Text('${p['uses']}'),
                    Text(money(p['netSalesCents'] as num)),
                    Text(money(p['discountCents'] as num)),
                    Tooltip(
                      message: 'Show in the app’s Deals tab',
                      child: Switch(value: p['isPublic'] == true, onChanged: (v) => _toggle(p, 'isPublic', v)),
                    ),
                    Switch(value: p['isActive'] == true, onChanged: (v) => _toggle(p, 'isActive', v)),
                  ],
              ],
            ),
          ),
  );

  Future<void> _create() async {
    final code = TextEditingController();
    final desc = TextEditingController();
    final value = TextEditingController(text: '10');
    final min = TextEditingController(text: '0');
    final campaign = TextEditingController();
    final maxUses = TextEditingController();
    var type = 'percent';
    var channel = 'Instagram';
    var isPublic = false;
    var firstOnly = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('New promo code', style: AlsText.display(22)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Code (e.g. FALL20)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: desc,
                    decoration: const InputDecoration(labelText: 'Description shown to customers'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (t, l) in const [('percent', '% off'), ('fixed', r'$ off'), ('free_delivery', 'Free delivery')])
                        ChoicePill(label: l, selected: type == t, onTap: () => set(() => type = t)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (type != 'free_delivery')
                        Expanded(
                          child: TextField(
                            controller: value,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: type == 'percent' ? 'Percent off' : r'Dollars off'),
                          ),
                        ),
                      if (type != 'free_delivery') const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: min,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: r'Minimum order $'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Where will you share it?', style: AlsText.body(13, weight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final c in _channels) ChoicePill(label: c, selected: channel == c, onTap: () => set(() => channel = c))],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: campaign,
                    decoration: const InputDecoration(labelText: 'Campaign name (optional)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: maxUses,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max total uses (optional)'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isPublic,
                    onChanged: (v) => set(() => isPublic = v),
                    title: Text('Show in the app’s Deals tab', style: AlsText.body(14)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: firstOnly,
                    onChanged: (v) => set(() => firstOnly = v),
                    title: Text('First order only', style: AlsText.body(14)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final v = int.tryParse(value.text) ?? 0;
    try {
      await context.read<OwnerStore>().api.post('/owner/promos', {
        'code': code.text.trim().toUpperCase(),
        'description': desc.text.trim().isEmpty
            ? (type == 'percent'
                  ? '$v% off'
                  : type == 'fixed'
                  ? '\$$v off'
                  : 'Free delivery')
            : desc.text.trim(),
        'type': type,
        'value': type == 'fixed' ? v * 100 : (type == 'percent' ? v : 0),
        'minSubtotalCents': ((double.tryParse(min.text) ?? 0) * 100).round(),
        'channel': channel,
        'campaign': campaign.text.trim().isEmpty ? null : campaign.text.trim(),
        'isPublic': isPublic,
        'firstOrderOnly': firstOnly,
        'maxUses': int.tryParse(maxUses.text),
      });
      await _load();
      if (mounted) showToast(context, 'Created ${code.text.trim().toUpperCase()}');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }
}
