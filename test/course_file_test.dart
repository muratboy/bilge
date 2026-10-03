// Bir kurs dosyasını ya da kurs paketini baştan sona denetler:
//   BILGE_COURSE=<dosya> flutter test test/course_file_test.dart
// Kalıba uyuyor mu, formülleri ve grafikleri çizilebiliyor mu, her dersi uygulamada sonuna kadar oynanabiliyor mu?
import 'dart:convert';
import 'dart:io';

import 'package:bilge/app_scope.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/core/store.dart';
import 'package:bilge/l10n/l10n.dart';
import 'package:bilge/lesson/lesson_screen.dart';
import 'package:bilge/main.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/mascot/mascot_view.dart';
import 'package:bilge/ui/confetti.dart';
import 'package:bilge/ui/sfx.dart';
import 'package:bilge/ui/theme.dart';
import 'package:bilge/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show label, play, tap;

void main() {
  final path = Platform.environment['BILGE_COURSE'];
  if (path == null) {
    test('kurs dosyası verilmedi (BILGE_COURSE)', () {}, skip: true);
    return;
  }
  final text = File(path).readAsStringSync();
  final pack = parsePack(text);
  // Tek kurs da paket de aynı denetimlerden geçer
  List<Course> courses() => pack != null ? pack.pack!.courses : [parseCourse(text).course!];

  test('kalıba uyar: uyarısız yüklenir, gidiş-dönüş aynı kalır', () {
    if (pack != null) {
      expect([pack.errors, pack.warnings], [isEmpty, isEmpty]);
      final again = parsePack(jsonEncode(pack.pack!.toJson()))!;
      expect(jsonEncode(again.pack!.toJson()), jsonEncode(pack.pack!.toJson()));
      expect({for (final c in pack.pack!.courses) c.id}.length, pack.pack!.courses.length);
      // ignore: avoid_print
      print('Paket “${pack.pack!.title}”: ${pack.pack!.courses.length} kurs');
    } else {
      final r = parseCourse(text);
      expect([r.errors, r.warnings, r.notes], [isEmpty, isEmpty, isEmpty]);
    }
    for (final c in courses()) {
      final again = parseCourse(jsonEncode(c.toJson()));
      expect([again.errors, again.warnings, again.notes], [isEmpty, isEmpty, isEmpty], reason: c.title);
      expect(jsonEncode(again.course!.copyWith(group: c.group).toJson()), jsonEncode(c.toJson()));
      expect(c.outline.length, c.units.length);
      // ignore: avoid_print
      print('${c.title}: ${c.units.length} ünite · ${c.lessonCount} ders · ${c.exerciseCount} adım');
    }
  });

  testWidgets('bütün formüller çizilebilir', (tester) async {
    final strings = <String>{};
    void walk(dynamic v) {
      if (v is String) {
        if (v.contains(r'$') || v.contains(r'\(')) strings.add(v);
      } else if (v is List) {
        v.forEach(walk);
      } else if (v is Map) {
        v.values.forEach(walk);
      }
    }

    for (final c in courses()) {
      walk(c.toJson());
    }
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Palette.light),
      home: Material(child: SingleChildScrollView(child: Column(children: [for (final s in strings) MdBlock(s)]))),
    ));
    final broken = find.descendant(of: find.byType(Formula), matching: find.byType(Text));
    expect([for (final e in broken.evaluate()) (e.widget as Text).data], isEmpty, reason: 'çizilemeyen formüller');
    // ignore: avoid_print
    print('${find.byType(Formula).evaluate().length} formül çizildi');
  });

  testWidgets('her ders uygulamada sonuna kadar oynanır', (tester) async {
    MascotView.animate = false;
    Confetti.enabled = false;
    Sfx.available = false;
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(MemoryStorage());
    await state.load();
    state
      ..settings.lang = 'tr'
      ..settings.freeMode = true
      ..settings.hearts = false
      ..companion = MascotId.puhu;
    for (final c in courses()) {
      state.putCourse(c);
    }
    await tester.pumpWidget(BilgeApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    for (final course in courses()) {
    var steps = 0, charts = 0;
    for (final node in state.nodes(course).where((n) => n.kind == NodeKind.lesson)) {
      charts += state.itemsOf(node).where((it) => it.chart != null).length;
      final context = tester.element(find.byType(Scaffold).first);
      LessonScreen.open(context, AppScope.read(context).courses[course.id]!, node);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final log = await play(tester);
      expect(log.where((s) => s.contains('✗')), isEmpty);
      steps += log.length;
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(t('finish.perfect')).evaluate().isNotEmpty || find.text(t('finish.done')).evaluate().isNotEmpty, isTrue, reason: '${node.id} bitmedi: $log');
      expect(state.progressOf(course.id).lessons[node.id]?.stars, 3, reason: '${node.id}: bir adım doğru çözülemedi ($log)');
      await tap(tester, label('common.continue'), wait: 600);
    }
    expect(steps, course.exerciseCount);
    // ignore: avoid_print
    print('${course.title}: $steps adım oynandı, $charts adımda grafik var');
    }
    await tester.pump(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
