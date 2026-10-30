import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/catalog.dart';
import '../state/ordering.dart';
import '../state/session.dart';
import '../widgets/places.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final ordering = context.watch<OrderingStore>();
    final user = session.user;
    final signedIn = session.isSignedIn;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 180),
          children: [
            Text('Account', style: AlsText.display(30)),
            const SizedBox(height: 16),
            Reveal(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF8A3B1F), AlsColors.brown], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [BoxShadow(color: Color(0x445A210F), blurRadius: 20, offset: Offset(0, 10))],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AlsColors.orange,
                      child: signedIn
                          ? Text(user!.firstName.isEmpty ? '?' : user.firstName[0].toUpperCase(), style: AlsText.display(26, color: AlsColors.brown))
                          : const Icon(Icons.person_rounded, color: AlsColors.brown, size: 34),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(signedIn ? (user!.name ?? 'Pizza lover') : 'Ordering as a guest', style: AlsText.display(22, color: AlsColors.cream)),
                          const SizedBox(height: 2),
                          Text(
                            signedIn ? (user!.email ?? '') : 'Create an account to save favorites & get member deals.',
                            style: AlsText.body(13, color: AlsColors.cream.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!signedIn) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AlsButton(label: 'Create account', onPressed: () => context.push('/auth?from=account')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AlsButton(label: 'Sign in', style: AlsButtonStyle.outline, onPressed: () => context.push('/auth?mode=signin&from=account')),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Text('ORDERING', style: AlsText.label(12)),
            const SizedBox(height: 8),
            _Group(
              children: [
                _Row(
                  icon: Icons.storefront_rounded,
                  title: 'Your store',
                  value: ordering.store?.shortName ?? 'Not set',
                  onTap: () async {
                    final s = await pickStore(context);
                    if (s != null) await ordering.setStore(s);
                  },
                ),
                _Row(
                  icon: Icons.place_rounded,
                  title: 'Delivery address',
                  value: ordering.address?.line1 ?? 'Add one',
                  onTap: () async {
                    final a = await pickAddress(context);
                    if (a != null) await ordering.setAddress(a);
                  },
                ),
                _Row(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Pickup or delivery',
                  value: switch (ordering.fulfillment) {
                    Fulfillment.pickup => 'Pickup',
                    Fulfillment.delivery => 'Delivery',
                    null => 'Decide at checkout',
                  },
                  onTap: () => ordering.setFulfillment(ordering.isDelivery ? Fulfillment.pickup : Fulfillment.delivery),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text('HELP', style: AlsText.label(12)),
            const SizedBox(height: 8),
            _Group(
              children: [
                _Row(icon: Icons.receipt_long_rounded, title: 'Order history', onTap: () => context.go('/orders')),
                if (ordering.store != null)
                  _Row(icon: Icons.call_rounded, title: 'Call ${ordering.store!.shortName}', onTap: () => launchUrl(Uri.parse('tel:${ordering.store!.phone}'))),
                _Row(icon: Icons.refresh_rounded, title: 'Refresh menu', onTap: () => context.read<CatalogStore>().load(force: true)),
              ],
            ),
            if (signedIn) ...[
              const SizedBox(height: 22),
              AlsButton(label: 'Sign out', style: AlsButtonStyle.outline, icon: Icons.logout_rounded, onPressed: () => session.signOut()),
            ],
            const SizedBox(height: 26),
            Center(child: Opacity(opacity: 0.8, child: const AlsLogo(height: 70))),
            const SizedBox(height: 6),
            Center(
              child: Text('Al’s Pizza · v1.0.0', style: AlsText.body(12, color: AlsColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CardBox(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(indent: 60), c],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.value, this.onTap});

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: AlsColors.creamDeep, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: AlsColors.brown, size: 20),
    ),
    title: Text(title, style: AlsText.body(15, weight: FontWeight.w800)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              value!,
              overflow: TextOverflow.ellipsis,
              style: AlsText.body(13, color: AlsColors.muted),
            ),
          ),
        const Icon(Icons.chevron_right_rounded, color: AlsColors.muted),
      ],
    ),
  );
}
