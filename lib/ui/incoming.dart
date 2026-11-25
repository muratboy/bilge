import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'io.dart';

/// Başka uygulamalardan gelen kurs dosyaları (dosyaya dokunma, "Bilge ile paylaş" ya da masaüstü komut satırı/tekil örnek).
/// Android karşılığı: MainActivity.kt, Linux karşılığı: linux/runner/my_application.cc
class Incoming {
  static const _channel = MethodChannel('bilge/incoming');

  /// Dosya boyut sınırını aşıyorsa yerel taraf içeriği okumaz, bunu gönderir (MainActivity.kt ile aynı olmalı).
  static const tooBig = 'bilge:too-big';

  /// Dosya veya metin okunamazsa yerel taraf bunu gönderir (MainActivity.kt ile aynı olmalı).
  static const readFailed = 'bilge:read-failed';

  /// Dosya yolunu veya file URI'sini okuyup metin içeriğini döner; sınır veya hata durumunda özel hata kodları üretir.
  static Future<String> readFile(String raw, {int maxBytes = maxCourseBytes}) async {
    try {
      final path = raw.startsWith('file://') ? Uri.parse(raw).toFilePath() : raw;
      final file = File(path);
      if (!file.existsSync() || FileSystemEntity.typeSync(path) != FileSystemEntityType.file) return readFailed;
      if (file.lengthSync() > maxBytes) return tooBig;
      return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    } catch (_) {
      return readFailed;
    }
  }

  /// Masaüstünde komut satırından (ör. dosya yöneticisinden "Birlikte Aç") gelen kurs dosyasını okur.
  static Future<String?> readArgs(List<String> args, {int maxBytes = maxCourseBytes}) async {
    String? raw;
    for (final a in args) {
      if (a.isNotEmpty && !a.startsWith('-')) {
        raw = a;
        break;
      }
    }
    if (raw == null) return null;
    return readFile(raw, maxBytes: maxBytes);
  }

  static Future<void> _dispatch(String payload, void Function(String text) onText) async {
    if (payload == readFailed || payload == tooBig) {
      onText(payload);
      return;
    }
    // Linux yerel dosya yolu (/... veya file://...) iletir; Android ise dosya içeriğini iletir.
    if (defaultTargetPlatform == TargetPlatform.linux && (payload.startsWith('/') || payload.startsWith('file://'))) {
      onText(await readFile(payload));
      return;
    }
    onText(payload);
  }

  /// Uygulama bir dosyayla açıldıysa ve açıkken yeni dosya gelirse [onText] çağrılır.
  static Future<void> listen(void Function(String text) onText) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming' && call.arguments is String) {
        await _dispatch(call.arguments as String, onText);
      }
    });
    try {
      final first = await _channel.invokeMethod<String>('take');
      if (first != null) {
        await _dispatch(first, onText);
      }
    } on MissingPluginException {
      // Android ve Linux platform köprüsü olmayan ortamlarda (ör. saf birim testleri) yutulur
    }
  }
}
