import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'owner/owner_app.dart';

/// Owner dashboard: web (flutter run -d chrome -t lib/main_owner.dart) and the
/// native Android/iOS "Al's Owner" app in owner_app/.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(alsSystemBars);
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(AlsOwnerApp(prefs: prefs));
}
