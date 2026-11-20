import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'driver/driver_app.dart';

/// Al's Driver — the in-house drivers' phone app. Native app in driver_app/, or on the web:
/// flutter run -d chrome -t lib/main_driver.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(alsSystemBars);
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(AlsDriverApp(prefs: prefs));
}
