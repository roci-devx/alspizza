import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class DriverItem {
  const DriverItem(this.name, this.quantity, this.summary);
  final String name;
  final int quantity;
  final String summary;
}

/// One order in a driver's queue or on the road.
class DriverDelivery {
  const DriverDelivery({
    required this.id,
    required this.orderId,
    required this.number,
    required this.ready,
    required this.onTheRoad,
    required this.orderStatus,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.itemsCount,
    required this.totalCents,
    required this.tipCents,
    required this.cashDueCents,
    this.address,
    this.notes,
    this.estimatedReadyAt,
    this.pickedUpAt,
    this.problem,
  });

  final String id;
  final String orderId;
  final int number;
  final bool ready;
  final bool onTheRoad;
  final String orderStatus;
  final String customerName;
  final String customerPhone;
  final PlaceAddress? address;
  final String? notes;
  final List<DriverItem> items;
  final int itemsCount;
  final int totalCents;
  final int tipCents;
  final int cashDueCents;
  final DateTime? estimatedReadyAt;
  final DateTime? pickedUpAt;
  final String? problem;

  bool get collectsCash => cashDueCents > 0;

  String get kitchenLabel => switch (orderStatus) {
    'received' => 'Waiting for the kitchen',
    'preparing' => estimatedReadyAt != null ? 'In the oven · ready ~${clock(estimatedReadyAt!)}' : 'In the oven',
    'ready' => 'Ready to pick up',
    _ => orderStatus.replaceAll('_', ' '),
  };

  factory DriverDelivery.fromJson(Json j) => DriverDelivery(
    id: j['id'] as String,
    orderId: j['orderId'] as String,
    number: _i(j['number']),
    ready: j['ready'] as bool? ?? false,
    onTheRoad: j['onTheRoad'] as bool? ?? false,
    orderStatus: j['orderStatus'] as String? ?? '',
    customerName: j['customerName'] as String? ?? '',
    customerPhone: j['customerPhone'] as String? ?? '',
    address: j['address'] == null ? null : PlaceAddress.fromJson(j['address'] as Json),
    notes: j['notes'] as String?,
    items: [for (final i in (j['items'] as List? ?? const [])) DriverItem((i as Json)['name'] as String, _i(i['quantity']), i['summary'] as String? ?? '')],
    itemsCount: _i(j['itemsCount']),
    totalCents: _i(j['totalCents']),
    tipCents: _i(j['tipCents']),
    cashDueCents: _i(j['cashDueCents']),
    estimatedReadyAt: parseDate(j['estimatedReadyAt']),
    pickedUpAt: parseDate(j['pickedUpAt']),
    problem: j['problem'] as String?,
  );
}

/// Everything the driver app shows, from GET /driver/state.
class DriverState {
  const DriverState({
    required this.userId,
    required this.name,
    required this.isActive,
    required this.maxActive,
    required this.maxBacklog,
    required this.cashEnabled,
    required this.cashOwedCents,
    required this.run,
    required this.queue,
    required this.waitingAtStore,
    this.storeName,
    this.storePhone,
    this.storeAddress,
    this.storeLat,
    this.storeLng,
    this.vehicle,
    this.shiftStartedAt,
    this.cashCollectedCents = 0,
  });

  final String userId;
  final String name;
  final bool isActive;
  final String? storeName;
  final String? storePhone;
  final String? storeAddress;
  final double? storeLat;
  final double? storeLng;
  final int maxActive;
  final int maxBacklog;
  final bool cashEnabled;
  final String? vehicle;
  final DateTime? shiftStartedAt;
  final int cashCollectedCents;
  final int cashOwedCents;
  final List<DriverDelivery> run;
  final List<DriverDelivery> queue;
  final int waitingAtStore;

  bool get onShift => shiftStartedAt != null;
  int get room => (maxActive - run.length).clamp(0, maxActive);

  /// First in, first out: the ready orders at the front of the queue that fit in the car.
  int get readyToTake {
    var n = 0;
    for (final d in queue) {
      if (!d.ready || n >= room) break;
      n++;
    }
    return n;
  }

  factory DriverState.fromJson(Json j) {
    final user = j['user'] as Json;
    final store = j['store'] as Json?;
    final profile = (j['profile'] as Json?) ?? const {};
    final shift = j['shift'] as Json?;
    return DriverState(
      userId: user['id'] as String,
      name: user['name'] as String? ?? 'Driver',
      isActive: user['isActive'] as bool? ?? true,
      storeName: store?['name'] as String?,
      storePhone: store?['phone'] as String?,
      storeAddress: store?['address'] as String?,
      storeLat: (store?['lat'] as num?)?.toDouble(),
      storeLng: (store?['lng'] as num?)?.toDouble(),
      maxActive: _i(profile['maxActive']),
      maxBacklog: _i(profile['maxBacklog']),
      cashEnabled: profile['cashEnabled'] as bool? ?? false,
      vehicle: profile['vehicle'] as String?,
      shiftStartedAt: parseDate(shift?['startedAt']),
      cashCollectedCents: _i(shift?['cashCollectedCents']),
      cashOwedCents: _i(j['cashOwedCents']),
      run: [for (final d in (j['run'] as List? ?? const [])) DriverDelivery.fromJson(d as Json)],
      queue: [for (final d in (j['queue'] as List? ?? const [])) DriverDelivery.fromJson(d as Json)],
      waitingAtStore: _i(j['waitingAtStore']),
    );
  }
}
