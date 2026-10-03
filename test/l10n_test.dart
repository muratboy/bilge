import 'dart:io';

import 'package:bilge/core/prompt.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/l10n/l10n.dart';
import 'package:bilge/mascot/cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => L.code = 'tr');

  test('iki dilin anahtarları aynı', () {
    expect(en.keys.toSet().difference(tr.keys.toSet()), isEmpty);
    expect(tr.keys.toSet().difference(en.keys.toSet()), isEmpty);
  });

  test('kodda kullanılan her anahtar tabloda var', () {
    final used = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r"""\bt\(\s*'([a-zA-Z0-9_.]+)'""").allMatches(src)) {
        used.add(m[1]!);
      }
      for (final m in RegExp(r"""L\.list\('([a-zA-Z0-9_.]+)'\)""").allMatches(src)) {
        used.add(m[1]!);
      }
    }
    expect(used.length, greaterThan(120));
    expect(used.where((k) => !tr.containsKey(k)), isEmpty, reason: 'tabloda olmayan anahtarlar');
  });

  test('yer tutucular iki dilde aynı', () {
    final ph = RegExp(r'(?<!\{)\{(\w+)\}(?!\})');
    for (final k in tr.keys) {
      expect(ph.allMatches(en[k]!).map((m) => m[1]).toSet(), ph.allMatches(tr[k]!).map((m) => m[1]).toSet(), reason: k);
    }
  });

  test('İngilizce: kalıp, hata iletileri, maskot replikleri, büyük harf', () {
    L.code = 'en';
    final p = buildPrompt(PromptOptions(topic: 'Basic statistics', units: 4));
    for (final s in ['Basic statistics', '4 units', 'Course language: English', 'COURSE COMPLETE']) {
      expect(p, contains(s));
    }
    final examples = p.split('\n').where((l) => l.startsWith('`{"type"')).map((l) => l.substring(1, l.length - 1)).toList();
    expect(examples.length, exerciseTypes.length);
    final r = parseCourse('{"title":"T","units":[{"id":"u1","title":"U","lessons":[{"title":"L","exercises":[${examples.join(',')},{"type":"choice","question":"q"}]}]}]}');
    expect(r.course!.exerciseCount, 12);
    expect(r.warnings.single, 'Unit 1 › Lesson 1 › step 13 (choice): "answer" is missing — skipped.');
    expect(parseCourse('nope').errors.single, startsWith('No JSON found'));
    expect(cast.first.voice.species, 'Owl');
    expect(upper('finish'), 'FINISH');
    L.code = 'tr';
    expect(cast.first.voice.species, 'Baykuş');
    expect(upper('bitir'), 'BİTİR');
  });

  test('İngilizce örnek kurs uyarısız yüklenir ve Türkçesiyle aynı yapıdadır', () {
    final enCourse = parseCourse(File('assets/courses/solar-system.bilge.json').readAsStringSync());
    final trCourse = parseCourse(File('assets/courses/gunes-sistemi.bilge.json').readAsStringSync());
    expect(enCourse.warnings, isEmpty);
    expect(enCourse.course!.language, 'en');
    List<String> shape(Course c) => [for (final u in c.units) for (final l in u.lessons) for (final e in l.exercises) '${l.id}:${e.type}'];
    expect(shape(enCourse.course!), shape(trCourse.course!));
  });
}
