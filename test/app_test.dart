// Uygulamayı baştan sona süren arayüz testi. BILGE_SHOTS ortam değişkeni bir klasörü gösterirse
// ekran görüntülerini oraya yazar (göz denetimi için); yoksa yalnızca davranışı sınar.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/core/text_utils.dart' show formatNumber;
import 'package:bilge/l10n/l10n.dart';
import 'package:bilge/lesson/exercises.dart';
import 'package:bilge/lesson/lesson_screen.dart';
import 'package:bilge/main.dart';
import 'package:bilge/mascot/actions.dart';
import 'package:bilge/mascot/cast.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/mascot/mascot_view.dart';
import 'package:bilge/mascot/rig_view.dart';
import 'package:bilge/screens/manage.dart';
import 'package:bilge/ui/chart.dart';
import 'package:bilge/ui/confetti.dart';
import 'package:bilge/ui/incoming.dart';
import 'package:bilge/ui/io.dart';
import 'package:bilge/ui/sfx.dart';
import 'package:bilge/ui/theme.dart';
import 'package:bilge/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _shots = Platform.environment['BILGE_SHOTS'];
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  final nunito = FontLoader('Nunito');
  for (final w in [600, 700, 800, 900]) {
    nunito.addFont(File('assets/fonts/Nunito-$w.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await nunito.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)))).load();
  }
  // Formül yazı tipleri (flutter_math_fork paketinin içinden)
  final packages = (jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map)['packages'] as List;
  final math = Uri.parse(packages.firstWhere((p) => p['name'] == 'flutter_math_fork')['rootUri'] as String).toFilePath();
  final families = <String, FontLoader>{};
  for (final f in Directory('$math/lib/katex_fonts/fonts').listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
    final family = 'packages/flutter_math_fork/${f.uri.pathSegments.last.split('-').first}';
    families.putIfAbsent(family, () => FontLoader(family)).addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  for (final loader in families.values) {
    await loader.load();
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  if (_shots == null) return;
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.25);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Finder label(String key, [Map<String, Object?> args = const {}]) => find.text(upper(t(key, args)));
// Şık, parça ve öğeleri kaynak metinleriyle bul: formüller çizim olarak görünür, "4" gibi kısa metinler de
// şık numaralarıyla karışabilir.
Finder rich(String text) {
  final md = find.byWidgetPredicate((w) => w is MdInline && w.text == text);
  return md.evaluate().isNotEmpty ? md : find.text(text, findRichText: true);
}

Future<void> tap(WidgetTester tester, Finder finder, {int wait = 300}) async {
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump(Duration(milliseconds: wait));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Ekrandaki adımı kurs verisine bakarak çözer; [wrong] ise bilerek yanlış yapar. Adımın tipini döndürür.
Future<String> solve(WidgetTester tester, {bool wrong = false}) async {
  final view = tester.widget<ExerciseView>(find.byType(ExerciseView));
  final ex = view.exercise;
  final check = label('lesson.check');
  switch (ex.type) {
    case 'info':
      await tap(tester, label('common.continue'));
      return ex.type;
    case 'choice':
      await tap(tester, rich(wrong ? ex.list('distractors').first : ex.text('answer')));
    case 'multi':
      for (final a in wrong ? [ex.list('answers').first, ex.list('distractors').first] : ex.list('answers')) {
        await tap(tester, rich(a));
      }
    case 'truefalse':
      await tap(tester, find.text(t((ex.data['answer'] as bool) != wrong ? 'lesson.true' : 'lesson.false')));
    case 'fill':
      final blanks = [for (final p in fillParts(ex.text('text'))) if (p.blank) p.text];
      if (find.byType(TextField).evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField), wrong ? 'zzz' : blanks.first);
        await tester.pump();
      } else {
        for (final b in wrong ? ex.list('distractors').take(blanks.length).toList() + blanks : blanks) {
          if (find.byType(ExerciseView).evaluate().isEmpty) break;
          await tap(tester, rich(b).last, wait: 60);
        }
      }
    case 'type':
      await tester.enterText(find.byType(TextField), wrong ? 'yanlış cevap' : lower(ex.text('answer')));
      await tester.pump();
    case 'number':
      await tester.enterText(find.byType(TextField), formatNumber((ex.data['answer'] as num) + (wrong ? 7 : 0), locale: view.locale));
      await tester.pump();
    case 'match':
      final pairs = ex.pairs;
      if (wrong) {
        for (var k = 0; k < 2; k++) {
          await tap(tester, rich(pairs[0][0]), wait: 60);
          await tap(tester, rich(pairs[1][1]), wait: 60);
        }
      }
      for (final p in pairs) {
        await tap(tester, rich(p[0]), wait: 60);
        await tap(tester, rich(p[1]), wait: 60);
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
    case 'order' || 'build':
      final seq = ex.type == 'order' ? ex.list('items') : ex.list('answer');
      for (final token in wrong ? seq.reversed : seq) {
        // Aynı parça birden çok kez geçebilir: yerleştirilmemiş olanı (ağaçta en sonda duran boş kartı) seç
        final free = find.ancestor(of: rich(token), matching: find.byWidgetPredicate((w) => w is TapCard && w.state == CardState.idle));
        await tap(tester, free.last, wait: 60);
      }
    case 'categorize':
      final cats = ex.categories;
      final total = cats.fold(0, (n, c) => n + c.items.length);
      for (var k = 0; k < total; k++) {
        final card = find.descendant(of: find.byType(FractionallySizedBox), matching: find.byType(MdInline));
        final item = tester.widget<MdInline>(card.first).text;
        var ci = cats.indexWhere((c) => c.items.contains(item));
        if (wrong && k < 2) ci = (ci + 1) % cats.length;
        await tap(tester, rich(cats[ci].name), wait: 60);
      }
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 300));
    case 'flashcard':
      await tap(tester, rich(ex.text('front')), wait: 500);
      await tap(tester, label(wrong ? 'lesson.again' : 'lesson.knew'));
      return ex.type;
  }
  if (modeOf(ex) == ExMode.check) await tap(tester, check);
  return ex.type;
}

String lower(String s) => s.toLowerCase();

/// Dersi bitene kadar oynatır; [wrongAt] sırasındaki sorularda bilerek yanlış yapar.
Future<List<String>> play(WidgetTester tester, {Set<int> wrongAt = const {}, Set<String> shots = const {}, String prefix = ''}) async {
  final log = <String>[];
  var n = 0;
  final seen = <String>{};
  for (var guard = 0; guard < 80; guard++) {
    if (find.byType(ExerciseView).evaluate().isEmpty) break;
    final type = tester.widget<ExerciseView>(find.byType(ExerciseView)).exercise.type;
    if (shots.contains(type) && seen.add(type)) await shot(tester, '$prefix$type');
    final wrong = wrongAt.contains(n);
    await solve(tester, wrong: wrong);
    log.add(type + (wrong ? '✗' : ''));
    n++;
    final next = label('common.continue');
    if (type != 'info' && type != 'flashcard' && next.evaluate().isNotEmpty && find.byType(ExerciseView).evaluate().isNotEmpty) {
      if (wrong && seen.add('bad')) await shot(tester, '${prefix}feedback-bad');
      if (!wrong && n > 3 && seen.add('good')) await shot(tester, '${prefix}feedback-good');
      await tap(tester, next);
    }
  }
  return log;
}

void main() {
  setUpAll(() async {
    MascotView.animate = false;
    Confetti.enabled = false;
    Sfx.available = false;
    await _loadFonts();
  });

  testWidgets('karşılamadan kurs bitimine tüm akış', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });

    final state = AppState(MemoryStorage());
    await state.load();
    state.settings.lang = 'tr';
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump();

    // 1) Karşılama: ekip ve yol arkadaşı seçimi
    expect(find.text(t('welcome.title')), findsOneWidget);
    await tap(tester, find.text('Tarçın'));
    await shot(tester, '01-karsilama');
    await tap(tester, label('welcome.start', {'name': 'Tarçın'}));
    expect(state.companion, MascotId.tarcin);

    // 2) Boş ekran → örnek kurs
    await shot(tester, '02-bos');
    await tester.runAsync(() async {
      await tester.tap(label('learn.sample'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.currentCourse?.id, 'gunes-sistemi');
    await shot(tester, '03-yol');

    // 3) İlk ders: bir soruyu bilerek yanlış yap
    Future<void> openCurrent() async {
      await tap(tester, label('learn.start'));
      await shot(tester, '04-ders-penceresi');
      await tap(tester, find.textContaining('XP').last, wait: 500);
    }

    await openCurrent();
    final log1 = await play(tester, wrongAt: {1}, shots: {'info', 'choice', 'truefalse', 'fill', 'multi', 'type', 'flashcard'});
    expect(log1.first, 'info');
    expect(log1.last, 'choice', reason: 'yanlış yapılan soru ders sonunda yeniden gelir');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.done')), findsOneWidget);
    await shot(tester, '05-bitis');
    expect(state.profile.xp, 13);
    expect(state.progressOf('gunes-sistemi').lessons['u1/l1']!.stars, 2);
    expect(state.mistakeCount(state.currentCourse!), 1);
    await tap(tester, label('common.continue'), wait: 500);

    // 4) Kalan dersler: 12 tipin hepsi oynanır
    final types = {...log1.map((x) => x.replaceAll('✗', ''))};
    for (var i = 0; i < 5; i++) {
      await tap(tester, label('learn.start'));
      await tap(tester, find.textContaining('XP').last, wait: 500);
      final log = await play(tester, shots: {'match', 'order', 'build', 'categorize'});
      types.addAll(log);
      await tester.pump(const Duration(seconds: 2));
      await tap(tester, label('common.continue'), wait: 500);
    }
    expect(types, exerciseTypes.toSet());
    expect(state.statusOf(state.currentCourse!).values.where((s) => s == NodeStatus.done).length, 6);
    await shot(tester, '06-yol-ilerlemis');

    // 5) Tekrar: ilk dersteki yanlış ya ünite tekrarında doğru yapılıp yarına kalmıştır ya da bugün sorulur;
    //    iki durumda da oturumdan sonra yanlış havuzunda kalmaz
    final due = state.dueCount(state.currentCourse!);
    expect(due, lessThanOrEqualTo(1));
    await tap(tester, label(due > 0 ? 'learn.daily' : 'learn.practice'), wait: 500);
    await play(tester);
    await tester.pump(const Duration(seconds: 2));
    expect([t('finish.practice'), t('finish.daily'), t('finish.perfect')].any((x) => find.text(x).evaluate().isNotEmpty), isTrue);
    await tap(tester, label('common.continue'), wait: 500);
    expect(state.mistakeCount(state.currentCourse!), 0);

    // 6) Canlar biter
    state.settings.freeMode = true;
    state.commit();
    await tester.pump();
    // Yol tembel kurulur: yukarıdaki düğüm görünene kadar kaydır
    // Henüz hiç oynanmamış bir ders: yıldızsız bitişin kaydı net görülsün
    final fresh = state.nodes(state.currentCourse!).firstWhere((n) => n.kind == NodeKind.lesson && !state.progressOf('gunes-sistemi').lessons.containsKey(n.id));
    await tester.scrollUntilVisible(find.byKey(ValueKey('node-${fresh.id}')), -250, scrollable: find.byType(Scrollable).first);
    await tap(tester, find.byKey(ValueKey('node-${fresh.id}')));
    await tap(tester, find.textContaining('XP').last, wait: 500);
    await play(tester, wrongAt: {for (var i = 0; i < 40; i++) i});
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(t('fail.title')), findsOneWidget);
    await shot(tester, '07-can-bitti');
    // Yıldızsız devam: ders kaldığı yerden, can sayılmadan sürer; tamamlanır ama yıldız kazandırmaz
    final xpBefore = state.profile.xp;
    await tap(tester, label('fail.continue'), wait: 500);
    expect(find.byType(ExerciseView), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^${t('lesson.hearts', {'n': ''})}')), findsNothing, reason: 'can göstergesi kalkar');
    await play(tester, wrongAt: {0});
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.done')), findsOneWidget);
    expect(find.text(t('finish.noStars')), findsOneWidget);
    await shot(tester, '07b-yildizsiz-bitis');
    final played = state.progressOf('gunes-sistemi').lessons[fresh.id]!;
    expect([played.stars, played.plays], [0, 1], reason: 'ders tamamlandı sayılır, yıldızı yoktur');
    expect(state.profile.xp - xpBefore, 5);
    await tap(tester, label('common.continue'), wait: 500);

    // 7) Kurslar ve kurs oluşturma: kalıbı kopyala, çıktıyı ekle
    await tap(tester, find.text(t('nav.courses')));
    await shot(tester, '08-kurslar');
    await tap(tester, label('courses.add'), wait: 500);
    await tap(tester, label('create.copy'));
    expect(clipboard, isNull, reason: 'konu yazmadan kopyalanmaz');
    await tester.pump(const Duration(seconds: 3)); // uyarı bildirimi düğmenin üstünden kalksın
    await tester.enterText(find.byType(TextField).first, 'Temel istatistik');
    // İmleci görünür tutan kaydırma bitsin: kaydırma sürerken liste dokunuşları yok sayar
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, label('create.copy'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, contains('Konu: Temel istatistik'));
    expect(clipboard, contains('her mesajda 3 ünite'));
    await shot(tester, '09-kalip');
    await tap(tester, label('create.goImport'));
    await tester.enterText(find.byType(TextField).first, 'bu json değil {"title": ');
    await tap(tester, label('import.check'));
    expect(find.text(t('import.failed')), findsOneWidget);
    await shot(tester, '10-ice-aktar-hata');
    const unit = '{"id":"u1","title":"Bir","lessons":[{"id":"l1","title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}';
    await tester.enterText(find.byType(TextField).first, 'İşte kursun:\n```json\n{"id":"deneme","title":"Deneme","outline":["Bir","İki"],"units":[$unit]}\n```');
    await tap(tester, label('import.check'), wait: 600);
    expect(state.currentCourse?.id, 'deneme');
    expect(state.profile.badges.containsKey('creator'), isTrue);
    // Planda iki ünite var, biri geldi: ekranda kalır ve ne yapılacağını söyler
    expect(find.text(t('import.progress', {'done': 1, 'total': 2})), findsOneWidget);
    expect(find.text(t('import.nextUnit', {'title': 'İki'})), findsOneWidget);
    await shot(tester, '10b-siradaki-unite');
    await tap(tester, label('import.later'), wait: 500);
    await tester.pump(const Duration(seconds: 3));

    // 8) Profil; sonra İngilizce + koyu tema
    await tap(tester, find.text(t('nav.profile')));
    await shot(tester, '11-profil');
    state.settings
      ..lang = 'en'
      ..theme = 'dark';
    state.commit();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400)); // tema geçişi + kart renkleri
    expect(find.text('Profile'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('The crew'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('The crew'), findsOneWidget);
    await shot(tester, '12-profile-en-dark');
    await tap(tester, find.text('Learn'));
    expect(find.textContaining('HOSTED BY'), findsWidgets);
    await shot(tester, '13-learn-en-dark');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('formül, sayısal cevap, ipucu, çözüm ve ortak metin', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..settings.freeMode = true
      ..companion = MascotId.sekiz
      ..putCourse(course);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> open(String id) async {
      await tester.scrollUntilVisible(find.byKey(ValueKey('node-$id')), 300, scrollable: find.byType(Scrollable).first);
      await tap(tester, find.byKey(ValueKey('node-$id')));
      await tap(tester, find.textContaining('XP').last, wait: 500);
    }

    Exercise current() => tester.widget<ExerciseView>(find.byType(ExerciseView)).exercise;
    Future<void> next() => tap(tester, label('common.continue'));

    // Ders 1: formüller çizilir, sayısal cevap tolerans ve birimle denetlenir
    await open('u8/l1');
    expect(find.byType(Formula), findsNWidgets(3), reason: 'gövdede iki, örnekte bir formül');
    await shot(tester, '20-formul-bilgi');
    await solve(tester); // info
    expect(current().type, 'choice');
    await shot(tester, '21-formul-siklar');
    await solve(tester);
    await next();

    expect(current().type, 'number');
    expect(find.text('km'), findsOneWidget, reason: 'birim kutunun yanında durur');
    expect(find.text(t('lesson.hint')), findsOneWidget);
    await tap(tester, find.text(t('lesson.hint')));
    expect(find.text(t('lesson.hint')), findsNothing, reason: 'ipucu açılınca düğme kalkar');
    expect(find.byWidgetPredicate((w) => w is MdBlock && w.text == current().hint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty, reason: 'yalnızca sayı yazılabilir');
    await tester.enterText(find.byType(TextField), '600.000');
    await tester.pump();
    await shot(tester, '22-sayisal-ipucu');
    await tap(tester, label('lesson.check'));
    expect(find.text(upper(t('lesson.correctAnswer'))), findsNothing, reason: '600.000 altı yüz bin olarak okunur');
    expect(find.text(upper(t('lesson.showSolution'))), findsOneWidget);
    await tap(tester, find.text(upper(t('lesson.showSolution'))), wait: 500);
    expect(find.text(t('lesson.solution')), findsOneWidget);
    await shot(tester, '23-cozum');
    await tap(tester, label('common.close'), wait: 500);
    await next();

    await solve(tester); // truefalse
    await next();
    expect(current().data['tolerance'], 5);
    await tester.enterText(find.byType(TextField), '503');
    await tester.pump();
    await tap(tester, label('lesson.check'));
    expect(find.text(t('lesson.exactValue', {'answer': '500 s'})), findsOneWidget, reason: 'tolerans içindeki cevap kabul edilir, tam değer gösterilir');
    await next();
    final rest = await play(tester);
    expect(rest, ['fill', 'build']);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.perfect')), findsOneWidget);
    await tap(tester, label('common.continue'), wait: 500);

    // Ders 2: ortak metin her sorunun üstünde açık gelir; kullanıcı kapatırsa sonraki sorularda kapalı kalır
    await open('u8/l2');
    expect(find.text(upper(t('lesson.context'))), findsNothing, reason: 'öğretici kartta metin gösterilmez');
    await solve(tester); // info
    expect(find.text(upper(t('lesson.context'))), findsOneWidget);
    expect(find.text(t('lesson.contextHide')), findsOneWidget);
    await shot(tester, '24-ortak-metin');
    await solve(tester);
    await next();
    expect(find.text(t('lesson.contextHide')), findsOneWidget, reason: 'metin sonraki soruda da açık');
    await tap(tester, find.text(t('lesson.contextHide')));
    expect(find.text(t('lesson.contextShow')), findsOneWidget);
    await solve(tester);
    await next();
    expect(find.text(t('lesson.contextShow')), findsOneWidget, reason: 'kapatılan metin sonraki soruda kapalı kalır');
    // Yanlış sayısal cevap: doğru değer ve birim gösterilir
    await solve(tester, wrong: true);
    expect(find.text(upper(t('lesson.correctAnswer'))), findsOneWidget);
    expect(rich('3000 m'), findsOneWidget);
    await shot(tester, '25-sayisal-yanlis');
    await next();
    await play(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.done')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('sınavla geçme, günlük tekrar, grafik ve dinleme', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Cihazın ses motoru: yalnızca İngilizce sesi var
    final spoken = <Map>[];
    const tts = MethodChannel('bilge/tts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method != 'speak') return null;
      spoken.add(call.arguments as Map);
      return (call.arguments as Map)['lang'] == 'en';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(tts, null));

    var now = DateTime(2026, 10, 4, 12);
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage(), clock: () => now);
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.dalga
      ..putCourse(course);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(upper(t('learn.practice'))), findsNothing, reason: 'henüz tekrar edilecek bir şey yok');

    Future<void> startExam(String unit) async {
      await tester.scrollUntilVisible(find.byKey(ValueKey('exam-$unit')), 250, scrollable: find.byType(Scrollable).first);
      await tap(tester, find.byKey(ValueKey('exam-$unit')), wait: 500);
    }

    // 1) İkinci ünitenin sınavı, bitmemiş birinci üniteyi de kapsar
    await startExam('u2');
    expect(find.text(t('learn.examTextMany', {'n': 20, 'm': 4, 'k': 2})), findsOneWidget);
    await shot(tester, '40-sinav-penceresi');
    await tap(tester, label('learn.examStart'), wait: 600);
    expect(find.text(t('lesson.hint')), findsNothing, reason: 'sınavda ipucu yok');
    final exam = await play(tester);
    expect(exam.length, 20);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.exam')), findsOneWidget);
    expect(find.text(t('finish.examUnits', {'n': 2})), findsOneWidget);
    await shot(tester, '41-sinav-gecildi');
    await tap(tester, label('common.continue'), wait: 600);
    final status = state.statusOf(course);
    expect(state.nodes(course).where((n) => n.unitIndex < 2).every((n) => status[n.id] == NodeStatus.done), isTrue);
    expect(status['u3/l1'], NodeStatus.current);
    expect(state.profile.xp, greaterThanOrEqualTo(20));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, '42-sinavdan-sonra-yol');

    // 2) Üçüncü ünitenin sınavında izin verilenden bir fazla yanlış: sınav biter, ünite açılmaz
    final questions = state.examItems(course, 2).length, allowed = AppState.examAllowance(questions);
    await startExam('u3');
    expect(find.text(t('learn.examText', {'n': questions, 'm': allowed})), findsOneWidget);
    await tap(tester, label('learn.examStart'), wait: 600);
    final failed = await play(tester, wrongAt: {for (var i = 0; i <= allowed; i++) i});
    expect(failed.length, allowed + 1, reason: 'yanlışlar yeniden sorulmaz; sınır aşılınca sınav biter');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(t('fail.examTitle')), findsOneWidget);
    await tap(tester, label('fail.examLeave'), wait: 600);
    expect(state.statusOf(course)['u3/l1'], NodeStatus.current);

    // 3) Sınavdaki yanlışlar bugün, doğrular yarın tekrar edilir
    expect(state.dueCount(course), allowed + 1);
    expect(find.text(upper(t('learn.daily'))), findsOneWidget);
    now = now.add(const Duration(days: 1));
    expect(state.dueCount(course), 20 + allowed + 1);
    await tap(tester, find.text(upper(t('learn.daily'))), wait: 600);
    final review = await play(tester);
    expect(review.length, AppState.dailySize, reason: 'bir oturumda en çok 15 öğe');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.dailyMore', {'n': 20 + allowed + 1 - AppState.dailySize})), findsOneWidget);
    await tap(tester, label('common.continue'), wait: 600);
    expect(state.dueCount(course), 20 + allowed + 1 - AppState.dailySize);

    // 4) Grafikli ders: grafik sorunun üstünde durur
    state.settings.freeMode = true;
    state.commit();
    await tester.pump();
    Future<void> open(String id) async {
      await tester.scrollUntilVisible(find.byKey(ValueKey('node-$id')), 300, scrollable: find.byType(Scrollable).first);
      await tap(tester, find.byKey(ValueKey('node-$id')));
      await tap(tester, find.textContaining('XP').last, wait: 500);
    }

    await open('u8/l3');
    expect(find.byType(ChartView), findsOneWidget);
    await shot(tester, '43-grafik-bilgi');
    await solve(tester);
    expect(find.byType(ChartView), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(ChartView)) + const Offset(60, 30));
    await tester.pump();
    await shot(tester, '44-grafik-soru');
    await play(tester);
    await tester.pump(const Duration(seconds: 2));
    await tap(tester, label('common.continue'), wait: 600);

    // 5) Dinleme dersi: metin kursun okuma diliyle okunur; dinleyemeyen soruyu geçer
    spoken.clear();
    await open('u8/l4');
    await tester.pump(const Duration(milliseconds: 100));
    expect(spoken.single, {'text': 'Sun, Moon, Earth, Star', 'lang': 'en', 'rate': 1.0});
    await tap(tester, find.bySemanticsLabel(t('lesson.listenSlow')));
    expect(spoken.last['rate'], 0.6);
    await solve(tester); // info
    await solve(tester); // match
    await tap(tester, label('common.continue'));
    expect(spoken.last['text'], 'Moon');
    expect(find.text('Moon'), findsNothing, reason: 'okunan metin ekranda yazmaz');
    await shot(tester, '45-dinle-sec');
    await tap(tester, find.text(t('lesson.cantListen')));
    final rest = await play(tester);
    expect(rest.first, 'type');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.perfect')), findsOneWidget, reason: 'geçilen soru puanı düşürmez');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('yarıda kesilmiş çıktı: tamamlanan üniteler eklenir, eksik kalan söylenir', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.puhu;
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, label('learn.create'), wait: 500);
    await tap(tester, find.text(t('create.tab2')));

    String unit(int n) => '{"id":"u$n","title":"Ünite $n","lessons":[{"id":"l1","title":"Ders","exercises":['
        '{"type":"info","body":"Gövde"},{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}';
    final full = '{"format":"bilge-course","id":"uzun","title":"Uzun Kurs","outline":["Ünite 1","Ünite 2","Ünite 3"],"units":[${unit(1)},${unit(2)},${unit(3)}]}';
    // Yapay zekâ üçüncü ünitenin ortasında kesilmiş
    await tester.enterText(find.byType(TextField).first, '```json\n${full.substring(0, full.indexOf('"id":"u3"') + 70)}');
    await tap(tester, label('import.check'), wait: 600);
    expect(find.text(t('import.failed')), findsNothing);
    expect(find.text(t('err.cutUnit', {'title': 'Ünite 3'})), findsOneWidget);
    await shot(tester, '30-yarida-kesilmis');
    await tap(tester, label('import.addCourse'), wait: 600);
    expect(state.currentCourse!.units.map((u) => u.title), ['Ünite 1', 'Ünite 2']);
    expect(state.currentCourse!.outline.length, 3, reason: 'plan korunur: kalan ünite sonradan istenebilir');

    // Kurs tamamlanmadı: ekran açık kalır, kutu boşalır, sıradaki ünite söylenir
    expect(find.text(t('import.progress', {'done': 2, 'total': 3})), findsOneWidget);
    expect(find.text(t('import.nextUnit', {'title': 'Ünite 3'})), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    // Kalan ünite gelir: sormadan eklenir, kurs tamamlanınca öğrenme ekranına dönülür
    await tester.enterText(find.byType(TextField).first, '{"format":"bilge-course","id":"uzun","title":"Uzun Kurs","outline":["Ünite 1","Ünite 2","Ünite 3"],"units":[${unit(3)}]}');
    await tap(tester, label('import.check'), wait: 600);
    expect(state.courses['uzun']!.units.length, 3);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t('create.tab2')), findsNothing, reason: 'kurs tamamlandı, ekran kapandı');
    expect(find.text(t('learn.planned')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('paylaşılan kurs dosyası: açılışta ve uygulama açıkken sorulur', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const incoming = MethodChannel('bilge/incoming');
    String course(String id, String title) =>
        '{"id":"$id","title":"$title","author":"Ayşe","units":[{"id":"u1","title":"Bir","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}';
    // Uygulama bir dosyaya dokunularak açılmış gibi
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incoming, (call) async => call.method == 'take' ? course('paylasilan', 'Paylaşılan Kurs') : null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incoming, null));

    final state = AppState(MemoryStorage());
    await state.load();
    state.settings.lang = 'tr';
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(t('welcome.title')), findsOneWidget, reason: 'önce yol arkadaşı seçilir');
    await tap(tester, find.text('English'));
    expect(find.text('Pick your companion'.toUpperCase()), findsOneWidget, reason: 'karşılama ekranında dil değişir');
    await tap(tester, find.text('Türkçe'));
    await tap(tester, label('welcome.start', {'name': 'Puhu'}), wait: 500);
    expect(find.text(t('incoming.title', {'title': 'Paylaşılan Kurs'})), findsOneWidget);
    expect(find.textContaining(t('incoming.by', {'author': 'Ayşe'})), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500)); // pencere açılma animasyonu
    await tap(tester, label('import.addCourse'), wait: 500);
    expect(state.currentCourse?.id, 'paylasilan');
    expect(state.profile.created, isFalse, reason: 'başkasının kursu "Kurs mimarı" rozeti vermez');

    // Uygulama açıkken ikinci bir dosya gelir
    Future<void> send(String text) => tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('bilge/incoming', const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', text)), (_) {});
    await send(course('ikinci', 'İkinci Kurs'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t('incoming.title', {'title': 'İkinci Kurs'})), findsOneWidget);
    await tap(tester, label('common.cancel'), wait: 500);
    expect(state.courses.containsKey('ikinci'), isFalse, reason: 'vazgeçilince eklenmez');

    await send('bu bir kurs değil');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text(t('incoming.failed')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    Future<void> arrive(String text) async {
      await send(text);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    // Aynı kimlikte ama başka başlıkta bir kurs: sormadan karışmaz, ilk seçenek ayrı kurs olarak eklemektir
    await arrive(course('paylasilan', 'Bambaşka Kurs'));
    expect(find.text(t('import.clashTitle')), findsOneWidget);
    expect(find.textContaining('“Bambaşka Kurs”'), findsOneWidget);
    expect(find.textContaining('“Paylaşılan Kurs”'), findsOneWidget);
    expect(label('import.replace'), findsNothing, reason: 'başka bir kurs eskisinin yerine geçmeyi önermez');
    await shot(tester, '83-kimlik-cakismasi');
    await tap(tester, label('import.separate'), wait: 500);
    expect(state.courses['paylasilan']!.title, 'Paylaşılan Kurs');
    expect(state.courses['paylasilan']!.units.length, 1);
    expect(state.courses['paylasilan-2']!.title, 'Bambaşka Kurs');
    await tester.pump(const Duration(seconds: 4));

    // Aynı kimlik ve aynı başlık: aynı kursun devamı sayılır, yine de sorulur
    await arrive(course('paylasilan', 'Paylaşılan Kurs'));
    expect(find.text(t('import.clashTitle')), findsOneWidget);
    expect(label('import.merge'), findsOneWidget);
    expect(label('import.replace'), findsOneWidget);
    await shot(tester, '84-ayni-kurs');
    await tap(tester, label('common.cancel'), wait: 500);
    expect(state.courses.length, 2);

    // Yapay zekâ uygulamasından paylaşılan "devam" çıktısı (çevresinde konuşma metniyle): aynı kurs, yeni ünite.
    // Kısa bir soru sorulur; eklenince kalan ünite için ne yapılacağı söylenir
    const chunk = '{"id":"paylasilan","title":"Paylaşılan Kurs","outline":["Bir","İki","Üç"],'
        '"units":[{"id":"u2","title":"İki","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Ateş sıcaktır.","answer":true}]}]}]}';
    await arrive('İşte kursun devamı:\n```json\n$chunk\n```\nBaşka bir şey ister misin?');
    expect(find.text(t('import.moreTitle', {'title': 'Paylaşılan Kurs', 'n': 1})), findsOneWidget);
    expect(label('import.replace'), findsNothing);
    await shot(tester, '85-devam-ciktisi');
    await tap(tester, label('import.merge'), wait: 500);
    expect(state.courses['paylasilan']!.units.map((u) => u.id), ['u1', 'u2']);
    expect(find.textContaining(t('incoming.moreLeft', {'n': 1})), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    // Yarıda kesilmiş bir çıktı paylaşıldıysa "kurs bulunamadı" yerine nedeni söylenir
    await arrive('```json\n{"format":"bilge-course","title":"Kesik","units":[{"title":"U","lessons":[{"title":"L","exercises":[{"type":"info","bo');
    expect(find.text(t('err.truncated')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    // Kendini var olan bir büyük kursun kısmı olarak tanıtan dosya: eklenmeden önce söylenir
    state.setGroup(['paylasilan'], 'Büyük Kurs');
    await tester.pump(const Duration(milliseconds: 300));
    await arrive(course('ucuncu', 'Üçüncü Kurs').replaceFirst('{', '{"group":"Büyük Kurs",'));
    expect(find.textContaining(t('import.joins', {'group': 'Büyük Kurs'})), findsOneWidget);
    await tap(tester, label('common.cancel'), wait: 500);
    // Kimliği de çakışıyorsa aynı şey çakışma penceresinde söylenir (ayrı eklenirse o büyük kursa girer)
    await arrive(course('paylasilan', 'Dördüncü Kurs').replaceFirst('{', '{"group":"Büyük Kurs",'));
    expect(find.text(t('import.clashTitle')), findsOneWidget);
    expect(find.textContaining(t('import.joinsSeparate', {'group': 'Büyük Kurs'})), findsOneWidget);
    await tap(tester, label('common.cancel'), wait: 500);

    // Sınırı aşan dosyayı Android tarafı okumaz; kullanıcıya nedeni söylenir
    await arrive(Incoming.tooBig);
    expect(find.text(t('err.tooBig', {'mb': 8})), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('yedekler: otomatik yedek listelenir, elle yedek alınır ve geri yüklenir', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime(2026, 10, 4, 9, 30);
    final storage = MemoryStorage();
    final state = AppState(storage, clock: () => now);
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tosbi
      ..putCourse(parseCourse('{"id":"k","title":"Kurs","units":[{"id":"u1","title":"Bir","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}').course!);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, find.text(t('nav.profile')));
    await tester.scrollUntilVisible(label('profile.backup'), 300, scrollable: find.byType(Scrollable).first);
    // Profil listesi tembel kurulur: yedekler bölümü görünene kadar kaydır
    await tester.scrollUntilVisible(find.text(t('backup.auto')), 120, scrollable: find.byType(Scrollable).first);
    expect(find.text(t('backup.auto')), findsOneWidget, reason: 'ilk kurs eklenince ilk otomatik yedek alınmıştır');
    expect(find.text('04.10.2026 09:30'), findsOneWidget);

    // Elle yedek
    state.profile.xp = 40;
    now = now.add(const Duration(hours: 1));
    await tap(tester, label('profile.backup'), wait: 400);
    expect(find.text(t('backup.manual')), findsOneWidget);
    expect(find.text('04.10.2026 10:30'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.scrollUntilVisible(find.text(t('backup.manual')), 100, scrollable: find.byType(Scrollable).first);
    await shot(tester, '60-yedekler');

    // Sonradan ilerleme değişir; elle alınan yedek geri yüklenir
    state.profile.xp = 90;
    state.commit();
    now = now.add(const Duration(hours: 1));
    final row = find.byKey(ValueKey('backup-${state.backups.firstWhere((b) => b.manual).name}'));
    await tap(tester, find.descendant(of: row, matching: find.text(t('backup.restore'))), wait: 500);
    expect(find.text(t('backup.restoreText', {'date': '04.10.2026 10:30'})), findsOneWidget);
    await tap(tester, label('backup.restore'), wait: 500);
    expect(state.profile.xp, 40);
    expect(state.backups.where((b) => !b.manual).length, 2, reason: 'geri yüklemeden önceki durum da yedeklendi');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('kurs paketi: tek dosyayla çok kurs eklenir, listede gruplanır, aranır, kaldırılır', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String one(int i) => '{"id":"ders-$i","title":"${['Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'Tarih', 'Coğrafya', 'Edebiyat', 'Felsefe'][i]}","emoji":"📗",'
        '"units":[{"id":"u1","title":"Bir","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}';
    final pack = '{"format":"bilge-pack","title":"Ada Koleji","author":"Ada Koleji","description":"9. sınıf kursları","courses":[${[for (var i = 0; i < 8; i++) one(i)].join(',')}]}';
    const incoming = MethodChannel('bilge/incoming');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incoming, (call) async => call.method == 'take' ? pack : null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(incoming, null));

    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.pasa
      ..putCourse(parseCourse('{"id":"benim","title":"Kendi Kursum","units":[{"id":"u1","title":"Bir","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}').course!);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Dosyaya dokunulunca tek pencere: sekiz kursun hepsi birden
    await tester.pump(const Duration(milliseconds: 500)); // pencere açılma animasyonu
    expect(find.text(t('pack.offerTitle', {'title': 'Ada Koleji'})), findsOneWidget);
    expect(find.textContaining(t('pack.summary', {'n': 8, 'l': 8})), findsOneWidget);
    await shot(tester, '50-paket-penceresi');
    await tap(tester, label('pack.addAll'), wait: 600);
    expect(state.courses.length, 9);
    expect(state.current, 'benim', reason: 'seçili kurs değişmez');
    await tester.pump(const Duration(seconds: 3));

    // Kurs listesi: kurumun sekiz kursu tek kartta toplanır, kendi kursu ayrı durur
    await tap(tester, find.text(t('nav.courses')));
    const group = ValueKey('group-Ada Koleji');
    expect(find.byKey(group), findsOneWidget);
    expect(find.text(t('courses.metaGroup', {'n': 8, 'l': 8})), findsOneWidget);
    expect(find.byKey(const ValueKey('course-benim')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-ders-1')), findsNothing, reason: 'kısımlar grubun içindedir');
    await shot(tester, '51-kurslar-gruplu');
    // Arama: grubun içindeki kurs da bulunur; grup adıyla aranınca grup kartı gelir
    await tester.enterText(find.byType(TextField).first, 'fizik');
    await tester.pump();
    expect(find.byKey(const ValueKey('course-ders-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-benim')), findsNothing);
    expect(find.byKey(group), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'ada kol');
    await tester.pump();
    expect(find.byKey(group), findsOneWidget);
    expect(find.byKey(const ValueKey('course-ders-1')), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    // Aynı paket yeniden gelirse kurslar güncellenir, çoğalmaz
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('bilge/incoming', const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', pack)), (_) {});
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t('pack.existing', {'n': 8})), findsOneWidget);
    await tap(tester, label('pack.addAll'), wait: 600);
    expect(state.courses.length, 9);
    await tester.pump(const Duration(seconds: 3));

    // Paket penceresi: seçilen kurslar tek dosya olur
    await tap(tester, find.byTooltip(t('pack.share')).first, wait: 500);
    expect(find.text(t('pack.shareTitle')), findsOneWidget);
    expect(find.text(upper(t('pack.shareAction', {'n': 9}))), findsOneWidget);
    await shot(tester, '52-paket-olustur');
    await tap(tester, label('common.cancel'), wait: 500);
    final built = buildPack(state, ['ders-0', 'ders-1'], '  ');
    expect([built.title, built.courses.map((c) => c.id), built.courses.first.group], [t('pack.defaultName'), ['ders-0', 'ders-1'], '']);

    // Paketi kaldır: kurumun sekiz kursu birden gider, kendi kursu kalır
    await tap(tester, find.descendant(of: find.byKey(group), matching: find.byTooltip(t('courses.more'))), wait: 500);
    await tap(tester, find.text(t('pack.remove')), wait: 500);
    expect(find.text(t('pack.removeTitle', {'title': 'Ada Koleji', 'n': 8})), findsOneWidget);
    await tap(tester, label('common.delete'), wait: 500);
    expect(state.courses.keys, ['benim']);
  });

  testWidgets('kısımlı kurs: grup tek kartta, kısımlar sırayla; raflar, arşiv ve kurslar arası günün tekrarı', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String sec(String id, String title, String emoji, {int units = 1}) => '{"id":"$id","title":"$title","emoji":"$emoji","description":"$title üzerine kısa bir açıklama.","units":[${[
          for (var u = 1; u <= units; u++)
            '{"id":"u$u","title":"Ünite $u","lessons":[{"id":"l1","title":"Ders","exercises":[${[for (var i = 0; i < 4; i++) '{"type":"truefalse","statement":"Önerme $u.$i doğrudur.","answer":true}'].join(',')}]}]}',
        ].join(',')}]}';
    final pack = '{"format":"bilge-pack","title":"İnsan Vücudu","courses":['
        '${sec('k1', 'İnsan Vücudu 1: Hareket', '🦴')},${sec('k2', 'İnsan Vücudu 2: Enerji', '🫁', units: 2)},${sec('k3', 'İnsan Vücudu 3: Kontrol', '🧠')}]}';
    var now = DateTime(2026, 10, 4, 12);
    final state = AppState(MemoryStorage(), clock: () => now);
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tosbi
      ..putCourse(parseCourse(sec('benim', 'Kendi Kursum', '📒')).course!)
      ..putPack(parsePack(pack)!.pack!);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 500));
    Finder menuOf(Key card) => find.descendant(of: find.byKey(card), matching: find.byTooltip(t('courses.more')));

    // 1) Liste: paketin üç kursu tek kartta
    await tap(tester, find.text(t('nav.courses')));
    const group = ValueKey('group-İnsan Vücudu');
    expect(find.byKey(group), findsOneWidget);
    expect(find.text(t('courses.metaGroup', {'n': 3, 'l': 4})), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-fresh')), findsNothing, reason: 'tek raf varken başlık gerekmez');

    // 2) Kısımlar ekranı: sırayla, kısa adlarıyla; "devam et" sıradaki kısmı açar
    await tap(tester, find.byKey(group), wait: 500);
    expect(find.text(upper('${t('group.section', {'n': 1})} · ${t('group.upNext')}')), findsOneWidget);
    for (final title in ['Hareket', 'Enerji', 'Kontrol']) {
      expect(find.text(title), findsOneWidget);
    }
    await shot(tester, '70-kisimlar');
    await tap(tester, label('group.resume'), wait: 600);
    expect(state.current, 'k1');
    await tester.pump(const Duration(milliseconds: 600)); // yol sıradaki derse kayarken dokunuşlar yok sayılır

    // 3) İlk kısım bitince sıradaki kısım önerilir
    await tap(tester, label('learn.start'));
    await tap(tester, find.textContaining('XP').last, wait: 500);
    await play(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.sectionDone', {'title': 'Enerji'})), findsOneWidget);
    expect(label('learn.nextSectionGo'), findsOneWidget, reason: 'sıradaki kısma bitiş ekranından geçilebilir');
    expect(label('common.continue'), findsNothing);
    await shot(tester, '71-kisim-bitti');
    // "Şimdi değil" denirse bu kısımda kalınır; seçenek yolun sonunda durmaya devam eder
    await tap(tester, label('finish.notNow'), wait: 600);
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.current, 'k1');
    expect(find.text(t('learn.sectionDone')), findsOneWidget);
    await shot(tester, '72-siradaki-kisim');
    await tap(tester, label('learn.nextSectionGo'), wait: 600);
    expect(state.current, 'k2');

    // 4) Raflar; ikinci kısım (iki ünite) tek sınavla geçilir
    await tap(tester, find.text(t('nav.courses')));
    expect(find.byKey(const ValueKey('shelf-active')), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-fresh')), findsOneWidget);
    expect(find.text(t('courses.next', {'title': 'Enerji'})), findsOneWidget);
    await shot(tester, '73-raflar');
    await tap(tester, find.byKey(group), wait: 500);
    await tap(tester, find.byKey(const ValueKey('exam-course-k2')), wait: 500);
    expect(find.text(t('group.examTitle', {'title': 'Enerji'})), findsOneWidget);
    expect(find.text(t('group.examText', {'n': 8, 'm': 1, 'k': 2})), findsOneWidget);
    await tap(tester, label('learn.examStart'), wait: 600);
    expect((await play(tester)).length, 8);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.exam')), findsOneWidget);
    expect(find.text(t('finish.sectionDone', {'title': 'Kontrol'})), findsOneWidget);
    // Bitiş ekranından doğrudan sıradaki kısma: kısımlar ekranı kapanır, üçüncü kısmın yolu açılır
    await tap(tester, label('learn.nextSectionGo'), wait: 600);
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.current, 'k3');
    expect(find.byKey(const ValueKey('exam-course-k3')), findsNothing, reason: 'kısımlar ekranı kapandı');
    expect(label('learn.start'), findsOneWidget);
    await shot(tester, '74a-siradaki-kisim-acildi');
    await tap(tester, find.text(t('nav.courses')));
    await tap(tester, find.byKey(group), wait: 500);
    expect(find.text(t('courses.done')), findsNWidgets(2));
    await shot(tester, '74-kisimlar-ilerlemis');

    // 5) Son kısım da bitince grup "Bitirdiklerim" rafına iner; raf kapalı gelir
    state.completeLesson(LessonResult(
        courseId: 'k3', node: state.nodes(state.courses['k3']!).first, stars: 3, xp: 10, perfect: true, questions: 4, firstTry: 4, maxCombo: 4,
        wrongKeys: const {}, rightKeys: const {'u1/l1#0'}));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(t('learn.groupDone', {'group': 'İnsan Vücudu'})), findsOneWidget);
    await tap(tester, find.byTooltip(t('common.back')), wait: 500);
    expect(find.byKey(const ValueKey('shelf-finished')), findsOneWidget);
    expect(find.byKey(group), findsNothing);
    await tap(tester, find.byKey(const ValueKey('shelf-finished')));
    expect(find.byKey(group), findsOneWidget);

    // 6) Arşiv: kurs listeden kalkar, "Arşiv" rafından geri alınır
    const own = ValueKey('course-benim');
    await tap(tester, menuOf(own), wait: 500);
    await tap(tester, find.text(t('courses.archive')), wait: 500);
    expect(state.archived, {'benim'});
    expect(find.byKey(own), findsNothing);
    await tester.pump(const Duration(seconds: 3)); // bildirim kalksın
    await shot(tester, '75-biten-ve-arsiv');
    await tap(tester, find.byKey(const ValueKey('shelf-archived')));
    await tap(tester, menuOf(own), wait: 500);
    await tap(tester, find.text(t('courses.unarchive')), wait: 500);
    expect(state.archived, isEmpty);
    await tester.pump(const Duration(seconds: 3));

    // 7) Günün tekrarı: ertesi gün üç kısmın vadesi gelen soruları tek oturumda sorulur
    now = now.add(const Duration(days: 1));
    await tap(tester, find.text(t('nav.learn')));
    expect(state.dueTotal, 4 + 8 + 1);
    expect(find.text(upper(t('learn.daily'))), findsOneWidget);
    await shot(tester, '76-gunun-tekrari-dugmesi');
    await tap(tester, find.byKey(const ValueKey('review-pill')), wait: 600);
    expect((await play(tester)).length, 13);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.dailyClear')), findsOneWidget);
    await shot(tester, '77-gunun-tekrari-bitti');
    await tap(tester, label('common.continue'), wait: 600);
    expect(state.dueTotal, 0);
    // Kısımların ders kimlikleri aynıdır: her cevap kendi kursuna işlenmiş olmalı
    expect([for (final id in ['k1', 'k2', 'k3']) state.progressOf(id).memory['u1/l1#0']!.box], [2, 2, 2]);
    expect(find.text(upper(t('learn.practice'))), findsOneWidget, reason: 'günü gelen soru kalmayınca düğme pratiğe döner');

    // 8) Kurs değiştirici: seçili kurs ve son çalışılanlar
    await tap(tester, find.byKey(const ValueKey('course-chip')), wait: 500);
    expect(find.text(t('learn.switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('switch-k1')), findsOneWidget);
    expect(find.byKey(const ValueKey('switch-benim')), findsNothing, reason: 'hiç çalışılmayan kurs kısa listede yer almaz');
    await shot(tester, '78-kurs-degistirici');
    await tap(tester, find.byKey(const ValueKey('switch-k1')), wait: 500);
    expect(state.current, 'k1');
  });

  testWidgets('kısım ekleme: tek kurs kısımlı kursa dönüşür, yeni kısım önceki kısımları bilen kalıpla eklenir', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    String course(String title) => '{"id":"olasilik","title":"$title","units":[{"id":"u1","title":"Şans Nedir?","lessons":[{"title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}';
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.puhu
      ..putCourse(parseCourse(course('Olasılık')).course!);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 500));

    // Kurs menüsü → Kısım ekle: önce büyük kursun adı sorulur, kurs onun 1. kısmı olur
    await tap(tester, find.text(t('nav.courses')));
    await tap(tester, find.descendant(of: find.byKey(const ValueKey('course-olasilik')), matching: find.byTooltip(t('courses.more'))), wait: 500);
    await shot(tester, '80-kurs-menusu');
    await tap(tester, find.text(t('courses.addSection')), wait: 500);
    expect(find.text(t('section.nameTitle')), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Olasılık ve İstatistik');
    await tester.pump();
    await tap(tester, label('common.continue'), wait: 600);
    expect(state.courses['olasilik']!.group, 'Olasılık ve İstatistik');
    expect(find.text(t('create.sectionTitle', {'group': 'Olasılık ve İstatistik', 'n': 2})), findsOneWidget);
    await shot(tester, '81-kisim-olustur');

    // Kalıp, büyük kursu ve ilk kısmın ünitelerini anlatır
    await tester.enterText(find.byType(TextField).first, 'Veri ve grafikler');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, label('create.copy'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, contains('"Olasılık ve İstatistik" adlı büyük kursun 2. kısmıdır'));
    expect(clipboard, contains('1. Olasılık: Şans Nedir?'));
    expect(clipboard, contains('Konu: Veri ve grafikler'));

    // Çıktı aynı kimlikle gelse bile ilk kısmın üzerine yazılmaz: ayrı bir kurs, grubun son kısmı olur
    await tap(tester, label('create.goImport'));
    await tester.enterText(find.byType(TextField).first, course('Olasılık ve İstatistik 2: Veri'));
    await tap(tester, label('import.check'), wait: 600);
    expect(state.sectionsOf('Olasılık ve İstatistik').map((c) => c.id), ['olasilik', 'olasilik-2']);
    expect(state.courses['olasilik']!.title, 'Olasılık');
    expect(state.current, 'olasilik-2');
    await tester.pump(const Duration(seconds: 3));

    // Liste artık tek kart gösterir; kısımlar ekranında da "Kısım ekle" vardır
    await tap(tester, find.text(t('nav.courses')));
    const group = ValueKey('group-Olasılık ve İstatistik');
    expect(find.byKey(group), findsOneWidget);
    await tap(tester, find.byKey(group), wait: 500);
    expect(find.text('Veri'), findsOneWidget, reason: 'kısım adı, büyük kursun adı atılarak gösterilir');
    expect(label('courses.addSection'), findsOneWidget);
    await shot(tester, '82-kisimlar-kisim-ekle');

    // Kısım gruptan çıkarılabilir
    await tap(tester, find.descendant(of: find.byKey(const ValueKey('course-olasilik-2')), matching: find.byTooltip(t('courses.more'))), wait: 500);
    await tap(tester, find.text(t('section.leave')), wait: 500);
    expect(state.courses['olasilik-2']!.group, '');
  });

  testWidgets('önceden eklenmiş örnek kurs yeni ünitelerle büyür, ilerleme korunur', (tester) async {
    final full = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final old = full.copyWith(units: full.units.take(2).toList(), outline: full.outline.take(2).toList());
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.puhu
      ..putCourse(old);
    state.progressOf(old.id).lessons['u1/l1'] = (stars: 3, plays: 1);
    await tester.runAsync(() async {
      await tester.pumpWidget(BilgeApp(state: state));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 300));
    final now = state.courses[old.id]!;
    expect(now.units.length, 8);
    expect(state.progressOf(old.id).lessons['u1/l1']!.stars, 3);
    expect({for (var i = 0; i < now.units.length; i++) state.hostOf(state.nodes(now).firstWhere((n) => n.unitIndex == i)).name}.length, 7,
        reason: 'yedi üniteyi yedi farklı maskot sunar');
  });

  testWidgets('hatalı soru: işaretlenir, sayılmaz, düzeltme kalıbıyla düzeltilir', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tarcin
      ..putCourse(course);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));

    // Derste bir soru yanlış yapılır: can gider
    await tap(tester, label('learn.start'));
    await tap(tester, find.textContaining('XP').last, wait: 500);
    await solve(tester); // öğretici kart
    expect(await solve(tester, wrong: true), 'choice');
    expect(find.bySemanticsLabel(t('lesson.hearts', {'n': 4})), findsOneWidget);
    await shot(tester, '95-hatali-baglantisi');

    // "Bu soru hatalı": önce ne olacağı anlatılır
    await tap(tester, find.text(t('lesson.flag')), wait: 500);
    expect(find.text(t('lesson.flagTitle')), findsOneWidget);
    await shot(tester, '96-hatali-pencere');
    await tap(tester, label('lesson.flagDo'), wait: 500);
    expect(find.text(t('lesson.flagged')), findsOneWidget);
    expect(find.text(t('lesson.flag')), findsNothing);
    expect(find.bySemanticsLabel(t('lesson.hearts', {'n': 5})), findsOneWidget, reason: 'giden can geri gelir');
    expect(state.flaggedOf(state.currentCourse!).single.key, 'u1/l1#1');
    await shot(tester, '97-hatali-isaretlendi');

    // Ders biter: soru yeniden sorulmaz, yanlış sayılmaz
    await tap(tester, label('common.continue'));
    final log = await play(tester);
    expect(log.length, course.units.first.lessons.first.exercises.length - 2, reason: 'işaretlenen soru dersin sonunda yeniden gelmez');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.perfect')), findsOneWidget, reason: 'işaretlenen soru yanlış sayılmadı: ders hatasız bitti');
    expect(find.text(t('finish.flagged', {'n': 1})), findsOneWidget);
    expect(state.progressOf(course.id).lessons['u1/l1']!.stars, 3);
    expect(state.mistakeCount(state.currentCourse!), 0);
    await tap(tester, label('common.continue'), wait: 500);

    // Kursun menüsünden hatalı sorular ekranı
    await tap(tester, find.text(t('nav.courses')), wait: 500);
    await tap(tester, find.byIcon(Icons.more_vert_rounded), wait: 500);
    await tap(tester, find.text(t('courses.flagged', {'n': 1})), wait: 500);
    expect(find.text(t('flagged.title')), findsOneWidget);
    final flagged = state.flaggedOf(state.currentCourse!).single.exercise;
    expect(rich(flagged.text('question')), findsOneWidget);
    await shot(tester, '98-hatali-sorular');
    await tap(tester, label('flagged.copy'));
    expect(clipboard, contains('"format": "bilge-fix"'));
    expect(clipboard, contains(flagged.text('question')));
    await tester.pump(const Duration(seconds: 4));

    // Panoda hâlâ kalıbın kendisi var: içindeki adımlar değişmemiş, soru "düzeltildi" sayılmaz
    await tap(tester, label('flagged.apply'), wait: 500);
    expect(find.text(t('fix.unchanged')), findsOneWidget);
    expect(state.flaggedOf(state.currentCourse!).length, 1);
    await tester.pump(const Duration(seconds: 4));

    // Başka bir kurs için alınmış düzeltme bu kursa uygulanmaz (adım anahtarı aynı olsa bile)
    clipboard = jsonEncode({
      'format': 'bilge-fix',
      'course': 'baska-kurs',
      'fixes': [
        {'at': 'u1/l1#1', 'exercise': {...flagged.data, 'answer': 'Uydurma'}},
      ],
    });
    await tap(tester, label('flagged.apply'), wait: 500);
    expect(find.text(t('fix.otherCourse')), findsOneWidget);
    expect(state.flaggedOf(state.currentCourse!).length, 1);
    await tester.pump(const Duration(seconds: 4));

    // Panoda düzeltme yokken söylenir
    clipboard = 'alakasız bir metin';
    await tap(tester, label('flagged.apply'), wait: 500);
    expect(find.text(t('fix.notFix')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    // Yapay zekânın çıktısı panoda: sorulur, uygulanır
    clipboard = '```json\n${jsonEncode({
          'format': 'bilge-fix',
          'course': course.id,
          'fixes': [
            {'at': 'u1/l1#1', 'lesson': 'x', 'exercise': {...flagged.data, 'explanation': 'Düzeltilmiş açıklama.'}},
          ],
        })}\n```';
    await tap(tester, label('flagged.apply'), wait: 500);
    expect(find.text(t('fix.offerTitle', {'n': 1})), findsOneWidget);
    await shot(tester, '99-duzeltme-penceresi');
    await tap(tester, label('fix.applyDo'), wait: 500);
    expect(state.flaggedOf(state.currentCourse!), isEmpty);
    expect(find.text(t('flagged.empty')), findsOneWidget);
    expect(state.currentCourse!.units.first.lessons.first.exercises[1].explanation, 'Düzeltilmiş açıklama.');
    expect(state.dueTotal, 1, reason: 'düzeltilen soru bugünkü tekrara girer');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('kursu düzenleme: sade oluşturma ekranı, ad değiştirme, ünite silme', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tarcin
      ..putCourse(course);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, find.text(t('nav.courses')), wait: 500);

    // Kurs oluşturma: konu ve seviye yeter; boyut ayarları özetiyle kapalı gelir
    await tap(tester, find.byIcon(Icons.add_rounded).first, wait: 500);
    expect(find.text(t('create.topic')), findsOneWidget);
    expect(find.text(t('create.level')), findsOneWidget);
    expect(find.text(t('create.perMessage')), findsNothing);
    expect(find.text(t('create.density')), findsNothing);
    expect(find.textContaining(t('create.sumPer', {'n': 3})), findsOneWidget);
    await shot(tester, '88-olustur-sade');
    await tap(tester, find.byKey(const ValueKey('create-details')));
    expect(find.text(t('create.perMessage')), findsOneWidget);
    expect(find.text(t('create.density')), findsOneWidget);
    await tap(tester, find.text(t('create.perAll')));
    expect(find.textContaining(t('create.sumAll')), findsOneWidget, reason: 'özet seçime göre güncellenir');
    await shot(tester, '89-olustur-ayrintili');
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Ad değiştirme
    await tap(tester, find.byIcon(Icons.more_vert_rounded), wait: 500);
    await tap(tester, find.text(t('courses.rename')), wait: 500);
    await tester.enterText(find.byType(TextField), 'Gökyüzü Komşularımız');
    await tap(tester, label('common.save'), wait: 500);
    expect(state.courses[course.id]!.title, 'Gökyüzü Komşularımız');
    expect(find.text('Gökyüzü Komşularımız'), findsWidgets);

    // Ünite silme: önce hangi ünite, sonra onay
    final units = course.units.length;
    final second = course.units[1];
    await tap(tester, find.byIcon(Icons.more_vert_rounded), wait: 500);
    await tap(tester, find.text(t('unit.delete')), wait: 500);
    expect(find.text(t('unit.deletePick')), findsOneWidget);
    await shot(tester, '89b-unite-sec');
    await tap(tester, find.text('2. ${second.title}'), wait: 500);
    expect(find.text(t('unit.deleteTitle', {'title': second.title})), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(label('common.delete'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.courses[course.id]!.units.length, units - 1);
    expect(state.courses[course.id]!.units.any((u) => u.id == second.id), isFalse);
    expect(find.text(t('unit.deleted', {'title': second.title})), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('öğrenme ekranındaki maskot dokununca kendi ağzından bir şey söyler', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tarcin
      ..putCourse(course);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));
    final host = state.hostOf(state.nodes(course).first);
    double shown(String line) => tester.widget<AnimatedOpacity>(find.ancestor(of: find.text(line), matching: find.byType(AnimatedOpacity))).opacity;

    // Maskot ekranın ortasında: balon başının üstünde açılır
    await tester.tap(find.byType(MascotView).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(shown(host.voice.poke[0]), 1);
    final mascot = tester.getRect(find.byType(MascotView).first);
    expect(tester.getRect(find.text(host.voice.poke[0])).bottom, lessThanOrEqualTo(mascot.top + 20));
    await shot(tester, '86-maskot-sozu');
    // Balon kendiliğinden kaybolur
    await tester.pump(const Duration(seconds: 4));
    expect(shown(host.voice.poke[0]), 0);
    // Yol yukarı kaydırılıp maskot ekranın tepesine gelince balon üstte kesilmesin diye ayaklarının altında açılır;
    // ikinci dokunuşta sıradaki söz gelir
    await tester.drag(find.byType(Scrollable).first, Offset(0, 60 - mascot.top));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(MascotView).first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400)); // balon yeniden belirir
    expect(shown(host.voice.poke[1]), 1);
    expect(tester.getRect(find.text(host.voice.poke[1])).top, greaterThan(tester.getRect(find.byType(MascotView).first).bottom - 20));
    await shot(tester, '87-maskot-sozu-altta');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('maskota dokununca bir imza hareketi başlar; ders içindeki maskot tepki vermez', (tester) async {
    MascotView.animate = true;
    addTearDown(() => MascotView.animate = false);
    var pokes = 0;
    Widget view({bool calm = false}) =>
        Directionality(textDirection: TextDirection.ltr, child: Center(child: MascotView(MascotId.tarcin, size: 132, calm: calm, onPoke: () => pokes++)));
    await tester.pumpWidget(view());
    await tester.pump(const Duration(milliseconds: 100));
    final rig = tester.state(find.byType(RigMascotView)) as dynamic;
    expect(rig.clipName, isNull, reason: 'kendi kendine ilk hareket en erken bir saniye sonra başlar');
    await tester.tap(find.byType(MascotView));
    await tester.pump(const Duration(milliseconds: 100));
    expect(pokes, 1);
    final first = rig.clipName as String?;
    expect(signatures[MascotId.tarcin]!.map((c) => c.name), contains(first));
    // Hareketin ortasında yeniden dokunmak onu yarıda kesmez
    await tester.tap(find.byType(MascotView));
    await tester.pump(const Duration(milliseconds: 100));
    expect([pokes, rig.clipName], [2, first]);

    await tester.pumpWidget(view(calm: true));
    await tester.tap(find.byType(MascotView), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(pokes, 2, reason: 'ders içindeki maskot dokunmaya tepki vermez');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sorulacak bir şey kalmayan oturum ödül vermez', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tarcin
      ..putCourse(parseCourse('{"id":"k","title":"Kurs","units":[{"id":"u1","title":"Bir","lessons":[{"id":"l1","title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}').course!);
    final course = state.courses['k']!;
    // Dersin tek sorusu hatalı işaretli: pratik havuzu boş. Düğme artık görünmez; oturum yine de açılırsa hiçbir şey yazılmaz
    state.flag('k', 'u1/l1#0', course.units.first.lessons.first.exercises.first);
    expect(state.practiceItems(course), isEmpty);
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(theme: buildTheme(Palette.light), home: LessonScreen(course: course, node: const PathNode(kind: NodeKind.practice, id: '', title: ''))),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('+0'), findsOneWidget);
    expect([state.profile.xp, state.profile.lessonsDone, state.streak], [0, 0, 0]);
  });

  testWidgets('yan çevrilmiş telefon: pencerelerin düğmeleri ekranda kalır, ders oynanır', (tester) async {
    tester.view
      ..physicalSize = const Size(892, 412)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.tarcin
      ..putCourse(course);
    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));

    // Ders penceresi: "Başla" düğmesi ekranın içinde ve dokunulabilir olmalı (eskiden pencerenin altında kalıyordu)
    await tap(tester, label('learn.start'), wait: 500);
    final start = find.text(upper(t('learn.startXp', {'xp': 10})));
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.getRect(start).bottom, lessThanOrEqualTo(412));
    await shot(tester, '90-yatay-ders-penceresi');
    await tester.tap(start);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    // Ders baştan sona oynanır; taşan bir yerleşim olursa test çerçevesi hata verir
    final log = await play(tester, wrongAt: {1}, shots: {'choice'}, prefix: '91-yatay-');
    expect(log, isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(t('finish.done')), findsOneWidget);
    expect(label('common.continue').hitTestable(), findsOneWidget);
    await shot(tester, '92-yatay-bitis');
    await tap(tester, label('common.continue'), wait: 500);

    // Uzun seçenek menüsü: son seçeneğe kaydırılarak ulaşılır
    await tap(tester, find.text(t('nav.courses')), wait: 500);
    await tap(tester, find.byIcon(Icons.more_vert_rounded), wait: 500);
    await shot(tester, '93-yatay-kurs-menusu');
    await tap(tester, find.text(t('common.delete')), wait: 500);
    // Onay penceresi: iki düğme de ekranda
    expect(label('common.cancel').hitTestable(), findsOneWidget);
    await tap(tester, label('common.cancel'), wait: 500);
    expect(state.courses.containsKey(course.id), isTrue);

    // Dört düğmeli pencere (aynı kimlikli kurs): en alttaki "Vazgeç"e ulaşılır
    Future<void> send(String text) => tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('bilge/incoming', const StandardMethodCodec().encodeMethodCall(MethodCall('incoming', text)), (_) {});
    await send(jsonEncode(course.toJson()));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text(t('import.clashTitle')), findsOneWidget);
    await shot(tester, '94-yatay-dort-dugme');
    await tap(tester, label('common.cancel'), wait: 500);
    expect(find.text(t('import.clashTitle')), findsNothing);
  });

  testWidgets('yeni özellikler: yarım kalan ders, kart tarayıcısı, soru düzenleme, seri koruyucu, rozet detayı, pano algılama ve doğrudan YZ', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final reminders = <Map>[];
    const reminderChannel = MethodChannel('bilge/reminder');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(reminderChannel, (call) async {
      if (call.method == 'schedule') reminders.add(call.arguments as Map);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(reminderChannel, null));

    var now = DateTime(2026, 10, 10, 12);
    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final state = AppState(MemoryStorage(), clock: () => now);
    await state.load();
    state
      ..settings.lang = 'tr'
      ..companion = MascotId.puhu
      ..putCourse(course);

    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));

    // 1) Ünite özeti: arama ve açılır/kapanır ders başlıkları
    await tap(tester, find.text(upper(t('learn.summary'))).first, wait: 500);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bulunamayacak-kelime-xyz');
    await tester.pump();
    expect(find.text(t('notes.none')), findsOneWidget);
    await tap(tester, label('common.close'), wait: 500);

    // 2) Derse başla, bir adımı geç, bir soruyu düzenle ve dersten çık → yarım kalan ders kaydedilir
    await tap(tester, label('learn.start'), wait: 400);
    await tap(tester, find.textContaining('XP').last, wait: 500);
    await solve(tester); // info adımı (_done = 1)
    await solve(tester, wrong: true); // choice adımı yanlış
    expect(find.text(t('lesson.edit')), findsOneWidget);
    await tap(tester, find.text(t('lesson.edit')), wait: 500);
    expect(find.text(t('edit.title')), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'Yeni özel açıklama.');
    await tap(tester, label('edit.save'), wait: 500);
    await tester.pump(const Duration(seconds: 3));
    expect(state.currentCourse!.units.first.lessons.first.exercises[1].explanation, 'Yeni özel açıklama.');

    // Dersten çık: oturum kaydedilir ve öğren ekranında kurtarma kartı görünür
    await tap(tester, find.byIcon(Icons.close_rounded), wait: 400);
    await tap(tester, label('lesson.leave'), wait: 500);
    expect(state.session, isNotNull);
    expect(find.byKey(const ValueKey('resume-banner')), findsOneWidget);
    await tap(tester, find.text(t('learn.resumeDiscard')), wait: 300);
    expect(state.session, isNull);
    expect(find.byKey(const ValueKey('resume-banner')), findsNothing);

    // 3) Kartlar ve hatalarım tarayıcısı + yalnızca ezber kartı modu
    await tap(tester, find.byKey(const ValueKey('cards-btn')), wait: 500);
    expect(find.text(t('cards.title')), findsOneWidget);
    expect(find.textContaining(t('cards.tabFlash')), findsOneWidget);
    await tap(tester, find.byIcon(Icons.arrow_back_rounded), wait: 500);

    // 4) Seri koruyucu: 50 XP ile satın alınır ve 1 günlük boşlukta seriyi korur
    state.profile
      ..xp = 120
      ..streak = 2
      ..lastActive = '2026-10-08'; // 1 gün boşluk (dün 2026-10-09 atlandı)
    expect(state.buyFreeze(), isTrue);
    expect(state.profile.freezes, 1);
    expect(state.streak, 2, reason: 'koruyucu varken 1 günlük boşlukta seri sıfırlanmaz');
    final outcome = state.completeLesson(LessonResult(
      courseId: course.id,
      node: state.nodes(course).first,
      stars: 3,
      xp: 10,
      perfect: true,
      questions: 4,
      firstTry: 4,
      maxCombo: 4,
      wrongKeys: const {},
      rightKeys: const {'u1/l1#1'},
    ));
    expect(outcome.freezeUsed, isTrue);
    expect(outcome.freezeEarned, isTrue, reason: '3. güne ulaşıldığında yeni seri koruyucu kazanılır');
    expect(state.profile.streak, 3);
    expect(state.profile.freezes, 1);

    // 5) Profil: ısı haritası, rozet detayı, hatırlatıcı ve doğrudan YZ (BYOK)
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, find.text(t('nav.profile')), wait: 500);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('heatmap-panel')), 250, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('heatmap-panel')), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('badge-first')), 250, scrollable: find.byType(Scrollable).first);
    await tap(tester, find.byKey(const ValueKey('badge-first')), wait: 400);
    expect(find.text(t('badge.earnedOn', {'date': '2026-10-10'})), findsOneWidget);
    await tap(tester, label('common.close'), wait: 400);

    await tap(tester, find.byKey(const ValueKey('badge-l50')), wait: 400);
    expect(find.text(t('badge.progress', {'cur': 1, 'max': 50})), findsOneWidget);
    await tap(tester, label('common.close'), wait: 400);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('set-reminder-toggle')), 250, scrollable: find.byType(Scrollable).first);
    await tap(tester, find.byKey(const ValueKey('set-reminder-toggle')), wait: 400);
    expect(reminders.any((r) => r['enabled'] == true), isTrue, reason: 'hatırlatıcı açıldığında platform kanalına schedule gönderilir');

    await tester.scrollUntilVisible(find.byKey(const ValueKey('set-ai-row')), 250, scrollable: find.byType(Scrollable).first);
    await tap(tester, find.byKey(const ValueKey('set-ai-row')), wait: 500);
    await tester.enterText(find.byKey(const ValueKey('ai-key-field')), 'test-api-key');
    await tap(tester, label('common.save'), wait: 500);
    expect(state.settings.aiKey, 'test-api-key');

    // 6) Otomatik pano algılama ve doğrudan YZ ile kurs üretimi
    clipboard = '{"id":"pano-kursu","title":"Pano Kursu","units":[{"id":"u1","title":"Bir","lessons":[{"id":"l1","title":"D","exercises":[{"type":"truefalse","statement":"Su ıslaktır.","answer":true}]}]}]}';
    aiHandler = (provider, apiKey, model, prompt) async =>
        '{"id":"yz-kursu","title":"YZ Kursu","units":[{"id":"u1","title":"Bir","lessons":[{"id":"l1","title":"D","exercises":[{"type":"truefalse","statement":"Güneş yıldızdır.","answer":true}]}]}]}';
    addTearDown(() => aiHandler = null);

    await tap(tester, find.text(t('nav.courses')), wait: 400);
    await tap(tester, find.byIcon(Icons.add_rounded).first, wait: 500);
    expect(find.text(t('clip.found')), findsOneWidget);
    expect(label('clip.courseAdd', {'title': 'Pano Kursu'}), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Astronomi');
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, label('create.generateAi'), wait: 600);
    expect(state.courses.containsKey('yz-kursu'), isTrue);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('multi sorusunda mükerrer seçenek ile eksik cevap kabul edilmez', (tester) async {
    final ex = Exercise({
      'type': 'multi',
      'question': 'Seç',
      'options': ['A', 'B', 'A'],
      'answers': ['A', 'B'],
    });
    final view = ExerciseView(
      key: const ValueKey('multi-test'),
      exercise: ex,
      host: characterOf(MascotId.puhu),
      color: Colors.blue,
      locale: 'tr',
      random: math.Random(1),
      onReady: (_) {},
      onDone: (_) {},
      onSubmit: () {},
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Palette.light),
      home: Scaffold(body: view),
    ));
    await tester.pump();

    final state = tester.state<ExerciseViewState>(find.byKey(const ValueKey('multi-test')));
    await tap(tester, find.text('A').first);
    await tap(tester, find.text('A').last);
    final res = state.check();
    expect(res.correct, isFalse, reason: 'B seçilmediği için doğru sayılmamalı');
  });

  testWidgets('profil ekranı 892x412 yatay boyutta taşma olmadan açılır, rozet penceresi çalışır', (tester) async {
    tester.view
      ..physicalSize = const Size(892, 412)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(MemoryStorage());
    await state.load();
    state.settings.lang = 'tr';
    state.profile.xp = 150;
    state.profile.streak = 5;
    state.profile.bestStreak = 7;
    state.profile.lessonsDone = 15;
    state.profile.badges['first'] = '2026-10-15';
    state.profile.badges['s3'] = '2026-10-18';
    state.companion = MascotId.tarcin;

    await tester.pumpWidget(RepaintBoundary(key: _boundary, child: BilgeApp(state: state)));
    await tester.pump(const Duration(milliseconds: 300));

    // Profil sekmesine git
    await tap(tester, find.text(t('nav.profile')), wait: 500);
    await tester.scrollUntilVisible(find.text(t('profile.badges')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text(t('profile.badges')), findsOneWidget);

    // Kazanılmış rozet detayı (sheetBody modal sheet)
    await tester.scrollUntilVisible(find.byKey(const ValueKey('badge-first')), 150, scrollable: find.byType(Scrollable).first);
    await tap(tester, find.byKey(const ValueKey('badge-first')), wait: 400);
    expect(find.text(t('badge.earnedOn', {'date': '2026-10-15'})), findsOneWidget);
    expect(label('common.close').hitTestable(), findsOneWidget);
    await tap(tester, label('common.close'), wait: 400);

    // Kilitli / kazanılmamış rozet detayı (ilerleme e.g. 7 / 30 gün)
    await tester.scrollUntilVisible(find.byKey(const ValueKey('badge-s30')), 150, scrollable: find.byType(Scrollable).first);
    await tap(tester, find.byKey(const ValueKey('badge-s30')), wait: 400);
    expect(find.text(t('badge.progress', {'cur': 7, 'max': '30 gün'})), findsOneWidget);
    expect(label('common.close').hitTestable(), findsOneWidget);
    await tap(tester, label('common.close'), wait: 400);

    // Yol arkadaşı seçimi bölümünün rozetlerin altında yer aldığını doğrula
    await tester.scrollUntilVisible(find.text(t('profile.crew')), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text(t('profile.crew')), findsOneWidget);
  });

  testWidgets('uygulama yeniden açıldığında yol ilerideki sıradaki derse kendiliğinden konumlanır', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final course = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync()).course!;
    final storage = MemoryStorage();
    final saved = AppState(storage);
    await saved.load();
    saved
      ..settings.lang = 'tr'
      ..companion = MascotId.tarcin
      ..putCourse(course);
    // İlk 5 ünitenin tüm düğümleri tamamlanmış olsun; sıradaki ders 6. ünitedeki u6/l1
    for (final n in saved.nodes(course).where((n) => n.unitIndex < 5)) {
      saved.progressOf(course.id).lessons[n.id] = (stars: 3, plays: 1);
    }
    saved.commit();
    await tester.pump();

    // Uygulama kapatılıp diskten yeniden açılır
    final reopened = AppState(storage);
    await reopened.load();
    expect(reopened.statusOf(reopened.currentCourse!)['u6/l1'], NodeStatus.current);

    await tester.pumpWidget(BilgeApp(state: reopened));
    await tester.pump();

    final target = find.byKey(const ValueKey('node-u6/l1'));
    expect(target.hitTestable(), findsOneWidget, reason: 'sıradaki ders ekranın içinde ve dokunulabilir');
    final rect = tester.getRect(target);
    expect(rect.top, greaterThan(0), reason: 'sıradaki ders ekranın içinde görünür');
    expect(rect.bottom, lessThan(892), reason: 'sıradaki ders ekranın içinde görünür');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(scroll, greaterThan(1000), reason: 'yol en baştan değil, sıradaki dersin olduğu yerden açılır');
  });
}
