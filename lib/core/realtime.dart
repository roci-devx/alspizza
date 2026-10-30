import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';

class RealtimeEvent {
  const RealtimeEvent(this.channel, this.event, this.data);

  final String channel;
  final String event;
  final dynamic data;
}

/// Live order, courier GPS and chat updates. Reconnects with backoff and
/// re-subscribes automatically, so screens just listen to [on].
class RealtimeClient {
  RealtimeClient({required this.token});

  final String? Function() token;
  final connected = ValueNotifier(false);
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _channels = <String>{};
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _ping;
  int _attempt = 0;
  bool _disposed = false;

  Stream<RealtimeEvent> on(String channel) => _events.stream.where((e) => e.channel == channel);
  Stream<RealtimeEvent> get all => _events.stream;

  void subscribe(String channel) {
    _channels.add(channel);
    if (_socket == null) {
      _connect();
    } else {
      _send({'type': 'subscribe', 'channel': channel});
    }
  }

  void unsubscribe(String channel) {
    _channels.remove(channel);
    _send({'type': 'unsubscribe', 'channel': channel});
  }

  /// Call after sign-in/out so the socket authenticates as the new user.
  void reconnect() {
    _teardown();
    if (_channels.isNotEmpty) _connect();
  }

  void _connect() {
    if (_disposed) return;
    final t = token();
    final uri = Uri.parse(AppConfig.wsUrl).replace(queryParameters: t == null ? null : {'token': t});
    try {
      final socket = WebSocketChannel.connect(uri);
      _socket = socket;
      socket.ready
          .then((_) {
            _attempt = 0;
            connected.value = true;
            for (final c in _channels) {
              _send({'type': 'subscribe', 'channel': c});
            }
            _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
          })
          .catchError((Object _) => _scheduleRetry());
      _sub = socket.stream.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            final channel = msg['channel'] as String?;
            final event = msg['event'] as String?;
            if (channel != null && event != null) _events.add(RealtimeEvent(channel, event, msg['data']));
          } catch (_) {}
        },
        onDone: _scheduleRetry,
        onError: (Object _) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _socket?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _teardown() {
    _ping?.cancel();
    _retry?.cancel();
    _sub?.cancel();
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    connected.value = false;
  }

  void _scheduleRetry() {
    _teardown();
    if (_disposed || _channels.isEmpty) return;
    final delay = Duration(milliseconds: (500 * (1 << _attempt.clamp(0, 5))).clamp(500, 15000));
    _attempt++;
    _retry = Timer(delay, _connect);
  }

  void dispose() {
    _disposed = true;
    _teardown();
    _events.close();
  }
}
