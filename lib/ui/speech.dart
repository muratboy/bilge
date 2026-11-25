import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'sfx.dart';

/// Linux sesli okuma süreç yürütme arabirimi (testlerde sahte yürütücü enjekte edebilmek için).
@visibleForTesting
abstract class LinuxSpeechExecutor {
  /// PATH taraması yerine geçer; null ise varsayılan PATH aranır.
  List<String>? get availablePrograms => null;

  /// Process.run karşılığı.
  Future<ProcessResult> run(String executable, List<String> arguments, {bool runInShell = false});

  /// Process.start karşılığı.
  Future<Process> start(String executable, List<String> arguments, {bool runInShell = false});
}

enum _PiperResult {
  success,
  cancelled,
  failed,
}

/// Metni cihazın kendi sesiyle okur (dil kurslarındaki dinleme adımları için).
/// Android'de bilge/tts kanalı (MainActivity.kt), Linux'ta ise Piper doğal ses motorunu kullanır.
class Speech {
  static const _channel = MethodChannel('bilge/tts');

  static Process? _currentPiperProc;
  static Process? _currentPlayerProc;
  static File? _currentTempWav;
  static Directory? _tempDir;
  static String? _lastBackend;
  static int _speakGeneration = 0;

  /// Testlerde Linux konuşma yürütücüsünü taklit etmek için kanca.
  @visibleForTesting
  static LinuxSpeechExecutor? linuxExecutor;

  /// Testlerde Piper çalıştırılabilir dosya yolunu ezmek için kanca.
  @visibleForTesting
  static String? piperExecutableOverride;

  /// Testlerde indirilen seslerin bulunduğu klasörü ezmek için kanca.
  @visibleForTesting
  static Directory? voicesDirOverride;

  /// Dil başına seçilmiş ses kimliğini verebilecek kanca.
  static String? Function(String lang)? selectedVoiceResolver;

  /// Son kullanılan konuşma motoru ('piper', 'android' vb.).
  static String? get lastBackend => _lastBackend;

  @visibleForTesting
  static void resetLinuxForTest() {
    _speakGeneration++;
    _currentPiperProc?.kill();
    _currentPiperProc = null;
    _currentPlayerProc?.kill();
    _currentPlayerProc = null;
    if (_currentTempWav != null) {
      try {
        if (_currentTempWav!.existsSync()) _currentTempWav!.deleteSync();
      } catch (_) {}
      _currentTempWav = null;
    }
    if (_tempDir != null) {
      try {
        if (_tempDir!.existsSync()) _tempDir!.deleteSync(recursive: true);
      } catch (_) {}
      _tempDir = null;
    }
    _lastBackend = null;
    linuxExecutor = null;
    piperExecutableOverride = null;
    voicesDirOverride = null;
    selectedVoiceResolver = null;
  }

  static Directory _getTempDir() {
    if (_tempDir == null || !_tempDir!.existsSync()) {
      _tempDir = Directory.systemTemp.createTempSync('bilge_piper_');
    }
    return _tempDir!;
  }

  static bool get _isLinux =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          (Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST')) ||
          linuxExecutor != null);

  /// Linux ortamında Piper ikilisinin yolunu çözer.
  /// Yalnızca Platform.resolvedExecutable klasöründeki piper/piper aranır; PATH'teki başka 'piper' programları karışmaz.
  static String? _resolvePiperExecutable() {
    if (piperExecutableOverride != null) return piperExecutableOverride;
    if (linuxExecutor != null && linuxExecutor!.availablePrograms != null) {
      if (linuxExecutor!.availablePrograms!.contains('piper')) return 'piper';
    }
    if (Platform.environment.containsKey('FLUTTER_TEST') && linuxExecutor == null) {
      return null;
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final piperPath = '$exeDir/piper/piper';
      if (File(piperPath).existsSync()) return piperPath;
    } catch (_) {}
    return null;
  }

  /// Linux ortamında gömülü Piper motorunun olup olmadığını döner.
  static bool get hasPiperEngine => _resolvePiperExecutable() != null;

  /// Linux ortamında seslerin saklandığı `voices/` klasörünü döner.
  static Future<Directory> getVoicesDirectory() async {
    if (voicesDirOverride != null) return voicesDirOverride!;
    final supportDir = await getApplicationSupportDirectory();
    return Directory('${supportDir.path}/voices');
  }

  /// Model dosyasından (.onnx) ses kimliği adını çıkarır.
  static String _voiceIdOf(File f) {
    final name = f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : f.path.split(Platform.pathSeparator).last;
    return name.endsWith('.onnx') ? name.substring(0, name.length - 5) : name;
  }

  /// İndirilmiş ve hem .onnx hem .onnx.json dosyası mevcut Piper seslerini döner.
  static Future<List<File>> getInstalledVoiceModels() async {
    try {
      final dir = await getVoicesDirectory();
      if (!dir.existsSync()) return const [];
      final files = dir.listSync();
      final onnxMap = <String, File>{};
      final jsonSet = <String>{};
      for (final f in files) {
        if (f is File) {
          final p = f.path;
          if (p.endsWith('.onnx')) {
            final id = p.substring(0, p.length - 5);
            onnxMap[id] = f;
          } else if (p.endsWith('.onnx.json')) {
            final id = p.substring(0, p.length - 10);
            jsonSet.add(id);
          }
        }
      }
      final valid = <File>[];
      for (final entry in onnxMap.entries) {
        if (jsonSet.contains(entry.key)) {
          valid.add(entry.value);
        }
      }
      return valid;
    } catch (_) {
      return const [];
    }
  }

  /// İstenen dil için indirilen Piper sesleri arasında en uygun modeli seçer.
  /// Dil eşleme: önce tam bölge (en-US için en_US), yoksa aynı birincil dil (en).
  /// Çoklu ses varsa kanca kontrol edilir; yoksa ada göre (alfabetik) ilk ses seçilir.
  static Future<File?> resolvePiperVoice(String lang) async {
    final models = await getInstalledVoiceModels();
    if (models.isEmpty) return null;

    final normRequested = lang.replaceAll('-', '_').toLowerCase().trim();
    if (normRequested.isEmpty) return null;
    final reqPrimary = normRequested.split('_').first;
    final hasRegion = normRequested.contains('_');

    String voiceLang(File f) {
      final id = _voiceIdOf(f);
      final prefix = id.split('-').first;
      return prefix.replaceAll('-', '_').toLowerCase();
    }

    String voicePrimary(File f) => voiceLang(f).split('_').first;

    // 1) Tam bölge eşleşmesi (istenen dilde bölge belirtilmişse)
    if (hasRegion) {
      final regionMatches = models.where((m) => voiceLang(m) == normRequested).toList();
      if (regionMatches.isNotEmpty) {
        return _pickVoice(regionMatches, lang);
      }
    }

    // 2) Birincil dil eşleşmesi
    final primaryMatches = models.where((m) => voicePrimary(m) == reqPrimary).toList();
    if (primaryMatches.isNotEmpty) {
      return _pickVoice(primaryMatches, lang);
    }

    return null;
  }

  static File _pickVoice(List<File> candidates, String requestedLang) {
    if (candidates.length == 1) return candidates.first;

    if (selectedVoiceResolver != null) {
      final chosenId = selectedVoiceResolver!(requestedLang);
      if (chosenId != null && chosenId.isNotEmpty) {
        for (final f in candidates) {
          final id = _voiceIdOf(f);
          if (id == chosenId || id.toLowerCase() == chosenId.toLowerCase()) {
            return f;
          }
        }
      }
    }

    candidates.sort((a, b) => _voiceIdOf(a).compareTo(_voiceIdOf(b)));
    return candidates.first;
  }

  /// Linux ses yürütücüsünü bulur (pw-play, paplay, aplay).
  static String? _discoverLinuxAudioPlayer() {
    if (linuxExecutor != null && linuxExecutor!.availablePrograms != null) {
      for (final cmd in const ['pw-play', 'paplay', 'aplay']) {
        if (linuxExecutor!.availablePrograms!.contains(cmd)) return cmd;
      }
      return null;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST') && linuxExecutor == null) {
      return null;
    }
    final players = Sfx.discoverLinuxAudioPlayers();
    return players.isNotEmpty ? players.first : null;
  }

  /// Okumayı başlatır. Cihazda ses motoru ya da o dilin sesi yoksa false döner.
  static Future<bool> speak(String text, {required String lang, bool slow = false}) async {
    if (_isLinux) {
      return _speakLinux(text, lang: lang, slow: slow);
    }
    try {
      final ok = await _channel.invokeMethod<bool>('speak', {'text': text, 'lang': lang, 'rate': slow ? 0.6 : 1.0}) ?? false;
      if (ok) _lastBackend = 'android';
      return ok;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    _speakGeneration++;
    if (_isLinux) {
      await _stopLinux();
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // ses yoksa durduracak bir şey de yoktur
    }
  }

  static Future<Process> _startProcess(String cmd, List<String> args) {
    if (linuxExecutor != null) {
      return linuxExecutor!.start(cmd, args, runInShell: false);
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      throw UnsupportedError('FLUTTER_TEST ortamında sahte yürütücü olmadan süreç başlatılamaz');
    }
    return Process.start(cmd, args, runInShell: false);
  }

  static Future<bool> _speakLinux(String text, {required String lang, bool slow = false}) async {
    final gen = ++_speakGeneration;
    await _stopLinux();

    if (_speakGeneration != gen) return true;

    // Piper: motor var, dilin indirilmiş sesi ve yürütücü mevcutsa Piper kullan
    final piperExe = _resolvePiperExecutable();
    if (piperExe != null) {
      final modelFile = await resolvePiperVoice(lang);
      if (_speakGeneration != gen) return true;
      if (modelFile != null) {
        final playerCmd = _discoverLinuxAudioPlayer();
        if (_speakGeneration != gen) return true;
        if (playerCmd != null) {
          final res = await _speakWithPiper(
            text,
            piperExe: piperExe,
            modelFile: modelFile,
            playerCmd: playerCmd,
            slow: slow,
            gen: gen,
          );
          if (res == _PiperResult.cancelled) {
            return true;
          }
          if (res == _PiperResult.success) {
            return true;
          }
        }
      }
    }

    return false;
  }

  static Future<_PiperResult> _speakWithPiper(
    String text, {
    required String piperExe,
    required File modelFile,
    required String playerCmd,
    required int gen,
    bool slow = false,
  }) async {
    if (_speakGeneration != gen) return _PiperResult.cancelled;

    final tempDir = _getTempDir();
    final tempWav = File('${tempDir.path}/speech_${DateTime.now().microsecondsSinceEpoch}.wav');
    _currentTempWav = tempWav;

    final piperArgs = <String>[
      '--model',
      modelFile.path,
      '--output_file',
      tempWav.path,
    ];
    if (slow) {
      piperArgs.addAll(['--length_scale', (1.0 / 0.6).toStringAsFixed(2)]);
    }

    final cleanText = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    final Process piperProc;
    try {
      piperProc = await _startProcess(piperExe, piperArgs);
      _currentPiperProc = piperProc;
    } catch (_) {
      _cleanupTempWav(tempWav);
      if (_speakGeneration != gen) return _PiperResult.cancelled;
      return _PiperResult.failed;
    }

    unawaited(piperProc.stdout.drain<void>().catchError((_) {}));
    unawaited(piperProc.stderr.drain<void>().catchError((_) {}));

    try {
      piperProc.stdin.add(utf8.encode(cleanText));
      await piperProc.stdin.flush();
      await piperProc.stdin.close();
    } catch (_) {}

    final exitCode = await piperProc.exitCode;
    if (_currentPiperProc == piperProc) {
      _currentPiperProc = null;
    }

    // Bekleme esnasında stop() ya da yeni speak() çağrılmışsa çık
    if (_speakGeneration != gen || _currentTempWav != tempWav) {
      _cleanupTempWav(tempWav);
      return _PiperResult.cancelled;
    }

    if (exitCode != 0) {
      _cleanupTempWav(tempWav);
      return _PiperResult.failed;
    }

    if (linuxExecutor == null && !tempWav.existsSync()) {
      _cleanupTempWav(tempWav);
      return _PiperResult.failed;
    }

    if (_speakGeneration != gen) {
      _cleanupTempWav(tempWav);
      return _PiperResult.cancelled;
    }

    final playerArgs = playerCmd == 'aplay' ? ['-q', tempWav.path] : [tempWav.path];
    final Process playerProc;
    try {
      playerProc = await _startProcess(playerCmd, playerArgs);
      _currentPlayerProc = playerProc;
      _lastBackend = 'piper';
    } catch (_) {
      _cleanupTempWav(tempWav);
      if (_speakGeneration != gen) return _PiperResult.cancelled;
      return _PiperResult.failed;
    }

    unawaited(playerProc.stdout.drain<void>().catchError((_) {}));
    unawaited(playerProc.stderr.drain<void>().catchError((_) {}));

    unawaited(playerProc.exitCode.then((_) {
      if (_currentPlayerProc == playerProc) {
        _currentPlayerProc = null;
      }
      if (_currentTempWav == tempWav) {
        _currentTempWav = null;
      }
      _cleanupTempWav(tempWav);
    }).catchError((_) {
      _cleanupTempWav(tempWav);
    }));

    return _PiperResult.success;
  }

  static void _cleanupTempWav(File wav) {
    try {
      if (wav.existsSync()) wav.deleteSync();
    } catch (_) {}
  }

  static Future<void> _stopLinux() async {
    final piperProc = _currentPiperProc;
    final playerProc = _currentPlayerProc;
    final tempWav = _currentTempWav;

    _currentPiperProc = null;
    _currentPlayerProc = null;
    _currentTempWav = null;

    if (piperProc != null) {
      try {
        piperProc.kill();
      } catch (_) {}
    }
    if (playerProc != null) {
      try {
        playerProc.kill();
      } catch (_) {}
    }
    if (tempWav != null) {
      _cleanupTempWav(tempWav);
    }
  }
}
