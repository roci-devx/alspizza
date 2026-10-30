import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';
import 'pizza_art.dart';

/// Renders a menu item's illustration from its `art` key ("pizza", "wings:bbq",
/// "soda:cola", "deal:family"…). A real photo can override it via [imageUrl].
class FoodArt extends StatelessWidget {
  const FoodArt({super.key, required this.art, this.pizza, this.imageUrl, this.seed, this.radius = 18});

  final String art;
  final PizzaConfig? pizza;
  final String? imageUrl;
  final int? seed;
  final double radius;

  factory FoodArt.item(MenuItem item, {double radius = 18, bool photo = true}) =>
      FoodArt(art: item.art, pizza: item.config.pizza, imageUrl: photo ? item.imageUrl : null, seed: item.id.hashCode, radius: radius);

  factory FoodArt.line(String art, Json config, {int? seed}) {
    final p = config['pizza'] as Json?;
    return FoodArt(
      art: art,
      seed: seed,
      pizza: p == null
          ? null
          : PizzaConfig(
              sizePrices: const {},
              toppings: ((p['toppings'] as List?) ?? const []).cast<String>(),
              sauce: p['sauce'] as String? ?? 'marinara',
              cheese: p['cheese'] as String? ?? 'regular',
              crust: p['crust'] as String? ?? 'hand-tossed',
              defaultSize: p['size'] as String? ?? 'large',
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _drawn();
    // The illustration shows while the photo loads (and if it fails), then the photo fades in.
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          AppConfig.mediaUrl(url),
          fit: BoxFit.cover,
          cacheWidth: 700,
          errorBuilder: (_, _, _) => _drawn(),
          frameBuilder: (context, child, frame, sync) => sync
              ? child
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  // The default layout loosens constraints, which would letterbox the photo instead of covering.
                  layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  child: frame == null ? KeyedSubtree(key: const ValueKey('art'), child: _drawn()) : KeyedSubtree(key: const ValueKey('photo'), child: child),
                ),
        ),
      ),
    );
  }

  Widget _drawn() {
    final parts = art.split(':');
    final type = parts.first;
    final variant = parts.length > 1 ? parts[1] : '';
    if (type == 'pizza') {
      final p = pizza;
      return PizzaArt(
        toppings: p?.toppings ?? const ['pepperoni'],
        sauce: p?.sauce ?? 'marinara',
        cheese: p?.cheese ?? 'regular',
        crust: p?.crust ?? 'hand-tossed',
        density: p?.density ?? 1,
        seed: seed ?? art.hashCode,
      );
    }
    if (type == 'deal') return _DealArt(variant);
    return AspectRatio(
      aspectRatio: 1,
      child: RepaintBoundary(child: CustomPaint(painter: _ItemPainter(type, variant))),
    );
  }
}

class _DealArt extends StatelessWidget {
  const _DealArt(this.variant);

  final String variant;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, box) {
        final s = box.maxWidth;
        Widget at(double left, double top, double size, Widget child) =>
            Positioned(left: s * left, top: s * top, width: s * size, height: s * size, child: child);
        const pepperoni = PizzaArt(toppings: ['pepperoni'], seed: 11);
        const supreme = PizzaArt(toppings: ['pepperoni', 'mushroom', 'green-pepper'], seed: 4);
        const item = FoodArt.new;
        return Stack(
          clipBehavior: Clip.none,
          children: switch (variant) {
            'family' => [at(0.0, 0.08, 0.62, supreme), at(0.3, 0.2, 0.62, pepperoni), at(0.62, 0.36, 0.42, item(art: 'soda:cola'))],
            'duo' => [at(0.0, 0.05, 0.72, pepperoni), at(0.48, 0.42, 0.55, item(art: 'wings:buffalo'))],
            'lunch' => [
              at(0.05, 0.12, 0.62, const PizzaArt(toppings: ['pepperoni'], crust: 'pan', seed: 3)),
              at(0.55, 0.3, 0.45, item(art: 'soda:cola')),
            ],
            _ => [
              at(0.0, 0.0, 1, CustomPaint(painter: _BoxPainter())),
              at(0.12, 0.1, 0.62, pepperoni),
              at(0.56, 0.42, 0.46, item(art: 'wings:buffalo')),
              at(0.02, 0.56, 0.44, item(art: 'breadsticks')),
            ],
          },
        );
      },
    ),
  );
}

class _BoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final lid = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.06, s * 0.02, s * 0.76, s * 0.34), Radius.circular(s * 0.04));
    canvas.drawRRect(lid, Paint()..color = const Color(0xFFC9955A));
    canvas.drawRRect(lid.deflate(s * 0.03), Paint()..color = const Color(0xFFD9A86C));
    final tp = TextPainter(
      text: TextSpan(
        text: "Al's",
        style: TextStyle(fontSize: s * 0.1, fontWeight: FontWeight.w900, color: const Color(0xFF5A210F), fontStyle: FontStyle.italic),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(s * 0.44 - tp.width / 2, s * 0.08));
    final base = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.04, s * 0.3, s * 0.8, s * 0.62), Radius.circular(s * 0.05));
    canvas.drawRRect(
      base.shift(Offset(0, s * 0.03)),
      Paint()
        ..color = const Color(0x305A210F)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.drawRRect(base, Paint()..color = const Color(0xFFD9A86C));
    canvas.drawRRect(base.deflate(s * 0.035), Paint()..color = const Color(0xFFEFD9B6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Paint _p(int c) => Paint()..color = Color(c);
Paint _line(int c, double w) => Paint()
  ..color = Color(c)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _ItemPainter extends CustomPainter {
  _ItemPainter(this.type, this.variant);

  final String type;
  final String variant;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s * 0.5, s * 0.88), width: s * 0.72, height: s * 0.12),
      Paint()
        ..color = const Color(0x2E5A210F)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    switch (type) {
      case 'wings':
        _wings(canvas, s);
      case 'breadsticks':
        _breadsticks(canvas, s);
      case 'cheesesticks':
        _cheeseSticks(canvas, s);
      case 'knots':
        _knots(canvas, s);
      case 'mozz':
        _mozz(canvas, s);
      case 'fries':
        _fries(canvas, s);
      case 'pasta':
        _pasta(canvas, s);
      case 'cinnamon':
        _cinnamon(canvas, s);
      case 'brownie':
        _brownie(canvas, s);
      case 'cookie':
        _cookie(canvas, s);
      case 'rolls':
        _rolls(canvas, s);
      case 'soda':
        _soda(canvas, s);
      case 'dip':
        _dip(canvas, Offset(s * 0.5, s * 0.55), s * 0.34, variant);
      default:
        canvas.drawCircle(Offset(s / 2, s / 2), s * 0.3, _p(0xFFE8962A));
    }
  }

  void _marinaraCup(Canvas c, Offset at, double r) => _dip(c, at, r, 'marinara');

  void _dip(Canvas c, Offset at, double r, String flavor) {
    const sauces = {'marinara': 0xFFC8371E, 'ranch': 0xFFF4F1E6, 'garlic': 0xFFF2CF63, 'bluecheese': 0xFFEEEAE0, 'bbq': 0xFF6A2412};
    final body = Path()
      ..moveTo(at.dx - r, at.dy)
      ..lineTo(at.dx - r * 0.78, at.dy + r * 0.85)
      ..quadraticBezierTo(at.dx, at.dy + r * 1.05, at.dx + r * 0.78, at.dy + r * 0.85)
      ..lineTo(at.dx + r, at.dy)
      ..close();
    c.drawPath(
      body,
      Paint()..shader = const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFE2DDD2)]).createShader(Rect.fromCircle(center: at, radius: r)),
    );
    c.drawOval(Rect.fromCenter(center: at, width: r * 2, height: r * 0.7), _p(0xFFF7F3EA));
    c.drawOval(Rect.fromCenter(center: at, width: r * 1.75, height: r * 0.55), _p(sauces[flavor] ?? sauces['marinara']!));
    c.drawOval(Rect.fromCenter(center: at.translate(-r * 0.35, -r * 0.06), width: r * 0.5, height: r * 0.14), _p(0x55FFFFFF));
    final rnd = math.Random(flavor.hashCode);
    final speck = flavor == 'ranch'
        ? _p(0xFF5D8F3A)
        : flavor == 'bluecheese'
        ? _p(0xFF6E8FB0)
        : flavor == 'garlic'
        ? _p(0xFFFFF6D8)
        : null;
    if (speck != null) {
      for (var i = 0; i < 10; i++) {
        c.drawCircle(at + Offset((rnd.nextDouble() - 0.5) * r * 1.4, (rnd.nextDouble() - 0.5) * r * 0.36), r * 0.04, speck);
      }
    }
  }

  void _wings(Canvas c, double s) {
    const glaze = {
      'buffalo': [0xFFC8461F, 0xFFE66A3C],
      'bbq': [0xFF7A2B12, 0xFFA34A2B],
      'garlic': [0xFFE2B866, 0xFFF2D58F],
      'lemon': [0xFFE7C35B, 0xFFF5DE8E],
    };
    final colors = glaze[variant] ?? glaze['buffalo']!;
    final boat = Path()
      ..moveTo(s * 0.1, s * 0.55)
      ..lineTo(s * 0.9, s * 0.55)
      ..lineTo(s * 0.8, s * 0.86)
      ..lineTo(s * 0.2, s * 0.86)
      ..close();
    c.drawPath(boat, _p(0xFFD3A86B));
    for (var i = 1; i < 4; i++) {
      final x = s * (0.2 + i * 0.15);
      c.drawLine(Offset(x, s * 0.56), Offset(x - s * 0.02, s * 0.85), _line(0xFFB98C52, s * 0.012));
    }
    final wings = [(0.3, 0.48, -0.5), (0.52, 0.44, 0.25), (0.72, 0.5, 0.8), (0.42, 0.56, 1.6), (0.62, 0.58, -1.2)];
    for (final (x, y, rot) in wings) {
      c.save();
      c.translate(s * x, s * y);
      c.rotate(rot);
      final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 0.3, height: s * 0.15), Radius.circular(s * 0.075));
      c.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            colors: [Color(colors[1]), Color(colors[0])],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(body.outerRect),
      );
      c.drawCircle(Offset(s * 0.13, 0), s * 0.09, _p(colors[0]));
      c.drawLine(Offset(-s * 0.09, -s * 0.035), Offset(s * 0.03, -s * 0.045), _line(0x66FFFFFF, s * 0.018));
      if (variant == 'garlic' || variant == 'lemon') {
        final speck = _p(variant == 'garlic' ? 0xFF4E7F34 : 0xFF2B2421);
        for (var i = 0; i < 5; i++) {
          c.drawCircle(Offset(-s * 0.1 + i * s * 0.05, (i.isEven ? 1 : -1) * s * 0.02), s * 0.008, speck);
        }
      }
      c.restore();
    }
  }

  void _breadsticks(Canvas c, double s) {
    for (var i = 0; i < 5; i++) {
      c.save();
      c.translate(s * 0.46, s * 0.62);
      c.rotate(-0.5 + i * 0.22);
      final stick = RRect.fromRectAndRadius(Rect.fromLTWH(-s * 0.05, -s * 0.52, s * 0.11, s * 0.56), Radius.circular(s * 0.055));
      c.drawRRect(stick, Paint()..shader = const LinearGradient(colors: [Color(0xFFF2C277), Color(0xFFCF8A3C)]).createShader(stick.outerRect));
      final rnd = math.Random(i);
      for (var k = 0; k < 6; k++) {
        c.drawCircle(
          Offset(-s * 0.02 + rnd.nextDouble() * s * 0.05, -s * 0.48 + rnd.nextDouble() * s * 0.46),
          s * 0.007,
          _p(k.isEven ? 0xFFFFF6DF : 0xFF5D8F3A),
        );
      }
      c.restore();
    }
    _marinaraCup(c, Offset(s * 0.74, s * 0.68), s * 0.13);
  }

  void _cheeseSticks(Canvas c, double s) {
    final board = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.12, s * 0.3, s * 0.72, s * 0.48), Radius.circular(s * 0.06));
    c.drawRRect(board, _p(0xFFD38C3F));
    final top = board.deflate(s * 0.035);
    c.drawRRect(top, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFE08A), Color(0xFFF4BE48)]).createShader(top.outerRect));
    final rnd = math.Random(3);
    for (var i = 0; i < 16; i++) {
      c.drawOval(
        Rect.fromCenter(center: Offset(top.left + rnd.nextDouble() * top.width, top.top + rnd.nextDouble() * top.height), width: s * 0.04, height: s * 0.025),
        _p(0x55D8892E),
      );
    }
    for (var i = 1; i < 5; i++) {
      final x = top.left + top.width * i / 5;
      c.drawLine(Offset(x, top.top), Offset(x, top.bottom), _line(0x55A0652A, s * 0.008));
    }
    _marinaraCup(c, Offset(s * 0.8, s * 0.3), s * 0.12);
  }

  void _knots(Canvas c, double s) {
    final spots = [(0.32, 0.42), (0.6, 0.38), (0.46, 0.62), (0.74, 0.62), (0.22, 0.66)];
    for (final (x, y) in spots) {
      final at = Offset(s * x, s * y);
      c.drawCircle(
        at,
        s * 0.14,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFFF6CB82), Color(0xFFCF8A3C)],
          ).createShader(Rect.fromCircle(center: at, radius: s * 0.14)),
      );
      c.drawArc(Rect.fromCircle(center: at, radius: s * 0.08), 0.4, math.pi * 1.4, false, _line(0xFFAF6B2A, s * 0.022));
      c.drawCircle(at.translate(-s * 0.04, -s * 0.05), s * 0.012, _p(0xFF5D8F3A));
      c.drawCircle(at.translate(s * 0.05, s * 0.02), s * 0.01, _p(0xFFFFF6DF));
    }
  }

  void _mozz(Canvas c, double s) {
    for (var i = 0; i < 4; i++) {
      c.save();
      c.translate(s * 0.45, s * (0.38 + i * 0.12));
      c.rotate(-0.12 + i * 0.05);
      final stick = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 0.5, height: s * 0.12), Radius.circular(s * 0.06));
      c.drawRRect(
        stick,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFE6A85A), Color(0xFFC07030)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(stick.outerRect),
      );
      if (i == 1) {
        c.drawRect(Rect.fromCenter(center: Offset(s * 0.2, 0), width: s * 0.08, height: s * 0.07), _p(0xFFFFF4D6));
      }
      c.restore();
    }
    _marinaraCup(c, Offset(s * 0.8, s * 0.7), s * 0.12);
  }

  void _fries(Canvas c, double s) {
    final rnd = math.Random(9);
    for (var i = 0; i < 10; i++) {
      c.save();
      c.translate(s * (0.32 + i * 0.04), s * 0.5);
      c.rotate((rnd.nextDouble() - 0.5) * 0.5);
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-s * 0.025, -s * (0.3 + rnd.nextDouble() * 0.1), s * 0.05, s * 0.4), Radius.circular(s * 0.01)),
        _p(i.isEven ? 0xFFF4C548 : 0xFFE9B23A),
      );
      c.restore();
    }
    final carton = Path()
      ..moveTo(s * 0.26, s * 0.46)
      ..quadraticBezierTo(s * 0.5, s * 0.54, s * 0.74, s * 0.46)
      ..lineTo(s * 0.68, s * 0.88)
      ..lineTo(s * 0.32, s * 0.88)
      ..close();
    c.drawPath(
      carton,
      Paint()..shader = const LinearGradient(colors: [Color(0xFFC8301F), Color(0xFF9A1B10)]).createShader(Rect.fromLTWH(0, s * 0.46, s, s * 0.42)),
    );
    c.drawCircle(Offset(s * 0.5, s * 0.68), s * 0.07, _p(0xFFFCF7EC));
    c.drawCircle(Offset(s * 0.5, s * 0.68), s * 0.045, _p(0xFFE8962A));
  }

  void _pasta(Canvas c, double s) {
    const sauces = {'alfredo': 0xFFF4E6C4, 'marinara': 0xFFC8371E, 'veggie': 0xFFD24A2A};
    final tray = Rect.fromCenter(center: Offset(s * 0.5, s * 0.58), width: s * 0.84, height: s * 0.6);
    c.drawOval(tray, Paint()..shader = const LinearGradient(colors: [Color(0xFFEDEFF2), Color(0xFFAEB3BA)]).createShader(tray));
    final inner = tray.deflate(s * 0.05);
    c.drawOval(inner, _p(sauces[variant] ?? sauces['marinara']!));
    final rnd = math.Random(variant.hashCode);
    for (var i = 0; i < 26; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = math.sqrt(rnd.nextDouble()) * 0.8;
      final at = inner.center + Offset(math.cos(a) * inner.width / 2 * d, math.sin(a) * inner.height / 2 * d);
      c.save();
      c.translate(at.dx, at.dy);
      c.rotate(rnd.nextDouble() * math.pi);
      c.drawLine(Offset(-s * 0.03, 0), Offset(s * 0.03, 0), _line(variant == 'alfredo' ? 0xFFF0CF84 : 0xFFF3D38E, s * 0.035));
      c.drawLine(Offset(-s * 0.02, -s * 0.008), Offset(s * 0.02, s * 0.008), _line(0x55A0652A, s * 0.006));
      c.restore();
    }
    for (var i = 0; i < 6; i++) {
      final at = inner.center + Offset((rnd.nextDouble() - 0.5) * inner.width * 0.7, (rnd.nextDouble() - 0.5) * inner.height * 0.6);
      if (variant == 'alfredo') {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: s * 0.08, height: s * 0.055), Radius.circular(s * 0.015)), _p(0xFFF0D9AE));
      } else if (variant == 'veggie') {
        c.drawPath(Path()..addOval(Rect.fromCenter(center: at, width: s * 0.09, height: s * 0.04)), _p(i.isEven ? 0xFF2D6A2A : 0xFFE9D8BC));
      } else {
        c.drawCircle(at, s * 0.035, _p(0xFF7B3A1E));
      }
    }
    for (var i = 0; i < 5; i++) {
      final at = inner.center + Offset((rnd.nextDouble() - 0.5) * inner.width * 0.6, (rnd.nextDouble() - 0.5) * inner.height * 0.5);
      c.drawOval(Rect.fromCenter(center: at, width: s * 0.12, height: s * 0.07), _p(0xAAFFE6A0));
    }
  }

  void _cinnamon(Canvas c, double s) {
    for (var i = 0; i < 5; i++) {
      final y = s * (0.34 + i * 0.09);
      final path = Path()
        ..moveTo(s * 0.16, y)
        ..cubicTo(s * 0.32, y - s * 0.08, s * 0.46, y + s * 0.08, s * 0.62, y)
        ..cubicTo(s * 0.7, y - s * 0.05, s * 0.74, y + s * 0.02, s * 0.78, y - s * 0.02);
      c.drawPath(path, _line(0xFFB86A2E, s * 0.07));
      c.drawPath(path, _line(0xFFD9944A, s * 0.035));
      c.drawPath(path, _line(0x88F3E1C0, s * 0.01));
    }
    _dip(c, Offset(s * 0.8, s * 0.74), s * 0.12, 'ranch');
  }

  void _brownie(Canvas c, double s) {
    final tray = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.14, s * 0.24, s * 0.72, s * 0.6), Radius.circular(s * 0.05));
    c.drawRRect(tray, _p(0xFF3B1C0E));
    final cell = (tray.width - s * 0.08) / 3;
    final rnd = math.Random(5);
    for (var r = 0; r < 3; r++) {
      for (var k = 0; k < 3; k++) {
        final rect = Rect.fromLTWH(tray.left + s * 0.03 + k * (cell + s * 0.01), tray.top + s * 0.03 + r * (cell * 0.78 + s * 0.01), cell, cell * 0.78);
        c.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(s * 0.02)),
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFF7A4226), Color(0xFF4A2412)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(rect),
        );
        for (var i = 0; i < 2; i++) {
          c.drawCircle(Offset(rect.left + rnd.nextDouble() * rect.width, rect.top + rnd.nextDouble() * rect.height), s * 0.014, _p(0xFF2E140A));
        }
      }
    }
  }

  void _cookie(Canvas c, double s) {
    final center = Offset(s * 0.5, s * 0.52);
    final r = s * 0.38;
    c.drawCircle(
      center,
      r,
      Paint()..shader = const RadialGradient(colors: [Color(0xFFE6B26B), Color(0xFFC48843)]).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 4;
      c.drawLine(center - Offset(math.cos(a), math.sin(a)) * r, center + Offset(math.cos(a), math.sin(a)) * r, _line(0x33874F1E, s * 0.008));
    }
    final rnd = math.Random(2);
    for (var i = 0; i < 16; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = math.sqrt(rnd.nextDouble()) * r * 0.85;
      c.drawOval(Rect.fromCenter(center: center + Offset(math.cos(a), math.sin(a)) * d, width: s * 0.05, height: s * 0.04), _p(0xFF3B1C0E));
    }
  }

  void _rolls(Canvas c, double s) {
    final spots = [(0.3, 0.42), (0.58, 0.38), (0.44, 0.64), (0.72, 0.62), (0.2, 0.68)];
    for (final (x, y) in spots) {
      final at = Offset(s * x, s * y);
      c.drawCircle(at, s * 0.13, _p(0xFFE5A65A));
      final path = Path();
      for (var t = 0.0; t < math.pi * 5; t += 0.2) {
        final rr = s * 0.012 * t;
        final p = at + Offset(math.cos(t) * rr, math.sin(t) * rr);
        t == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path, _line(0xFFB06730, s * 0.018));
      c.drawOval(Rect.fromCenter(center: at.translate(0, -s * 0.03), width: s * 0.16, height: s * 0.07), _p(0xCCFFFBF0));
    }
  }

  void _soda(Canvas c, double s) {
    const flavors = {
      'cola': (0xFF3A1A0F, 0xFFB02013, 0xFFB02013),
      'diet': (0xFF3A1A0F, 0xFFB7BBC2, 0xFF9EA3AA),
      'lemon': (0xFFE3EFA6, 0xFF2E8B3D, 0xFF2E8B3D),
      'orange': (0xFFF08A24, 0xFFE0661A, 0xFFF08A24),
      'rootbeer': (0xFF4A2412, 0xFFF3E6C8, 0xFF7A3A1E),
      'tea': (0xFFB8641E, 0xFF356726, 0xFF356726),
      'water': (0xFFE4F2FA, 0xFF2A78D6, 0xFF2A78D6),
    };
    final (liquid, label, cap) = flavors[variant] ?? flavors['cola']!;
    final body = Path()
      ..moveTo(s * 0.44, s * 0.14)
      ..lineTo(s * 0.56, s * 0.14)
      ..cubicTo(s * 0.57, s * 0.24, s * 0.7, s * 0.26, s * 0.7, s * 0.36)
      ..lineTo(s * 0.7, s * 0.86)
      ..quadraticBezierTo(s * 0.7, s * 0.9, s * 0.66, s * 0.9)
      ..lineTo(s * 0.34, s * 0.9)
      ..quadraticBezierTo(s * 0.3, s * 0.9, s * 0.3, s * 0.86)
      ..lineTo(s * 0.3, s * 0.36)
      ..cubicTo(s * 0.3, s * 0.26, s * 0.43, s * 0.24, s * 0.44, s * 0.14)
      ..close();
    c.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(colors: [Color(liquid), Color.lerp(Color(liquid), Colors.white, 0.25)!, Color(liquid)])
            .createShader(Rect.fromLTWH(s * 0.3, 0, s * 0.4, s)),
    );
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.42, s * 0.07, s * 0.16, s * 0.08), Radius.circular(s * 0.02)), _p(cap));
    final band = Rect.fromLTWH(s * 0.3, s * 0.5, s * 0.4, s * 0.18);
    c.drawRect(band, _p(label));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: band.center, width: s * 0.24, height: s * 0.05), Radius.circular(s * 0.025)), _p(0xEEFFFFFF));
    c.drawLine(Offset(s * 0.36, s * 0.36), Offset(s * 0.36, s * 0.84), _line(0x55FFFFFF, s * 0.025));
    if (variant != 'water' && variant != 'tea') {
      final rnd = math.Random(4);
      for (var i = 0; i < 6; i++) {
        c.drawCircle(Offset(s * (0.42 + rnd.nextDouble() * 0.2), s * (0.72 + rnd.nextDouble() * 0.14)), s * 0.008, _p(0x66FFFFFF));
      }
    }
  }

  @override
  bool shouldRepaint(_ItemPainter old) => old.type != type || old.variant != variant;
}
