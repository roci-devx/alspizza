import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kitchen/kitchen_app.dart';

/// Al's Kitchen — the kitchen tablet. Native app in kitchen_app/, or on the web:
/// flutter run -d chrome -t lib/main_kitchen.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final prefs = await SharedPreferences.getInstance();
  runApp(AlsKitchenApp(prefs: prefs));
}
