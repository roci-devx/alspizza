import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/models.dart';

enum Fulfillment { pickup, delivery }

/// The ordering context: which store, pickup vs delivery (may stay undecided
/// until checkout), and the delivery address + live delivery quote.
class OrderingStore extends ChangeNotifier {
  OrderingStore(this.prefs, this.api) {
    final s = prefs.getString(_storeKey);
    final a = prefs.getString(_addressKey);
    final f = prefs.getString(_fulfillmentKey);
    store = s == null ? null : StoreInfo.fromJson(jsonDecode(s) as Json);
    address = a == null ? null : PlaceAddress.fromJson(jsonDecode(a) as Json);
    fulfillment = Fulfillment.values.where((v) => v.name == f).firstOrNull;
  }

  static const _storeKey = 'ordering.store';
  static const _addressKey = 'ordering.address';
  static const _fulfillmentKey = 'ordering.fulfillment';

  final SharedPreferences prefs;
  final ApiClient api;

  StoreInfo? store;
  Fulfillment? fulfillment;
  PlaceAddress? address;
  DeliveryQuote? quote;
  String? quoteError;
  bool quoting = false;
  List<StoreInfo> nearby = const [];
  ({double lat, double lng})? here;

  bool get isDelivery => fulfillment == Fulfillment.delivery;

  Future<List<StoreInfo>> loadStores({double? lat, double? lng}) async {
    final res = await api.get('/stores', query: {'lat': lat?.toString(), 'lng': lng?.toString()});
    nearby = ((res['stores'] as List?) ?? const []).map((e) => StoreInfo.fromJson(e as Json)).toList();
    if (lat != null && lng != null) here = (lat: lat, lng: lng);
    notifyListeners();
    return nearby;
  }

  /// Asks for the device location. Returns null (with a friendly reason) when it can't.
  Future<({double lat, double lng})?> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw const ApiException(0, 'Turn on location services, or type your address instead.');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const ApiException(0, 'No worries — type your address and we’ll find the closest Al’s.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
    );
    here = (lat: pos.latitude, lng: pos.longitude);
    return here;
  }

  Future<PlaceAddress?> reverse(double lat, double lng) async {
    final res = await api.get('/geo/reverse', query: {'lat': '$lat', 'lng': '$lng'});
    final r = res['result'] as Json?;
    return r == null ? null : PlaceAddress.fromJson(r);
  }

  Future<List<PlaceAddress>> search(String q) async {
    final res = await api.get(
      '/geo/search',
      query: {'q': q, 'lat': here?.lat.toString() ?? store?.lat.toString(), 'lng': here?.lng.toString() ?? store?.lng.toString()},
    );
    return ((res['results'] as List?) ?? const []).map((e) => PlaceAddress.fromJson(e as Json)).toList();
  }

  Future<void> setStore(StoreInfo s) async {
    store = s;
    quote = null;
    await prefs.setString(_storeKey, jsonEncode(s.toJson()));
    notifyListeners();
  }

  Future<void> setFulfillment(Fulfillment? f) async {
    fulfillment = f;
    if (f == null) {
      await prefs.remove(_fulfillmentKey);
    } else {
      await prefs.setString(_fulfillmentKey, f.name);
    }
    notifyListeners();
  }

  Future<void> setAddress(PlaceAddress a) async {
    address = a;
    quote = null;
    quoteError = null;
    await prefs.setString(_addressKey, jsonEncode(a.toJson()));
    notifyListeners();
  }

  /// Delivery fee + ETA for the current address. Quotes expire, so callers refresh before placing an order.
  Future<DeliveryQuote?> refreshQuote({required int subtotalCents, String? name, String? phone}) async {
    final s = store;
    final a = address;
    if (s == null || a == null) return null;
    quoting = true;
    quoteError = null;
    notifyListeners();
    try {
      final res = await api.post('/delivery/quote', {
        'storeId': s.id,
        'address': a.toJson(),
        'subtotalCents': subtotalCents,
        if (name != null && name.isNotEmpty) 'customerName': name,
        if (phone != null && phone.isNotEmpty) 'customerPhone': phone,
      });
      quote = DeliveryQuote.fromJson(res);
      if (a.lat == null) {
        address = quote!.address.copyWith(line2: a.line2, instructions: a.instructions);
        await prefs.setString(_addressKey, jsonEncode(address!.toJson()));
      }
      return quote;
    } on ApiException catch (e) {
      quote = null;
      quoteError = e.message;
      return null;
    } finally {
      quoting = false;
      notifyListeners();
    }
  }
}
