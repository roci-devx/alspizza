import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/cart.dart';
import '../state/catalog.dart';
import '../widgets/menu_cards.dart';

class DealsScreen extends StatelessWidget {
  const DealsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogStore>();
    final combos = catalog.menu?.categories.where((c) => c.slug == 'deals').expand((c) => c.items).toList() ?? const <MenuItem>[];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 180),
          children: [
            Text('Deals', style: AlsText.display(30)),
            Text('Fresh savings, every day', style: AlsText.body(14, color: AlsColors.muted)),
            const SizedBox(height: 18),
            for (final (i, d) in catalog.deals.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Reveal(
                  delay: Reveal.stagger(i, ms: 80),
                  child: _Ticket(deal: d, index: i),
                ),
              ),
            if (combos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Combos', style: AlsText.display(22)),
              const SizedBox(height: 10),
              for (final (i, c) in combos.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Reveal(
                    delay: Reveal.stagger(i + 2),
                    child: MenuItemTile(item: c),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Coupon-style card with a perforated edge.
class _Ticket extends StatelessWidget {
  const _Ticket({required this.deal, required this.index});

  final Deal deal;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final applied = cart.promoCode == deal.code;
    final colors = [
      [const Color(0xFFE8962A), const Color(0xFFC9461C)],
      [const Color(0xFF8A3B1F), AlsColors.brown],
      [const Color(0xFF4E8A34), const Color(0xFF2C5E24)],
    ][index % 3];
    return ClipPath(
      clipper: _TicketClipper(),
      child: Container(
        height: 132,
        decoration: const BoxDecoration(color: Colors.white),
        child: Row(
          children: [
            Container(
              width: 112,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              child: Text(
                deal.label.split(' on ').first,
                textAlign: TextAlign.center,
                style: AlsText.display(22, color: Colors.white),
              ),
            ),
            CustomPaint(size: const Size(2, 132), painter: _Perforation()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deal.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AlsText.body(15, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (deal.minSubtotalCents > 0) 'Min ${money(deal.minSubtotalCents)}',
                        if (deal.firstOrderOnly) 'First order only',
                        if (deal.endsAt != null) 'Ends ${dayLabel(deal.endsAt!)}',
                      ].join(' · '),
                      style: AlsText.body(12, color: AlsColors.muted),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(8)),
                          child: Text(deal.code, style: AlsText.label(13, color: AlsColors.brown)),
                        ),
                        const Spacer(),
                        AlsButton(
                          label: applied ? 'Applied' : 'Apply',
                          icon: applied ? Icons.check_rounded : null,
                          height: 38,
                          expand: false,
                          style: applied ? AlsButtonStyle.outline : AlsButtonStyle.dark,
                          onPressed: () {
                            cart.setPromo(applied ? null : deal.code);
                            showToast(context, applied ? 'Removed ${deal.code}' : '${deal.code} will be applied at checkout');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const r = 12.0;
    const notchX = 113.0;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)))
      ..addOval(Rect.fromCircle(center: const Offset(notchX, 0), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(notchX, size.height), radius: r))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _Perforation extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AlsColors.line
      ..strokeWidth = 2;
    for (var y = 16.0; y < size.height - 14; y += 10) {
      canvas.drawLine(Offset(1, y), Offset(1, y + 5), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
