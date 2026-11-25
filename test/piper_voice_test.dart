import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/screens/profile.dart';
import 'package:bilge/ui/natural_voices_sheet.dart';
import 'package:bilge/ui/piper_catalog.dart';
import 'package:bilge/ui/piper_downloader.dart';
import 'package:bilge/ui/speech.dart';
import 'package:bilge/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Piper Ses Kataloğu Bütünlüğü', () {
    test('her sesin benzersiz kimliği vardır', () {
      final ids = PiperCatalog.voices.map((v) => v.id).toList();
      final set = ids.toSet();
      expect(set.length, ids.length);
      expect(ids.length, 13);
    });

    test('adresler HTTPS ve sabit commit kimliğini içerir', () {
      for (final v in PiperCatalog.voices) {
        expect(v.onnxUrl, startsWith('https://'));
        expect(v.onnxUrl, contains('/${PiperCatalog.commit}/'));
        expect(v.onnxUrl, endsWith('.onnx'));

        expect(v.jsonUrl, startsWith('https://'));
        expect(v.jsonUrl, contains('/${PiperCatalog.commit}/'));
        expect(v.jsonUrl, endsWith('.onnx.json'));
      }
    });

    test('özetler 64 haneli SHA-256 ve boyutlar pozitiftir', () {
      final shaRegex = RegExp(r'^[0-9a-f]{64}$');
      for (final v in PiperCatalog.voices) {
        expect(shaRegex.hasMatch(v.onnxSha256), isTrue, reason: '${v.id} onnx SHA-256 geçersiz');
        expect(shaRegex.hasMatch(v.jsonSha256), isTrue, reason: '${v.id} json SHA-256 geçersiz');
        expect(v.onnxSize, greaterThan(0));
        expect(v.jsonSize, greaterThan(0));
      }
    });

    test('her dil için önizleme cümlesi ve boş olmayan lisans tanımlıdır', () {
      const requiredLangs = ['tr', 'en', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'ar', 'nl', 'zh'];
      for (final lang in requiredLangs) {
        final sentence = PiperCatalog.previewSentences[lang];
        expect(sentence, isNotNull, reason: '$lang için önizleme cümlesi yok');
        expect(sentence!.trim(), isNotEmpty);
      }

      for (final v in PiperCatalog.voices) {
        expect(v.license.trim(), isNotEmpty, reason: '${v.id} lisansı boş');
        expect(PiperCatalog.previewSentenceFor(v.lang).trim(), isNotEmpty);
      }
    });
  });

  group('Piper Ses İndirici (Yerel Test Sunucusu, Ağ Yok)', () {
    late Directory tempDir;
    HttpServer? server;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = Directory.systemTemp.createTempSync('bilge_test_voices_');
      Speech.voicesDirOverride = tempDir;
      PiperVoiceDownloader.allowInsecureHttpForTest = true;
      PiperVoiceDownloader.httpClientFactoryOverride = null;
      PiperVoiceDownloader.sha256CalculatorOverride = null;
    });

    tearDown(() async {
      HttpOverrides.global = null;
      PiperVoiceDownloader.allowInsecureHttpForTest = false;
      PiperVoiceDownloader.httpClientFactoryOverride = null;
      PiperVoiceDownloader.sha256CalculatorOverride = null;
      Speech.voicesDirOverride = null;
      try {
        await server?.close(force: true);
      } catch (_) {}
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('başarılı indirme ve doğrulama: .part kalkar, dosyalar taşınır', () async {
      const dummyOnnxData = 'fake-onnx-content-123456';
      const dummyJsonData = '{"test": 1}';
      final onnxBytes = utf8.encode(dummyOnnxData);
      final jsonBytes = utf8.encode(dummyJsonData);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) {
        req.response.headers.contentType = ContentType.binary;
        if (req.uri.path.endsWith('.onnx')) {
          req.response.add(onnxBytes);
        } else {
          req.response.add(jsonBytes);
        }
        req.response.close();
      });

      final testVoice = PiperVoice(
        id: 'tr_TR-test-medium',
        lang: 'tr_TR',
        name: 'TestVoice',
        onnxUrl: 'http://${server!.address.host}:${server!.port}/model.onnx',
        onnxSize: onnxBytes.length,
        onnxSha256: 'dummy-onnx-sha',
        jsonUrl: 'http://${server!.address.host}:${server!.port}/model.onnx.json',
        jsonSize: jsonBytes.length,
        jsonSha256: 'dummy-json-sha',
        license: 'CC0',
      );

      PiperVoiceDownloader.sha256CalculatorOverride = (f) async {
        if (f.path.contains('.onnx.part')) return 'dummy-onnx-sha';
        if (f.path.contains('.onnx.json.part')) return 'dummy-json-sha';
        return '';
      };

      final downloader = PiperVoiceDownloader.instance;
      final ok = await downloader.download(testVoice);

      expect(ok, isTrue);
      expect(downloader.snapshot.status, PiperDownloadStatus.idle);

      final onnxFinal = File('${tempDir.path}/${testVoice.id}.onnx');
      final jsonFinal = File('${tempDir.path}/${testVoice.id}.onnx.json');
      final onnxPart = File('${tempDir.path}/${testVoice.id}.onnx.part');
      final jsonPart = File('${tempDir.path}/${testVoice.id}.onnx.json.part');

      expect(onnxFinal.existsSync(), isTrue);
      expect(jsonFinal.existsSync(), isTrue);
      expect(onnxPart.existsSync(), isFalse);
      expect(jsonPart.existsSync(), isFalse);
    });

    test('SHA-256 uyuşmazlığında silinir ve hata durumuna geçer', () async {
      const dummyOnnxData = 'corrupt-content';
      final onnxBytes = utf8.encode(dummyOnnxData);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) {
        req.response.add(onnxBytes);
        req.response.close();
      });

      final testVoice = PiperVoice(
        id: 'tr_TR-test-medium',
        lang: 'tr_TR',
        name: 'TestVoice',
        onnxUrl: 'http://${server!.address.host}:${server!.port}/model.onnx',
        onnxSize: onnxBytes.length,
        onnxSha256: 'expected-onnx-sha',
        jsonUrl: 'http://${server!.address.host}:${server!.port}/model.onnx.json',
        jsonSize: 10,
        jsonSha256: 'expected-json-sha',
        license: 'CC0',
      );

      PiperVoiceDownloader.sha256CalculatorOverride = (f) async => 'mismatched-sha';

      final downloader = PiperVoiceDownloader.instance;
      final ok = await downloader.download(testVoice);

      expect(ok, isFalse);
      expect(downloader.snapshot.status, PiperDownloadStatus.error);

      final onnxFinal = File('${tempDir.path}/${testVoice.id}.onnx');
      final onnxPart = File('${tempDir.path}/${testVoice.id}.onnx.part');
      expect(onnxFinal.existsSync(), isFalse);
      expect(onnxPart.existsSync(), isFalse);
    });

    test('iptal durumunda geçici .part dosyası kalmaz', () async {
      final completer = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) async {
        req.response.bufferOutput = false;
        req.response.add(List.filled(100, 0));
        await completer.future;
        req.response.close();
      });

      final testVoice = PiperVoice(
        id: 'tr_TR-test-medium',
        lang: 'tr_TR',
        name: 'TestVoice',
        onnxUrl: 'http://${server!.address.host}:${server!.port}/model.onnx',
        onnxSize: 1000,
        onnxSha256: 'sha',
        jsonUrl: 'http://${server!.address.host}:${server!.port}/model.onnx.json',
        jsonSize: 100,
        jsonSha256: 'sha',
        license: 'CC0',
      );

      final downloader = PiperVoiceDownloader.instance;
      final future = downloader.download(testVoice);

      // İndirme başladıktan hemen sonra iptal et
      await Future<void>.delayed(const Duration(milliseconds: 50));
      downloader.cancel();
      completer.complete();

      final ok = await future;
      expect(ok, isFalse);
      expect(downloader.snapshot.status, PiperDownloadStatus.idle);

      final onnxPart = File('${tempDir.path}/${testVoice.id}.onnx.part');
      expect(onnxPart.existsSync(), isFalse);
    });

    test('HTTPS dışı adres reddedilir (birim düzeyi kontrolü)', () async {
      PiperVoiceDownloader.allowInsecureHttpForTest = false; // Üretim varsayılanı

      final testVoice = const PiperVoice(
        id: 'insecure-test',
        lang: 'en_US',
        name: 'Insecure',
        onnxUrl: 'http://example.com/model.onnx',
        onnxSize: 100,
        onnxSha256: 'sha',
        jsonUrl: 'http://example.com/model.onnx.json',
        jsonSize: 10,
        jsonSha256: 'sha',
        license: 'CC0',
      );

      final downloader = PiperVoiceDownloader.instance;
      final ok = await downloader.download(testVoice);

      expect(ok, isFalse);
      expect(downloader.snapshot.status, PiperDownloadStatus.error);
      expect(downloader.snapshot.errorMessage, contains('HTTPS'));
    });

    test('beklenenden büyük yanıt akış sırasında hemen kesilir ve .part kalmaz', () async {
      PiperVoiceDownloader.allowInsecureHttpForTest = true;
      final oversizedBytes = List<int>.filled(500, 42);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((req) {
        req.response.bufferOutput = false;
        req.response.add(oversizedBytes);
        req.response.close();
      });

      final testVoice = PiperVoice(
        id: 'tr_TR-oversized-medium',
        lang: 'tr_TR',
        name: 'OversizedVoice',
        onnxUrl: 'http://${server!.address.host}:${server!.port}/model.onnx',
        onnxSize: 100,
        onnxSha256: 'some-sha',
        jsonUrl: 'http://${server!.address.host}:${server!.port}/model.onnx.json',
        jsonSize: 50,
        jsonSha256: 'some-json-sha',
        license: 'CC0',
      );

      final downloader = PiperVoiceDownloader.instance;
      final ok = await downloader.download(testVoice);

      expect(ok, isFalse);
      expect(downloader.snapshot.status, PiperDownloadStatus.error);
      expect(downloader.snapshot.errorMessage, anyOf(contains('Boyut'), contains('sınır')));

      final onnxPart = File('${tempDir.path}/${testVoice.id}.onnx.part');
      final onnxFinal = File('${tempDir.path}/${testVoice.id}.onnx');
      expect(onnxPart.existsSync(), isFalse);
      expect(onnxFinal.existsSync(), isFalse);
    });
  });

  group('Ses Seçiminin Saklanması ve Speech.selectedVoiceResolver', () {
    test('Settings toJson ve fromJson geriye uyumludur, seçim saklanır', () {
      final s = Settings();
      expect(s.selectedVoices, isEmpty);
      expect(s.toJson().containsKey('selectedVoices'), isFalse);

      s.selectedVoices['en'] = 'en_US-amy-medium';
      s.selectedVoices['tr'] = 'tr_TR-dfki-medium';
      final json = s.toJson();
      expect(json['selectedVoices'], isA<Map>());

      final loaded = Settings.fromJson(json);
      expect(loaded.selectedVoices['en'], 'en_US-amy-medium');
      expect(loaded.selectedVoices['tr'], 'tr_TR-dfki-medium');
    });

    test('AppState.selectVoice seçimi kaydeder ve Speech.selectedVoiceResolver üzerinden çözer', () async {
      final storage = MemoryStorage();
      final app = AppState(storage);
      Speech.selectedVoiceResolver = (lang) {
        final norm = lang.replaceAll('-', '_').toLowerCase().trim();
        final primary = norm.split('_').first;
        return app.settings.selectedVoices[norm] ??
            app.settings.selectedVoices[primary] ??
            app.settings.selectedVoices[lang];
      };
      await app.load();

      app.selectVoice('en', 'en_US-amy-medium');
      expect(Speech.selectedVoiceResolver, isNotNull);
      expect(Speech.selectedVoiceResolver!('en'), 'en_US-amy-medium');
      expect(Speech.selectedVoiceResolver!('en_US'), 'en_US-amy-medium');
      expect(Speech.selectedVoiceResolver!('en-US'), 'en_US-amy-medium');

      // Yeni AppState yüklendiğinde de kalır
      final app2 = AppState(storage);
      Speech.selectedVoiceResolver = (lang) {
        final norm = lang.replaceAll('-', '_').toLowerCase().trim();
        final primary = norm.split('_').first;
        return app2.settings.selectedVoices[norm] ??
            app2.settings.selectedVoices[primary] ??
            app2.settings.selectedVoices[lang];
      };
      await app2.load();
      expect(app2.settings.selectedVoices['en'], 'en_US-amy-medium');
      expect(Speech.selectedVoiceResolver!('en'), 'en_US-amy-medium');
    });
  });

  group('Doğal Sesler UI ve Platform Davranışı', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      Speech.resetLinuxForTest();
    });

    testWidgets('Linux ortamında ve Piper motoru varsa Doğal Sesler satırı görünür', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        Speech.piperExecutableOverride = '/app/piper/piper';

        final app = AppState(MemoryStorage());
        await app.load();
        app.companion = MascotId.puhu;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Palette.light),
            home: AppScope(state: app, child: const Scaffold(body: ProfileScreen())),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final row = find.byKey(const ValueKey('set-natural-voices-row'));
        await tester.scrollUntilVisible(row, 250, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(row);
        await tester.pump(const Duration(milliseconds: 300));
        expect(row, findsOneWidget);

        // Dokunulunca sheet açılır
        await tester.tap(row);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(NaturalVoicesSheet), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android ortamında Doğal Sesler satırı görünmez', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        Speech.piperExecutableOverride = '/app/piper/piper';

        final app = AppState(MemoryStorage());
        await app.load();
        app.companion = MascotId.puhu;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Palette.light),
            home: AppScope(state: app, child: const Scaffold(body: ProfileScreen())),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final row = find.byKey(const ValueKey('set-natural-voices-row'));
        expect(row, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Dar yükseklikte (892x412 isCompact) taşma hatası vermez', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(892, 412);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      try {
        Speech.piperExecutableOverride = '/app/piper/piper';

        final app = AppState(MemoryStorage());
        await app.load();
        app.companion = MascotId.puhu;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Palette.light),
            home: AppScope(state: app, child: const Scaffold(body: ProfileScreen())),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final row = find.byKey(const ValueKey('set-natural-voices-row'));
        await tester.scrollUntilVisible(row, 250, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(row);
        await tester.pump(const Duration(milliseconds: 300));
        expect(row, findsOneWidget);

        await tester.tap(row);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(NaturalVoicesSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
