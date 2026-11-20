import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/realtime.dart';

enum StaffApp { kitchen, driver }

/// Sign-in shared by Al's Kitchen and Al's Driver: email or phone + the password the owner set.
class StaffSession extends ChangeNotifier {
  StaffSession(this.prefs, this.app) {
    _token = prefs.getString(_key);
    final saved = prefs.getString('$_key.user');
    if (_token != null && saved != null) _readUser(jsonDecode(saved) as Json);
    api.token = () => _token;
  }

  final SharedPreferences prefs;
  final StaffApp app;
  final api = ApiClient();
  late final realtime = RealtimeClient(token: () => _token);

  String get _key => '${app.name}.token';
  String? _token;
  String? userId;
  String? userName;
  String? role;
  String? storeId;

  bool get signedIn => _token != null;

  void _readUser(Json u) {
    userId = u['id'] as String?;
    userName = u['name'] as String?;
    role = u['role'] as String?;
    storeId = u['storeId'] as String?;
  }

  Future<void> login(String login, String password) async {
    final res = await api.post('/staff/login', {'login': login.trim(), 'password': password, 'app': app.name});
    final user = res['user'] as Json;
    _token = res['token'] as String;
    _readUser(user);
    await prefs.setString(_key, _token!);
    await prefs.setString('$_key.user', jsonEncode(user));
    realtime.reconnect();
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    userId = userName = role = storeId = null;
    await prefs.remove(_key);
    await prefs.remove('$_key.user');
    realtime.reconnect();
    notifyListeners();
  }

  /// One-tap demo login the API advertises on test servers.
  Future<({String email, String password})?> demoAccount() async {
    try {
      final demo = ((await api.get('/config'))['demoAccounts'] as Json?)?[app.name] as Json?;
      return demo == null ? null : (email: demo['email'] as String, password: demo['password'] as String);
    } catch (_) {
      return null;
    }
  }
}
