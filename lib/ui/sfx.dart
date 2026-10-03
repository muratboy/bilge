import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Ses efektleri ve titreşim. Sesler assets/sounds altındaki kısa WAV dosyalarıdır.
class Sfx {
  /// Ayarlardaki "Ses ve titreşim" anahtarı.
  static bool enabled = true;

  /// Testlerde ses eklentisi yoktur; orada tamamen kapatılır.
  static bool available = true;

  static final _players = <String, AudioPlayer>{};

  static Future<void> play(String name) async {
    if (!enabled || !available) return;
    try {
      final player = _players[name] ??= AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      await player.stop();
      await player.play(AssetSource('sounds/$name.wav'));
    } catch (_) {
      available = false; // ses açılamıyorsa sessiz devam et
    }
  }

  static void buzz() {
    if (enabled && available) HapticFeedback.mediumImpact();
  }
}
