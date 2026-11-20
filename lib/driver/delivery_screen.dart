import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/ui.dart';
import 'driver_controller.dart';
import 'driver_models.dart';

/// One delivery: where it goes, who to call, what to collect — then Delivered.
class DeliveryScreen extends StatelessWidget {
  const DeliveryScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final s = c.state;
    final d = [...?s?.run, ...?s?.queue].where((x) => x.id == deliveryId).firstOrNull;
    if (d == null) {
      // Delivered, cancelled or moved to another driver.
      return Scaffold(
        backgroundColor: AlsColors.cream,
        appBar: AppBar(backgroundColor: AlsColors.cream),
        body: Center(child: Text('This order isn’t on your list any more.', style: AlsText.body(16))),
      );
    }
    final a = d.address;
    return Scaffold(
      backgroundColor: AlsColors.cream,
      appBar: AppBar(backgroundColor: AlsColors.cream, title: Text('Order #${d.number}', style: AlsText.display(22))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
        children: [
          _PaymentBanner(d),
          const SizedBox(height: 14),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.customerName, style: AlsText.display(24)),
                if (a != null) ...[
                  const SizedBox(height: 4),
                  Text(a.full, style: AlsText.body(17, weight: FontWeight.w800)),
                ],
                if (a?.instructions?.isNotEmpty ?? false)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(12)),
                    child: Text('Drop-off: ${a!.instructions}', style: AlsText.body(15, weight: FontWeight.w800)),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AlsButton(label: 'Navigate', icon: Icons.navigation_rounded, height: 50, onPressed: a == null ? null : () => _navigate(context, d)),
                    ),
                    const SizedBox(width: 10),
                    _RoundAction(icon: Icons.call_rounded, tooltip: 'Call', onTap: () => _launch(context, Uri(scheme: 'tel', path: d.customerPhone))),
                    const SizedBox(width: 8),
                    _RoundAction(icon: Icons.sms_rounded, tooltip: 'Text', onTap: () => _launch(context, Uri(scheme: 'sms', path: d.customerPhone))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d.itemsCount} item${d.itemsCount == 1 ? '' : 's'}', style: AlsText.display(18)),
                const SizedBox(height: 8),
                for (final i in d.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${i.quantity}× ${i.name}', style: AlsText.body(15, weight: FontWeight.w800)),
                  ),
                if (d.notes?.isNotEmpty ?? false) Text('Note: ${d.notes}', style: AlsText.body(14, color: AlsColors.brownSoft)),
                if (!d.onTheRoad) ...[const SizedBox(height: 8), Text(d.kitchenLabel, style: AlsText.body(14, color: d.ready ? AlsColors.success : AlsColors.muted, weight: FontWeight.w800))],
              ],
            ),
          ),
          if (d.problem != null) ...[
            const SizedBox(height: 12),
            Text('You reported: ${d.problem}. The store has been told.', style: AlsText.body(14, color: AlsColors.red, weight: FontWeight.w800)),
          ],
        ],
      ),
      bottomSheet: d.onTheRoad
          ? SafeArea(
              child: Container(
                color: AlsColors.cream,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AlsButton(label: 'Problem', style: AlsButtonStyle.outline, onPressed: c.busy ? null : () => _problem(context, c, d)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: AlsButton(label: 'Delivered', icon: Icons.check_rounded, style: AlsButtonStyle.dark, loading: c.busy, onPressed: () => _delivered(context, c, d)),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _navigate(BuildContext context, DriverDelivery d) {
    final a = d.address!;
    final destination = a.lat != null && a.lng != null ? '${a.lat},${a.lng}' : a.full;
    return _launch(context, Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': destination, 'travelmode': 'driving'}));
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false);
    if (!opened && context.mounted) showError(context, 'Couldn’t open that on this phone');
  }

  Future<void> _delivered(BuildContext context, DriverController c, DriverDelivery d) async {
    var cash = false;
    if (d.collectsCash) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Did you collect ${money(d.cashDueCents)}?'),
          content: const Text('Only confirm once you have the cash. It’s added to what you hand in at the end of your shift.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, collected')),
          ],
        ),
      );
      if (yes != true) return;
      cash = true;
    }
    final error = await c.delivered(d, cashCollected: cash);
    if (!context.mounted) return;
    if (error != null) {
      showError(context, error);
    } else {
      showToast(context, 'Order #${d.number} delivered');
      Navigator.pop(context);
    }
  }

  Future<void> _problem(BuildContext context, DriverController c, DriverDelivery d) async {
    const reasons = ['Customer isn’t answering', 'Can’t find the address', 'Customer refused the order', 'Car trouble'];
    final other = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AlsColors.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What’s wrong?', style: AlsText.display(22)),
            const SizedBox(height: 4),
            Text('The store gets an alert and will call you or the customer.', style: AlsText.body(13, color: AlsColors.muted)),
            const SizedBox(height: 10),
            for (final r in reasons) ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
            TextField(controller: other, decoration: const InputDecoration(hintText: 'Something else…')),
            const SizedBox(height: 10),
            AlsButton(
              label: 'Send',
              style: AlsButtonStyle.dark,
              onPressed: () => other.text.trim().length >= 3 ? Navigator.pop(ctx, other.text.trim()) : null,
            ),
          ],
        ),
      ),
    );
    other.dispose();
    if (reason == null) return;
    final error = await c.reportProblem(d, reason);
    if (context.mounted) error != null ? showError(context, error) : showToast(context, 'The store has been told');
  }
}

class _PaymentBanner extends StatelessWidget {
  const _PaymentBanner(this.d);

  final DriverDelivery d;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: d.collectsCash ? AlsColors.red : AlsColors.success, borderRadius: BorderRadius.circular(18)),
    child: Row(
      children: [
        Icon(d.collectsCash ? Icons.payments_rounded : Icons.verified_rounded, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            d.collectsCash ? 'Collect ${money(d.cashDueCents)} cash' : 'Paid — nothing to collect',
            style: AlsText.display(22, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: AlsColors.line, width: 1.5)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(13), child: Icon(icon, color: AlsColors.brown)),
      ),
    ),
  );
}
