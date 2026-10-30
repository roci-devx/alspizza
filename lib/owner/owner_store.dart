import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart' show DateTimeRange;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/realtime.dart';

class StoreRef {
  const StoreRef(this.id, this.name, this.timezone);
  final String id;
  final String name;
  final String timezone;
  String get shortName => name.contains('—') ? name.split('—').last.trim() : name;
}

enum RangePreset {
  today('Today', 0),
  yesterday('Yesterday', 1),
  week('7 days', 6),
  month('30 days', 29),
  quarter('90 days', 89),
  custom('Custom', 0);

  const RangePreset(this.label, this.days);
  final String label;
  final int days;
}

/// Owner session + the global filters (store, date range) every page shares.
class OwnerStore extends ChangeNotifier {
  OwnerStore(this.prefs) {
    _token = prefs.getString(_tokenKey);
    api.token = () => _token;
  }

  static const _tokenKey = 'owner.token';
  final SharedPreferences prefs;
  final api = ApiClient();
  late final realtime = RealtimeClient(token: () => _token);

  String? _token;
  String? ownerName;
  List<StoreRef> stores = const [];
  String storeId = 'all';
  RangePreset range = RangePreset.today;
  DateTimeRange? customRange;
  bool booting = true;

  bool get signedIn => _token != null;
  List<String> get storeIdsInScope => storeId == 'all' ? stores.map((s) => s.id).toList() : [storeId];
  StoreRef? get selectedStore => stores.where((s) => s.id == storeId).firstOrNull;

  ({String from, String to}) get dates {
    final f = DateFormat('yyyy-MM-dd');
    final today = DateTime.now();
    if (range == RangePreset.custom && customRange != null) return (from: f.format(customRange!.start), to: f.format(customRange!.end));
    if (range == RangePreset.yesterday) {
      final y = today.subtract(const Duration(days: 1));
      return (from: f.format(y), to: f.format(y));
    }
    return (from: f.format(today.subtract(Duration(days: range.days))), to: f.format(today));
  }

  String get rangeLabel => range == RangePreset.custom && customRange != null
      ? '${DateFormat('MMM d').format(customRange!.start)} – ${DateFormat('MMM d').format(customRange!.end)}'
      : range.label;

  Future<void> boot() async {
    if (_token != null) {
      try {
        await _loadMe();
      } on ApiException catch (e) {
        if (e.status == 401 || e.status == 403) await logout();
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> _loadMe() async {
    final res = await api.get('/owner/me');
    ownerName = (res['user'] as Json?)?['name'] as String?;
    stores = ((res['stores'] as List?) ?? const [])
        .map((s) => StoreRef((s as Json)['id'] as String, s['name'] as String, s['timezone'] as String? ?? 'America/Chicago'))
        .toList();
    for (final s in stores) {
      realtime.subscribe('store:${s.id}');
    }
  }

  Future<void> login(String email, String password) async {
    final res = await api.post('/auth/login', {'email': email, 'password': password});
    final user = res['user'] as Json;
    if (user['role'] != 'owner') throw const ApiException(403, 'This account isn’t an owner account.');
    _token = res['token'] as String;
    await prefs.setString(_tokenKey, _token!);
    realtime.reconnect();
    await _loadMe();
    notifyListeners();
  }

  /// Demo owner credentials, advertised by the API outside production.
  Future<({String email, String password})?> demoAccount() async {
    try {
      final owner = ((await api.get('/config'))['demoAccounts'] as Json?)?['owner'] as Json?;
      return owner == null ? null : (email: owner['email'] as String, password: owner['password'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _token = null;
    await prefs.remove(_tokenKey);
    realtime.reconnect();
    notifyListeners();
  }

  void setStore(String id) {
    storeId = id;
    notifyListeners();
  }

  void setRange(RangePreset preset, [DateTimeRange? custom]) {
    range = preset;
    customRange = custom;
    notifyListeners();
  }
}
