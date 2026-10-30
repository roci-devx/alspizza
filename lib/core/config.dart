import 'package:flutter/foundation.dart';

/// Where the apps find the API.
///
/// Override with `--dart-define=API_URL=https://api.alspizza.com` (required on
/// physical phones, e.g. `http://192.168.1.20:4000`). Defaults: Android emulator
/// → 10.0.2.2, iOS simulator → localhost, web → same host as the page, port 4000.
abstract final class AppConfig {
  static const _apiUrl = String.fromEnvironment('API_URL');

  static String get apiUrl {
    if (_apiUrl.isNotEmpty) return _apiUrl.endsWith('/') ? _apiUrl.substring(0, _apiUrl.length - 1) : _apiUrl;
    if (kIsWeb) {
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      return 'http://$host:4000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  /// Photos uploaded through the owner app are stored as `/media/...` paths on the API.
  static String mediaUrl(String url) => url.startsWith('/') ? '$apiUrl$url' : url;

  static String get wsUrl => '${apiUrl.replaceFirst(RegExp('^http'), 'ws')}/ws';

  static String get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
