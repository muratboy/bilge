/// Dosya, paylaşım ve ağ işlemleri (eklenti çağrıları tek yerde dursun diye).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Metni geçici bir dosyaya yazıp sistemin paylaşım penceresini açar.
Future<void> shareFile(String name, String content, {String? subject, String? text, String? mimeType}) async {
  final file = File('${(await getTemporaryDirectory()).path}/$name');
  await file.writeAsString(content);
  final type = mimeType ?? (name.endsWith('.md') ? 'text/markdown' : 'application/json');
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: type)], subject: subject, text: text));
}

/// Kurs dosyası ve bağlantısı için boyut sınırı; yedek dosyası bütün kursları taşıdığı için daha büyük olabilir.
const maxCourseBytes = 8 * 1024 * 1024, maxBackupBytes = 64 * 1024 * 1024;

/// Dosya ya da bağlantıdaki içerik sınırı aşıyor.
class TooBigException implements Exception {
  const TooBigException(this.maxBytes);
  final int maxBytes;
  int get megabytes => maxBytes ~/ (1024 * 1024);
}

/// Kullanıcının seçtiği dosyanın metnini döndürür; vazgeçilirse null. [maxBytes] aşılırsa [TooBigException] atar.
Future<String?> pickTextFile({int maxBytes = maxCourseBytes}) async {
  final file = await selector.openFile();
  if (file == null) return null;
  if (await file.length() > maxBytes) throw TooBigException(maxBytes);
  return utf8.decode(await file.readAsBytes(), allowMalformed: true);
}

Future<String?> clipboardText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

bool _isPrivateHost(String host) {
  final h = host.toLowerCase().trim();
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return true;
  final ip = InternetAddress.tryParse(h);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final raw = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    if (raw[0] == 10) return true; // 10.0.0.0/8
    if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return true; // 172.16.0.0/12
    if (raw[0] == 192 && raw[1] == 168) return true; // 192.168.0.0/16
    if (raw[0] == 0 || raw[0] == 127) return true;
  } else if (ip.type == InternetAddressType.IPv6) {
    if ((raw[0] & 0xfe) == 0xfc) return true; // fc00::/7 ULA
  }
  return false;
}

@visibleForTesting
bool isPrivateHostForTest(String host) => _isPrivateHost(host);

/// Paylaşılan bir kurs dosyasını indirir. GitHub sayfa bağlantılarını ham dosya adresine çevirir.
/// Yalnızca http/https kabul edilir ve en fazla 5 yönlendirme güvenli host kontrolüyle elle izlenir;
/// gövde [maxBytes] aşılınca okuma kesilir ve [TooBigException] atılır.
/// Metin her zaman UTF-8 okunur: sunucu kodlamayı bildirmese de Türkçe harfler bozulmaz.
Future<String> fetchText(String url, {int maxBytes = maxCourseBytes, http.Client? client}) async {
  final raw = url.replaceFirstMapped(RegExp(r'^https://github\.com/([^/]+)/([^/]+)/blob/'), (m) => 'https://raw.githubusercontent.com/${m[1]}/${m[2]}/');
  var uri = Uri.parse(raw);
  final c = client ?? (httpClientFactory != null ? httpClientFactory!() : http.Client());
  try {
    const wait = Duration(seconds: 20);
    var redirects = 0;
    while (true) {
      if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty || _isPrivateHost(uri.host)) {
        throw const FormatException('https');
      }
      final req = http.Request('GET', uri)..followRedirects = false;
      final res = await c.send(req).timeout(wait);
      if (res.isRedirect || (res.statusCode >= 301 && res.statusCode <= 308 && res.statusCode != 304 && res.statusCode != 305 && res.statusCode != 306)) {
        redirects++;
        if (redirects > 5) throw const HttpException('Too many redirects');
        final location = res.headers['location'];
        if (location == null || location.isEmpty) throw const HttpException('Redirect without location');
        uri = uri.resolve(location);
        continue;
      }
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      if ((res.contentLength ?? 0) > maxBytes) throw TooBigException(maxBytes);
      final body = BytesBuilder(copy: false);
      await for (final part in res.stream.timeout(wait)) {
        body.add(part);
        if (body.length > maxBytes) throw TooBigException(maxBytes);
      }
      return utf8.decode(body.takeBytes(), allowMalformed: true);
    }
  } finally {
    if (client == null && httpClientFactory == null) c.close();
  }
}

/// Testlerde ağa çıkmadan yapay zekâ yanıtını taklit etmek için kanca.
Future<String> Function(String provider, String apiKey, String model, String prompt)? aiHandler;

/// Testlerde HTTP istemcisini değiştirmek için fabrika.
http.Client Function()? httpClientFactory;

/// Kullanıcının kendi API anahtarıyla (Gemini, OpenAI ya da Claude) doğrudan kalıp çıktısı üretir.
Future<String> callAi({required String provider, required String apiKey, String model = '', required String prompt, http.Client? client}) async {
  final key = apiKey.trim();
  final m = model.trim();
  if (aiHandler != null) return aiHandler!(provider, key, m, prompt);
  final c = client ?? (httpClientFactory != null ? httpClientFactory!() : http.Client());
  try {
    const wait = Duration(seconds: 120);
    late final http.Response res;
    switch (provider) {
      case 'openai':
        final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
        final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'};
        final payload = {
          'model': m.isEmpty ? 'gpt-4o-mini' : m,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        };
        res = await c.post(uri, headers: headers, body: jsonEncode(payload)).timeout(wait);
      case 'claude':
        final uri = Uri.parse('https://api.anthropic.com/v1/messages');
        final headers = {'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01'};
        final claudeModel = m.isEmpty || m == 'claude-3-5-sonnet-latest' ? 'claude-sonnet-5-5' : m;
        final payload = {
          'model': claudeModel,
          'max_tokens': 8192,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        };
        res = await c.post(uri, headers: headers, body: jsonEncode(payload)).timeout(wait);
      default:
        var geminiModel = (m.isEmpty ? 'gemini-flash-latest' : m).replaceFirst(RegExp(r'^models/'), '');
        if (geminiModel == 'gemini-2.5-flash') geminiModel = 'gemini-flash-latest';
        final headers = {'Content-Type': 'application/json', 'x-goog-api-key': key};
        final payload = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 8192,
          },
        };
        final candidates = [
          geminiModel,
          if (geminiModel != 'gemini-1.5-flash') 'gemini-1.5-flash',
          if (geminiModel != 'gemini-2.0-flash') 'gemini-2.0-flash',
        ];
        http.Response? lastRes;
        for (final cand in candidates) {
          final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$cand:generateContent');
          final r = await c.post(uri, headers: headers, body: jsonEncode(payload)).timeout(wait);
          lastRes = r;
          if (r.statusCode == 200 || r.statusCode != 404) break;
        }
        res = lastRes ?? http.Response('', 404);
    }
    final decoded = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode != 200) {
      String? detail;
      try {
        final errJson = jsonDecode(decoded);
        if (errJson is Map) {
          detail = (errJson['error'] is Map ? errJson['error']['message']?.toString() : null) ?? errJson['message']?.toString();
        }
      } catch (_) {}
      throw HttpException(detail != null && detail.isNotEmpty ? 'HTTP ${res.statusCode}: $detail' : 'HTTP ${res.statusCode}');
    }
    final json = jsonDecode(decoded) as Map;
    return switch (provider) {
      'openai' => (((json['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?)?['content'] as String? ?? '',
      'claude' => (((json['content'] as List?)?.firstOrNull as Map?)?['text']) as String? ?? '',
      _ => () {
          final parts = (((json['candidates'] as List?)?.firstOrNull as Map?)?['content'] as Map?)?['parts'] as List?;
          if (parts == null || parts.isEmpty) {
            final blockReason = (json['promptFeedback'] as Map?)?['blockReason'] ?? ((json['candidates'] as List?)?.firstOrNull as Map?)?['finishReason'];
            if (blockReason != null) throw HttpException('Gemini: $blockReason');
            return '';
          }
          return parts.map((p) => (p as Map?)?['text'] as String? ?? '').join('');
        }(),
    };
  } finally {
    if (client == null && httpClientFactory == null) {
      c.close();
    }
  }
}

const _reminderChannel = MethodChannel('bilge/reminder');

/// Yerel günlük hatırlatıcıyı kurar ya da iptal eder (Android AlarmManager + NotificationManager).
Future<void> scheduleReminder({required bool enabled, required int hour, required String title, required String body, String? lastActive}) async {
  try {
    await _reminderChannel.invokeMethod<void>('schedule', {
      'enabled': enabled,
      'hour': hour,
      'title': title,
      'body': body,
      'lastActive': ?lastActive,
    });
  } catch (_) {
    // Masaüstü / test ortamında bildirim köprüsü yoktur
  }
}

