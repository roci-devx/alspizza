import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api.dart';
import '../../core/art/pizza_art.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';

/// Menu, deals and payment configuration from the API.
class CatalogStore extends ChangeNotifier {
  CatalogStore(this.api);

  final ApiClient api;
  MenuData? menu;
  List<Deal> deals = const [];
  PaymentSetup payments = const PaymentSetup(stripe: false, paypal: false, demo: true);

  /// One-tap demo login (only advertised by the API outside production).
  ({String email, String password})? demoCustomer;
  bool loading = false;
  String? error;
  Future<void>? _inflight;

  /// Callers that arrive mid-load share the request, so awaiting this always means the data is in.
  Future<void> load({bool force = false}) {
    if (menu != null && !force) return Future.value();
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<void> _fetch() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([api.get('/menu'), api.get('/deals'), api.get('/config')]);
      menu = MenuData.fromJson(results[0]);
      registerToppingArt(menu!.pizzaOptions.toppings.map((t) => (id: t.id, art: t.art)));
      deals = ((results[1]['deals'] as List?) ?? const []).map((e) => Deal.fromJson(e as Json)).toList();
      payments = PaymentSetup.fromJson(results[2]['payments'] as Json);
      final demo = (results[2]['demoAccounts'] as Json?)?['customer'] as Json?;
      demoCustomer = demo == null ? null : (email: demo['email'] as String, password: demo['password'] as String);
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// The customer's orders, with the newest active one kept live for the home banner.
class OrdersStore extends ChangeNotifier {
  OrdersStore(this.api, this.realtime);

  final ApiClient api;
  final RealtimeClient realtime;
  List<Order> orders = const [];
  bool loading = false;
  StreamSubscription<RealtimeEvent>? _sub;
  String? _watching;

  Order? get active => orders.where((o) => o.isActive).firstOrNull;
  Order? get lastCompleted => orders.where((o) => o.status == 'completed').firstOrNull;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final res = await api.get('/orders');
      orders = ((res['orders'] as List?) ?? const []).map((e) => Order.fromJson(e as Json)).toList();
      _watchActive();
    } catch (_) {
      // Offline is fine here; the list just stays as it was.
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void upsert(Order order) {
    final i = orders.indexWhere((o) => o.id == order.id);
    orders = i >= 0 ? ([...orders]..[i] = order) : [order, ...orders];
    _watchActive();
    notifyListeners();
  }

  void _watchActive() {
    final id = active?.id;
    if (id == _watching) return;
    _sub?.cancel();
    if (_watching != null) realtime.unsubscribe('order:$_watching');
    _watching = id;
    if (id == null) return;
    realtime.subscribe('order:$id');
    _sub = realtime.on('order:$id').listen((e) {
      if (e.event == 'order.updated') upsert(Order.fromJson(e.data as Json));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
