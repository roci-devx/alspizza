import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../staff/staff_login.dart';
import '../staff/staff_session.dart';
import 'driver_home.dart';

class AlsDriverApp extends StatefulWidget {
  const AlsDriverApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<AlsDriverApp> createState() => _AlsDriverAppState();
}

class _AlsDriverAppState extends State<AlsDriverApp> {
  late final session = StaffSession(widget.prefs, StaffApp.driver);

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: session,
    child: MaterialApp(
      title: "Al's Driver",
      debugShowCheckedModeBanner: false,
      theme: buildAlsTheme(),
      builder: (context, child) => kIsWeb ? child! : AnnotatedRegion<SystemUiOverlayStyle>(value: alsSystemBars, child: child!),
      home: Consumer<StaffSession>(
        builder: (context, s, _) => s.signedIn
            ? DriverHome(key: ValueKey(s.userId))
            : const StaffLoginPage(
                title: 'Al’s Driver',
                subtitle: 'Clock in, get your deliveries in order, and tap Delivered at the door.',
                icon: Icons.delivery_dining_rounded,
                accent: AlsColors.basil,
              ),
      ),
    ),
  );
}
