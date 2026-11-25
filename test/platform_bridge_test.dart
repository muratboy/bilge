import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/l10n/l10n.dart';
import 'package:bilge/lesson/exercises.dart';
import 'package:bilge/main.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/screens/profile.dart';
import 'package:bilge/ui/incoming.dart';
import 'package:bilge/ui/io.dart';
import 'dart:math' as math;
import 'package:bilge/mascot/cast.dart';
import 'package:bilge/ui/sfx.dart';
import 'package:bilge/ui/speech.dart';
import 'package:bilge/ui/theme.dart';

Future<void> _loadFonts() async {
  final nunito = FontLoader('Nunito');
  for (final w in [600, 700, 800, 900]) {
    final f = File('assets/fonts/Nunito-$w.ttf');
    if (f.existsSync()) {
      nunito.addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
  }
  await nunito.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('hatırlatıcı açılırken platform başarısız dönerse ayar kapanır ve uyarı görünür', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const reminderChannel = MethodChannel('bilge/reminder');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(reminderChannel, (call) async {
      if (call.method == 'schedule') {
        final enabled = call.arguments['enabled'] as bool? ?? false;
        if (enabled) return false;
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(reminderChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;
    app.settings.reminder = false;

    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: buildTheme(Palette.light),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Ayarlara kaydır ve hatırlatıcı anahtarını açmayı dene
    final toggleFinder = find.byKey(const ValueKey('set-reminder-toggle'));
    await tester.scrollUntilVisible(toggleFinder, 250, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(toggleFinder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(app.settings.reminder, isFalse);
    expect(find.text(t('reminder.permissionDenied')), findsOneWidget);
  });

  testWidgets('gelen içerik okunamadı bildirimi gelince uyarı görünür', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
      if (call.method == 'take') return null;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app));
    await tester.pump(const Duration(milliseconds: 300));

    // Uygulama açıkken okunamayan içerik bildirimi gelir
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'bilge/incoming',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('incoming', Incoming.readFailed)),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsOneWidget);
  });

  testWidgets('içerik taşımayan açılışta uyarı görünmez', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
      if (call.method == 'take') return null;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsNothing);
    expect(find.text(t('incoming.failed')), findsNothing);
  });

  testWidgets('açılışta okunamayan dosya geldiğinde uyarı görünür', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
      if (call.method == 'take') return Incoming.readFailed;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsOneWidget);
  });

  test('Incoming.readArgs dosya yolu, file URI, boyut sınırı ve eksik dosyayı doğru işler', () async {
    final dir = await Directory.systemTemp.createTemp('bilge_args_test_');
    addTearDown(() => dir.delete(recursive: true));

    final good = File('${dir.path}/kurs.bilge.json')..writeAsStringSync('{"title":"Deneme"}');
    final big = File('${dir.path}/buyuk.bilge.json')..writeAsStringSync('1234567890');

    expect(await Incoming.readArgs([]), isNull);
    expect(await Incoming.readArgs(['--verbose']), isNull);
    expect(await Incoming.readArgs(['--flag', good.path]), '{"title":"Deneme"}');
    expect(await Incoming.readArgs([good.uri.toString()]), '{"title":"Deneme"}');
    expect(await Incoming.readArgs([big.path], maxBytes: 5), Incoming.tooBig);
    expect(await Incoming.readArgs(['${dir.path}/yok.bilge.json']), Incoming.readFailed);
    expect(await Incoming.readArgs([dir.path]), Incoming.readFailed);
  });

  testWidgets('açılışta komut satırından gelen okunamayan dosya uyarı gösterir', (tester) async {
    const incomingChannel = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    final app = AppState(MemoryStorage());
    await app.load();
    app.companion = MascotId.puhu;

    await tester.pumpWidget(BilgeApp(state: app, initialIncoming: Incoming.readFailed));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t('import.fileFailed')), findsOneWidget);
  });

  test('shareFile Linux ortamında seçilen yola yazar ve vazgeçilince hata atmaz', () async {
    if (!Platform.isLinux) return;
    final dir = await Directory.systemTemp.createTemp('bilge_share_test_');
    addTearDown(() {
      savePathPicker = null;
      dir.deleteSync(recursive: true);
    });

    final out = File('${dir.path}/cikti.bilge.json');
    String? seenName;
    savePathPicker = (name) async {
      seenName = name;
      return out.path;
    };
    await shareFile('deneme.bilge.json', '{"ok":true}');
    expect(seenName, 'deneme.bilge.json');
    expect(out.readAsStringSync(), '{"ok":true}');

    savePathPicker = (_) async => null;
    await shareFile('iptal.bilge.json', '{}');
  });

  test('Sfx Linux ortamında WAV varlığını çözüp yerel yürütücüye iletir', () async {
    if (!Platform.isLinux) return;
    final prevEnabled = Sfx.enabled;
    final prevAvailable = Sfx.available;
    addTearDown(() {
      Sfx.enabled = prevEnabled;
      Sfx.available = prevAvailable;
      Sfx.resetLinuxForTest();
    });

    Sfx.resetLinuxForTest();
    Sfx.enabled = true;
    Sfx.available = true;
    String? played;
    Sfx.linuxPlayer = (path) async {
      played = path;
      return true;
    };

    await Sfx.play('pop');
    expect(played, isNotNull);
    final file = File(played!);
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync().sublist(0, 4), [0x52, 0x49, 0x46, 0x46]); // RIFF
    addTearDown(() {
      if (file.parent.path.contains('bilge-sfx-') && file.parent.existsSync()) {
        file.parent.deleteSync(recursive: true);
      }
    });

    Sfx.linuxPlayer = (_) async => false;
    await Sfx.play('tap');
    expect(Sfx.available, isFalse);
  });

  testWidgets('günlük hatırlatıcı ayarı Linux masaüstünde gizlenir, Android ortamında görünür', (tester) async {
    final storage = MemoryStorage();
    final app = AppState(storage);
    await app.load();
    app.companion = MascotId.puhu;

    // Varsayılan test ortamında (TargetPlatform.android) görünür
    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: buildTheme(Palette.light),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final toggleFinder = find.byKey(const ValueKey('set-reminder-toggle'));
    await tester.scrollUntilVisible(toggleFinder, 250, scrollable: find.byType(Scrollable).first);
    expect(toggleFinder, findsOneWidget);

    // Linux masaüstünde gizlenir
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: buildTheme(Palette.light),
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('set-reminder-toggle')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sahte kanaldan gelen Linux dosya yolu içe aktarma önizlemesini açar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      const incomingChannel = MethodChannel('bilge/incoming');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

      final dir = Directory.systemTemp.createTempSync('bilge_linux_incoming_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/test.bilge.json')
        ..writeAsStringSync('{"id":"linux-test","title":"Linux Kursu","units":[{"id":"u1","title":"Bir","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}');

      final storage = MemoryStorage();
      final app = AppState(storage);
      await app.load();
      app.companion = MascotId.puhu;

      await tester.pumpWidget(BilgeApp(state: app));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'bilge/incoming',
        const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', file.path)),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(t('import.addCourse').toUpperCase()), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sahte kanaldan gelen çok büyük Linux dosyası tooBig uyarısı verir', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      const incomingChannel = MethodChannel('bilge/incoming');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

      final dir = Directory.systemTemp.createTempSync('bilge_linux_big_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/buyuk.bilge.json');
      final raf = file.openSync(mode: FileMode.write);
      raf.setPositionSync(maxCourseBytes + 10);
      raf.writeByteSync(0);
      raf.closeSync();

      final storage = MemoryStorage();
      final app = AppState(storage);
      await app.load();
      app.companion = MascotId.puhu;

      await tester.pumpWidget(BilgeApp(state: app));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'bilge/incoming',
        const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', file.path)),
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(t('err.tooBig', {'mb': maxCourseBytes ~/ (1024 * 1024)})), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sahte kanaldan gelen okunamayan Linux dosya yolu readFailed uyarısı verir', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      const incomingChannel = MethodChannel('bilge/incoming');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

      final storage = MemoryStorage();
      final app = AppState(storage);
      await app.load();
      app.companion = MascotId.puhu;

      await tester.pumpWidget(BilgeApp(state: app));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'bilge/incoming',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('incoming', '/gecersiz/dosya/yolu.bilge.json')),
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(t('import.fileFailed')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('açılışta sahte kanaldan take ile gelen dosya yolu içe aktarma önizlemesini açar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final dir = Directory.systemTemp.createTempSync('bilge_linux_take_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/take.bilge.json')
        ..writeAsStringSync('{"id":"linux-take","title":"Take Kursu","units":[{"id":"u1","title":"Bir","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}');

      const incomingChannel = MethodChannel('bilge/incoming');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async {
        if (call.method == 'take') return file.path;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

      final storage = MemoryStorage();
      final app = AppState(storage);
      await app.load();
      app.companion = MascotId.puhu;

      await tester.pumpWidget(BilgeApp(state: app));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(t('import.addCourse').toUpperCase()), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Android ortamında "/" ile başlayan paylaşılan metin dosya olarak okunmaz, metin olarak işlenir', () async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final dir = Directory.systemTemp.createTempSync('bilge_android_share_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/gizli.txt')..writeAsStringSync('gizli dosya icerigi');

    const incomingChannel = MethodChannel('bilge/incoming');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, (call) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(incomingChannel, null));

    String? received;
    await Incoming.listen((text) => received = text);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'bilge/incoming',
      const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', file.path)),
      (_) {},
    );

    expect(received, file.path);
    expect(received, isNot(contains('gizli dosya icerigi')));
  });

  test('linux/packaging/AppRun XDG_DATA_DIRS boşken sistem varsayılanını ekler', () {
    final appRun = File('linux/packaging/AppRun').readAsStringSync();
    expect(appRun, contains(r'${XDG_DATA_DIRS:-/usr/local/share:/usr/share}'));
  });

  test('Speech sahte yürütücüde espeak-ng ve spd-say kullanılabilir görünse bile hiçbiri çalıştırılmaz', () async {
    addTearDown(Speech.resetLinuxForTest);
    final exec = FakeSpeechExecutor(programs: ['espeak-ng', 'espeak', 'spd-say']);
    Speech.resetLinuxForTest();
    Speech.linuxExecutor = exec;

    expect(await Speech.speak('hello', lang: 'en'), isFalse);
    expect(exec.startCalls, isEmpty);
    expect(exec.runCalls, isEmpty);
    expect(Speech.lastBackend, isNull);
  });

  group('Piper doğal ses motoru', () {
    late Directory tempVoicesDir;

    setUp(() {
      tempVoicesDir = Directory.systemTemp.createTempSync('bilge_test_voices_');
      Speech.resetLinuxForTest();
      Speech.voicesDirOverride = tempVoicesDir;
      Speech.piperExecutableOverride = '/app/piper/piper';
    });

    tearDown(() {
      Speech.resetLinuxForTest();
      try {
        if (tempVoicesDir.existsSync()) tempVoicesDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    void createVoice(String id) {
      File('${tempVoicesDir.path}/$id.onnx').writeAsStringSync('dummy model');
      File('${tempVoicesDir.path}/$id.onnx.json').writeAsStringSync('{}');
    }

    test('Piper seçimi: Piper motoru ve indirilen ses varsa espeak ve spd-say yerine Piper kullanılır', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play', 'espeak-ng', 'spd-say']);
      Speech.linuxExecutor = exec;

      expect(Speech.hasPiperEngine, isTrue);
      expect(await Speech.speak('Merhaba Bilge', lang: 'tr'), isTrue);

      expect(exec.startCalls.length, 2);
      expect(exec.startCalls[0].executable, '/app/piper/piper');
      expect(exec.startCalls[1].executable, 'pw-play');
      expect(Speech.lastBackend, 'piper');
      expect(exec.startCalls.any((c) => c.executable == 'espeak-ng' || c.executable == 'spd-say'), isFalse);
    });

    test('model yolu ve --length_scale: yavaş okumada length_scale verilir, normalde verilmez', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play']);
      Speech.linuxExecutor = exec;

      // Normal hız
      expect(await Speech.speak('Normal hız', lang: 'tr', slow: false), isTrue);
      final normalPiperCall = exec.startCalls.first;
      final mIdx = normalPiperCall.arguments.indexOf('--model');
      expect(mIdx, isNonNegative);
      expect(normalPiperCall.arguments[mIdx + 1], '${tempVoicesDir.path}/tr_TR-dfki-medium.onnx');
      expect(normalPiperCall.arguments, isNot(contains('--length_scale')));

      // Yavaş hız
      exec.startCalls.clear();
      expect(await Speech.speak('Yavaş hız', lang: 'tr', slow: true), isTrue);
      final slowPiperCall = exec.startCalls.first;
      final lsIdx = slowPiperCall.arguments.indexOf('--length_scale');
      expect(lsIdx, isNonNegative);
      expect(slowPiperCall.arguments[lsIdx + 1], '1.67');
    });

    test('metnin stdin ile gitmesi: satır sonları boşluğa çevrilir, kabuk kullanılmaz', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play']);
      Speech.linuxExecutor = exec;

      expect(await Speech.speak("İlk satır.\nİkinci satır.\r\nÜçüncü satır.", lang: 'tr'), isTrue);
      final piperCall = exec.startCalls.first;
      expect(piperCall.runInShell, isFalse);
      expect(exec.startedProcesses.first.stdinText, 'İlk satır. İkinci satır. Üçüncü satır.');
    });

    test('dil eşleme (bölge ve birincil dil): önce tam bölge, yoksa birincil dil, birden çok seste kanca veya alfabetik ilk ses', () async {
      createVoice('en_US-lessac-medium');
      createVoice('en_GB-alan-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play']);
      Speech.linuxExecutor = exec;

      // Tam bölge eşleşmesi (en-US -> en_US-lessac-medium)
      expect(await Speech.speak('Hello US', lang: 'en-US'), isTrue);
      expect(exec.startCalls.first.arguments, contains('${tempVoicesDir.path}/en_US-lessac-medium.onnx'));

      // Bölge bulunamadığında birincil dil (en-AU -> alfabetik ilk: en_GB-alan-medium)
      exec.startCalls.clear();
      expect(await Speech.speak('Hello AU', lang: 'en-AU'), isTrue);
      expect(exec.startCalls.first.arguments, contains('${tempVoicesDir.path}/en_GB-alan-medium.onnx'));

      // Birincil dil (en -> alfabetik ilk: en_GB-alan-medium)
      exec.startCalls.clear();
      expect(await Speech.speak('Hello EN', lang: 'en'), isTrue);
      expect(exec.startCalls.first.arguments, contains('${tempVoicesDir.path}/en_GB-alan-medium.onnx'));

      // Kanca ile ses seçimi
      Speech.selectedVoiceResolver = (lang) => 'en_US-lessac-medium';
      exec.startCalls.clear();
      expect(await Speech.speak('Hello EN selected', lang: 'en'), isTrue);
      expect(exec.startCalls.first.arguments, contains('${tempVoicesDir.path}/en_US-lessac-medium.onnx'));
    });

    test('Piper sesi yoksa speak false döner', () async {
      // Sadece tr sesi var, en isteniyor
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play', 'espeak-ng', 'spd-say']);
      Speech.linuxExecutor = exec;

      expect(await Speech.speak('Hello world', lang: 'en'), isFalse);
      expect(exec.startCalls, isEmpty);
      expect(Speech.lastBackend, isNull);
    });

    test('stop hem piper sürecini hem yürütücü sürecini durdurur', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play']);
      Speech.linuxExecutor = exec;

      // 1) Yürütücü çalarken stop()
      expect(await Speech.speak('Çalıyor', lang: 'tr'), isTrue);
      final playerProc = exec.startedProcesses[1];
      expect(playerProc.killed, isFalse);

      await Speech.stop();
      expect(playerProc.killed, isTrue);

      // 2) Piper sentez yaparken stop()
      final slowPiperExec = FakeSpeechExecutor(
        programs: ['piper', 'pw-play'],
        autoExitPiperOnStdinClose: false,
      );
      Speech.linuxExecutor = slowPiperExec;
      final speakFuture = Speech.speak('Uzun sentez', lang: 'tr');
      await Future<void>.delayed(Duration.zero);
      final piperProc = slowPiperExec.startedProcesses.first;
      expect(piperProc.killed, isFalse);

      await Speech.stop();
      expect(piperProc.killed, isTrue);
      expect(await speakFuture, isTrue);
    });

    test('sentez sırasında stop() çağrılınca espeak başlamaz, hiçbir şey çalmaz ve true döner', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(
        programs: ['piper', 'pw-play', 'espeak-ng', 'spd-say'],
        autoExitPiperOnStdinClose: false,
      );
      Speech.linuxExecutor = exec;

      final speakFuture = Speech.speak('Uzun sentez', lang: 'tr');
      await Future<void>.delayed(Duration.zero);
      expect(exec.startedProcesses.length, 1);
      final piperProc = exec.startedProcesses.first;
      expect(piperProc.killed, isFalse);

      await Speech.stop();
      expect(piperProc.killed, isTrue);
      expect(await speakFuture, isTrue);
      expect(exec.startCalls.any((c) => c.executable == 'espeak-ng' || c.executable == 'spd-say'), isFalse);
      expect(exec.startCalls.any((c) => c.executable == 'pw-play'), isFalse);
    });

    test('hızlı ardışık iki speak çağrısında yalnızca ikincisi çalar ve ilki yedeğe düşmez', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(
        programs: ['piper', 'pw-play', 'espeak-ng', 'spd-say'],
        autoExitPiperOnStdinClose: false,
      );
      Speech.linuxExecutor = exec;

      final f1 = Speech.speak('İlk çağrı', lang: 'tr');
      await Future<void>.delayed(Duration.zero);
      expect(exec.startedProcesses.length, 1);
      final firstProc = exec.startedProcesses.first;

      final f2 = Speech.speak('İkinci çağrı', lang: 'tr');
      await Future<void>.delayed(Duration.zero);

      expect(firstProc.killed, isTrue);
      expect(exec.startedProcesses.length, 2);
      final secondProc = exec.startedProcesses[1];
      secondProc.exitCompleter.complete(0);

      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isTrue);
      expect(r2, isTrue);

      expect(exec.startCalls.where((c) => c.executable == 'pw-play').length, 1);
      expect(exec.startCalls.any((c) => c.executable == 'espeak-ng' || c.executable == 'spd-say'), isFalse);
    });

    test('geçici WAV dosyası çalma bitince veya stop edilince silinir', () async {
      createVoice('tr_TR-dfki-medium');
      final exec = FakeSpeechExecutor(programs: ['piper', 'pw-play']);
      Speech.linuxExecutor = exec;

      expect(await Speech.speak('Geçici dosya testi', lang: 'tr'), isTrue);
      final playerCall = exec.startCalls[1];
      final wavPath = playerCall.arguments.first;
      final wavFile = File(wavPath);
      expect(wavFile.existsSync(), isTrue);

      // Çalma bitince dosya silinir
      exec.startedProcesses[1].exitCompleter.complete(0);
      await Future<void>.delayed(Duration.zero);
      expect(wavFile.existsSync(), isFalse);

      // Tekrar başlatıp stop ile durdurunca da dosya silinir
      exec.startCalls.clear();
      exec.startedProcesses.clear();
      expect(await Speech.speak('İkinci geçici dosya', lang: 'tr'), isTrue);
      final secondWavFile = File(exec.startCalls[1].arguments.first);
      expect(secondWavFile.existsSync(), isTrue);

      await Speech.stop();
      expect(secondWavFile.existsSync(), isFalse);
    });

    testWidgets("Linux'ta Piper motoru varken ders ekranında 'ses yok' mesajıyla doğal ses ipucu görünür", (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final exec = FakeSpeechExecutor(
          programs: ['piper', 'pw-play', 'espeak-ng', 'spd-say'],
        );
        Speech.linuxExecutor = exec;

        final ex = Exercise({
          'type': 'info',
          'title': 'Test',
          'say': 'Hello world',
        });

        // 1) Piper motoru var ama ses yok -> Profil › Doğal sesler ipucu ile ses yok mesajı
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Palette.light),
            home: Scaffold(
              body: ExerciseView(
                key: const ValueKey('f_piper_no_voice'),
                exercise: ex,
                host: characterOf(MascotId.puhu),
                color: Colors.blue,
                locale: 'tr',
                speechLang: 'en',
                random: math.Random(1),
                onReady: (_) {},
                onDone: (_) {},
                onSubmit: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byIcon(Icons.volume_up_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('${t('lesson.noVoice', {'lang': 'en'})} ${t('lesson.naturalVoiceHint')}'), findsOneWidget);

        // 2) Piper motoru yok -> Yalnızca ses yok mesajı, doğal ses ipucu yok
        Speech.resetLinuxForTest();
        Speech.voicesDirOverride = tempVoicesDir;
        Speech.piperExecutableOverride = null;
        Speech.linuxExecutor = FakeSpeechExecutor(programs: ['pw-play']);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Palette.light),
            home: Scaffold(
              body: ExerciseView(
                key: const ValueKey('f_no_piper_engine'),
                exercise: ex,
                host: characterOf(MascotId.puhu),
                color: Colors.blue,
                locale: 'tr',
                speechLang: 'en',
                random: math.Random(1),
                onReady: (_) {},
                onDone: (_) {},
                onSubmit: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byIcon(Icons.volume_up_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(t('lesson.noVoice', {'lang': 'en'})), findsOneWidget);
        expect(find.textContaining(t('lesson.naturalVoiceHint')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

class FakeProcess implements Process {
  FakeProcess({this.exitCodeValue = 0, this.autoExitOnStdinClose = false});

  final int exitCodeValue;
  final bool autoExitOnStdinClose;
  final Completer<int> exitCompleter = Completer<int>();
  final _stdinController = StreamController<List<int>>();
  late final IOSink _stdinSink = IOSink(_stdinController);
  final List<int> stdinBytes = [];
  bool killed = false;

  void init() {
    _stdinController.stream.listen(
      stdinBytes.addAll,
      onDone: () {
        if (!exitCompleter.isCompleted && autoExitOnStdinClose) {
          exitCompleter.complete(exitCodeValue);
        }
      },
    );
  }

  String get stdinText => utf8.decode(stdinBytes, allowMalformed: true);

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!exitCompleter.isCompleted) exitCompleter.complete(exitCodeValue);
    return true;
  }

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  IOSink get stdin => _stdinSink;
}

class FakeCall {
  FakeCall(this.executable, this.arguments, {required this.runInShell});
  final String executable;
  final List<String> arguments;
  final bool runInShell;
}

class FakeSpeechExecutor implements LinuxSpeechExecutor {
  FakeSpeechExecutor({
    this.programs = const ['pw-play'],
    this.voices = '',
    this.autoExitPiperOnStdinClose = true,
  });

  final List<String>? programs;
  final String voices;
  final bool autoExitPiperOnStdinClose;

  @override
  List<String>? get availablePrograms => programs;

  final List<FakeCall> runCalls = [];
  final List<FakeCall> startCalls = [];
  final List<FakeProcess> startedProcesses = [];
  FakeProcess? lastProcess;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments, {bool runInShell = false}) async {
    runCalls.add(FakeCall(executable, arguments, runInShell: runInShell));
    return ProcessResult(4242, 0, voices, '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments, {bool runInShell = false}) async {
    startCalls.add(FakeCall(executable, arguments, runInShell: runInShell));
    final isPiper = executable.contains('piper');
    final proc = FakeProcess(autoExitOnStdinClose: isPiper && autoExitPiperOnStdinClose)..init();
    lastProcess = proc;
    startedProcesses.add(proc);
    if (isPiper) {
      final outIdx = arguments.indexOf('--output_file');
      if (outIdx >= 0 && outIdx + 1 < arguments.length) {
        final outPath = arguments[outIdx + 1];
        try {
          File(outPath).writeAsStringSync('RIFF_DUMMY_AUDIO');
        } catch (_) {}
      }
    }
    return proc;
  }
}

