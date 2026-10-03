/// Ders ekranı: adım kuyruğu, canlar, kombo, geri bildirim ve bitiş.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/schema.dart';
import '../core/store.dart';
import '../core/text_utils.dart';
import '../l10n/l10n.dart';
import '../mascot/cast.dart';
import '../mascot/mascot_art.dart';
import '../mascot/mascot_view.dart';
import '../ui/chart.dart';
import '../ui/confetti.dart';
import '../ui/io.dart';
import '../ui/sfx.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'exercises.dart';

const _maxHearts = 5;

/// Bir adımı (soruyu, cevabını ve açıklamasını) uygulama içinden hızlıca düzenleme penceresi.
/// Kaydedildiyse yeni [Exercise] döner; vazgeçildiyse null döner.
Future<Exercise?> showEditExerciseSheet(BuildContext context, Course course, String key, Exercise ex) =>
    showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _EditExerciseSheet(course: course, exerciseKey: key, ex: ex),
    );

class _EditExerciseSheet extends StatefulWidget {
  const _EditExerciseSheet({required this.course, required this.exerciseKey, required this.ex});
  final Course course;
  final String exerciseKey;
  final Exercise ex;

  @override
  State<_EditExerciseSheet> createState() => _EditExerciseSheetState();
}

class _EditExerciseSheetState extends State<_EditExerciseSheet> {
  late final String promptField = switch (widget.ex.type) {
    'truefalse' => 'statement',
    'fill' => 'text',
    'flashcard' => 'front',
    'info' => 'title',
    _ => 'question',
  };
  late final String answerField = switch (widget.ex.type) {
    'choice' || 'type' => 'answer',
    'number' => 'answer',
    'flashcard' => 'back',
    'info' => 'body',
    _ => '',
  };
  late final TextEditingController promptCtrl = TextEditingController(text: widget.ex.text(promptField));
  late final TextEditingController answerCtrl = TextEditingController(
    text: answerField.isEmpty ? '' : (widget.ex.type == 'number' ? '${widget.ex.data['answer'] ?? ''}' : widget.ex.text(answerField)),
  );
  late final TextEditingController explainCtrl = TextEditingController(text: widget.ex.explanation);

  @override
  void dispose() {
    promptCtrl.dispose();
    answerCtrl.dispose();
    explainCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final p = context.p;
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: ts(14, w: FontWeight.w800, color: p.ink3),
          filled: true,
          fillColor: p.surface2,
          contentPadding: const EdgeInsets.all(14),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.line2, width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.primary, width: 2)),
        );
    return sheetBody(
      context,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      head: [
        Text(t('edit.title'), style: ts(22, w: FontWeight.w900, color: p.ink)),
        const SizedBox(height: 14),
      ],
      scroll: [
        TextField(
          controller: promptCtrl,
          maxLines: 3,
          minLines: 1,
          style: ts(16, w: FontWeight.w700, color: p.ink),
          decoration: deco(t('edit.question')),
        ),
        if (answerField.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextField(
            controller: answerCtrl,
            maxLines: widget.ex.type == 'flashcard' || widget.ex.type == 'info' ? 3 : 1,
            minLines: 1,
            style: ts(16, w: FontWeight.w700, color: p.ink),
            decoration: deco(t('edit.answer')),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: explainCtrl,
          maxLines: 3,
          minLines: 1,
          style: ts(16, w: FontWeight.w700, color: p.ink),
          decoration: deco(t('edit.explanation')),
        ),
      ],
      foot: [
        const SizedBox(height: 16),
        ChunkyButton(
          label: t('edit.save'),
          onPressed: () {
            final q = promptCtrl.text.trim();
            if (q.isEmpty) return;
            if (widget.ex.type == 'fill' && !q.contains(RegExp(r'\{\{.+?\}\}'))) {
              toast(context, t('r.noBlank'), floating: true);
              return;
            }
            final map = Map<String, dynamic>.from(widget.ex.content);
            map[promptField] = q;
            if (answerField.isNotEmpty) {
              final a = answerCtrl.text.trim();
              if (widget.ex.type != 'info' && a.isEmpty) return;
              if (a.isNotEmpty) {
                if (widget.ex.type == 'number') {
                  final n = num.tryParse(a.replaceAll(',', '.'));
                  if (n == null) return;
                  map[answerField] = n;
                } else {
                  map[answerField] = a;
                  if (widget.ex.type == 'choice') {
                    final dist = (map['distractors'] as List?)?.map((e) => e.toString()).toList() ?? [];
                    dist.removeWhere((d) => norm(d) == norm(a));
                    if (dist.isEmpty) {
                      toast(context, t('r.needDistractor'), floating: true);
                      return;
                    }
                    map['distractors'] = dist;
                  }
                }
              }
            }
            final exp = explainCtrl.text.trim();
            map.remove('explain');
            if (exp.isNotEmpty) {
              map['explanation'] = exp;
            } else {
              map.remove('explanation');
            }
            final candidate = Exercise(map);
            final activeCourse = app.courses[widget.course.id] ?? widget.course;
            if (app.editExercise(activeCourse, widget.exerciseKey, candidate)) {
              Sfx.play('correct');
              Navigator.pop(context, candidate);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        const SizedBox(height: 8),
        ChunkyButton(label: t('common.cancel'), kind: ButtonKind.ghost, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.course, required this.node, this.resume});
  final Course course;
  final PathNode node;
  final SavedSession? resume;

  /// Dersi açar. Kısım bu dersle bitip kullanıcı "sıradaki kısma geç" dediyse (sıradaki kısım seçilmiş olarak) true döner.
  static Future<bool> open(BuildContext context, Course course, PathNode node, {SavedSession? resume}) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LessonScreen(course: course, node: node, resume: resume))).then((next) => next ?? false);

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _Queued {
  _Queued(this.item);
  final LessonItem item;
  int tries = 0;
}

enum _Phase { answer, feedback, finished, failed }

class _LessonScreenState extends State<LessonScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AppState _app = AppScope.read(context);
  late final Character _host = _app.hostOf(widget.node);
  late final bool _daily = widget.node.kind == NodeKind.daily; // günün tekrarı: bütün kurslardan karışık
  late final bool _flashcards = widget.node.kind == NodeKind.flashcards;
  late final bool _practice = widget.node.kind == NodeKind.practice || _daily || _flashcards;
  late final bool _exam = widget.node.kind == NodeKind.exam;
  // Sınavda can, yapılabilecek yanlış sayısıdır; ayardan bağımsız olarak hep sayılır
  late final bool _useHearts = _exam || (_app.settings.hearts && !_practice);
  late final Color _color = _practice ? Palette.unitColors.first : Palette.unitColor(widget.node.unitIndex);
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));

  late List<_Queued> _queue;
  late int _total, _questions;
  int _done = 0, _hearts = _maxHearts, _combo = 0, _maxCombo = 0, _firstTry = 0, _serial = 0;
  final _wrong = <LessonItem>{}, _right = <LessonItem>{};
  final _cardWrong = <LessonItem>{}, _cardRight = <LessonItem>{}; // ezber kartları: yalnızca tekrar takvimini etkiler
  final _resumedWrong = <String>{}, _resumedRight = <String>{}, _resumedCardWrong = <String>{}, _resumedCardRight = <String>{};
  final _resumedRightStepTypes = <String>{}, _rightStepTypes = <String>{};
  int _skippedUnits = 0; // sınavla geçilen ünite sayısı
  int _dueLeft = 0; // günün tekrarından sonra bugün için kalan öğe sayısı
  Course? _nextSection; // kurs bu dersle bittiyse grubun sıradaki kısmı
  final _hidden = <String>{}; // kullanıcının bu derste kapattığı ortak metinler
  bool _flaggedNow = false; // ekrandaki soru az önce hatalı olarak işaretlendi
  int _flagCount = 0; // bu oturumda hatalı işaretlenen soru sayısı
  int _comboBefore = 0; // son cevaptan önceki kombo: soru hatalı işaretlenirse geri gelir
  int _heartCap = _maxHearts; // oturumun başındaki can sayısı: geri gelen canlar bunu aşmaz
  bool _freePlay = false; // canlar bitti, kullanıcı yıldızsız devam etmeyi seçti: artık can sayılmaz
  final _recorded = <LessonItem>{}; // canlar bittiğinde yanlışları yazılmış öğeler (ders bitince ikinci kez yazılmaz)
  DateTime _started = DateTime.now();
  _Queued? _cur;
  _Phase _phase = _Phase.answer;
  bool _ready = false;
  ExResult? _result;
  String _line = '';
  GlobalKey<ExerciseViewState> _key = GlobalKey();

  // Bitiş ekranı için
  LessonOutcome? _outcome;
  int _stars = 0, _xp = 0, _seconds = 0;
  double _accuracy = 1;
  bool _perfect = false;

  /// Uzun süre dokunulmazsa dersteki maskot uyur; ekrana dokununca uyanır.
  static const _sleepAfter = Duration(seconds: 30);
  Timer? _idle;

  void _awake() {
    MascotView.drowsy.value = false;
    _idle?.cancel();
    // Testlerde animasyon kapalıdır: bekleyen zamanlayıcı bırakılmaz
    if (MascotView.animate) _idle = Timer(_sleepAfter, () => MascotView.drowsy.value = true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _awake();
    _start(fromResume: widget.resume != null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    _shake.dispose();
    MascotView.drowsy.value = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _saveSessionState();
    }
  }

  void _start({bool fromResume = false}) {
    _resumedWrong.clear();
    _resumedRight.clear();
    _resumedCardWrong.clear();
    _resumedCardRight.clear();
    _resumedRightStepTypes.clear();
    _rightStepTypes.clear();
    if (fromResume && widget.resume != null) {
      final r = widget.resume!;
      final resumed = _app.resumeItems(widget.course, r);
      if (resumed.isNotEmpty) {
        _queue = [
          for (final it in resumed)
            _Queued(it)..tries = (r.wrongKeys.contains(it.key) ? 1 : 0),
        ];
        _total = math.max(r.total, r.done + _queue.length);
        _questions = r.questions;
        _done = r.done.clamp(0, _total - 1);
        _heartCap = _exam ? AppState.examAllowance(_questions) + 1 : _maxHearts;
        _hearts = r.hearts.clamp(1, _heartCap);
        _combo = r.combo;
        _maxCombo = r.maxCombo;
        _firstTry = r.firstTry;
        _resumedWrong.addAll(r.wrongKeys);
        _resumedRight.addAll(r.rightKeys);
        _resumedCardWrong.addAll(r.cardWrong);
        _resumedCardRight.addAll(r.cardRight);
        _resumedRightStepTypes.addAll(r.rightStepTypes);
        _wrong.clear();
        _right.clear();
        _cardWrong.clear();
        _cardRight.clear();
        _hidden.clear();
        _flagCount = 0;
        _freePlay = false;
        _recorded.clear();
        _started = DateTime.now();
        _phase = _Phase.answer;
        _next();
        return;
      }
    }
    var items = _daily
        ? _app.dailyItems()
        : _flashcards
            ? _app.flashcardItems(widget.course)
            : _practice
                ? _app.practiceItems(widget.course)
                : _exam
                    ? _app.examItems(widget.course, widget.node.unitIndex)
                    : _app.itemsOf(widget.node, widget.course);
    // Dersin bütün adımları hatalı işaretlenmişse ders boş kalmasın: işaretlere bakılmadan oynanır
    if (items.isEmpty && !_practice && !_exam) items = _app.itemsOf(widget.node);
    _queue = [for (final it in items) _Queued(it)];
    _total = items.length;
    _questions = items.where((it) => it.exercise.isQuestion).length;
    _done = _combo = _maxCombo = _firstTry = 0;
    _hearts = _heartCap = _exam ? AppState.examAllowance(_questions) + 1 : _maxHearts;
    _wrong.clear();
    _right.clear();
    _cardWrong.clear();
    _cardRight.clear();
    _hidden.clear();
    _flagCount = 0;
    _freePlay = false;
    _recorded.clear();
    _started = DateTime.now();
    _phase = _Phase.answer;
    _next();
  }

  ExMode get _mode => modeOf(_cur!.item.exercise);

  /// Bu oturumda can sayılıyor mu: canlar açık ve kullanıcı yıldızsız devam etmeye geçmemiş.
  bool get _countHearts => _useHearts && !_freePlay;

  /// Ekrandaki öğenin kursu (karışık oturumda öğeden öğeye değişir): dil ve seslendirme buna göre seçilir.
  Course get _course => _cur!.item.from ?? widget.course;

  void _next() {
    _awake(); // yeni adım: uyku sayacı baştan başlar
    if (_queue.isEmpty) return _finish();
    setState(() {
      _cur = _queue.removeAt(0);
      _phase = _Phase.answer;
      _ready = false;
      _result = null;
      _flaggedNow = false;
      _key = GlobalKey();
      _serial++;
    });
  }

  void _onMain() {
    if (_phase == _Phase.feedback) return _countHearts && _hearts <= 0 ? _fail() : _next();
    if (_phase != _Phase.answer) return;
    if (_mode == ExMode.info) {
      Sfx.play('tap');
      _done++;
      _next();
    } else if (_mode == ExMode.check && _ready) {
      _resolve(_key.currentState!.check());
    }
  }

  void _resolve(ExResult r) {
    if (_phase != _Phase.answer) return;
    final cur = _cur!;
    if (r.skipped) {
      // Dinlenemeyen adım: sorulmamış sayılır
      _done++;
      if (cur.item.exercise.isQuestion && cur.tries == 0) _questions--;
      return _next();
    }
    _comboBefore = _combo;
    if (r.correct) {
      _done++;
      _rightStepTypes.add(cur.item.exercise.type);
      if (r.soft) {
        if (cur.tries == 0) _cardRight.add(cur.item);
      } else {
        _combo++;
        if (_combo > _maxCombo) _maxCombo = _combo;
        if (cur.tries == 0) {
          _firstTry++;
          _right.add(cur.item);
        }
      }
    } else {
      cur.tries++;
      if (_exam) {
        _done++; // sınavda her soru bir kez sorulur
      } else {
        _queue.add(cur); // dersin sonunda yeniden sorulur
      }
      if (r.soft) {
        _cardWrong.add(cur.item);
      } else {
        _combo = 0;
        _wrong.add(cur.item);
        if (_countHearts) _hearts--;
      }
    }
    if (r.soft) return _next();
    Sfx.play(r.correct ? 'correct' : 'wrong');
    if (!r.correct) {
      Sfx.buzz();
      if (MascotView.animate) _shake.forward(from: 0);
    }
    setState(() {
      _phase = _Phase.feedback;
      _result = r;
      _line = _host.pick(r.correct ? _host.voice.praise : _host.voice.oops, _app.random);
    });
  }

  /// "Bu soru hatalı": yapay zekânın yazdığı soru yanlış olabilir (yanlış cevap anahtarı, iki doğru şık…).
  /// İşaretlemenin sonuçları belli olmadığı için önce anlatılır.
  void _askFlag() => showBilgeDialog(
        context,
        title: t('lesson.flagTitle'),
        text: t('lesson.flagText'),
        actions: [
          DialogAction(t('lesson.flagDo'), onPressed: _flag),
          DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
        ],
      );

  /// İşaretlenen soru sorulmamış sayılır: yanlış yapıldıysa canlar ve kombo geri gelir, dersin sonunda yeniden
  /// sorulmaz; doğru yapıldıysa da puana katılmaz. Düzeltilene kadar hiçbir oturumda sorulmaz.
  void _flag() {
    final cur = _cur, r = _result;
    if (cur == null || r == null || _flaggedNow || _phase != _Phase.feedback) return;
    _app.flag((cur.item.from ?? widget.course).id, cur.item.key, cur.item.exercise);
    setState(() {
      _flaggedNow = true;
      _flagCount++;
      _questions--;
      if (_right.remove(cur.item)) _firstTry--;
      _wrong.remove(cur.item);
      if (!r.correct) _combo = _comboBefore;
      // Bu soruda (önceki denemeler dâhil) giden canlar geri gelir
      if (_countHearts) _hearts = (_hearts + cur.tries).clamp(0, _heartCap);
      // Dersin sonuna eklenmişti: artık sorulmayacak, ilerleme çubuğunda tamamlanmış sayılır
      if (_queue.remove(cur)) _done++;
    });
  }

  Future<void> _editCurrent() async {
    final cur = _cur;
    if (cur == null) return;
    final next = await showEditExerciseSheet(context, _course, cur.item.key, cur.item.exercise);
    if (next == null || !mounted) return;
    final updatedItem = LessonItem(next, cur.item.key, context: cur.item.context, chart: cur.item.chart, from: cur.item.from);
    setState(() {
      _cur = _Queued(updatedItem)..tries = cur.tries;
      for (var i = 0; i < _queue.length; i++) {
        if (_queue[i].item.key == cur.item.key) {
          _queue[i] = _Queued(updatedItem)..tries = _queue[i].tries;
        }
      }
      _flaggedNow = false;
    });
    toast(context, t('edit.saved'), floating: true);
  }

  void _finish() {
    if (_total == 0) {
      // Sorulacak hiçbir şey yoktu (hepsi bu arada hatalı işaretlenmiş olabilir): ödül de kayıt da yok
      _stars = _xp = _seconds = 0;
      _accuracy = 1;
      _perfect = false;
      _outcome = const LessonOutcome(levelUp: 0, streakUp: 0, goalMet: false, newBadges: []);
      setState(() => _phase = _Phase.finished);
      return;
    }
    _seconds = DateTime.now().difference(_started).inSeconds;
    _accuracy = _questions == 0 ? 1 : _firstTry / _questions;
    // Canlar bittikten sonra sürdürülen ders tamamlanır ama yıldız kazandırmaz
    _stars = _freePlay ? 0 : (_accuracy >= 0.9 ? 3 : (_accuracy >= 0.7 ? 2 : 1));
    _perfect = !_freePlay && _questions > 0 && _wrong.isEmpty && _resumedWrong.isEmpty;
    // Sınavla geçilmiş (hiç oynanmamış) ders ilk kez oynanıyorsa tekrar sayılmaz
    final replay = !_practice && !_exam && (_app.progressOf(widget.course.id).lessons[widget.node.id]?.plays ?? 0) > 0;
    _skippedUnits = _exam ? _app.examUnits(widget.course, widget.node.unitIndex).length : 0;
    final base = _exam ? 10 * _skippedUnits : (_practice || replay ? 5 : (widget.node.kind == NodeKind.review ? 15 : 10));
    _xp = _freePlay ? 5 : base + (_perfect ? 5 : 0) + (_maxCombo >= 10 ? 5 : (_maxCombo >= 5 ? 3 : 0));
    // Cevaplar kurslarına göre ayrılır: aynı ders kimliği farklı kurslarda bulunabilir
    final marks = <String, Marks>{};
    Marks of(LessonItem it) => marks.putIfAbsent((it.from ?? widget.course).id, Marks.new);
    for (final it in _right) {
      of(it).right.add(it.key);
    }
    for (final it in _wrong) {
      if (!_recorded.contains(it)) of(it).wrong.add(it.key);
    }
    for (final it in _cardRight) {
      of(it).cardRight.add(it.key);
    }
    for (final it in _cardWrong) {
      of(it).cardWrong.add(it.key);
    }
    final own = marks.remove(widget.course.id) ?? Marks();
    own.right.addAll(_resumedRight);
    own.wrong.addAll(_resumedWrong);
    own.cardRight.addAll(_resumedCardRight);
    own.cardWrong.addAll(_resumedCardWrong);
    _outcome = _app.completeLesson(LessonResult(
      courseId: widget.course.id, node: widget.node, stars: _stars, xp: _xp, perfect: _perfect,
      questions: _questions, firstTry: _firstTry, maxCombo: _maxCombo, wrongKeys: own.wrong, rightKeys: own.right,
      cardWrong: own.cardWrong, cardRight: own.cardRight, mixed: marks,
      rightStepTypes: {..._resumedRightStepTypes, ..._rightStepTypes},
    ));
    _dueLeft = _daily ? _app.dueTotal : 0;
    _nextSection = _outcome!.courseDone ? _app.nextSection(widget.course) : null;
    if (_app.settings.reminder) {
      scheduleReminder(
        enabled: true,
        hour: _app.settings.reminderHour,
        title: t('reminder.notifTitle'),
        body: t('reminder.notifBody'),
        lastActive: _app.today,
      );
    }
    Sfx.play('complete');
    setState(() => _phase = _Phase.finished);
  }

  void _fail() {
    if (_app.session?.courseId == widget.course.id && _app.session?.nodeId == widget.node.id) _app.session = null;
    _app.recordMistakes(widget.course.id, {..._resumedWrong, for (final it in _wrong) it.key});
    _recorded.addAll(_wrong);
    Sfx.play('fail');
    setState(() => _phase = _Phase.failed);
  }

  /// Canlar bitti ama kullanıcı dersi baştan almak istemiyor: kaldığı yerden, can sayılmadan sürer.
  /// Ders tamamlanır (yol ilerler) ama yıldız kazandırmaz; yıldız için sonra yeniden oynanır. Sınavda yoktur.
  void _continueFree() {
    _freePlay = true;
    _next();
  }

  void _saveSessionState() {
    if (_done > 0 && _phase != _Phase.finished && _phase != _Phase.failed && !_daily) {
      final remaining = [
        if (_cur != null && _phase == _Phase.answer) _cur!.item.key,
        for (final q in _queue) q.item.key,
      ];
      if (remaining.isNotEmpty) {
        _app.saveSession(SavedSession(
          courseId: widget.course.id,
          nodeId: widget.node.id,
          nodeKind: widget.node.kind,
          nodeTitle: widget.node.title,
          unitIndex: widget.node.unitIndex,
          lessonIndex: widget.node.lessonIndex,
          queueKeys: remaining,
          done: _done,
          total: _total,
          questions: _questions,
          hearts: _hearts,
          combo: _combo,
          maxCombo: _maxCombo,
          firstTry: _firstTry,
          wrongKeys: {..._resumedWrong, for (final it in _wrong) it.key},
          rightKeys: {..._resumedRight, for (final it in _right) it.key},
          cardWrong: {..._resumedCardWrong, for (final it in _cardWrong) it.key},
          cardRight: {..._resumedCardRight, for (final it in _cardRight) it.key},
          rightStepTypes: {..._resumedRightStepTypes, ..._rightStepTypes},
        ));
      }
    }
  }

  void _saveAndLeave() {
    _saveSessionState();
    Navigator.of(context).pop();
  }

  void _quit() {
    if (_phase == _Phase.finished || _phase == _Phase.failed || _done == 0) return Navigator.of(context).pop();
    showBilgeDialog(
      context,
      title: t('lesson.quitTitle'),
      text: t('lesson.quitText'),
      actions: [
        DialogAction(t('lesson.stay')),
        DialogAction(t('lesson.leave'), kind: ButtonKind.ghost, onPressed: _saveAndLeave),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final footColor = _phase == _Phase.feedback ? (_result!.correct ? p.goodSoft : p.badSoft) : p.bg;
    final Widget body = switch (_phase) {
      _Phase.finished => _FinishView(state: this),
      _Phase.failed => _FailView(
          host: _host,
          exam: _exam,
          onRetry: () => setState(_start),
          onContinue: _exam ? null : _continueFree,
          onLeave: () => Navigator.of(context).pop(),
        ),
      _ => _play(p, footColor),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _awake(),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: footColor,
          systemNavigationBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(backgroundColor: p.bg, body: body),
        ),
      ),
    );
  }

  Widget _play(Palette p, Color footColor) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final feedback = _phase == _Phase.feedback;
    final showMain = feedback || _mode == ExMode.check || _mode == ExMode.info;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
            child: Row(
              children: [
                IconTap(icon: Icons.close_rounded, onTap: _quit, label: t('lesson.leave')),
                Expanded(child: Semantics(label: '${(_done / _total * 100).round()}%', child: Bar(value: _done / _total, color: _color, track: p.line, height: 16))),
                if (_countHearts) ...[
                  const SizedBox(width: 10),
                  Semantics(
                    label: t('lesson.hearts', {'n': _hearts}),
                    excludeSemantics: true,
                    child: Row(children: [
                      Icon(Icons.favorite_rounded, color: p.bad, size: 24),
                      const SizedBox(width: 3),
                      Text('${_hearts < 0 ? 0 : _hearts}', style: ts(18, w: FontWeight.w900, color: p.bad, height: 1)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(math.sin(_shake.value * math.pi * 3) * 10 * (1 - _shake.value), 0),
                      child: child,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(animation), child: child),
                      ),
                      layoutBuilder: (current, _) => current ?? const SizedBox.shrink(),
                      child: KeyedSubtree(
                        key: ValueKey(_serial),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_cur!.item.context.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                // Açık gelir; kullanıcı kapatırsa (ya da yeniden açarsa) sonraki sorularda öyle kalır
                                child: _ContextCard(
                                  text: _cur!.item.context,
                                  color: _color,
                                  open: !_hidden.contains(_cur!.item.context),
                                  onToggle: (open) => open ? _hidden.remove(_cur!.item.context) : _hidden.add(_cur!.item.context),
                                ),
                              ),
                            // Sorunun dayandığı grafik (öğretici kartta grafik kartın içinde durur)
                            if (_cur!.item.chart != null && _cur!.item.exercise.type != 'info')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Panel(padding: const EdgeInsets.all(14), child: ChartView(_cur!.item.chart!, locale: _course.language)),
                              ),
                            ExerciseView(
                              key: _key,
                              exercise: _cur!.item.exercise,
                              host: _host,
                              color: _color,
                              locale: _course.language,
                              hints: !_exam,
                              speechLang: [_cur!.item.exercise.text('sayLang'), _course.sayLang, _course.language].firstWhere((l) => l.isNotEmpty),
                              random: _app.random,
                              onReady: (v) {
                                _awake(); // klavyeyle yazmak da etkinliktir
                                if (_phase == _Phase.answer) setState(() => _ready = v);
                              },
                              onDone: _resolve,
                              onSubmit: _onMain,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!showMain) SizedBox(height: inset),
          if (showMain) AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10 + inset),
            decoration: BoxDecoration(color: footColor, border: Border(top: BorderSide(color: feedback ? Colors.transparent : p.line, width: 2))),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (feedback) _feedback(p),
                    if (showMain)
                      ChunkyButton(
                        label: feedback || _mode == ExMode.info ? t('common.continue') : t('lesson.check'),
                        kind: feedback ? (_result!.correct ? ButtonKind.good : ButtonKind.bad) : ButtonKind.primary,
                        onPressed: feedback || _mode == ExMode.info || _ready ? _onMain : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Geri bildirim: ünitenin sunucusu kendi ağzından konuşur.
  Widget _feedback(Palette p) {
    final r = _result!;
    final ink = r.correct ? p.goodInk : p.badInk;
    final explanation = _cur!.item.exercise.explanation;
    final solution = _cur!.item.exercise.solution;
    final short = isCompact(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ConstrainedBox(
        // Yan çevrilmiş telefonda yükseklik azdır: maskot küçülür, açıklamaya yer kalır
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (short ? 0.5 : 0.42)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MascotView(_host.id, mood: r.correct ? Mood.cheer : Mood.sad, size: short ? 56 : 98, calm: true),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_line, style: ts(19, w: FontWeight.w900, color: ink, height: 1.2))),
                  if (r.correct && _combo >= 3)
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                      decoration: BoxDecoration(color: Palette.fire, borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 3),
                        Text(t('lesson.combo', {'n': _combo}), style: ts(14, w: FontWeight.w900, color: Colors.white, height: 1.2)),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (!r.correct && r.answer != null) ...[
                Kicker(t('lesson.correctAnswer'), color: ink),
                MdBlock(r.answer!, style: ts(16.5, w: FontWeight.w900, color: ink)),
                const SizedBox(height: 4),
              ],
              for (final text in [r.message, r.note, explanation.isEmpty ? null : explanation])
                if (text != null) Padding(padding: const EdgeInsets.only(top: 2), child: MdBlock(text, style: ts(15.5, color: ink, height: 1.4))),
              if (solution.isNotEmpty)
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showBilgeDialog(
                      context,
                      title: t('lesson.solution'),
                      body: MdBlock(solution, style: ts(16.5, w: FontWeight.w600, color: p.ink, height: 1.5)),
                      actions: [DialogAction(t('common.close'), kind: ButtonKind.ghost)],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.format_list_numbered_rounded, size: 19, color: ink),
                        const SizedBox(width: 6),
                        Text(upper(t('lesson.showSolution')), style: ts(13.5, w: FontWeight.w900, color: ink, spacing: 0.6)),
                        Icon(Icons.chevron_right_rounded, size: 20, color: ink),
                      ]),
                    ),
                  ),
                ),
              // Yapay zekânın yazdığı soru yanlış olabilir: kullanıcı işaretler ya da yerinde düzenler
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (_flaggedNow)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.flag_rounded, size: 19, color: ink),
                        const SizedBox(width: 6),
                        Text(t('lesson.flagged'), style: ts(13.5, w: FontWeight.w800, color: ink)),
                      ])
                    else
                      Semantics(
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _askFlag,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.flag_outlined, size: 19, color: ink.withValues(alpha: 0.75)),
                            const SizedBox(width: 6),
                            Text(t('lesson.flag'), style: ts(13.5, w: FontWeight.w800, color: ink.withValues(alpha: 0.75))),
                          ]),
                        ),
                      ),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _editCurrent,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.edit_outlined, size: 18, color: ink.withValues(alpha: 0.75)),
                          const SizedBox(width: 5),
                          Text(t('lesson.edit'), style: ts(13.5, w: FontWeight.w800, color: ink.withValues(alpha: 0.75))),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- Ortak metin ---------- */

/// Birkaç sorunun dayandığı metin (okuma parçası, vaka, veri). Başlığına dokununca açılıp kapanır.
class _ContextCard extends StatefulWidget {
  const _ContextCard({required this.text, required this.color, required this.open, required this.onToggle});
  final String text;
  final Color color;
  final bool open;
  final ValueChanged<bool> onToggle;

  @override
  State<_ContextCard> createState() => _ContextCardState();
}

class _ContextCardState extends State<_ContextCard> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Sfx.play('tap');
                setState(() => _open = !_open);
                widget.onToggle(_open);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 19, color: widget.color),
                    const SizedBox(width: 8),
                    Expanded(child: Kicker(t('lesson.context'), color: widget.color)),
                    Text(t(_open ? 'lesson.contextHide' : 'lesson.contextShow'), style: ts(13.5, w: FontWeight.w800, color: p.ink3)),
                    Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.ink3),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: MdBlock(widget.text, style: ts(16.5, w: FontWeight.w600, color: p.ink, height: 1.5), strong: widget.color),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/* ---------- Bitiş ---------- */

class _FinishView extends StatelessWidget {
  const _FinishView({required this.state});
  final _LessonScreenState state;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final s = state;
    final o = s._outcome!;
    Widget tile(Color color, Color on, Color ink, IconData icon, String label, Widget value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: FittedBox(child: Text(upper(label), style: ts(11, w: FontWeight.w900, color: on, spacing: 0.4))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(13)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(icon, color: ink, size: 22), const SizedBox(width: 3), DefaultTextStyle(style: ts(20, w: FontWeight.w900, color: ink, height: 1.2), child: value)],
                  ),
                ),
              ],
            ),
          ),
        );
    Widget note(String icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [Text(icon, style: const TextStyle(fontSize: 22)), const SizedBox(width: 10), Expanded(child: Text(text, style: ts(15.5, w: FontWeight.w800, color: p.ink)))]),
          ),
        );
    final title = s._exam
        ? t('finish.exam')
        : (s._flashcards
            ? t('finish.flashcards')
            : (s._perfect ? t('finish.perfect') : (s._daily ? t('finish.daily') : (s._practice ? t('finish.practice') : t('finish.done')))));
    return Stack(
      children: [
        SafeArea(
          // Düğmeler kaydırılan içeriğin dışında, hep görünür durur (rozet ve notlar çok olsa da)
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        children: [
                          // Bitiş ekranında maskot serbesttir: sevinir, sonra jestlerini ve imza hareketlerini yapar
                          // Yan çevrilmiş telefonda yıldızlar ve puanlar ilk bakışta görünsün diye maskot küçülür
                          MascotView(s._host.id, mood: Mood.cheer, size: isCompact(context) ? 124 : 236),
                          const SizedBox(height: 6),
                          Text(title, textAlign: TextAlign.center, style: ts(30, w: FontWeight.w900, color: p.goldInk, height: 1.15)),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${s._host.name}: “${s._perfect ? s._host.voice.perfect : s._host.voice.finish}”',
                                textAlign: TextAlign.center, style: ts(16, color: p.ink2)),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < 3; i++)
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: 1),
                                  duration: Duration(milliseconds: 500 + i * 320),
                                  curve: Interval(i * 320 / (500 + i * 320), 1, curve: Curves.elasticOut),
                                  builder: (_, v, child) => Transform.scale(scale: i < s._stars ? v : 1, child: child),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(Icons.star_rounded, size: i == 1 ? 64 : 48, color: i < s._stars ? Palette.gold : p.line2),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              tile(Palette.gold, const Color(0xFF5A3F00), p.goldInk, Icons.bolt_rounded, t('finish.xp'),
                                  TweenAnimationBuilder<int>(tween: IntTween(begin: 0, end: s._xp), duration: const Duration(milliseconds: 900), builder: (_, v, _) => Text('+$v'))),
                              const SizedBox(width: 10),
                              tile(p.good, const Color(0xFF06351F), p.goodInk, Icons.check_rounded, t('finish.accuracy'), Text('${(s._accuracy * 100).round()}%')),
                              const SizedBox(width: 10),
                              tile(Palette.blue, const Color(0xFF06224F), p.blueInk, Icons.local_fire_department_rounded, t('finish.combo'), Text('${s._maxCombo}')),
                            ],
                          ),
                          if (s._exam) note('⏩', t(s._skippedUnits == 1 ? 'finish.examUnit' : 'finish.examUnits', {'n': s._skippedUnits})),
                          if (s._daily) note('🧠', s._dueLeft > 0 ? t('finish.dailyMore', {'n': s._dueLeft}) : t('finish.dailyClear')),
                          if (o.courseDone)
                            note('🎓', s._nextSection == null ? t('learn.allDone') : t('finish.sectionDone', {'title': sectionTitle(s._nextSection!)})),
                          if (o.streakUp > 0) note('🔥', t('finish.streak', {'n': o.streakUp})),
                          if (o.freezeUsed) note('🧊', t('finish.freezeUsed')),
                          if (o.freezeEarned) note('🧊', t('finish.freezeEarned')),
                          if (o.goalMet) note('🎯', t('finish.goal')),
                          if (o.levelUp > 0) note('⭐', t('finish.level', {'n': o.levelUp})),
                          for (final b in o.newBadges) note(b.icon, t('finish.badge', {'name': b.name})),
                          if (s._flagCount > 0) note('🚩', t('finish.flagged', {'n': s._flagCount})),
                          if (s._freePlay) note('💔', t('finish.noStars')),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(t('finish.time', {'t': formatDuration(s._seconds)}), style: ts(13, w: FontWeight.w800, color: p.ink3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Kısım bittiyse sıradaki kısma buradan geçilir; istemeyen bu kısımda kalır
                      if (s._nextSection case final next?) ...[
                        ChunkyButton(
                          label: t('learn.nextSectionGo'),
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () {
                            s._app.selectCourse(next.id);
                            Navigator.of(context).pop(true);
                          },
                        ),
                        const SizedBox(height: 8),
                        ChunkyButton(label: t('finish.notNow'), kind: ButtonKind.ghost, onPressed: () => Navigator.of(context).pop()),
                      ] else
                        ChunkyButton(label: t('common.continue'), onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned.fill(child: Confetti(count: s._perfect ? 200 : 120)),
      ],
    );
  }
}

class _FailView extends StatelessWidget {
  const _FailView({required this.host, required this.exam, required this.onRetry, required this.onLeave, this.onContinue});
  final Character host;
  final bool exam;
  final VoidCallback onRetry, onLeave;

  /// Yıldızsız devam (sınavda yoktur).
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                MascotView(host.id, mood: Mood.sad, size: isCompact(context) ? 112 : 228, calm: true),
                const SizedBox(height: 8),
                Text(t(exam ? 'fail.examTitle' : 'fail.title'), textAlign: TextAlign.center, style: ts(30, w: FontWeight.w900, color: p.goldInk, height: 1.15)),
                if (exam) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('fail.examText'), textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, color: p.ink))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('${host.name}: “${host.voice.fail}”', textAlign: TextAlign.center, style: ts(17, color: p.ink2)),
                ),
                const SizedBox(height: 8),
                ChunkyButton(label: t('fail.retry'), onPressed: onRetry),
                if (onContinue != null) ...[
                  const SizedBox(height: 8),
                  ChunkyButton(label: t('fail.continue'), kind: ButtonKind.ghost, onPressed: onContinue),
                ],
                const SizedBox(height: 8),
                ChunkyButton(label: t(exam ? 'fail.examLeave' : 'fail.leave'), kind: ButtonKind.ghost, onPressed: onLeave),
                if (onContinue != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(t('fail.continueHint'), textAlign: TextAlign.center, style: ts(13.5, color: p.ink3)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
