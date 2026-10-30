import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A pizza drawn from its actual configuration: crust style, sauce, cheese level
/// and every topping. Topping placement is seeded per topping, so adding one
/// never shuffles the others. [toppingProgress] (0–1 per topping id) drives the
/// pop-in animation in the builder.
class PizzaArt extends StatelessWidget {
  const PizzaArt({
    super.key,
    this.toppings = const [],
    this.sauce = 'marinara',
    this.cheese = 'regular',
    this.crust = 'hand-tossed',
    this.density = 1,
    this.seed = 1,
    this.toppingProgress = const {},
    this.shadow = true,
  });

  final List<String> toppings;
  final String sauce;
  final String cheese;
  final String crust;
  final double density;
  final int seed;
  final Map<String, double> toppingProgress;
  final bool shadow;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: RepaintBoundary(
      child: CustomPaint(
        painter: PizzaPainter(
          toppings: toppings,
          sauce: sauce,
          cheese: cheese,
          crust: crust,
          density: density,
          seed: seed,
          toppingProgress: toppingProgress,
          shadow: shadow,
        ),
      ),
    ),
  );
}

int _hash(String s) => s.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x7fffffff);

/// Owner-added toppings borrow a built-in drawing (topping id → art id). Filled from the menu's pizza options.
final toppingArtAliases = <String, String>{};

void registerToppingArt(Iterable<({String id, String? art})> toppings) {
  for (final t in toppings) {
    if (t.art != null && t.art!.isNotEmpty) toppingArtAliases[t.id] = t.art!;
  }
}

/// Built-in topping drawings, offered as "looks like" choices when adding a topping.
const toppingArtChoices = [
  'pepperoni',
  'sausage',
  'beef',
  'ham',
  'bacon',
  'chicken',
  'meatball',
  'mushroom',
  'green-pepper',
  'onion',
  'olive',
  'tomato',
  'jalapeno',
  'banana-pepper',
  'pineapple',
  'spinach',
  'basil',
];

const _rim = {'pan': 0.15, 'hand-tossed': 0.12, 'thin': 0.07, 'stuffed': 0.17, 'ny': 0.1, 'gluten-free': 0.09};

const _crustColors = {
  'pan': [Color(0xFFD9893C), Color(0xFFF0B460), Color(0xFFA9581F)],
  'thin': [Color(0xFFE6B06C), Color(0xFFF5D198), Color(0xFFD49A55)],
  'stuffed': [Color(0xFFE09A4A), Color(0xFFF6C77E), Color(0xFFBF6F2C)],
  'gluten-free': [Color(0xFFE3B072), Color(0xFFF1CF94), Color(0xFFC8904F)],
};
const _defaultCrust = [Color(0xFFE09A4A), Color(0xFFF3C27A), Color(0xFFC0702E)];

const _sauceColors = {
  'marinara': Color(0xFFC8371E),
  'garlic-parm': Color(0xFFF2E2BC),
  'bbq': Color(0xFF7E2F14),
  'buffalo': Color(0xFFE0592A),
  'none': Color(0xFFF1D29A),
};

const _cheeseCoverage = {'light': 0.84, 'regular': 0.93, 'extra': 0.985};

const _baseCount = {
  'pepperoni': 9,
  'sausage': 13,
  'beef': 16,
  'ham': 10,
  'bacon': 7,
  'chicken': 9,
  'meatball': 7,
  'mushroom': 9,
  'green-pepper': 9,
  'onion': 9,
  'olive': 12,
  'tomato': 6,
  'jalapeno': 10,
  'banana-pepper': 10,
  'pineapple': 10,
  'spinach': 8,
  'basil': 6,
};

class PizzaPainter extends CustomPainter {
  PizzaPainter({
    required this.toppings,
    required this.sauce,
    required this.cheese,
    required this.crust,
    required this.density,
    required this.seed,
    required this.toppingProgress,
    required this.shadow,
  });

  final List<String> toppings;
  final String sauce;
  final String cheese;
  final String crust;
  final double density;
  final int seed;
  final Map<String, double> toppingProgress;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2 * (shadow ? 0.9 : 0.98);
    final rim = _rim[crust] ?? 0.12;

    if (shadow) {
      canvas.drawCircle(
        c.translate(0, r * 0.07),
        r * 0.98,
        Paint()
          ..color = const Color(0x405A210F)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
      );
    }

    // Crust: puffy rim lighter on top, darker at the baked outer edge.
    final crustColors = _crustColors[crust] ?? _defaultCrust;
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = RadialGradient(colors: crustColors, stops: [1 - rim, 1 - rim * 0.5, 1]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * (1 - rim * 0.5)),
      math.pi * 1.05,
      math.pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * rim * 0.28
        ..color = Colors.white.withValues(alpha: 0.28),
    );
    final rnd = math.Random(seed);
    final char = Paint()..color = const Color(0x55A65424);
    for (var i = 0; i < 30; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = r * (1 - rim * (0.2 + rnd.nextDouble() * 0.6));
      canvas.drawOval(Rect.fromCenter(center: c + Offset(math.cos(a), math.sin(a)) * d, width: r * 0.035, height: r * 0.022), char);
    }
    if (crust == 'stuffed') {
      canvas.drawCircle(
        c,
        r * (1 - rim * 0.55),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.02
          ..color = const Color(0x88FFF1C2),
      );
    }
    if (crust == 'pan') {
      canvas.drawCircle(
        c,
        r * 0.985,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.025
          ..color = const Color(0x55A0521E),
      );
    }

    // Sauce.
    final inner = r * (1 - rim);
    final sauceColor = _sauceColors[sauce] ?? _sauceColors['marinara']!;
    canvas.drawCircle(
      c,
      inner,
      Paint()
        ..shader = RadialGradient(colors: [Color.lerp(sauceColor, Colors.white, 0.12)!, sauceColor]).createShader(Rect.fromCircle(center: c, radius: inner)),
    );

    // Cheese: a wobbly melted blob that lets sauce peek out at the edge.
    final coverage = _cheeseCoverage[cheese];
    if (coverage != null) {
      final rc = inner * coverage;
      final path = Path();
      const n = 56;
      final pts = <Offset>[];
      for (var i = 0; i < n; i++) {
        final a = i / n * math.pi * 2;
        final rr = rc * (1 + 0.03 * math.sin(a * 7 + seed) + 0.018 * math.sin(a * 13 + seed * 2));
        pts.add(c + Offset(math.cos(a), math.sin(a)) * rr);
      }
      path.moveTo((pts.last.dx + pts.first.dx) / 2, (pts.last.dy + pts.first.dy) / 2);
      for (var i = 0; i < n; i++) {
        final p = pts[i];
        final q = pts[(i + 1) % n];
        path.quadraticBezierTo(p.dx, p.dy, (p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFE6A0), Color(0xFFFBD064), Color(0xFFF2B640)],
            stops: [0, 0.7, 1],
          ).createShader(Rect.fromCircle(center: c, radius: rc)),
      );
      final brown = Paint()..color = const Color(0x50D8892E);
      final dark = Paint()..color = const Color(0x38B5651F);
      final light = Paint()..color = const Color(0x99FFF2C6);
      final spots = cheese == 'extra' ? 26 : 15;
      for (var i = 0; i < spots; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final d = rc * 0.92 * math.sqrt(rnd.nextDouble());
        final w = r * (0.03 + rnd.nextDouble() * 0.05);
        canvas.drawOval(Rect.fromCenter(center: c + Offset(math.cos(a), math.sin(a)) * d, width: w, height: w * 0.7), i % 4 == 0 ? dark : brown);
      }
      for (var i = 0; i < 9; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final d = rc * 0.85 * math.sqrt(rnd.nextDouble());
        final w = r * (0.03 + rnd.nextDouble() * 0.04);
        canvas.drawOval(Rect.fromCenter(center: c + Offset(math.cos(a), math.sin(a)) * d, width: w, height: w * 0.6), light);
      }
    }

    // Cut lines: tavern squares on thin crust, wedges otherwise.
    final cut = Paint()
      ..color = const Color(0x2E7A4416)
      ..strokeWidth = r * 0.009;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
    if (crust == 'thin') {
      for (var k = -2; k <= 2; k++) {
        final o = k * inner * 0.44;
        canvas.drawLine(c + Offset(o, -inner), c + Offset(o, inner), cut);
        canvas.drawLine(c + Offset(-inner, o), c + Offset(inner, o), cut);
      }
    } else {
      for (var k = 0; k < 4; k++) {
        final a = k * math.pi / 4 + (seed % 10) * 0.05;
        final d = Offset(math.cos(a), math.sin(a)) * inner;
        canvas.drawLine(c - d, c + d, cut);
      }
    }
    canvas.restore();

    // Toppings.
    final area = inner * 0.8;
    final crowd = toppings.length <= 2 ? 1.0 : (2.2 / toppings.length).clamp(0.45, 1.0);
    final unit = r * 0.085;
    for (final id in toppings) {
      final progress = toppingProgress[id] ?? 1.0;
      if (progress <= 0) continue;
      final art = toppingArtAliases[id] ?? id;
      final count = ((_baseCount[art] ?? 8) * density * crowd).round().clamp(2, 24);
      final tr = math.Random(seed * 1000 + _hash(id));
      final placed = <Offset>[];
      final minDist = area * 1.5 / math.sqrt(count + 1);
      for (var k = 0; k < count; k++) {
        var p = Offset.zero;
        for (var attempt = 0; attempt < 24; attempt++) {
          final a = tr.nextDouble() * math.pi * 2;
          final d = area * math.sqrt(tr.nextDouble());
          p = Offset(math.cos(a), math.sin(a)) * d;
          if (placed.every((q) => (q - p).distance > minDist)) break;
        }
        placed.add(p);
        final rot = tr.nextDouble() * math.pi * 2;
        final jitter = 0.85 + tr.nextDouble() * 0.3;
        // Stagger pieces so a new topping "rains" onto the pizza.
        final local = ((progress - k / count * 0.4) / 0.6).clamp(0.0, 1.0);
        if (local <= 0) continue;
        final scale = Curves.easeOutBack.transform(local) * jitter;
        canvas.save();
        canvas.translate(c.dx + p.dx, c.dy + p.dy - unit * 2.5 * (1 - local));
        canvas.rotate(rot);
        canvas.scale(scale);
        drawTopping(canvas, art, unit);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(PizzaPainter old) =>
      old.sauce != sauce ||
      old.cheese != cheese ||
      old.crust != crust ||
      old.density != density ||
      old.seed != seed ||
      old.shadow != shadow ||
      !_listEq(old.toppings, toppings) ||
      !_mapEq(old.toppingProgress, toppingProgress);
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, double> a, Map<String, double> b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

Paint _fill(int color) => Paint()..color = Color(color);
Paint _stroke(int color, double width) => Paint()
  ..color = Color(color)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round;

Path _leaf(double length, double width) => Path()
  ..moveTo(-length / 2, 0)
  ..quadraticBezierTo(0, -width, length / 2, 0)
  ..quadraticBezierTo(0, width, -length / 2, 0)
  ..close();

/// Draws one topping piece centered at the origin. [u] ≈ one pepperoni radius.
void drawTopping(Canvas c, String id, double u) {
  switch (id) {
    case 'pepperoni':
      c.drawCircle(
        Offset.zero,
        u,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFC9361F), Color(0xFFA4231A), Color(0xFF7E160F)],
            stops: [0, 0.75, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: u)),
      );
      final speck = _fill(0xCCE77B62);
      c.drawCircle(Offset(-u * 0.35, -u * 0.2), u * 0.13, speck);
      c.drawCircle(Offset(u * 0.3, u * 0.25), u * 0.11, speck);
      c.drawCircle(Offset(u * 0.12, -u * 0.45), u * 0.08, speck);
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: u * 0.8), math.pi * 1.1, math.pi * 0.55, false, _stroke(0x40FFFFFF, u * 0.12));
    case 'sausage':
      final p = _fill(0xFF8A4521);
      c.drawCircle(Offset(-u * 0.3, 0), u * 0.42, p);
      c.drawCircle(Offset(u * 0.25, -u * 0.18), u * 0.36, p);
      c.drawCircle(Offset(u * 0.1, u * 0.3), u * 0.32, p);
      final d = _fill(0xFF6A3016);
      c.drawCircle(Offset(-u * 0.2, -u * 0.1), u * 0.1, d);
      c.drawCircle(Offset(u * 0.28, u * 0.05), u * 0.08, d);
    case 'beef':
      final p = _fill(0xFF5E2B15);
      for (final o in const [Offset(-0.3, -0.1), Offset(0.2, -0.25), Offset(0.05, 0.25), Offset(0.35, 0.15)]) {
        c.drawCircle(o * u, u * 0.2, p);
      }
    case 'ham':
      final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * 1.25, height: u * 1.05), Radius.circular(u * 0.28));
      c.drawRRect(rect, _fill(0xFFF2A7A1));
      c.drawRRect(rect.deflate(u * 0.15), _fill(0xFFF8C2BD));
      c.drawRRect(rect, _stroke(0xFFDD8A84, u * 0.08));
    case 'bacon':
      final w = u * 1.9;
      final h = u * 0.42;
      final path = Path()..moveTo(-w / 2, -h / 2);
      for (var i = 0; i <= 8; i++) {
        path.lineTo(-w / 2 + w * i / 8, -h / 2 + math.sin(i * 1.4) * h * 0.35);
      }
      for (var i = 8; i >= 0; i--) {
        path.lineTo(-w / 2 + w * i / 8, h / 2 + math.sin(i * 1.4) * h * 0.35);
      }
      path.close();
      c.drawPath(path, _fill(0xFFB8402F));
      final fat = Path()..moveTo(-w / 2, 0);
      for (var i = 0; i <= 8; i++) {
        fat.lineTo(-w / 2 + w * i / 8, math.sin(i * 1.4) * h * 0.35);
      }
      c.drawPath(fat, _stroke(0xFFF3C2AE, h * 0.28));
    case 'chicken':
      final rect = RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset.zero, width: u * 1.15, height: u * 0.82),
        topLeft: Radius.circular(u * 0.35),
        topRight: Radius.circular(u * 0.2),
        bottomLeft: Radius.circular(u * 0.22),
        bottomRight: Radius.circular(u * 0.4),
      );
      c.drawRRect(rect, _fill(0xFFF0D9AE));
      final grill = _stroke(0xFFB58652, u * 0.1);
      c.drawLine(Offset(-u * 0.35, -u * 0.25), Offset(-u * 0.05, u * 0.3), grill);
      c.drawLine(Offset(u * 0.05, -u * 0.3), Offset(u * 0.35, u * 0.22), grill);
    case 'meatball':
      final r = u * 0.78;
      c.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFF9A4E2A), Color(0xFF6E3218)],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
      );
      c.drawCircle(Offset(-r * 0.3, -r * 0.35), r * 0.18, _fill(0x40FFFFFF));
    case 'mushroom':
      final cap = Path()
        ..moveTo(-u * 0.75, u * 0.05)
        ..quadraticBezierTo(-u * 0.7, -u * 0.75, 0, -u * 0.78)
        ..quadraticBezierTo(u * 0.7, -u * 0.75, u * 0.75, u * 0.05)
        ..quadraticBezierTo(u * 0.35, u * 0.18, u * 0.22, u * 0.12)
        ..lineTo(u * 0.26, u * 0.72)
        ..quadraticBezierTo(0, u * 0.82, -u * 0.26, u * 0.72)
        ..lineTo(-u * 0.22, u * 0.12)
        ..quadraticBezierTo(-u * 0.35, u * 0.18, -u * 0.75, u * 0.05)
        ..close();
      c.drawPath(cap, _fill(0xFFE9D8BC));
      c.drawPath(cap, _stroke(0xFFA8896A, u * 0.1));
    case 'green-pepper':
      final rect = Rect.fromCircle(center: Offset.zero, radius: u * 0.8);
      c.drawArc(rect, -math.pi * 0.9, math.pi * 0.85, false, _stroke(0xFF3E8E2E, u * 0.3));
      c.drawArc(rect, -math.pi * 0.85, math.pi * 0.7, false, _stroke(0xFF6DB55A, u * 0.08));
    case 'onion':
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: u * 0.75), -math.pi * 0.95, math.pi * 0.95, false, _stroke(0xFFB25C9F, u * 0.13));
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: u * 0.52), -math.pi * 0.9, math.pi * 0.8, false, _stroke(0xFFDBA6D0, u * 0.1));
    case 'olive':
      c.drawCircle(Offset.zero, u * 0.42, _stroke(0xFF2A2421, u * 0.24));
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: u * 0.45), math.pi * 1.1, math.pi * 0.4, false, _stroke(0x55FFFFFF, u * 0.07));
    case 'tomato':
      c.drawCircle(Offset.zero, u, _fill(0xFFD93A2C));
      c.drawCircle(Offset.zero, u * 0.82, _fill(0xFFEE6A55));
      final seeds = _fill(0xFFF7C7A3);
      for (var i = 0; i < 5; i++) {
        final a = i / 5 * math.pi * 2;
        c.save();
        c.translate(math.cos(a) * u * 0.47, math.sin(a) * u * 0.47);
        c.rotate(a);
        c.drawOval(Rect.fromCenter(center: Offset.zero, width: u * 0.32, height: u * 0.18), seeds);
        c.restore();
      }
      c.drawCircle(Offset.zero, u * 0.12, _fill(0xFFE85846));
    case 'jalapeno':
      c.drawCircle(Offset.zero, u * 0.36, _fill(0xFFDCEAB0));
      c.drawCircle(Offset.zero, u * 0.5, _stroke(0xFF4E9A2B, u * 0.22));
      final seed = _fill(0xFFF4F0D0);
      c.drawCircle(Offset(-u * 0.1, -u * 0.08), u * 0.07, seed);
      c.drawCircle(Offset(u * 0.12, u * 0.02), u * 0.07, seed);
      c.drawCircle(Offset(0, u * 0.15), u * 0.06, seed);
    case 'banana-pepper':
      c.drawCircle(Offset.zero, u * 0.38, _fill(0x66F3EE9A));
      c.drawCircle(Offset.zero, u * 0.5, _stroke(0xFFD6CC4C, u * 0.18));
    case 'pineapple':
      final path = Path()
        ..moveTo(0, -u * 0.6)
        ..quadraticBezierTo(u * 0.1, -u * 0.62, u * 0.62, u * 0.38)
        ..quadraticBezierTo(u * 0.62, u * 0.5, u * 0.5, u * 0.5)
        ..lineTo(-u * 0.5, u * 0.5)
        ..quadraticBezierTo(-u * 0.62, u * 0.5, -u * 0.62, u * 0.38)
        ..quadraticBezierTo(-u * 0.1, -u * 0.62, 0, -u * 0.6)
        ..close();
      c.drawPath(path, _fill(0xFFF8D54E));
      c.drawPath(path, _stroke(0xFFE2B63A, u * 0.08));
    case 'spinach':
      final leaf = _leaf(u * 1.3, u * 0.7);
      c.drawPath(leaf, _fill(0xFF2D6A2A));
      c.drawLine(Offset(-u * 0.55, 0), Offset(u * 0.55, 0), _stroke(0xFF4F8E44, u * 0.06));
    case 'basil':
      final leaf = _leaf(u * 1.6, u * 0.9);
      c.drawPath(
        leaf,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFF4A8C3A), Color(0xFF2C5E24)])
              .createShader(Rect.fromCenter(center: Offset.zero, width: u * 1.6, height: u)),
      );
      c.drawLine(Offset(-u * 0.7, 0), Offset(u * 0.7, 0), _stroke(0xFF6AA457, u * 0.07));
    default:
      c.drawCircle(Offset.zero, u * 0.4, _fill(0xFF8A4521));
  }
}

/// Small round swatch of a single topping (used on topping chips).
class ToppingIcon extends StatelessWidget {
  const ToppingIcon(this.id, {super.key, this.size = 34});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ToppingIconPainter(id)),
  );
}

class _ToppingIconPainter extends CustomPainter {
  _ToppingIconPainter(this.id);

  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, size.width / 2, _fill(0xFFFBE3A6));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.4);
    drawTopping(canvas, toppingArtAliases[id] ?? id, size.width * 0.3);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ToppingIconPainter old) => old.id != id;
}
