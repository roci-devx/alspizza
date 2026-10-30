import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/art/food_art.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../logic.dart';
import '../state/cart.dart';
import '../state/catalog.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<OrdersStore>().refresh());
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OrdersStore>();
    final active = store.orders.where((o) => o.isActive).toList();
    final past = store.orders.where((o) => !o.isActive).toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AlsColors.orange,
          onRefresh: store.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 180),
            children: [
              Text('Orders', style: AlsText.display(30)),
              const SizedBox(height: 14),
              if (store.orders.isEmpty && !store.loading)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 64, color: AlsColors.line),
                      const SizedBox(height: 10),
                      Text('No orders yet', style: AlsText.display(22)),
                      const SizedBox(height: 4),
                      Text('Your first slice is a few taps away.', style: AlsText.body(14, color: AlsColors.muted)),
                      const SizedBox(height: 16),
                      AlsButton(label: 'Start an order', expand: false, onPressed: () => context.go('/menu')),
                    ],
                  ),
                ),
              if (active.isNotEmpty) ...[
                Text('In progress', style: AlsText.label(12)),
                const SizedBox(height: 8),
                for (final (i, o) in active.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Reveal(
                      delay: Reveal.stagger(i),
                      child: _OrderCard(order: o),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              if (past.isNotEmpty) ...[
                Text('Past orders', style: AlsText.label(12)),
                const SizedBox(height: 8),
                for (final (i, o) in past.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Reveal(
                      delay: Reveal.stagger(i),
                      child: _OrderCard(order: o),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final (title, _) = statusCopy[order.status] ?? (order.status, '');
    return CardBox(
      onTap: () => context.push('/order/${order.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${order.number}', style: AlsText.display(18)),
              const SizedBox(width: 8),
              Tag(title.toUpperCase(), color: order.isActive ? AlsColors.orangeDeep : (order.status == 'cancelled' ? AlsColors.muted : AlsColors.basil)),
              const Spacer(),
              Text(money(order.totalCents), style: AlsText.display(18, color: AlsColors.orangeDeep)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 92,
                height: 48,
                child: Stack(
                  children: [
                    for (final (i, l) in order.items.take(3).indexed)
                      Positioned(
                        left: i * 22.0,
                        width: 48,
                        height: 48,
                        child: FoodArt.line(l.art, l.config, seed: i),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.items.map((l) => '${l.quantity}× ${l.name}').join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AlsText.body(13, weight: FontWeight.w800),
                    ),
                    Text(
                      '${order.isDelivery ? 'Delivery' : 'Pickup'} · ${dayLabel(order.createdAt)} ${clock(order.createdAt)}',
                      style: AlsText.body(12, color: AlsColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (order.isDone) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AlsButton(
                label: 'Reorder',
                icon: Icons.replay_rounded,
                height: 42,
                expand: false,
                style: AlsButtonStyle.outline,
                onPressed: () {
                  final menu = context.read<CatalogStore>().menu;
                  if (menu == null) return;
                  final cart = context.read<CartStore>();
                  for (final l in linesFromOrder(order, menu)) {
                    cart.add(l);
                  }
                  showToast(context, 'Added to your bag');
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
