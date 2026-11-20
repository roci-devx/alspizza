import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets/ui.dart';
import '../staff/staff_session.dart';
import 'kitchen_controller.dart';
import 'ticket_pdf.dart';

/// Al's Kitchen: the tablet on the kitchen wall. New orders ring until someone taps them;
/// staff open the ticket (and can print it), then tap Start and Done.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  late final KitchenController _k = KitchenController(context.read<StaffSession>())..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((Object _) {});
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {})); // "6 min" timers
  }

  @override
  void dispose() {
    _tick?.cancel();
    WakelockPlus.disable().catchError((Object _) {});
    _k.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _k,
    child: Consumer<KitchenController>(
      builder: (context, k, _) => Scaffold(
        backgroundColor: const Color(0xFF2A120A),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _TopBar(k: k),
                  Expanded(child: _body(k)),
                ],
              ),
              if (!k.ringer.unlocked) _StartOverlay(onStart: () => setState(() => k.ringer.unlock())),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _body(KitchenController k) {
    if (k.loading && k.orders.isEmpty) return const Center(child: CircularProgressIndicator(color: AlsColors.orange));
    if (k.error != null && k.orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(k.error!, style: AlsText.body(16, color: AlsColors.cream)),
            const SizedBox(height: 12),
            AlsButton(label: 'Try again', expand: false, onPressed: k.refresh),
          ],
        ),
      );
    }
    final columns = [
      (title: 'New', color: AlsColors.orange, icon: Icons.notifications_active_rounded, orders: k.newOrders),
      (title: 'In the oven', color: const Color(0xFFE25B2B), icon: Icons.local_fire_department_rounded, orders: k.cooking),
      (title: 'Ready', color: const Color(0xFF5BAA4A), icon: Icons.check_circle_rounded, orders: k.ready),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in columns)
                Expanded(
                  child: _Column(title: c.title, color: c.color, icon: c.icon, orders: c.orders, k: k),
                ),
            ],
          );
        }
        return DefaultTabController(
          length: columns.length,
          child: Column(
            children: [
              TabBar(
                labelColor: AlsColors.cream,
                unselectedLabelColor: AlsColors.cream.withValues(alpha: 0.6),
                indicatorColor: AlsColors.orange,
                tabs: [for (final c in columns) Tab(text: '${c.title} (${c.orders.length})')],
              ),
              Expanded(
                child: TabBarView(
                  children: [for (final c in columns) _TicketList(orders: c.orders, k: k)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.k});

  final KitchenController k;

  @override
  Widget build(BuildContext context) {
    final session = context.read<StaffSession>();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: const Color(0xFF3B1508),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AlsColors.cream, borderRadius: BorderRadius.circular(10)),
            child: const AlsLogo(height: 34),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: k.stores.length > 1
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: k.storeId,
                      dropdownColor: const Color(0xFF3B1508),
                      iconEnabledColor: AlsColors.cream,
                      style: AlsText.display(20, color: AlsColors.cream),
                      items: [for (final s in k.stores) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (id) => id == null ? null : k.switchStore(id),
                    ),
                  )
                : Text(
                    k.storeName.isEmpty ? 'Kitchen' : k.storeName,
                    overflow: TextOverflow.ellipsis,
                    style: AlsText.display(20, color: AlsColors.cream),
                  ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: session.realtime.connected,
            builder: (context, live, _) => Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: live ? const Color(0xFF7BD389) : AlsColors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(live ? 'Live' : 'Offline', style: AlsText.body(13, color: AlsColors.cream, weight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(clock(DateTime.now()), style: AlsText.display(20, color: AlsColors.orangeLight)),
          IconButton(
            tooltip: k.ringer.muted ? 'Turn the sound on' : 'Mute the chime',
            onPressed: () => k.setMuted(!k.ringer.muted),
            icon: Icon(k.ringer.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: k.ringer.muted ? AlsColors.red : AlsColors.cream),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: k.refresh,
            icon: const Icon(Icons.refresh_rounded, color: AlsColors.cream),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded, color: AlsColors.cream),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out of the kitchen screen?'),
                  content: const Text('New orders won’t ring on this tablet until someone signs in again.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (yes == true) await session.logout();
            },
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.color, required this.icon, required this.orders, required this.k});

  final String title;
  final Color color;
  final IconData icon;
  final List<Order> orders;
  final KitchenController k;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(6, 10, 6, 0),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(title, style: AlsText.display(22, color: AlsColors.cream)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Text('${orders.length}', style: AlsText.body(15, color: Colors.white, weight: FontWeight.w900)),
              ),
            ],
          ),
        ),
        Expanded(child: _TicketList(orders: orders, k: k)),
      ],
    ),
  );
}

class _TicketList extends StatelessWidget {
  const _TicketList({required this.orders, required this.k});

  final List<Order> orders;
  final KitchenController k;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Text('Nothing here', style: AlsText.body(15, color: AlsColors.cream.withValues(alpha: 0.5))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _TicketCard(order: orders[i], k: k),
    );
  }
}

/// What the main button on a ticket does, by status.
({String label, String status})? nextStep(Order o) => switch (o.status) {
  'received' => (label: 'Start', status: 'preparing'),
  'preparing' => (label: 'Done', status: 'ready'),
  'ready' when !o.isDelivery => (label: 'Picked up', status: 'completed'),
  _ => null,
};

Future<void> _advance(BuildContext context, KitchenController k, Order o, String status) async {
  try {
    await k.setStatus(o, status);
  } on ApiException catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.order, required this.k});

  final Order order;
  final KitchenController k;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final isNew = k.unacknowledged.contains(o.id);
    final placed = o.paidAt ?? o.createdAt;
    final minutes = DateTime.now().difference(placed.toLocal()).inMinutes;
    final late = o.estimatedReadyAt != null && DateTime.now().isAfter(o.estimatedReadyAt!) && o.status != 'ready';
    final step = nextStep(o);
    const maxLines = 6;
    return _Pulse(
      active: isNew,
      child: Material(
        color: AlsColors.paper,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            k.acknowledge(o.id);
            showTicket(context, k, o);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${o.number}', style: AlsText.display(30)),
                    const SizedBox(width: 10),
                    _Chip(o.isDelivery ? 'DELIVERY' : 'PICKUP', o.isDelivery ? const Color(0xFF2F5FA8) : AlsColors.basil),
                    if (isNew) ...[const SizedBox(width: 6), const _Chip('NEW', AlsColors.orangeDeep)],
                    const Spacer(),
                    Text(
                      minutes < 1 ? 'now' : '$minutes min',
                      style: AlsText.display(20, color: late ? AlsColors.red : AlsColors.brownSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${o.customerName.split(' ').first}${o.estimatedReadyAt != null ? '  ·  due ${clock(o.estimatedReadyAt!)}' : ''}',
                  style: AlsText.body(14, color: AlsColors.muted, weight: FontWeight.w700),
                ),
                const Divider(height: 18),
                for (final line in o.items.take(maxLines))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 34, child: Text('${line.quantity}×', style: AlsText.display(18, color: AlsColors.orangeDeep))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.name, style: AlsText.body(16, weight: FontWeight.w900)),
                              if (line.summary.isNotEmpty) Text(line.summary, style: AlsText.body(13, color: AlsColors.brownSoft)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (o.items.length > maxLines) Text('+ ${o.items.length - maxLines} more — tap for the full ticket', style: AlsText.body(13, color: AlsColors.muted)),
                if (o.notes?.isNotEmpty ?? false) _Note(o.notes!),
                if (o.isDelivery) ...[const SizedBox(height: 6), _DriverLine(o)],
                if (o.paymentStatus == 'pay_at_pickup') ...[const SizedBox(height: 6), _Chip('COLLECT ${money(o.totalCents)} AT PICKUP', AlsColors.red)],
                if (step != null) ...[
                  const SizedBox(height: 12),
                  AlsButton(
                    label: step.label,
                    height: 50,
                    style: step.status == 'preparing' ? AlsButtonStyle.primary : AlsButtonStyle.dark,
                    onPressed: () => _advance(context, k, o, step.status),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverLine extends StatelessWidget {
  const _DriverLine(this.o);

  final Order o;

  @override
  Widget build(BuildContext context) {
    final d = o.delivery;
    final (text, color) = switch (d) {
      null => ('Finding a driver…', AlsColors.muted),
      _ when d.driverName == null => ('Waiting for a driver', AlsColors.red),
      _ when d.provider == 'own' || d.provider == null => ('Driver: ${d.driverName}', AlsColors.basil),
      _ => ('Courier: ${d.driverName}', const Color(0xFF2F5FA8)),
    };
    return Row(
      children: [
        Icon(Icons.delivery_dining_rounded, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: AlsText.body(14, color: color, weight: FontWeight.w800))),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(10)),
    child: Text('Note: $text', style: AlsText.body(14, weight: FontWeight.w800)),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: AlsText.body(12, color: Colors.white, weight: FontWeight.w900)),
  );
}

/// A glowing orange border that breathes while a new order hasn't been tapped.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: Color.lerp(AlsColors.orange, AlsColors.cheese, _c.value)!, width: 3),
          boxShadow: [BoxShadow(color: AlsColors.orange.withValues(alpha: 0.25 + 0.35 * _c.value), blurRadius: 18 + 10 * _c.value)],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _StartOverlay extends StatelessWidget {
  const _StartOverlay({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: InkWell(
        onTap: onStart,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.volume_up_rounded, color: AlsColors.orange, size: 64),
              const SizedBox(height: 12),
              Text('Tap anywhere to start', style: AlsText.display(32, color: AlsColors.cream)),
              const SizedBox(height: 6),
              Text('This lets the tablet ring when an order comes in.', style: AlsText.body(16, color: AlsColors.cream.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The full ticket: every item and option, notes, delivery details — with Print and the next step.
Future<void> showTicket(BuildContext context, KitchenController k, Order order) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AlsColors.paper,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (ctx) => ChangeNotifierProvider.value(
    value: k,
    child: Consumer<KitchenController>(
      builder: (ctx, k, _) {
        final o = k.orders.firstWhere((x) => x.id == order.id, orElse: () => order);
        final step = nextStep(o);
        final address = o.address;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              children: [
                Row(
                  children: [
                    Text('#${o.number}', style: AlsText.display(40)),
                    const SizedBox(width: 12),
                    _Chip(o.isDelivery ? 'DELIVERY' : 'PICKUP', o.isDelivery ? const Color(0xFF2F5FA8) : AlsColors.basil),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                Text(
                  '${o.customerName}  ·  placed ${clock(o.paidAt ?? o.createdAt)}${o.estimatedReadyAt != null ? '  ·  due ${clock(o.estimatedReadyAt!)}' : ''}',
                  style: AlsText.body(15, color: AlsColors.muted, weight: FontWeight.w700),
                ),
                const Divider(height: 26),
                for (final line in o.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 44, child: Text('${line.quantity}×', style: AlsText.display(22, color: AlsColors.orangeDeep))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.name, style: AlsText.body(19, weight: FontWeight.w900)),
                              if (line.summary.isNotEmpty) Text(line.summary, style: AlsText.body(15, color: AlsColors.brownSoft)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (o.notes?.isNotEmpty ?? false) _Note(o.notes!),
                if (address != null) ...[
                  const SizedBox(height: 12),
                  Text(address.full, style: AlsText.body(15, weight: FontWeight.w800)),
                  if (address.instructions?.isNotEmpty ?? false) Text('Drop-off: ${address.instructions}', style: AlsText.body(14, color: AlsColors.brownSoft)),
                  const SizedBox(height: 6),
                  _DriverLine(o),
                ],
                if (o.paymentStatus == 'pay_at_pickup') ...[const SizedBox(height: 10), _Chip('COLLECT ${money(o.totalCents)} AT PICKUP', AlsColors.red)],
                if (o.paymentStatus == 'pay_on_delivery') ...[const SizedBox(height: 10), _Chip('DRIVER COLLECTS ${money(o.totalCents)} CASH', AlsColors.red)],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: AlsButton(
                        label: 'Print',
                        icon: Icons.print_rounded,
                        style: AlsButtonStyle.outline,
                        onPressed: () => printTicket(o).catchError((Object e) {
                          if (ctx.mounted) showError(ctx, 'Couldn’t print: $e');
                        }),
                      ),
                    ),
                    if (step != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: AlsButton(
                          label: step.label,
                          style: step.status == 'preparing' ? AlsButtonStyle.primary : AlsButtonStyle.dark,
                          onPressed: () async {
                            await _advance(ctx, k, o, step.status);
                            if (ctx.mounted && (step.status == 'ready' || step.status == 'completed')) Navigator.pop(ctx);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 10),
                  Text('Printing opens your browser’s print window — pick the receipt printer there.', style: AlsText.body(12, color: AlsColors.muted)),
                ],
              ],
            ),
          ),
        );
      },
    ),
  ),
);
