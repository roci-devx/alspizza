import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The kitchen/driver chime (assets/sounds/ring.wav). [ring] loops until [stop];
/// [ding] plays it once. Browsers only allow sound after a tap, so web screens
/// call [unlock] from a button first.
class Ringer {
  Ringer() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final _player = AudioPlayer();
  static final _sound = AssetSource('sounds/ring.wav');
  bool _looping = false;
  bool muted = false;
  bool unlocked = !kIsWeb;

  bool get ringing => _looping;

  Future<void> unlock() async {
    unlocked = true;
    await _safe(() async {
      await _player.setVolume(0);
      await _player.play(_sound);
      await _player.stop();
      await _player.setVolume(1);
    });
  }

  Future<void> ding() async {
    if (muted || _looping) return;
    await _safe(() async {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(_sound);
    });
  }

  Future<void> ring() async {
    if (_looping) return;
    _looping = true;
    if (muted) return;
    await _safe(() async {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(_sound);
    });
  }

  Future<void> stop() async {
    _looping = false;
    await _safe(() async {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
    });
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    if (value) {
      await _safe(_player.stop);
    } else if (_looping) {
      _looping = false;
      await ring();
    }
  }

  void dispose() => _player.dispose();

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[ringer] $e');
    }
  }
}
