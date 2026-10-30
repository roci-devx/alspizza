import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/cart.dart';
import '../state/catalog.dart';
import '../state/session.dart';
import 'stripe_native.dart';

enum PayMethod {
  applePay('apple_pay', 'Apple Pay', Icons.apple),
  googlePay('google_pay', 'Google Pay', Icons.account_balance_wallet_rounded),
  card('card', 'Credit or debit card', Icons.credit_card_rounded),
  paypal('paypal', 'PayPal', Icons.paypal_rounded),
  cash('cash', 'Pay at pickup', Icons.payments_rounded);

  const PayMethod(this.api, this.label, this.icon);

  final String api;
  final String label;
  final IconData icon;
}

List<PayMethod> availableMethods(PaymentSetup setup, {required bool pickup, required bool cashEnabled}) {
  final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final cards = setup.stripe || setup.demo;
  return [
    if (cards && (ios || kIsWeb)) PayMethod.applePay,
    if (cards && (android || kIsWeb)) PayMethod.googlePay,
    if (cards) PayMethod.card,
    if (setup.paypal || setup.demo) PayMethod.paypal,
    if (pickup && cashEnabled) PayMethod.cash,
  ];
}

class PaymentOutcome {
  const PaymentOutcome.paid(Order this.order) : redirected = false, cancelled = false;
  const PaymentOutcome.redirected() : order = null, redirected = true, cancelled = false;
  const PaymentOutcome.cancelled() : order = null, redirected = false, cancelled = true;

  final Order? order;
  final bool redirected;
  final bool cancelled;
}

/// Runs the right payment flow for [method]: native PaymentSheet, hosted
/// Stripe Checkout (web), PayPal approval, pay-at-pickup, or the demo sheet
/// when no processor keys are configured.
Future<PaymentOutcome> payOrder(BuildContext context, {required Order order, required PayMethod method}) async {
  final api = context.read<SessionStore>().api;
  final setup = context.read<CatalogStore>().payments;
  final prefs = context.read<CartStore>().prefs;
  Future<Json> pay(String provider) => api.post('/orders/${order.id}/pay', {'provider': provider, 'method': method.api, 'platform': AppConfig.platform});
  Order parse(Json res) => Order.fromJson(res['order'] as Json);

  if (method == PayMethod.cash) return PaymentOutcome.paid(parse(await pay('cash')));

  final live = method == PayMethod.paypal ? setup.paypal : setup.stripe;
  if (!live) {
    final ok = await showDemoPaySheet(context, method, order.totalCents);
    if (!ok) return const PaymentOutcome.cancelled();
    return PaymentOutcome.paid(parse(await pay('demo')));
  }

  final res = await pay(method == PayMethod.paypal ? 'paypal' : 'stripe');
  if (res['status'] == 'redirect') {
    final url = Uri.parse(res['url'] as String);
    if (kIsWeb) {
      await prefs.setString(CartStore.pendingOrderKey, order.id);
      await launchUrl(url, webOnlyWindowName: '_self');
      return const PaymentOutcome.redirected();
    }
    await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    // PayPal returns to our API, which captures the payment; watch for it here.
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final synced = parse(await api.post('/orders/${order.id}/payment/sync'));
      if (synced.paymentStatus == 'paid') {
        await closeInAppWebView();
        return PaymentOutcome.paid(synced);
      }
    }
    return const PaymentOutcome.cancelled();
  }

  final ok = await presentStripePaymentSheet(
    clientSecret: res['clientSecret'] as String,
    publishableKey: res['publishableKey'] as String,
    merchantName: res['merchantDisplayName'] as String? ?? "Al's Pizza",
    appleMerchantId: res['appleMerchantId'] as String?,
    testEnv: res['testEnv'] as bool? ?? true,
  );
  if (!ok) return const PaymentOutcome.cancelled();
  return PaymentOutcome.paid(parse(await api.post('/orders/${order.id}/payment/sync')));
}

/// Stand-in for Apple Pay / Google Pay / card / PayPal while the API runs in demo mode.
Future<bool> showDemoPaySheet(BuildContext context, PayMethod method, int totalCents) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DemoPaySheet(method: method, totalCents: totalCents),
  );
  return ok ?? false;
}

class _DemoPaySheet extends StatefulWidget {
  const _DemoPaySheet({required this.method, required this.totalCents});

  final PayMethod method;
  final int totalCents;

  @override
  State<_DemoPaySheet> createState() => _DemoPaySheetState();
}

class _DemoPaySheetState extends State<_DemoPaySheet> {
  var _stage = 0; // 0 ready, 1 processing, 2 done

  Future<void> _confirm() async {
    HapticFeedback.mediumImpact();
    setState(() => _stage = 1);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _stage = 2);
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.method;
    final dark = m == PayMethod.applePay;
    final (bg, fg, accent) = switch (m) {
      PayMethod.applePay => (const Color(0xFF111111), Colors.white, Colors.white),
      PayMethod.paypal => (Colors.white, const Color(0xFF003087), const Color(0xFF0070E0)),
      _ => (Colors.white, AlsColors.ink, AlsColors.brown),
    };
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(m.icon, color: fg, size: 28),
              const SizedBox(width: 8),
              Text(
                m == PayMethod.card ? 'Card payment' : m.label,
                style: AlsText.display(22, color: fg, weight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                onPressed: _stage == 0 ? () => Navigator.pop(context, false) : null,
                icon: Icon(Icons.close_rounded, color: fg),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AlsColors.orange.withValues(alpha: dark ? 0.25 : 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Demo mode — no real money moves. Add Stripe / PayPal keys to the API to go live.',
              style: AlsText.body(12, color: dark ? AlsColors.orangeLight : AlsColors.brown),
            ),
          ),
          const SizedBox(height: 16),
          _row('Merchant', "Al's Pizza", fg),
          _row(m == PayMethod.paypal ? 'Account' : 'Card', m == PayMethod.paypal ? 'jordan@example.com' : 'Visa •••• 4242', fg),
          Divider(color: fg.withValues(alpha: 0.15), height: 24),
          Row(
            children: [
              Text(
                'Pay Al’s Pizza',
                style: AlsText.body(16, color: fg, weight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                money(widget.totalCents),
                style: AlsText.display(24, color: fg, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: switch (_stage) {
              0 => TapScale(
                key: const ValueKey(0),
                onTap: _confirm,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: m == PayMethod.applePay ? Colors.white : (m == PayMethod.paypal ? const Color(0xFFFFC439) : AlsColors.brown),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    m == PayMethod.applePay ? 'Double-tap to pay' : (m == PayMethod.paypal ? 'Pay with PayPal' : 'Pay ${money(widget.totalCents)}'),
                    style: AlsText.display(
                      18,
                      color: m == PayMethod.applePay ? Colors.black : (m == PayMethod.paypal ? const Color(0xFF003087) : AlsColors.cream),
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              1 => SizedBox(
                key: const ValueKey(1),
                height: 56,
                child: Center(child: CircularProgressIndicator(color: accent)),
              ),
              _ => SizedBox(
                key: const ValueKey(2),
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 34),
                    const SizedBox(width: 8),
                    Text(
                      'Done',
                      style: AlsText.display(20, color: fg, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v, Color fg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(k, style: AlsText.body(14, color: fg.withValues(alpha: 0.6))),
        const Spacer(),
        Text(
          v,
          style: AlsText.body(14, color: fg, weight: FontWeight.w800),
        ),
      ],
    ),
  );
}
