import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../staff/staff_login.dart';
import '../staff/staff_session.dart';
import 'kitchen_screen.dart';

class AlsKitchenApp extends StatefulWidget {
  const AlsKitchenApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<AlsKitchenApp> createState() => _AlsKitchenAppState();
}

class _AlsKitchenAppState extends State<AlsKitchenApp> {
  late final session = StaffSession(widget.prefs, StaffApp.kitchen);

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: session,
    child: MaterialApp(
      title: "Al's Kitchen",
      debugShowCheckedModeBanner: false,
      theme: buildAlsTheme(),
      builder: (context, child) => kIsWeb ? child! : AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: child!),
      home: Consumer<StaffSession>(
        builder: (context, s, _) => s.signedIn
            // Keyed by user so signing in as someone else starts a fresh board.
            ? KitchenScreen(key: ValueKey(s.userId))
            : const StaffLoginPage(
                title: 'Al’s Kitchen',
                subtitle: 'The kitchen tablet: new orders ring, tickets print, tap Done when it’s ready.',
                icon: Icons.soup_kitchen_rounded,
                accent: AlsColors.red,
              ),
      ),
    ),
  );
}
