import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/art/pizza_art.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/ui.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    Widget decor(double s, List<String> toppings, int seed, {double rotate = 0.25}) => Floaty(
      amplitude: 8,
      rotate: rotate,
      period: Duration(milliseconds: 2400 + seed * 300),
      child: SizedBox.square(
        dimension: s,
        child: Spin(
          period: Duration(seconds: 30 + seed * 6),
          child: PizzaArt(toppings: toppings, seed: seed),
        ),
      ),
    );
    return Scaffold(
      body: Stack(
        children: [
          Positioned(top: -50, left: -60, child: decor(190, const ['pepperoni', 'basil'], 3)),
          Positioned(top: size.height * 0.16, right: -70, child: decor(150, const ['mushroom', 'green-pepper', 'olive'], 5)),
          Positioned(bottom: size.height * 0.2, left: -80, child: decor(170, const ['pineapple', 'ham'], 7)),
          Positioned(bottom: -40, right: -40, child: decor(130, const ['sausage', 'onion'], 2)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 1100),
                        curve: Curves.elasticOut,
                        builder: (context, t, child) => Transform.scale(
                          scale: 0.4 + 0.6 * t,
                          child: Opacity(opacity: t.clamp(0, 1), child: child),
                        ),
                        child: const AlsLogo(height: 210),
                      ),
                      const SizedBox(height: 20),
                      Reveal(
                        delay: const Duration(milliseconds: 350),
                        child: Text('Hot, fresh &\nmade your way.', textAlign: TextAlign.center, style: AlsText.display(34)),
                      ),
                      const SizedBox(height: 10),
                      Reveal(
                        delay: const Duration(milliseconds: 500),
                        child: Text(
                          'Order Al’s in a few taps — pickup or delivery, your call.',
                          textAlign: TextAlign.center,
                          style: AlsText.body(16, color: AlsColors.muted),
                        ),
                      ),
                      const Spacer(flex: 4),
                      Reveal(
                        delay: const Duration(milliseconds: 700),
                        child: AlsButton(label: 'Let’s get started', icon: Icons.local_pizza_rounded, onPressed: () => context.go('/auth')),
                      ),
                      const SizedBox(height: 8),
                      Reveal(
                        delay: const Duration(milliseconds: 820),
                        child: TextButton(
                          onPressed: () => context.go('/auth?mode=signin'),
                          child: Text(
                            'I already have an account',
                            style: AlsText.body(15, color: AlsColors.brown, weight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
