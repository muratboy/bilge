import 'package:flutter/services.dart';

/// Metni cihazın kendi sesiyle okur (dil kurslarındaki dinleme adımları için).
/// Android'in TextToSpeech'ini kullanır; karşılığı MainActivity.kt içindedir.
class Speech {
  static const _channel = MethodChannel('bilge/tts');

  /// Okumayı başlatır. Cihazda ses motoru ya da o dilin sesi yoksa false döner.
  static Future<bool> speak(String text, {required String lang, bool slow = false}) async {
    try {
      return await _channel.invokeMethod<bool>('speak', {'text': text, 'lang': lang, 'rate': slow ? 0.6 : 1.0}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // ses yoksa durduracak bir şey de yoktur
    }
  }
}
