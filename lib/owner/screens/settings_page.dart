import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';

/// Per-store operations: ordering switches, kitchen pacing, delivery routing
/// (own drivers → DoorDash → Uber Direct), POS, reports, and integration status.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Json? _store;
  Json? _integrations;
  final _draft = <String, dynamic>{};
  String? _storeId;
  bool _saving = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _posLocation = TextEditingController();
  final _reportEmail = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<OwnerStore>();
    final id = s.storeId == 'all' ? s.stores.firstOrNull?.id : s.storeId;
    if (id != null && id != _storeId) {
      _storeId = id;
      _load(id);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _posLocation, _reportEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load(String id) async {
    final api = context.read<OwnerStore>().api;
    final res = await Future.wait([api.get('/owner/stores/$id/settings'), api.get('/owner/integrations')]);
    if (!mounted) return;
    setState(() {
      _store = res[0]['store'] as Json;
      _integrations = res[1];
      _draft.clear();
      _name.text = _store!['name'] as String? ?? '';
      _phone.text = _store!['phone'] as String? ?? '';
      _posLocation.text = _store!['posLocationId'] as String? ?? '';
      _reportEmail.text = _store!['reportEmail'] as String? ?? '';
    });
  }

  T _v<T>(String key) => (_draft.containsKey(key) ? _draft[key] : _store![key]) as T;
  void _set(String key, dynamic value) => setState(() => _draft[key] = value);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<OwnerStore>().api.patch('/owner/stores/$_storeId/settings', {
        ..._draft,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'posLocationId': _posLocation.text.trim().isEmpty ? null : _posLocation.text.trim(),
        'reportEmail': _reportEmail.text.trim(),
      });
      await _load(_storeId!);
      if (mounted) showToast(context, 'Settings saved');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return OwnerPageScaffold(
      title: 'Settings',
      subtitle: store == null ? null : store['name'] as String,
      showRange: false,
      allowAllStores: false,
      actions: [
        AlsButton(label: 'Save changes', icon: Icons.save_rounded, expand: false, height: 46, loading: _saving, onPressed: store == null ? null : _save),
      ],
      child: store == null
          ? const Center(child: CircularProgressIndicator(color: AlsColors.orange))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponsiveRow(
                  children: [
                    Panel(
                      title: 'Store',
                      child: Column(
                        children: [
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Store name'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _phone,
                            decoration: const InputDecoration(labelText: 'Phone'),
                          ),
                          const SizedBox(height: 8),
                          _switch('Accepting online orders', 'Pause the app during a rush or outage', 'acceptingOrders'),
                          _switch('Pickup', null, 'pickupEnabled'),
                          _switch('Delivery', null, 'deliveryEnabled'),
                          _switch('Pay at pickup (cash)', 'Customers pay at the counter', 'cashEnabled'),
                        ],
                      ),
                    ),
                    Panel(
                      title: 'Kitchen & tax',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stepper(
                            'Extra minutes per order in the kitchen',
                            'Added to the pickup ETA for every order already in progress',
                            'queueMinutesPerOrder',
                            0,
                            15,
                          ),
                          const SizedBox(height: 12),
                          Text('Sales tax: ${(_v<num>('taxRate') * 100).toStringAsFixed(2)}%', style: AlsText.body(14, weight: FontWeight.w800)),
                          Slider(
                            value: _v<num>('taxRate').toDouble(),
                            min: 0,
                            max: 0.15,
                            divisions: 600,
                            onChanged: (v) => _set('taxRate', double.parse(v.toStringAsFixed(4))),
                          ),
                          const SizedBox(height: 8),
                          Text('End-of-day report', style: AlsText.body(14, weight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.schedule_rounded),
                                label: Text('Runs at ${_v<String>('reportTime')}'),
                                onPressed: () async {
                                  final parts = _v<String>('reportTime').split(':').map(int.parse).toList();
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
                                  );
                                  if (t != null) _set('reportTime', '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                                },
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _reportEmail,
                                  decoration: const InputDecoration(labelText: 'Email reports to', isDense: true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Panel(
                  title: 'Delivery',
                  subtitle: 'Customers always see Al’s — the courier network runs behind the scenes',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (id, label, hint) in const [
                            ('auto', 'Auto', 'Own drivers first, then DoorDash, then Uber'),
                            ('own', 'Own drivers only', 'Staff assign every delivery'),
                            ('doordash', 'DoorDash Drive', 'Uber Direct as backup'),
                            ('uber', 'Uber Direct', 'DoorDash as backup'),
                          ])
                            ChoicePill(label: label, sublabel: hint, selected: _v<String>('deliveryMode') == id, onTap: () => _set('deliveryMode', id)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 28,
                        runSpacing: 16,
                        children: [
                          _stepper('Own drivers on duty', 'In Auto mode, deliveries go to your drivers while this is above 0', 'ownDriversOnDuty', 0, 50),
                          _money('Delivery fee (courier)', 'flatDeliveryFeeCents'),
                          _money('Delivery fee (own drivers)', 'ownDeliveryFeeCents'),
                          _money('Minimum delivery order', 'minDeliveryCents'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _switch(
                        'Pass the courier’s fee through to the customer',
                        'Off = charge the flat fee above and absorb the difference',
                        'deliveryFeeMode',
                        on: 'passthrough',
                        off: 'flat',
                      ),
                      Text('Delivery radius: ${_v<num>('deliveryRadiusMiles').toStringAsFixed(1)} mi', style: AlsText.body(14, weight: FontWeight.w800)),
                      Slider(
                        value: _v<num>('deliveryRadiusMiles').toDouble(),
                        min: 1,
                        max: 15,
                        divisions: 28,
                        onChanged: (v) => _set('deliveryRadiusMiles', v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ResponsiveRow(
                  children: [
                    Panel(
                      title: 'Point of sale',
                      subtitle: 'Paid app orders are pushed straight into your POS / kitchen screen',
                      child: RadioGroup<String>(
                        groupValue: _v<String>('posProvider'),
                        onChanged: (v) => _set('posProvider', v),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in ((_integrations?['pos'] as List?) ?? const []).cast<Json>())
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                value: p['id'] as String,
                                title: Text(p['label'] as String, style: AlsText.body(14, weight: FontWeight.w800)),
                                subtitle: p['id'] == 'none'
                                    ? null
                                    : Text(
                                        p['configured'] == true ? 'API keys found ✓' : 'Add API keys to the server .env to enable',
                                        style: AlsText.body(12, color: p['configured'] == true ? AlsColors.success : AlsColors.muted),
                                      ),
                              ),
                            if (_v<String>('posProvider') == 'square')
                              TextField(
                                controller: _posLocation,
                                decoration: const InputDecoration(labelText: 'Square location ID'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Panel(
                      title: 'Integrations',
                      subtitle: 'Read from the API server’s .env',
                      child: _Integrations(data: _integrations),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _switch(String label, String? hint, String key, {Object on = true, Object off = false}) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: _v<Object>(key) == on,
    onChanged: (v) => _set(key, v ? on : off),
    title: Text(label, style: AlsText.body(14, weight: FontWeight.w800)),
    subtitle: hint == null ? null : Text(hint, style: AlsText.body(12, color: AlsColors.muted)),
  );

  Widget _stepper(String label, String hint, String key, int min, int max) => SizedBox(
    width: 300,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AlsText.body(14, weight: FontWeight.w800)),
              Text(hint, style: AlsText.body(12, color: AlsColors.muted)),
            ],
          ),
        ),
        QuantityStepper(value: _v<num>(key).toInt(), min: min, max: max, compact: true, onChanged: (v) => _set(key, v)),
      ],
    ),
  );

  Widget _money(String label, String key) => SizedBox(
    width: 200,
    child: Row(
      children: [
        Expanded(
          child: Text('$label\n${money(_v<num>(key))}', style: AlsText.body(13, weight: FontWeight.w800)),
        ),
        IconButton(icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: () => _set(key, (_v<num>(key).toInt() - 50).clamp(0, 10000))),
        IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => _set(key, (_v<num>(key).toInt() + 50).clamp(0, 10000))),
      ],
    ),
  );
}

class _Integrations extends StatelessWidget {
  const _Integrations({required this.data});

  final Json? data;

  @override
  Widget build(BuildContext context) {
    final i = (data?['integrations'] as Json?) ?? const {};
    final demo = (data?['demo'] as Json?) ?? const {};
    const rows = [
      ('stripe', 'Stripe (cards, Apple Pay, Google Pay)'),
      ('paypal', 'PayPal'),
      ('doordash', 'DoorDash Drive'),
      ('uber', 'Uber Direct'),
      ('twilio', 'Twilio (driver chat relay)'),
      ('square', 'Square POS'),
      ('clover', 'Clover POS'),
      ('toast', 'Toast POS'),
      ('googleMaps', 'Google Maps geocoding'),
      ('smtp', 'Email for reports'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (key, label) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  i[key] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: i[key] == true ? AlsColors.success : AlsColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: AlsText.body(13, weight: FontWeight.w700)),
                ),
                Text(
                  i[key] == true ? 'Connected' : 'Not set',
                  style: AlsText.body(12, color: i[key] == true ? AlsColors.success : AlsColors.muted, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
        if (demo['payments'] == true || demo['simulateDelivery'] == true) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AlsColors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Demo mode: ${[if (demo['payments'] == true) 'payments are simulated', if (demo['simulateDelivery'] == true) 'couriers are simulated when no DoorDash/Uber keys are set'].join(' · ')}.',
              style: AlsText.body(12, color: AlsColors.brown),
            ),
          ),
        ],
      ],
    );
  }
}
