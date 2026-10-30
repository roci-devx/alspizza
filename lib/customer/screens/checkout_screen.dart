import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../payments/payment_flow.dart';
import '../state/cart.dart';
import '../state/catalog.dart';
import '../state/ordering.dart';
import '../state/session.dart';
import '../widgets/places.dart';
import 'home_screen.dart' show FulfillmentToggle;

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, this.cancelledOrderId});

  final String? cancelledOrderId;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _apt = TextEditingController();
  final _instructions = TextEditingController();
  double? _tipRate = 0.18;
  int _customTipCents = 0;
  PayMethod? _method;
  bool _placing = false;
  bool _triedSubmit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<SessionStore>().user;
    final ordering = context.read<OrderingStore>();
    _name.text = user?.name ?? '';
    _phone.text = user?.phone == null ? '' : prettyPhone(user!.phone!);
    _email.text = user?.email ?? '';
    _apt.text = ordering.address?.line2 ?? '';
    _instructions.text = ordering.address?.instructions ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.cancelledOrderId != null) showToast(context, 'Payment cancelled — your order is still here.', icon: Icons.info_outline_rounded);
      _refresh(requote: true);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _apt, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _tipCents {
    final sub = context.read<CartStore>().priced?.subtotalCents ?? context.read<CartStore>().estimateCents;
    if (_tipRate == null) return _customTipCents;
    return ((sub * _tipRate!) / 25).round() * 25;
  }

  Future<void> _refresh({bool requote = false}) async {
    final ordering = context.read<OrderingStore>();
    final cart = context.read<CartStore>();
    final store = ordering.store;
    if (store == null) return;
    if (ordering.isDelivery && ordering.address != null && (requote || !(ordering.quote?.isFresh ?? false))) {
      await ordering.refreshQuote(subtotalCents: cart.estimateCents, name: _name.text, phone: _phone.text);
    }
    if (!mounted) return;
    await cart.reprice(
      storeId: store.id,
      fulfillment: ordering.fulfillment?.name,
      deliveryQuoteId: ordering.isDelivery ? ordering.quote?.quoteId : null,
      tipCents: ordering.isDelivery ? _tipCents : 0,
      immediate: true,
    );
  }

  Future<void> _setFulfillment(Fulfillment f) async {
    await context.read<OrderingStore>().setFulfillment(f);
    await _refresh(requote: true);
  }

  Future<void> _changeAddress() async {
    final a = await pickAddress(context);
    if (a == null || !mounted) return;
    await context.read<OrderingStore>().setAddress(a.copyWith(line2: _apt.text, instructions: _instructions.text));
    await _refresh(requote: true);
  }

  Future<void> _changeStore() async {
    final s = await pickStore(context);
    if (s == null || !mounted) return;
    await context.read<OrderingStore>().setStore(s);
    await _refresh(requote: true);
  }

  Future<void> _place() async {
    final ordering = context.read<OrderingStore>();
    final cart = context.read<CartStore>();
    final session = context.read<SessionStore>();
    setState(() {
      _error = null;
      _triedSubmit = true;
    });
    if (ordering.fulfillment == null) return setState(() => _error = 'Choose pickup or delivery');
    if (!_form.currentState!.validate()) return;
    if (ordering.isDelivery && ordering.address == null) return setState(() => _error = 'Add a delivery address');
    if (_method == null) return setState(() => _error = 'Pick a way to pay');

    setState(() => _placing = true);
    try {
      await session.ensureSession();
      if (ordering.isDelivery && !(ordering.quote?.isFresh ?? false)) await _refresh(requote: true);
      if (ordering.isDelivery && ordering.quote == null) throw ApiException(400, ordering.quoteError ?? 'Delivery isn’t available to that address.');
      final res = await session.api.post('/orders', {
        'storeId': ordering.store!.id,
        'fulfillment': ordering.fulfillment!.name,
        'items': cart.lines.map((l) => l.toApi()).toList(),
        'promoCode': ?cart.promoCode,
        if (ordering.isDelivery) 'deliveryQuoteId': ordering.quote!.quoteId,
        'tipCents': ordering.isDelivery ? _tipCents : 0,
        'customer': {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim().isEmpty ? null : _email.text.trim()},
        if (ordering.isDelivery) 'addressLine2': _apt.text.trim(),
        if (ordering.isDelivery) 'dropoffInstructions': _instructions.text.trim(),
        'platform': AppConfig.platform,
      });
      final order = Order.fromJson(res['order'] as Json);
      if (!mounted) return;
      final outcome = await payOrder(context, order: order, method: _method!);
      if (!mounted || outcome.redirected) return;
      if (outcome.cancelled) {
        setState(() => _error = 'Payment cancelled. Your order wasn’t placed.');
        return;
      }
      cart.clear();
      context.read<OrdersStore>().upsert(outcome.order!);
      context.go('/order/${order.id}?new=1');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordering = context.watch<OrderingStore>();
    final cart = context.watch<CartStore>();
    final payments = context.watch<CatalogStore>().payments;
    final store = ordering.store;
    final q = cart.priced;
    final delivery = ordering.isDelivery;
    final methods = availableMethods(payments, pickup: !delivery, cashEnabled: store?.cashEnabled ?? false);
    if (_method != null && !methods.contains(_method)) _method = null;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _form,
        // Re-check fields as the customer fixes them once they've tried to place the order.
        autovalidateMode: _triedSubmit ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 150),
          children: [
            _Section(
              title: 'Pickup or delivery?',
              child: FulfillmentToggle(value: ordering.fulfillment, onChanged: _setFulfillment, height: 54),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: delivery ? _deliveryDetails(ordering, q) : _pickupDetails(store, q),
            ),
            _Section(
              title: 'Your details',
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Name for the order', prefixIcon: Icon(Icons.person_outline_rounded)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Add a name for the order' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: 'Mobile number', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                    validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'We need a number in case there’s a question' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'Email for your receipt (optional)', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  ),
                ],
              ),
            ),
            _Section(
              title: 'Payment',
              trailing: payments.demo && !payments.stripe ? const Tag('DEMO', color: AlsColors.orangeDeep) : null,
              child: Column(
                children: [
                  for (final m in methods)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MethodTile(method: m, selected: _method == m, onTap: () => setState(() => _method = m)),
                    ),
                ],
              ),
            ),
            if (q != null)
              _Section(
                title: 'Summary',
                child: _Summary(quote: q, delivery: delivery),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(_error),
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AlsColors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!, style: AlsText.body(14, color: AlsColors.red)),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AlsButton(
            label: _method == PayMethod.cash ? 'Place order' : 'Place order & pay',
            icon: Icons.lock_rounded,
            loading: _placing,
            onPressed: cart.isEmpty || cart.pricing ? null : _place,
            trailing: q == null
                ? null
                : AnimatedMoney(
                    q.totalCents,
                    style: AlsText.display(18, color: AlsColors.brown, weight: FontWeight.w600),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _pickupDetails(StoreInfo? store, PriceQuote? q) {
    final eta = q?.pickupEtaMinutes ?? store?.pickupEtaMinutes ?? 20;
    return Column(
      key: const ValueKey('pickup'),
      children: [
        _Section(
          title: 'Pickup from',
          action: 'Change',
          onAction: _changeStore,
          child: CardBox(
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, color: AlsColors.orangeDeep, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store?.shortName ?? 'Choose a store', style: AlsText.display(18)),
                      if (store != null) Text('${store.address.line1} · ${store.hoursToday}', style: AlsText.body(13, color: AlsColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _EtaCard(
          icon: Icons.local_fire_department_rounded,
          title: 'Ready in about $eta–${eta + 5} min',
          subtitle: 'Around ${clock(DateTime.now().add(Duration(minutes: eta)))} · we’ll text you when it’s out of the oven',
        ),
      ],
    );
  }

  Widget _deliveryDetails(OrderingStore ordering, PriceQuote? q) {
    final quote = ordering.quote;
    final sub = q?.subtotalCents ?? context.read<CartStore>().estimateCents;
    return Column(
      key: const ValueKey('delivery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Deliver to',
          action: ordering.address == null ? null : 'Change',
          onAction: _changeAddress,
          child: ordering.address == null
              ? AlsButton(label: 'Add delivery address', icon: Icons.add_location_alt_rounded, style: AlsButtonStyle.outline, onPressed: _changeAddress)
              : Column(
                  children: [
                    CardBox(
                      child: Row(
                        children: [
                          const Icon(Icons.place_rounded, color: AlsColors.orangeDeep, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ordering.address!.line1, style: AlsText.display(18)),
                                Text(
                                  [ordering.address!.city, ordering.address!.state, ordering.address!.zip].where((x) => x.isNotEmpty).join(', '),
                                  style: AlsText.body(13, color: AlsColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _apt,
                      decoration: const InputDecoration(hintText: 'Apt, suite or floor (optional)', prefixIcon: Icon(Icons.apartment_rounded)),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _instructions,
                      decoration: const InputDecoration(hintText: 'Drop-off notes, e.g. “ring buzzer 3”', prefixIcon: Icon(Icons.sticky_note_2_outlined)),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        if (ordering.quoting)
          const Skeleton(height: 84, radius: 24)
        else if (ordering.quoteError != null)
          CardBox(
            color: const Color(0xFFFFEDE8),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AlsColors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(ordering.quoteError!, style: AlsText.body(14, color: AlsColors.red)),
                ),
              ],
            ),
          )
        else if (quote != null)
          _EtaCard(
            icon: Icons.delivery_dining_rounded,
            title: 'Arrives in about ${q?.deliveryEtaMinutes ?? quote.etaMinutes}–${(q?.deliveryEtaMinutes ?? quote.etaMinutes) + 10} min',
            subtitle: 'Delivery fee ${money(quote.feeCents)}${(q?.minDeliveryCents ?? 0) > sub ? ' · ${money(q!.minDeliveryCents)} minimum' : ''}',
          ),
        _Section(
          title: 'Tip your driver',
          subtitle: '100% goes to your driver',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rate in const [0.0, 0.15, 0.18, 0.2])
                ChoicePill(
                  label: rate == 0 ? 'No tip' : '${(rate * 100).round()}%',
                  sublabel: rate == 0 ? null : money(((sub * rate) / 25).round() * 25),
                  selected: _tipRate == rate,
                  onTap: () {
                    setState(() => _tipRate = rate);
                    _refresh();
                  },
                ),
              ChoicePill(
                label: _tipRate == null ? money(_customTipCents) : 'Custom',
                selected: _tipRate == null,
                onTap: () async {
                  final cents = await _askTip(context);
                  if (cents == null) return;
                  setState(() {
                    _tipRate = null;
                    _customTipCents = cents;
                  });
                  _refresh();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<int?> _askTip(BuildContext context) {
    final c = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Custom tip', style: AlsText.display(22)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: r'$ ', hintText: '5.00'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ((double.tryParse(c.text) ?? 0) * 100).round().clamp(0, 20000)), child: const Text('Save')),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle, this.action, this.onAction, this.trailing});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: AlsText.display(20)),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(subtitle!, style: AlsText.body(12, color: AlsColors.muted)),
              ),
            ],
            const Spacer(),
            ?trailing,
            if (action != null)
              TextButton(
                onPressed: onAction,
                child: Text(
                  action!,
                  style: AlsText.body(14, color: AlsColors.orangeDeep, weight: FontWeight.w800),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Reveal(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF0CF), Color(0xFFFFE2A8)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Floaty(
            amplitude: 3,
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(color: AlsColors.orange, shape: BoxShape.circle),
              child: Icon(icon, color: AlsColors.brown, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AlsText.display(18)),
                const SizedBox(height: 2),
                Text(subtitle, style: AlsText.body(13, color: AlsColors.brownSoft)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, required this.selected, required this.onTap});

  final PayMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    scale: 0.98,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? AlsColors.orange : AlsColors.line, width: selected ? 2 : 1.5),
        boxShadow: selected ? alsShadow : null,
      ),
      child: Row(
        children: [
          Icon(method.icon, color: AlsColors.brown, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(method.label, style: AlsText.body(16, weight: FontWeight.w800)),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AlsColors.orange : Colors.transparent,
              border: Border.all(color: selected ? AlsColors.orange : AlsColors.line, width: 2),
            ),
            child: selected ? const Icon(Icons.check_rounded, size: 16, color: AlsColors.brown) : null,
          ),
        ],
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.quote, required this.delivery});

  final PriceQuote quote;
  final bool delivery;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int cents, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: AlsText.body(bold ? 17 : 15, weight: bold ? FontWeight.w900 : FontWeight.w700, color: color ?? AlsColors.ink),
          ),
          const Spacer(),
          AnimatedMoney(
            cents,
            style: bold ? AlsText.display(20) : AlsText.body(15, weight: FontWeight.w800, color: color ?? AlsColors.ink),
          ),
        ],
      ),
    );
    return CardBox(
      child: Column(
        children: [
          row('Subtotal', quote.subtotalCents),
          if (quote.discountCents > 0) row('Promo ${quote.promoCode ?? ''}', -quote.discountCents, color: AlsColors.basil),
          if (delivery) row('Delivery fee', quote.deliveryFeeCents),
          row('Tax', quote.taxCents),
          if (delivery) row('Driver tip', quote.tipCents),
          const Divider(height: 20),
          row('Total', quote.totalCents, bold: true),
          if (quote.promoError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(quote.promoError!, style: AlsText.body(13, color: AlsColors.red)),
            ),
        ],
      ),
    );
  }
}
