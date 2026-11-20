import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';

/// Kitchen tablets and drivers: who's on the clock, cash waiting to be settled, and the team list.
class StaffPage extends StatefulWidget {
  const StaffPage({super.key});

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  Json? _data;
  String? _error;
  String? _scope;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sub = context.read<OwnerStore>().realtime.all.listen((e) {
      if (e.event == 'drivers.updated' || e.event == 'order.updated') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), _load);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.watch<OwnerStore>().storeId;
    if (scope != _scope) {
      _scope = scope;
      _load();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<OwnerStore>().api.get('/owner/staff', query: {'storeId': _scope});
      if (mounted) {
        setState(() {
          _data = res;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _do(Future<Json> Function(ApiClient api) call, String done) async {
    try {
      await call(context.read<OwnerStore>().api);
      if (mounted) showToast(context, done);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OwnerStore>();
    final data = _data;
    return OwnerPageScaffold(
      title: 'Staff & drivers',
      subtitle: 'Kitchen tablets and drivers · who’s on the clock · cash to settle',
      showRange: false,
      actions: [AlsButton(label: 'Add staff', icon: Icons.person_add_alt_1_rounded, height: 44, expand: false, onPressed: () => _edit(context, null))],
      child: data == null
          ? Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: _error != null ? Text(_error!, style: AlsText.body(15, color: AlsColors.red)) : const CircularProgressIndicator(color: AlsColors.orange),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _onShift(context, store, (data['onShift'] as List).cast<Json>()),
                const SizedBox(height: 18),
                _cash(context, (data['unsettled'] as List).cast<Json>()),
                const SizedBox(height: 18),
                _team(context, store, (data['staff'] as List).cast<Json>()),
              ],
            ),
    );
  }

  String _storeName(OwnerStore store, String? id) => store.stores.where((s) => s.id == id).firstOrNull?.shortName ?? '—';

  Widget _onShift(BuildContext context, OwnerStore store, List<Json> drivers) => Panel(
    title: 'On the clock',
    subtitle: drivers.isEmpty ? 'No drivers clocked in on Al’s Driver' : '${drivers.length} driver${drivers.length == 1 ? '' : 's'} · orders go to them first',
    child: drivers.isEmpty
        ? Text('When drivers start a shift in the Al’s Driver app they show up here, and delivery orders go to them before DoorDash/Uber.', style: AlsText.body(14, color: AlsColors.muted))
        : Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final d in drivers)
                Container(
                  width: 300,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFBF5EA), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(d['name'] as String? ?? 'Driver', style: AlsText.display(18))),
                          Badge2(d['atStore'] == true ? 'At the store' : 'On the road', color: d['atStore'] == true ? AlsColors.success : AlsColors.orangeDeep, filled: true),
                        ],
                      ),
                      Text(
                        '${_storeName(store, d['storeId'] as String?)} · since ${clock(parseDate(d['startedAt'])!)}',
                        style: AlsText.body(12, color: AlsColors.muted),
                      ),
                      const SizedBox(height: 10),
                      _Load(label: 'On the road', used: (d['run'] as List).length, max: (d['maxActive'] as num).toInt()),
                      const SizedBox(height: 6),
                      _Load(label: 'Queue', used: (d['queue'] as List).length, max: (d['maxBacklog'] as num).toInt()),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final o in (d['run'] as List).cast<Json>()) Badge2('#${o['number']}', color: AlsColors.orangeDeep, icon: Icons.delivery_dining_rounded),
                          for (final o in (d['queue'] as List).cast<Json>())
                            Badge2('#${o['number']}', color: o['ready'] == true ? AlsColors.success : AlsColors.brownSoft),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d['cashEnabled'] == true ? 'Cash collected ${money((d['cashCollectedCents'] as num?) ?? 0)}' : 'Card orders only',
                              style: AlsText.body(13, weight: FontWeight.w800),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (await _confirm(context, 'Clock out ${d['name']}?', 'Their queued orders go back to the store for another driver.')) {
                                await _do((api) => api.post('/owner/staff/${d['driverId']}/end-shift'), 'Clocked out');
                              }
                            },
                            child: const Text('Clock out'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );

  Widget _cash(BuildContext context, List<Json> shifts) => Panel(
    title: 'Cash to settle',
    subtitle: 'Drivers can’t start their next shift until their cash is settled',
    child: shifts.isEmpty
        ? Text('No cash waiting.', style: AlsText.body(14, color: AlsColors.muted))
        : Column(
            children: [
              for (final s in shifts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(backgroundColor: AlsColors.red, child: Icon(Icons.payments_rounded, color: Colors.white)),
                  title: Text('${s['name'] ?? 'Driver'} · ${money((s['cashCollectedCents'] as num).toInt())}', style: AlsText.body(15, weight: FontWeight.w900)),
                  subtitle: Text('Shift ${dayLabel(parseDate(s['startedAt'])!)}, ${clock(parseDate(s['startedAt'])!)} – ${clock(parseDate(s['endedAt'])!)}'),
                  trailing: AlsButton(label: 'Settle', height: 40, expand: false, style: AlsButtonStyle.dark, onPressed: () => _settle(context, s)),
                ),
            ],
          ),
  );

  Widget _team(BuildContext context, OwnerStore store, List<Json> staff) => Panel(
    title: 'Team',
    subtitle: 'Logins for Al’s Kitchen (tablet) and Al’s Driver (phone)',
    child: staff.isEmpty
        ? Text('No staff yet — add your kitchen tablet and drivers.', style: AlsText.body(14, color: AlsColors.muted))
        : Column(
            children: [
              for (final u in staff)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: u['isActive'] == true ? (u['role'] == 'driver' ? AlsColors.basil : AlsColors.red) : AlsColors.line,
                    child: Icon(u['role'] == 'driver' ? Icons.delivery_dining_rounded : Icons.soup_kitchen_rounded, color: Colors.white),
                  ),
                  title: Row(
                    children: [
                      Flexible(child: Text(u['name'] as String? ?? '—', style: AlsText.body(15, weight: FontWeight.w900))),
                      const SizedBox(width: 8),
                      if (u['onShift'] == true) const Badge2('ON THE CLOCK', color: AlsColors.success, filled: true),
                      if (u['isActive'] != true) const Badge2('SWITCHED OFF', color: AlsColors.muted, filled: true),
                      if (((u['cashOwedCents'] as num?) ?? 0) > 0) Badge2('OWES ${money(u['cashOwedCents'] as num)}', color: AlsColors.red, filled: true),
                    ],
                  ),
                  subtitle: Text(
                    [
                      u['role'] == 'driver' ? 'Driver' : 'Kitchen',
                      _storeName(store, u['storeId'] as String?),
                      [u['email'], if (u['phone'] != null) prettyPhone(u['phone'] as String)].whereType<String>().join(' / '),
                      if (u['driver'] != null)
                        '${u['driver']['maxActive']} on the road · ${u['driver']['maxBacklog']} in queue${u['driver']['cashEnabled'] == true ? ' · takes cash' : ''}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded), onPressed: () => _edit(context, u)),
                ),
            ],
          ),
  );

  Future<void> _settle(BuildContext context, Json s) async {
    final collected = (s['cashCollectedCents'] as num).toInt();
    final amount = TextEditingController(text: (collected / 100).toStringAsFixed(2));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Settle ${s['name']}’s cash', style: AlsText.display(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('They collected ${money(collected)} on this shift.', style: AlsText.body(14)),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount you received', prefixText: '\$'),
            ),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark settled')),
        ],
      ),
    );
    final cents = ((double.tryParse(amount.text.replaceAll(',', '').trim()) ?? -1) * 100).round();
    final text = note.text.trim();
    amount.dispose();
    note.dispose();
    if (ok != true) return;
    if (cents < 0) {
      if (context.mounted) showError(context, 'Enter the amount you received');
      return;
    }
    await _do(
      (api) => api.post('/owner/shifts/${s['shiftId']}/settle', {'receivedCents': cents, if (text.isNotEmpty) 'note': text}),
      cents < collected ? 'Settled — ${money(collected - cents)} short noted' : 'Settled',
    );
  }

  Future<void> _edit(BuildContext context, Json? user) async {
    final store = context.read<OwnerStore>();
    final body = await showDialog<Json>(
      context: context,
      builder: (_) => _StaffDialog(user: user, stores: store.stores, defaultStore: store.selectedStore?.id),
    );
    if (body == null) return;
    await _do(
      (api) => user == null ? api.post('/owner/staff', body) : api.patch('/owner/staff/${user['id']}', body),
      user == null ? 'Added ${body['name']}' : 'Saved',
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    ) ??
    false;

class _Load extends StatelessWidget {
  const _Load({required this.label, required this.used, required this.max});

  final String label;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 86, child: Text(label, style: AlsText.body(12, color: AlsColors.muted, weight: FontWeight.w800))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: max == 0 ? 1 : (used / max).clamp(0, 1),
            minHeight: 9,
            backgroundColor: AlsColors.line,
            color: used >= max ? AlsColors.red : AlsColors.orange,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('$used/$max', style: AlsText.body(12, weight: FontWeight.w900)),
    ],
  );
}

/// Add or edit a kitchen/driver login. Pops the request body.
class _StaffDialog extends StatefulWidget {
  const _StaffDialog({required this.user, required this.stores, required this.defaultStore});

  final Json? user;
  final List<StoreRef> stores;
  final String? defaultStore;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final Json? u = widget.user;
  late String role = u?['role'] as String? ?? 'driver';
  late final name = TextEditingController(text: u?['name'] as String? ?? '');
  late final email = TextEditingController(text: u?['email'] as String? ?? '');
  late final phone = TextEditingController(text: u?['phone'] == null ? '' : prettyPhone(u!['phone'] as String));
  late final password = TextEditingController();
  late final vehicle = TextEditingController(text: (u?['driver'] as Json?)?['vehicle'] as String? ?? '');
  late String? storeId = u?['storeId'] as String? ?? widget.defaultStore ?? widget.stores.firstOrNull?.id;
  late int maxActive = ((u?['driver'] as Json?)?['maxActive'] as num?)?.toInt() ?? 4;
  late int maxBacklog = ((u?['driver'] as Json?)?['maxBacklog'] as num?)?.toInt() ?? 6;
  late bool cash = (u?['driver'] as Json?)?['cashEnabled'] as bool? ?? false;
  late bool active = u?['isActive'] as bool? ?? true;
  String? error;

  bool get creating => u == null;

  @override
  void dispose() {
    for (final c in [name, email, phone, password, vehicle]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final pw = password.text;
    if (name.text.trim().isEmpty) return setState(() => error = 'Add their name');
    if (email.text.trim().isEmpty && phone.text.trim().isEmpty) return setState(() => error = 'Add an email or phone number — that’s what they sign in with');
    if (creating && pw.length < 6) return setState(() => error = 'Set a password of at least 6 characters');
    if (!creating && pw.isNotEmpty && pw.length < 6) return setState(() => error = 'New password needs at least 6 characters');
    if (storeId == null) return setState(() => error = 'Pick their store');
    Navigator.pop(context, <String, dynamic>{
      if (creating) 'role': role,
      'name': name.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      if (pw.isNotEmpty) 'password': pw,
      'storeId': storeId,
      if (!creating) 'isActive': active,
      if (role == 'driver') ...{'maxActive': maxActive, 'maxBacklog': maxBacklog, 'cashEnabled': cash, 'vehicle': vehicle.text.trim()},
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(creating ? 'Add staff' : 'Edit ${u!['name']}', style: AlsText.display(20)),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (creating) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'driver', icon: Icon(Icons.delivery_dining_rounded), label: Text('Driver')),
                  ButtonSegment(value: 'kitchen', icon: Icon(Icons.soup_kitchen_rounded), label: Text('Kitchen tablet')),
                ],
                selected: {role},
                onSelectionChanged: (s) => setState(() => role = s.first),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: name, decoration: InputDecoration(labelText: role == 'kitchen' ? 'Name (e.g. Lincoln Park Kitchen)' : 'Name')),
            const SizedBox(height: 8),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (they can sign in with it)')),
            const SizedBox(height: 8),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional if phone is set)')),
            const SizedBox(height: 8),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: creating ? 'Password' : 'New password (leave blank to keep)'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: storeId,
              decoration: const InputDecoration(labelText: 'Store'),
              items: [for (final s in widget.stores) DropdownMenuItem(value: s.id, child: Text(s.shortName))],
              onChanged: (v) => setState(() => storeId = v),
            ),
            if (role == 'driver') ...[
              const SizedBox(height: 14),
              _Stepper(label: 'Most orders on the road at once', value: maxActive, min: 1, max: 10, onChanged: (v) => setState(() => maxActive = v)),
              _Stepper(label: 'Most orders waiting in their queue', value: maxBacklog, min: 0, max: 20, onChanged: (v) => setState(() => maxBacklog = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cash,
                onChanged: (v) => setState(() => cash = v),
                title: const Text('Takes cash-on-delivery orders'),
                subtitle: const Text('Cash is settled with you at the end of each shift'),
              ),
              TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'Vehicle (shown to customers, optional)')),
            ],
            if (!creating)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                onChanged: (v) => setState(() => active = v),
                title: const Text('Account on'),
                subtitle: const Text('Switch off when someone leaves — they’re signed out and clocked out'),
              ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: AlsText.body(13, color: AlsColors.red))),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _save, child: Text(creating ? 'Add' : 'Save')),
    ],
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged});

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: AlsText.body(14))),
      IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
      SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: AlsText.display(18))),
      IconButton(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
    ],
  );
}
