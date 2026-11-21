import 'dart:convert';

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/core/text_utils.dart';
import 'package:bilge/l10n/l10n.dart';
import 'package:bilge/lesson/lesson_screen.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/ui/theme.dart';
import 'package:bilge/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp({required Widget child, AppState? state}) {
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
  group('streak getter ve saveResult dondurma tutarlılığı', () {
    test('bugün veya dün aktif olunduğunda seri sürer', () {
      final fixed = DateTime(2026, 10, 4, 12);
      final storage = MemoryStorage();
      final app = AppState(storage, clock: () => fixed);
      final t = app.today;

      // Dün ders yapılmış
      app.profile.streak = 5;
      app.profile.lastActive = addDays(t, -1);
      expect(app.streak, 5);

      // Bugün ders tamamlandığında seri 6'ya çıkar
      final res = LessonResult(
        courseId: 'c1',
        node: const PathNode(id: 'l1', title: 'L1', kind: NodeKind.lesson, unitIndex: 0),
        stars: 3,
        xp: 10,
        perfect: true,
        questions: 1,
        firstTry: 1,
        maxCombo: 1,
        wrongKeys: const {},
        rightKeys: const {'l1#0'},
      );
      app.completeLesson(res);
      expect(app.profile.streak, 6);
      expect(app.streak, 6);
    });

    test('1 gün boşlukta dondurma hakkı varsa ekranda görünür ve ders yapılınca harcanır', () {
      final fixed = DateTime(2026, 10, 4, 12);
      final storage = MemoryStorage();
      final app = AppState(storage, clock: () => fixed);
      final t = app.today;

      // 2 gün önce aktif olunmuş, 1 dondurma hakkı var
      app.profile.streak = 7;
      app.profile.freezes = 1;
      app.profile.lastActive = addDays(t, -2);

      // Ekranda seri dondurma hakkıyla korunur
      expect(app.streak, 7);

      // Ders yapılınca dondurma tutarlı biçimde harcanır ve seri artar
      final res = LessonResult(
        courseId: 'c1',
        node: const PathNode(id: 'l1', title: 'L1', kind: NodeKind.lesson, unitIndex: 0),
        stars: 3,
        xp: 10,
        perfect: true,
        questions: 1,
        firstTry: 1,
        maxCombo: 1,
        wrongKeys: const {},
        rightKeys: const {'l1#0'},
      );
      final outcome = app.completeLesson(res);
      expect(outcome.freezeUsed, isTrue);
      expect(app.profile.freezes, 0);
      expect(app.profile.streak, 8);
      expect(app.streak, 8);
    });

    test('1 gün boşlukta dondurma hakkı yoksa ekran seriyi kopmuş (0) gösterir, ders yapılınca 1 olur', () {
      final fixed = DateTime(2026, 10, 4, 12);
      final storage = MemoryStorage();
      final app = AppState(storage, clock: () => fixed);
      final t = app.today;

      // 2 gün önce aktif olunmuş, dondurma hakkı yok
      app.profile.streak = 7;
      app.profile.freezes = 0;
      app.profile.lastActive = addDays(t, -2);

      // Ekran seriyi kopmuş gösterir
      expect(app.streak, 0);

      // Ders yapılınca seri 1 olur
      final res = LessonResult(
        courseId: 'c1',
        node: const PathNode(id: 'l1', title: 'L1', kind: NodeKind.lesson, unitIndex: 0),
        stars: 3,
        xp: 10,
        perfect: true,
        questions: 1,
        firstTry: 1,
        maxCombo: 1,
        wrongKeys: const {},
        rightKeys: const {'l1#0'},
      );
      final outcome = app.completeLesson(res);
      expect(outcome.freezeUsed, isFalse);
      expect(app.profile.streak, 1);
      expect(app.streak, 1);
    });
  });

  group('LessonItem nesne eşitliği (operator == ve hashCode)', () {
    test('aynı key ve aynı from içeren farklı instance lar eşittir ve Set/List işlemlerinde çalışır', () {
      final courseA = Course(id: 'kurs-a', title: 'A', units: const []);
      final ex1 = Exercise(const {'type': 'choice', 'question': 'Soru', 'answer': 'Cevap'});
      final ex2 = Exercise(const {'type': 'choice', 'question': 'Soru Düzeltildi', 'answer': 'Cevap'});

      final item1 = LessonItem(ex1, 'ders1#0', from: courseA);
      final item2 = LessonItem(ex2, 'ders1#0', from: courseA);

      expect(item1, equals(item2));
      expect(item1.hashCode, equals(item2.hashCode));

      final set = <LessonItem>{item1};
      expect(set.contains(item2), isTrue);

      final removed = set.remove(item2);
      expect(removed, isTrue);
      expect(set.isEmpty, isTrue);
    });

    test('farklı kurslardaki aynı key li öğeler çakışmaz', () {
      final courseA = Course(id: 'kurs-a', title: 'A', units: const []);
      final courseB = Course(id: 'kurs-b', title: 'B', units: const []);
      final ex = Exercise(const {'type': 'choice', 'question': 'Soru', 'answer': 'Cevap'});

      final itemA = LessonItem(ex, 'ortak#0', from: courseA);
      final itemB = LessonItem(ex, 'ortak#0', from: courseB);

      expect(itemA, isNot(equals(itemB)));
      expect(itemA.hashCode, isNot(equals(itemB.hashCode)));

      final set = <LessonItem>{itemA};
      expect(set.contains(itemB), isFalse);
      expect(set.remove(itemB), isFalse);
      expect(set.contains(itemA), isTrue);
    });

    test('from null olduğunda kendi içinde key ile eşitlik sağlanır', () {
      final ex1 = Exercise(const {'type': 'choice', 'question': 'Q1'});
      final ex2 = Exercise(const {'type': 'choice', 'question': 'Q2'});

      final it1 = LessonItem(ex1, 'u1#0');
      final it2 = LessonItem(ex2, 'u1#0');
      final itDiff = LessonItem(ex1, 'u1#1');

      expect(it1, equals(it2));
      expect(it1, isNot(equals(itDiff)));

      final list = [it1];
      expect(list.contains(it2), isTrue);
      expect(list.indexOf(it2), 0);
    });

    test('soru düzenlendiğinde (_editCurrent) _wrong listesinden _flag ile kaldırılabilir', () {
      final course = Course(id: 'kurs-1', title: 'Kurs', units: const []);
      final originalEx = Exercise(const {'type': 'choice', 'question': 'Eski Soru', 'answer': 'A'});
      final editedEx = Exercise(const {'type': 'choice', 'question': 'Yeni Soru', 'answer': 'B'});

      final originalItem = LessonItem(originalEx, 'lesson1#2', from: course);
      final wrongSet = <LessonItem>{originalItem};

      // Kullanıcı soruyu düzenledi: yeni LessonItem üretildi
      final editedItem = LessonItem(editedEx, 'lesson1#2', from: course);

      // Hatalı işaretleme anında _wrong.remove(cur.item) çağrılır
      final removed = wrongSet.remove(editedItem);
      expect(removed, isTrue, reason: 'Düzenlenmiş öğe eski instance ı Set ten silebilmelidir');
      expect(wrongSet.isEmpty, isTrue);
    });
  });

  group('Bidi karakter temizliği ve RTL işaretlerinin korunması', () {
    test('U+202A-U+202E ve U+2066-U+2069 silinir, LRM/RLM/ALM korunur', () {
      const overrides = '\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069';
      const lrm = '\u200E';
      const rlm = '\u200F';
      const alm = '\u061C';

      final jsonStr = jsonEncode({
        'id': 'bidi-test',
        'title': 'Başlık$overrides ile $lrm ve $rlm',
        'description': 'Açıklama$overrides metni',
        'units': [
          {
            'id': 'u1',
            'title': 'Ünite$overrides 1',
            'lessons': [
              {
                'id': 'l1',
                'title': 'Ders 1',
                'exercises': [
                  {
                    'type': 'choice',
                    'question': 'Soru$overrides$lrm? $alm',
                    'options': ['Şık A$overrides', 'Şık B$rlm', 'Şık C'],
                    'answer': 'Şık A$overrides',
                    'explain': 'Açıklama$overrides'
                  },
                  {
                    'type': 'flashcard',
                    'front': 'Ön yüz$overrides$lrm',
                    'back': 'Arka yüz$overrides$rlm',
                  }
                ]
              }
            ]
          }
        ]
      });

      final report = parseCourse(jsonStr);
      expect(report.course, isNotNull);
      final course = report.course!;

      // Başlıkta overrides silinir, LRM/RLM kalır
      expect(course.title, contains(lrm));
      expect(course.title, contains(rlm));
      for (final code in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]) {
        expect(course.title.contains(String.fromCharCode(code)), isFalse);
      }

      // Soru metni
      final ex1 = course.units[0].lessons[0].exercises[0];
      final q = ex1.text('question');
      expect(q, contains(lrm));
      expect(q, contains(alm));
      for (final code in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]) {
        expect(q.contains(String.fromCharCode(code)), isFalse);
      }

      // Şıklar ve cevap
      expect(ex1.text('answer'), 'Şık A');
      final dist0 = ex1.list('distractors')[0];
      expect(dist0, 'Şık B$rlm');
      final dist1 = ex1.list('distractors')[1];
      expect(dist1, 'Şık C');

      // Ezber kartı
      final ex2 = course.units[0].lessons[0].exercises[1];
      expect(ex2.text('front'), 'Ön yüz$lrm');
      expect(ex2.text('back'), 'Arka yüz$rlm');
    });

    test('cevap karşılaştırması: bidi override karakterleri temizlenerek eşleşir', () {
      const overrides = '\u202E'; // Right-to-Left Override
      final answers = ['merhaba dünya', 'selam'];

      // Kullanıcı girdisinde override karakteri olsa bile norm() temizler
      final match1 = compareAnswer('merhaba$overrides dünya', answers);
      expect(match1, isNotNull);
      expect(match1!.kind, MatchKind.exact);

      // Sayısal cevapta override karakteri
      final numMatch = compareNumber('$overrides 42', 42);
      expect(numMatch, isNotNull);
      expect(numMatch!.exact, isTrue);

      // LRM ve RLM işaretleri semantik olarak korunur
      const lrm = '\u200E';
      final arabicMatch = compareAnswer('عربي$lrm', ['عربي$lrm']);
      expect(arabicMatch, isNotNull);
      expect(arabicMatch!.kind, MatchKind.exact);
    });
  });

  group('ders deneyimi düzeltmeleri', () {
    testWidgets('hızlı çift dokunuşta geri bildirim paneli açık kalır ve 400 ms sonra Devam çalışır', (tester) async {
      final course = parseCourse(jsonEncode({
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
                  {'type': 'truefalse', 'statement': 'Soru 1', 'answer': true},
                  {'type': 'truefalse', 'statement': 'Soru 2', 'answer': true},
                ]
              }
            ]
          }
        ]
      })).course!;

      final app = AppState(MemoryStorage());
      await app.load();
      app.companion = MascotId.tarcin;
      app.putCourse(course);
      final node = app.nodes(course).first;

      await tester.pumpWidget(_testApp(state: app, child: LessonScreen(course: course, node: node)));
      await tester.pumpAndSettle();

      // Soru 1 ekranda
      expect(find.text('Soru 1'), findsOneWidget);

      // Doğru seçeneğine tıkla
      await tester.tap(find.text(t('lesson.true')));
      await tester.pumpAndSettle();

      // Kontrol et butonuna tıkla
      await tester.tap(find.text(upper(t('lesson.check'))));
      await tester.pump(const Duration(milliseconds: 50));

      // Geri bildirim aşamasına geçildi, buton 'DEVAM' oldu
      expect(find.text(upper(t('common.continue'))), findsOneWidget);

      // 400 ms dolmadan hemen ikinci kez bas (hızlı çift dokunuş)
      await tester.tap(find.text(upper(t('common.continue'))));
      await tester.pump(const Duration(milliseconds: 50));

      // Kilit devrede: panel açık kalmalı, sonraki soruya geçilmemeli
      expect(find.text(upper(t('common.continue'))), findsOneWidget);
      expect(find.text('Soru 2'), findsNothing);

      // 400 ms kilidin dolmasını bekle
      await tester.pump(const Duration(milliseconds: 350));

      // Şimdi Devam butonuna bas
      await tester.tap(find.text(upper(t('common.continue'))));
      await tester.pumpAndSettle();

      // Sonraki soruya başarıyla geçildi
      expect(find.text('Soru 2'), findsOneWidget);
    });

    testWidgets('eşleştirmede ve kategoride kaybedince doğru cevap panelde görünür', (tester) async {
      // 1. Eşleştirme adımı
      final matchCourse = parseCourse(jsonEncode({
        'id': 'match-c',
        'title': 'Eşleştirme',
        'units': [
          {
            'id': 'u1',
            'title': 'U1',
            'lessons': [
              {
                'id': 'l1',
                'title': 'L1',
                'exercises': [
                  {
                    'type': 'match',
                    'pairs': [
                      ['A', '1'],
                      ['B', '2']
                    ]
                  }
                ]
              }
            ]
          }
        ]
      })).course!;

      final app1 = AppState(MemoryStorage());
      await app1.load();
      app1.companion = MascotId.tarcin;
      app1.putCourse(matchCourse);
      final matchNode = app1.nodes(matchCourse).first;

      await tester.pumpWidget(_testApp(state: app1, child: LessonScreen(key: const ValueKey('match'), course: matchCourse, node: matchNode)));
      await tester.pumpAndSettle();

      // 2 kez hatalı eşleştir
      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('2'));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('2'));
      await tester.pump(const Duration(milliseconds: 50));

      // Doğru eşleştirerek bitir
      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('1'));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('B'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('2'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // 2 hata ile kaybedildi: doğru cevap paneli görünmeli
      expect(find.text(upper(t('lesson.correctAnswer'))), findsOneWidget);
      expect(find.textContaining('A → 1'), findsOneWidget);
      expect(find.textContaining('B → 2'), findsOneWidget);

      // 2. Kategori adımı
      final catCourse = parseCourse(jsonEncode({
        'id': 'cat-c',
        'title': 'Kategori',
        'units': [
          {
            'id': 'u1',
            'title': 'U1',
            'lessons': [
              {
                'id': 'l1',
                'title': 'L1',
                'exercises': [
                  {
                    'type': 'categorize',
                    'categories': [
                      {'name': 'Meyve', 'items': ['Elma', 'Armut']},
                      {'name': 'Sebze', 'items': ['Pırasa']}
                    ]
                  }
                ]
              }
            ]
          }
        ]
      })).course!;

      final app2 = AppState(MemoryStorage());
      await app2.load();
      app2.companion = MascotId.tarcin;
      app2.putCourse(catCourse);
      final catNode = app2.nodes(catCourse).first;

      await tester.pumpWidget(_testApp(state: app2, child: LessonScreen(key: const ValueKey('cat'), course: catCourse, node: catNode)));
      await tester.pumpAndSettle();

      // İlk 2 öğeyi ters kovaya at (2 hata)
      await tester.tap(find.byWidgetPredicate((w) => w is MdInline && w.text == 'Sebze'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byWidgetPredicate((w) => w is MdInline && w.text == 'Sebze'));
      await tester.pump(const Duration(milliseconds: 100));

      // 3. öğeyi de atarak tamamla
      await tester.tap(find.byWidgetPredicate((w) => w is MdInline && w.text == 'Sebze'));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      // 2 hata ile kaybedildi: doğru kategoriler panelde görünmeli
      expect(find.text(upper(t('lesson.correctAnswer'))), findsOneWidget);
      expect(find.textContaining('Meyve: Elma, Armut'), findsOneWidget);
      expect(find.textContaining('Sebze: Pırasa'), findsOneWidget);
    });

    testWidgets('düzenlenen sorunun paneli yeni cevabı gösterir', (tester) async {
      final course = parseCourse(jsonEncode({
        'id': 'edit-c',
        'title': 'Düzenleme',
        'units': [
          {
            'id': 'u1',
            'title': 'U1',
            'lessons': [
              {
                'id': 'l1',
                'title': 'L1',
                'exercises': [
                  {
                    'type': 'type',
                    'question': 'Soru?',
                    'answer': 'EskiCevap',
                    'explanation': 'EskiAciklama'
                  }
                ]
              }
            ]
          }
        ]
      })).course!;

      final app = AppState(MemoryStorage());
      await app.load();
      app.companion = MascotId.tarcin;
      app.putCourse(course);
      final node = app.nodes(course).first;

      await tester.pumpWidget(_testApp(state: app, child: LessonScreen(course: course, node: node)));
      await tester.pumpAndSettle();

      // Yanlış cevap yazıp gönder
      await tester.enterText(find.byType(TextField), 'Yanlis');
      await tester.pumpAndSettle();
      await tester.tap(find.text(upper(t('lesson.check'))));
      await tester.pumpAndSettle();

      // Panelde eski doğru cevap ve eski açıklama görünür
      expect(find.text('EskiCevap'), findsOneWidget);
      expect(find.text('EskiAciklama'), findsOneWidget);

      // Soruyu düzenle simgesine tıkla
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Düzenleme penceresinde cevabı ve açıklamayı değiştir
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(2), 'YeniCevap');
      await tester.enterText(textFields.at(3), 'YeniAciklama');
      await tester.pumpAndSettle();

      // Kaydet butonuna bas
      await tester.tap(find.text(upper(t('edit.save'))));
      await tester.pumpAndSettle();

      // Panel güncellenmiş yeni cevabı ve açıklamayı gösterir, eskiler kalkar
      expect(find.text('YeniCevap'), findsOneWidget);
      expect(find.text('YeniAciklama'), findsOneWidget);
      expect(find.text('EskiCevap'), findsNothing);
      expect(find.text('EskiAciklama'), findsNothing);
    });
  });
}
