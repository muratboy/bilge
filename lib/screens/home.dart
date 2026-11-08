/// Ana kabuk (alt menü) ve "Öğren" sekmesi: kursun kıvrılan yolu.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/schema.dart';
import '../core/store.dart';
import '../l10n/l10n.dart';
import '../lesson/lesson_screen.dart';
import '../mascot/cast.dart';
import '../mascot/mascot_art.dart';
import '../mascot/mascot_view.dart';
import '../ui/sfx.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'manage.dart';
import 'profile.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget item(int i, IconData icon, String label) {
      final on = _tab == i;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkResponse(
            onTap: () => setState(() => _tab = i),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  decoration: BoxDecoration(color: on ? p.primarySoft : null, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 26, color: on ? p.primaryInk : p.ink3),
                ),
                Text(
                  label,
                  style: ts(12, w: FontWeight.w800, color: on ? p.primaryInk : p.ink3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: p.surface,
        systemNavigationBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: switch (_tab) {
            0 => LearnScreen(onOpenCourses: () => setState(() => _tab = 1)),
            1 => CoursesScreen(onOpenLearn: () => setState(() => _tab = 0)),
            _ => const ProfileScreen(),
          },
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.line, width: 2)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 66,
              child: Row(children: [item(0, Icons.home_rounded, t('nav.learn')), item(1, Icons.school_rounded, t('nav.courses')), item(2, Icons.person_rounded, t('nav.profile'))]),
            ),
          ),
        ),
      ),
    );
  }
}

/* ================= Öğren ================= */

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key, required this.onOpenCourses});
  final VoidCallback onOpenCourses;
  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final _currentKey = GlobalKey();
  final _scroll = ScrollController();
  String? _shownCourse;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Kurs açıldığında ya da ders/sınav bittiğinde sıradaki derse kaydır.
  void _scrollToCurrent({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _currentKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.45,
          duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        );
      } else if (_scroll.hasClients && _scroll.position.pixels < _scroll.position.maxScrollExtent) {
        final step = math.max(300.0, _scroll.position.viewportDimension * 0.8);
        _scroll.jumpTo(math.min(_scroll.position.pixels + step, _scroll.position.maxScrollExtent));
        _scrollToCurrent(animate: animate);
      }
    });
  }

  void _openNode(AppState app, Course course, PathNode node, NodeStatus status, Color color) {
    final p = context.p;
    final host = app.hostOf(node);
    final locked = status == NodeStatus.locked;
    final sub = node.kind == NodeKind.review
        ? t('learn.reviewSub')
        : t('learn.lessonSub', {'i': node.lessonIndex + 1, 'n': node.unit!.lessons.length, 'steps': node.lesson!.exercises.length});
    // Sınavla geçilmiş ders henüz oynanmamıştır: ilk oynayışta tam puan verir
    final played = (app.progressOf(course.id).lessons[node.id]?.plays ?? 0) > 0;
    final xp = played ? 5 : (node.kind == NodeKind.review ? 15 : 10);
    Sfx.play('tap');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: locked ? p.surface : color,
      // Yan çevrilmiş telefonda pencere ekranın yarısına sığmaz: yükseklik serbest, içerik gerekirse kayar
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => sheetBody(
        sheet,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        scroll: [
          Row(
            children: [
              MascotView(host.id, mood: locked ? Mood.think : Mood.happy, size: 128),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.label,
                      style: ts(20, w: FontWeight.w900, color: locked ? p.ink : Colors.white, height: 1.2),
                    ),
                    Text(sub, style: ts(14.5, color: locked ? p.ink2 : Colors.white.withValues(alpha: 0.92))),
                    Text(
                      t('learn.hostedBy', {'name': host.name}),
                      style: ts(13.5, w: FontWeight.w800, color: locked ? p.ink3 : Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (locked)
            Row(
              children: [
                Icon(Icons.lock_rounded, color: p.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('learn.locked'),
                    style: ts(16, w: FontWeight.w800, color: p.ink2),
                  ),
                ),
              ],
            )
          else
            ChunkyButton(
              label: t(played ? 'learn.replayXp' : 'learn.startXp', {'xp': xp}),
              kind: ButtonKind.light,
              color: color,
              onPressed: () {
                Navigator.of(sheet).pop();
                // Sıradaki ders tamamlandığında ya da kısım bittiğinde yol yeni hedefe kayar
                LessonScreen.open(context, course, node).then((_) {
                  if (status == NodeStatus.current || app.isFinished(course)) _scrollToCurrent(animate: true);
                });
              },
            ),
        ],
      ),
    );
  }

  /// "Sınavla geç": üniteyi (ve bitmemiş önceki üniteleri) bilen kullanıcı kısa bir sınavla atlar.
  void _startExam(AppState app, Course course, int unitIndex) {
    final unit = course.units[unitIndex];
    final covered = app.examUnits(course, unitIndex).length;
    final questions = app.examItems(course, unitIndex).length;
    final args = {'n': questions, 'm': AppState.examAllowance(questions), 'k': covered};
    Sfx.play('tap');
    showBilgeDialog(
      context,
      title: t('learn.examTitle', {'unit': unit.title}),
      text: t(covered > 1 ? 'learn.examTextMany' : 'learn.examText', args),
      actions: [
        DialogAction(
          t('learn.examStart'),
          onPressed: () => LessonScreen.open(
            context,
            course,
            PathNode(kind: NodeKind.exam, id: '${unit.id}/~sinav', title: '', unitIndex: unitIndex, unit: unit),
          ).then((_) => _scrollToCurrent(animate: true)),
        ),
        DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
      ],
    );
  }

  /// Kurs değiştirici: yalnızca seçili kurs ve en son çalışılanlar görünür; gerisi "Kurslar" sekmesindedir.
  void _switchCourse(AppState app, Course course) {
    final recent = app.recentCourses(5);
    final sections = course.group.isEmpty ? const <Course>[] : app.sectionsOf(course.group);
    if (recent.length < 2 && sections.length < 2) return widget.onOpenCourses();
    final p = context.p;
    Sfx.play('tap');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => sheetBody(
        sheet,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        head: [
        Text(
          t('learn.switch'),
          style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25),
        ),
        const SizedBox(height: 12),
      ],
      scroll: [
        for (final c in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TapCard(
              key: ValueKey('switch-${c.id}'),
              state: c.id == course.id ? CardState.selected : CardState.idle,
              onTap: () {
                Navigator.of(sheet).pop();
                app.selectCourse(c.id);
              },
              child: Row(
                children: [
                  Text(c.emoji.isEmpty ? '📘' : c.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.group.isNotEmpty)
                          Text(
                            upper(c.group),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(12, w: FontWeight.w900, color: p.ink3, spacing: 0.8),
                          ),
                        Text(
                          sectionTitle(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(16, w: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${(app.percent(c) * 100).round()}%', style: ts(14, w: FontWeight.w900)),
                ],
              ),
            ),
          ),
      ],
      foot: [
        const SizedBox(height: 4),
        if (sections.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyButton(
              label: t('learn.sections'),
              icon: Icons.layers_rounded,
              kind: ButtonKind.ghost,
              onPressed: () {
                Navigator.of(sheet).pop();
                GroupScreen.open(context, course.group);
              },
            ),
          ),
        ChunkyButton(
          label: t('learn.allCourses'),
          kind: ButtonKind.ghost,
          onPressed: () {
            Navigator.of(sheet).pop();
            widget.onOpenCourses();
          },
        ),
        ],
      ),
    );
  }

  void _showNotes(Unit unit) {
    Sfx.play('tap');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => _UnitNotesSheet(sheetContext: sheet, unit: unit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final course = app.currentCourse;
    if (course == null) return _Empty(app: app);
    final p = context.p;
    final status = app.statusOf(course);
    final curNode = status.entries.where((e) => e.value == NodeStatus.current).firstOrNull?.key;
    final target = '${course.id}:${curNode ?? 'done'}';
    if (_shownCourse != target) {
      final animate = _shownCourse != null && _shownCourse!.startsWith('${course.id}:');
      _shownCourse = target;
      _scrollToCurrent(animate: animate);
    }
    final prog = app.progressOf(course.id);
    final nodes = app.nodes(course);
    var serial = 0; // yol boyunca süren kıvrım için
    final nodeX = <String, double>{
      for (final n in nodes) n.id: (math.sin(serial++ * 0.85) * 62).roundToDouble(),
    };

    Widget node(PathNode n, int indexInUnit, Color color) {
      final st = status[n.id]!;
      final stars = prog.lessons[n.id]?.stars ?? 0;
      final skipped = (prog.lessons[n.id]?.plays ?? 1) == 0; // sınavla geçildi, henüz oynanmadı
      final x = nodeX[n.id] ?? 0;
      final locked = st == NodeStatus.locked;
      final fill = locked ? p.line : (stars == 3 ? Palette.gold : color);
      final edge = locked ? p.line2 : (stars == 3 ? Palette.goldD : Palette.darken(color));
      final icon = locked
          ? Icons.lock_rounded
          : (n.kind == NodeKind.review ? Icons.emoji_events_rounded : (st == NodeStatus.done ? (skipped ? Icons.fast_forward_rounded : Icons.check_rounded) : Icons.star_rounded));
      final innerCircle = Container(
        width: 74,
        height: 66,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(Radius.elliptical(37, 33)),
          boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 8))],
        ),
        child: Icon(icon, color: locked ? p.ink3 : Colors.white, size: 32),
      );
      final button = Semantics(
        button: true,
        label: n.label,
        child: GestureDetector(
          key: ValueKey('node-${n.id}'),
          onTap: () => _openNode(app, course, n, st, color),
          child: st == NodeStatus.current
              ? _PulseRing(color: color, child: innerCircle)
              : Container(padding: const EdgeInsets.all(6), child: innerCircle),
        ),
      );
      final host = hostOfUnit(n.unitIndex, app.buddy.id);
      return Padding(
        key: st == NodeStatus.current ? _currentKey : null,
        padding: const EdgeInsets.only(bottom: 14),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(x, 0),
              child: Column(
                children: [
                  if (st == NodeStatus.current)
                    GestureDetector(
                      onTap: () => _openNode(app, course, n, st, color),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.line, width: 2),
                        ),
                        child: Text(
                          upper(t('learn.start')),
                          style: ts(14, w: FontWeight.w900, color: color, spacing: 1),
                        ),
                      ),
                    ),
                  button,
                  if (st == NodeStatus.done && !skipped)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (var k = 0; k < 3; k++) Icon(Icons.star_rounded, size: 17, color: k < stars ? Palette.gold : p.line2)],
                    ),
                ],
              ),
            ),
            // Ünitenin sunucusu yolun kenarında durur
            if (indexInUnit == 1)
              Align(
                alignment: Alignment(x > 0 ? -0.82 : 0.82, 0),
                child: _Buddy(host, size: 132, bubble: x > 0 ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd),
              ),
          ],
        ),
      );
    }

    final planned = course.outline.skip(course.units.length).toList();
    final due = app.dueTotal; // bütün kurslarda bugün tekrar edilecekler
    // Kurs bir grubun kısmıysa ve bittiyse sıradaki kısım önerilir
    final finished = app.isFinished(course);
    final next = finished ? app.nextSection(course) : null;
    final groupDone = finished && next == null && course.group.isNotEmpty && app.sectionsOf(course.group).length > 1;
    final savedSession = app.session?.courseId == course.id ? app.session : null;
    final resumeNode = savedSession == null ? null : app.nodeForSession(course, savedSession);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            // Sabit üst çubuk: yol kayarken kurs seçici, kart tarayıcısı, seri ve günlük hedef görünür kalır
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(bottom: BorderSide(color: p.line.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TapCard(
                        key: const ValueKey('course-chip'),
                        onTap: () => _switchCourse(app, course),
                        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                        radius: 14,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(course.emoji.isEmpty ? '📘' : course.emoji, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                course.title,
                                overflow: TextOverflow.ellipsis,
                                style: ts(16, w: FontWeight.w800, color: p.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconTap(
                    key: const ValueKey('cards-btn'),
                    icon: Icons.style_rounded,
                    label: t('learn.cards'),
                    color: p.ink2,
                    onTap: () => CardsScreen.open(context, course),
                  ),
                  const SizedBox(width: 6),
                  _Pill(icon: Icons.local_fire_department_rounded, color: app.streak > 0 ? Palette.fire : p.ink3, text: '${app.streak}', label: t('learn.streak')),
                  const SizedBox(width: 8),
                  _GoalRing(value: app.todayXp / math.max(1, app.settings.dailyGoal), text: '${app.todayXp}/${app.settings.dailyGoal}', label: t('learn.todayXp')),
                ],
              ),
            ),
            if (savedSession != null && resumeNode != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Panel(
                  key: const ValueKey('resume-banner'),
                  color: p.primarySoft,
                  border: p.primary,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Kicker(t('learn.resumeTitle'), color: p.primaryInk),
                      const SizedBox(height: 2),
                      Text(
                        t('learn.resumeText', {
                          'title': resumeNode.label.isEmpty ? course.title : resumeNode.label,
                          'done': savedSession.done,
                          'total': savedSession.done + savedSession.queueKeys.length,
                        }),
                        style: ts(14.5, w: FontWeight.w800, color: p.ink),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChunkyButton(
                              label: t('learn.resumeBtn'),
                              icon: Icons.play_arrow_rounded,
                              onPressed: () => LessonScreen.open(context, course, resumeNode, resume: savedSession)
                                  .then((_) => _scrollToCurrent(animate: true)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => app.saveSession(null),
                            child: Text(t('learn.resumeDiscard'), style: ts(14, w: FontWeight.w800, color: p.ink3)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  ListView(
                    controller: _scroll,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(10000),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    children: [
                      for (final (ui, unit) in course.units.indexed) ...[
                        SizedBox(height: ui == 0 ? 10 : 22),
                        _UnitBanner(
                          index: ui,
                          unit: unit,
                          host: hostOfUnit(ui, app.buddy.id),
                          onNotes: unit.lessons.any((l) => l.exercises.any((e) => e.type == 'info')) ? () => _showNotes(unit) : null,
                          onExam: app.canTestOut(course, ui) ? () => _startExam(app, course, ui) : null,
                        ),
                        const SizedBox(height: 22),
                        for (final (i, n) in nodes.where((n) => n.unitIndex == ui).indexed)
                          node(n, i, Palette.unitColor(ui)),
                      ],
                      const SizedBox(height: 10),
                      if (app.percent(course) == 1) ...[
                        Center(child: _Buddy(app.buddy, mood: Mood.cheer, size: 184)),
                        Padding(
                          key: next == null ? _currentKey : null,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            groupDone ? t('learn.groupDone', {'group': course.group}) : t(next != null ? 'learn.sectionDone' : (planned.isEmpty ? 'learn.allDone' : 'learn.soFarDone')),
                            textAlign: TextAlign.center,
                            style: ts(20, w: FontWeight.w900, color: p.ink),
                          ),
                        ),
                      ],
                      if (next != null)
                        Padding(
                          key: _currentKey,
                          padding: const EdgeInsets.only(top: 4, bottom: 14),
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Kicker('${course.group} · ${t('learn.nextSection')}'),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(next.emoji.isEmpty ? '📘' : next.emoji, style: const TextStyle(fontSize: 26)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        sectionTitle(next),
                                        style: ts(19, w: FontWeight.w900, color: p.ink, height: 1.25),
                                      ),
                                    ),
                                  ],
                                ),
                                if (next.description.isNotEmpty) Text(next.description, style: ts(14.5, color: p.ink2)),
                                const SizedBox(height: 12),
                                ChunkyButton(label: t('learn.nextSectionGo'), icon: Icons.arrow_forward_rounded, onPressed: () => app.selectCourse(next.id)),
                              ],
                            ),
                          ),
                        ),
                      if (planned.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: p.line2, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('learn.plannedHint', {'done': course.units.length, 'total': course.outline.length}),
                                style: ts(15.5, w: FontWeight.w800, color: p.ink),
                              ),
                              const SizedBox(height: 8),
                              Kicker(t('learn.planned')),
                              for (final title in planned.take(5)) Text('• $title', style: ts(15.5, color: p.ink2)),
                              if (planned.length > 5) Text('• …', style: ts(15.5, color: p.ink2)),
                            ],
                          ),
                        ),
                      Center(
                        child: ChunkyButton(
                          label: t(planned.isEmpty ? 'learn.addUnit' : 'learn.addNext'),
                          icon: Icons.add_rounded,
                          kind: ButtonKind.ghost,
                          expand: false,
                          onPressed: () => CreateScreen.open(context, target: course, startOnImport: planned.isNotEmpty),
                        ),
                      ),
                    ],
                  ),
                  // Vadesi gelen soru varsa (hangi kursta olursa olsun) günün tekrarı; yoksa bu kursta serbest pratik
                  if (due > 0 || app.hasPractice(course))
                    Positioned(
                      right: 16,
                      bottom: 14,
                      child: TapCard(
                        key: const ValueKey('review-pill'),
                        radius: 99,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        onTap: () => LessonScreen.open(context, course, PathNode(kind: due > 0 ? NodeKind.daily : NodeKind.practice, id: '', title: '')),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fitness_center_rounded, size: 20, color: p.primaryInk),
                            const SizedBox(width: 8),
                            Text(
                              upper(t(due > 0 ? 'learn.daily' : 'learn.practice')),
                              style: ts(14, w: FontWeight.w900, color: p.primaryInk, spacing: 0.7),
                            ),
                            if (due > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: p.bad, borderRadius: BorderRadius.circular(99)),
                                child: Text(
                                  '$due',
                                  style: ts(12, w: FontWeight.w900, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Sıradaki düğümün etrafında nefes alan halka (testlerde sabit kalır).
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (MascotView.animate) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl == null) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.elliptical(50, 46)),
          border: Border.all(color: widget.color.withValues(alpha: 0.3), width: 5),
        ),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (_, child) {
        final v = _ctrl!.value;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.elliptical(50, 46)),
            border: Border.all(color: widget.color.withValues(alpha: 0.22 + 0.38 * v), width: 5),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Ünite özeti el kitabı: arama çubuğu ve açılır/kapanır ders notları.
class _UnitNotesSheet extends StatefulWidget {
  const _UnitNotesSheet({required this.sheetContext, required this.unit});
  final BuildContext sheetContext;
  final Unit unit;

  @override
  State<_UnitNotesSheet> createState() => _UnitNotesSheetState();
}

class _UnitNotesSheetState extends State<_UnitNotesSheet> {
  String _query = '';
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final q = _query.trim().toLowerCase();
    final lessons = [
      for (final l in widget.unit.lessons)
        (
          lesson: l,
          notes: [
            for (final e in l.exercises)
              if (e.type == 'info' &&
                  (q.isEmpty ||
                      l.title.toLowerCase().contains(q) ||
                      e.text('title').toLowerCase().contains(q) ||
                      e.text('body').toLowerCase().contains(q) ||
                      e.text('example').toLowerCase().contains(q)))
                e,
          ],
        ),
    ].where((x) => x.notes.isNotEmpty).toList();

    return sheetBody(
      widget.sheetContext,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      head: [
        Text(
          '${widget.unit.title} · ${t('learn.summary')}',
          style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25),
        ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          style: ts(15, w: FontWeight.w700, color: p.ink),
          decoration: InputDecoration(
            hintText: t('notes.search'),
            prefixIcon: Icon(Icons.search_rounded, color: p.ink3),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
      ],
      scroll: [
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(t('notes.none'), textAlign: TextAlign.center, style: ts(15, color: p.ink3)),
          ),
        for (final item in lessons) ...[
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              if (!_collapsed.add(item.lesson.id)) _collapsed.remove(item.lesson.id);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Kicker(item.lesson.title)),
                  Icon(
                    _collapsed.contains(item.lesson.id) ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                    color: p.ink3,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed.contains(item.lesson.id))
            for (final e in item.notes)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.text('title').isNotEmpty)
                      Text(
                        e.text('title'),
                        style: ts(16, w: FontWeight.w900, color: p.ink),
                      ),
                    MdBlock(
                      e.text('body'),
                      style: ts(15.5, w: FontWeight.w600, color: p.ink),
                    ),
                    if (e.text('example').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: MdBlock(e.text('example'), style: ts(14.5, color: p.ink2)),
                      ),
                  ],
                ),
              ),
        ],
      ],
      foot: [
        const SizedBox(height: 8),
        ChunkyButton(
          label: t('common.close'),
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.of(widget.sheetContext).pop(),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.color, required this.text, required this.label});
  final IconData icon;
  final Color color;
  final String text, label;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 2),
        Text(
          text,
          style: ts(16, w: FontWeight.w900, color: color),
        ),
      ],
    ),
  );
}

/// Günlük XP hedefi: halka dolunca hedef tutmuş demektir.
class _GoalRing extends StatelessWidget {
  const _GoalRing({required this.value, required this.text, required this.label});
  final double value;
  final String text, label;
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final met = value >= 1;
    return Tooltip(
      message: label,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: value.clamp(0, 1).toDouble(), strokeWidth: 4, backgroundColor: p.line, color: Palette.gold, strokeCap: StrokeCap.round),
                Icon(met ? Icons.check_rounded : Icons.bolt_rounded, size: 17, color: Palette.gold),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: ts(15, w: FontWeight.w900, color: p.goldInk),
          ),
        ],
      ),
    );
  }
}

class _UnitBanner extends StatelessWidget {
  const _UnitBanner({required this.index, required this.unit, required this.host, this.onNotes, this.onExam});
  final int index;
  final Unit unit;
  final Character host;
  final VoidCallback? onNotes, onExam;

  @override
  Widget build(BuildContext context) {
    final color = Palette.unitColor(index);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Palette.darken(color, 0.28), offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  upper('${t('learn.unit', {'n': index + 1})} · ${t('learn.hostedBy', {'name': host.name})}'),
                  style: ts(12.5, w: FontWeight.w900, color: Colors.white.withValues(alpha: 0.85), spacing: 0.8),
                ),
                Text(
                  '${unit.emoji.isEmpty ? '' : '${unit.emoji} '}${unit.title}',
                  style: ts(21, w: FontWeight.w900, color: Colors.white, height: 1.2),
                ),
                if (unit.description.isNotEmpty) Text(unit.description, style: ts(14.5, color: Colors.white.withValues(alpha: 0.92))),
                if (onExam != null)
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      key: ValueKey('exam-${unit.id}'),
                      onTap: onExam,
                      child: Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 5),
                            Text(
                              upper(t('learn.testOut')),
                              style: ts(12.5, w: FontWeight.w900, color: Colors.white, spacing: 0.6, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onNotes != null)
            GestureDetector(
              onTap: onNotes,
              child: Container(
                margin: const EdgeInsets.only(left: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.description_rounded, color: Colors.white, size: 22),
                    Text(
                      upper(t('learn.summary')),
                      style: ts(11.5, w: FontWeight.w900, color: Colors.white, spacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Öğrenme ekranındaki maskot: dokununca bir imza hareketi yapar ve kendi ağzından bir şey söyler.
/// Söz, maskotun başının üstünde kısa bir süre duran bir balonda görünür. Balon ekranın üst katmanında çizilir ve
/// maskotu izler: listenin satırları kendi sınırlarının dışına taşan çizimi göstermez.
class _Buddy extends StatefulWidget {
  const _Buddy(this.character, {required this.size, this.mood = Mood.happy, this.bubble = AlignmentDirectional.center});
  final Character character;
  final double size;
  final Mood mood;

  /// Balon maskotun hangi kenarına yaslanır: ekranın kenarında duran maskotta balon içeri doğru açılır.
  final AlignmentDirectional bubble;

  @override
  State<_Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<_Buddy> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  String _line = '';
  bool _shown = false;
  bool _below = false; // başının üstünde yer yoksa balon ayaklarının altında açılır
  int _next = 0;
  Timer? _hide;

  void _poke() {
    // Sözler sırayla gelir: aynı söz üst üste söylenmez
    final lines = widget.character.voice.poke;
    // Maskot ekranın tepesine yakınsa (yol yukarı kaydırılmışsa) balon üstte kesilirdi
    final box = context.findRenderObject();
    final top = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero).dy : double.infinity;
    Sfx.play('pop');
    _line = lines[_next++ % lines.length];
    _shown = true;
    _below = top < MediaQuery.paddingOf(context).top + 150;
    if (_entry == null) {
      _entry = OverlayEntry(builder: _bubble);
      Overlay.of(context).insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      _shown = false;
      _entry?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _entry?.remove();
    _entry?.dispose();
    super.dispose();
  }

  Widget _bubble(BuildContext context) {
    final p = context.p;
    final x = widget.bubble == AlignmentDirectional.centerStart ? -1.0 : (widget.bubble == AlignmentDirectional.centerEnd ? 1.0 : 0.0);
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        // Maskot çizilmiyorsa (başka ekran açıldı, başka sekmeye geçildi) balon da görünmez
        showWhenUnlinked: false,
        targetAnchor: Alignment(x, _below ? 1 : -1),
        followerAnchor: Alignment(x, _below ? -1 : 1),
        offset: Offset(0, _below ? -4 : 10),
        child: IgnorePointer(
          // Üst katmanda yazı biçimi miras alınmaz: Material olmadan yazı sarı çizgili (biçimsiz) görünür
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedOpacity(
              opacity: _shown ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 230),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.line, width: 2),
                ),
                child: Text(_line, textAlign: TextAlign.center, style: ts(14.5, w: FontWeight.w800, color: p.ink, height: 1.25)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
        link: _link,
        child: Semantics(
          button: true,
          label: widget.character.name,
          child: MascotView(widget.character.id, mood: widget.mood, size: widget.size, onPoke: _poke),
        ),
      );
}

/// Henüz kurs yokken: yol arkadaşı karşılar ve üç adımı anlatır.
class _Empty extends StatelessWidget {
  const _Empty({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget step(int n) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.primarySoft, shape: BoxShape.circle),
              child: Text(
                '$n',
                style: ts(16, w: FontWeight.w900, color: p.primaryInk, height: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('learn.step$n.title'),
                    style: ts(16, w: FontWeight.w900, color: p.ink, height: 1.3),
                  ),
                  Text(t('learn.step$n.text'), style: ts(14.5, color: p.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _Buddy(app.buddy, size: 228)),
              const SizedBox(height: 8),
              Text(
                '${app.buddy.name}: “${app.buddy.voice.greet}”',
                textAlign: TextAlign.center,
                style: ts(18, w: FontWeight.w900, color: p.ink, height: 1.3),
              ),
              const SizedBox(height: 16),
              step(1),
              step(2),
              step(3),
              const SizedBox(height: 6),
              ChunkyButton(label: t('learn.create'), onPressed: () => CreateScreen.open(context)),
              const SizedBox(height: 8),
              ChunkyButton(label: t('learn.sample'), kind: ButtonKind.ghost, onPressed: () => addSampleCourse(context)),
            ],
          ),
        ),
      ),
    );
  }
}
