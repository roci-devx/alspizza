import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import 'router.dart';
import 'state/cart.dart';
import 'state/catalog.dart';
import 'state/ordering.dart';
import 'state/session.dart';

class AlsCustomerApp extends StatefulWidget {
  const AlsCustomerApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<AlsCustomerApp> createState() => _AlsCustomerAppState();
}

class _AlsCustomerAppState extends State<AlsCustomerApp> {
  late final session = SessionStore(widget.prefs);
  late final ordering = OrderingStore(widget.prefs, session.api);
  late final cart = CartStore(widget.prefs, session.api);
  late final catalog = CatalogStore(session.api);
  late final orders = OrdersStore(session.api, session.realtime);
  late final router = buildRouter(session);

  @override
  void initState() {
    super.initState();
    () async {
      try {
        await session.ensureSession();
        session.refreshUser();
        orders.refresh();
      } catch (_) {
        // API offline — screens show their own retry states.
      }
    }();
    catalog.load();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: ordering),
      ChangeNotifierProvider.value(value: cart),
      ChangeNotifierProvider.value(value: catalog),
      ChangeNotifierProvider.value(value: orders),
    ],
    child: MaterialApp.router(
      title: "Al's Pizza",
      debugShowCheckedModeBanner: false,
      theme: buildAlsTheme(),
      routerConfig: router,
      // Covers the whole screen so the nav-bar style survives screens with their own AppBar style.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(value: alsSystemBars, child: child!),
    ),
  );
}
