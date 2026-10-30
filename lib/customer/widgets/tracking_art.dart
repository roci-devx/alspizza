import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/art/pizza_art.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';

/// Animated scene for each order status (ticket → oven → box/scooter → confetti).
class OrderStatusArt extends StatelessWidget {
  const OrderStatusArt({super.key, required this.status, required this.delivery});

  final String status;
  final bool delivery;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 500),
    switchInCurve: Curves.easeOutBack,
    transitionBuilder: (child, a) => ScaleTransition(
      scale: Tween(begin: 0.6, end: 1.0).animate(a),
      child: FadeTransition(opacity: a, child: child),
    ),
    child: SizedBox.square(
      key: ValueKey(status),
      dimension: 190,
      child: switch (status) {
        'preparing' => const _Oven(),
        'ready' => const _SteamingBox(),
        'out_for_delivery' => Floaty(
          amplitude: 4,
          period: const Duration(milliseconds: 900),
          child: _Badge(icon: Icons.delivery_dining_rounded, colors: const [Color(0xFF8A3B1F), AlsColors.brown]),
        ),
        'completed' => const _Celebrate(),
        'cancelled' => _Badge(icon: Icons.close_rounded, colors: const [AlsColors.muted, AlsColors.brownSoft]),
        _ => Floaty(
          child: _Badge(icon: Icons.receipt_long_rounded, colors: const [AlsColors.orangeLight, AlsColors.orange]),
        ),
      },
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.colors});

  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x445A210F), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Icon(icon, size: 76, color: Colors.white),
    ),
  );
}

class _Oven extends StatefulWidget {
  const _Oven();

  @override
  State<_Oven> createState() => _OvenState();
}

class _OvenState extends State<_Oven> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(
      painter: _OvenPainter(_c.value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(46, 74, 46, 34),
        child: Transform.rotate(
          angle: _c.value * 0.2,
          child: const PizzaArt(toppings: ['pepperoni', 'basil'], shadow: false, seed: 5),
        ),
      ),
    ),
  );
}

class _OvenPainter extends CustomPainter {
  _OvenPainter(this.glow);

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, w * 0.12, w * 0.84, w * 0.8), Radius.circular(w * 0.12));
    canvas.drawRRect(
      body.shift(Offset(0, w * 0.03)),
      Paint()
        ..color = const Color(0x335A210F)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.04),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF8A3B1F), Color(0xFF5A210F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(body.outerRect),
    );
    final mouth = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.18, w * 0.34, w * 0.64, w * 0.48),
      topLeft: Radius.circular(w * 0.32),
      topRight: Radius.circular(w * 0.32),
      bottomLeft: Radius.circular(w * 0.04),
      bottomRight: Radius.circular(w * 0.04),
    );
    canvas.drawRRect(
      mouth,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.6),
          colors: [Color.lerp(const Color(0xFFFFB347), const Color(0xFFFFE08A), glow)!, const Color(0xFFE0592A), const Color(0xFF7A1F10)],
          stops: const [0.2, 0.65, 1],
        ).createShader(mouth.outerRect),
    );
    // Flickering flames along the back of the oven.
    final flame = Paint()..color = const Color(0xFFFFD36A).withValues(alpha: 0.5 + glow * 0.4);
    for (var i = 0; i < 5; i++) {
      final x = w * (0.28 + i * 0.11);
      final h = w * (0.06 + 0.04 * math.sin(glow * math.pi * 2 + i));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, w * 0.44), width: w * 0.06, height: h), flame);
    }
    final brick = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 2;
    for (var r = 0; r < 2; r++) {
      canvas.drawLine(Offset(w * 0.12, w * (0.2 + r * 0.06)), Offset(w * 0.88, w * (0.2 + r * 0.06)), brick);
    }
  }

  @override
  bool shouldRepaint(_OvenPainter old) => old.glow != glow;
}

class _SteamingBox extends StatefulWidget {
  const _SteamingBox();

  @override
  State<_SteamingBox> createState() => _SteamingBoxState();
}

class _SteamingBoxState extends State<_SteamingBox> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(painter: _BoxPainter(_c.value)),
  );
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      final x = w * (0.36 + i * 0.14);
      final path = Path()..moveTo(x, w * 0.44);
      for (var k = 1; k <= 6; k++) {
        path.lineTo(x + math.sin(k * 1.2 + p * 6) * w * 0.025, w * (0.44 - k * 0.045));
      }
      canvas.save();
      canvas.translate(0, -p * w * 0.12);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round
          ..color = AlsColors.muted.withValues(alpha: (1 - p) * 0.55),
      );
      canvas.restore();
    }
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.12, w * 0.5, w * 0.76, w * 0.34), Radius.circular(w * 0.05));
    canvas.drawRRect(
      box.shift(Offset(0, w * 0.03)),
      Paint()
        ..color = const Color(0x335A210F)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03),
    );
    canvas.drawRRect(box, Paint()..color = const Color(0xFFD9A86C));
    canvas.drawRRect(box.deflate(w * 0.03), Paint()..color = const Color(0xFFC9955A));
    final tp = TextPainter(
      text: TextSpan(
        text: "Al's",
        style: TextStyle(fontSize: w * 0.13, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: AlsColors.brown),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, w * 0.67 - tp.height / 2));
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.t != t;
}

class _Celebrate extends StatefulWidget {
  const _Celebrate();

  @override
  State<_Celebrate> createState() => _CelebrateState();
}

class _CelebrateState extends State<_Celebrate> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(
      painter: ConfettiPainter(_c.value),
      child: Center(
        child: Transform.scale(
          scale: Curves.elasticOut.transform(_c.value.clamp(0, 1)),
          child: const _Badge(icon: Icons.check_rounded, colors: [Color(0xFF5E9C3A), AlsColors.basil]),
        ),
      ),
    ),
  );
}

/// Pepperoni / basil / cheese confetti burst.
class ConfettiPainter extends CustomPainter {
  ConfettiPainter(this.t);

  final double t;
  static final _pieces = List.generate(28, (i) {
    final r = math.Random(i * 7 + 3);
    return (angle: r.nextDouble() * math.pi * 2, speed: 0.5 + r.nextDouble() * 0.6, kind: i % 3, spin: r.nextDouble() * 6);
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final colors = [AlsColors.red, AlsColors.basil, AlsColors.cheese];
    for (final p in _pieces) {
      final d = Curves.easeOutCubic.transform(t) * size.width * 0.55 * p.speed;
      final pos = c + Offset(math.cos(p.angle), math.sin(p.angle)) * d + Offset(0, t * t * size.width * 0.25);
      final paint = Paint()..color = colors[p.kind].withValues(alpha: 1 - t);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      if (p.kind == 0) {
        canvas.drawCircle(Offset.zero, 6, paint);
      } else if (p.kind == 1) {
        canvas.drawOval(const Rect.fromLTWH(-7, -3, 14, 6), paint);
      } else {
        canvas.drawRect(const Rect.fromLTWH(-4, -4, 8, 8), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.t != t;
}

/// Stylized live map: real store/home/driver coordinates projected onto a
/// drawn street grid (no map SDK or API key needed on any platform).
class LiveMap extends StatefulWidget {
  const LiveMap({super.key, required this.store, required this.home, this.driver, required this.status});

  final Offset store; // (lat, lng)
  final Offset home;
  final Offset? driver;
  final String status;

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: TweenAnimationBuilder<Offset?>(
      tween: _OffsetTween(end: widget.driver),
      duration: const Duration(milliseconds: 1900),
      curve: Curves.linear,
      builder: (context, driver, _) => AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _MapPainter(
            store: widget.store,
            home: widget.home,
            driver: driver,
            pulse: _pulse.value,
            enRoute: widget.status == 'enroute_to_dropoff' || widget.status == 'picked_up' || widget.status == 'arrived_at_dropoff',
          ),
        ),
      ),
    ),
  );
}

class _OffsetTween extends Tween<Offset?> {
  _OffsetTween({super.end}) : super(begin: end);

  @override
  Offset? lerp(double t) {
    if (begin == null || end == null) return end;
    return Offset.lerp(begin, end, t);
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.store, required this.home, required this.driver, required this.pulse, required this.enRoute});

  final Offset store;
  final Offset home;
  final Offset? driver;
  final double pulse;
  final bool enRoute;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF3EADA));
    // Decorative city: park, river and a street grid.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.62, size.height * 0.08, size.width * 0.26, size.height * 0.3), const Radius.circular(18)),
      Paint()..color = const Color(0xFFD7E7C4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-10, size.height * 0.82)
        ..quadraticBezierTo(size.width * 0.35, size.height * 0.68, size.width + 10, size.height * 0.92)
        ..lineTo(size.width + 10, size.height + 10)
        ..lineTo(-10, size.height + 10)
        ..close(),
      Paint()..color = const Color(0xFFD2E6EF),
    );
    final street = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 6;
    final avenue = Paint()
      ..color = Colors.white
      ..strokeWidth = 11;
    for (var x = 18.0; x < size.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x - 12, size.height), ((x / 46).round() % 3 == 0) ? avenue : street);
    }
    for (var y = 14.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 8), ((y / 40).round() % 3 == 1) ? avenue : street);
    }

    // Project lat/lng into the box (equirectangular, padded).
    final pts = [store, home, ?driver];
    var minLat = pts.map((p) => p.dx).reduce(math.min);
    var maxLat = pts.map((p) => p.dx).reduce(math.max);
    var minLng = pts.map((p) => p.dy).reduce(math.min);
    var maxLng = pts.map((p) => p.dy).reduce(math.max);
    final k = math.cos(store.dx * math.pi / 180);
    var spanLat = math.max(maxLat - minLat, 0.004);
    var spanLng = math.max((maxLng - minLng) * k, 0.004);
    final aspect = size.width / size.height;
    if (spanLng / spanLat < aspect) {
      spanLng = spanLat * aspect;
    } else {
      spanLat = spanLng / aspect;
    }
    final cLat = (minLat + maxLat) / 2;
    final cLng = (minLng + maxLng) / 2;
    Offset project(Offset p) =>
        Offset(size.width / 2 + ((p.dy - cLng) * k / spanLng) * size.width * 0.72, size.height / 2 - ((p.dx - cLat) / spanLat) * size.height * 0.72);
    final s = project(store);
    final h = project(home);
    final control = Offset((s.dx + h.dx) / 2 + (h.dy - s.dy) * 0.25, (s.dy + h.dy) / 2 - (h.dx - s.dx) * 0.25);
    final route = Path()
      ..moveTo(s.dx, s.dy)
      ..quadraticBezierTo(control.dx, control.dy, h.dx, h.dy);
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = AlsColors.orange.withValues(alpha: 0.35),
    );

    // Solid "already driven" portion when the driver is between store and home.
    final d = driver == null ? null : project(driver!);
    if (d != null && enRoute) {
      final metric = route.computeMetrics().first;
      var best = 0.0;
      var bestDist = double.infinity;
      for (var i = 0; i <= 40; i++) {
        final pos = metric.getTangentForOffset(metric.length * i / 40)!.position;
        final dist = (pos - d).distanceSquared;
        if (dist < bestDist) {
          bestDist = dist;
          best = i / 40;
        }
      }
      canvas.drawPath(
        metric.extractPath(0, metric.length * best),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = AlsColors.brown,
      );
    }

    _pin(canvas, s, AlsColors.brown, Icons.storefront_rounded);
    canvas.drawCircle(h, 16 + pulse * 22, Paint()..color = AlsColors.orange.withValues(alpha: (1 - pulse) * 0.35));
    _pin(canvas, h, AlsColors.orangeDeep, Icons.home_rounded);
    if (d != null) {
      canvas.drawCircle(d, 22 + pulse * 10, Paint()..color = AlsColors.brown.withValues(alpha: (1 - pulse) * 0.25));
      canvas.drawCircle(d, 21, Paint()..color = Colors.white);
      canvas.drawCircle(
        d,
        21,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AlsColors.orange,
      );
      _icon(canvas, d, Icons.delivery_dining_rounded, AlsColors.brown, 24);
    }
  }

  void _pin(Canvas canvas, Offset at, Color color, IconData icon) {
    canvas.drawCircle(
      at.translate(0, 3),
      18,
      Paint()
        ..color = const Color(0x335A210F)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(at, 18, Paint()..color = color);
    canvas.drawCircle(
      at,
      18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    _icon(canvas, at, icon, Colors.white, 18);
  }

  void _icon(Canvas canvas, Offset at, IconData icon, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.driver != driver || old.pulse != pulse || old.store != store || old.home != home || old.enRoute != enRoute;
}
