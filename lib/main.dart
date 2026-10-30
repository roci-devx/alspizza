import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'customer/app.dart';

/// Customer ordering app (iOS, Android, web). The owner dashboard lives in main_owner.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars so the cream background runs edge to edge (screens use SafeArea).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(alsSystemBars);
  final prefs = await SharedPreferences.getInstance();
  runApp(AlsCustomerApp(prefs: prefs));
}
