/// Uygulamanın kalıcı durumu: kurslar, ilerleme, XP, seri, rozetler, ayarlar.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../mascot/cast.dart';
import '../mascot/mascot_art.dart';
import 'schema.dart';
import 'text_utils.dart';

/* ---------- Saklama ---------- */

/// Kayıt iki parçadır: sık değişen küçük "durum" (ayarlar, profil, ilerleme) ve yalnızca kurs eklenip
/// değişince yazılan "kurslar". Böylece kurs sayısı arttıkça her ders sonunda megabaytlarca veri yazılmaz.
abstract class Storage {
  Future<String?> read();
  Future<void> write(String data);
  Future<String?> readCourses();
  Future<void> writeCourses(String data);

  /// Cihazda saklanan yedekler: her biri adıyla anılan ayrı bir dosyadır.
  Future<List<String>> listBackups();
  Future<String?> readBackup(String name);
  Future<void> writeBackup(String name, String data);
  Future<void> deleteBackup(String name);

  /// Bozuk kayıt dosyasını diskte .corrupt uzantısıyla saklar.
  Future<void> preserveCorrupt(String name);
}

/// Cihazda iki JSON dosyası: bilge.json (durum) ve bilge-kurslar.json (kurslar).
class FileStorage implements Storage {
  FileStorage([this._baseDir]);
  final Future<Directory> Function()? _baseDir;

  Future<Directory> _dir() async => _baseDir != null ? await _baseDir() : await getApplicationSupportDirectory();

  Future<File> _file(String name) async => File('${(await _dir()).path}/$name');

  final Map<String, Future<void>> _writeQueues = {};

  Future<String?> _read(String name) async {
    final f = await _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  Future<void> _write(String name, String data) {
    final prev = _writeQueues[name] ?? Future.value();
    final current = () async {
      try {
        await prev;
      } catch (_) {}
      final f = await _file(name);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path); // yarım yazılmış dosya kalmasın
    }();
    _writeQueues[name] = current;
    return current;
  }

  @override
  Future<void> preserveCorrupt(String name) async {
    final f = await _file(name);
    if (await f.exists()) {
      final corrupt = await _file('$name.corrupt');
      try {
        await f.rename(corrupt.path);
      } catch (_) {
        try {
          await f.copy(corrupt.path);
          await f.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Future<String?> read() => _read('bilge.json');
  @override
  Future<void> write(String data) => _write('bilge.json', data);
  @override
  Future<String?> readCourses() => _read('bilge-kurslar.json');
  @override
  Future<void> writeCourses(String data) => _write('bilge-kurslar.json', data);

  Future<Directory> _backups() async {
    final dir = Directory('${(await _dir()).path}/yedekler');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<List<String>> listBackups() async => [
        await for (final f in (await _backups()).list())
          if (f is File) f.uri.pathSegments.last,
      ];
  @override
  Future<String?> readBackup(String name) => _read('yedekler/$name');
  @override
  Future<void> writeBackup(String name, String data) async {
    await _backups();
    await _write('yedekler/$name', data);
  }

  @override
  Future<void> deleteBackup(String name) async {
    final f = await _file('yedekler/$name');
    if (await f.exists()) await f.delete();
  }
}

class MemoryStorage implements Storage {
  MemoryStorage([this.data, this.courseData]);
  String? data, courseData;
  int courseWrites = 0; // testler için: kurslar kaç kez yazıldı
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String d) async => data = d;
  @override
  Future<String?> readCourses() async => courseData;
  @override
  Future<void> writeCourses(String d) async {
    courseData = d;
    courseWrites++;
  }

  final backups = <String, String>{};
  final corruptFiles = <String, String>{};
  @override
  Future<List<String>> listBackups() async => backups.keys.toList();
  @override
  Future<String?> readBackup(String name) async => backups[name];
  @override
  Future<void> writeBackup(String name, String data) async => backups[name] = data;
  @override
  Future<void> deleteBackup(String name) async => backups.remove(name);
  @override
  Future<void> preserveCorrupt(String name) async {
    if (name == 'bilge.json' && data != null) {
      corruptFiles['bilge.json'] = data!;
      data = null;
    } else if (name == 'bilge-kurslar.json' && courseData != null) {
      corruptFiles['bilge-kurslar.json'] = courseData!;
      courseData = null;
    }
  }
}

/// Cihazdaki bir yedek. Türü, zamanı ve içeriğin parmak izi dosya adında durur:
/// "oto-20261004-162005-1a2b3c4d.json" ya da "elle-…".
class BackupInfo {
  const BackupInfo({required this.name, required this.manual, required this.time, required this.signature});
  final String name;
  final bool manual; // kullanıcı kendisi mi aldı
  final DateTime time;
  final String signature;

  static final _pattern = RegExp(r'^(oto|elle)-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-([0-9a-f]+)\.json$');

  static BackupInfo? parse(String name) {
    final m = _pattern.firstMatch(name);
    if (m == null) return null;
    final n = [for (var i = 2; i <= 7; i++) int.parse(m[i]!)];
    return BackupInfo(name: name, manual: m[1] == 'elle', time: DateTime(n[0], n[1], n[2], n[3], n[4], n[5]), signature: m[8]!);
  }

  static String nameFor({required bool manual, required DateTime time, required String signature}) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${manual ? 'elle' : 'oto'}-${time.year}${two(time.month)}${two(time.day)}-${two(time.hour)}${two(time.minute)}${two(time.second)}-$signature.json';
  }
}

/* ---------- Kayıt parçaları ---------- */

class Settings {
  bool sound = true, hearts = true, freeMode = false, reminder = false;
  String theme = 'auto'; // auto | light | dark
  String lang = 'auto'; // auto | tr | en
  int dailyGoal = 30, reminderHour = 20;
  String aiProvider = 'gemini', aiKey = '', aiModel = '';

  Map<String, dynamic> toJson({bool includeSecrets = true}) => {
        'sound': sound, 'hearts': hearts, 'freeMode': freeMode, 'theme': theme, 'lang': lang, 'dailyGoal': dailyGoal,
        if (reminder) 'reminder': reminder,
        if (reminderHour != 20) 'reminderHour': reminderHour,
        if (aiProvider != 'gemini') 'aiProvider': aiProvider,
        if (includeSecrets && aiKey.isNotEmpty) 'aiKey': aiKey,
        if (aiModel.isNotEmpty) 'aiModel': aiModel,
      };
  Settings();
  Settings.fromJson(Map j) {
    sound = j['sound'] ?? true;
    hearts = j['hearts'] ?? true;
    freeMode = j['freeMode'] ?? false;
    theme = j['theme'] ?? 'auto';
    lang = j['lang'] ?? 'auto';
    dailyGoal = (j['dailyGoal'] is int ? j['dailyGoal'] as int : 30).clamp(5, 500);
    reminder = j['reminder'] == true;
    reminderHour = (j['reminderHour'] is int ? j['reminderHour'] as int : 20).clamp(0, 23);
    aiProvider = j['aiProvider'] is String ? j['aiProvider'] as String : 'gemini';
    aiKey = j['aiKey'] is String ? j['aiKey'] as String : '';
    aiModel = j['aiModel'] is String ? j['aiModel'] as String : '';
  }
}

class Profile {
  int xp = 0, totalXp = 0, streak = 0, bestStreak = 0, lessonsDone = 0, perfect = 0, maxCombo = 0, answered = 0, correct = 0, freezes = 0;
  int importedCourses = 0, sectionsAdded = 0, spacedSessions = 0, nightLessons = 0, earlyLessons = 0, breakReturns = 0;
  Set<String> stepTypes = {};
  String? lastActive;
  bool created = false;
  Map<String, int> xpByDay = {};
  Map<String, String> badges = {};

  Map<String, dynamic> toJson() => {
        'xp': xp, if (totalXp > 0) 'totalXp': totalXp, 'streak': streak, 'bestStreak': bestStreak, 'lessonsDone': lessonsDone, 'perfect': perfect, 'maxCombo': maxCombo,
        'answered': answered, 'correct': correct, 'lastActive': lastActive, 'created': created, 'xpByDay': xpByDay, 'badges': badges,
        if (freezes > 0) 'freezes': freezes,
        if (importedCourses > 0) 'importedCourses': importedCourses,
        if (sectionsAdded > 0) 'sectionsAdded': sectionsAdded,
        if (spacedSessions > 0) 'spacedSessions': spacedSessions,
        if (nightLessons > 0) 'nightLessons': nightLessons,
        if (earlyLessons > 0) 'earlyLessons': earlyLessons,
        if (breakReturns > 0) 'breakReturns': breakReturns,
        if (stepTypes.isNotEmpty) 'stepTypes': stepTypes.toList(),
      };
  Profile();
  Profile.fromJson(Map j) {
    xp = j['xp'] ?? 0;
    totalXp = j['totalXp'] ?? xp;
    streak = j['streak'] ?? 0;
    bestStreak = j['bestStreak'] ?? 0;
    lessonsDone = j['lessonsDone'] ?? 0;
    perfect = j['perfect'] ?? 0;
    maxCombo = j['maxCombo'] ?? 0;
    answered = j['answered'] ?? 0;
    correct = j['correct'] ?? 0;
    freezes = j['freezes'] is int ? (j['freezes'] as int).clamp(0, 2) : 0;
    importedCourses = j['importedCourses'] is int ? j['importedCourses'] as int : (j['imported'] == true ? 1 : 0);
    sectionsAdded = j['sectionsAdded'] is int ? j['sectionsAdded'] as int : 0;
    spacedSessions = j['spacedSessions'] is int ? j['spacedSessions'] as int : 0;
    nightLessons = j['nightLessons'] is int ? j['nightLessons'] as int : (j['nightOwl'] == true ? 1 : 0);
    earlyLessons = j['earlyLessons'] is int ? j['earlyLessons'] as int : (j['earlyBird'] == true ? 1 : 0);
    breakReturns = j['breakReturns'] is int ? j['breakReturns'] as int : (j['returnedAfterBreak'] == true ? 1 : 0);
    stepTypes = (j['stepTypes'] as List? ?? const []).map((e) => e.toString()).toSet();
    lastActive = j['lastActive'];
    created = j['created'] ?? false;
    xpByDay = Map<String, int>.from(j['xpByDay'] ?? {});
    badges = Map<String, String>.from(j['badges'] ?? {});
  }
}

class CourseProgress {
  /// düğüm kimliği → { stars, plays }
  Map<String, ({int stars, int plays})> lessons = {};

  /// "ders#sıra" → kaç kez yanlış yapıldı
  Map<String, int> mistakes = {};

  /// Aralıklı tekrar: "ders#sıra" → kutu (0: yanlış yapıldı … 5: iyice yerleşti) ve yeniden sorulacağı gün.
  Map<String, ({int box, String due})> memory = {};

  /// Kullanıcının hatalı bulduğu adımlar ("ders#sıra"): düzeltilene ya da işaret kaldırılana kadar sorulmaz.
  /// Değer, işaretlenen adımın izidir ([Exercise.fingerprint]): aynı sıraya başka bir adım gelirse işaret geçersizdir.
  /// Boş iz, izsiz kaydedilmiş eski bir işarettir; kurs yüklenince o sıradaki adıma bağlanır.
  Map<String, String> flagged = {};

  /// Kursta en son ne zaman çalışıldı (epoch ms; hiç çalışılmadıysa 0): kurs listesi buna göre sıralanır.
  int last = 0;

  Map<String, dynamic> toJson() => {
        'lessons': {for (final e in lessons.entries) e.key: {'stars': e.value.stars, 'plays': e.value.plays}},
        'mistakes': mistakes,
        'memory': {for (final e in memory.entries) e.key: [e.value.box, e.value.due]},
        if (flagged.isNotEmpty) 'flagged': flagged,
        if (last > 0) 'last': last,
      };
  CourseProgress();
  CourseProgress.fromJson(Map j) {
    last = j['last'] ?? 0;
    lessons = {for (final e in (j['lessons'] as Map? ?? {}).entries) e.key as String: (stars: e.value['stars'] as int, plays: e.value['plays'] as int)};
    mistakes = Map<String, int>.from(j['mistakes'] ?? {});
    memory = {for (final e in (j['memory'] as Map? ?? {}).entries) e.key as String: (box: e.value[0] as int, due: e.value[1] as String)};
    // 0.10.0 işaretleri izsiz, liste olarak yazıyordu
    final marks = j['flagged'];
    flagged = marks is List ? {for (final k in marks) k as String: ''} : Map<String, String>.from(marks ?? const {});
    // Eski kayıtlarda takvim yok: yanlışlar hemen tekrar edilecekler olarak başlar
    for (final k in mistakes.keys) {
      memory.putIfAbsent(k, () => (box: 0, due: ''));
    }
  }
}

/// Kutuya göre bir sonraki tekrara kaç gün kaldığı: yanlış yapılan aynı gün, yeni öğrenilen ertesi gün,
/// her doğru hatırlamada aralık açılır.
const reviewDays = [0, 1, 3, 7, 16, 35];

/* ---------- Kurs yolu ---------- */

enum NodeKind { lesson, review, practice, exam, daily, flashcards }

enum NodeStatus { done, current, open, locked }

class PathNode {
  const PathNode({required this.kind, required this.id, required this.title, this.unitIndex = 0, this.lessonIndex = 0, this.unit, this.lesson});
  final NodeKind kind;
  final String id, title;
  final int unitIndex, lessonIndex;
  final Unit? unit;
  final Lesson? lesson;

  /// Ekranda görünen ad (tekrar ve pratik düğümlerinin adı dile göre değişir).
  String get label => switch (kind) {
        NodeKind.review => t('learn.review'),
        NodeKind.practice => t('learn.practice'),
        NodeKind.exam => t('learn.exam'),
        NodeKind.daily => t('learn.daily'),
        NodeKind.flashcards => t('learn.cards'),
        NodeKind.lesson => title,
      };
}

/// Yarım kalan bir ders oturumunun kurtarma kaydı.
class SavedSession {
  const SavedSession({
    required this.courseId,
    required this.nodeId,
    required this.nodeKind,
    required this.nodeTitle,
    this.unitIndex = 0,
    this.lessonIndex = 0,
    required this.queueKeys,
    required this.done,
    required this.total,
    required this.questions,
    required this.hearts,
    required this.combo,
    required this.maxCombo,
    required this.firstTry,
    this.wrongKeys = const {},
    this.rightKeys = const {},
    this.cardWrong = const {},
    this.cardRight = const {},
    this.rightStepTypes = const {},
  });
  final String courseId, nodeId, nodeTitle;
  final NodeKind nodeKind;
  final int unitIndex, lessonIndex, done, total, questions, hearts, combo, maxCombo, firstTry;
  final List<String> queueKeys;
  final Set<String> wrongKeys, rightKeys, cardWrong, cardRight, rightStepTypes;

  Map<String, dynamic> toJson() => {
        'courseId': courseId, 'nodeId': nodeId, 'nodeKind': nodeKind.name, 'nodeTitle': nodeTitle,
        'unitIndex': unitIndex, 'lessonIndex': lessonIndex, 'queueKeys': queueKeys,
        'done': done, 'total': total, 'questions': questions, 'hearts': hearts,
        'combo': combo, 'maxCombo': maxCombo, 'firstTry': firstTry,
        if (wrongKeys.isNotEmpty) 'wrongKeys': wrongKeys.toList(),
        if (rightKeys.isNotEmpty) 'rightKeys': rightKeys.toList(),
        if (cardWrong.isNotEmpty) 'cardWrong': cardWrong.toList(),
        if (cardRight.isNotEmpty) 'cardRight': cardRight.toList(),
        if (rightStepTypes.isNotEmpty) 'rightStepTypes': rightStepTypes.toList(),
      };

  static SavedSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = NodeKind.values.where((k) => k.name == raw['nodeKind']).firstOrNull;
    final keys = raw['queueKeys'];
    if (raw['courseId'] is! String || raw['nodeId'] is! String || kind == null || keys is! List) return null;
    final queueList = keys.whereType<String>().toList();
    if (queueList.isEmpty) return null;
    return SavedSession(
      courseId: raw['courseId'] as String,
      nodeId: raw['nodeId'] as String,
      nodeKind: kind,
      nodeTitle: raw['nodeTitle'] is String ? raw['nodeTitle'] as String : '',
      unitIndex: raw['unitIndex'] is int ? raw['unitIndex'] as int : 0,
      lessonIndex: raw['lessonIndex'] is int ? raw['lessonIndex'] as int : 0,
      queueKeys: queueList,
      done: raw['done'] is int ? raw['done'] as int : 0,
      total: raw['total'] is int ? raw['total'] as int : queueList.length,
      questions: raw['questions'] is int ? raw['questions'] as int : 0,
      hearts: raw['hearts'] is int ? raw['hearts'] as int : 5,
      combo: raw['combo'] is int ? raw['combo'] as int : 0,
      maxCombo: raw['maxCombo'] is int ? raw['maxCombo'] as int : 0,
      firstTry: raw['firstTry'] is int ? raw['firstTry'] as int : 0,
      wrongKeys: (raw['wrongKeys'] as List? ?? const []).whereType<String>().toSet(),
      rightKeys: (raw['rightKeys'] as List? ?? const []).whereType<String>().toSet(),
      cardWrong: (raw['cardWrong'] as List? ?? const []).whereType<String>().toSet(),
      cardRight: (raw['cardRight'] as List? ?? const []).whereType<String>().toSet(),
      rightStepTypes: (raw['rightStepTypes'] as List? ?? const []).whereType<String>().toSet(),
    );
  }
}

class LessonItem {
  const LessonItem(this.exercise, this.key, {this.context = '', this.chart, this.from});
  LessonItem.of(Lesson lesson, int index, {Course? from})
      : this(lesson.exercises[index], '${lesson.id}#$index',
            context: lesson.contextOf(lesson.exercises[index]), chart: lesson.chartOf(lesson.exercises[index]), from: from);
  final Exercise exercise;
  final String key; // "ders kimliği#sıra": yanlışları ve tekrar takvimini izlemek için
  final String context; // sorunun üstünde gösterilecek ortak metin
  final Map<String, dynamic>? chart; // sorunun üstünde gösterilecek grafik
  final Course? from; // karışık oturumlarda (günün tekrarı) öğenin geldiği kurs; yoksa oturumun kursu

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LessonItem &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          from?.id == other.from?.id;

  @override
  int get hashCode => Object.hash(key, from?.id);
}

/// Bir oturumda tek bir kursun öğelerine verilen cevaplar.
class Marks {
  final right = <String>{}, wrong = <String>{}, cardRight = <String>{}, cardWrong = <String>{};
}

class LessonResult {
  const LessonResult({
    required this.courseId, required this.node, required this.stars, required this.xp, required this.perfect,
    required this.questions, required this.firstTry, required this.maxCombo, required this.wrongKeys, required this.rightKeys,
    this.cardWrong = const {}, this.cardRight = const {}, this.mixed = const {},
    this.rightStepTypes = const {},
  });
  final String courseId;
  final PathNode node;
  final int stars, xp, questions, firstTry, maxCombo;
  final bool perfect;
  final Set<String> wrongKeys, rightKeys;
  final Set<String> rightStepTypes;

  /// Ezber kartları: "Tekrar sor" ve "Biliyordum" denenler (puanı etkilemez, tekrar takvimini etkiler).
  final Set<String> cardWrong, cardRight;

  /// Karışık oturumlarda başka kursların öğelerine verilen cevaplar: kurs kimliği → cevaplar.
  final Map<String, Marks> mixed;
}

class LessonOutcome {
  const LessonOutcome({
    required this.levelUp, required this.streakUp, required this.goalMet, required this.newBadges,
    this.courseDone = false, this.freezeUsed = false, this.freezeEarned = false,
  });
  final int levelUp, streakUp; // 0: değişmedi
  final bool goalMet;
  final bool courseDone; // kurs (kısım) bu dersle tamamlandı
  final bool freezeUsed, freezeEarned;
  final List<Badge> newBadges;
}

class Badge {
  const Badge(this.id, this.icon, this.test);
  final String id, icon;
  final bool Function(AppState) test;
  String get name => t('badge.$id.name');
  String get desc => t('badge.$id.desc');
}

const reviewSuffix = '/~tekrar';

const answerStepTypes = {
  'choice',
  'multi',
  'truefalse',
  'fill',
  'type',
  'number',
  'match',
  'order',
  'build',
  'categorize',
};

final badges = <Badge>[
  Badge('first', '🌱', (s) => s.profile.lessonsDone >= 1),
  Badge('creator', '🧪', (s) => s.profile.created),
  Badge('perfect', '💎', (s) => s.profile.perfect >= 1),
  Badge('combo10', '⚡', (s) => s.profile.maxCombo >= 10),
  Badge('goal', '🎯', (s) => s.todayXp >= s.settings.dailyGoal),
  Badge('s3', '🔥', (s) => s.profile.bestStreak >= 3),
  Badge('s7', '☄️', (s) => s.profile.bestStreak >= 7),
  Badge('s30', '🌋', (s) => s.profile.bestStreak >= 30),
  Badge('s100', '🪐', (s) => s.profile.bestStreak >= 100),
  Badge('l10', '📚', (s) => s.profile.lessonsDone >= 10),
  Badge('l50', '🏛️', (s) => s.profile.lessonsDone >= 50),
  Badge('l100', '📜', (s) => s.profile.lessonsDone >= 100),
  Badge('perfect5', '👑', (s) => s.profile.perfect >= 5),
  Badge('perfect10', '🎯', (s) => s.profile.perfect >= 10),
  Badge('unit', '🏆', (s) => s.progress.values.any((p) => p.lessons.keys.any((k) => k.endsWith(reviewSuffix)))),
  Badge('course', '🎓', (s) => s.courses.values.any((c) => s.percent(c) == 1)),
  Badge('course3', '🎖️', (s) => s.courses.values.where((c) => s.percent(c) == 1).length >= 3),
  Badge('xp100', '🥉', (s) => math.max(s.profile.xp, s.profile.totalXp) >= 100),
  Badge('xp500', '🥈', (s) => math.max(s.profile.xp, s.profile.totalXp) >= 500),
  Badge('xp1000', '💫', (s) => math.max(s.profile.xp, s.profile.totalXp) >= 1000),
  Badge('xp2000', '🥇', (s) => math.max(s.profile.xp, s.profile.totalXp) >= 2000),
  Badge('xp5000', '👑', (s) => math.max(s.profile.xp, s.profile.totalXp) >= 5000),
  Badge('import1', '📥', (s) => s.profile.importedCourses >= 1),
  Badge('section1', '🧩', (s) => s.profile.sectionsAdded >= 1 || s.courses.values.any((c) => c.group.isNotEmpty && s.courses.values.where((x) => x.group == c.group).length > 1)),
  Badge('spaced1', '🧠', (s) => s.profile.spacedSessions >= 1),
  Badge('spaced10', '🐘', (s) => s.profile.spacedSessions >= 10),
  Badge('night_owl', '🦉', (s) => s.profile.nightLessons >= 1),
  Badge('early_bird', '🌅', (s) => s.profile.earlyLessons >= 1),
  Badge('all_types', '🎪', (s) => answerStepTypes.every(s.profile.stepTypes.contains)),
  Badge('comeback', '🪃', (s) => s.profile.breakReturns >= 1),
  Badge('marathon', '🏃', (s) => s.profile.xpByDay.values.fold(0, math.max) >= 200),
  Badge('mastered50', '🏰', (s) => s.progress.values.fold(0, (sum, p) => sum + p.memory.values.where((m) => m.box == reviewDays.length - 1).length) >= 50),
];

/* ---------- Kurs listesi ---------- */

/// Kurs listesindeki bir satır: tek başına bir kurs ya da kısımlarıyla bir kurs grubu (paket).
class CourseEntry {
  const CourseEntry(this.group, this.courses);
  final String group; // kursların ait olduğu paket; boşsa kullanıcının kendi kursu
  final List<Course> courses; // grubun kısımları, sırasıyla
  bool get isGroup => courses.length > 1;
  String get key => isGroup ? 'group-$group' : 'course-${courses.first.id}';
  String get title => isGroup ? group : courses.first.title;
  int get lessonCount => courses.fold(0, (n, c) => n + c.lessonCount);
}

/// Kurslar ekranındaki raflar.
enum Shelf { active, fresh, finished, archived }

/// Kısmın, grubun adıyla başlayan adından ortak parçayı atar: "İnsan Vücudu 2: Enerji ve Denge" → "Enerji ve Denge".
String sectionTitle(Course c) {
  if (c.group.isEmpty || !c.title.startsWith(c.group)) return c.title;
  final rest = c.title.substring(c.group.length);
  if (!RegExp(r'^[\s\d:\-–—·.]').hasMatch(rest)) return c.title;
  final short = rest.replaceFirst(RegExp(r'^\s*\d*\s*[:\-–—·.]?\s*'), '');
  return short.isEmpty ? c.title : short;
}

/* ---------- Durum ---------- */

class AppState extends ChangeNotifier {
  AppState(this._storage, {DateTime Function()? clock, math.Random? random})
      : _clock = clock ?? DateTime.now,
        random = random ?? math.Random();

  final Storage _storage;
  final DateTime Function() _clock;
  final math.Random random;

  Settings settings = Settings();
  Profile profile = Profile();
  Map<String, Course> courses = {};
  List<String> order = [];
  Map<String, CourseProgress> progress = {};
  String? current;

  /// Arşive kaldırılan kurslar: listede görünmezler; ilerlemeleri ve tekrar soruları durur.
  Set<String> archived = {};

  /// Kullanıcının seçtiği yol arkadaşı; seçilene kadar null (karşılama ekranı gösterilir).
  MascotId? companion;

  /// Yarım bırakılmış ders oturumu; tamamlanınca ya da vazgeçilince silinir.
  SavedSession? session;

  static const maxFreezes = 2, freezeCost = 50;

  String get today => dayKey(_clock());
  Course? get currentCourse => courses[current];
  Character get buddy => characterOf(companion ?? MascotId.puhu);

  /// Kurslar son kayıttan beri değişti mi (değiştiyse kurs dosyası da yazılır).
  bool _coursesDirty = false;

  /// Cihazdaki yedekler, en yenisi başta.
  List<BackupInfo> backups = [];
  String? _autoCheckedOn; // otomatik yedeğe en son hangi gün bakıldı
  bool _backingUp = false;

  /// Açılışta bozuk veri tespit edildiyse kullanıcıya gösterilecek uyarı anahtarı.
  String? recoveryNotice;
  String? consumeRecoveryNotice() {
    final n = recoveryNotice;
    recoveryNotice = null;
    return n;
  }
  bool _corruptedAndNotRestored = false;

  Future<void> load() async {
    bool corrupt = false;
    try {
      final raw = await _storage.read();
      if (raw != null) {
        final state = jsonDecode(raw) as Map;
        final rawCourses = await _storage.readCourses();
        if (rawCourses != null) {
          _apply({...state, 'courses': (jsonDecode(rawCourses) as Map)['courses']});
        } else {
          // Eski kayıt: kurslar durumla aynı dosyadaydı; ilk kayıtta ayrılır
          _apply(state);
          _coursesDirty = courses.isNotEmpty;
        }
      }
    } catch (_) {
      corrupt = true;
    }
    try {
      backups = [for (final name in await _storage.listBackups()) ?BackupInfo.parse(name)]..sort((a, b) => b.time.compareTo(a.time));
    } catch (_) {
      backups = [];
    }
    if (corrupt) {
      try {
        await _storage.preserveCorrupt('bilge.json');
        await _storage.preserveCorrupt('bilge-kurslar.json');
      } catch (_) {}
      bool restored = false;
      for (final b in backups) {
        try {
          final text = await _storage.readBackup(b.name);
          if (text != null) {
            final data = _backupData(text);
            _apply(data);
            _coursesDirty = true;
            restored = true;
            break;
          }
        } catch (_) {}
      }
      if (restored) {
        recoveryNotice = 'backup.corruptRestored';
      } else {
        _corruptedAndNotRestored = true;
        recoveryNotice = 'backup.corruptUnrecovered';
      }
    }
    notifyListeners();
    // Günün ilk açılışı: dünden kalan durumun yedeği alınır (açılışı bekletmez)
    unawaited(autoBackup());
  }

  /// Önce her şey okunur, en sonda atanır: bozuk bir kayıt ya da yedek yarıda hata verirse eldeki durum olduğu gibi kalır.
  void _apply(Map j) {
    final settings = Settings.fromJson(j['settings'] ?? {});
    // Yedekten geri yüklerken cihazdaki kayıtlı gizli anahtarlar korunur (yedek dosyasına girmedikleri için)
    if (settings.aiKey.isEmpty && this.settings.aiKey.isNotEmpty) {
      settings.aiKey = this.settings.aiKey;
    }
    final profile = Profile.fromJson(j['profile'] ?? {});
    final courses = <String, Course>{};
    // Kimliği kayıttakinden farklı okunan kurslar (kayıttaki → şimdiki): ilerleme, sıra ve arşiv kursu izler
    final renamed = <String, String>{};
    for (final e in (j['courses'] as Map? ?? {}).entries) {
      var c = e.value is Map ? courseFromMap(e.value as Map) : null;
      if (c == null) continue;
      // İki kayıt aynı kimliğe düşerse biri öbürünün üzerine yazılmaz, yeni bir kimlik alır
      if (courses.containsKey(c.id)) c = c.copyWith(id: freeId(c.id, courses.containsKey));
      if (e.key is String && e.key != c.id) renamed[e.key as String] = c.id;
      courses[c.id] = c;
    }
    String now(String id) => renamed[id] ?? id;
    final order = List<String>.from(j['order'] ?? []).map(now).where(courses.containsKey).toSet().toList();
    // Sırada adı geçmeyen kurs listede görünmez olurdu: sona eklenir
    order.addAll(courses.keys.toSet().difference(order.toSet()));
    final progress = {for (final e in (j['progress'] as Map? ?? {}).entries) now(e.key as String): CourseProgress.fromJson(e.value)};
    final current = j['current'] is String ? now(j['current'] as String) : null;
    final archived = List<String>.from(j['archived'] ?? []).map(now).where(courses.containsKey).toSet();
    final companion = MascotId.values.where((m) => m.name == j['companion']).firstOrNull;
    final sess = SavedSession.fromJson(j['session']);

    this.settings = settings;
    this.profile = profile;
    this.courses = courses;
    this.order = order;
    this.progress = progress;
    this.current = current != null && courses.containsKey(current) ? current : order.firstOrNull;
    this.archived = archived;
    this.companion = companion;
    session = sess != null && courses.containsKey(now(sess.courseId))
        ? SavedSession(
            courseId: now(sess.courseId),
            nodeId: sess.nodeId,
            nodeKind: sess.nodeKind,
            nodeTitle: sess.nodeTitle,
            unitIndex: sess.unitIndex,
            lessonIndex: sess.lessonIndex,
            queueKeys: sess.queueKeys,
            done: sess.done,
            total: sess.total,
            questions: sess.questions,
            hearts: sess.hearts,
            combo: sess.combo,
            maxCombo: sess.maxCombo,
            firstTry: sess.firstTry,
            wrongKeys: sess.wrongKeys,
            rightKeys: sess.rightKeys,
            cardWrong: sess.cardWrong,
            cardRight: sess.cardRight,
            rightStepTypes: sess.rightStepTypes,
          )
        : null;
    courses.values.forEach(_settleFlags);
    awardBadges();
  }

  Map<String, dynamic> _stateJson({bool includeSecrets = true}) => {
        'v': 3,
        'settings': settings.toJson(includeSecrets: includeSecrets),
        'profile': profile.toJson(),
        'order': order,
        'progress': {for (final e in progress.entries) e.key: e.value.toJson()},
        'current': current,
        if (archived.isNotEmpty) 'archived': archived.toList(),
        'companion': companion?.name,
        if (session != null) 'session': session!.toJson(),
      };

  Map<String, dynamic> _coursesJson() => {for (final c in courses.values) c.id: c.toJson()};

  /// Her şey tek nesnede: yedek dosyasının biçimi. Yedeklerde ve dışa aktarmalarda gizli anahtarlar yer almaz.
  Map<String, dynamic> toJson({bool includeSecrets = false}) => {..._stateJson(includeSecrets: includeSecrets), 'courses': _coursesJson()};

  /// Değişikliği kaydeder ve ekranları yeniler. Kurslar yalnızca değiştiklerinde yazılır.
  void commit() {
    if (_corruptedAndNotRestored && courses.isEmpty && profile.xp == 0) {
      // Boş durum asla diskteki veriyi ezmesin
      notifyListeners();
      return;
    }
    _corruptedAndNotRestored = false;
    notifyListeners();
    // Gün döndüyse ya da henüz hiç yedek yoksa (ilk kurs eklendiğinde) otomatik yedeğe bakılır
    if (_autoCheckedOn != today || backups.isEmpty) unawaited(autoBackup());
    if (_coursesDirty) {
      _coursesDirty = false;
      unawaited(_storage.writeCourses(jsonEncode({'courses': _coursesJson()})).catchError((_) {}));
    }
    unawaited(_storage.write(jsonEncode(_stateJson(includeSecrets: true))).catchError((_) {}));
  }

  /* ----- Seviye, seri, günlük hedef ----- */

  /// n. seviyenin eşiği 20·(n−1)² XP: 20, 80, 180, 320…
  ({int level, int from, int to, double fraction}) get level {
    final cur = math.max(profile.xp, profile.totalXp);
    final lv = math.sqrt(cur / 20).floor() + 1;
    final from = 20 * (lv - 1) * (lv - 1), to = 20 * lv * lv;
    return (level: lv, from: from, to: to, fraction: (cur - from) / (to - from));
  }

  /// Dün ya da bugün ders yapıldıysa (veya dondurma 1 günlük boşluğu koruyorsa) seri sürüyor demektir.
  int get streak {
    if (profile.lastActive != null && today.compareTo(profile.lastActive!) < 0) return profile.streak;
    if (profile.lastActive == today || profile.lastActive == addDays(today, -1)) return profile.streak;
    if (profile.freezes > 0 && profile.lastActive == addDays(today, -2)) return profile.streak;
    return 0;
  }

  int get todayXp => profile.xpByDay[today] ?? 0;

  /// 50 XP karşılığında seri dondurma alır (en çok [maxFreezes] adet).
  bool buyFreeze() {
    if (profile.freezes >= maxFreezes || profile.xp < freezeCost) return false;
    profile.totalXp = math.max(profile.totalXp, profile.xp);
    profile.xp -= freezeCost;
    profile.freezes++;
    commit();
    return true;
  }

  /* ----- Kurslar ----- */

  CourseProgress progressOf(String courseId) => progress.putIfAbsent(courseId, CourseProgress.new);

  void putCourse(Course incoming, {bool own = false, bool imported = false}) {
    final course = _keepFixes(incoming);
    courses[course.id] = course;
    if (!order.contains(course.id)) order.add(course.id);
    progressOf(course.id);
    _settleFlags(course);
    current = course.id;
    if (own) profile.created = true;
    if (imported) profile.importedCourses++;
    if (incoming.group.isNotEmpty && courses.values.any((c) => c.group == incoming.group && c.id != incoming.id)) {
      profile.sectionsAdded++;
    }
    awardBadges();
    _coursesDirty = true;
    commit();
  }

  /// Bir paketteki bütün kursları tek seferde ekler. Aynı kimlikli kurs zaten varsa içeriği paketteki
  /// sürümle değişir, ilerleme korunur. Seçili kurs değişmez (hiç kurs yoksa paketin ilki seçilir).
  ({int added, int updated}) putPack(Pack pack, {bool imported = false}) {
    var added = 0, updated = 0;
    for (final incoming in pack.courses) {
      courses.containsKey(incoming.id) ? updated++ : added++;
      final c = _keepFixes(incoming);
      courses[c.id] = c;
      if (!order.contains(c.id)) order.add(c.id);
      progressOf(c.id);
      _settleFlags(c);
    }
    if (imported) profile.importedCourses += pack.courses.length;
    current ??= pack.courses.firstOrNull?.id;
    _coursesDirty = true;
    awardBadges();
    commit();
    return (added: added, updated: updated);
  }

  /// Var olan bir kursun içeriğini değiştirir; ilerleme ve seçili kurs aynı kalır.
  void replaceCourse(Course incoming) => _replace(_keepFixes(incoming));

  void _replace(Course course) {
    courses[course.id] = course;
    _settleFlags(course);
    _coursesDirty = true;
    commit();
  }

  /// Kullanıcının yazdığı adı tek satıra indirir ve kısaltır (dosyadan gelen başlıklarla aynı kural).
  static String _name(String text, int max) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > max ? one.substring(0, max).trim() : one;
  }

  /// Kursun adını değiştirir; kimliği, içeriği ve ilerlemesi aynı kalır.
  void renameCourse(String id, String title) {
    final c = courses[id];
    final name = _name(title, 120);
    if (c == null || name.isEmpty || name == c.title) return;
    courses[id] = c.copyWith(title: name);
    _coursesDirty = true;
    commit();
  }

  /// Kısımlı büyük kursun adını değiştirir. Kısım adları büyük kursun adıyla başlıyorsa ("İnsan Vücudu 2: Enerji")
  /// o önek de değişir. Bu adda başka bir büyük kurs varsa (ikisi birleşirdi) değiştirmez ve false döner.
  bool renameGroup(String group, String to) {
    final name = _name(to, 80);
    if (name.isEmpty || name == group) return true;
    if (groups.contains(name)) return false;
    // Başlık büyük kursun adıyla başlıyorsa o önek yenilenir; ama yalnızca ad bittiğinde ("İnsan Vücudu 2: …"):
    // "İnsanlık Tarihi" başlığı "İnsan" adlı bir büyük kursun öneki sayılmaz (sectionTitle ile aynı kural)
    String retitle(Course c) {
      if (!c.title.startsWith(group)) return c.title;
      final rest = c.title.substring(group.length);
      return rest.isEmpty || RegExp(r'^[\s\d:\-–—·.]').hasMatch(rest) ? _name(name + rest, 120) : c.title;
    }

    for (final c in sectionsOf(group)) {
      courses[c.id] = c.copyWith(title: retitle(c), group: name);
    }
    _coursesDirty = true;
    commit();
    return true;
  }

  /// Kurstan bir üniteyi siler: o ünitedeki ilerleme, tekrar kayıtları ve işaretler de gider.
  /// Kursun tek ünitesi silinmez (o zaman kursun kendisi silinir); silinemediyse false döner.
  bool removeUnit(String courseId, String unitId) {
    final course = courses[courseId];
    final at = course?.units.indexWhere((u) => u.id == unitId) ?? -1;
    if (course == null || at < 0 || course.units.length < 2) return false;
    final unit = course.units[at];
    bool mine(String key) => key == unit.id + reviewSuffix || key.startsWith('${unit.id}/');
    final prog = progressOf(courseId);
    prog.lessons.removeWhere((k, _) => mine(k));
    prog.mistakes.removeWhere((k, _) => mine(k));
    prog.memory.removeWhere((k, _) => mine(k));
    prog.flagged.removeWhere((k, _) => mine(k));
    final curSess = session;
    if (curSess != null && curSess.courseId == courseId) {
      if (curSess.unitIndex == at || curSess.nodeId.startsWith('${unit.id}/') || curSess.nodeId == unit.id + reviewSuffix) {
        session = null;
      } else if (curSess.unitIndex > at) {
        session = SavedSession(
          courseId: curSess.courseId,
          nodeId: curSess.nodeId,
          nodeKind: curSess.nodeKind,
          nodeTitle: curSess.nodeTitle,
          unitIndex: curSess.unitIndex - 1,
          lessonIndex: curSess.lessonIndex,
          queueKeys: curSess.queueKeys,
          done: curSess.done,
          total: curSess.total,
          questions: curSess.questions,
          hearts: curSess.hearts,
          combo: curSess.combo,
          maxCombo: curSess.maxCombo,
          firstTry: curSess.firstTry,
          wrongKeys: curSess.wrongKeys,
          rightKeys: curSess.rightKeys,
          cardWrong: curSess.cardWrong,
          cardRight: curSess.cardRight,
        );
      }
    }
    // Plan da kısalır: yoksa uygulama bir ünitenin daha beklendiğini sanar ve "devam" çıktısı ister
    final outline = [...course.outline];
    if (at < outline.length) outline.removeAt(at);
    _replace(course.copyWith(outline: outline, units: [...course.units]..removeAt(at)));
    return true;
  }

  void removeCourse(String id) => removeCourses([id]);

  void removeCourses(Iterable<String> ids) {
    for (final id in ids.toList()) {
      courses.remove(id);
      progress.remove(id);
      order.remove(id);
      archived.remove(id);
      if (session?.courseId == id) session = null;
    }
    if (!courses.containsKey(current)) current = order.firstOrNull;
    _coursesDirty = true;
    commit();
  }

  void selectCourse(String id) {
    current = id;
    commit();
  }

  /* ----- Kurs listesi: gruplar, raflar, arşiv ----- */

  /// Bir grubun (paketin) kısımları, sırasıyla.
  List<Course> sectionsOf(String group) => [
        for (final id in order)
          if (courses[id]!.group == group) courses[id]!,
      ];

  /// Kurs listesinin satırları: grubun kursları tek satırda toplanır, grupsuz kursların her biri ayrı satırdır.
  List<CourseEntry> get entries {
    final groups = <String, List<Course>>{};
    final out = <CourseEntry>[];
    for (final id in order) {
      final c = courses[id]!;
      if (c.group.isEmpty) {
        out.add(CourseEntry('', [c]));
      } else if (groups[c.group] case final list?) {
        list.add(c);
      } else {
        out.add(CourseEntry(c.group, groups[c.group] = [c]));
      }
    }
    return out;
  }

  int _doneNodes(Course course) {
    final done = progressOf(course.id).lessons;
    return nodes(course).where((n) => done.containsKey(n.id)).length;
  }

  /// Kurs bitti mi: bütün düğümleri tamam ve planlanıp henüz eklenmemiş ünitesi yok.
  bool isFinished(Course course) => percent(course) == 1 && course.outline.length <= course.units.length;

  double percentOf(CourseEntry entry) {
    final all = entry.courses.fold(0, (n, c) => n + nodes(c).length);
    return all == 0 ? 0 : entry.courses.fold(0, (n, c) => n + _doneNodes(c)) / all;
  }

  Shelf shelfOf(CourseEntry entry) {
    if (entry.courses.every((c) => archived.contains(c.id))) return Shelf.archived;
    if (entry.courses.every(isFinished)) return Shelf.finished;
    return entry.courses.any((c) => progressOf(c.id).lessons.isNotEmpty) ? Shelf.active : Shelf.fresh;
  }

  int lastStudied(CourseEntry entry) => entry.courses.fold(0, (n, c) => math.max(n, progressOf(c.id).last));

  /// Gruba dönüldüğünde açılacak kısım: seçili kurs bu gruptaysa ve bitmediyse o; değilse en son çalışılan
  /// bitmemiş kısım; hiçbirine başlanmadıysa ilk bitmemiş kısım.
  Course resumeOf(CourseEntry entry) {
    final open = entry.courses.where((c) => !isFinished(c)).toList();
    if (open.isEmpty) return entry.courses.first;
    final selected = open.where((c) => c.id == current).firstOrNull;
    if (selected != null) return selected;
    final recent = open.reduce((a, b) => progressOf(b.id).last > progressOf(a.id).last ? b : a);
    return progressOf(recent.id).last > 0 ? recent : open.first;
  }

  /// Aynı gruptaki sıradaki bitmemiş kısım (sona gelindiyse baştan aranır); yoksa null.
  Course? nextSection(Course course) {
    if (course.group.isEmpty) return null;
    final all = sectionsOf(course.group);
    final at = all.indexWhere((c) => c.id == course.id);
    return [...all.skip(at + 1), ...all.take(math.max(at, 0))].where((c) => !isFinished(c)).firstOrNull;
  }

  /// Ana ekrandaki kurs değiştirici için: seçili kurs ve en son çalışılan öbür kurslar (arşivdekiler hariç).
  List<Course> recentCourses(int count) {
    final others = [
      for (final c in courses.values)
        if (c.id != current && !archived.contains(c.id) && progressOf(c.id).last > 0) c,
    ]..sort((a, b) => progressOf(b.id).last.compareTo(progressOf(a.id).last));
    return [?currentCourse, ...others].take(count).toList();
  }

  /// Kısımlı büyük kursların (grupların) adları, listedeki sırayla.
  List<String> get groups => [
        for (final e in entries)
          if (e.group.isNotEmpty) e.group,
      ];

  /// Kursları bir gruba (kısımlı büyük kursa) kısım olarak ekler ya da gruptan çıkarır ([group] boşsa).
  /// Gruba giren kurs o grubun son kısmı olur; ilerleme korunur.
  void setGroup(Iterable<String> ids, String group) {
    final name = group.trim();
    for (final id in ids.toList()) {
      final c = courses[id];
      if (c == null || c.group == name) continue;
      courses[id] = c.copyWith(group: name);
      if (name.isNotEmpty) {
        order
          ..remove(id)
          ..add(id);
        profile.sectionsAdded++;
      }
    }
    awardBadges();
    _coursesDirty = true;
    commit();
  }

  /// Kursları arşive kaldırır ya da arşivden çıkarır. Seçili kurs arşive giderse en son çalışılan başka kurs seçilir.
  void setArchived(Iterable<String> ids, bool value) {
    value ? archived.addAll(ids.where(courses.containsKey)) : archived.removeAll(ids);
    if (value && session?.courseId != null && ids.contains(session!.courseId)) {
      session = null;
    }
    if (archived.contains(current)) {
      final rest = [for (final id in order) if (!archived.contains(id)) id]
        ..sort((a, b) => progressOf(b).last.compareTo(progressOf(a).last));
      current = rest.firstOrNull ?? current;
    }
    commit();
  }

  /* ----- Yol ----- */

  /// Ünitenin soruları; [course] verilirse kullanıcının o kursta hatalı işaretlediği sorular alınmaz.
  List<LessonItem> questionsOf(Unit unit, [Course? course]) => [
        for (final l in unit.lessons)
          for (final (i, ex) in l.exercises.indexed)
            if (ex.isQuestion && !(course != null && isFlagged(course, '${l.id}#$i'))) LessonItem.of(l, i),
      ];

  // Kurs nesneleri değişmez (içerik değişince yenisi konur): hesaplananlar kursun kendisine iliştirilir.
  // Böylece onlarca kursluk liste her çizimde bütün soruları yeniden dolaşmaz.
  final _nodes = Expando<List<PathNode>>();
  final _lessons = Expando<Map<String, Lesson>>();

  /// Yoldaki düğümler: dersler + (yeterince soru varsa) ünite sonu tekrarı.
  List<PathNode> nodes(Course course) => _nodes[course] ??= List.unmodifiable([
        for (final (ui, unit) in course.units.indexed) ...[
          for (final (li, lesson) in unit.lessons.indexed)
            PathNode(kind: NodeKind.lesson, id: lesson.id, title: lesson.title, unitIndex: ui, lessonIndex: li, unit: unit, lesson: lesson),
          if (unit.lessons.length >= 2 && questionsOf(unit).length >= 6)
            PathNode(kind: NodeKind.review, id: unit.id + reviewSuffix, title: '', unitIndex: ui, unit: unit),
        ],
      ]);

  Map<String, NodeStatus> statusOf(Course course) {
    final done = progressOf(course.id).lessons;
    final out = <String, NodeStatus>{};
    var currentSet = false;
    for (final n in nodes(course)) {
      if (done.containsKey(n.id)) {
        out[n.id] = NodeStatus.done;
      } else if (!currentSet) {
        out[n.id] = NodeStatus.current;
        currentSet = true;
      } else {
        out[n.id] = settings.freeMode ? NodeStatus.open : NodeStatus.locked;
      }
    }
    return out;
  }

  double percent(Course course) {
    final all = nodes(course);
    return all.isEmpty ? 0 : _doneNodes(course) / all.length;
  }

  /// Düğümde sorulacak adımlar. [course] verilirse kullanıcının o kursta hatalı işaretlediği sorular atlanır.
  List<LessonItem> itemsOf(PathNode node, [Course? course]) {
    if (node.kind == NodeKind.review) return (questionsOf(node.unit!, course)..shuffle(random)).take(12).toList();
    final lesson = node.lesson!;
    return [
      for (var i = 0; i < lesson.exercises.length; i++)
        if (!(course != null && isFlagged(course, '${lesson.id}#$i'))) LessonItem.of(lesson, i),
    ];
  }

  /// Yarım kalan oturumu kaydeder ya da temizler.
  void saveSession(SavedSession? s) {
    session = s;
    commit();
  }

  /// Yarım kalan oturumun kalan adımlarını kurstan geri kurar.
  List<LessonItem> resumeItems(Course course, SavedSession s) => [
        for (final k in s.queueKeys)
          if (_stepAt(course, k) case final at? when !isFlagged(course, k)) LessonItem.of(at.lesson, at.index),
      ];

  /// Yarım kalan oturumun düğümünü kurstan bulur ya da yeniden kurar.
  PathNode? nodeForSession(Course course, SavedSession s) {
    if (s.nodeKind == NodeKind.lesson || s.nodeKind == NodeKind.review) {
      return nodes(course).where((n) => n.id == s.nodeId).firstOrNull;
    }
    final ui = s.unitIndex.clamp(0, math.max(0, course.units.length - 1)).toInt();
    final unit = course.units.isNotEmpty ? course.units[ui] : null;
    return PathNode(kind: s.nodeKind, id: s.nodeId, title: s.nodeTitle, unitIndex: ui, lessonIndex: s.lessonIndex, unit: unit);
  }

  /* ----- Aralıklı tekrar ----- */

  /// Kursun tekrar edilebilen bütün öğeleri (sorular ve ezber kartları), anahtarlarıyla.
  Map<String, LessonItem> _reviewables(Course course) => {
        for (final u in course.units)
          for (final l in u.lessons)
            for (final (i, ex) in l.exercises.indexed)
              if (ex.isReviewable && !isFlagged(course, '${l.id}#$i')) '${l.id}#$i': LessonItem.of(l, i),
      };

  /// Tekrar anahtarının ("ders#sıra") kursta gösterdiği öğe; kurs değişmiş ve öğe artık yoksa null.
  LessonItem? _itemAt(Course course, String key) {
    final at = _stepAt(course, key);
    if (at == null || !at.lesson.exercises[at.index].isReviewable || isFlagged(course, key)) return null;
    return LessonItem.of(at.lesson, at.index, from: course);
  }

  Map<String, Lesson> _lessonsOf(Course course) => _lessons[course] ??= {
        for (final u in course.units)
          for (final l in u.lessons) l.id: l,
      };

  /// "ders#sıra" anahtarının kursta gösterdiği yer; kurs değişmiş ve orada adım kalmamışsa null.
  ({Lesson lesson, int index})? _stepAt(Course course, String key) {
    final cut = key.lastIndexOf('#');
    if (cut < 0) return null;
    final lesson = _lessonsOf(course)[key.substring(0, cut)];
    final i = int.tryParse(key.substring(cut + 1));
    return lesson == null || i == null || i < 0 || i >= lesson.exercises.length ? null : (lesson: lesson, index: i);
  }

  bool _isDue(Course course, MapEntry<String, ({int box, String due})> e) => e.value.due.compareTo(today) <= 0 && _itemAt(course, e.key) != null;

  /// Bugün tekrar edilmesi gereken öğe sayısı.
  int dueCount(Course course) => progressOf(course.id).memory.entries.where((e) => _isDue(course, e)).length;

  /// Bütün kurslarda (bitenler ve arşivdekiler dâhil) bugün tekrar edilmesi gereken öğe sayısı.
  int get dueTotal => courses.values.fold(0, (n, c) => n + dueCount(c));

  /// Günün tekrarında bir oturumda sorulan en çok öğe sayısı.
  static const dailySize = 15;

  /// Günün tekrarı: bütün kurslardan vadesi gelen öğeler; en zayıf ve en eski olan önce.
  List<LessonItem> dailyItems() {
    final due = [
      for (final c in courses.values)
        for (final e in progressOf(c.id).memory.entries)
          if (_isDue(c, e)) (course: c, key: e.key, box: e.value.box, due: e.value.due),
    ]..sort((a, b) => a.box != b.box ? a.box.compareTo(b.box) : a.due.compareTo(b.due));
    return [for (final d in due.take(dailySize)) _itemAt(d.course, d.key)!]..shuffle(random);
  }

  /// Tekrar oturumu: önce vadesi gelenler (en zayıf ve en eski olan önce); azsa tamamlanan derslerden
  /// rastgele sorularla tamamlanır.
  List<LessonItem> practiceItems(Course course) {
    final prog = progressOf(course.id);
    final byKey = _reviewables(course);
    // Yalnızca kurstan gerçekten kalkmış adımların kaydı silinsin (bayraklı sorular korunur)
    prog.mistakes.removeWhere((k, _) => _stepAt(course, k) == null);
    prog.memory.removeWhere((k, _) => _stepAt(course, k) == null);
    final due = prog.memory.entries.where((e) => e.value.due.compareTo(today) <= 0).toList()
      ..sort((a, b) => a.value.box != b.value.box ? a.value.box.compareTo(b.value.box) : a.value.due.compareTo(b.value.due));
    final picked = [for (final e in due) if (byKey.containsKey(e.key)) byKey[e.key]!].take(12).toList();
    if (picked.length < 8) {
      final studied = {for (final e in prog.lessons.entries) if (e.value.plays > 0) e.key};
      final rest = [
        for (final it in byKey.values)
          if (it.exercise.isQuestion && studied.contains(it.key.split('#').first) && !picked.contains(it)) it,
      ]..shuffle(random);
      picked.addAll(rest.take(8 - picked.length));
    }
    return picked..shuffle(random);
  }

  int mistakeCount(Course course) => progressOf(course.id).mistakes.length;

  /// Kursun bütün ezber kartları (hatalı işaretliler hariç).
  List<LessonItem> flashcardItems(Course course) => [
        for (final u in course.units)
          for (final l in u.lessons)
            for (final (i, ex) in l.exercises.indexed)
              if (ex.type == 'flashcard' && !isFlagged(course, '${l.id}#$i')) LessonItem.of(l, i),
      ];

  /// Kursta yanlış yapılmış ve henüz düzeltilmemiş sorular, yanlış yapılma sayısına göre azalan sırada.
  List<({LessonItem item, int count, Lesson lesson})> mistakeItems(Course course) {
    final mistakes = progressOf(course.id).mistakes;
    final out = <({LessonItem item, int count, Lesson lesson})>[
      for (final e in mistakes.entries)
        if (_stepAt(course, e.key) case final at? when !isFlagged(course, e.key))
          (item: LessonItem.of(at.lesson, at.index), count: e.value, lesson: at.lesson),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Kursun bilgi kartları (`info`), ünite ve ders sırasıyla.
  List<({Unit unit, Lesson lesson, Exercise exercise})> infoItems(Course course) => [
        for (final u in course.units)
          for (final l in u.lessons)
            for (final ex in l.exercises)
              if (ex.type == 'info') (unit: u, lesson: l, exercise: ex),
      ];

  /// Tekrar ya da pratik yapılabilecek bir şey var mı: vadesi gelen öğe ya da oynanmış bir ders.
  bool hasPractice(Course course) {
    if (dueCount(course) > 0) return true;
    // Oynanmış derslerde sorulabilecek en az bir soru olmalı: hepsi hatalı işaretliyse (ya da ders yalnızca
    // öğretici karttan oluşuyorsa) pratik boş başlar, hiçbir şey sorulmadan biterdi
    final played = progressOf(course.id).lessons;
    return _lessonsOf(course).values.any((l) =>
        (played[l.id]?.plays ?? 0) > 0 && l.exercises.indexed.any((e) => e.$2.isQuestion && !isFlagged(course, '${l.id}#${e.$1}')));
  }

  /// Cevaplara göre tekrar takvimini günceller.
  void _remember(CourseProgress prog, Iterable<String> right, Iterable<String> wrong) {
    for (final k in wrong) {
      prog.memory[k] = (box: 0, due: today);
    }
    for (final k in right) {
      final m = prog.memory[k];
      if (m == null) {
        prog.memory[k] = (box: 1, due: addDays(today, reviewDays[1]));
      } else if (m.due.compareTo(today) <= 0) {
        // Vadesi gelmiş öğe hatırlandı: bir kutu ilerler, aralık açılır
        final box = math.min(m.box + 1, reviewDays.length - 1);
        prog.memory[k] = (box: box, due: addDays(today, reviewDays[box]));
      }
      // Vadesi gelmeden doğru yapılan öğenin takvimi değişmez
    }
  }

  /// İçeriği yenilenen kursta (örnek kursun büyümesi, paket güncellemesi, yeniden üretilen ünite) kullanıcının
  /// düzelttirdiği adımları korur: yeni içerikte aynı sırada hâlâ düzeltmeden önceki adım duruyorsa düzeltilmiş hâli
  /// kalır. Yeni içerik o adımı değiştirmişse (iz tutmuyorsa) yenisi alınır.
  Course _keepFixes(Course incoming) {
    final old = courses[incoming.id];
    if (old == null || identical(old, incoming)) return incoming;
    final mine = {
      for (final u in old.units)
        for (final l in u.lessons)
          for (final (i, e) in l.exercises.indexed)
            if (e.fixedFrom.isNotEmpty) '${l.id}#$i': e,
    };
    if (mine.isEmpty) return incoming;
    var kept = false;
    Exercise pick(String key, Exercise now) {
      final fix = mine[key];
      if (fix == null || identical(fix, now) || fix.fixedFrom != now.fingerprint) return now;
      kept = true;
      return fix;
    }

    final units = [
      for (final u in incoming.units)
        u.copyWith(lessons: [
          for (final l in u.lessons)
            l.copyWith(exercises: [
              for (final (i, e) in l.exercises.indexed) pick('${l.id}#$i', e),
            ]),
        ]),
    ];
    return kept ? incoming.copyWith(units: units) : incoming;
  }

  /* ----- Hatalı işaretlenen sorular ----- */

  /// Kullanıcı soruyu hatalı buldu: düzeltilene ya da işareti kaldırılana kadar hiçbir yerde sorulmaz,
  /// yanlış sayılmaz, tekrar takviminden çıkar. İşaret [step] adımının izine bağlanır.
  void flag(String courseId, String key, Exercise step) {
    final prog = progressOf(courseId);
    prog.flagged[key] = step.fingerprint;
    prog.mistakes.remove(key);
    prog.memory.remove(key);
    commit();
  }

  void unflag(String courseId, String key) {
    if (progressOf(courseId).flagged.remove(key) != null) commit();
  }

  /// [key] sırasındaki adım hatalı işaretli mi. İşaret sıraya değil adıma aittir: ünite yeniden üretilip o sıraya
  /// başka bir adım geldiyse (iz tutmuyorsa) işaretli sayılmaz; yoksa yeni adım gizlenir, bir düzeltme de onun üzerine yazardı.
  bool isFlagged(Course course, String key) {
    final mark = progress[course.id]?.flagged[key];
    if (mark == null) return false;
    final at = _stepAt(course, key);
    return at != null && (mark.isEmpty || mark == at.lesson.exercises[at.index].fingerprint);
  }

  /// Kursun içeriği değiştiğinde (birleştirme, yenileme, paket, yükleme) artık adımını göstermeyen işaretleri atar;
  /// izsiz kaydedilmiş eski işaretleri sıradaki soruya bağlar.
  void _settleFlags(Course course) {
    final flagged = progress[course.id]?.flagged;
    if (flagged == null || flagged.isEmpty) return;
    for (final key in flagged.keys.toList()) {
      final at = _stepAt(course, key);
      final step = at?.lesson.exercises[at.index];
      if (step == null || !step.isQuestion || (flagged[key]!.isNotEmpty && flagged[key] != step.fingerprint)) {
        flagged.remove(key);
      } else {
        flagged[key] = step.fingerprint;
      }
    }
  }

  /// Kursta hatalı işaretlenmiş adımlar, kurstaki sırasıyla.
  List<({String key, Lesson lesson, Exercise exercise})> flaggedOf(Course course) {
    if (progress[course.id]?.flagged.isEmpty ?? true) return const [];
    return [
      for (final u in course.units)
        for (final l in u.lessons)
          for (final (i, ex) in l.exercises.indexed)
            if (isFlagged(course, '${l.id}#$i')) (key: '${l.id}#$i', lesson: l, exercise: ex),
    ];
  }

  /// Bir düzeltme çıktısının işaretli sorulara göre dökümü. `changed`: uygulanabilecek olanlar; yalnızca kullanıcının
  /// hatalı işaretlediği, tipi aynı kalmış ve gerçekten değişmiş adımlar. Başka bir adımı gösteren düzeltme alınmaz;
  /// böylece dışarıdan gelen bir düzeltme dosyası işaretlenmemiş içeriği değiştiremez. `unchanged`: olduğu gibi geri
  /// gelen işaretli adım sayısı (yapay zekâ hata bulamadı ya da panoda cevap değil kalıbın kendisi var); bunlar
  /// düzeltilmiş sayılmaz, işaretleri durur.
  ({Map<String, Exercise> changed, int unchanged}) fixable(Course course, Iterable<({String at, Exercise exercise})> fixes) {
    final flagged = {for (final f in flaggedOf(course)) f.key: f.exercise};
    final changed = <String, Exercise>{};
    final same = <String>{};
    for (final f in fixes) {
      final old = flagged[f.at];
      if (old == null || old.type != f.exercise.type) continue;
      jsonEncode(old.content) == jsonEncode(f.exercise.content) ? same.add(f.at) : changed[f.at] = f.exercise;
    }
    return (changed: changed, unchanged: same.difference(changed.keys.toSet()).length);
  }

  /// Düzeltmeleri uygular: adımlar yeni hâlleriyle değişir, işaretleri kalkar ve bugünkü tekrara girer.
  /// Kaç adımın değiştiğini döndürür.
  int applyFixes(Course course, Iterable<({String at, Exercise exercise})> fixes) {
    final byKey = fixable(course, fixes).changed;
    if (byKey.isEmpty || courses[course.id] != course) return 0;
    // Düzeltilen adım, yerine geçtiği adımın izini taşır (bir kez daha düzeltilirse ilk hâlin izi kalır):
    // kursun içeriği sonradan yenilenirse düzeltme bununla tanınıp korunur (_keepFixes)
    Exercise fixed(Exercise old, Exercise now) => Exercise({...now.content, 'fixedFrom': old.fixedFrom.isEmpty ? old.fingerprint : old.fixedFrom});
    final units = [
      for (final u in course.units)
        u.copyWith(lessons: [
          for (final l in u.lessons)
            l.copyWith(exercises: [
              for (final (i, e) in l.exercises.indexed)
                if (byKey['${l.id}#$i'] case final now?) fixed(e, now) else e,
            ]),
        ]),
    ];
    final prog = progressOf(course.id);
    for (final key in byKey.keys) {
      prog.flagged.remove(key);
      prog.mistakes.remove(key);
      prog.memory[key] = (box: 0, due: today);
    }
    // Düzeltmenin kendisi "eski düzeltmeyi koru" kuralından geçmez: kullanıcı az önce yeni hâli seçti
    _replace(course.copyWith(units: units));
    return byKey.length;
  }

  /// Kullanıcının uygulama içinden tek bir adımı düzenlemesi: adım yeni içeriğiyle değişir,
  /// hatalı işareti varsa kalkar ve kurs kaydedilir.
  bool editExercise(Course course, String key, Exercise updated) {
    if (courses[course.id] != course) return false;
    final at = _stepAt(course, key);
    if (at == null) return false;
    final old = at.lesson.exercises[at.index];
    final next = Exercise({...updated.content, 'fixedFrom': old.fixedFrom.isEmpty ? old.fingerprint : old.fixedFrom});
    final units = [
      for (final u in course.units)
        u.copyWith(lessons: [
          for (final l in u.lessons)
            l.id == at.lesson.id
                ? l.copyWith(exercises: [
                    for (final (i, e) in l.exercises.indexed) i == at.index ? next : e,
                  ])
                : l,
        ]),
    ];
    final prog = progressOf(course.id);
    prog.flagged.remove(key);
    _replace(course.copyWith(units: units));
    return true;
  }

  /* ----- Sınavla geçme ----- */

  bool _unitDone(Course course, int unitIndex) {
    final done = progressOf(course.id).lessons;
    return nodes(course).where((n) => n.unitIndex == unitIndex).every((n) => done.containsKey(n.id));
  }

  /// [unitIndex]. üniteye kadar (o dâhil) henüz bitmemiş üniteler: sınav bunları kapsar, geçilince hepsi tamamlanır.
  List<int> examUnits(Course course, int unitIndex) => [
        for (var i = 0; i <= unitIndex && i < course.units.length; i++)
          if (!_unitDone(course, i)) i,
      ];

  /// Sınav soruları: kapsanan her üniteden eşit sayıda, rastgele seçilir.
  List<LessonItem> examItems(Course course, int unitIndex) {
    final units = examUnits(course, unitIndex);
    if (units.isEmpty) return [];
    final per = units.length == 1 ? 10 : math.max(3, 20 ~/ units.length);
    return [
      for (final i in units) ...(questionsOf(course.units[i], course)..shuffle(random)).take(per),
    ];
  }

  /// Sınavda kaç soru sorulacağı (soruları seçmeden).
  int examSize(Course course, int unitIndex) {
    final units = examUnits(course, unitIndex);
    final per = units.length == 1 ? 10 : math.max(3, 20 ~/ math.max(1, units.length));
    return units.fold(0, (n, i) => n + math.min(per, questionsOf(course.units[i], course).length));
  }

  /// Kursun (kısmın) kalan bütün üniteleri tek sınavla geçilebilir mi.
  bool canTestOutCourse(Course course) => course.units.isNotEmpty && examSize(course, course.units.length - 1) >= 3;

  /// Sınavda yapılabilecek en çok yanlış sayısı (bir fazlası sınavı bitirir).
  static int examAllowance(int questions) => math.max(1, questions ~/ 5);

  bool canTestOut(Course course, int unitIndex) =>
      !_unitDone(course, unitIndex) && questionsOf(course.units[unitIndex], course).length >= 3;

  Character hostOf(PathNode node) =>
      node.kind == NodeKind.practice || node.kind == NodeKind.daily || node.kind == NodeKind.flashcards
          ? characterOf(MascotId.pasa)
          : hostOfUnit(node.unitIndex, buddy.id);

  /* ----- Rozetler ve ders sonucu ----- */

  /// Rozetin ilerleme durumu: kazanılmamış rozetlerde mevcut ve hedef değeri verir.
  ({int cur, int max, String? unit})? badgeProgress(Badge b) => switch (b.id) {
        'first' => (cur: math.min(profile.lessonsDone, 1), max: 1, unit: null),
        'creator' => (cur: profile.created ? 1 : 0, max: 1, unit: null),
        'perfect' => (cur: math.min(profile.perfect, 1), max: 1, unit: null),
        'combo10' => (cur: math.min(profile.maxCombo, 10), max: 10, unit: null),
        'goal' => (cur: math.min(todayXp, settings.dailyGoal), max: settings.dailyGoal, unit: null),
        's3' => (cur: math.min(profile.bestStreak, 3), max: 3, unit: t('badge.unitDays')),
        's7' => (cur: math.min(profile.bestStreak, 7), max: 7, unit: t('badge.unitDays')),
        's30' => (cur: math.min(profile.bestStreak, 30), max: 30, unit: t('badge.unitDays')),
        's100' => (cur: math.min(profile.bestStreak, 100), max: 100, unit: t('badge.unitDays')),
        'l10' => (cur: math.min(profile.lessonsDone, 10), max: 10, unit: null),
        'l50' => (cur: math.min(profile.lessonsDone, 50), max: 50, unit: null),
        'l100' => (cur: math.min(profile.lessonsDone, 100), max: 100, unit: null),
        'perfect5' => (cur: math.min(profile.perfect, 5), max: 5, unit: null),
        'perfect10' => (cur: math.min(profile.perfect, 10), max: 10, unit: null),
        'unit' => (cur: progress.values.any((p) => p.lessons.keys.any((k) => k.endsWith(reviewSuffix))) ? 1 : 0, max: 1, unit: null),
        'course' => (cur: math.min(courses.values.where((c) => percent(c) == 1).length, 1), max: 1, unit: null),
        'course3' => (cur: math.min(courses.values.where((c) => percent(c) == 1).length, 3), max: 3, unit: null),
        'xp100' => (cur: math.min(math.max(profile.xp, profile.totalXp), 100), max: 100, unit: null),
        'xp500' => (cur: math.min(math.max(profile.xp, profile.totalXp), 500), max: 500, unit: null),
        'xp1000' => (cur: math.min(math.max(profile.xp, profile.totalXp), 1000), max: 1000, unit: null),
        'xp2000' => (cur: math.min(math.max(profile.xp, profile.totalXp), 2000), max: 2000, unit: null),
        'xp5000' => (cur: math.min(math.max(profile.xp, profile.totalXp), 5000), max: 5000, unit: null),
        'import1' => (cur: profile.importedCourses >= 1 ? 1 : 0, max: 1, unit: null),
        'section1' => (cur: (profile.sectionsAdded >= 1 || courses.values.any((c) => c.group.isNotEmpty && courses.values.where((x) => x.group == c.group).length > 1)) ? 1 : 0, max: 1, unit: null),
        'spaced1' => (cur: math.min(profile.spacedSessions, 1), max: 1, unit: null),
        'spaced10' => (cur: math.min(profile.spacedSessions, 10), max: 10, unit: null),
        'night_owl' => (cur: profile.nightLessons >= 1 ? 1 : 0, max: 1, unit: null),
        'early_bird' => (cur: profile.earlyLessons >= 1 ? 1 : 0, max: 1, unit: null),
        'all_types' => (cur: math.min(profile.stepTypes.where(answerStepTypes.contains).length, answerStepTypes.length), max: answerStepTypes.length, unit: null),
        'comeback' => (cur: profile.breakReturns >= 1 ? 1 : 0, max: 1, unit: null),
        'marathon' => (cur: math.min(profile.xpByDay.values.fold(0, math.max), 200), max: 200, unit: null),
        'mastered50' => (cur: math.min(progress.values.fold(0, (sum, p) => sum + p.memory.values.where((m) => m.box == reviewDays.length - 1).length), 50), max: 50, unit: null),
        _ => null,
      };

  List<Badge> awardBadges() {
    final fresh = badges.where((b) => !profile.badges.containsKey(b.id) && b.test(this)).toList();
    for (final b in fresh) {
      profile.badges[b.id] = today;
    }
    return fresh;
  }

  LessonOutcome completeLesson(LessonResult r) {
    final p = profile;
    final t = today;
    final beforeLevel = level.level;
    final beforeGoal = todayXp >= settings.dailyGoal;
    final wasActive = p.lastActive == t;

    if (p.lastActive != null && p.lastActive!.compareTo(addDays(t, -7)) <= 0) {
      p.breakReturns++;
    }
    final hour = _clock().hour;
    final min = _clock().minute;
    if (hour >= 22 || hour < 4 || (hour == 4 && min == 0)) {
      p.nightLessons++;
    }
    if ((hour >= 5 && hour < 8) || (hour == 8 && min == 0)) {
      p.earlyLessons++;
    }
    if (r.node.kind == NodeKind.daily) {
      p.spacedSessions++;
    }
    p.stepTypes.addAll(r.rightStepTypes);

    p.xp += r.xp;
    p.totalXp = math.max(p.totalXp, p.xp - r.xp) + r.xp;
    p.xpByDay[t] = todayXp + r.xp;
    p.xpByDay.removeWhere((d, _) => d.compareTo(addDays(t, -90)) < 0);
    p.lessonsDone++;
    if (r.perfect) p.perfect++;
    p.maxCombo = math.max(p.maxCombo, r.maxCombo);
    p.answered += r.questions;
    p.correct += r.firstTry;
    var freezeUsed = false, freezeEarned = false;
    if (!wasActive) {
      if (p.lastActive != null && t.compareTo(p.lastActive!) < 0) {
        // Cihaz saati geriye alınmış: bugün lastActive tarihinden önceyse seri korunur, lastActive geriye çekilmez.
      } else {
        if (p.lastActive == addDays(t, -1)) {
          p.streak++;
        } else if (p.freezes > 0 && p.lastActive == addDays(t, -2)) {
          p.freezes--;
          p.streak++;
          freezeUsed = true;
        } else {
          p.streak = 1;
        }
        p.lastActive = t;
        p.bestStreak = math.max(p.bestStreak, p.streak);
        if (p.streak > 0 && p.streak % 3 == 0 && p.freezes < maxFreezes) {
          p.freezes++;
          freezeEarned = true;
        }
      }
    }

    if (session?.courseId == r.courseId && session?.nodeId == r.node.id) session = null;

    final prog = progressOf(r.courseId);
    final course = courses[r.courseId];
    final wasFinished = course != null && isFinished(course);
    if (r.node.kind != NodeKind.daily) prog.last = _clock().millisecondsSinceEpoch;
    if (r.node.kind == NodeKind.exam && course != null) {
      // Sınav geçildi: kapsanan ünitelerin bütün düğümleri tamamlanmış sayılır (yıldızsız: derse girilmedi)
      final covered = examUnits(course, r.node.unitIndex).toSet();
      for (final n in nodes(course)) {
        if (covered.contains(n.unitIndex)) prog.lessons.putIfAbsent(n.id, () => (stars: 0, plays: 0));
      }
    } else if (r.node.kind == NodeKind.lesson || r.node.kind == NodeKind.review) {
      final prev = prog.lessons[r.node.id];
      prog.lessons[r.node.id] = (stars: math.max(prev?.stars ?? 0, r.stars), plays: (prev?.plays ?? 0) + 1);
    }
    void mark(CourseProgress prog, Set<String> right, Set<String> wrong, Set<String> cardRight, Set<String> cardWrong) {
      right.forEach(prog.mistakes.remove);
      for (final k in wrong) {
        prog.mistakes[k] = (prog.mistakes[k] ?? 0) + 1;
      }
      _remember(prog, [...right, ...cardRight], [...wrong, ...cardWrong]);
    }

    mark(prog, r.rightKeys, r.wrongKeys, r.cardRight, r.cardWrong);
    for (final e in r.mixed.entries) {
      mark(progressOf(e.key), e.value.right, e.value.wrong, e.value.cardRight, e.value.cardWrong);
    }

    final fresh = awardBadges();
    commit();
    return LessonOutcome(
      levelUp: level.level > beforeLevel ? level.level : 0,
      streakUp: wasActive ? 0 : p.streak,
      goalMet: !beforeGoal && todayXp >= settings.dailyGoal,
      newBadges: fresh,
      courseDone: course != null && !wasFinished && isFinished(course),
      freezeUsed: freezeUsed,
      freezeEarned: freezeEarned,
    );
  }

  /// Yarıda kalan dersin yanlışları da pratik havuzuna girer.
  void recordMistakes(String courseId, Set<String> keys) {
    final prog = progressOf(courseId)..last = _clock().millisecondsSinceEpoch;
    for (final k in keys) {
      prog.mistakes[k] = (prog.mistakes[k] ?? 0) + 1;
    }
    _remember(prog, const [], keys);
    commit();
  }

  /* ----- Yedek -----
     Otomatik yedek günde en çok bir kez, bir şey değiştiyse alınır; son [autoBackupsKept] tanesi durur.
     Elle alınan son yedek ayrıca saklanır ve yalnızca yeni bir elle yedek alındığında silinir. */

  static const autoBackupsKept = 3;

  String exportBackup({bool includeSecrets = false}) => jsonEncode(toJson(includeSecrets: includeSecrets));

  /// Kaydın parmak izi: aynı içeriğin ikinci kez yedeklenmemesi için (FNV-1a).
  String get _signature {
    final text = jsonEncode(_stateJson(includeSecrets: false)) + [for (final c in courses.values) '${c.id}:${c.title}:${c.lessonCount}:${c.exerciseCount}'].join('|');
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Future<BackupInfo> _writeBackup({required bool manual}) async {
    final info = BackupInfo(manual: manual, time: _clock(), signature: _signature, name: BackupInfo.nameFor(manual: manual, time: _clock(), signature: _signature));
    await _storage.writeBackup(info.name, exportBackup(includeSecrets: false));
    backups = [info, ...backups.where((b) => b.name != info.name)]..sort((a, b) => b.time.compareTo(a.time));
    return info;
  }

  Future<void> _dropBackups(Iterable<BackupInfo> old) async {
    for (final b in old.toList()) {
      await _storage.deleteBackup(b.name);
      backups.remove(b);
    }
  }

  /// Otomatik yedek. Günde bir kez ve ancak şimdiki durumun yedeği yoksa alınır; [force] gün sınırını kaldırır
  /// (geri yükleme ve sıfırlama öncesi için). En yeni üç otomatik yedek kalır; elle alınana dokunulmaz.
  Future<bool> autoBackup({bool force = false}) async {
    _autoCheckedOn = today;
    // Yedeklenecek bir şey olmalı: yalnızca yol arkadaşı seçilmiş boş uygulama yedeklenmez
    if (_backingUp || (courses.isEmpty && profile.xp == 0)) return false;
    final signature = _signature;
    if (backups.any((b) => b.signature == signature)) return false;
    final lastAuto = backups.where((b) => !b.manual).firstOrNull;
    if (!force && lastAuto != null && dayKey(lastAuto.time) == today) return false;
    _backingUp = true;
    try {
      await _writeBackup(manual: false);
      await _dropBackups(backups.where((b) => !b.manual).skip(autoBackupsKept));
    } catch (_) {
      return false; // yedek alınamadıysa uygulama yine de çalışır
    } finally {
      _backingUp = false;
    }
    notifyListeners();
    return true;
  }

  /// Kullanıcının kendisinin aldığı yedek: bir öncekinin yerine geçer.
  Future<BackupInfo> manualBackup() async {
    final info = await _writeBackup(manual: true);
    await _dropBackups(backups.where((b) => b.manual && b.name != info.name));
    notifyListeners();
    return info;
  }

  Future<String?> backupText(BackupInfo backup) => _storage.readBackup(backup.name);

  /// Cihazdaki bir yedeği geri yükler; önce şimdiki durumun yedeğini alır.
  Future<void> restoreBackup(BackupInfo backup) async {
    final text = await _storage.readBackup(backup.name);
    if (text == null) throw const FormatException('Yedek dosyası bulunamadı.');
    await restoreFrom(text);
  }

  /// Bir yedek metnini (cihazdan ya da dosyadan) yükler; önce şimdiki durumun yedeğini alır.
  Future<void> restoreFrom(String text) async {
    final data = _backupData(text);
    await autoBackup(force: true);
    _applyBackup(data);
  }

  /// Her şeyi siler ama önce şimdiki durumun yedeğini alır; cihazdaki yedekler silinmez.
  Future<void> resetWithBackup() async {
    await autoBackup(force: true);
    reset();
  }

  void importBackup(String text) => _applyBackup(_backupData(text));

  Map _backupData(String text) {
    final data = jsonDecode(text);
    if (data is! Map || data['courses'] is! Map || data['profile'] is! Map) throw const FormatException('Bu dosya bir Bilge yedeği değil.');
    return data;
  }

  void _applyBackup(Map data) {
    try {
      _apply(data);
    } on Error {
      // Alanlardan biri beklenen türde değil (elle değiştirilmiş ya da bozulmuş yedek)
      throw const FormatException('Bu yedek dosyası bozuk.');
    }
    _coursesDirty = true;
    commit();
  }

  /// Her şeyi siler; uygulama karşılama ekranına döner.
  void reset() {
    _apply({});
    _coursesDirty = true;
    commit();
  }
}
