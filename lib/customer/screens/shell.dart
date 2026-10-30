import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/cart.dart';

/// Tab scaffold: animated bottom bar + a floating "View order" bar that springs
/// up whenever the bag has something in it (McDonald's-app style).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_rounded, 'Home'),
    (Icons.local_pizza_rounded, 'Menu'),
    (Icons.local_offer_rounded, 'Deals'),
    (Icons.receipt_long_rounded, 'Orders'),
    (Icons.person_rounded, 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          Positioned(left: 16, right: 16, bottom: 82 + bottomInset, child: const CartBar()),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomInset),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: [BoxShadow(color: Color(0x1F5A210F), blurRadius: 24, offset: Offset(0, -6))],
        ),
        child: Row(
          children: [
            for (final (i, (icon, label)) in _tabs.indexed)
              Expanded(
                child: TapScale(
                  onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                  child: _TabItem(icon: icon, label: label, selected: shell.currentIndex == i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.icon, required this.label, required this.selected});

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 10, vertical: 5),
          decoration: BoxDecoration(color: selected ? AlsColors.orange.withValues(alpha: 0.22) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
          child: AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Icon(icon, size: 24, color: selected ? AlsColors.brown : AlsColors.muted),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AlsText.body(11, color: selected ? AlsColors.brown : AlsColors.muted, weight: selected ? FontWeight.w900 : FontWeight.w700),
        ),
      ],
    ),
  );
}

class CartBar extends StatefulWidget {
  const CartBar({super.key});

  @override
  State<CartBar> createState() => _CartBarState();
}

class _CartBarState extends State<CartBar> with SingleTickerProviderStateMixin {
  late final _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  int _lastBump = 0;

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    if (cart.bump != _lastBump) {
      _lastBump = cart.bump;
      _bounce.forward(from: 0);
    }
    final visible = !cart.isEmpty;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 2),
      duration: const Duration(milliseconds: 450),
      curve: visible ? Curves.easeOutBack : Curves.easeIn,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: AnimatedBuilder(
          animation: _bounce,
          builder: (context, child) {
            final t = _bounce.value;
            final s = 1 + 0.06 * (t < 0.3 ? t / 0.3 : (1 - t) / 0.7) * (1 - t);
            return Transform.scale(scale: s, child: child);
          },
          child: TapScale(
            onTap: visible ? () => context.push('/cart') : null,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AlsColors.brown,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [BoxShadow(color: Color(0x555A210F), blurRadius: 22, offset: Offset(0, 10))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: AlsColors.orange, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${cart.count}', style: AlsText.display(18, color: AlsColors.brown)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'View order',
                    style: AlsText.display(18, color: AlsColors.cream, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    money(cart.priced?.subtotalCents ?? cart.estimateCents),
                    style: AlsText.display(18, color: AlsColors.orangeLight, weight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AlsColors.orangeLight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
