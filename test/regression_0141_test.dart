import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/lesson/lesson_screen.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/mascot/mascot_view.dart';
import 'package:bilge/mascot/rig_view.dart';
import 'package:bilge/screens/welcome.dart';
import 'package:bilge/ui/io.dart';
import 'package:bilge/ui/theme.dart';
import 'package:bilge/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget testApp({required Widget child, AppState? state}) {
  final s = state ?? AppState(MemoryStorage());
  return AppScope(
    state: s,
    child: MaterialApp(
      theme: buildTheme(Palette.light),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ders ekranında arka plana geçişte oturum kaydı', () {
    testWidgets('uygulama paused durumuna geçince mevcut oturum kaydedilir', (tester) async {
      MascotView.animate = false;
      tester.view
        ..physicalSize = const Size(412, 892)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = MemoryStorage();
      final app = AppState(storage);
      final rawCourse = jsonEncode({
        'id': 'test-course',
        'title': 'Test Kursu',
        'units': [
          {
            'id': 'u1',
            'title': 'Ünite 1',
            'lessons': [
              {
                'id': 'l1',
                'title': 'Ders 1',
                'exercises': [
                  {'type': 'info', 'title': 'Giriş', 'body': 'İlk bilgi metni'},
                  {'type': 'truefalse', 'statement': 'Su ıslaktır.', 'answer': true},
                  {'type': 'truefalse', 'statement': 'Ateş soğuktur.', 'answer': false},
                ]
              }
            ]
          }
        ]
      });
      final c = parseCourse(rawCourse).course!;
      app.putCourse(c);
      final node = app.nodes(c).first;

      await tester.pumpWidget(testApp(state: app, child: LessonScreen(course: c, node: node)));
      await tester.pumpAndSettle();

      // Henüz soru/adım tamamlanmadı (_done == 0), session null olmalı
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(app.session, isNull);

      // Info adımında 'Devam' butonuna basarak adımı tamamla
      await tester.tap(find.byType(ChunkyButton));
      await tester.pumpAndSettle();

      // Şimdi _done = 1 oldu. Arka plana geçişi (paused) tetikle
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(app.session, isNotNull);
      expect(app.session!.courseId, c.id);
      expect(app.session!.done, 1);
      expect(app.session!.queueKeys.length, 2);

      // Tekrar resumed olunca ekran normal devam eder ve ikinci soru görünür
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Su ıslaktır.'), findsOneWidget);
    });
  });

  group('fetchText yönlendirme ve SSRF koruması', () {
    test('özel ağ IP adresleri ve geçersiz şemalar reddedilir', () async {
      expect(isPrivateHostForTest('localhost'), isTrue);
      expect(isPrivateHostForTest('127.0.0.1'), isTrue);
      expect(isPrivateHostForTest('192.168.1.10'), isTrue);
      expect(isPrivateHostForTest('10.0.0.1'), isTrue);
      expect(isPrivateHostForTest('172.16.5.1'), isTrue);
      expect(isPrivateHostForTest('example.local'), isTrue);
      expect(isPrivateHostForTest('example.com'), isFalse);

      await expectLater(
        fetchText('http://127.0.0.1/kurs.json'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        fetchText('http://192.168.1.1/kurs.json'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        fetchText('ftp://example.com/kurs.json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('HTTP yönlendirmeleri elle izlenir ve 5 adımı aşarsa hata verir', () async {
      var count = 0;
      final mockClient = MockClient((req) async {
        count++;
        return http.Response('', 302, headers: {'location': 'https://example.com/step$count'});
      });

      await expectLater(
        fetchText('https://example.com/step0', client: mockClient),
        throwsA(isA<HttpException>()),
      );
      expect(count, 6);
    });

    test('HTTP yönlendirmesi özel ağa yapılınca reddedilir', () async {
      final mockClient = MockClient((req) async {
        if (req.url.host == 'example.com') {
          return http.Response('', 302, headers: {'location': 'http://192.168.1.50/gizli.json'});
        }
        return http.Response('gizli icerik', 200);
      });

      await expectLater(
        fetchText('https://example.com/indir', client: mockClient),
        throwsA(isA<FormatException>()),
      );
    });

    test('HTTP yönlendirmesi 200 ile sonuçlanınca veri okunur', () async {
      final mockClient = MockClient((req) async {
        if (req.url.path == '/indir') {
          return http.Response('', 301, headers: {'location': 'https://cdn.example.com/sonuc.json'});
        }
        return http.Response('{"kurs": "basarili"}', 200);
      });

      final result = await fetchText('https://example.com/indir', client: mockClient);
      expect(result, '{"kurs": "basarili"}');
    });
  });

  group('TapCard Semantics selected durumu', () {
    testWidgets('seçili ve seçili olmayan durumlarda semantics selected bildirilir', (tester) async {
      await tester.pumpWidget(
        testApp(
          child: Scaffold(
            body: Column(
              children: [
                TapCard(
                  key: const ValueKey('card-idle'),
                  state: CardState.idle,
                  child: const Text('Boş'),
                ),
                TapCard(
                  key: const ValueKey('card-selected'),
                  state: CardState.selected,
                  child: const Text('Seçili'),
                ),
              ],
            ),
          ),
        ),
      );

      final idleSemantics = tester.getSemantics(find.byKey(const ValueKey('card-idle')));
      expect(idleSemantics.flagsCollection.isSelected == ui.Tristate.isTrue, isFalse);

      final selectedSemantics = tester.getSemantics(find.byKey(const ValueKey('card-selected')));
      expect(selectedSemantics.flagsCollection.isSelected == ui.Tristate.isTrue, isTrue);
    });
  });

  group('karşılama ekranı yatay 892x412 boyutta maskot sırası ve buton', () {
    testWidgets('892x412 yatay modda maskot sırası tek satırda kayar ve başla butonu ekrandadır', (tester) async {
      MascotView.animate = false;
      tester.view
        ..physicalSize = const Size(892, 412)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = MemoryStorage();
      final app = AppState(storage);

      await tester.pumpWidget(testApp(state: app, child: const WelcomeScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      // Karakter seçici tek satırda yatay kaydırılabilir olmalı
      final pickerScroll = find.descendant(
        of: find.byType(CharacterPicker),
        matching: find.byType(SingleChildScrollView),
      );
      expect(pickerScroll, findsOneWidget);

      final singleScroll = tester.widget<SingleChildScrollView>(pickerScroll);
      expect(singleScroll.scrollDirection, Axis.horizontal);

      // Başla butonu görünür ve ekranda kalmalı
      final button = find.byType(ChunkyButton);
      expect(button, findsOneWidget);
    });
  });

  group('Maskot uykudayken Ticker durdurma ve nefes alma', () {
    testWidgets('calm maskot uykuya daldığında Ticker durur, nefes timer başlar, dokununca uyanır', (tester) async {
      MascotView.animate = true;
      MascotView.drowsy.value = false;
      addTearDown(() {
        MascotView.animate = false;
        MascotView.drowsy.value = false;
      });

      await tester.pumpWidget(
        testApp(
          child: const Scaffold(
            body: Center(
              child: RigMascotView(
                MascotId.tarcin,
                calm: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final stateFinder = find.byType(RigMascotView);
      final dynamic state = tester.state(stateFinder);

      expect(state.isTickerActive, isTrue);
      expect(state.isSleepTimerActive, isFalse);

      // Maskotu uyut
      MascotView.drowsy.value = true;

      // Uykuya dalması için zaman ilerlet (yaklaşık 1.5 saniye dt * 0.8)
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Şimdi tam uyku durumunda olmalı: Ticker durmuş, sleep timer aktif
      expect(state.sleepValue, greaterThanOrEqualTo(1.0));
      expect(state.isTickerActive, isFalse);
      expect(state.isSleepTimerActive, isTrue);

      // Maskota dokunarak uyandır
      await tester.tap(stateFinder);
      await tester.pump();

      // Uyanmalı: sleep timer durur, Ticker tekrar başlar
      expect(MascotView.drowsy.value, isFalse);
      expect(state.isSleepTimerActive, isFalse);
      expect(state.isTickerActive, isTrue);
    });
  });
}
