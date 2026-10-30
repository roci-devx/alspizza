import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/art/food_art.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../logic.dart';
import '../state/cart.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import '../widgets/tracking_art.dart';

/// Live order tracker: kitchen progress, ETA, courier map, chat & call.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.orderId, this.justPaid = false});

  final String orderId;
  final bool justPaid;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Order? _order;
  String? _error;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _poll;
  Timer? _tick;
  late final RealtimeClient _realtime;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionStore>();
    _realtime = session.realtime;
    _realtime.subscribe('order:${widget.orderId}');
    _sub = _realtime.on('order:${widget.orderId}').listen(_onEvent);
    _load(sync: widget.justPaid);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    _tick?.cancel();
    _realtime.unsubscribe('order:${widget.orderId}');
    super.dispose();
  }

  void _onEvent(RealtimeEvent e) {
    if (!mounted) return;
    if (e.event == 'order.updated') {
      _set(Order.fromJson(e.data as Json));
    } else if (e.event == 'driver.location' && _order != null) {
      final d = e.data as Json;
      setState(
        () => _order = _order!.withDriverLocation(
          (d['driverLat'] as num).toDouble(),
          (d['driverLng'] as num).toDouble(),
          d['status'] as String? ?? _order!.delivery?.status ?? '',
        ),
      );
    }
  }

  void _set(Order o) {
    setState(() => _order = o);
    context.read<OrdersStore>().upsert(o);
    // Returning from a hosted checkout on web: empty the bag once payment lands.
    final cart = context.read<CartStore>();
    if (o.paymentStatus != 'unpaid' && cart.prefs.getString(CartStore.pendingOrderKey) == o.id) {
      cart.prefs.remove(CartStore.pendingOrderKey);
      cart.clear();
    }
  }

  Future<void> _load({bool sync = false}) async {
    final session = context.read<SessionStore>();
    try {
      await session.ensureSession();
      final res = sync ? await session.api.post('/orders/${widget.orderId}/payment/sync') : await session.api.get('/orders/${widget.orderId}');
      if (mounted && res['order'] != null) _set(Order.fromJson(res['order'] as Json));
    } on ApiException catch (e) {
      if (mounted && _order == null) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(o == null ? 'Your order' : 'Order #${o.number}'),
        actions: [
          if (o != null)
            IconButton(icon: const Icon(Icons.call_rounded), tooltip: 'Call the store', onPressed: () => launchUrl(Uri.parse('tel:${o.storePhone}'))),
        ],
      ),
      body: o == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center, style: AlsText.body(16)),
                    )
                  : const CircularProgressIndicator(color: AlsColors.orange),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AlsColors.orange,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _StatusHeader(order: o),
                  const SizedBox(height: 18),
                  _Steps(order: o),
                  if (o.isDelivery && o.status != 'cancelled') ...[const SizedBox(height: 18), _DeliveryCard(order: o)],
                  if (!o.isDelivery && o.status != 'cancelled') ...[const SizedBox(height: 18), _PickupCard(order: o)],
                  const SizedBox(height: 18),
                  _Receipt(order: o),
                  if (o.isDone) ...[
                    const SizedBox(height: 18),
                    AlsButton(
                      label: 'Order this again',
                      icon: Icons.replay_rounded,
                      style: AlsButtonStyle.dark,
                      onPressed: () {
                        final menu = context.read<CatalogStore>().menu;
                        if (menu == null) return;
                        final cart = context.read<CartStore>();
                        for (final l in linesFromOrder(o, menu)) {
                          cart.add(l);
                        }
                        context.go('/home');
                        context.push('/cart');
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = statusCopy[order.status] ?? ('In progress', '');
    final eta = order.isDelivery ? (order.delivery?.dropoffEta ?? order.estimatedDeliveryAt) : order.estimatedReadyAt;
    final minutes = eta?.difference(DateTime.now()).inMinutes;
    return Column(
      children: [
        OrderStatusArt(status: order.status, delivery: order.isDelivery),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(title, key: ValueKey(title), style: AlsText.display(30), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AlsText.body(15, color: AlsColors.muted),
          textAlign: TextAlign.center,
        ),
        if (eta != null && order.isActive) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: AlsColors.brown, borderRadius: BorderRadius.circular(22)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule_rounded, color: AlsColors.orangeLight, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${order.isDelivery ? 'Arrives' : 'Ready'} around ${clock(eta)}${minutes != null && minutes > 0 ? ' · $minutes min' : ''}',
                  style: AlsText.body(15, color: AlsColors.cream, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final steps = order.isDelivery
        ? const [
            ('received', 'Received', Icons.receipt_long_rounded),
            ('preparing', 'In the oven', Icons.local_fire_department_rounded),
            ('out_for_delivery', 'On the way', Icons.delivery_dining_rounded),
            ('completed', 'Delivered', Icons.home_rounded),
          ]
        : const [
            ('received', 'Received', Icons.receipt_long_rounded),
            ('preparing', 'In the oven', Icons.local_fire_department_rounded),
            ('ready', 'Ready', Icons.shopping_bag_rounded),
            ('completed', 'Picked up', Icons.check_rounded),
          ];
    final order0 = ['received', 'preparing', 'ready', 'out_for_delivery', 'completed'];
    final current = order0.indexOf(order.status);
    final done = [for (final s in steps) order0.indexOf(s.$1) <= current];
    final progress = done.where((d) => d).length;
    return CardBox(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned(
                      left: w / 8,
                      right: w / 8,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    Positioned(
                      left: w / 8,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress <= 1 ? 0 : (progress - 1) / (steps.length - 1)),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeInOutCubic,
                        builder: (context, v, _) => Container(
                          width: (w * 0.75) * v,
                          height: 6,
                          decoration: BoxDecoration(color: AlsColors.orange, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (i, s) in steps.indexed)
                          Expanded(
                            child: Center(
                              child: _StepDot(icon: s.$3, done: done[i] && order.status != 'cancelled', current: i == progress - 1 && order.isActive),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, s) in steps.indexed)
                Expanded(
                  child: Text(
                    s.$2,
                    textAlign: TextAlign.center,
                    style: AlsText.body(12, color: done[i] ? AlsColors.brown : AlsColors.muted, weight: done[i] ? FontWeight.w900 : FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatefulWidget {
  const _StepDot({required this.icon, required this.done, required this.current});

  final IconData icon;
  final bool done;
  final bool current;

  @override
  State<_StepDot> createState() => _StepDotState();
}

class _StepDotState extends State<_StepDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Stack(
      alignment: Alignment.center,
      children: [
        if (widget.current)
          Container(
            width: 40 + 10 * _c.value,
            height: 40 + 10 * _c.value,
            decoration: BoxDecoration(
              color: AlsColors.orange.withValues(alpha: 0.35 * (1 - _c.value)),
              shape: BoxShape.circle,
            ),
          ),
        child!,
      ],
    ),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: widget.done ? AlsColors.orange : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: widget.done ? AlsColors.orange : AlsColors.line, width: 2),
      ),
      child: Icon(widget.icon, size: 20, color: widget.done ? AlsColors.brown : AlsColors.muted),
    ),
  );
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final d = order.delivery;
    final home = order.address;
    final driverPos = d?.driverLat != null && d?.driverLng != null ? Offset(d!.driverLat!, d.driverLng!) : null;
    return CardBox(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (home?.lat != null)
            SizedBox(
              height: 230,
              child: LiveMap(
                store: Offset(order.storeLat, order.storeLng),
                home: Offset(home!.lat!, home.lng!),
                driver: order.status == 'completed' ? null : driverPos,
                status: d?.status ?? '',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: d == null || !d.hasDriver
                  ? Row(
                      key: const ValueKey('finding'),
                      children: [
                        const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AlsColors.orange)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Lining up your driver…', style: AlsText.body(15, weight: FontWeight.w800)),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('driver'),
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AlsColors.orange,
                          child: Text(d.driverName!.characters.first, style: AlsText.display(20, color: AlsColors.brown)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.driverName!, style: AlsText.display(18)),
                              Text(d.driverVehicle ?? _driverStatus(d.status), style: AlsText.body(13, color: AlsColors.muted)),
                            ],
                          ),
                        ),
                        _RoundAction(icon: Icons.chat_bubble_rounded, onTap: () => context.push('/order/${order.id}/chat')),
                        const SizedBox(width: 8),
                        if (d.driverPhone != null) _RoundAction(icon: Icons.call_rounded, onTap: () => launchUrl(Uri.parse('tel:${d.driverPhone}'))),
                      ],
                    ),
            ),
          ),
          if (d != null && d.hasDriver)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
              child: Text(
                _driverStatus(d.status),
                style: AlsText.body(13, color: AlsColors.brownSoft, weight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  static String _driverStatus(String s) => switch (s) {
    'confirmed' => 'Driver assigned',
    'enroute_to_pickup' => 'Heading to Al’s to grab your food',
    'arrived_at_pickup' => 'At the store, waiting on your pizza',
    'picked_up' || 'enroute_to_dropoff' => 'Your food is on the way',
    'arrived_at_dropoff' => 'Your driver has arrived!',
    'delivered' => 'Delivered — enjoy!',
    'pending_driver' => 'Assigning one of our drivers',
    _ => 'Getting things ready',
  };
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    child: Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(color: AlsColors.brown, shape: BoxShape.circle),
      child: Icon(icon, color: AlsColors.cream, size: 22),
    ),
  );
}

class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Row(
      children: [
        const Icon(Icons.storefront_rounded, color: AlsColors.orangeDeep, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.storeName.split('—').last.trim(), style: AlsText.display(18)),
              Text(order.storeAddress.full, style: AlsText.body(13, color: AlsColors.muted)),
              const SizedBox(height: 4),
              Text(
                'Tell the counter your name: ${order.customerName}',
                style: AlsText.body(13, color: AlsColors.brownSoft, weight: FontWeight.w800),
              ),
            ],
          ),
        ),
        _RoundAction(
          icon: Icons.directions_rounded,
          onTap: () => launchUrl(
            Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${order.storeLat},${order.storeLng}'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    ),
  );
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, int cents, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            k,
            style: AlsText.body(bold ? 16 : 14, weight: bold ? FontWeight.w900 : FontWeight.w700, color: color ?? AlsColors.ink),
          ),
          const Spacer(),
          Text(
            money(cents),
            style: bold ? AlsText.display(18) : AlsText.body(14, weight: FontWeight.w800, color: color ?? AlsColors.ink),
          ),
        ],
      ),
    );
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order details', style: AlsText.display(18)),
          const SizedBox(height: 10),
          for (final (i, l) in order.items.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(dimension: 44, child: FoodArt.line(l.art, l.config, seed: i)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l.quantity}× ${l.name}', style: AlsText.body(14, weight: FontWeight.w900)),
                        if (l.summary.isNotEmpty) Text(l.summary, style: AlsText.body(12, color: AlsColors.muted)),
                      ],
                    ),
                  ),
                  Text(money(l.totalCents), style: AlsText.body(14, weight: FontWeight.w800)),
                ],
              ),
            ),
          const Divider(height: 18),
          row('Subtotal', order.subtotalCents),
          if (order.discountCents > 0) row('Promo ${order.promoCode ?? ''}', -order.discountCents, color: AlsColors.basil),
          if (order.isDelivery) row('Delivery fee', order.deliveryFeeCents),
          row('Tax', order.taxCents),
          if (order.tipCents > 0) row('Driver tip', order.tipCents),
          const Divider(height: 18),
          row('Total', order.totalCents, bold: true),
          if (order.paymentMethod != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Paid with ${order.paymentMethod}', style: AlsText.body(12, color: AlsColors.muted)),
            ),
        ],
      ),
    );
  }
}
