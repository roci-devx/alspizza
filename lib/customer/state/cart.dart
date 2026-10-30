import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/models.dart';

/// The bag. Lines carry display prices; the server re-prices everything
/// (sizes, crusts, toppings, promo, tax, delivery fee) via [reprice].
class CartStore extends ChangeNotifier {
  CartStore(this.prefs, this.api) {
    final raw = prefs.getString(_linesKey);
    if (raw != null) {
      try {
        lines = (jsonDecode(raw) as List).map((e) => CartLine.fromJson(e as Json)).toList();
      } catch (_) {
        lines = [];
      }
    }
    promoCode = prefs.getString(_promoKey);
  }

  static const _linesKey = 'cart.lines';
  static const _promoKey = 'cart.promo';
  static const pendingOrderKey = 'cart.pendingOrder';

  final SharedPreferences prefs;
  final ApiClient api;

  List<CartLine> lines = [];
  String? promoCode;
  PriceQuote? priced;
  String? priceError;
  bool pricing = false;

  /// Increments on every add so the cart badge/bar can play a bounce.
  int bump = 0;
  Timer? _debounce;

  int get count => lines.fold(0, (s, l) => s + l.quantity);
  int get estimateCents => lines.fold(0, (s, l) => s + l.totalCents);
  bool get isEmpty => lines.isEmpty;

  void _persist() {
    prefs.setString(_linesKey, jsonEncode(lines.map((l) => l.toJson()).toList()));
    if (promoCode == null) {
      prefs.remove(_promoKey);
    } else {
      prefs.setString(_promoKey, promoCode!);
    }
  }

  void add(CartLine line) {
    final i = lines.indexWhere((l) => l.signature == line.signature);
    if (i >= 0) {
      lines[i] = lines[i].copyWith(quantity: (lines[i].quantity + line.quantity).clamp(1, 25));
    } else {
      lines = [...lines, line];
    }
    bump++;
    priced = null;
    _persist();
    notifyListeners();
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) {
      remove(key);
      return;
    }
    lines = [for (final l in lines) l.key == key ? l.copyWith(quantity: quantity.clamp(1, 25)) : l];
    priced = null;
    _persist();
    notifyListeners();
  }

  CartLine? remove(String key) {
    final removed = lines.where((l) => l.key == key).firstOrNull;
    lines = lines.where((l) => l.key != key).toList();
    priced = null;
    _persist();
    notifyListeners();
    return removed;
  }

  void restore(CartLine line, int index) {
    lines = [...lines]..insert(index.clamp(0, lines.length), line);
    _persist();
    notifyListeners();
  }

  void setPromo(String? code) {
    promoCode = code?.trim().toUpperCase();
    if (promoCode?.isEmpty ?? false) promoCode = null;
    _persist();
    notifyListeners();
  }

  void clear() {
    lines = [];
    promoCode = null;
    priced = null;
    _persist();
    notifyListeners();
  }

  /// Server pricing for the current cart (debounced so steppers don't spam the API).
  Future<PriceQuote?> reprice({required String storeId, String? fulfillment, String? deliveryQuoteId, int tipCents = 0, bool immediate = false}) {
    final done = Completer<PriceQuote?>();
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 350), () async {
      if (lines.isEmpty) {
        priced = null;
        notifyListeners();
        return done.complete(null);
      }
      pricing = true;
      notifyListeners();
      try {
        final res = await api.post('/cart/price', {
          'storeId': storeId,
          'items': lines.map((l) => l.toApi()).toList(),
          'fulfillment': ?fulfillment,
          'promoCode': ?promoCode,
          'deliveryQuoteId': ?deliveryQuoteId,
          'tipCents': tipCents,
        });
        priced = PriceQuote.fromJson(res);
        priceError = null;
        // Keep display prices in sync with what the server charges.
        for (var i = 0; i < lines.length && i < priced!.lineSummaries.length; i++) {
          final s = priced!.lineSummaries[i];
          lines[i] = lines[i].copyWith(unitPriceCents: s.unitPriceCents, summary: s.summary);
        }
        _persist();
        done.complete(priced);
      } on ApiException catch (e) {
        priceError = e.message;
        done.complete(null);
      } finally {
        pricing = false;
        notifyListeners();
      }
    });
    return done.future;
  }
}
