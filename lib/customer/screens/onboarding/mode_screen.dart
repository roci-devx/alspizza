import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/ui.dart';
import '../../state/ordering.dart';
import '../../state/session.dart';

/// Pickup or delivery? Skippable — checkout asks again.
class ModeScreen extends StatelessWidget {
  const ModeScreen({super.key});

  Future<void> _finish(BuildContext context, Fulfillment? f) async {
    await context.read<OrderingStore>().setFulfillment(f);
    if (!context.mounted) return;
    await context.read<SessionStore>().completeOnboarding();
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final ordering = context.watch<OrderingStore>();
    final store = ordering.store;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => context.go('/location'),
                      icon: const Icon(Icons.arrow_back_rounded, color: AlsColors.brown),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Reveal(child: Text('How do you want it?', style: AlsText.display(32))),
                  const SizedBox(height: 6),
                  Reveal(
                    delay: const Duration(milliseconds: 80),
                    child: Text(
                      store == null ? 'You can always change this at checkout.' : 'From ${store.shortName} · you can switch at checkout.',
                      style: AlsText.body(15, color: AlsColors.muted),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Reveal(
                    delay: const Duration(milliseconds: 160),
                    child: _ModeCard(
                      icon: Icons.shopping_bag_rounded,
                      title: 'Pickup',
                      subtitle: store?.pickupEtaMinutes != null ? 'Ready in about ${store!.pickupEtaMinutes} min' : 'Skip the wait, grab it hot',
                      gradient: const [Color(0xFFF6B54E), Color(0xFFE8962A)],
                      onTap: () => _finish(context, Fulfillment.pickup),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Reveal(
                    delay: const Duration(milliseconds: 260),
                    child: _ModeCard(
                      icon: Icons.delivery_dining_rounded,
                      title: 'Delivery',
                      subtitle: ordering.address != null ? 'To ${ordering.address!.line1}' : 'Hot to your door',
                      gradient: const [Color(0xFF8A3B1F), Color(0xFF5A210F)],
                      light: true,
                      onTap: () => _finish(context, Fulfillment.delivery),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _finish(context, null),
                    child: Text(
                      'I’ll decide later',
                      style: AlsText.body(15, color: AlsColors.brownSoft, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.subtitle, required this.gradient, required this.onTap, this.light = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final bool light;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = light ? AlsColors.cream : AlsColors.brown;
    return TapScale(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x335A210F), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: AlsText.display(30, color: fg)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AlsText.body(15, color: fg.withValues(alpha: 0.85))),
                ],
              ),
            ),
            Floaty(
              amplitude: 5,
              rotate: 0.12,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: light ? 0.12 : 0.35),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 52, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
