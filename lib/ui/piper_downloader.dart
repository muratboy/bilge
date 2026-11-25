import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'piper_catalog.dart';
import 'speech.dart';

class _CancelledException implements Exception {
  const _CancelledException();
  @override
  String toString() => 'İndirme iptal edildi';
}

/// İndirme durumları.
enum PiperDownloadStatus {
  idle,
  downloading,
  verifying,
  error,
}

/// İndiricinin canlı durum bilgisi.
class PiperDownloadSnapshot {
  const PiperDownloadSnapshot({
    this.activeVoiceId,
    this.progress = 0.0,
    this.status = PiperDownloadStatus.idle,
    this.errorMessage,
  });

  final String? activeVoiceId;
  final double progress;
  final PiperDownloadStatus status;
  final String? errorMessage;

  bool get isBusy => status == PiperDownloadStatus.downloading || status == PiperDownloadStatus.verifying;
}

/// Piper ses modellerini Hugging Face üzerinden güvenle indiren ve doğrulayan yönetici.
class PiperVoiceDownloader extends ChangeNotifier {
  PiperVoiceDownloader._();

  static final PiperVoiceDownloader instance = PiperVoiceDownloader._();

  PiperDownloadSnapshot _snapshot = const PiperDownloadSnapshot();
  PiperDownloadSnapshot get snapshot => _snapshot;

  bool _cancelRequested = false;
  HttpClient? _activeClient;
  IOSink? _activeSink;
  File? _activePartFile;

  /// Testler için sahte HttpClient fabrikası.
  @visibleForTesting
  static HttpClient Function()? httpClientFactoryOverride;

  /// Testler için sahte sha256 hesaplayıcı.
  @visibleForTesting
  static Future<String> Function(File file)? sha256CalculatorOverride;

  /// Testler için yerel HttpServer'a (HTTP) izin veren anahtar.
  @visibleForTesting
  static bool allowInsecureHttpForTest = false;

  /// Boşta olup olmadığını döner.
  bool get isIdle => _snapshot.status == PiperDownloadStatus.idle;

  /// Belirtilen sesin şu an indirilip indirilmediğini döner.
  bool isDownloading(String voiceId) => _snapshot.activeVoiceId == voiceId && _snapshot.isBusy;

  /// Kalan .part uzantılı geçici dosyaları temizler.
  static Future<void> cleanPartFiles() async {
    try {
      final dir = await Speech.getVoicesDirectory();
      if (!dir.existsSync()) return;
      final list = dir.listSync();
      for (final f in list) {
        if (f is File && f.path.endsWith('.part')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Aktif indirmeyi iptal eder.
  void cancel() {
    if (!_snapshot.isBusy) return;
    _cancelRequested = true;
    try {
      _activeSink?.close();
    } catch (_) {}
    _activeSink = null;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
    _cleanupActivePart();
    _snapshot = const PiperDownloadSnapshot(status: PiperDownloadStatus.idle);
    notifyListeners();
  }

  void _cleanupActivePart() {
    try {
      if (_activePartFile != null && _activePartFile!.existsSync()) {
        _activePartFile!.deleteSync();
      }
    } catch (_) {}
    _activePartFile = null;
  }

  /// Dosyanın SHA-256 özetini hesaplar (Process.run ile sha256sum çalıştırır, kabuk kullanmaz).
  static Future<String> calculateSha256(File file) async {
    if (sha256CalculatorOverride != null) {
      return sha256CalculatorOverride!(file);
    }
    final res = await Process.run('sha256sum', [file.path], runInShell: false);
    if (res.exitCode != 0) {
      throw ProcessException('sha256sum', [file.path], res.stderr.toString(), res.exitCode);
    }
    final out = res.stdout.toString().trim();
    final hash = out.split(RegExp(r'\s+')).first.toLowerCase();
    return hash;
  }

  /// Katalogdaki bir sesi indirir ve doğrular.
  Future<bool> download(PiperVoice voice) async {
    // Aynı anda yalnızca tek indirme
    if (_snapshot.isBusy) {
      if (_snapshot.activeVoiceId == voice.id) return true;
      return false;
    }

    _cancelRequested = false;
    await cleanPartFiles();

    final dir = await Speech.getVoicesDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Dosya adları yalnızca katalog kimliğinden gelir
    final onnxPart = File('${dir.path}/${voice.id}.onnx.part');
    final onnxFinal = File('${dir.path}/${voice.id}.onnx');
    final jsonPart = File('${dir.path}/${voice.id}.onnx.json.part');
    final jsonFinal = File('${dir.path}/${voice.id}.onnx.json');

    _snapshot = PiperDownloadSnapshot(
      activeVoiceId: voice.id,
      progress: 0.0,
      status: PiperDownloadStatus.downloading,
    );
    notifyListeners();

    final totalBytes = voice.onnxSize + voice.jsonSize;
    int downloadedBytes = 0;

    final client = httpClientFactoryOverride != null ? httpClientFactoryOverride!() : HttpClient();
    client.userAgent = 'Bilge';
    _activeClient = client;

    try {
      // 1) .onnx dosyasını indir
      _activePartFile = onnxPart;
      await _downloadUrl(
        client,
        voice.onnxUrl,
        onnxPart,
        maxBytes: voice.onnxSize,
        onBytes: (b) {
          downloadedBytes += b;
          _snapshot = PiperDownloadSnapshot(
            activeVoiceId: voice.id,
            progress: totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 0.95) : 0.0,
            status: PiperDownloadStatus.downloading,
          );
          notifyListeners();
        },
      );

      // 2) .onnx.json dosyasını indir
      _activePartFile = jsonPart;
      await _downloadUrl(
        client,
        voice.jsonUrl,
        jsonPart,
        maxBytes: voice.jsonSize,
        onBytes: (b) {
          downloadedBytes += b;
          _snapshot = PiperDownloadSnapshot(
            activeVoiceId: voice.id,
            progress: totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 0.95) : 0.0,
            status: PiperDownloadStatus.downloading,
          );
          notifyListeners();
        },
      );

      // 3) Doğrulama
      _snapshot = PiperDownloadSnapshot(
        activeVoiceId: voice.id,
        progress: 0.96,
        status: PiperDownloadStatus.verifying,
      );
      notifyListeners();

      // .onnx boyut ve sha256 kontrolü
      if (onnxPart.lengthSync() != voice.onnxSize) {
        throw FormatException('Boyut uyuşmazlığı (.onnx): beklenen ${voice.onnxSize}, gelen ${onnxPart.lengthSync()}');
      }
      final onnxSha = await calculateSha256(onnxPart);
      if (onnxSha.toLowerCase() != voice.onnxSha256.toLowerCase()) {
        throw FormatException('SHA-256 uyuşmazlığı (.onnx): beklenen ${voice.onnxSha256}, hesaplanan $onnxSha');
      }

      // .onnx.json boyut ve sha256 kontrolü
      if (jsonPart.lengthSync() != voice.jsonSize) {
        throw FormatException('Boyut uyuşmazlığı (.onnx.json): beklenen ${voice.jsonSize}, gelen ${jsonPart.lengthSync()}');
      }
      final jsonSha = await calculateSha256(jsonPart);
      if (jsonSha.toLowerCase() != voice.jsonSha256.toLowerCase()) {
        throw FormatException('SHA-256 uyuşmazlığı (.onnx.json): beklenen ${voice.jsonSha256}, hesaplanan $jsonSha');
      }

      // Yerine taşı
      if (onnxFinal.existsSync()) onnxFinal.deleteSync();
      if (jsonFinal.existsSync()) jsonFinal.deleteSync();
      onnxPart.renameSync(onnxFinal.path);
      jsonPart.renameSync(jsonFinal.path);

      _activePartFile = null;
      _snapshot = const PiperDownloadSnapshot(status: PiperDownloadStatus.idle);
      notifyListeners();
      return true;
    } catch (e) {
      // Hata durumunda part dosyalarını temizle
      try {
        if (onnxPart.existsSync()) onnxPart.deleteSync();
      } catch (_) {}
      try {
        if (jsonPart.existsSync()) jsonPart.deleteSync();
      } catch (_) {}
      _activePartFile = null;

      if (_cancelRequested || e is _CancelledException) {
        _snapshot = const PiperDownloadSnapshot(status: PiperDownloadStatus.idle);
        notifyListeners();
        return false;
      }

      _snapshot = PiperDownloadSnapshot(
        activeVoiceId: voice.id,
        status: PiperDownloadStatus.error,
        errorMessage: e.toString(),
      );
      notifyListeners();
      return false;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
      _activeClient = null;
      _activeSink = null;
    }
  }

  /// Güvenli HTTPS indirme (yönlendirmeler de HTTPS olmalı, takılan bağlantı için zaman aşımı).
  Future<void> _downloadUrl(
    HttpClient client,
    String initialUrl,
    File destination, {
    int? maxBytes,
    required void Function(int bytes) onBytes,
  }) async {
    Uri current = Uri.parse(initialUrl);
    if (!allowInsecureHttpForTest && !current.isScheme('https')) {
      throw const HttpException('Yalnızca HTTPS adreslerine izin verilir');
    }

    HttpClientResponse? response;
    int redirects = 0;

    while (redirects < 6) {
      if (_cancelRequested) throw const _CancelledException();
      final req = await client.getUrl(current);
      req.headers.set(HttpHeaders.userAgentHeader, 'Bilge');
      req.followRedirects = false;
      final res = await req.close();

      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null) throw const HttpException('Yönlendirme adresi eksik');
        final next = current.resolve(loc);
        if (!allowInsecureHttpForTest && !next.isScheme('https')) {
          await res.drain<void>();
          throw const HttpException('Güvenli olmayan yönlendirme (HTTPS değil)');
        }
        current = next;
        redirects++;
        await res.drain<void>();
        continue;
      }

      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        throw HttpException('Sunucu hatası: HTTP ${res.statusCode}');
      }

      response = res;
      break;
    }

    if (response == null) {
      throw const HttpException('Bağlantı kurulamadı');
    }

    if (maxBytes != null && maxBytes > 0 && response.contentLength > maxBytes) {
      await response.drain<void>();
      throw HttpException('Boyut sınırı aşıldı: beklenen en fazla $maxBytes bayt');
    }

    if (destination.existsSync()) destination.deleteSync();
    final sink = destination.openWrite();
    _activeSink = sink;

    int writtenBytes = 0;
    try {
      // 15 saniye veri akmazsa takılan bağlantı için zaman aşımı
      final timeoutDuration = const Duration(seconds: 15);
      final stream = response.timeout(
        timeoutDuration,
        onTimeout: (s) => s.addError(TimeoutException('İndirme zaman aşımına uğradı')),
      );

      await for (final chunk in stream) {
        if (_cancelRequested) throw const _CancelledException();
        if (maxBytes != null && maxBytes > 0 && (writtenBytes + chunk.length) > maxBytes) {
          throw HttpException('Boyut sınırı aşıldı: beklenen en fazla $maxBytes bayt');
        }
        sink.add(chunk);
        writtenBytes += chunk.length;
        onBytes(chunk.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
      _activeSink = null;
    }
  }

  /// İndirilmiş bir sesi ve dosyalarını siler.
  static Future<bool> deleteVoice(String voiceId) async {
    try {
      final dir = await Speech.getVoicesDirectory();
      final onnx = File('${dir.path}/$voiceId.onnx');
      final json = File('${dir.path}/$voiceId.onnx.json');
      var deleted = false;
      if (onnx.existsSync()) {
        onnx.deleteSync();
        deleted = true;
      }
      if (json.existsSync()) {
        json.deleteSync();
        deleted = true;
      }
      return deleted;
    } catch (_) {
      return false;
    }
  }
}
