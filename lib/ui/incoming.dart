import 'package:flutter/services.dart';

/// Başka uygulamalardan gelen kurs dosyaları (dosyaya dokunma ya da "Bilge ile paylaş").
/// Android karşılığı: MainActivity.kt
class Incoming {
  static const _channel = MethodChannel('bilge/incoming');

  /// Dosya boyut sınırını aşıyorsa Android tarafı içeriği okumaz, bunu gönderir (MainActivity.kt ile aynı olmalı).
  static const tooBig = 'bilge:too-big';

  /// Uygulama bir dosyayla açıldıysa ve açıkken yeni dosya gelirse [onText] çağrılır.
  static Future<void> listen(void Function(String text) onText) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming' && call.arguments is String) onText(call.arguments as String);
    });
    try {
      final first = await _channel.invokeMethod<String>('take');
      if (first != null) onText(first);
    } on MissingPluginException {
      // Android dışında (testler dahil) bu köprü yoktur
    }
  }
}
