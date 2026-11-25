import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ses efektleri ve titreşim. Sesler assets/sounds altındaki kısa WAV dosyalarıdır.
class Sfx {
  /// Ayarlardaki "Ses ve titreşim" anahtarı.
  static bool enabled = true;

  /// Testlerde ses eklentisi yoktur; orada tamamen kapatılır.
  static bool available = true;

  static final _players = <String, AudioPlayer>{};
  static final _linuxFiles = <String, String>{};
  static final _linuxProcs = <String, Process>{};
  static final _killedProcs = <Process>{};
  static List<String>? _linuxCmds;
  static int _linuxCmdIndex = 0;
  static bool _linuxCmdLocked = false;

  /// Testlerde Linux ses yürütücüsünü taklit etmek için kanca.
  @visibleForTesting
  static Future<bool> Function(String path)? linuxPlayer;

  @visibleForTesting
  static void resetLinuxForTest() {
    _linuxFiles.clear();
    _linuxCmds = null;
    _linuxCmdIndex = 0;
    _linuxCmdLocked = false;
    linuxPlayer = null;
  }

  static final _safeName = RegExp(r'^[a-z0-9_-]+$');

  static Future<void> play(String name) async {
    if (!enabled || !available || !_safeName.hasMatch(name)) return;
    if (!kIsWeb && Platform.isLinux) {
      try {
        await _playLinux(name);
      } catch (_) {
        available = false;
      }
      return;
    }
    try {
      final player = _players[name] ??= AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      await player.stop();
      await player.play(AssetSource('sounds/$name.wav'));
    } catch (_) {
      available = false; // ses açılamıyorsa sessiz devam et
    }
  }

  static Future<String?> _resolveLinuxSound(String name) async {
    final cached = _linuxFiles[name];
    if (cached != null && File(cached).existsSync()) return cached;

    final bundled = '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/sounds/$name.wav';
    if (File(bundled).existsSync()) {
      _linuxFiles[name] = bundled;
      return bundled;
    }

    final data = await rootBundle.load('assets/sounds/$name.wav');
    final dir = Directory('${Directory.systemTemp.path}/bilge-sfx-$pid');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final out = File('${dir.path}/$name.wav');
    await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    _linuxFiles[name] = out.path;
    return out.path;
  }

  /// Linux sistemindeki ses yürütücüleri (pw-play, paplay, aplay) döner.
  static List<String> discoverLinuxAudioPlayers() {
    final dirs = (Platform.environment['PATH'] ?? '/usr/bin:/bin').split(':').where((d) => d.isNotEmpty).toList();
    return [
      for (final cmd in const ['pw-play', 'paplay', 'aplay'])
        if (dirs.any((d) => File('$d/$cmd').existsSync())) cmd,
    ];
  }

  static Future<void> _playLinux(String name) async {
    if (Platform.environment.containsKey('FLUTTER_TEST') && linuxPlayer == null) return;
    final path = await _resolveLinuxSound(name);
    if (path == null) return;
    if (linuxPlayer != null) {
      if (!await linuxPlayer!(path)) available = false;
      return;
    }
    final cmds = _linuxCmds ??= discoverLinuxAudioPlayers();
    if (_linuxCmdIndex >= cmds.length) {
      available = false;
      return;
    }
    final prev = _linuxProcs.remove(name);
    if (prev != null) {
      _killedProcs.add(prev);
      prev.kill();
    }
    await _spawnLinux(name, path, cmds);
  }

  static Future<void> _spawnLinux(String name, String path, List<String> cmds) async {
    while (_linuxCmdIndex < cmds.length) {
      final idx = _linuxCmdIndex;
      final cmd = cmds[idx];
      final args = cmd == 'aplay' ? ['-q', path] : [path];
      try {
        final proc = await Process.start(cmd, args);
        _linuxProcs[name] = proc;
        unawaited(proc.stdout.drain<void>());
        unawaited(proc.stderr.drain<void>());
        unawaited(proc.exitCode.then((code) {
          if (_linuxProcs[name] == proc) _linuxProcs.remove(name);
          if (_killedProcs.remove(proc)) return;
          if (code == 0) {
            _linuxCmdLocked = true;
          } else if (!_linuxCmdLocked && _linuxCmdIndex == idx) {
            _linuxCmdIndex = idx + 1;
            if (_linuxCmdIndex < cmds.length && enabled && available) {
              unawaited(_spawnLinux(name, path, cmds));
            } else if (_linuxCmdIndex >= cmds.length) {
              available = false;
            }
          }
        }));
        return;
      } catch (_) {
        if (_linuxCmdLocked) return;
        if (_linuxCmdIndex == idx) _linuxCmdIndex = idx + 1;
      }
    }
    available = false;
  }

  static void buzz() {
    if (enabled && available) HapticFeedback.mediumImpact();
  }
}
