import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/theme.dart';
import '../core/widgets/ui.dart';
import 'owner_store.dart';
import 'screens/customers_page.dart';
import 'screens/dashboard_page.dart';
import 'screens/live_orders_page.dart';
import 'screens/login_page.dart';
import 'screens/menu_page.dart';
import 'screens/promos_page.dart';
import 'screens/reports_page.dart';
import 'screens/settings_page.dart';
import 'widgets/owner_ui.dart';

class AlsOwnerApp extends StatefulWidget {
  const AlsOwnerApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<AlsOwnerApp> createState() => _AlsOwnerAppState();
}

class _AlsOwnerAppState extends State<AlsOwnerApp> {
  late final store = OwnerStore(widget.prefs)..boot();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: store,
    child: MaterialApp(
      title: "Al's Pizza · Owner",
      debugShowCheckedModeBanner: false,
      theme: buildAlsTheme().copyWith(scaffoldBackgroundColor: const Color(0xFFF7F1E5)),
      // Native builds (Android/iOS owner app) draw edge to edge like the customer app.
      builder: (context, child) => kIsWeb ? child! : AnnotatedRegion<SystemUiOverlayStyle>(value: alsSystemBars, child: child!),
      home: Consumer<OwnerStore>(
        builder: (context, s, _) {
          if (s.booting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: AlsColors.orange)),
            );
          }
          return AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: s.signedIn ? const OwnerShell() : const LoginPage());
        },
      ),
    ),
  );
}

enum OwnerPage {
  dashboard('Dashboard', Icons.space_dashboard_rounded),
  orders('Live orders', Icons.local_fire_department_rounded),
  menu('Menu', Icons.restaurant_menu_rounded),
  promos('Promo codes', Icons.local_offer_rounded),
  customers('Customers', Icons.people_alt_rounded),
  reports('Reports', Icons.table_chart_rounded),
  settings('Settings', Icons.tune_rounded);

  const OwnerPage(this.label, this.icon);
  final String label;
  final IconData icon;
}

class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key});

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  OwnerPage _page = OwnerPage.dashboard;
  int _newOrders = 0;
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final realtime = context.read<OwnerStore>().realtime;
    _sub = realtime.all.listen((e) {
      if (!mounted) return;
      if (e.event == 'order.new') {
        final number = (e.data as Json)['number'];
        if (_page != OwnerPage.orders) setState(() => _newOrders++);
        if (!kIsWeb) HapticFeedback.heavyImpact();
        showToast(context, 'New order #$number just came in', icon: Icons.notifications_active_rounded);
      } else if (e.event == 'alert') {
        showToast(context, (e.data as Json)['message'] as String? ?? 'Heads up', icon: Icons.warning_amber_rounded);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _go(OwnerPage p) => setState(() {
    _page = p;
    if (p == OwnerPage.orders) _newOrders = 0;
  });

  static const _phoneTabs = [OwnerPage.dashboard, OwnerPage.orders, OwnerPage.menu, OwnerPage.reports];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final phone = isCompact(context);
    final body = switch (_page) {
      OwnerPage.dashboard => const DashboardPage(),
      OwnerPage.orders => const LiveOrdersPage(),
      OwnerPage.menu => const MenuPage(),
      OwnerPage.promos => const PromosPage(),
      OwnerPage.customers => const CustomersPage(),
      OwnerPage.reports => const ReportsPage(),
      OwnerPage.settings => const SettingsPage(),
    };
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.015, 0), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_page), child: body),
    );
    if (phone) {
      // Phone: app bar + bottom tabs; everything else lives under "More".
      final tabIndex = _phoneTabs.contains(_page) ? _phoneTabs.indexOf(_page) : _phoneTabs.length;
      return Scaffold(
        appBar: AppBar(
          title: Text(_page.label),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: context.read<OwnerStore>().realtime.connected,
              builder: (context, live, _) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: live ? AlsColors.success : AlsColors.muted, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      live ? 'Live' : 'Offline',
                      style: AlsText.body(12, color: AlsColors.muted, weight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tabIndex,
          backgroundColor: Colors.white,
          indicatorColor: AlsColors.orange.withValues(alpha: 0.25),
          onDestinationSelected: (i) => i < _phoneTabs.length ? _go(_phoneTabs[i]) : _more(),
          destinations: [
            for (final p in _phoneTabs)
              NavigationDestination(
                icon: Badge(isLabelVisible: p == OwnerPage.orders && _newOrders > 0, label: Text('$_newOrders'), child: Icon(p.icon)),
                label: p == OwnerPage.orders ? 'Orders' : p.label,
              ),
            const NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
          ],
        ),
      );
    }
    final sidebar = _Sidebar(page: _page, onSelect: _go, badge: _newOrders);
    return Scaffold(
      drawer: wide ? null : Drawer(backgroundColor: AlsColors.brown, child: sidebar),
      appBar: wide ? null : AppBar(title: Text(_page.label)),
      body: Row(
        children: [
          if (wide) SizedBox(width: 248, child: sidebar),
          Expanded(child: content),
        ],
      ),
    );
  }

  Future<void> _more() async {
    final store = context.read<OwnerStore>();
    final picked = await showModalBottomSheet<OwnerPage>(
      context: context,
      backgroundColor: AlsColors.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: AlsColors.line, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 8),
            for (final p in const [OwnerPage.promos, OwnerPage.customers, OwnerPage.settings])
              ListTile(
                leading: Icon(p.icon, color: AlsColors.brown),
                title: Text(p.label, style: AlsText.body(15, weight: FontWeight.w800)),
                onTap: () => Navigator.pop(ctx, p),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AlsColors.red),
              title: Text(
                'Sign out${store.ownerName != null ? ' (${store.ownerName})' : ''}',
                style: AlsText.body(15, color: AlsColors.red, weight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.pop(ctx);
                store.logout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) _go(picked);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.page, required this.onSelect, required this.badge});

  final OwnerPage page;
  final ValueChanged<OwnerPage> onSelect;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OwnerStore>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF5A210F), Color(0xFF3B1508)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AlsColors.cream, borderRadius: BorderRadius.circular(14)),
                    child: const AlsLogo(height: 44),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Al's Pizza", style: AlsText.display(19, color: AlsColors.cream)),
                      Text('Owner dashboard', style: AlsText.body(12, color: AlsColors.orangeLight)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            for (final p in OwnerPage.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: TapScale(
                  scale: 0.98,
                  onTap: () {
                    onSelect(p);
                    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: p == page ? AlsColors.orange : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Icon(p.icon, size: 20, color: p == page ? AlsColors.brown : AlsColors.cream.withValues(alpha: 0.8)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.label,
                            style: AlsText.body(14, color: p == page ? AlsColors.brown : AlsColors.cream, weight: FontWeight.w800),
                          ),
                        ),
                        if (p == OwnerPage.orders && badge > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AlsColors.red, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              '$badge',
                              style: AlsText.body(12, color: Colors.white, weight: FontWeight.w900),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: store.realtime.connected,
              builder: (context, live, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: live ? const Color(0xFF7BD389) : AlsColors.muted, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(live ? 'Live updates on' : 'Reconnecting…', style: AlsText.body(12, color: AlsColors.cream.withValues(alpha: 0.75))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: Colors.white.withValues(alpha: 0.06),
                leading: CircleAvatar(
                  backgroundColor: AlsColors.orange,
                  child: Text((store.ownerName ?? 'A')[0], style: AlsText.display(16, color: AlsColors.brown)),
                ),
                title: Text(
                  store.ownerName ?? 'Owner',
                  style: AlsText.body(14, color: AlsColors.cream, weight: FontWeight.w800),
                ),
                subtitle: Text('Sign out', style: AlsText.body(12, color: AlsColors.orangeLight)),
                onTap: store.logout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
