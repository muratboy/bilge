/// Kurs kalıbı: yapıştırılan metinden JSON'u bulur, doğrular ve tek tip biçime çevirir.
/// Çıktı biçimi girdiyle aynıdır; dışa aktarılan bir kurs yeniden içe aktarılabilir.
library;

import 'dart:convert';

import '../l10n/l10n.dart';
import 'expr.dart';
import 'text_utils.dart';

const courseFormat = 'bilge-course';
const courseVersion = 1;
const _maxUnits = 60, _maxLessons = 30, _maxExercises = 40, _maxText = 2000, _maxBody = 4000;

/// Başlık gibi tek satırlık alanların sınırı. Bu alanlar ekranda dar yerde durur ve "ünite ekle" kalıbına
/// yazılır: başkasından gelen bir kurs, uzun ya da çok satırlı bir başlıkla kalıba kendi talimatını sokamasın.
const _maxTitle = 120, _maxBlurb = 300;

/// Bir listeden en çok bu kadar öğe okunur (şık, çift, etiket…); gerisine bakılmaz.
const _maxItems = 60;

/// Yapıştırılan, dosyadan ya da bağlantıdan gelen metnin en büyük boyu (karakter).
const maxImportChars = 8000000;

const exerciseTypes = ['info', 'choice', 'multi', 'truefalse', 'fill', 'type', 'number', 'match', 'order', 'build', 'categorize', 'flashcard'];

// LLM'lerin sık kullandığı başka adlar
const _aliases = {
  'concept': 'info', 'teach': 'info', 'note': 'info', 'explain': 'info',
  'mcq': 'choice', 'multiple_choice': 'choice', 'single': 'choice', 'single_choice': 'choice', 'quiz': 'choice',
  'multi_select': 'multi', 'multiselect': 'multi', 'multiple': 'multi', 'checkbox': 'multi',
  'true_false': 'truefalse', 'tf': 'truefalse', 'boolean': 'truefalse',
  'fill_blank': 'fill', 'fill_in_the_blank': 'fill', 'blank': 'fill', 'cloze': 'fill',
  'text': 'type', 'input': 'type', 'short_answer': 'type', 'write': 'type',
  'numeric': 'number', 'numerical': 'number', 'num': 'number', 'calculate': 'number', 'calculation': 'number',
  'matching': 'match', 'pairs': 'match',
  'sort': 'order', 'sequence': 'order', 'ordering': 'order',
  'sentence': 'build', 'arrange': 'build', 'word_bank': 'build',
  'classify': 'categorize', 'group': 'categorize', 'bucket': 'categorize', 'category': 'categorize',
  'card': 'flashcard', 'flash': 'flashcard',
};

/* ---------- Model ---------- */

/// Bir ders adımı. Alanlar tipine göre değişir; hepsi [data] içinde kalıp biçimiyle durur.
class Exercise {
  Exercise(this.data);
  final Map<String, dynamic> data;

  String get type => data['type'] as String;
  bool get isQuestion => type != 'info' && type != 'flashcard';

  /// Aralıklı tekrara girer mi: sorular ve ezber kartları (öğretici kartlar girmez).
  bool get isReviewable => type != 'info';
  String text(String key) => (data[key] as String?) ?? '';
  List<String> list(String key) => ((data[key] as List?) ?? const []).cast<String>();
  String get explanation => text('explanation');
  String get hint => text('hint');
  String get solution => text('solution');

  /// Adımı bir listede tanıtan kısa metin: sorunun kendisi (boşluk doldurmada boşluklar çizgiyle gösterilir).
  String get headline {
    if (type == 'fill') return [text('question'), fillParts(text('text')).map((p) => p.blank ? '_____' : p.text).join()].where((s) => s.isNotEmpty).join(' ');
    return ['question', 'statement', 'front', 'title', 'body'].map(text).firstWhere((s) => s.isNotEmpty, orElse: () => '');
  }

  /// Cevap anahtarının tek satırlık özeti (hatalı işaretlenen soruyu listede tanımak için).
  String get answerText => switch (type) {
        'choice' || 'type' => text('answer'),
        'multi' => list('answers').join(' · '),
        'truefalse' => t(data['answer'] == true ? 'lesson.true' : 'lesson.false'),
        'fill' => fillParts(text('text')).where((p) => p.blank).map((p) => p.text).join(' · '),
        'number' => '${data['answer']}${text('unit').isEmpty ? '' : ' ${text('unit')}'}',
        'match' => pairs.map((p) => '${p[0]} → ${p[1]}').join(' · '),
        'order' => list('items').join(' → '),
        'build' => list('answer').join(' '),
        'categorize' => categories.map((c) => '${c.name}: ${c.items.join(', ')}').join(' · '),
        'flashcard' => text('back'),
        _ => '',
      };

  /// Adımın sorusundan ve cevap anahtarından türeyen kısa iz. Kullanıcının "hatalı" işareti sıraya ("ders#sıra")
  /// bağlıdır; ünite yeniden üretilip aynı sıraya başka bir adım geldiyse iz tutmaz ve işaret geçersiz sayılır.
  /// Arayüz diline ve açıklama, ipucu gibi yan alanlara bağlı değildir.
  String get fingerprint {
    const fields = ['type', 'question', 'statement', 'text', 'front', 'back', 'answer', 'answers', 'distractors', 'pairs', 'items', 'categories', 'unit'];
    final core = jsonEncode([
      for (final k in fields)
        if (data[k] != null) data[k],
    ]);
    var h = 0x811c9dc5; // FNV-1a
    for (final u in core.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Bu adım kullanıcının düzelttirdiği bir adımsa, yerine geçtiği (hatalı) adımın izi; değilse boş.
  /// Kursun içeriği yenilenirken aynı sırada hâlâ o hatalı adım geliyorsa düzeltilmiş hâl korunur (AppState).
  String get fixedFrom => text('fixedFrom');

  /// Adımın kalıba yazılan ve karşılaştırılan içeriği: uygulamanın kendi tuttuğu [fixedFrom] dışında her şey.
  Map<String, dynamic> get content => {
        for (final e in data.entries)
          if (e.key != 'fixedFrom') e.key: e.value,
      };

  /// Cihazın sesli okuyacağı metin (dil kurslarında dinleme için).
  String get say => text('say');
  Map<String, dynamic>? get chart => data['chart'] as Map<String, dynamic>?;
  List<List<String>> get pairs => ((data['pairs'] as List?) ?? const []).map((p) => (p as List).cast<String>()).toList();
  List<({String name, List<String> items})> get categories => ((data['categories'] as List?) ?? const [])
      .map((c) => (name: c['name'] as String, items: (c['items'] as List).cast<String>()))
      .toList();
}

class Lesson {
  Lesson({required this.id, required this.title, this.context = '', this.chart, required this.exercises});
  final String id; // "ünite/ders": kurs içinde benzersiz
  final String title;
  final String context; // dersteki soruların dayandığı ortak metin (okuma parçası, vaka, veri)
  final Map<String, dynamic>? chart; // dersteki soruların dayandığı ortak grafik
  final List<Exercise> exercises;

  /// Adımın üstünde gösterilecek grafik: adımın kendi grafiği, yoksa (sorularda) dersinki.
  Map<String, dynamic>? chartOf(Exercise e) => e.chart ?? (e.isQuestion ? chart : null);

  /// Adımın üstünde gösterilecek ortak metin: adımın kendi metni, yoksa dersinki. Öğretici kartlarda gösterilmez.
  String contextOf(Exercise e) => !e.isQuestion ? '' : (e.text('context').isEmpty ? context : e.text('context'));

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, if (context.isNotEmpty) 'context': context, if (chart != null) 'chart': chart, 'exercises': [for (final e in exercises) e.data]};

  /// Verilmeyen alanlar olduğu gibi kalır: derse yeni bir alan eklendiğinde kopyalarda unutulmaz.
  Lesson copyWith({String? id, List<Exercise>? exercises}) =>
      Lesson(id: id ?? this.id, title: title, context: context, chart: chart, exercises: exercises ?? this.exercises);
}

class Unit {
  Unit({required this.id, required this.title, this.description = '', this.emoji = '', required this.lessons});
  final String id, title, description, emoji;
  final List<Lesson> lessons;
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'description': description, 'emoji': emoji, 'lessons': [for (final l in lessons) l.toJson()]};

  Unit copyWith({String? id, List<Lesson>? lessons}) =>
      Unit(id: id ?? this.id, title: title, description: description, emoji: emoji, lessons: lessons ?? this.lessons);
}

class Course {
  Course({
    required this.id,
    required this.title,
    this.description = '',
    this.emoji = '',
    this.language = 'tr',
    this.author = '',
    this.group = '',
    this.sayLang = '',
    this.outline = const [],
    required this.units,
  });
  final String id, title, description, emoji, language, author;

  /// Kursun ait olduğu paket ya da kurum (kurs listesinde bu ad altında gruplanır); boşsa kullanıcının kendi kursu.
  final String group;

  /// Sesli okunan metinlerin dili (dil kurslarında öğrenilen dil); boşsa kursun dili.
  final String sayLang;
  final List<String> outline;
  final List<Unit> units;

  int get lessonCount => units.fold(0, (n, u) => n + u.lessons.length);
  int get exerciseCount => units.fold(0, (n, u) => n + u.lessons.fold(0, (m, l) => m + l.exercises.length));

  Map<String, dynamic> toJson() => {
        'format': courseFormat, 'version': courseVersion, 'id': id, 'title': title, 'description': description,
        'emoji': emoji, 'language': language, if (sayLang.isNotEmpty) 'sayLang': sayLang, 'author': author,
        if (group.isNotEmpty) 'group': group, 'outline': outline,
        'units': [for (final u in units) u.toJson()],
      };

  Course copyWith({String? id, String? title, String? description, String? emoji, String? author, String? group, String? sayLang, List<String>? outline, List<Unit>? units}) =>
      Course(
        id: id ?? this.id, title: title ?? this.title, description: description ?? this.description, emoji: emoji ?? this.emoji,
        language: language, author: author ?? this.author, group: group ?? this.group, sayLang: sayLang ?? this.sayLang, outline: outline ?? this.outline, units: units ?? this.units,
      );
}

class ParseReport {
  Course? course;
  final List<String> errors = [];
  final List<String> warnings = []; // kalıba uymadığı için atlanan parçalar
  final List<String> notes = []; // kullanıcının bilmesi gereken eksikler (yarıda kesilmiş çıktı gibi)
}

/* ---------- Alan okuma ---------- */

class _Skip implements Exception {
  _Skip(this.message);
  final String message;
}

Never _fail(String message) => throw _Skip(message);

final _bidi = RegExp('[\u202a-\u202e\u2066-\u2069]');

String _str(dynamic v, [int max = _maxText]) {
  if (v is num) return '$v';
  if (v is! String) return '';
  // Sınırı çok aşan metin onarılmadan önce kesilir: dev bir alan ayrıştırmayı yavaşlatamaz
  var s = v;
  if (s.contains(_bidi)) s = s.replaceAll(_bidi, '');
  if (s.length > max + 64) s = s.trimLeft();
  if (s.length > max + 64) s = s.substring(0, max + 64);
  return _cut(_repairMath(s).trim(), max);
}

/// En çok [max] karakter; iki parçalı bir karakteri (emoji gibi) ortasından bölmez.
String _cut(String s, int max) {
  if (s.length <= max) return s;
  final end = (s.codeUnitAt(max - 1) & 0xFC00) == 0xD800 ? max - 1 : max;
  return s.substring(0, end).trimRight();
}

final _spaces = RegExp(r'[\s\u0000-\u001f\u007f]+');

/// Tek satırlık alan (başlık, tanıtım, hazırlayan): satır sonları boşluğa çevrilir, yön değiştiren
/// görünmez karakterler atılır.
String _label(dynamic v, [int max = _maxTitle]) => _cut(_str(v, max * 2).replaceAll(_spaces, ' ').trim(), max);

// JSON'da "\frac", "\times" gibi komutlar tek ters eğik çizgiyle yazılırsa \f, \t, \n… denetim karakterine dönüşür.
// Formül ($...$) içinde kalanları geri çevirir.
final _control = RegExp(r'[\b\f\t\r\n]');
final _brokenN = RegExp(r'\n(?=(?:eq?|u|abla|ot(?:in)?|eg|i|leq|geq|less|gtr|mid|parallel|subseteq|exists|earrow|warrow|ewline|cong|sim|atural)(?![a-zA-Z]))');
final _brokenR = RegExp(r'\r(?=[a-zA-Z])');
// Bozulmuş bir komutta sekmeyi harf izler ("\times" → sekme + "imes"); girinti ya da sütun ayıran gerçek sekmeyi izlemez
final _brokenT = RegExp(r'\t(?=[a-zA-Z])');
final _inlineCode = RegExp(r'`[^`\n]+`');

/// Kod parçaları onarılmaz: ``` çitli bloktaki ve `satır içi` koddaki $ işaretleri formül sınırı değil, aralarındaki
/// sekmeler de gerçektir (kabuk, PHP, Makefile). Kod, ekrana çizilirken de aynı kuralla ayrılır (MdBlock).
String _repairMath(String s) {
  if (!s.contains(r'$')) return s;
  if (!s.contains('`')) return _repairFormulas(s);
  final parts = s.split('```');
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i].splitMapJoin(_inlineCode, onNonMatch: _repairFormulas);
  }
  return parts.join('```');
}

/// Metni bir kez baştan sona tarar ($ işaretinden sıradaki $ işaretine); süre metnin boyuyla doğru orantılıdır.
String _repairFormulas(String s) {
  var open = s.indexOf(r'$');
  if (open < 0) return s;
  StringBuffer? out;
  var done = 0;
  while (open >= 0) {
    final close = s.indexOf(r'$', open + 1);
    if (close < 0) break;
    final formula = s.substring(open, close + 1);
    if (!_control.hasMatch(formula)) {
      // Formül değil ya da bozulmamış: kapanan işaret sıradaki formülü açıyor olabilir
      open = close;
      continue;
    }
    (out ??= StringBuffer())
      ..write(s.substring(done, open))
      ..write(formula
          .replaceAll('\b', r'\b')
          .replaceAll('\f', r'\f')
          .replaceAllMapped(_brokenT, (_) => r'\t')
          .replaceAllMapped(_brokenR, (_) => r'\r')
          .replaceAllMapped(_brokenN, (_) => r'\n'));
    done = close + 1;
    open = s.indexOf(r'$', done);
  }
  if (out == null) return s;
  out.write(s.substring(done));
  return out.toString();
}

/// Sayı ya da sayı yazılmış metin ("9,81", "3/4"). Tam sayılar int olarak kalır.
num? _num(dynamic v) {
  final n = v is num ? v : (v is String && v.length <= 64 ? parseNumbers(v).firstOrNull : null);
  if (n == null || !n.isFinite) return null;
  return n == n.roundToDouble() && n.abs() < 1e15 ? n.round() : n;
}

List<String> _list(dynamic v) {
  if (v is List) return v.take(_maxItems).map(_str).where((s) => s.isNotEmpty).toList();
  final s = _str(v);
  return s.isEmpty ? [] : [s];
}

/// Aynı anlama gelen (büyük/küçük harf, boşluk, sondaki nokta farkıyla aynı) öğelerden ilkini bırakır.
/// Her öğe bir kez sadeleştirilir: öğeleri birbiriyle tek tek karşılaştırmak uzun listede dakikalar sürüyordu.
List<String> _uniq(Iterable<String> items) {
  final seen = <String>{};
  return [
    for (final x in items)
      if (seen.add(norm(x))) x,
  ];
}

List<T> _take<T>(List<T> items, int n) => items.length > n ? items.sublist(0, n) : items;

dynamic _first(Map e, List<String> keys) {
  for (final k in keys) {
    if (e[k] != null) return e[k];
  }
  return null;
}

/// Şıkların "options" + "answer" (metin ya da sıra numarası) ile verildiği yazım.
({List<String> answers, List<String> distractors}) _fromOptions(Map e, {required bool many}) {
  final opts = _list(e['options'] ?? e['choices']);
  final raw = _first(e, many ? ['answers', 'answer', 'correct'] : ['answer', 'correct']);
  // Aynı anlama gelen iki şık varsa ilki geçerlidir
  final byKey = {for (final o in opts.reversed) norm(o): o};
  final wanted = <String>[];
  for (final a in raw is List ? raw.take(_maxItems) : [raw]) {
    final hit = a is int ? (a >= 0 && a < opts.length ? opts[a] : null) : byKey[norm(_str(a))];
    if (hit == null) _fail(t('r.notInOptions'));
    wanted.add(hit);
  }
  final picked = wanted.toSet();
  return (answers: wanted, distractors: opts.where((o) => !picked.contains(o)).toList());
}

final _blank = RegExp(r'\{\{(.+?)\}\}');

/// "Su {{100}} °C'de kaynar." → metin ve boşluk parçaları.
List<({bool blank, String text})> fillParts(String text) {
  final parts = <({bool blank, String text})>[];
  var last = 0;
  for (final m in _blank.allMatches(text)) {
    if (m.start > last) parts.add((blank: false, text: text.substring(last, m.start)));
    parts.add((blank: true, text: m[1]!.trim()));
    last = m.end;
  }
  if (last < text.length) parts.add((blank: false, text: text.substring(last)));
  return parts;
}

/* ---------- Adım tipleri ---------- */

Map<String, dynamic> _normalize(String type, Map e) {
  String question() {
    final q = _str(e['question'] ?? e['prompt']);
    return q.isEmpty ? _fail(t('r.question')) : q;
  }

  switch (type) {
    case 'info':
      final body = _str(e['body'] ?? e['text'] ?? e['content'], _maxBody);
      if (body.isEmpty) _fail(t('r.bodyEmpty'));
      return {'title': _str(e['title']), 'body': body, 'example': _str(e['example'])};
    case 'choice':
      final q = question();
      var answer = _str(e['answer'] ?? e['correct']);
      var distractors = _list(e['distractors'] ?? e['wrong']);
      if ((e['options'] ?? e['choices']) is List) {
        final o = _fromOptions(e, many: false);
        answer = o.answers.first;
        distractors = o.distractors;
      }
      if (answer.isEmpty) _fail(t('r.answerMissing'));
      final key = norm(answer);
      distractors = _take(_uniq(distractors).where((d) => norm(d) != key).toList(), 5);
      if (distractors.isEmpty) _fail(t('r.needDistractor'));
      return {'question': q, 'answer': answer, 'distractors': distractors};
    case 'multi':
      final q = question();
      var answers = _list(e['answers'] ?? e['answer'] ?? e['correct']);
      var distractors = _list(e['distractors'] ?? e['wrong']);
      if ((e['options'] ?? e['choices']) is List) {
        final o = _fromOptions(e, many: true);
        answers = o.answers;
        distractors = o.distractors;
      }
      answers = _uniq(answers);
      final keys = {for (final a in answers) norm(a)};
      distractors = _uniq(distractors).where((d) => !keys.contains(norm(d))).toList();
      if (answers.isEmpty) _fail(t('r.answersMissing'));
      if (distractors.isEmpty) _fail(t('r.needDistractor'));
      return {'question': q, 'answers': _take(answers, 5), 'distractors': _take(distractors, 5)};
    case 'truefalse':
      final statement = _str(e['statement'] ?? e['question'] ?? e['text']);
      if (statement.isEmpty) _fail(t('r.statement'));
      final a = e['answer'] is String ? norm(e['answer'] as String) : e['answer'];
      final answer = (a == true || a == 'true' || a == 'doğru') ? true : (a == false || a == 'false' || a == 'yanlış') ? false : null;
      if (answer == null) _fail(t('r.tfAnswer'));
      return {'statement': statement, 'answer': answer};
    case 'fill':
      final q = _str(e['question']);
      var text = _str(e['text'] ?? e['sentence']);
      if (text.isEmpty && RegExp(r'\{\{|_{2,}').hasMatch(q)) text = q;
      if (text.isEmpty) _fail(t('r.textMissing'));
      // "___" + "answer" yazımını {{...}} biçimine çevir
      if (!_blank.hasMatch(text) && text.contains(RegExp('_{2,}'))) {
        final answers = _list(e['answers'] ?? e['answer']);
        var i = 0;
        text = text.replaceAllMapped(RegExp('_{2,}'), (m) => i < answers.length ? '{{${answers[i++]}}}' : m[0]!);
      }
      final blanks = fillParts(text).where((p) => p.blank).map((p) => p.text).toList();
      if (blanks.isEmpty) _fail(t('r.noBlank'));
      if (blanks.length > 4) _fail(t('r.tooManyBlanks'));
      final keys = {for (final b in blanks) norm(b)};
      final distractors = _uniq(_list(e['distractors'] ?? e['wrong'])).where((d) => !keys.contains(norm(d))).toList();
      return {'question': q == text ? '' : q, 'text': text, 'distractors': _take(distractors, 5)};
    case 'type':
      final q = question();
      final all = [..._list(e['answer'] ?? e['answers']), ..._list(e['accept'] ?? e['alternatives'])];
      if (all.isEmpty) _fail(t('r.answerMissing'));
      return {'question': q, 'answer': all.first, 'accept': _take(_uniq(all.skip(1)), 12)};
    case 'number':
      final q = question();
      var raw = _first(e, ['answer', 'value', 'correct']);
      if (raw is String) raw = _str(raw, 80);
      var unit = _str(e['unit'] ?? e['units'], 24);
      // "10 m/s" gibi birimiyle yazılmış cevap: sayıyı ve birimi ayır
      final withUnit = raw is String ? RegExp(r'^\s*([+\-−]?[\d.,\s]*\d)\s*(\D.*)$').firstMatch(raw) : null;
      if (withUnit != null && parseNumbers(raw as String).isEmpty) {
        raw = withUnit[1];
        if (unit.isEmpty) unit = _str(withUnit[2], 24);
      }
      final answer = _num(raw);
      if (answer == null) _fail(t('r.numberAnswer'));
      var tol = _first(e, ['tolerance', 'tol', 'margin']);
      if (tol is String) tol = _str(tol, 40);
      final percent = tol is String && tol.trim().endsWith('%') ? _num(tol.trim().replaceFirst(RegExp(r'\s*%$'), '')) : null;
      final tolerance = percent != null ? answer.abs() * percent / 100 : (_num(tol) ?? 0);
      return {'question': q, 'answer': answer, 'tolerance': _num(tolerance.abs()) ?? 0, 'unit': unit};
    case 'match':
      final raw = e['pairs'] is List ? e['pairs'] as List : e['pairs'] is Map ? (e['pairs'] as Map).entries.map((x) => [x.key, x.value]).toList() : const [];
      final pairs = <List<String>>[];
      final left = <String>{}, right = <String>{};
      for (final p in raw.take(_maxItems)) {
        final a = _str(p is List ? (p.isNotEmpty ? p[0] : null) : p is Map ? _first(p, ['left', 'a', 'term', 'key']) : null);
        final b = _str(p is List ? (p.length > 1 ? p[1] : null) : p is Map ? _first(p, ['right', 'b', 'definition', 'value']) : null);
        if (a.isEmpty || b.isEmpty) continue;
        // Sol ya da sağ tarafı daha önce geçen çift alınmaz
        final ka = norm(a), kb = norm(b);
        if (left.contains(ka) || right.contains(kb)) continue;
        left.add(ka);
        right.add(kb);
        pairs.add([a, b]);
      }
      if (pairs.length < 2) _fail(t('r.pairs'));
      return {'question': _str(e['question'] ?? e['prompt']), 'pairs': _take(pairs, 6)};
    case 'order':
      final items = _list(e['items'] ?? e['answer'] ?? e['steps']);
      if (items.length < 2) _fail(t('r.items'));
      return {'question': _str(e['question'] ?? e['prompt']), 'items': _take(items, 8)};
    case 'build':
      final a = e['answer'] ?? e['tokens'];
      final answer = a is List ? _list(a) : _str(a).split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (answer.length < 2) _fail(t('r.tokens'));
      return {
        'question': _str(e['question'] ?? e['prompt']),
        'answer': _take(answer, 14),
        'distractors': _take(_list(e['distractors'] ?? e['wrong']), 5),
        'accept': _take(_list(e['accept']), 6),
      };
    case 'categorize':
      final raw = e['categories'] is List
          ? e['categories'] as List
          : e['categories'] is Map
              ? (e['categories'] as Map).entries.map((x) => {'name': x.key, 'items': x.value}).toList()
              : const [];
      final seen = <String>{};
      final categories = <Map<String, dynamic>>[];
      for (final c in raw.take(12)) {
        if (c is! Map) continue;
        final name = _str(c['name'] ?? c['title']);
        final items = <String>[];
        for (final it in _list(c['items'])) {
          if (!seen.add(norm(it))) continue;
          items.add(it);
        }
        if (name.isNotEmpty && items.isNotEmpty) categories.add({'name': name, 'items': items});
      }
      if (categories.length < 2) _fail(t('r.categories'));
      if (seen.length < 3) _fail(t('r.fewItems'));
      return {'question': _str(e['question'] ?? e['prompt']), 'categories': _take(categories, 4)};
    case 'flashcard':
      final front = _str(e['front'] ?? e['question'] ?? e['term']);
      final back = _str(e['back'] ?? e['answer'] ?? e['definition']);
      if (front.isEmpty) _fail(t('r.front'));
      if (back.isEmpty) _fail(t('r.back'));
      return {'front': front, 'back': back};
  }
  _fail(t('r.unknownType', {'type': type}));
}

/* ---------- Grafik ----------
   Yapay zekâ çizim yapmaz: veriyi ya da fonksiyonu verir, grafiği uygulama çizer.
   Çıktı tek biçimdedir: etiketli grafiklerde "labels" + "series[].values", sayısal eksenli grafiklerde
   "series[].points", fonksiyon grafiğinde "fn" + "from" + "to". */

const chartTypes = ['bar', 'line', 'scatter', 'pie', 'function'];
const _chartAliases = {
  'column': 'bar', 'columns': 'bar', 'bars': 'bar', 'histogram': 'bar',
  'lines': 'line', 'area': 'line',
  'points': 'scatter', 'dots': 'scatter',
  'donut': 'pie', 'doughnut': 'pie',
  'fn': 'function', 'plot': 'function', 'curve': 'function', 'graph': 'function',
};

List<num>? _nums(dynamic v) {
  if (v is! List || v.isEmpty) return null;
  final out = <num>[];
  for (final x in v) {
    final n = _num(x);
    if (n == null) return null;
    out.add(n);
  }
  return out;
}

Map<String, dynamic> _chart(dynamic raw) {
  if (raw is! Map) _fail(t('r.chart'));
  final fnSource = raw['fn'] ?? raw['function'] ?? raw['functions'];
  var type = _str(raw['type'] ?? raw['kind']).toLowerCase();
  type = _chartAliases[type] ?? type;
  if (type.isEmpty) type = fnSource != null ? 'function' : (raw['points'] != null ? 'line' : 'bar');
  if (!chartTypes.contains(type)) _fail(t('r.chartType', {'type': type}));
  String axis(String key) {
    final v = raw[key] ?? raw['${key}Label'];
    return _str(v is Map ? (v['label'] ?? v['title']) : v, 40);
  }

  final out = <String, dynamic>{'type': type, 'title': _str(raw['title'], 80), 'x': axis('x'), 'y': axis('y')};

  if (type == 'function') {
    final fns = _take(_list(fnSource), 3);
    if (fns.isEmpty) _fail(t('r.chartFn'));
    final range = _nums(raw['range'] ?? raw['domain']);
    final from = _num(raw['from'] ?? raw['min']) ?? (range?.length == 2 ? range![0] : -5);
    final to = _num(raw['to'] ?? raw['max']) ?? (range?.length == 2 ? range![1] : 5);
    if (to <= from) _fail(t('r.chartRange'));
    for (final f in fns) {
      final fn = parseFunction(f);
      // Aralığın en azından bir bölümünde tanımlı olmalı
      final defined = fn == null ? 0 : [for (var i = 0; i <= 40; i++) fn(from + (to - from) * i / 40)].where((v) => v.isFinite).length;
      if (defined < 5) _fail(t('r.chartFnBad', {'fn': f}));
    }
    return {...out, 'fn': fns, 'from': from, 'to': to};
  }

  // Seriler: tek seri doğrudan ("values" / "points" / "data"), birden çoğu "series" içinde verilir
  var rawSeries = raw['series'];
  if (rawSeries is Map) rawSeries = [for (final e in rawSeries.entries) {'name': e.key, 'values': e.value}];
  final sources = <(String, dynamic)>[
    if (rawSeries is List)
      for (final s in rawSeries)
        if (s is Map) (_str(s['name'] ?? s['label'], 30), s['points'] ?? s['values'] ?? s['data'])
        else ('', s)
    else
      ('', raw['points'] ?? raw['values'] ?? raw['data']),
  ];
  var labels = _list(raw['labels'] ?? raw['categories']);
  final valued = <Map<String, dynamic>>[], pointed = <Map<String, dynamic>>[];
  // En çok 3 seri: renkleri ancak bu kadarı güvenle ayırt edilir
  for (final (name, body) in _take(sources, 3)) {
    if (body is! List || body.isEmpty) _fail(t('r.chartData'));
    final pairs = body.every((p) => p is List && p.length == 2);
    if (pairs && body.every((p) => _num(p[0]) != null && _num(p[1]) != null && p[0] is! String)) {
      // [[x, y], …]: sayısal eksen
      final points = [for (final p in _take(body, 60)) [_num(p[0])!, _num(p[1])!]]..sort((a, b) => a[0].compareTo(b[0]));
      pointed.add({'name': name, 'points': points});
      continue;
    }
    List<num>? values;
    if (pairs) {
      // [["Pzt", 5], …]: etiket ve değer
      values = _nums([for (final p in body) p[1]]);
      if (labels.isEmpty) labels = [for (final p in body) _str(p[0], 24)];
    } else if (body.every((p) => p is Map)) {
      values = _nums([for (final p in body) p['value'] ?? p['y']]);
      if (labels.isEmpty) labels = [for (final p in body) _str(p['label'] ?? p['name'] ?? p['x'], 24)];
    } else {
      values = _nums(body);
    }
    if (values == null) _fail(t('r.chartData'));
    valued.add({'name': name, 'values': values});
  }
  if (valued.isEmpty && pointed.isEmpty) _fail(t('r.chartData'));

  if (type == 'scatter' || (type == 'line' && valued.isEmpty)) {
    if (pointed.isEmpty || valued.isNotEmpty) _fail(t('r.chartPoints'));
    if (pointed.any((s) => (s['points'] as List).length < 2)) _fail(t('r.chartData'));
    return {...out, 'series': pointed};
  }
  // Sütun ve pasta grafiği etiketlidir; sayısal noktalar verildiyse x değerleri etiket olur
  if (valued.isEmpty) {
    final first = pointed.first['points'] as List;
    if (labels.isEmpty) labels = [for (final p in first) formatNumber(p[0] as num, locale: 'en')];
    for (final s in pointed) {
      valued.add({'name': s['name'], 'values': [for (final p in s['points'] as List) p[1]]});
    }
  }
  final count = (valued.first['values'] as List).length;
  if (labels.isEmpty) labels = [for (var i = 1; i <= count; i++) '$i'];
  final most = type == 'pie' ? 6 : 12;
  if (count < 2 || count > most) _fail(t('r.chartCount', {'max': most}));
  if (labels.length != count || valued.any((s) => (s['values'] as List).length != count)) _fail(t('r.chartLength'));
  if (type == 'pie') {
    final values = valued.first['values'] as List<num>;
    if (values.any((v) => v < 0) || values.every((v) => v == 0)) _fail(t('r.chartPie'));
    return {...out, 'labels': labels, 'series': [valued.first]};
  }
  return {...out, 'labels': labels, 'series': valued};
}

Exercise _exercise(dynamic e) {
  if (e is! Map) _fail(t('r.notObject'));
  final rawType = _str(e['type'] ?? e['kind']).toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  final type = exerciseTypes.contains(rawType) ? rawType : _aliases[rawType];
  if (type == null) _fail(t('r.unknownType', {'type': rawType.isEmpty ? '?' : rawType}));
  final out = <String, dynamic>{'type': type, ..._normalize(type, e)};
  // Her adımda bulunabilen ekler: sesli okunacak metin ve grafik
  final say = _str(e['say'] ?? e['speak'] ?? e['audio'], 300);
  if (say.isNotEmpty) {
    out['say'] = say;
    final lang = _str(e['sayLang'] ?? e['audioLang'], 12);
    if (lang.isNotEmpty) out['sayLang'] = lang;
  }
  if (e['chart'] != null) out['chart'] = _chart(e['chart']);
  // Kullanıcının düzelttirdiği adım, yerine geçtiği adımın izini taşır (Exercise.fixedFrom)
  final fixedFrom = _str(e['fixedFrom'], 16);
  if (fixedFrom.isNotEmpty) out['fixedFrom'] = fixedFrom;
  if (type == 'info' || type == 'flashcard') return Exercise(out);
  // Her soruda bulunabilen alanlar: açıklama, ipucu, adım adım çözüm, ortak metin
  for (final (key, names, max) in const [
    ('explanation', ['explanation', 'why', 'feedback'], _maxText),
    ('hint', ['hint', 'tip', 'clue'], 600),
    ('solution', ['solution', 'worked_solution', 'working'], _maxBody),
    ('context', ['context', 'passage'], _maxBody),
  ]) {
    final value = _str(_first(e, names), max);
    if (value.isNotEmpty) out[key] = value;
  }
  return Exercise(out);
}

String _uniqueId(String wanted, Set<String> taken) {
  final id = freeId(wanted, taken.contains);
  taken.add(id);
  return id;
}

final _plainId = RegExp(r'^-*[a-z0-9][a-z0-9-]{0,63}$');

/// Dosyada yazan kimlik: zaten kimlik biçimindeyse (küçük harf, rakam, tire) olduğu gibi kalır, değilse sadeleştirilir.
/// Kayıtlı kurs her açılışta buradan geçer; kimlik burada değişirse ilerleme, tekrar takvimi ve işaretler sahipsiz kalır.
/// Bu yüzden uygulamanın bir kez verdiği kimlik (eski sürümlerin sonu tireli ya da sınırı aşan kimlikleri dâhil) değişmez.
String _id(String raw) => _plainId.hasMatch(raw) ? raw : slug(raw);

Course? _course(Map raw, ParseReport report) {
  final title = _label(raw['title'] ?? raw['name']);
  var rawUnits = raw['units'];
  if (rawUnits is! List && raw['lessons'] is List) {
    rawUnits = [
      {'title': title.isEmpty ? t('err.unit', {'n': 1}) : title, 'lessons': raw['lessons']}
    ];
  }
  if (title.isEmpty) report.errors.add(t('err.noTitle'));
  if (rawUnits is! List || rawUnits.isEmpty) report.errors.add(t('err.unitsMissing'));
  if (report.errors.isNotEmpty) return null;

  final unitIds = <String>{};
  final units = <Unit>[];
  final rawList = _take(rawUnits as List, _maxUnits);
  for (var ui = 0; ui < rawList.length; ui++) {
    final u = rawList[ui];
    final where = t('err.unit', {'n': ui + 1});
    if (u is! Map || u['lessons'] is! List) {
      report.warnings.add(t('err.noLessonsList', {'where': where}));
      continue;
    }
    final unitTitle = _label(u['title'] ?? u['name']).isEmpty ? where : _label(u['title'] ?? u['name']);
    final rawUnitId = _str(u['id']);
    final unitId = _uniqueId([_id(rawUnitId), slug(unitTitle), 'u${ui + 1}'].firstWhere((s) => s.isNotEmpty), unitIds);
    final lessonIds = <String>{};
    final lessons = <Lesson>[];
    final rawLessons = _take(u['lessons'] as List, _maxLessons);
    for (var li = 0; li < rawLessons.length; li++) {
      final l = rawLessons[li];
      final lwhere = '$where › ${t('err.lesson', {'n': li + 1})}';
      final rawEx = l is Map ? (l['exercises'] ?? l['steps'] ?? l['items']) : null;
      if (rawEx is! List) {
        report.warnings.add(t('err.noExercisesList', {'where': lwhere}));
        continue;
      }
      final exercises = <Exercise>[];
      final list = _take(rawEx, _maxExercises);
      for (var ei = 0; ei < list.length; ei++) {
        try {
          exercises.add(_exercise(list[ei]));
        } on _Skip catch (err) {
          final e = list[ei];
          final kind = e is Map && e['type'] != null ? ' (${e['type']})' : '';
          report.warnings.add(t('err.stepSkipped', {'where': lwhere, 'n': ei + 1, 'type': kind, 'reason': err.message}));
        }
      }
      if (exercises.isEmpty) {
        report.warnings.add(t('err.lessonEmpty', {'where': lwhere}));
        continue;
      }
      // Derse yazılmış ortak grafik bozuksa yalnızca grafik atılır; sorular kalır
      Map<String, dynamic>? lessonChart;
      if ((l as Map)['chart'] != null) {
        try {
          lessonChart = _chart(l['chart']);
        } on _Skip catch (err) {
          report.warnings.add(t('err.chartSkipped', {'where': lwhere, 'reason': err.message}));
        }
      }
      // Dışa aktarılmış kurslarda ders kimliği zaten "ünite/ders" biçimindedir; öneki iki kez ekleme
      var ownId = _str(l['id']);
      if (rawUnitId.isNotEmpty && ownId.startsWith('$rawUnitId/')) ownId = ownId.substring(rawUnitId.length + 1);
      lessons.add(Lesson(
        id: '$unitId/${_uniqueId(_id(ownId).isEmpty ? 'l${li + 1}' : _id(ownId), lessonIds)}',
        title: _label(l['title'] ?? l['name']).isEmpty ? t('err.lesson', {'n': li + 1}) : _label(l['title'] ?? l['name']),
        context: _str(l['context'] ?? l['passage'], _maxBody),
        chart: lessonChart,
        exercises: exercises,
      ));
    }
    if (lessons.isEmpty) {
      report.warnings.add(t('err.unitEmpty', {'where': where}));
      continue;
    }
    units.add(Unit(id: unitId, title: unitTitle, description: _label(u['description'], _maxBlurb), emoji: _str(u['emoji'], 8), lessons: lessons));
  }
  if (units.isEmpty) {
    report.errors.add(t('err.nothingPlayable'));
    return null;
  }
  final lang = _label(raw['language'] ?? raw['lang'], 12);
  return Course(
    id: [_id(_str(raw['id'])), slug(title), 'kurs'].firstWhere((s) => s.isNotEmpty),
    title: title,
    description: _label(raw['description'], _maxBlurb),
    emoji: _str(raw['emoji'], 8),
    language: lang.isEmpty ? 'tr' : lang,
    author: _label(raw['author'], 80),
    group: _label(raw['group'] ?? raw['pack'], 80),
    sayLang: _label(raw['sayLang'] ?? raw['audioLanguage'], 12),
    outline: [for (final x in _list(raw['outline'])) if (_label(x).isNotEmpty) _label(x)],
    units: units,
  );
}

/* ---------- Metinden JSON çıkarma ----------
   Yapay zekâ çıktısı çoğu zaman kusurludur: uzun çıktı yarıda kesilir, metin içindeki çift tırnak kaçırılmaz,
   satır sonu olduğu gibi yazılır. Tarayıcı bunları onarır; onaramadığında kursu ünite ünite kurtarır. */

/// Metinde bulunan bir { ... } bloğu; yaygın yazım kusurları onarılmıştır.
class _Chunk {
  _Chunk(this.start, this.text, this.open);
  final int start; // kaynak metindeki yeri
  final String text; // kesilmişse kesildiği yere kadar
  final List<String> open; // kapanmamış parantezlerin kapanışları, dıştan içe

  bool get cut => open.isNotEmpty;

  /// Tam bir değerin (nesne ya da dizi) hemen ardından mı kesilmiş: yalnızca kapanış parantezleri eksik olabilir.
  bool get clean => RegExp(r'[}\]][\s,]*$').hasMatch(text);
  String get closed => text.replaceFirst(RegExp(r'[\s,]+$'), '') + open.reversed.join();
}

final _hex4 = RegExp(r'^[0-9a-fA-F]{4}$');

/// Metnin içindeki çift tırnak metni bitiriyor mu? Geçerli JSON'da kapanış tırnağını hep `,` `:` `}` `]` izler;
/// izlemiyorsa yapay zekâ tırnağı kaçırmayı unutmuştur ("O "evet" dedi" gibi) ve tırnak metnin parçasıdır.
/// Virgülden sonra yeni bir tırnak geliyorsa ("sol", "güneş" demektir) o tırnağın gerçekten sıradaki anahtarı
/// ya da dizi öğesini açıp açmadığına bakılır.
bool _closesString(String s, int i, {required bool inObject}) {
  final n = s.length;
  int skip(int k) {
    while (k < n && ' \t\r\n'.contains(s[k])) {
      k++;
    }
    return k;
  }

  var j = skip(i + 1);
  if (j >= n || ':}]'.contains(s[j])) return true;
  if (s[j] != ',') return false;
  j = skip(j + 1);
  if (j >= n) return true;
  if (s[j] != '"') return '{[}]-0123456789'.contains(s[j]) || s.startsWith('true', j) || s.startsWith('false', j) || s.startsWith('null', j);
  var k = j + 1;
  while (k < n && s[k] != '"') {
    k += s[k] == r'\' ? 2 : 1;
  }
  final after = skip(k + 1);
  if (after >= n) return true;
  return inObject ? s[after] == ':' : ',]'.contains(s[after]);
}

/// Üst düzey { ... } bloklarını bulur (kod çiti, ön/arka açıklama, art arda yapıştırılmış parçalar).
/// Metinlerdeki kaçışsız tırnağı, satır sonunu ve "\sqrt" gibi geçersiz kaçışları onarır.
List<_Chunk> _scan(String src) {
  final chunks = <_Chunk>[];
  final out = StringBuffer();
  final open = <String>[];
  final n = src.length;
  var start = 0;
  for (var i = 0; i < n; i++) {
    final c = src[i];
    if (open.isEmpty) {
      if (c != '{') continue;
      start = i;
      out
        ..clear()
        ..write(c);
      open.add('}');
    } else if (c == '"') {
      out.write(c);
      for (i++; i < n; i++) {
        final ch = src[i];
        if (ch == r'\') {
          if (++i >= n) break;
          final valid = r'"\/bfnrt'.contains(src[i]) || (src[i] == 'u' && i + 5 <= n && _hex4.hasMatch(src.substring(i + 1, i + 5)));
          out
            ..write(valid ? r'\' : r'\\')
            ..write(src[i]);
        } else if (ch == '"') {
          if (_closesString(src, i, inObject: open.last == '}')) break;
          out.write(r'\"');
        } else if (ch == '\n') {
          out.write(r'\n');
        } else if (ch == '\t') {
          out.write(r'\t');
        } else if (ch.codeUnitAt(0) >= 0x20) {
          out.write(ch);
        }
      }
      out.write('"');
    } else if (c == '{' || c == '[') {
      open.add(c == '{' ? '}' : ']');
      out.write(c);
    } else if (c == '}' || c == ']') {
      if (open.last != c) continue; // eşleşmeyen kapanış yok sayılır
      open.removeLast();
      out.write(c);
      if (open.isEmpty) chunks.add(_Chunk(start, out.toString(), const []));
    } else {
      out.write(c);
    }
  }
  if (open.isNotEmpty) chunks.add(_Chunk(start, out.toString(), List.of(open)));
  return chunks;
}

dynamic _decode(String text, void Function(String message) onError) {
  // Sondaki fazladan virgül de sık görülür: önce olduğu gibi, olmazsa virgülleri ayıklayıp dene
  for (final t in [text, text.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m[1]!)]) {
    try {
      return jsonDecode(t);
    } on FormatException catch (e) {
      onError(e.message);
    }
  }
  return null;
}

class _Found {
  final courses = <Map>[]; // "units" ya da "lessons" içeren nesneler
  bool other = false; // JSON okundu ama kurs değil
  bool cut = false; // yarıda kesilmiş, hiçbir ünitesi kurtarılamayan parça
  String? error; // ilk JSON hatası
  final notes = <String>[], warnings = <String>[];
}

final _fence = RegExp(r'^[ \t]*```.*$', multiLine: true);
final _rootStart = RegExp(r'^(?=\{\s*"format"\s*:)', multiLine: true);
final _titleField = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"');

/// Bütün olarak okunamayan (yarıda kesilmiş ya da bozuk) kursun ünitelerini tek tek kurtarır.
Map? _rescue(_Chunk root, _Found f) {
  final parts = _scan(root.text.substring(1));
  if (parts.isEmpty) return null;
  // Kurs bilgileri (başlık, kimlik, plan) ilk üniteden önce durur
  final head = _decode('${root.text.substring(0, parts.first.start + 1)}]}', (_) {});
  final units = <dynamic>[];
  var broken = 0;
  for (final part in parts) {
    // Kesilen ünitenin yalnızca kendi kapanış parantezi eksikse içeriği tamdır; daha erken kesildiyse yarımdır
    final whole = !part.cut || (part.clean && part.open.length == 1);
    String? error;
    final data = whole ? _decode(part.cut ? part.closed : part.text, (m) => error ??= m) : null;
    if (data is Map && data['lessons'] is List) {
      units.add(data);
    } else if (part.cut) {
      final title = _titleField.firstMatch(part.text)?[1];
      f.notes.add(title == null ? t('err.cutUnitUnnamed') : t('err.cutUnit', {'title': title}));
    } else if (data == null && part.text.contains('"lessons"')) {
      broken++;
      f.warnings.add(t('err.unitBroken', {'n': units.length + broken, 'error': error ?? '?'}));
    }
  }
  if (units.isEmpty) return null;
  // Son ünite tam ama ardından virgül gelmiş: sıradaki ünite başlamadan kesilmiş
  if (!parts.last.cut && RegExp(r',\s*$').hasMatch(root.text)) f.notes.add(t('err.cutAfter', {'title': _label(units.last['title'])}));
  return {if (head is Map) ...head, 'units': units};
}

_Found _collect(String src) {
  final f = _Found();
  // Kod çiti satırı ve yeni bir kursun ilk satırı kesin sınırdır: yarıda kesilmiş bir parça sonrakileri bozmasın
  for (final block in src.split(_fence).expand((b) => b.split(_rootStart))) {
    for (final chunk in _scan(block)) {
      final data = chunk.cut ? null : _decode(chunk.text, (m) => f.error ??= m);
      if (data is Map && (data['units'] is List || data['lessons'] is List)) {
        f.courses.add(data);
      } else if (data is Map) {
        f.other = true;
      } else if (data == null) {
        final rescued = _rescue(chunk, f);
        if (rescued != null) {
          f.courses.add(rescued);
        } else if (chunk.cut && RegExp('"(?:format|units|lessons|exercises)"').hasMatch(chunk.text)) {
          f.cut = true;
        }
      }
    }
  }
  return f;
}

/// LLM çıktısını (ya da dışa aktarılmış bir kurs dosyasını) kursa çevirir.
ParseReport parseCourse(String text) {
  final report = ParseReport();
  if (text.length > maxImportChars) {
    report.errors.add(t('err.tooBig', {'mb': maxImportChars ~/ 1000000}));
    return report;
  }
  final src = text.replaceFirst('﻿', '').trim();
  if (src.isEmpty) {
    report.errors.add(t('err.empty'));
    return report;
  }
  var found = _collect(src);
  if (found.courses.isEmpty && src.contains(RegExp('[“”]'))) {
    // Tırnaklar "akıllı tırnağa" çevrilmiş olabilir
    final again = _collect(src.replaceAll(RegExp('[“”]'), '"'));
    if (again.courses.isNotEmpty) found = again;
  }
  final courses = found.courses;
  if (courses.isEmpty) {
    if (found.cut) {
      report.errors.add(t('err.truncated'));
    } else if (found.error != null) {
      report.errors.add(t('err.invalidJson', {'error': found.error}));
    } else if (found.other) {
      report.errors.add(t('err.noUnits'));
    } else {
      report.errors.add(t('err.noJson'));
    }
    return report;
  }
  report.notes.addAll(found.notes);
  if (found.cut && found.notes.isEmpty) report.notes.add(t('err.partialIgnored'));
  report.warnings.addAll(found.warnings);
  // Birden fazla parça yapıştırıldıysa ünitelerini tek kursta topla
  final units = <dynamic>[];
  for (final c in courses) {
    if (c['units'] is List) {
      units.addAll(c['units'] as List);
    } else {
      units.add({'title': c['title'], 'lessons': c['lessons']});
    }
  }
  // Kurs bilgileri: başlığı olan ilk parçadan (ilk parçanın başı bozuksa sonrakinden) alınır
  final meta = courses.firstWhere((c) => _str(c['title'] ?? c['name']).isNotEmpty, orElse: () => courses.first);
  report.course = _course({...meta, 'units': units}, report);
  return report;
}

/* ---------- Kurs paketi ----------
   Bir kurumun ya da öğretmenin birlikte dağıttığı kurslar tek dosyada durur; alan kişi hepsini bir kerede ekler. */

const packFormat = 'bilge-pack';
const _maxPackCourses = 300;

class Pack {
  Pack({required this.title, this.description = '', this.author = '', required this.courses});
  final String title, description, author;
  final List<Course> courses;

  int get lessonCount => courses.fold(0, (n, c) => n + c.lessonCount);

  Map<String, dynamic> toJson() => {
        'format': packFormat, 'version': 1, 'title': title, 'description': description, 'author': author,
        'courses': [for (final c in courses) c.toJson()],
      };
}

class PackReport {
  Pack? pack;
  final List<String> errors = [];
  final List<String> warnings = []; // alınamayan kurslar ve nedenleri
}

/// Kayıtlı (zaten doğrulanmış) bir kursu metne çevirmeden yeniden kurar; açılışta çok kurs varken hızlıdır.
Course? courseFromMap(Map raw) => _course(raw, ParseReport());

/// Metin bir kurs paketiyse çözer. Paket değilse null döner; o zaman [parseCourse] denenmelidir.
PackReport? parsePack(String text) {
  final src = text.replaceFirst('﻿', '').trim();
  if (!src.contains('"courses"')) return null;
  if (text.length > maxImportChars) return PackReport()..errors.add(t('err.tooBig', {'mb': maxImportChars ~/ 1000000}));
  Map? root;
  var cut = false;
  for (final block in src.split(_fence)) {
    for (final chunk in _scan(block)) {
      if (root != null || !chunk.text.contains('"courses"')) continue;
      final data = chunk.cut ? null : _decode(chunk.text, (_) {});
      if (data is Map && data['courses'] is List && data['units'] == null) {
        root = data;
      } else if (data == null) {
        // Bütün olarak okunamayan (yarıda kesilmiş) paket: içindeki tam kursları kurtar
        final parts = _scan(chunk.text.substring(1));
        final whole = [
          for (final part in parts)
            if (!part.cut)
              if (_decode(part.text, (_) {}) case final Map m when m['units'] is List) m,
        ];
        if (whole.isEmpty) continue;
        final head = _decode('${chunk.text.substring(0, parts.first.start + 1)}]}', (_) {});
        root = {if (head is Map) ...head, 'courses': whole};
        cut = true;
      }
    }
  }
  if (root == null) return null;
  final report = PackReport();
  final title = _label(root['title'] ?? root['name'], 80);
  final author = _label(root['author'], 80);
  final name = title.isNotEmpty ? title : (author.isNotEmpty ? author : t('pack.defaultName'));
  final courses = <Course>[];
  final ids = <String>{};
  for (final (i, raw) in _take(root['courses'] as List, _maxPackCourses).indexed) {
    final inner = ParseReport();
    final course = raw is Map ? _course(raw, inner) : null;
    if (course == null) {
      final label = raw is Map && _label(raw['title']).isNotEmpty ? _label(raw['title']) : '${i + 1}';
      report.warnings.add(t('pack.courseSkipped', {'title': label, 'reason': inner.errors.firstOrNull ?? t('r.notObject')}));
      continue;
    }
    // Paketteki kurslar paketin adı altında gruplanır; kimlik çakışırsa sonraki kurs ayrı kimlik alır
    courses.add(course.copyWith(id: _uniqueId(course.id, ids), group: course.group.isEmpty ? name : null));
  }
  if (cut) report.warnings.add(t('pack.cut'));
  if (courses.isEmpty) {
    report.errors.add(t('pack.empty'));
    return report;
  }
  report.pack = Pack(title: name, description: _label(root['description'], _maxBlurb), author: author, courses: courses);
  return report;
}

/* ---------- Düzeltme ----------
   Kullanıcının hatalı işaretlediği adımlar yapay zekâya düzelttirilir; çıktı aynı yapıda geri gelir:
   { "format": "bilge-fix", "course": "<kurs kimliği>", "fixes": [ { "at": "<ders>#<sıra>", "exercise": { … } } ] } */

const fixFormat = 'bilge-fix';

class FixReport {
  String courseId = '';
  final fixes = <({String at, Exercise exercise})>[];
  final List<String> errors = [];
  final List<String> warnings = []; // kalıba uymadığı için alınmayan düzeltmeler
}

/// Metin bir düzeltme çıktısıysa çözer. Değilse null döner; o zaman [parsePack] ve [parseCourse] denenmelidir.
FixReport? parseFixes(String text) {
  final src = text.replaceFirst('\uFEFF', '').trim();
  if (!src.contains('"fixes"')) return null;
  final report = FixReport();
  if (text.length > maxImportChars) return report..errors.add(t('err.tooBig', {'mb': maxImportChars ~/ 1000000}));
  Map? root;
  var named = false; // biçim adı geçiyor ama okunamadı (yarıda kesilmiş çıktı)
  for (final block in src.split(_fence)) {
    for (final chunk in _scan(block)) {
      if (!chunk.text.contains('"fixes"')) continue;
      final data = chunk.cut ? null : _decode(chunk.text, (_) {});
      if (data is Map && data['fixes'] is List && data['units'] == null) {
        // Sonuncusu geçerlidir: sohbetin tamamı kopyalandıysa önce kalıptaki (düzeltilmemiş) adımlar, sonra cevap gelir
        root = data;
      } else if (data == null && chunk.text.contains(fixFormat)) {
        named = true;
      }
    }
  }
  if (root == null) return named ? (report..errors.add(t('fix.unreadable'))) : null;
  report.courseId = _id(_str(root['course'] ?? root['id'], 200));
  for (final (i, f) in _take(root['fixes'] as List, 200).indexed) {
    if (f is! Map) continue;
    try {
      // Düzeltme çıktısı adımın geçmişini belirleyemez: o izi uygulama yazar
      report.fixes.add((at: _str(f['at'] ?? f['key'], 200), exercise: _exercise(f['exercise'] ?? f['step'])..data.remove('fixedFrom')));
    } on _Skip catch (e) {
      report.warnings.add(t('fix.skipped', {'n': i + 1, 'reason': e.message}));
    }
  }
  if (report.fixes.isEmpty) report.errors.add(report.warnings.firstOrNull ?? t('fix.unreadable'));
  return report;
}

/* ---------- Birleştirme (parça parça üretim) ---------- */

Unit _reId(Unit u, String id) => u.copyWith(id: id, lessons: [for (final l in u.lessons) l.copyWith(id: id + l.id.substring(u.id.length))]);

/// Aynı kimlik + aynı başlık: ünite yeniden üretilmiştir, yerine geçer. Aksi hâlde sona eklenir.
({Course course, int added, int updated}) mergeCourses(Course existing, Course incoming) {
  final units = [...existing.units];
  final taken = {for (final u in units) u.id};
  var added = 0, updated = 0;
  for (final u in incoming.units) {
    final at = units.indexWhere((x) => x.id == u.id);
    if (at >= 0 && norm(units[at].title) == norm(u.title)) {
      units[at] = u;
      updated++;
    } else if (at >= 0) {
      units.add(_reId(u, _uniqueId(slug(u.title).isEmpty ? u.id : slug(u.title), taken)));
      added++;
    } else {
      taken.add(u.id);
      units.add(u);
      added++;
    }
  }
  return (
    course: existing.copyWith(
      description: existing.description.isEmpty ? incoming.description : null,
      emoji: existing.emoji.isEmpty ? incoming.emoji : null,
      author: existing.author.isEmpty ? incoming.author : null,
      sayLang: existing.sayLang.isEmpty ? incoming.sayLang : null,
      outline: incoming.outline.length > existing.outline.length ? incoming.outline : null,
      units: units,
    ),
    added: added,
    updated: updated,
  );
}
