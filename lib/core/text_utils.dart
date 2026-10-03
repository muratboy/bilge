/// Metin yardımcıları: cevap karşılaştırma, kimlik üretme, tarih.
library;

import 'dart:math' as math;

const _folds = {
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u',
  'á': 'a', 'à': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'ñ': 'n',
};

/// Türkçede I→ı ve İ→i olur; diğer dillerde standart küçültme yeterli.
String lower(String s, {String locale = 'tr'}) {
  if (locale.startsWith('tr')) s = s.replaceAll('I', 'ı').replaceAll('İ', 'i');
  return s.toLowerCase();
}

/// Karşılaştırma için sadeleştirir: boşluklar, tırnaklar, büyük/küçük harf, sondaki nokta.
String norm(String s, {String locale = 'tr'}) {
  var out = s
      .replaceAll(RegExp('[“”„«»]'), '"')
      .replaceAll(RegExp('[‘’`´]'), "'")
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  out = lower(out, locale: locale);
  // Sondaki noktalama yalnızca dizede alfasayısal karakter varsa kırpılır; tek başına '?' veya '.' gibi noktalama cevapları korunur.
  if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(out)) {
    var end = out.length;
    while (end > 0 && '.!?…'.contains(out[end - 1])) {
      end--;
    }
    return out.substring(0, end).trim();
  }
  return out;
}

/// Aksan ve ı/i farkını yok sayan gevşek biçim.
String fold(String s, {String locale = 'tr'}) => norm(s, locale: locale).split('').map((c) => _folds[c] ?? c).join();

int levenshtein(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i];
    for (var j = 1; j <= b.length; j++) {
      cur.add([prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce(math.min));
    }
    prev = cur;
  }
  return prev[b.length];
}

enum MatchKind { exact, accent, typo }

class AnswerMatch {
  const AnswerMatch(this.kind, this.match);
  final MatchKind kind;
  final String match;
}

/// Yazılan cevabı kabul edilen cevaplarla karşılaştırır; uymuyorsa null döner.
/// Aksansız yazım ve (uzun, sayısız cevaplarda) tek harflik hata uyarıyla kabul edilir.
AnswerMatch? compareAnswer(String input, List<String> answers, {String locale = 'tr'}) {
  final n = norm(input, locale: locale);
  if (n.isEmpty) return null;
  for (final a in answers) {
    if (norm(a, locale: locale) == n) return AnswerMatch(MatchKind.exact, a);
  }
  final f = fold(input, locale: locale);
  for (final a in answers) {
    if (fold(a, locale: locale) == f) return AnswerMatch(MatchKind.accent, a);
  }
  for (final a in answers) {
    final fa = fold(a, locale: locale);
    if (fa.length < 5 || fa.contains(RegExp(r'\d'))) continue; // kısa ya da sayısal cevapta hata payı yok
    final maxDist = fa.length >= 12 ? 2 : 1;
    if ((f.length - fa.length).abs() > maxDist) continue;
    if (levenshtein(f, fa) <= maxDist) return AnswerMatch(MatchKind.typo, a);
  }
  return null;
}

/* ---------- Sayısal cevap ---------- */

const _commaLocales = {'tr', 'az', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'ru', 'uk', 'pl', 'cs', 'sv', 'da', 'nb', 'fi', 'el', 'id'};

List<double> _scalar(String s) {
  final m = RegExp(r'^([+-]?)(\d[\d.,]*|[.,]\d+)(e[+-]?\d+)?$', caseSensitive: false).firstMatch(s);
  if (m == null) return const [];
  final body = m[2]!;
  final dots = '.'.allMatches(body).length, commas = ','.allMatches(body).length;
  final forms = <String>[];
  if (dots > 0 && commas > 0) {
    // "1.234,5" ya da "1,234.5": sonda duran ondalık ayırıcıdır
    final decimal = body.lastIndexOf('.') > body.lastIndexOf(',') ? '.' : ',';
    forms.add(body.replaceAll(decimal == '.' ? ',' : '.', '').replaceAll(decimal, '.'));
  } else if (dots + commas > 1) {
    if (RegExp(r'^\d{1,3}(?:[.,]\d{3})+$').hasMatch(body)) forms.add(body.replaceAll(RegExp('[.,]'), ''));
  } else if (dots + commas == 1) {
    forms.add(body.replaceAll(',', '.'));
    if (RegExp(r'^[1-9]\d{0,2}[.,]\d{3}$').hasMatch(body)) forms.add(body.replaceAll(RegExp('[.,]'), ''));
  } else {
    forms.add(body);
  }
  return [
    for (final f in forms)
      if (double.tryParse('${m[1]}$f${m[3] ?? ''}') case final v? when v.isFinite) v,
  ];
}

/// Yazılan sayının olası değerleri; sayı değilse boş liste. Virgül de nokta da ondalık ayırıcı sayılır.
/// "1.500" gibi iki türlü okunabilen yazımlarda (bir buçuk ya da bin beş yüz) iki değer de döner.
/// Sonuna [unit] yazılmışsa yok sayılır; "3/4" gibi kesirler de okunur.
List<double> parseNumbers(String input, {String unit = ''}) {
  String clean(String x) => x.toLowerCase().replaceAll(RegExp('[−–]'), '-').replaceAll(RegExp("[\\s  '’_]"), '');
  var s = clean(input);
  final u = clean(unit);
  if (u.isNotEmpty && s.endsWith(u)) s = s.substring(0, s.length - u.length);
  final parts = s.split('/');
  if (parts.length == 2) {
    final a = _scalar(parts[0]), b = _scalar(parts[1]);
    return a.isEmpty || b.isEmpty || b.first == 0 ? const [] : [a.first / b.first];
  }
  return _scalar(s);
}

/// Sayısal cevabı karşılaştırır. Sayı yazılmadıysa null; [ok] tolerans içinde, [exact] tam değerle aynı demektir.
({bool ok, bool exact})? compareNumber(String input, num answer, {num tolerance = 0, String unit = ''}) {
  final values = parseNumbers(input, unit: unit);
  if (values.isEmpty) return null;
  final eps = 1e-9 * math.max(1, answer.abs());
  bool within(num t) => values.any((v) => (v - answer).abs() <= t + eps);
  return (ok: within(tolerance.abs()), exact: within(0));
}

/// Sayıyı kursun diline göre yazar: Türkçede "9,81", İngilizcede "9.81"; büyük sayılar üçerli gruplanır.
/// [groupFrom]: kaç basamaktan itibaren gruplanacağı (grafik eksenlerinde 4: "5 000" ile "10 000" aynı yazılsın).
String formatNumber(num v, {String locale = 'tr', int groupFrom = 5}) {
  var s = v == v.roundToDouble() && v.abs() < 1e15 ? v.round().toString() : v.toString();
  if (s.contains('e')) return s;
  final at = s.indexOf('.');
  var whole = at < 0 ? s : s.substring(0, at);
  if (whole.replaceFirst('-', '').length >= groupFrom) whole = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ' ');
  final comma = _commaLocales.contains(locale.split(RegExp('[-_]')).first.toLowerCase());
  return at < 0 ? whole : '$whole${comma ? ',' : '.'}${s.substring(at + 1)}';
}

/// Kimliklerin (kurs, ünite, ders) en büyük uzunluğu.
const maxIdLength = 48;

/// Metinden kimlik üretir: küçük harf, rakam ve tek tireler. Sonuç yeniden verildiğinde değişmez:
/// önce uzunluk kesilir, sonra uçtaki tireler atılır (tersi yapılırsa kesilen yer tireye denk gelebilir).
String slug(String s) {
  final folded = lower(s).split('').map((c) => _folds[c] ?? c).join();
  var out = folded.replaceAll(RegExp('[^a-z0-9]+'), '-');
  if (out.startsWith('-')) out = out.substring(1);
  if (out.length > maxIdLength) out = out.substring(0, maxIdLength);
  return out.endsWith('-') ? out.substring(0, out.length - 1) : out;
}

/// [base] alınmışsa sonuna "-2", "-3"… ekleyerek boş bir kimlik bulur. Ek, uzunluk sınırının içinde kalır
/// (gerekirse [base] kısalır): sınırı aşan bir kimlik sonradan kesildiğinde ekini yitirir ve özgün kimlikle aynı olurdu.
String freeId(String base, bool Function(String id) taken) {
  if (!taken(base)) return base;
  for (var n = 2;; n++) {
    final suffix = '-$n';
    var head = base.length > maxIdLength - suffix.length ? base.substring(0, maxIdLength - suffix.length) : base;
    while (head.endsWith('-')) {
      head = head.substring(0, head.length - 1);
    }
    if (!taken('$head$suffix')) return '$head$suffix';
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
String dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String addDays(String key, int n) {
  final p = key.split('-').map(int.parse).toList();
  return dayKey(DateTime(p[0], p[1], p[2] + n));
}

String formatDuration(int seconds) => '${seconds ~/ 60}:${_two(seconds % 60)}';

/// "04.10.2026 16:20": yedeklerin tarihini göstermek için.
String formatStamp(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Sıralama sorularında karışık hâl doğru sırayla aynı çıkmasın.
List<T> shuffledDifferent<T>(List<T> items, math.Random random, [bool Function(T, T)? same]) {
  final eq = same ?? (a, b) => a == b;
  for (var n = 0; n < 12; n++) {
    final out = [...items]..shuffle(random);
    if (items.length < 2) return out;
    for (var i = 0; i < items.length; i++) {
      if (!eq(out[i], items[i])) return out;
    }
  }
  return items.reversed.toList();
}
