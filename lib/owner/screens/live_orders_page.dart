import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../owner_store.dart';
import '../widgets/owner_ui.dart';

/// Kitchen board: New → In the oven → Ready → Out for delivery, live over WebSockets.
class LiveOrdersPage extends StatefulWidget {
  const LiveOrdersPage({super.key});

  @override
  State<LiveOrdersPage> createState() => _LiveOrdersPageState();
}

class _LiveOrdersPageState extends State<LiveOrdersPage> {
  List<Order> _orders = [];
  bool _loading = true;
  String? _scope;
  final _flash = <String>{};
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _tick;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final s = context.read<OwnerStore>();
    _sub = s.realtime.all.listen(_onEvent);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _load(quiet: true));
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
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  bool _inScope(String storeId) => context.read<OwnerStore>().storeIdsInScope.contains(storeId);

  void _onEvent(RealtimeEvent e) {
    if (!mounted) return;
    if (e.event == 'order.updated' || e.event == 'order.new') {
      final o = Order.fromJson(e.data as Json);
      if (!_inScope(o.storeId) || o.status == 'pending_payment') return;
      setState(() {
        final i = _orders.indexWhere((x) => x.id == o.id);
        if (i >= 0) {
          _orders[i] = o;
        } else {
          _orders = [..._orders, o];
        }
        if (e.event == 'order.new') _flash.add(o.id);
      });
      if (e.event == 'order.new') Timer(const Duration(seconds: 6), () => mounted ? setState(() => _flash.remove(o.id)) : null);
    } else if (e.event == 'driver.location') {
      final d = e.data as Json;
      final i = _orders.indexWhere((x) => x.id == d['orderId']);
      if (i >= 0) {
        setState(
          () => _orders[i] = _orders[i].withDriverLocation((d['driverLat'] as num).toDouble(), (d['driverLng'] as num).toDouble(), d['status'] as String),
        );
      }
    } else if (e.event == 'chat.message') {
      final m = e.data as Json;
      final i = _orders.indexWhere((x) => x.id == m['orderId']);
      if (i >= 0) setState(() => _orders[i] = Order.fromJson({..._orders[i].raw, 'messageCount': _orders[i].messageCount + 1}));
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final s = context.read<OwnerStore>();
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await s.api.get('/owner/orders', query: {'storeId': s.storeId, 'view': 'board'});
      if (mounted) setState(() => _orders = ((res['orders'] as List?) ?? const []).map((e) => Order.fromJson(e as Json)).toList());
    } on ApiException catch (e) {
      if (mounted && !quiet) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<Json> Function(ApiClient api) call) async {
    final s = context.read<OwnerStore>();
    try {
      final res = await call(s.api);
      final o = res['order'] == null ? null : Order.fromJson(res['order'] as Json);
      if (o != null && mounted) setState(() => _orders = [for (final x in _orders) x.id == o.id ? o : x]);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = [
      ('New', 'Paid and waiting to start', Icons.notifications_active_rounded, _orders.where((o) => o.status == 'received').toList()),
      ('In the oven', 'Being made now', Icons.local_fire_department_rounded, _orders.where((o) => o.status == 'preparing').toList()),
      ('Ready', 'Waiting for pickup or a driver', Icons.shopping_bag_rounded, _orders.where((o) => o.status == 'ready').toList()),
      ('Out for delivery', 'On the road', Icons.delivery_dining_rounded, _orders.where((o) => o.status == 'out_for_delivery').toList()),
    ];
    final done = _orders.where((o) => o.isDone).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return OwnerPageScaffold(
      title: 'Live orders',
      subtitle: 'Updates instantly as orders, couriers and the kitchen move',
      showRange: false,
      scroll: false,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: AlsColors.brown),
        ),
      ],
      child: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AlsColors.orange))
          : LayoutBuilder(
              builder: (context, box) {
                final phone = box.maxWidth < 700;
                final colWidth = box.maxWidth >= 1250 ? (box.maxWidth - 56 - 3 * 16) / 4 : (phone ? box.maxWidth - 56 : 300.0);
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(phone ? 16 : 28, 0, phone ? 16 : 28, 24),
                  children: [
                    for (final (i, (title, hint, icon, orders)) in columns.indexed) ...[
                      if (i > 0) const SizedBox(width: 16),
                      SizedBox(
                        width: colWidth,
                        child: _Column(title: title, hint: hint, icon: icon, orders: orders, flash: _flash, onAct: _act),
                      ),
                    ],
                    const SizedBox(width: 16),
                    SizedBox(width: 260, child: _DoneColumn(orders: done)),
                  ],
                );
              },
            ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.hint, required this.icon, required this.orders, required this.flash, required this.onAct});

  final String title;
  final String hint;
  final IconData icon;
  final List<Order> orders;
  final Set<String> flash;
  final Future<void> Function(Future<Json> Function(ApiClient)) onAct;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: const Color(0xFFEFE6D6), borderRadius: BorderRadius.circular(22)),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: Row(
            children: [
              Icon(icon, color: AlsColors.brown, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: AlsText.display(18, weight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: orders.isEmpty ? Colors.white : AlsColors.brown, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '${orders.length}',
                  style: AlsText.body(13, color: orders.isEmpty ? AlsColors.muted : AlsColors.cream, weight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: AlsText.body(13, color: AlsColors.muted),
                  ),
                )
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => Reveal(
                    key: ValueKey(orders[i].id),
                    child: _OrderCard(order: orders[i], flash: flash.contains(orders[i].id), onAct: onAct),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.flash, required this.onAct});

  final Order order;
  final bool flash;
  final Future<void> Function(Future<Json> Function(ApiClient)) onAct;

  Future<void> _status(String status) => onAct((api) => api.patch('/owner/orders/${order.id}/status', {'status': status}));

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(order.paidAt ?? order.createdAt).inMinutes;
    final late =
        order.estimatedReadyAt != null && DateTime.now().isAfter(order.estimatedReadyAt!) && (order.status == 'received' || order.status == 'preparing');
    final d = order.delivery;
    final own = d?.provider == 'own';
    final needsDriver = order.isDelivery && (d == null || d.status == 'pending_driver');
    final (label, next) = switch (order.status) {
      'received' => ('Start making', 'preparing'),
      'preparing' => ('Mark ready', 'ready'),
      'ready' when !order.isDelivery => ('Picked up', 'completed'),
      'ready' when own && d?.driverName != null => ('Out for delivery', 'out_for_delivery'),
      'out_for_delivery' when own => ('Delivered', 'completed'),
      _ => ('', ''),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: flash ? AlsColors.orange : (late ? AlsColors.red : Colors.transparent), width: 2),
        boxShadow: flash ? const [BoxShadow(color: Color(0x66E8962A), blurRadius: 22)] : alsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${order.number}', style: AlsText.display(19)),
              const SizedBox(width: 8),
              Badge2(order.isDelivery ? 'DELIVERY' : 'PICKUP', color: order.isDelivery ? AlsColors.series2 : AlsColors.series1, filled: true),
              const Spacer(),
              Icon(Icons.timer_outlined, size: 14, color: late ? AlsColors.red : AlsColors.muted),
              const SizedBox(width: 3),
              Text(
                '$age min',
                style: AlsText.body(12, color: late ? AlsColors.red : AlsColors.muted, weight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${order.customerName} · ${prettyPhone(order.customerPhone)}',
            style: AlsText.body(13, color: AlsColors.brownSoft, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final l in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l.quantity}× ${l.name}', style: AlsText.body(14, weight: FontWeight.w900)),
                  if (l.summary.isNotEmpty) Text(l.summary, style: AlsText.body(12, color: AlsColors.muted)),
                  if (l.config['notes'] != null)
                    Text(
                      '“${l.config['notes']}”',
                      style: AlsText.body(12, color: AlsColors.red, weight: FontWeight.w800),
                    ),
                ],
              ),
            ),
          if (order.notes != null)
            Text(
              'Note: ${order.notes}',
              style: AlsText.body(12, color: AlsColors.red, weight: FontWeight.w800),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Badge2(money(order.totalCents), color: AlsColors.ink),
              if (order.paymentStatus == 'pay_at_pickup') const Badge2('COLLECT PAYMENT', color: AlsColors.red, filled: true),
              if (order.promoCode != null) Badge2(order.promoCode!, color: AlsColors.basil),
              if (order.estimatedReadyAt != null && order.isActive)
                Badge2('Ready by ${clock(order.estimatedReadyAt!)}', color: late ? AlsColors.red : AlsColors.brownSoft),
              if (order.posError != null) const Badge2('POS failed', color: AlsColors.red, icon: Icons.error_outline_rounded),
              if (order.posProvider != null && order.posError == null)
                Badge2('Sent to ${order.posProvider}', color: AlsColors.success, icon: Icons.check_rounded),
              if (order.messageCount > 0) Badge2('${order.messageCount} msgs', color: AlsColors.series2, icon: Icons.chat_bubble_rounded),
            ],
          ),
          if (order.isDelivery) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFBF5EA), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.delivery_dining_rounded, size: 18, color: AlsColors.brownSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          needsDriver ? 'Needs a driver' : '${providerLabel(d!.provider)} · ${d.driverName ?? 'assigning…'}',
                          style: AlsText.body(12, color: needsDriver ? AlsColors.red : AlsColors.ink, weight: FontWeight.w900),
                        ),
                        if (d != null) Text(d.status.replaceAll('_', ' '), style: AlsText.body(11, color: AlsColors.muted)),
                      ],
                    ),
                  ),
                  if (d?.trackingUrl != null)
                    IconButton(
                      tooltip: 'Courier tracking',
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      onPressed: () => launchUrl(Uri.parse(d!.trackingUrl!)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (label.isNotEmpty)
                Expanded(
                  child: AlsButton(label: label, height: 40, style: AlsButtonStyle.dark, onPressed: () => _status(next)),
                ),
              if (needsDriver || (own && d?.driverName == null)) ...[
                if (label.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: AlsButton(label: 'Assign driver', height: 40, style: AlsButtonStyle.outline, onPressed: () => _assign(context)),
                ),
              ],
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded, color: AlsColors.brownSoft),
                onSelected: (v) async {
                  if (v == 'details') _details(context);
                  if (v == 'own') _assign(context);
                  if (v == 'courier') onAct((api) => api.post('/owner/orders/${order.id}/send-to-courier'));
                  if (v == 'pos') onAct((api) => api.post('/owner/orders/${order.id}/retry-pos'));
                  if (v == 'cancel' && await _confirmCancel(context)) {
                    onAct((api) => api.post('/owner/orders/${order.id}/cancel', {'reason': 'Your order was cancelled by the store'}));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'details', child: Text('Details & messages')),
                  if (needsDriver || own) const PopupMenuItem(value: 'courier', child: Text('Send to DoorDash / Uber')),
                  if (order.isDelivery && !own && !needsDriver && order.status != 'out_for_delivery')
                    const PopupMenuItem(value: 'own', child: Text('Use one of our drivers instead')),
                  if (order.posError != null) const PopupMenuItem(value: 'pos', child: Text('Retry sending to POS')),
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel & refund')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Assign one of your drivers', style: AlsText.display(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Driver name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              decoration: const InputDecoration(hintText: 'Driver phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await onAct(
        (api) => api.post('/owner/orders/${order.id}/assign-driver', {'name': name.text.trim(), if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim()}),
      );
    }
  }

  Future<bool> _confirmCancel(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Cancel order #${order.number}?', style: AlsText.display(20)),
          content: Text('The customer is refunded automatically and any courier is called off.', style: AlsText.body(14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Cancel & refund',
                style: AlsText.body(14, color: AlsColors.red, weight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ) ??
      false;

  void _details(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _OrderDetails(orderId: order.id, api: context.read<OwnerStore>().api),
  );
}

class _OrderDetails extends StatefulWidget {
  const _OrderDetails({required this.orderId, required this.api});

  final String orderId;
  final ApiClient api;

  @override
  State<_OrderDetails> createState() => _OrderDetailsState();
}

class _OrderDetailsState extends State<_OrderDetails> {
  Order? _order;
  List<ChatMessage> _messages = [];
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await widget.api.get('/owner/orders/${widget.orderId}');
    if (!mounted) return;
    setState(() {
      _order = Order.fromJson(res['order'] as Json);
      _messages = ((res['messages'] as List?) ?? const []).map((e) => ChatMessage.fromJson(e as Json)).toList();
    });
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    await widget.api.post('/owner/orders/${widget.orderId}/messages', {'body': _reply.text.trim()});
    _reply.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: o == null
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: AlsColors.orange)),
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      Text('Order #${o.number}', style: AlsText.display(24)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  Text(
                    '${o.customerName} · ${prettyPhone(o.customerPhone)}${o.customerEmail != null ? ' · ${o.customerEmail}' : ''}',
                    style: AlsText.body(14, color: AlsColors.brownSoft),
                  ),
                  if (o.address != null)
                    Text(
                      o.address!.full + (o.address!.instructions != null ? ' — “${o.address!.instructions}”' : ''),
                      style: AlsText.body(13, color: AlsColors.muted),
                    ),
                  const SizedBox(height: 14),
                  SimpleTable(
                    columns: const ['Item', 'Qty', 'Total'],
                    numeric: const {1, 2},
                    flex: const [4, 1, 1],
                    rows: [
                      for (final l in o.items)
                        [Text('${l.name}${l.summary.isEmpty ? '' : '\n${l.summary}'}'), Text('${l.quantity}'), Text(money(l.totalCents))],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Text('Subtotal ${money(o.subtotalCents)}', style: AlsText.body(13)),
                      if (o.discountCents > 0) Text('Discount −${money(o.discountCents)} (${o.promoCode})', style: AlsText.body(13, color: AlsColors.basil)),
                      if (o.isDelivery) Text('Delivery ${money(o.deliveryFeeCents)}', style: AlsText.body(13)),
                      Text('Tax ${money(o.taxCents)}', style: AlsText.body(13)),
                      if (o.tipCents > 0) Text('Tip ${money(o.tipCents)}', style: AlsText.body(13)),
                      Text('Total ${money(o.totalCents)}', style: AlsText.body(13, weight: FontWeight.w900)),
                      Text(
                        'Paid with ${o.paymentMethod ?? o.paymentProvider ?? '—'} · ${platformLabel(o.platform)}',
                        style: AlsText.body(13, color: AlsColors.muted),
                      ),
                    ],
                  ),
                  if (o.delivery != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Courier: ${providerLabel(o.delivery!.provider)}${o.delivery!.providerFeeCents != null && o.delivery!.providerFeeCents! > 0 ? ' · fee ${money(o.delivery!.providerFeeCents!)}' : ''} · ${o.delivery!.status.replaceAll('_', ' ')}',
                      style: AlsText.body(13, weight: FontWeight.w800),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text('Customer ↔ driver messages', style: AlsText.display(18)),
                  const SizedBox(height: 8),
                  if (_messages.isEmpty) Text('No messages yet.', style: AlsText.body(13, color: AlsColors.muted)),
                  for (final m in _messages)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${m.sender[0].toUpperCase()}${m.sender.substring(1)} · ${clock(m.createdAt)}  ',
                              style: AlsText.body(12, color: AlsColors.muted, weight: FontWeight.w800),
                            ),
                            TextSpan(text: m.body, style: AlsText.body(14)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reply,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(hintText: 'Reply as Al’s team'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AlsButton(label: 'Send', expand: false, height: 48, style: AlsButtonStyle.dark, onPressed: _send),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _DoneColumn extends StatelessWidget {
  const _DoneColumn({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(22)),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: Text('Done · last 12 hours', style: AlsText.display(16, weight: FontWeight.w600)),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final o in orders.take(40))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(
                    o.status == 'cancelled' ? Icons.cancel_rounded : Icons.check_circle_rounded,
                    color: o.status == 'cancelled' ? AlsColors.muted : AlsColors.success,
                  ),
                  title: Text('#${o.number} · ${o.customerName}', style: AlsText.body(13, weight: FontWeight.w800)),
                  subtitle: Text(
                    '${o.isDelivery ? 'Delivery' : 'Pickup'} · ${money(o.totalCents)} · ${clock(o.createdAt)}',
                    style: AlsText.body(11, color: AlsColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
