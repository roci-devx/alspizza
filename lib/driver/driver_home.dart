import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/ui.dart';
import '../staff/staff_session.dart';
import 'delivery_screen.dart';
import 'driver_controller.dart';
import 'driver_models.dart';

/// Al's Driver home: clock in/out, what's on the road, and the queue (oldest first).
class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  late final DriverController _c = DriverController(context.read<StaffSession>())..start();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _c,
    child: Consumer<DriverController>(
      builder: (context, c, _) {
        final s = c.state;
        return Scaffold(
          backgroundColor: AlsColors.cream,
          appBar: AppBar(
            backgroundColor: AlsColors.cream,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Al’s Driver', style: AlsText.display(22)),
                if (s?.storeName != null) Text(s!.storeName!, style: AlsText.body(12, color: AlsColors.muted)),
              ],
            ),
            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: c.session.realtime.connected,
                builder: (context, live, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: live ? AlsColors.success : AlsColors.red, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(live ? 'Live' : 'Offline', style: AlsText.body(12, color: AlsColors.muted, weight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'refresh') await c.refresh();
                  if (v == 'logout' && context.mounted) await _signOut(context, c);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  PopupMenuItem(value: 'logout', child: Text('Sign out')),
                ],
              ),
            ],
          ),
          body: c.loading && s == null
              ? const Center(child: CircularProgressIndicator(color: AlsColors.orange))
              : s == null
              ? _ErrorView(message: c.error ?? 'Couldn’t load your shift', onRetry: c.refresh)
              : RefreshIndicator(
                  color: AlsColors.orange,
                  onRefresh: c.refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (c.locationProblem != null && s.onShift) _LocationBanner(c),
                      if (!s.onShift) _OffShift(s: s, c: c) else ..._onShift(context, s, c),
                    ],
                  ),
                ),
        );
      },
    ),
  );

  List<Widget> _onShift(BuildContext context, DriverState s, DriverController c) => [
    _ShiftCard(s: s, c: c),
    const SizedBox(height: 18),
    _SectionTitle('On the road', '${s.run.length} of ${s.maxActive}'),
    if (s.run.isEmpty)
      const _Empty('Nothing in the car. Ready orders from your queue show up below.')
    else
      for (final d in s.run) _DeliveryCard(d: d, onTap: () => _open(context, d)),
    if (s.readyToTake > 0) ...[
      const SizedBox(height: 10),
      AlsButton(
        label: s.readyToTake == 1 ? 'Pick up the next order' : 'Pick up the next ${s.readyToTake} orders',
        icon: Icons.shopping_bag_rounded,
        loading: c.busy,
        onPressed: () => _run(context, c.pickUp),
      ),
    ],
    const SizedBox(height: 22),
    _SectionTitle('Your queue', '${s.queue.length} of ${s.maxBacklog} · oldest first'),
    if (s.queue.isEmpty)
      const _Empty('No orders waiting for you. Keep the app open — it chimes when one is yours.')
    else
      for (final (i, d) in s.queue.indexed) _QueueTile(position: i + 1, d: d, onTap: () => _open(context, d)),
    if (s.waitingAtStore > 0) ...[
      const SizedBox(height: 14),
      Text(
        '${s.waitingAtStore} more order${s.waitingAtStore == 1 ? ' is' : 's are'} waiting at the store for a driver with room.',
        style: AlsText.body(13, color: AlsColors.muted),
      ),
    ],
  ];

  void _open(BuildContext context, DriverDelivery d) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider.value(value: _c, child: DeliveryScreen(deliveryId: d.id)),
    ),
  );
}

Future<void> _run(BuildContext context, Future<String?> Function() action) async {
  final error = await action();
  if (error != null && context.mounted) showError(context, error);
}

Future<void> _signOut(BuildContext context, DriverController c) async {
  final s = c.state;
  if (s?.onShift ?? false) {
    showToast(context, 'End your shift first, then sign out', icon: Icons.info_outline_rounded);
    return;
  }
  await c.session.logout();
}

class _OffShift extends StatelessWidget {
  const _OffShift({required this.s, required this.c});

  final DriverState s;
  final DriverController c;

  @override
  Widget build(BuildContext context) {
    final owes = s.cashOwedCents > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi ${s.name.split(' ').first}', style: AlsText.display(28)),
              const SizedBox(height: 4),
              Text('You’re off the clock.', style: AlsText.body(16, color: AlsColors.muted)),
              const SizedBox(height: 16),
              _Fact(Icons.delivery_dining_rounded, 'Up to ${s.maxActive} orders on the road at once'),
              _Fact(Icons.format_list_numbered_rounded, 'Up to ${s.maxBacklog} waiting in your queue'),
              _Fact(Icons.payments_rounded, s.cashEnabled ? 'You take cash-on-delivery orders' : 'Card-paid orders only (no cash)'),
              if (s.vehicle != null) _Fact(Icons.directions_car_rounded, s.vehicle!),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (owes)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AlsColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.payments_rounded, color: AlsColors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Hand in ${money(s.cashOwedCents)} cash from your last shift to the owner. You can start once they mark it settled.',
                    style: AlsText.body(14, color: AlsColors.red, weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        if (!s.isActive)
          Text('Your account is switched off. Talk to the owner.', style: AlsText.body(15, color: AlsColors.red))
        else
          AlsButton(
            label: owes ? 'Check again' : 'Start shift',
            icon: owes ? Icons.refresh_rounded : Icons.play_arrow_rounded,
            loading: c.busy,
            onPressed: owes ? () => c.refresh() : () => _run(context, c.startShift),
          ),
        const SizedBox(height: 12),
        Text(
          'While you’re on the clock the app shares your location so customers can follow their order. It stops when you end your shift.',
          textAlign: TextAlign.center,
          style: AlsText.body(12, color: AlsColors.muted),
        ),
      ],
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.s, required this.c});

  final DriverState s;
  final DriverController c;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF5A210F), Color(0xFF3B1508)]),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On the clock', style: AlsText.display(22, color: AlsColors.cream)),
              Text('since ${clock(s.shiftStartedAt!)}', style: AlsText.body(13, color: AlsColors.orangeLight)),
              if (s.cashEnabled) ...[
                const SizedBox(height: 6),
                Text('Cash collected: ${money(s.cashCollectedCents)}', style: AlsText.body(14, color: AlsColors.cream, weight: FontWeight.w800)),
              ],
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AlsColors.cream, backgroundColor: Colors.white.withValues(alpha: 0.12)),
          onPressed: c.busy
              ? null
              : () async {
                  final cash = s.cashCollectedCents;
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('End your shift?'),
                      content: Text(
                        cash > 0
                            ? 'Hand ${money(cash)} cash to the owner before you go — you can’t start your next shift until it’s settled.'
                            : 'Orders still in your queue go back to the store for another driver.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep driving')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End shift')),
                      ],
                    ),
                  );
                  if (yes == true && context.mounted) await _run(context, c.endShift);
                },
          child: const Text('End shift'),
        ),
      ],
    ),
  );
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.d, required this.onTap});

  final DriverDelivery d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${d.number}', style: AlsText.display(22)),
                        const SizedBox(width: 8),
                        if (d.collectsCash) _Pill('COLLECT ${money(d.cashDueCents)}', AlsColors.red) else const _Pill('PAID', AlsColors.success),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(d.customerName, style: AlsText.body(15, weight: FontWeight.w800)),
                    if (d.address != null) Text(d.address!.full, style: AlsText.body(14, color: AlsColors.brownSoft)),
                    if (d.problem != null) Text('Reported: ${d.problem}', style: AlsText.body(13, color: AlsColors.red, weight: FontWeight.w800)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AlsColors.muted, size: 30),
            ],
          ),
        ),
      ),
    ),
  );
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.position, required this.d, required this.onTap});

  final int position;
  final DriverDelivery d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: d.ready ? AlsColors.success : AlsColors.creamDeep,
                child: Text('$position', style: AlsText.body(14, color: d.ready ? Colors.white : AlsColors.brown, weight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${d.number} · ${d.customerName}', style: AlsText.body(15, weight: FontWeight.w800)),
                    Text(d.kitchenLabel, style: AlsText.body(13, color: d.ready ? AlsColors.success : AlsColors.muted, weight: FontWeight.w700)),
                  ],
                ),
              ),
              if (d.collectsCash) _Pill('CASH ${money(d.cashDueCents)}', AlsColors.red),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner(this.c);

  final DriverController c;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AlsColors.cheese.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        const Icon(Icons.location_off_rounded, color: AlsColors.brown),
        const SizedBox(width: 10),
        Expanded(child: Text(c.locationProblem!, style: AlsText.body(13, weight: FontWeight.w800))),
        TextButton(
          onPressed: () async {
            await Geolocator.openAppSettings().catchError((Object _) => false);
            await c.retryLocation();
          },
          child: const Text('Fix'),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: AlsText.display(20)),
        const SizedBox(width: 8),
        Text(detail, style: AlsText.body(13, color: AlsColors.muted, weight: FontWeight.w700)),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
    child: Text(text, style: AlsText.body(14, color: AlsColors.muted)),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AlsColors.orangeDeep),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AlsText.body(14))),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: AlsText.body(11, color: Colors.white, weight: FontWeight.w900)),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center, style: AlsText.body(15)),
          const SizedBox(height: 12),
          AlsButton(label: 'Try again', expand: false, onPressed: onRetry),
        ],
      ),
    ),
  );
}
