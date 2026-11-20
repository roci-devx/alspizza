import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/realtime.dart';
import '../staff/ringer.dart';
import '../staff/staff_session.dart';

/// The kitchen tablet's live board. New orders ring until someone taps them.
class KitchenController extends ChangeNotifier {
  KitchenController(this.session);

  final StaffSession session;
  final ringer = Ringer();

  List<Order> orders = const [];
  String? storeId;
  String storeName = '';
  List<({String id, String name})> stores = const []; // owner only: switch store
  bool loading = true;
  String? error;

  /// New orders nobody has tapped yet (they keep the chime going).
  final unacknowledged = <String>{};
  final _seen = <String>{};
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _poll;
  String? _channel;

  List<Order> get newOrders => _by('received');
  List<Order> get cooking => _by('preparing');
  List<Order> get ready => _by('ready');

  List<Order> _by(String status) =>
      orders.where((o) => o.status == status).toList()..sort((a, b) => (a.paidAt ?? a.createdAt).compareTo(b.paidAt ?? b.createdAt));

  Future<void> start() async {
    _sub = session.realtime.all.listen(_onEvent);
    await refresh();
    // Safety net in case a live update is missed (Wi-Fi blips etc.).
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => refresh(quiet: true));
  }

  Future<void> refresh({bool quiet = false}) async {
    try {
      final res = await session.api.get('/kitchen/state', query: {'storeId': storeId});
      final store = res['store'] as Json;
      storeId = store['id'] as String;
      storeName = store['name'] as String? ?? '';
      stores = ((res['stores'] as List?) ?? const []).map((s) => (id: (s as Json)['id'] as String, name: s['name'] as String)).toList();
      orders = ((res['orders'] as List?) ?? const []).map((o) => Order.fromJson(o as Json)).toList();
      _listen('store:$storeId');
      for (final o in orders) {
        _track(o);
      }
      unacknowledged.removeWhere((id) => !orders.any((o) => o.id == id && o.status == 'received'));
      _updateRing();
      error = null;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await session.logout();
        return;
      }
      if (!quiet) error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _listen(String channel) {
    if (_channel == channel) return;
    if (_channel != null) session.realtime.unsubscribe(_channel!);
    _channel = channel;
    session.realtime.subscribe(channel);
  }

  void _track(Order o) {
    if (_seen.add(o.id) && o.status == 'received') unacknowledged.add(o.id);
    if (o.status != 'received') unacknowledged.remove(o.id);
  }

  void _onEvent(RealtimeEvent e) {
    if (e.channel != _channel || (e.event != 'order.updated' && e.event != 'order.new')) return;
    final o = Order.fromJson(e.data as Json);
    if (o.status == 'pending_payment') return;
    final i = orders.indexWhere((x) => x.id == o.id);
    orders = i == -1 ? [...orders, o] : ([...orders]..[i] = o);
    _track(o);
    _updateRing();
    notifyListeners();
  }

  void _updateRing() => unacknowledged.isEmpty ? ringer.stop() : ringer.ring();

  void acknowledge(String id) {
    if (unacknowledged.remove(id)) {
      _updateRing();
      notifyListeners();
    }
  }

  Future<void> setStatus(Order order, String status) async {
    acknowledge(order.id);
    final res = await session.api.patch('/kitchen/orders/${order.id}/status', {'status': status});
    final updated = Order.fromJson(res['order'] as Json);
    orders = [for (final o in orders) o.id == updated.id ? updated : o];
    notifyListeners();
  }

  Future<void> switchStore(String id) async {
    storeId = id;
    unacknowledged.clear();
    _seen.clear();
    loading = true;
    notifyListeners();
    await refresh();
  }

  Future<void> setMuted(bool muted) async {
    await ringer.setMuted(muted);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    if (_channel != null) session.realtime.unsubscribe(_channel!);
    ringer.dispose();
    super.dispose();
  }
}
