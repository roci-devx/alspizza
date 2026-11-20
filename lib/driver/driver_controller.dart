import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../staff/ringer.dart';
import '../staff/staff_session.dart';
import 'driver_models.dart';

/// Driver app state: the shift, the queue, actions, the chime and location sharing.
class DriverController extends ChangeNotifier {
  DriverController(this.session);

  final StaffSession session;
  final ringer = Ringer();

  DriverState? state;
  bool loading = true;
  bool busy = false;
  String? error;

  /// Shown as a banner when location can't be shared (customers then see no moving pin).
  String? locationProblem;

  StreamSubscription<RealtimeEvent>? _sub;
  StreamSubscription<Position>? _gps;
  bool _tracking = false;
  Timer? _poll;
  Timer? _debounce;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  String? _channel;

  Future<void> start() async {
    _sub = session.realtime.all.listen(_onEvent);
    await refresh();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh(quiet: true));
  }

  Future<void> refresh({bool quiet = false}) async {
    try {
      _apply(await session.api.get('/driver/state'));
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

  void _apply(Json res) {
    state = DriverState.fromJson(res);
    if (_channel == null) {
      _channel = 'driver:${state!.userId}';
      session.realtime.subscribe(_channel!);
    }
    _syncTracking();
  }

  void _onEvent(RealtimeEvent e) {
    if (e.channel != _channel) return;
    if (e.event == 'driver.assigned') {
      ringer.ding();
      if (!kIsWeb) HapticFeedback.heavyImpact();
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => refresh(quiet: true));
  }

  /// Runs an action; returns an error message to show, or null when it worked.
  Future<String?> _act(Future<Json> Function() call) async {
    busy = true;
    notifyListeners();
    try {
      _apply(await call());
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> startShift() => _act(() => session.api.post('/driver/shift/start'));
  Future<String?> endShift() => _act(() => session.api.post('/driver/shift/end'));
  Future<String?> pickUp() => _act(() => session.api.post('/driver/pickup'));
  Future<String?> delivered(DriverDelivery d, {required bool cashCollected}) =>
      _act(() => session.api.post('/driver/deliveries/${d.id}/delivered', {'cashCollected': cashCollected}));
  Future<String?> reportProblem(DriverDelivery d, String reason) => _act(() => session.api.post('/driver/deliveries/${d.id}/problem', {'reason': reason}));

  // ── Location while on the clock ─────────────────────────────────────────────
  void _syncTracking() {
    final on = state?.onShift ?? false;
    if (on && !_tracking) _startTracking();
    if (!on && _tracking) _stopTracking();
    WakelockPlus.toggle(enable: on).catchError((Object _) {});
  }

  Future<void> _startTracking() async {
    _tracking = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _problem('Turn on location so customers can follow their order');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _problem('Allow location for Al’s Driver so customers can follow their order');
        return;
      }
      locationProblem = null;
      _gps = Geolocator.getPositionStream(locationSettings: _settings()).listen(_send, onError: (Object e) => _problem('Location stopped — tap to try again'));
      notifyListeners();
    } catch (e) {
      _problem('Location isn’t available on this device');
    }
  }

  void _problem(String message) {
    locationProblem = message;
    _tracking = false;
    notifyListeners();
  }

  /// Called from the banner after the driver fixes permissions.
  Future<void> retryLocation() async {
    await _stopTracking();
    _syncTracking();
  }

  Future<void> _stopTracking() async {
    _tracking = false;
    await _gps?.cancel();
    _gps = null;
  }

  LocationSettings _settings() {
    if (kIsWeb) return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 10),
        // Keeps sharing while the phone is in a pocket or another app (e.g. Maps) is open.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Al’s Driver — on the clock',
          notificationText: 'Sharing your location with customers while you deliver',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
  }

  Future<void> _send(Position p) async {
    if (DateTime.now().difference(_lastSent) < const Duration(seconds: 8)) return;
    _lastSent = DateTime.now();
    try {
      await session.api.post('/driver/location', {'lat': p.latitude, 'lng': p.longitude});
    } catch (_) {
      // Next fix will try again.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
    _gps?.cancel();
    if (_channel != null) session.realtime.unsubscribe(_channel!);
    WakelockPlus.disable().catchError((Object _) {});
    ringer.dispose();
    super.dispose();
  }
}
