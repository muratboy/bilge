/// Ders adımlarının bileşenleri (12 tip). Ders ekranı bir adımı [ExerciseView] ile gösterir,
/// "Kontrol et"e basılınca [ExerciseViewState.check] ile sonucu alır.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/schema.dart';
import '../core/text_utils.dart';
import '../l10n/l10n.dart';
import '../mascot/cast.dart';
import '../mascot/mascot_view.dart';
import '../ui/chart.dart';
import '../ui/sfx.dart';
import '../ui/speech.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class ExResult {
  const ExResult({required this.correct, this.answer, this.note, this.message, this.soft = false, this.skipped = false});
  final bool correct;
  final String? answer; // yanlışta gösterilecek doğru cevap
  final String? note; // doğru ama uyarılı (yazım farkı gibi)
  final String? message; // yanlışın nedeni (eşleştirme, sınıflandırma)
  final bool soft; // kendini değerlendirme: can ve doğruluk etkilenmez
  final bool skipped; // dinlenemeyen adım: hiçbir şeyi etkilemeden geçilir
}

/// check: "Kontrol et" ile; auto: kendi biter; self: kullanıcı kendini değerlendirir; info: yalnızca okunur.
enum ExMode { check, auto, self, info }

ExMode modeOf(Exercise e) => switch (e.type) {
      'info' => ExMode.info,
      'match' || 'categorize' => ExMode.auto,
      'flashcard' => ExMode.self,
      _ => ExMode.check,
    };

class ExerciseView extends StatefulWidget {
  const ExerciseView({
    super.key,
    required this.exercise,
    required this.host,
    required this.color,
    required this.locale,
    required this.random,
    required this.onReady,
    required this.onDone,
    required this.onSubmit,
    this.hints = true,
    this.speechLang = '',
  });

  final Exercise exercise;
  final Character host;
  final Color color; // ünitenin rengi
  final String locale; // kursun dili (cevap karşılaştırma için)
  final Random random;
  final ValueChanged<bool> onReady;
  final ValueChanged<ExResult> onDone;
  final VoidCallback onSubmit;
  final bool hints; // sınavda ipucu verilmez
  final String speechLang; // sesli okunan metinlerin dili

  @override
  // ignore: no_logic_in_create_state
  ExerciseViewState createState() => switch (exercise.type) {
        'info' => _InfoState(),
        'choice' => _OptionsState(false),
        'multi' => _OptionsState(true),
        'truefalse' => _TrueFalseState(),
        'fill' => _FillState(),
        'type' => _TypeState(),
        'number' => _NumberState(),
        'match' => _MatchState(),
        'order' => _ArrangeState(true),
        'build' => _ArrangeState(false),
        'categorize' => _CategorizeState(),
        _ => _FlashState(),
      };
}

abstract class ExerciseViewState extends State<ExerciseView> {
  Exercise get ex => widget.exercise;
  bool locked = false;
  bool _noVoice = false;

  @override
  void initState() {
    super.initState();
    // Dinleme adımı açılınca metin bir kez okunur; ses kapalıysa kullanıcı düğmeye kendisi basar
    if (ex.say.isNotEmpty && Sfx.enabled) WidgetsBinding.instance.addPostFrameCallback((_) => say());
  }

  @override
  void dispose() {
    if (ex.say.isNotEmpty) Speech.stop();
    super.dispose();
  }

  Future<void> say({bool slow = false}) async {
    final ok = await Speech.speak(ex.say, lang: widget.speechLang, slow: slow);
    if (mounted && _noVoice == ok) setState(() => _noVoice = !ok);
  }

  /// Dinleme düğmeleri: normal ve yavaş okuma. Dinleyemeyen kullanıcı soruyu puanı etkilenmeden geçebilir.
  Widget listenBar() {
    final p = context.p;
    Widget round(IconData icon, double size, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Palette.darken(widget.color), offset: const Offset(0, 4))]),
              child: Icon(icon, color: Colors.white, size: size * 0.5),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            round(Icons.volume_up_rounded, 64, t('lesson.listen'), say),
            const SizedBox(width: 14),
            round(Icons.slow_motion_video_rounded, 44, t('lesson.listenSlow'), () => say(slow: true)),
            const SizedBox(width: 8),
            if (ex.isQuestion && !locked)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => widget.onDone(const ExResult(correct: true, skipped: true)),
                    child: Text(t('lesson.cantListen'), textAlign: TextAlign.right, style: ts(13.5, w: FontWeight.w800, color: p.ink3)),
                  ),
                ),
              ),
          ],
        ),
        if (_noVoice) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('lesson.noVoice', {'lang': widget.speechLang}), style: ts(13.5, color: p.badInk))),
      ],
    );
  }

  /// Yalnızca [ExMode.check] adımlarında çağrılır; cevabı işaretler ve sonucu döndürür.
  ExResult check() => const ExResult(correct: true);

  bool same(String a, String b) => norm(a, locale: widget.locale) == norm(b, locale: widget.locale);

  bool _hinted = false;

  /// Adımın başlığı: tip etiketi, soru kökü ve (varsa) istenince açılan ipucu.
  Widget head([String question = '']) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Kicker(t('ex.${ex.type}'), color: widget.color)),
            if (ex.hint.isNotEmpty && widget.hints && !_hinted && !locked)
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Sfx.play('tap');
                    setState(() => _hinted = true);
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
                    decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lightbulb_rounded, size: 17, color: p.goldInk),
                      const SizedBox(width: 4),
                      Text(t('lesson.hint'), style: ts(13.5, w: FontWeight.w900, color: p.goldInk, height: 1.2)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
        if (question.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: MdBlock(question, style: ts(22, w: FontWeight.w800, color: p.ink, height: 1.3))),
        if (ex.say.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: listenBar()),
        if (_hinted)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.lightbulb_rounded, size: 19, color: p.goldInk)),
                const SizedBox(width: 8),
                Expanded(child: MdBlock(ex.hint, style: ts(15.5, w: FontWeight.w700, color: p.ink, height: 1.4))),
              ],
            ),
          ),
      ],
    );
  }

  Widget page(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final (i, c) in children.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 18), child: c)],
      );
}

/* ---------- info ---------- */

class _InfoState extends ExerciseViewState {
  late final String _intro = widget.host.pick(widget.host.voice.intro, widget.random);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return page([
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MascotView(widget.host.id, size: isCompact(context) ? 80 : 132, calm: true),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.line, width: 2),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_intro, style: ts(14, w: FontWeight.w800, color: widget.color)),
                  if (ex.text('title').isNotEmpty) MdInline(ex.text('title'), style: ts(19, w: FontWeight.w900, color: p.ink, height: 1.25)),
                ],
              ),
            ),
          ),
        ],
      ),
      TapCard(
        padding: const EdgeInsets.all(18),
        radius: 18,
        child: MdBlock(ex.text('body'), style: ts(18, w: FontWeight.w600, color: p.ink, height: 1.5), strong: widget.color),
      ),
      if (ex.say.isNotEmpty) listenBar(),
      if (ex.chart != null) Panel(padding: const EdgeInsets.all(14), child: ChartView(ex.chart!, locale: widget.locale)),
      if (ex.text('example').isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kicker(t('lesson.example'), color: p.goldInk),
              const SizedBox(height: 2),
              MdBlock(ex.text('example'), style: ts(16, color: p.ink)),
            ],
          ),
        ),
    ]);
  }
}

/* ---------- choice / multi ---------- */

class _OptionsState extends ExerciseViewState {
  _OptionsState(this.many);
  final bool many;

  late final List<String> _right = many ? ex.list('answers') : [ex.text('answer')];
  late final List<String> _opts = [..._right, ...ex.list('distractors')]..shuffle(widget.random);
  final _picked = <int>{};

  void _pick(int i) {
    if (locked) return;
    setState(() {
      if (many) {
        _picked.contains(i) ? _picked.remove(i) : _picked.add(i);
      } else {
        _picked
          ..clear()
          ..add(i);
      }
    });
    Sfx.play('tap');
    widget.onReady(_picked.isNotEmpty);
  }

  @override
  ExResult check() {
    setState(() => locked = true);
    final correct = _picked.length == _right.length &&
        _picked.map((i) => _opts[i]).toSet().length == _right.toSet().length &&
        _picked.every((i) => _right.contains(_opts[i]));
    return ExResult(correct: correct, answer: _right.join(' · '));
  }

  CardState _state(int i) {
    if (locked) return _right.contains(_opts[i]) ? CardState.good : (_picked.contains(i) ? CardState.bad : CardState.idle);
    return _picked.contains(i) ? CardState.selected : CardState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final grid = _opts.length.isEven && _opts.every((o) => o.length <= 16);
    Widget option(int i) {
      final s = _state(i);
      final c = TapCard.colors(p, s);
      final marked = s != CardState.idle;
      return TapCard(
        state: s,
        onTap: () => _pick(i),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: marked ? c.fg : p.line2, width: 2)),
              child: many
                  ? (marked && s != CardState.bad ? Icon(Icons.check_rounded, size: 18, color: c.fg) : null)
                  : Text('${i + 1}', style: ts(14, w: FontWeight.w900, color: marked ? c.fg : p.ink3, height: 1)),
            ),
            const SizedBox(width: 12),
            Expanded(child: MdInline(_opts[i], style: ts(17, w: FontWeight.w800, height: 1.3))),
          ],
        ),
      );
    }

    return page([
      head(ex.text('question')),
      if (grid)
        LayoutBuilder(
          builder: (_, box) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (var i = 0; i < _opts.length; i++) SizedBox(width: (box.maxWidth - 10) / 2, child: option(i))],
          ),
        )
      else
        Column(children: [for (var i = 0; i < _opts.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 10), child: option(i))]),
    ]);
  }
}

/* ---------- truefalse ---------- */

class _TrueFalseState extends ExerciseViewState {
  bool? _sel;
  bool get _answer => ex.data['answer'] as bool;

  void _pick(bool v) {
    if (locked) return;
    setState(() => _sel = v);
    Sfx.play('tap');
    widget.onReady(true);
  }

  @override
  ExResult check() {
    setState(() => locked = true);
    return ExResult(correct: _sel == _answer, answer: t(_answer ? 'lesson.true' : 'lesson.false'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget button(bool v) {
      final s = locked ? (v == _answer ? CardState.good : (_sel == v ? CardState.bad : CardState.idle)) : (_sel == v ? CardState.selected : CardState.idle);
      return Expanded(
        child: TapCard(
          state: s,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          radius: 18,
          onTap: () => _pick(v),
          child: Column(
            children: [
              Icon(v ? Icons.check_rounded : Icons.close_rounded, size: 34, color: v ? p.good : p.bad),
              const SizedBox(height: 4),
              Text(t(v ? 'lesson.true' : 'lesson.false'), style: ts(17, w: FontWeight.w900)),
            ],
          ),
        ),
      );
    }

    return page([
      head(),
      Panel(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22), child: MdBlock(ex.text('statement'), style: ts(21, w: FontWeight.w800, color: p.ink))),
      Row(children: [button(true), const SizedBox(width: 12), button(false)]),
    ]);
  }
}

/* ---------- fill ---------- */

class _FillState extends ExerciseViewState {
  late final _parts = fillParts(ex.text('text'));
  late final List<String> _blanks = [for (final p in _parts) if (p.blank) p.text];
  late final bool _typed = _blanks.length == 1 && ex.list('distractors').isEmpty;
  late final List<String> _chips = [..._blanks, ...ex.list('distractors')]..shuffle(widget.random);
  late final List<int?> _slots = List.filled(_blanks.length, null);
  int _activeSlot = 0;
  final _input = TextEditingController();
  bool? _typedOk;

  String get _full => _parts.map((p) => p.text).join();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _place(int chip) {
    if (locked || _slots.contains(chip)) return;
    final at = _activeSlot < _slots.length && _slots[_activeSlot] == null ? _activeSlot : _slots.indexOf(null);
    if (at < 0) return;
    setState(() {
      _slots[at] = chip;
      final next = _slots.indexOf(null);
      if (next >= 0) _activeSlot = next;
    });
    Sfx.play('tap');
    widget.onReady(!_slots.contains(null));
  }

  void _tapSlot(int slot) {
    if (locked) return;
    setState(() {
      _activeSlot = slot;
      _slots[slot] = null;
    });
    Sfx.play('tap');
    widget.onReady(!_slots.contains(null));
  }

  @override
  ExResult check() {
    if (_typed) {
      final m = compareAnswer(_input.text, [_blanks.first], locale: widget.locale);
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        locked = true;
        _typedOk = m != null;
      });
      return ExResult(correct: m != null, answer: _full, note: m != null && m.kind != MatchKind.exact ? t('lesson.spelling', {'answer': _blanks.first}) : null);
    }
    setState(() => locked = true);
    final correct = [for (var i = 0; i < _blanks.length; i++) same(_chips[_slots[i]!], _blanks[i])].every((ok) => ok);
    return ExResult(correct: correct, answer: _full);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final base = ts(20, w: FontWeight.w700, color: p.ink, height: 2.0);
    var blank = 0;
    final spans = <InlineSpan>[];
    for (final part in _parts) {
      if (!part.blank) {
        spans.addAll(mdSpans(part.text, p, style: base));
        continue;
      }
      final i = blank++;
      if (_typed) {
        final c = _typedOk == null ? (bg: p.primarySoft, border: p.primary, fg: p.ink) : TapCard.colors(p, _typedOk! ? CardState.good : CardState.bad);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            width: (_blanks.first.length * 13.0 + 40).clamp(72, 240).toDouble(),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: c.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), border: Border(bottom: BorderSide(color: c.border, width: 3))),
            child: TextField(
              controller: _input,
              enabled: !locked,
              autocorrect: false,
              enableSuggestions: false,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              style: ts(19, w: FontWeight.w800, color: c.fg, height: 1.2),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 6)),
              onChanged: (v) => widget.onReady(v.trim().isNotEmpty),
              onSubmitted: (v) => v.trim().isEmpty ? null : widget.onSubmit(),
            ),
          ),
        ));
        continue;
      }
      final chip = _slots[i];
      final s = chip == null ? CardState.idle : (locked ? (same(_chips[chip], _blanks[i]) ? CardState.good : CardState.bad) : CardState.selected);
      final c = TapCard.colors(p, s);
      final targeted = !locked && chip == null && _blanks.length > 1 && _activeSlot == i;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: () => _tapSlot(i),
          child: Container(
            constraints: const BoxConstraints(minWidth: 76, minHeight: 40),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: chip == null ? (targeted ? p.primarySoft.withValues(alpha: 0.5) : p.surface2) : c.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: chip == null ? (targeted ? p.primary : p.line2) : c.border, width: 2),
            ),
            child: MdInline(chip == null ? '' : _chips[chip], align: TextAlign.center, style: ts(18, w: FontWeight.w800, color: c.fg, height: 1.3)),
          ),
        ),
      ));
    }
    return page([
      head(ex.text('question')),
      Panel(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), child: Text.rich(TextSpan(children: spans), style: base)),
      if (!_typed)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _chips.length; i++)
              TapCard(
                state: _slots.contains(i) ? CardState.used : CardState.idle,
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                onTap: () => _place(i),
                child: MdInline(_chips[i], style: ts(17, w: FontWeight.w800, height: 1.3)),
              ),
          ],
        ),
    ]);
  }
}

/* ---------- type ---------- */

class _TypeState extends ExerciseViewState {
  final _input = TextEditingController();
  bool? _ok;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  ExResult check() {
    final m = compareAnswer(_input.text, [ex.text('answer'), ...ex.list('accept')], locale: widget.locale);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      locked = true;
      _ok = m != null;
    });
    return ExResult(correct: m != null, answer: ex.text('answer'), note: m != null && m.kind != MatchKind.exact ? t('lesson.spelling', {'answer': m.match}) : null);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = _ok == null ? (bg: p.surface, border: p.line2, fg: p.ink) : TapCard.colors(p, _ok! ? CardState.good : CardState.bad);
    OutlineInputBorder border(Color color) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: color, width: 2));
    return page([
      head(ex.text('question')),
      TextField(
        controller: _input,
        enabled: !locked,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        style: ts(19, color: c.fg),
        decoration: InputDecoration(
          hintText: t('lesson.typeHint'),
          hintStyle: ts(19, w: FontWeight.w600, color: p.ink3),
          filled: true,
          fillColor: c.bg,
          contentPadding: const EdgeInsets.all(16),
          enabledBorder: border(c.border),
          disabledBorder: border(c.border),
          focusedBorder: border(p.primary),
        ),
        onChanged: (v) => widget.onReady(v.trim().isNotEmpty),
        onSubmitted: (v) => v.trim().isEmpty ? null : widget.onSubmit(),
      ),
    ]);
  }
}

/* ---------- number: toleranslı ve birimli sayısal cevap ---------- */

class _NumberState extends ExerciseViewState {
  final _input = TextEditingController();
  bool? _ok;

  num get _answer => ex.data['answer'] as num;
  num get _tolerance => (ex.data['tolerance'] as num?) ?? 0;
  String get _unit => ex.text('unit');
  String _withUnit(num v) => [formatNumber(v, locale: widget.locale), if (_unit.isNotEmpty) _unit].join(' ');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  ExResult check() {
    final m = compareNumber(_input.text, _answer, tolerance: _tolerance, unit: _unit);
    final ok = m?.ok ?? false;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      locked = true;
      _ok = ok;
    });
    return ExResult(
      correct: ok,
      answer: _withUnit(_answer) + (_tolerance > 0 ? '  (± ${formatNumber(_tolerance, locale: widget.locale)})' : ''),
      note: ok && !m!.exact ? t('lesson.exactValue', {'answer': _withUnit(_answer)}) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = _ok == null ? (bg: p.surface, border: p.line2, fg: p.ink) : TapCard.colors(p, _ok! ? CardState.good : CardState.bad);
    OutlineInputBorder border(Color color) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: color, width: 2));
    return page([
      head(ex.text('question')),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !locked,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-−/eE ]'))],
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              style: ts(24, w: FontWeight.w900, color: c.fg, height: 1.2),
              decoration: InputDecoration(
                hintText: t('lesson.numberHint'),
                hintStyle: ts(19, w: FontWeight.w600, color: p.ink3),
                filled: true,
                fillColor: c.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                enabledBorder: border(c.border),
                disabledBorder: border(c.border),
                focusedBorder: border(p.primary),
              ),
              onChanged: (v) => widget.onReady(parseNumbers(v, unit: _unit).isNotEmpty),
              onSubmitted: (v) => parseNumbers(v, unit: _unit).isEmpty ? null : widget.onSubmit(),
            ),
          ),
          if (_unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: MdInline(_unit, style: ts(21, w: FontWeight.w900, color: p.ink2, height: 1.2)),
              ),
            ),
        ],
      ),
    ]);
  }
}

/* ---------- match ---------- */

class _MatchState extends ExerciseViewState {
  late final _pairs = ex.pairs;
  late final List<int> _left = List.generate(_pairs.length, (i) => i)..shuffle(widget.random);
  late final List<int> _right = List.generate(_pairs.length, (i) => i)..shuffle(widget.random);
  int? _selL, _selR, _badL, _badR;
  final _matched = <int>{};
  int _mistakes = 0;

  void _tap(bool left, int pair) {
    if (_matched.contains(pair)) return;
    Sfx.play('tap');
    setState(() {
      _badL = _badR = null;
      if (left) {
        _selL = _selL == pair ? null : pair;
      } else {
        _selR = _selR == pair ? null : pair;
      }
    });
    final a = _selL, b = _selR;
    if (a == null || b == null) return;
    setState(() {
      _selL = _selR = null;
      if (a == b) {
        _matched.add(a);
      } else {
        _mistakes++;
        _badL = a;
        _badR = b;
      }
    });
    if (a != b) return Sfx.buzz();
    Sfx.play('pop');
    if (_matched.length == _pairs.length) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        widget.onDone(ExResult(
          correct: _mistakes < 2,
          message: _mistakes >= 2 ? t('lesson.matchFail', {'n': _mistakes}) : null,
          note: _mistakes == 1 ? t('lesson.matchOne') : null,
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget column(bool left) => Expanded(
          child: Column(
            children: [
              for (final (n, i) in (left ? _left : _right).indexed)
                Padding(
                  padding: EdgeInsets.only(top: n == 0 ? 0 : 10),
                  child: TapCard(
                    state: _matched.contains(i)
                        ? CardState.matched
                        : (left ? _badL : _badR) == i
                            ? CardState.bad
                            : (left ? _selL : _selR) == i
                                ? CardState.selected
                                : CardState.idle,
                    onTap: () => _tap(left, i),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Center(child: MdInline(_pairs[i][left ? 0 : 1], align: TextAlign.center, style: ts(16, w: FontWeight.w800, height: 1.25))),
                    ),
                  ),
                ),
            ],
          ),
        );
    return page([
      head(ex.text('question')),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [column(true), const SizedBox(width: 12), column(false)]),
    ]);
  }
}

/* ---------- order / build: parçaları sıraya koyma ---------- */

class _ArrangeState extends ExerciseViewState {
  _ArrangeState(this.vertical);
  final bool vertical; // order: alt alta, numaralı; build: yan yana, çeldiricili

  late final List<String> _tokens = vertical ? ex.list('items') : ex.list('answer');
  late final List<String> _pool = shuffledDifferent([..._tokens, if (!vertical) ...ex.list('distractors')], widget.random);
  final _placed = <int>[]; // havuzdaki sıra numaraları
  bool _correct = false;

  void _add(int i) {
    if (locked || _placed.contains(i)) return;
    setState(() => _placed.add(i));
    Sfx.play('tap');
    widget.onReady(vertical ? _placed.length == _pool.length : true);
  }

  void _remove(int i) {
    if (locked) return;
    setState(() => _placed.remove(i));
    Sfx.play('tap');
    widget.onReady(vertical ? false : _placed.isNotEmpty);
  }

  void _move(int from, int to) {
    if (locked || from == to || from < 0 || from >= _placed.length || to < 0 || to >= _placed.length) return;
    setState(() {
      final item = _placed.removeAt(from);
      _placed.insert(to, item);
    });
    Sfx.play('tap');
  }

  @override
  ExResult check() {
    final got = [for (final i in _placed) _pool[i]];
    final ok = (got.length == _tokens.length && [for (var i = 0; i < got.length; i++) same(got[i], _tokens[i])].every((x) => x)) ||
        ex.list('accept').any((a) => same(a, got.join(' ')));
    setState(() {
      locked = true;
      _correct = ok;
    });
    return ExResult(correct: ok, answer: vertical ? [for (final (i, x) in _tokens.indexed) '${i + 1}. $x'].join('\n') : _tokens.join(' '));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget chip(int i, {required bool placed, int n = 0}) {
      final state = placed
          ? (locked ? (_correct || (n < _tokens.length && same(_pool[i], _tokens[n])) ? CardState.good : CardState.bad) : CardState.idle)
          : (_placed.contains(i) ? CardState.used : CardState.idle);
      final label = MdInline(_pool[i], style: ts(17, w: FontWeight.w800, height: 1.3));
      final card = TapCard(
        state: state,
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        onTap: () => placed ? _remove(i) : _add(i),
        child: vertical && placed
            ? Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(8)),
                  child: Text('${n + 1}', style: ts(13, w: FontWeight.w900, color: p.primaryInk, height: 1)),
                ),
                const SizedBox(width: 10),
                Expanded(child: label),
                if (!locked && _placed.length > 1) Icon(Icons.drag_indicator_rounded, size: 18, color: p.ink3),
              ])
            : label,
      );
      if (!placed || locked || _placed.length < 2) return card;
      return DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != n,
        onAcceptWithDetails: (d) => _move(d.data, n),
        builder: (_, candidate, _) => LongPressDraggable<int>(
          data: n,
          delay: const Duration(milliseconds: 140),
          feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.85, child: card)),
          childWhenDragging: Opacity(opacity: 0.35, child: card),
          child: AnimatedScale(scale: candidate.isNotEmpty ? 1.03 : 1.0, duration: const Duration(milliseconds: 120), child: card),
        ),
      );
    }

    final answer = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line2, width: 2)),
      child: _placed.isEmpty
          ? Padding(padding: const EdgeInsets.all(8), child: Text(t(vertical ? 'lesson.orderHint' : 'lesson.buildHint'), style: ts(15, color: p.ink3)))
          : vertical
              ? Column(children: [for (final (n, i) in _placed.indexed) Padding(padding: EdgeInsets.only(top: n == 0 ? 0 : 8), child: chip(i, placed: true, n: n))])
              : Wrap(spacing: 8, runSpacing: 8, children: [for (final (n, i) in _placed.indexed) chip(i, placed: true, n: n)]),
    );
    final remaining = [for (var i = 0; i < _pool.length; i++) if (!vertical || !_placed.contains(i)) i];
    return page([
      head(ex.text('question')),
      answer,
      vertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final (n, i) in remaining.indexed) Padding(padding: EdgeInsets.only(top: n == 0 ? 0 : 10), child: chip(i, placed: false))],
            )
          : Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [for (final i in remaining) chip(i, placed: false)]),
    ]);
  }
}

/* ---------- categorize ---------- */

class _CategorizeState extends ExerciseViewState {
  late final _cats = ex.categories;
  late final List<({String text, int cat})> _items = [
    for (final (ci, c) in _cats.indexed)
      for (final it in c.items) (text: it, cat: ci),
  ]..shuffle(widget.random);
  late final List<List<({String text, bool ok})>> _placed = List.generate(_cats.length, (_) => []);
  int _at = 0, _mistakes = 0;
  int? _hint; // yanlışta doğru grubu kısa süre vurgula

  void _drop(int cat) {
    if (_at >= _items.length) return;
    final item = _items[_at];
    final ok = cat == item.cat;
    setState(() {
      _placed[item.cat].add((text: item.text, ok: ok));
      if (!ok) {
        _mistakes++;
        _hint = item.cat;
      } else {
        _hint = null;
      }
      _at++;
    });
    ok ? Sfx.play('pop') : Sfx.buzz();
    if (_at < _items.length) return;
    Future.delayed(Duration(milliseconds: ok ? 350 : 800), () {
      if (!mounted) return;
      widget.onDone(ExResult(
        correct: _mistakes < 2,
        message: _mistakes >= 2 ? t('lesson.catFail', {'n': _mistakes}) : null,
        note: _mistakes == 1 ? t('lesson.catOne') : null,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final done = _at >= _items.length;
    Widget bucket(int ci) => DragTarget<int>(
          onWillAcceptWithDetails: (_) => !done,
          onAcceptWithDetails: (_) => _drop(ci),
          builder: (_, candidate, _) {
            final hover = candidate.isNotEmpty;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _drop(ci),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minHeight: 124),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: _hint == ci ? p.goodSoft : (hover ? p.primarySoft : p.surface),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _hint == ci ? p.good : (hover ? p.primary : p.line2), width: 2),
                ),
                child: Column(
                  children: [
                    MdInline(_cats[ci].name, align: TextAlign.center, style: ts(15, w: FontWeight.w900, color: widget.color, height: 1.25)),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final it in _placed[ci])
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: it.ok ? p.goodSoft : p.badSoft, borderRadius: BorderRadius.circular(8)),
                            child: MdInline(it.text, style: ts(13, w: FontWeight.w800, color: it.ok ? p.goodInk : p.badInk)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
    final activeCard = TapCard(
      state: done ? CardState.good : CardState.idle,
      radius: 20,
      depth: 5,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Center(
        child: done ? Icon(Icons.check_rounded, color: p.good, size: 30) : MdInline(_items[_at].text, align: TextAlign.center, style: ts(21, w: FontWeight.w900, height: 1.3)),
      ),
    );
    return page([
      head(ex.text('question')),
      Column(
        children: [
          Text(done ? '' : '${_at + 1} / ${_items.length}', style: ts(13, w: FontWeight.w900, color: p.ink3)),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.7,
            child: done
                ? activeCard
                : Draggable<int>(
                    data: _at,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(width: 220, child: Opacity(opacity: 0.9, child: activeCard)),
                    ),
                    childWhenDragging: Opacity(opacity: 0.35, child: activeCard),
                    child: activeCard,
                  ),
          ),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var ci = 0; ci < _cats.length; ci++) ...[if (ci > 0) const SizedBox(width: 10), Expanded(child: bucket(ci))],
        ],
      ),
    ]);
  }
}

/* ---------- flashcard ---------- */

class _FlashState extends ExerciseViewState with SingleTickerProviderStateMixin {
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  bool _seen = false;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggle() {
    Sfx.play('flip');
    setState(() => _seen = true);
    _flip.status == AnimationStatus.completed || _flip.status == AnimationStatus.forward ? _flip.reverse() : _flip.forward();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget face(String text, {required bool back}) => TapCard(
          state: back ? CardState.selected : CardState.idle,
          radius: 22,
          depth: 6,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 190),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MdBlock(text, align: CrossAxisAlignment.center, style: ts(21, w: FontWeight.w800, color: p.ink)),
                if (!back) Padding(padding: const EdgeInsets.only(top: 14), child: Kicker(t('lesson.flipHint'))),
              ],
            ),
          ),
        );
    return page([
      head(),
      GestureDetector(
        onTap: _toggle,
        child: AnimatedBuilder(
          animation: _flip,
          builder: (_, _) {
            final angle = Curves.easeInOut.transform(_flip.value) * pi;
            final back = angle > pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(back ? angle - pi : angle),
              child: face(back ? ex.text('back') : ex.text('front'), back: back),
            );
          },
        ),
      ),
      AnimatedOpacity(
        opacity: _seen ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_seen,
          child: Row(
            children: [
              Expanded(child: ChunkyButton(label: t('lesson.again'), kind: ButtonKind.ghost, onPressed: () => widget.onDone(const ExResult(correct: false, soft: true)))),
              const SizedBox(width: 12),
              Expanded(child: ChunkyButton(label: t('lesson.knew'), kind: ButtonKind.good, onPressed: () => widget.onDone(const ExResult(correct: true, soft: true)))),
            ],
          ),
        ),
      ),
    ]);
  }
}
