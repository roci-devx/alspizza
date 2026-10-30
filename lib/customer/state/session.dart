import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';

/// Who is ordering. Everyone gets a guest session automatically; creating an
/// account (optional — the X on the sign-up screen skips it) upgrades that guest
/// in place so earlier orders stay attached.
class SessionStore extends ChangeNotifier {
  SessionStore(this.prefs) {
    api.token = () => _token;
    final raw = prefs.getString(_userKey);
    _token = prefs.getString(_tokenKey);
    _user = raw == null ? null : AppUser.fromJson(jsonDecode(raw) as Json);
    onboarded = prefs.getBool(_onboardedKey) ?? false;
  }

  static const _tokenKey = 'session.token';
  static const _userKey = 'session.user';
  static const _onboardedKey = 'session.onboarded';

  final SharedPreferences prefs;
  final api = ApiClient();
  late final realtime = RealtimeClient(token: () => _token);

  String? _token;
  AppUser? _user;
  bool onboarded = false;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null && !_user!.isGuest;
  bool get hasSession => _token != null;

  Future<void> ensureSession() async {
    if (_token != null) return;
    final res = await api.post('/auth/guest', {'platform': AppConfig.platform});
    await _save(res);
  }

  Future<void> _save(Json res) async {
    _token = res['token'] as String;
    _user = AppUser.fromJson(res['user'] as Json);
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
    realtime.reconnect();
    notifyListeners();
  }

  Future<void> register({required String name, required String email, required String password, String? phone, String? marketingSource}) async {
    final res = await api.post('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'marketingSource': ?marketingSource,
      'platform': AppConfig.platform,
    });
    await _save(res);
  }

  Future<void> signIn(String email, String password) async {
    await _save(await api.post('/auth/login', {'email': email, 'password': password}));
  }

  Future<void> refreshUser() async {
    if (_token == null) return;
    try {
      final res = await api.get('/auth/me');
      _user = AppUser.fromJson(res['user'] as Json);
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) await signOut();
    }
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
    await ensureSession();
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    await prefs.setBool(_onboardedKey, true);
    notifyListeners();
  }
}
