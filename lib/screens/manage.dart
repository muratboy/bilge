/// "Kurslar" sekmesi ve kurs oluşturma / içe aktarma ekranı.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/prompt.dart';
import '../core/schema.dart';
import '../core/store.dart';
import '../core/text_utils.dart';
import '../l10n/l10n.dart';
import '../lesson/lesson_screen.dart';
import '../ui/incoming.dart';
import '../ui/io.dart';
import '../ui/sfx.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Uygulamayla gelen örnek kursu (arayüz diline göre) ekler.
Future<void> addSampleCourse(BuildContext context) async {
  final app = AppScope.read(context);
  final text = await rootBundle.loadString('assets/courses/${L.code == 'en' ? 'solar-system' : 'gunes-sistemi'}.bilge.json');
  final course = parseCourse(text).course;
  if (course != null) app.putCourse(course);
}

/// Uygulamayla gelen örnek kurs büyüdüyse, daha önce eklenmiş kopyasına yeni üniteleri ekler.
/// İlerleme korunur; kullanıcı kursu silip yeniden eklemek zorunda kalmaz.
Future<void> refreshSampleCourses(AppState app) async {
  for (final id in const ['gunes-sistemi', 'solar-system']) {
    final have = app.courses[id];
    if (have == null) continue;
    final bundled = parseCourse(await rootBundle.loadString('assets/courses/$id.bilge.json')).course;
    // Yeni ünite ya da var olan ünitelere yeni ders geldiyse kullanıcının kopyası da büyür
    if (bundled != null && (bundled.units.length > have.units.length || bundled.exerciseCount > have.exerciseCount)) {
      app.replaceCourse(mergeCourses(have, bundled).course);
    }
  }
}

String _summary(Course c) => t('import.summary', {'u': c.units.length, 'l': c.lessonCount, 'e': c.exerciseCount});

/// Kursu tek bir .bilge.json dosyası olarak sistemin paylaşım penceresine verir.
Future<void> shareCourse(Course c) => shareFile(
      '${c.id}.bilge.json',
      const JsonEncoder.withIndent('  ').convert(c.toJson()),
      subject: t('courses.shareText', {'title': c.title}),
      text: '${t('courses.shareText', {'title': c.title})}\n${t('courses.shareHint')}',
    );

/// Gelen kurs kütüphanedeki bir kursla aynı kimliği taşıyor, ama kullanıcı o kursu büyütmek için gelmedi.
/// Kimlik rastlantıyla da aynı olabilir (iki ayrı kişinin aynı konuda ürettiği kurslar), bilerek de (devam çıktısı):
/// hangisi olduğunu kullanıcı seçer, hiçbir şey sormadan karıştırılmaz. Başlıklar aynıysa ilk seçenek üniteleri
/// eklemek, değilse ayrı kurs olarak eklemektir.
void _offerClash(
  BuildContext context, {
  required Course existing,
  required Course incoming,
  Widget? body,
  required void Function(Course course, String message) onDone,
}) {
  final app = AppScope.read(context);
  final summary = _summary(incoming);
  final same = norm(existing.title) == norm(incoming.title);
  // Aynı kursun devamı: başlık aynı, gelen ünitelerin hiçbiri kursta yok (yapay zekâdan paylaşılan "devam" çıktısı).
  // Yine sorulur, ama soru kısadır: hangi kursa kaç ünite ekleneceği.
  final have = {for (final u in existing.units) u.id};
  final more = same && incoming.units.every((u) => !have.contains(u.id));
  DialogAction merge(ButtonKind kind) => DialogAction(t('import.merge'), kind: kind, onPressed: () {
        final m = mergeCourses(existing, incoming);
        onDone(m.course, t('import.merged', {'a': m.added, 'u': m.updated}));
      });
  DialogAction separate(ButtonKind kind) => DialogAction(t('import.separate'), kind: kind, onPressed: () {
        onDone(incoming.copyWith(id: freeId(incoming.id, app.courses.containsKey)), t('import.added', {'summary': summary}));
      });
  showBilgeDialog(
    context,
    title: more ? t('import.moreTitle', {'title': existing.title, 'n': incoming.units.length}) : t('import.clashTitle'),
    text: [
      more ? t('import.moreText', {'summary': summary}) : t('import.clashText', {'incoming': incoming.title, 'existing': existing.title, 'summary': summary}),
      // Ayrı eklenen kurs kendi grubunu taşır: sendeki bir büyük kursun kısmı olacaksa bu da sorulmadan olmaz
      if (app.groups.contains(incoming.group)) t('import.joinsSeparate', {'group': incoming.group}),
    ].join('\n'),
    body: body,
    actions: [
      if (same) ...[
        merge(ButtonKind.primary),
        separate(ButtonKind.ghost),
        // Yerine geçen kurs, eskisinin bulunduğu kısımlı kursta kalır
        if (!more) DialogAction(t('import.replace'), kind: ButtonKind.ghost, onPressed: () => onDone(incoming.copyWith(group: existing.group), t('import.replaced', {'summary': summary}))),
      ] else ...[
        separate(ButtonKind.primary),
        merge(ButtonKind.ghost),
      ],
      DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
    ],
  );
}

/// Dışarıdan gelen bir kurs dosyasını (paylaşım, dosyaya dokunma) kullanıcıya sorarak ekler.
void offerIncomingCourse(BuildContext context, String text) {
  final app = AppScope.read(context);
  if (text == Incoming.tooBig || text.length > maxImportChars) return toast(context, t('err.tooBig', {'mb': maxCourseBytes ~/ (1024 * 1024)}));
  // Hatalı işaretlenen sorular için yapay zekânın verdiği düzeltme
  final fix = parseFixes(text);
  if (fix != null) return offerFixes(context, fix);
  // Tek dosyada birden çok kurs: paket
  final pack = parsePack(text);
  if (pack != null) return offerPack(context, pack);
  final report = parseCourse(text);
  final incoming = report.course;
  if (incoming == null) {
    // Kurs olmaya çalışıp okunamayan çıktıda neden söylenir (yarıda kesilmiş, bozuk JSON); ilgisiz bir metinde genel mesaj
    final why = report.errors.firstOrNull;
    return toast(context, why == null || why == t('err.noJson') || why == t('err.empty') ? t('incoming.failed') : why);
  }
  final existing = app.courses[incoming.id];
  final summary = _summary(incoming);
  void add(Course course, String message) {
    app.putCourse(course, imported: true);
    Sfx.play('complete');
    // Kurs parça parça üretiliyorsa sıradaki parça için ne yapılacağı da söylenir
    final left = course.outline.length - course.units.length;
    toast(context, left > 0 ? '$message ${t('incoming.moreLeft', {'n': left})}' : message);
  }

  // Yarıda kesilmiş bir çıktı paylaşıldıysa neyin eksik kaldığı burada da söylenir
  final notes = report.notes.isEmpty
      ? null
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final n in report.notes) Text(n, style: ts(14.5, w: FontWeight.w800, color: context.p.goldInk))],
        );
  if (existing != null) return _offerClash(context, existing: existing, incoming: incoming, body: notes, onDone: add);
  showBilgeDialog(
    context,
    title: t('incoming.title', {'title': incoming.title}),
    text: [
      if (incoming.description.isNotEmpty) incoming.description,
      summary,
      if (incoming.author.isNotEmpty) t('incoming.by', {'author': incoming.author}),
      // Dosya kendini var olan bir büyük kursun kısmı olarak tanıtıyorsa bu da sorulmadan olmaz
      if (app.groups.contains(incoming.group)) t('import.joins', {'group': incoming.group}),
    ].join('\n'),
    body: notes,
    actions: [
      DialogAction(t('import.addCourse'), onPressed: () => add(incoming, t('import.added', {'summary': summary}))),
      DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
    ],
  );
}

/* ================= Kurslar ================= */

/// Kurs, kısım ve grup kartlarının ortak görünümü. Seçenekler kartın "⋮" düğmesinde durur: çok kursta liste kısa kalır.
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.meta,
    required this.value,
    required this.color,
    required this.onTap,
    required this.onMenu,
    this.kicker = '',
    this.description = '',
    this.selected = false,
    this.done = false,
    this.layers = false,
    this.footer,
  });
  final String emoji, title, meta, kicker, description;
  final double value;
  final Color color;
  final VoidCallback onTap, onMenu;
  final bool selected; // seçili kurs (ya da onu içeren grup)
  final bool done; // tamamlandı
  final bool layers; // birden çok kısmı olan grup
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final edge = selected ? color : p.line;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border(
          top: BorderSide(color: edge, width: 2),
          left: BorderSide(color: edge, width: 2),
          right: BorderSide(color: edge, width: 2),
          bottom: BorderSide(color: edge, width: 4),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Color.lerp(color, p.surface, 0.84), borderRadius: BorderRadius.circular(15)),
                  child: Text(emoji.isEmpty ? '📘' : emoji, style: const TextStyle(fontSize: 27)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (kicker.isNotEmpty) Text(upper(kicker), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w900, color: p.ink3, spacing: 0.8)),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(17, w: FontWeight.w900, color: p.ink, height: 1.25)),
                      if (description.isNotEmpty) Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, color: p.ink2)),
                      Row(
                        children: [
                          if (layers) ...[Icon(Icons.layers_rounded, size: 15, color: p.ink3), const SizedBox(width: 4)],
                          Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w800, color: p.ink3))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (done)
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 18, color: Palette.gold),
                            const SizedBox(width: 5),
                            Text(t('courses.done'), style: ts(13.5, w: FontWeight.w900, color: p.goldInk)),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(child: Bar(value: value, color: color)),
                            const SizedBox(width: 8),
                            Text('${(value * 100).round()}%', style: ts(14, w: FontWeight.w900, color: p.ink2)),
                          ],
                        ),
                      ?footer,
                    ],
                  ),
                ),
                IconTap(icon: Icons.more_vert_rounded, label: t('courses.more'), onTap: onMenu),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _confirmRemove(BuildContext context, {required String title, required List<String> ids}) {
  final app = AppScope.read(context);
  showBilgeDialog(
    context,
    title: title,
    text: t('courses.deleteText'),
    actions: [DialogAction(t('common.delete'), kind: ButtonKind.bad, onPressed: () => app.removeCourses(ids)), DialogAction(t('common.cancel'), kind: ButtonKind.ghost)],
  );
}

SheetAction _archiveAction(BuildContext context, List<String> ids) {
  final app = AppScope.read(context);
  final archived = ids.every(app.archived.contains);
  return SheetAction(archived ? Icons.unarchive_rounded : Icons.archive_rounded, t(archived ? 'courses.unarchive' : 'courses.archive'), () {
    app.setArchived(ids, !archived);
    toast(context, t(archived ? 'courses.unarchived' : 'courses.archived'));
  });
}

/// Tek bir kursun seçenekleri. Bir grubun kısmı tek başına arşivlenmez ([archivable] kapalı gelir); [onExam] kısmı sınavla geçer.
void _courseMenu(BuildContext context, Course c, {bool archivable = true, VoidCallback? onExam}) => showActionSheet(
      context,
      title: c.title,
      actions: [
        if (onExam != null) SheetAction(Icons.fast_forward_rounded, t('learn.testOut'), onExam),
        if (AppScope.read(context).flaggedOf(c).isNotEmpty)
          SheetAction(Icons.flag_rounded, t('courses.flagged', {'n': AppScope.read(context).flaggedOf(c).length}), () => FlaggedScreen.open(context, c)),
        SheetAction(Icons.style_rounded, t('courses.cards'), () => CardsScreen.open(context, c)),
        SheetAction(Icons.add_rounded, t('courses.addUnit'), () => CreateScreen.open(context, target: c)),
        SheetAction(Icons.layers_rounded, t('courses.addSection'), () => addSection(context, c)),
        if (c.group.isEmpty && AppScope.read(context).groups.isNotEmpty) SheetAction(Icons.call_merge_rounded, t('section.join'), () => _joinGroup(context, c)),
        if (c.group.isNotEmpty) SheetAction(Icons.call_split_rounded, t('section.leave'), () => AppScope.read(context).setGroup([c.id], '')),
        SheetAction(Icons.edit_rounded, t('courses.rename'), () => _rename(context, c.title, (name) => AppScope.read(context).renameCourse(c.id, name))),
        if (c.units.length > 1) SheetAction(Icons.playlist_remove_rounded, t('unit.delete'), () => _pickUnitToDelete(context, c)),
        SheetAction(Icons.ios_share_rounded, t('courses.share'), () => shareCourse(c)),
        if (archivable) _archiveAction(context, [c.id]),
        SheetAction(Icons.delete_rounded, t('common.delete'), danger: true, () => _confirmRemove(context, title: t('courses.deleteTitle', {'title': c.title}), ids: [c.id])),
      ],
    );

/// Kursun ya da büyük kursun adını sorar; boş bırakılırsa bir şey değişmez.
void _rename(BuildContext context, String current, void Function(String name) onSave) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _RenameSheet(current: current, onSave: onSave),
  );
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.current, required this.onSave});
  final String current;
  final void Function(String name) onSave;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return sheetBody(
      context,
      padding: EdgeInsets.fromLTRB(20, 22, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      head: [
        Text(t('courses.renameTitle'), style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25)),
      ],
      scroll: [
        Padding(padding: const EdgeInsets.only(top: 10), child: _Field(controller: name, hint: t('courses.renameHint'))),
      ],
      foot: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyButton(
            label: t('common.save'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onSave(name.text);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyButton(
            label: t('common.cancel'),
            kind: ButtonKind.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

/// Hangi ünitenin silineceğini sorar, sonra onay alır. Silmeden önce yedek alınır: yanlış ünite silinirse
/// Profil › Yedekler'den geri dönülebilir.
void _pickUnitToDelete(BuildContext context, Course c) => showActionSheet(
      context,
      title: t('unit.deletePick'),
      actions: [
        for (final (i, u) in c.units.indexed)
          SheetAction(Icons.delete_outline_rounded, '${i + 1}. ${u.title}', () {
            final app = AppScope.read(context);
            showBilgeDialog(
              context,
              title: t('unit.deleteTitle', {'title': u.title}),
              text: t('unit.deleteText', {'n': u.lessons.length}),
              actions: [
                DialogAction(t('common.delete'), kind: ButtonKind.bad, onPressed: () async {
                  await app.autoBackup(force: true);
                  if (app.removeUnit(c.id, u.id) && context.mounted) toast(context, t('unit.deleted', {'title': u.title}));
                }),
                DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
              ],
            );
          }),
      ],
    );

/// Kursa yeni bir kısım ekler: kısım, yapay zekâya önceki kısımları da anlatan kalıpla yeni bir kurs olarak yazdırılır.
/// Kurs henüz kısımlı bir büyük kursun parçası değilse önce büyük kursun adı sorulur; bu kurs onun 1. kısmı olur.
void addSection(BuildContext context, Course c) {
  if (c.group.isNotEmpty) {
    CreateScreen.open(context, group: c.group);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _AddSectionSheet(course: c),
  );
}

class _AddSectionSheet extends StatefulWidget {
  const _AddSectionSheet({required this.course});
  final Course course;

  @override
  State<_AddSectionSheet> createState() => _AddSectionSheetState();
}

class _AddSectionSheetState extends State<_AddSectionSheet> {
  late final TextEditingController name = TextEditingController(text: widget.course.title);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final p = context.p;
    return sheetBody(
      context,
      padding: EdgeInsets.fromLTRB(20, 22, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      head: [
        Text(t('section.nameTitle'), style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25)),
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('section.nameText', {'title': widget.course.title}), style: ts(15.5, color: p.ink2))),
      ],
      scroll: [
        Padding(padding: const EdgeInsets.only(top: 10), child: _Field(controller: name, hint: t('section.nameHint'))),
      ],
      foot: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyButton(
            label: t('common.continue'),
            onPressed: () {
              final group = name.text.trim();
              if (group.isEmpty) return toast(context, t('section.nameNeeded'));
              Navigator.of(context).pop();
              app.setGroup([widget.course.id], group);
              CreateScreen.open(context, group: group);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyButton(
            label: t('common.cancel'),
            kind: ButtonKind.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

/// Tek başına duran bir kursu, var olan kısımlı bir büyük kursun son kısmı yapar.
void _joinGroup(BuildContext context, Course c) {
  final app = AppScope.read(context);
  showActionSheet(
    context,
    title: t('section.joinTitle', {'title': c.title}),
    actions: [
      for (final g in app.groups) SheetAction(Icons.layers_rounded, g, () => app.setGroup([c.id], g)),
    ],
  );
}

/// Bir grubun (paketin) seçenekleri: bütün kısımlar için geçerlidir.
void _groupMenu(BuildContext context, CourseEntry entry, {VoidCallback? onResume}) {
  final ids = [for (final c in entry.courses) c.id];
  showActionSheet(
    context,
    title: entry.group,
    actions: [
      if (onResume != null) SheetAction(Icons.play_arrow_rounded, t('group.resume'), onResume),
      SheetAction(Icons.add_rounded, t('courses.addSection'), () => CreateScreen.open(context, group: entry.group)),
      SheetAction(Icons.edit_rounded, t('courses.rename'), () {
        _rename(context, entry.group, (name) {
          if (!AppScope.read(context).renameGroup(entry.group, name)) toast(context, t('courses.renameTaken'));
        });
      }),
      SheetAction(Icons.ios_share_rounded, t('pack.share'), () => sharePackDialog(context, group: entry.group)),
      _archiveAction(context, ids),
      SheetAction(Icons.delete_rounded, t('pack.remove'), danger: true, () => _confirmRemove(context, title: t('pack.removeTitle', {'title': entry.group, 'n': ids.length}), ids: ids)),
    ],
  );
}

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key, required this.onOpenLearn});
  final VoidCallback onOpenLearn;

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  final _search = TextEditingController();
  final _toggled = <Shelf, bool>{}; // kullanıcının açıp kapattığı raflar

  static const _shelfIcons = {
    Shelf.active: Icons.play_circle_rounded,
    Shelf.fresh: Icons.radio_button_unchecked_rounded,
    Shelf.finished: Icons.emoji_events_rounded,
    Shelf.archived: Icons.archive_rounded,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.p;
    final entries = app.entries;
    final place = {for (final (i, e) in entries.indexed) e.key: i};

    void open(Course c) {
      app.selectCourse(c.id);
      widget.onOpenLearn();
    }

    Widget courseCard(Course c, Color color, {bool archivable = true}) => _CourseCard(
          key: ValueKey('course-${c.id}'),
          emoji: c.emoji,
          kicker: c.group,
          title: c.title,
          description: c.description,
          meta: t('courses.meta', {'u': c.units.length, 'l': c.lessonCount}) + (c.author.isEmpty ? '' : ' · ${c.author}'),
          value: app.percent(c),
          color: color,
          selected: c.id == app.current,
          done: app.isFinished(c),
          onTap: () => open(c),
          onMenu: () => _courseMenu(context, c, archivable: archivable),
        );

    Widget card(CourseEntry e) {
      final color = Palette.unitColor(place[e.key] ?? 0);
      if (!e.isGroup) return courseCard(e.courses.first, color);
      final resume = app.resumeOf(e);
      final shelf = app.shelfOf(e);
      return _CourseCard(
        key: ValueKey(e.key),
        emoji: resume.emoji,
        title: e.group,
        // Yarıda kalan grupta nerede kalındığı bir bakışta görünür
        description: shelf == Shelf.active ? t('courses.next', {'title': sectionTitle(resume)}) : '',
        meta: t('courses.metaGroup', {'n': e.courses.length, 'l': e.lessonCount}),
        layers: true,
        value: app.percentOf(e),
        color: color,
        selected: e.courses.any((c) => c.id == app.current),
        done: e.courses.every(app.isFinished),
        onTap: () => GroupScreen.open(context, e.group, onOpenLearn: widget.onOpenLearn),
        onMenu: () => _groupMenu(context, e, onResume: () => open(app.resumeOf(e))),
      );
    }

    Widget note(String text) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(text, style: ts(16, color: p.ink2)));

    // Liste tembel kurulur: yüzlerce kurs olsa da yalnızca görünen kartlar çizilir
    final rows = <Widget Function()>[
      () => Row(
            children: [
              Expanded(child: Text(t('courses.title'), style: ts(26, w: FontWeight.w900, color: p.ink, height: 1.2))),
              if (app.order.length >= 2) IconTap(icon: Icons.inventory_2_rounded, label: t('pack.share'), color: p.ink2, onTap: () => sharePackDialog(context)),
              if (app.order.isNotEmpty) IconTap(icon: Icons.add_rounded, label: t('courses.add'), color: p.ink2, onTap: () => CreateScreen.open(context)),
            ],
          ),
      () => const SizedBox(height: 10),
      if (app.order.length > 6)
        () => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Field(controller: _search, hint: t('courses.search'), onChanged: (_) => setState(() {})),
            ),
      if (app.order.isEmpty) () => note(t('courses.empty')),
    ];

    final query = fold(_search.text);
    if (query.isNotEmpty) {
      // Arama: adı uyan gruplar ve (hangi grupta olursa olsun) uyan kurslar düz listede
      final groups = [for (final e in entries) if (e.isGroup && fold(e.group).contains(query)) e];
      final found = [
        for (final e in entries)
          for (final c in e.courses)
            if (fold('${c.title} ${c.description} ${c.author}').contains(query)) (entry: e, course: c),
      ];
      rows.addAll([
        for (final e in groups) () => card(e),
        for (final f in found) () => courseCard(f.course, Palette.unitColor(place[f.entry.key] ?? 0), archivable: !f.entry.isGroup),
        if (groups.isEmpty && found.isEmpty) () => note(t('courses.none')),
      ]);
    } else {
      // Raflar: önce çalışılanlar (en son çalışılan en üstte), sonra başlanmayanlar; bitenler ve arşiv kapalı gelir
      final shelves = {for (final s in Shelf.values) s: <CourseEntry>[]};
      for (final e in entries) {
        shelves[app.shelfOf(e)]!.add(e);
      }
      int byRecent(CourseEntry a, CourseEntry b) {
        final la = app.lastStudied(a), lb = app.lastStudied(b);
        return la != lb ? lb.compareTo(la) : place[a.key]!.compareTo(place[b.key]!);
      }

      shelves[Shelf.active]!.sort(byRecent);
      shelves[Shelf.finished]!.sort(byRecent);
      final filled = [for (final s in Shelf.values) if (shelves[s]!.isNotEmpty) s];
      final studying = filled.contains(Shelf.active) || filled.contains(Shelf.fresh);
      final headers = filled.length > 1 || !studying;
      for (final s in filled) {
        final collapsible = s == Shelf.finished || s == Shelf.archived;
        // Çalışılacak başka kurs yoksa bitenler açık gelir
        final isOpen = !collapsible || (_toggled[s] ?? (s == Shelf.finished && !studying));
        if (headers) {
          rows.add(() => Semantics(
                button: collapsible,
                child: GestureDetector(
                  key: ValueKey('shelf-${s.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: collapsible ? () => setState(() => _toggled[s] = !isOpen) : null,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    child: Row(
                      children: [
                        Icon(_shelfIcons[s], size: 19, color: p.ink3),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: upper(t('courses.shelf.${s.name}'))),
                              TextSpan(text: '   ${shelves[s]!.length}', style: ts(13.5, w: FontWeight.w800, color: p.ink3)),
                            ]),
                            style: ts(13.5, w: FontWeight.w900, color: p.ink2, spacing: 0.8),
                          ),
                        ),
                        if (collapsible) Icon(isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.ink3),
                      ],
                    ),
                  ),
                ),
              ));
        }
        if (isOpen) rows.addAll([for (final e in shelves[s]!) () => card(e)]);
      }
    }

    rows.addAll([
      () => const SizedBox(height: 4),
      () => ChunkyButton(label: t('courses.add'), icon: Icons.add_rounded, onPressed: () => CreateScreen.open(context)),
      if (!app.courses.containsKey('gunes-sistemi') && !app.courses.containsKey('solar-system')) ...[
        () => const SizedBox(height: 8),
        () => ChunkyButton(label: t('courses.addSample'), kind: ButtonKind.ghost, onPressed: () => addSampleCourse(context)),
      ],
    ]);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i](),
        ),
      ),
    );
  }
}

/* ================= Kurs grubu: kısımlar ================= */

/// Bir kısmın (kursun) kalan bütün ünitelerini tek sınavla geçmeyi önerir. Sınav geçilip bitiş ekranında
/// "sıradaki kısma geç" denirse [onNext] çağrılır.
void startCourseExam(BuildContext context, Course course, {VoidCallback? onNext}) {
  final app = AppScope.read(context);
  final last = course.units.length - 1;
  final unit = course.units[last];
  final questions = app.examSize(course, last);
  Sfx.play('tap');
  showBilgeDialog(
    context,
    title: t('group.examTitle', {'title': sectionTitle(course)}),
    text: t('group.examText', {'n': questions, 'm': AppState.examAllowance(questions), 'k': app.examUnits(course, last).length}),
    actions: [
      DialogAction(
        t('learn.examStart'),
        onPressed: () => LessonScreen.open(context, course, PathNode(kind: NodeKind.exam, id: '${unit.id}/~sinav', title: '', unitIndex: last, unit: unit)).then((next) {
          if (next) onNext?.call();
        }),
      ),
      DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
    ],
  );
}

/// Büyük bir konunun kısımları: paketin kursları sırayla, her birinin ilerlemesiyle. Kısım bitince sıradaki önerilir;
/// konuyu bilen kişi bir kısmı sınavla geçebilir.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.group, this.onOpenLearn});
  final String group;

  /// Bir kısım seçilince çağrılır ("Öğren" sekmesine geçmek için).
  final VoidCallback? onOpenLearn;

  static Future<void> open(BuildContext context, String group, {VoidCallback? onOpenLearn}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(group: group, onOpenLearn: onOpenLearn)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.p;
    final sections = app.sectionsOf(group);
    if (sections.isEmpty) {
      // Grup silindi: listeye dön
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
      });
      return Scaffold(backgroundColor: p.bg);
    }
    final entry = CourseEntry(group, sections);
    final resume = app.resumeOf(entry);
    final value = app.percentOf(entry);
    final allDone = sections.every(app.isFinished);

    // Kısımlar ekranını kapatıp seçili kursun yoluna döner
    void leave() {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      onOpenLearn?.call();
    }

    void open(Course c) {
      app.selectCourse(c.id);
      leave();
    }

    void exam(Course c) => startCourseExam(context, c, onNext: leave);

    Widget section(int i, Course c) {
      final color = Palette.unitColor(i);
      final done = app.isFinished(c);
      final canExam = !done && app.canTestOutCourse(c);
      return _CourseCard(
        key: ValueKey('course-${c.id}'),
        emoji: c.emoji,
        kicker: t('group.section', {'n': i + 1}) + (!allDone && c.id == resume.id ? ' · ${t('group.upNext')}' : ''),
        title: sectionTitle(c),
        description: c.description,
        meta: t('courses.meta', {'u': c.units.length, 'l': c.lessonCount}),
        value: app.percent(c),
        color: color,
        selected: !allDone && c.id == resume.id,
        done: done,
        onTap: () => open(c),
        onMenu: () => _courseMenu(context, c, archivable: false, onExam: canExam ? () => exam(c) : null),
        footer: canExam
            ? Semantics(
                button: true,
                child: GestureDetector(
                  key: ValueKey('exam-course-${c.id}'),
                  onTap: () => exam(c),
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
                    decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fast_forward_rounded, color: p.ink2, size: 18),
                        const SizedBox(width: 5),
                        Text(upper(t('learn.testOut')), style: ts(12.5, w: FontWeight.w900, color: p.ink2, spacing: 0.6, height: 1.2)),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      );
    }

    final rows = <Widget Function()>[
      () => Row(
            children: [
              IconTap(icon: Icons.arrow_back_rounded, label: t('common.back'), onTap: () => Navigator.of(context).pop()),
              Expanded(child: Text(group, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(22, w: FontWeight.w900, color: p.ink, height: 1.2))),
              IconTap(icon: Icons.more_vert_rounded, label: t('courses.more'), onTap: () => _groupMenu(context, entry)),
            ],
          ),
      () => Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.layers_rounded, size: 18, color: p.ink3),
                      const SizedBox(width: 6),
                      Expanded(child: Text(t('courses.metaGroup', {'n': sections.length, 'l': entry.lessonCount}), style: ts(14.5, w: FontWeight.w800, color: p.ink2))),
                      Text('${(value * 100).round()}%', style: ts(16, w: FontWeight.w900, color: p.ink)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Bar(value: value, color: allDone ? Palette.gold : p.primary),
                  const SizedBox(height: 14),
                  if (allDone)
                    Text(t('learn.groupDone', {'group': group}), style: ts(15.5, w: FontWeight.w800, color: p.goldInk))
                  else ...[
                    Text(t('courses.next', {'title': sectionTitle(resume)}), style: ts(15.5, w: FontWeight.w800, color: p.ink)),
                    const SizedBox(height: 10),
                    ChunkyButton(label: t('group.resume'), icon: Icons.play_arrow_rounded, onPressed: () => open(resume)),
                  ],
                ],
              ),
            ),
          ),
      for (final (i, c) in sections.indexed) () => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: section(i, c)),
      () => Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: ChunkyButton(label: t('courses.addSection'), icon: Icons.add_rounded, kind: ButtonKind.ghost, onPressed: () => CreateScreen.open(context, group: group)),
          ),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i](),
        ),
      ),
    );
  }
}

/* ================= Kurs paketi ================= */

/// Bir paketi (tek dosyada birden çok kurs) kullanıcıya sorarak ekler.
void offerPack(BuildContext context, PackReport report, {void Function(String message)? onAdded}) {
  final app = AppScope.read(context);
  final pack = report.pack;
  if (pack == null) return toast(context, report.errors.firstOrNull ?? t('incoming.failed'));
  final p = context.p;
  final existing = pack.courses.where((c) => app.courses.containsKey(c.id)).length;
  // Paketin yeni kursları sende zaten duran bir büyük kursa kısım olarak girecekse söylenir
  final groups = app.groups.toSet();
  final joined = {
    for (final c in pack.courses)
      if (!app.courses.containsKey(c.id) && groups.contains(c.group)) c.group,
  };
  showBilgeDialog(
    context,
    title: t('pack.offerTitle', {'title': pack.title}),
    text: [
      if (pack.description.isNotEmpty) pack.description,
      t('pack.summary', {'n': pack.courses.length, 'l': pack.lessonCount}),
      if (pack.author.isNotEmpty) t('incoming.by', {'author': pack.author}),
    ].join('\n'),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in pack.courses.take(8)) Text('${c.emoji.isEmpty ? '📘' : c.emoji}  ${c.title}', style: ts(15, w: FontWeight.w800, color: p.ink)),
        if (pack.courses.length > 8) Text(t('pack.more', {'n': pack.courses.length - 8}), style: ts(14, color: p.ink2)),
        if (existing > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('pack.existing', {'n': existing}), style: ts(14, w: FontWeight.w800, color: p.goldInk))),
        for (final g in joined.take(3)) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('pack.joins', {'group': g}), style: ts(14, w: FontWeight.w800, color: p.goldInk))),
        for (final w in report.warnings.take(4)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $w', style: ts(13.5, color: p.ink2))),
      ],
    ),
    actions: [
      DialogAction(t('pack.addAll'), onPressed: () {
        final r = app.putPack(pack, imported: true);
        Sfx.play('complete');
        final message = t('pack.added', {'a': r.added, 'u': r.updated});
        onAdded != null ? onAdded(message) : toast(context, message);
      }),
      DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
    ],
  );
}

/// Seçilen kurslardan paket kurar. Kurslar grupsuz yazılır: alan kişide paketin adı altında toplanırlar.
Pack buildPack(AppState app, Iterable<String> ids, String title) => Pack(
      title: title.trim().isEmpty ? t('pack.defaultName') : title.trim(),
      courses: [
        for (final id in app.order)
          if (ids.contains(id)) app.courses[id]!.copyWith(group: ''),
      ],
    );

/// Paketi tek bir dosya olarak sistemin paylaşım penceresine verir.
Future<void> sharePack(Pack pack) => shareFile(
      '${slug(pack.title).isEmpty ? 'paket' : slug(pack.title)}.bilge-paket.json',
      jsonEncode(pack.toJson()),
      subject: t('pack.shareFile', {'title': pack.title, 'n': pack.courses.length}),
      text: '${t('pack.shareFile', {'title': pack.title, 'n': pack.courses.length})}\n${t('courses.shareHint')}',
    );

/// Hangi kursların pakete gireceğini ve paketin adını sorar. [group] verilirse o grubun kursları seçili gelir.
void sharePackDialog(BuildContext context, {String group = ''}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SharePackSheet(group: group),
  );
}

class _SharePackSheet extends StatefulWidget {
  const _SharePackSheet({required this.group});
  final String group;

  @override
  State<_SharePackSheet> createState() => _SharePackSheetState();
}

class _SharePackSheetState extends State<_SharePackSheet> {
  late final TextEditingController name = TextEditingController(text: widget.group);
  late final Set<String> picked = {
    for (final id in AppScope.read(context).order)
      if (widget.group.isEmpty || AppScope.read(context).courses[id]!.group == widget.group) id,
  };

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final p = context.p;
    return sheetBody(
      context,
      padding: EdgeInsets.fromLTRB(20, 22, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      head: [
        Text(t('pack.shareTitle'), style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25)),
        Padding(padding: const EdgeInsets.only(top: 6, bottom: 10), child: Text(t('pack.shareText'), style: ts(15, color: p.ink2))),
        _Field(controller: name, hint: t('pack.nameHint')),
        const SizedBox(height: 6),
      ],
      scroll: [
        for (final id in app.order)
          CheckboxListTile(
            value: picked.contains(id),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: p.primary,
            title: Text(app.courses[id]!.title, style: ts(15.5, w: FontWeight.w800, color: p.ink)),
            onChanged: (v) => setState(() => v == true ? picked.add(id) : picked.remove(id)),
          ),
      ],
      foot: [
        const SizedBox(height: 10),
        ChunkyButton(
          label: t('pack.shareAction', {'n': picked.length}),
          icon: Icons.ios_share_rounded,
          onPressed: picked.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop();
                  sharePack(buildPack(app, picked, name.text));
                },
        ),
        const SizedBox(height: 8),
        ChunkyButton(label: t('common.cancel'), kind: ButtonKind.ghost, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/* ================= Hatalı sorular ================= */

/// Bir düzeltme çıktısını kullanıcıya sorarak uygular. Yalnızca hatalı işaretlenmiş sorular değişir.
/// [course] verilirse çıktıdaki kurs kimliğine bakılmaz (kullanıcı o kursun ekranından geldi).
void offerFixes(BuildContext context, FixReport report, {Course? course, void Function(String message)? onDone}) {
  final app = AppScope.read(context);
  if (report.errors.isNotEmpty) return toast(context, report.errors.first);
  // Adım anahtarları ("u1/l1#2") her kursta benzer: başka bir kurs için alınmış düzeltme bu kursa uygulanmaz
  if (course != null && report.courseId.isNotEmpty && report.courseId != course.id) return toast(context, t('fix.otherCourse'));
  final target = course ?? app.courses[report.courseId];
  if (target == null) return toast(context, t('fix.noCourse'));
  final sorted = app.fixable(target, report.fixes);
  final fixes = sorted.changed;
  // Sorular olduğu gibi geri geldiyse düzeltilmiş sayılmaz (panoda cevap değil, kalıbın kendisi de olabilir)
  if (fixes.isEmpty) return toast(context, t(sorted.unchanged > 0 ? 'fix.unchanged' : 'fix.none'));
  final ignored = report.fixes.length - fixes.length - sorted.unchanged;
  final p = context.p;
  showBilgeDialog(
    context,
    title: t('fix.offerTitle', {'n': fixes.length}),
    text: t('fix.offerText', {'title': target.title}),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Yeni hâller: kullanıcı uygulamadan önce düzeltmenin akla yatkın olduğunu görsün
        for (final e in fixes.values.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MdInline(e.headline, style: ts(15, w: FontWeight.w800, color: p.ink)),
                if (e.answerText.isNotEmpty) MdInline('${t('lesson.correctAnswer')}: ${e.answerText}', style: ts(14, w: FontWeight.w700, color: p.goodInk)),
              ],
            ),
          ),
        if (fixes.length > 4) Text(t('fix.more', {'n': fixes.length - 4}), style: ts(14, color: p.ink2)),
        if (sorted.unchanged > 0)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('fix.someUnchanged', {'n': sorted.unchanged}), style: ts(14, w: FontWeight.w800, color: p.goldInk))),
        if (ignored > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('fix.ignored', {'n': ignored}), style: ts(14, w: FontWeight.w800, color: p.goldInk))),
        for (final w in report.warnings.take(3)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $w', style: ts(13.5, color: p.ink2))),
      ],
    ),
    actions: [
      DialogAction(t('fix.applyDo'), onPressed: () {
        final n = app.applyFixes(target, report.fixes);
        Sfx.play('complete');
        final message = t('fix.applied', {'n': n});
        onDone != null ? onDone(message) : toast(context, message);
      }),
      DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
    ],
  );
}

/// Kullanıcının bir kursta hatalı işaretlediği sorular: düzeltme kalıbı buradan kopyalanır, yapay zekânın
/// verdiği düzeltme buradan uygulanır, yanlışlıkla konan işaret buradan kaldırılır.
class FlaggedScreen extends StatelessWidget {
  const FlaggedScreen({super.key, required this.courseId});
  final String courseId;

  static Future<void> open(BuildContext context, Course course) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlaggedScreen(courseId: course.id)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.p;
    final course = app.courses[courseId];
    if (course == null) {
      // Kurs silindi: listeye dön
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
      });
      return Scaffold(backgroundColor: p.bg);
    }
    final flagged = app.flaggedOf(course);

    Future<void> copy() async {
      await copyText(buildFixPrompt(course, [
        for (final f in flagged)
          // Sorunun kendi metni ya da grafiği yoksa dersin ortak metni ve grafiği de verilir: soru onlara dayanıyor olabilir
          (
            at: f.key,
            lesson: f.lesson.title,
            context: f.exercise.text('context').isEmpty ? f.lesson.context : '',
            chart: f.exercise.chart == null ? f.lesson.chart : null,
            exercise: f.exercise,
          ),
      ]));
      Sfx.play('pop');
      if (context.mounted) toast(context, t('flagged.copied'));
    }

    Future<void> apply() async {
      final text = await clipboardText();
      if (!context.mounted) return;
      final report = text == null ? null : parseFixes(text);
      if (report == null) return toast(context, t('fix.notFix'));
      offerFixes(context, report, course: course);
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
              child: Row(
                children: [
                  IconTap(icon: Icons.arrow_back_rounded, label: t('common.back'), onTap: () => Navigator.of(context).pop()),
                  Expanded(child: Text(t('flagged.title'), style: ts(22, w: FontWeight.w900, color: p.ink, height: 1.2))),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(course.title, style: ts(15, w: FontWeight.w800, color: p.ink2)),
                  const SizedBox(height: 10),
                  if (flagged.isEmpty)
                    Padding(padding: const EdgeInsets.only(top: 24), child: Text(t('flagged.empty'), textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, color: p.ink2)))
                  else ...[
                    _Callout(children: [
                      Text(t('flagged.intro'), style: ts(15.5, w: FontWeight.w900, color: p.ink)),
                      for (final (i, key) in const ['flagged.step1', 'flagged.step2', 'flagged.step3'].indexed)
                        Text('${i + 1}. ${t(key)}', style: ts(14.5, color: p.ink)),
                    ]),
                    const SizedBox(height: 12),
                    ChunkyButton(label: t('flagged.copy'), icon: Icons.copy_rounded, onPressed: copy),
                    const SizedBox(height: 8),
                    ChunkyButton(label: t('flagged.apply'), icon: Icons.content_paste_go_rounded, kind: ButtonKind.ghost, onPressed: apply),
                    if (flagged.length > fixBatch)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('flagged.more', {'n': fixBatch}), style: ts(13.5, color: p.ink3))),
                    const SizedBox(height: 16),
                    for (final f in flagged)
                      Padding(
                        key: ValueKey('flag-${f.key}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Kicker(f.lesson.title, color: p.ink3),
                              const SizedBox(height: 4),
                              MdInline(f.exercise.headline, style: ts(15.5, w: FontWeight.w800, color: p.ink)),
                              if (f.exercise.answerText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: MdInline('${t('lesson.correctAnswer')}: ${f.exercise.answerText}', style: ts(14, color: p.ink2)),
                                ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => showEditExerciseSheet(context, course, f.key, f.exercise),
                                    icon: Icon(Icons.edit_outlined, size: 17, color: p.ink2),
                                    label: Text(t('lesson.edit'), style: ts(13.5, w: FontWeight.w900, color: p.ink2)),
                                  ),
                                  TextButton(
                                    onPressed: () => app.unflag(course.id, f.key),
                                    child: Text(t('flagged.unflag'), style: ts(13.5, w: FontWeight.w900, color: p.primary)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ================= Kartlar, yanlışlar ve notlar tarayıcısı ================= */

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key, required this.courseId, this.initialTab = 0});
  final String courseId;
  final int initialTab;

  static Future<void> open(BuildContext context, Course course, {int initialTab = 0}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardsScreen(courseId: course.id, initialTab: initialTab)));

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  late int _tab = widget.initialTab;
  final _flipped = <String>{};

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.p;
    final course = app.courses[widget.courseId];
    if (course == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
      });
      return Scaffold(backgroundColor: p.bg);
    }
    final flashcards = app.flashcardItems(course);
    final mistakes = app.mistakeItems(course);
    final infos = app.infoItems(course);

    Widget buildFlashcards() {
      if (flashcards.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(t('cards.emptyFlash'), textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, color: p.ink2)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyButton(
            label: t('cards.studyFlash', {'n': flashcards.length}),
            icon: Icons.style_rounded,
            onPressed: () => LessonScreen.open(context, course, const PathNode(kind: NodeKind.flashcards, id: '~kartlar', title: '')),
          ),
          const SizedBox(height: 14),
          for (final it in flashcards)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TapCard(
                state: _flipped.contains(it.key) ? CardState.selected : CardState.idle,
                onTap: () {
                  Sfx.play('flip');
                  setState(() => _flipped.contains(it.key) ? _flipped.remove(it.key) : _flipped.add(it.key));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Kicker(t('cards.flip'), color: _flipped.contains(it.key) ? p.primaryInk : p.ink3)),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showEditExerciseSheet(context, course, it.key, it.exercise),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined, size: 18, color: p.ink3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    MdBlock(
                      _flipped.contains(it.key) ? it.exercise.text('back') : it.exercise.text('front'),
                      style: ts(17, w: FontWeight.w800, color: p.ink, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    Widget buildMistakes() {
      if (mistakes.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(t('cards.emptyMistakes'), textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, color: p.ink2)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyButton(
            label: t('cards.practiceMistakes', {'n': mistakes.length}),
            icon: Icons.fitness_center_rounded,
            onPressed: () => LessonScreen.open(context, course, const PathNode(kind: NodeKind.practice, id: '~pratik', title: '')),
          ),
          const SizedBox(height: 14),
          for (final m in mistakes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Kicker(m.lesson.title, color: p.ink3)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: p.badSoft, borderRadius: BorderRadius.circular(99)),
                          child: Text(t('cards.wrongCount', {'n': m.count}), style: ts(12, w: FontWeight.w900, color: p.badInk)),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showEditExerciseSheet(context, course, m.item.key, m.item.exercise),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined, size: 18, color: p.ink3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    MdInline(m.item.exercise.headline, style: ts(15.5, w: FontWeight.w800, color: p.ink)),
                    if (m.item.exercise.answerText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: MdInline('${t('lesson.correctAnswer')}: ${m.item.exercise.answerText}', style: ts(14, w: FontWeight.w700, color: p.goodInk)),
                      ),
                    if (m.item.exercise.explanation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: MdBlock(m.item.exercise.explanation, style: ts(13.5, color: p.ink2, height: 1.35)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    Widget buildInfos() {
      if (infos.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(t('cards.emptyInfo'), textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, color: p.ink2)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in infos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Kicker('${it.unit.title} · ${it.lesson.title}', color: p.primary),
                    if (it.exercise.text('title').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      MdInline(it.exercise.text('title'), style: ts(17, w: FontWeight.w900, color: p.ink)),
                    ],
                    const SizedBox(height: 6),
                    MdBlock(it.exercise.text('body'), style: ts(15.5, color: p.ink, height: 1.45), strong: p.primary),
                    if (it.exercise.text('example').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(12)),
                        child: MdBlock(it.exercise.text('example'), style: ts(14.5, color: p.ink)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
                  child: Row(
                    children: [
                      IconTap(icon: Icons.arrow_back_rounded, label: t('common.back'), onTap: () => Navigator.of(context).pop()),
                      Expanded(child: Text(t('cards.title'), style: ts(22, w: FontWeight.w900, color: p.ink, height: 1.2))),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: Segments<int>(
                    value: _tab,
                    options: {
                      0: '${t('cards.tabFlash')} (${flashcards.length})',
                      1: '${t('cards.tabMistakes')} (${mistakes.length})',
                      2: '${t('cards.tabInfo')} (${infos.length})',
                    },
                    onChanged: (v) => setState(() => _tab = v),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      switch (_tab) {
                        0 => buildFlashcards(),
                        1 => buildMistakes(),
                        _ => buildInfos(),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ================= Kurs oluştur / içe aktar ================= */

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key, this.target, this.startOnImport = false, this.group});

  /// Doluysa bu kursa ünite eklenir; boşsa yeni kurs oluşturulur.
  final Course? target;

  /// Doğrudan "Çıktıyı ekle" sekmesinde açılır (yarım kalmış kursun sıradaki çıktısını eklemek için).
  final bool startOnImport;

  /// Doluysa oluşturulan kurs, bu adlı kısımlı büyük kursun yeni (son) kısmı olur.
  final String? group;

  static Future<void> open(BuildContext context, {Course? target, bool startOnImport = false, String? group}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateScreen(target: target, startOnImport: startOnImport, group: group)));

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  late final _options = PromptOptions(units: widget.target == null ? 5 : 2);
  final _topic = TextEditingController(), _goal = TextEditingController(), _output = TextEditingController();
  final _topicFocus = FocusNode();
  final _scroll = ScrollController();
  final _nextKey = GlobalKey();
  late int _tab = widget.startOnImport ? 1 : 0;
  bool _copied = false, _showTemplate = false, _generating = false;
  bool _details = false; // boyut, uzunluk ve hedef ayarları açık mı (kapalıyken özetleri görünür)
  List<String> _errors = [];
  String? _clipRaw, _clipLabel;

  /// Bu ekranda parça parça kurulan kursun kimliği: çıktılar geldikçe üniteleri buna eklenir.
  late String? _buildingId = widget.target?.id;
  Course? get _building => _buildingId == null ? null : AppScope.read(context).courses[_buildingId];

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  @override
  void dispose() {
    _topic.dispose();
    _goal.dispose();
    _output.dispose();
    _topicFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final raw = await clipboardText();
      if (!mounted || raw == null || raw.trim().isEmpty || raw == _clipRaw) return;
      final trimmed = raw.trim();
      if (!trimmed.startsWith('{') && !trimmed.startsWith('[') && !trimmed.startsWith('```')) return;
      if (trimmed.contains('JSON ŞEMASI') || trimmed.contains('JSON SCHEMA')) return;
      final fix = parseFixes(trimmed);
      if (fix != null && fix.errors.isEmpty && fix.fixes.isNotEmpty) {
        setState(() {
          _clipRaw = raw;
          _clipLabel = t('clip.fixAdd', {'n': fix.fixes.length});
        });
        return;
      }
      final pack = parsePack(trimmed);
      if (pack != null && pack.pack != null) {
        setState(() {
          _clipRaw = raw;
          _clipLabel = t('clip.packAdd', {'title': pack.pack!.title, 'n': pack.pack!.courses.length});
        });
        return;
      }
      final report = parseCourse(trimmed);
      if (report.course != null) {
        setState(() {
          _clipRaw = raw;
          _clipLabel = t('clip.courseAdd', {'title': report.course!.title});
        });
      }
    } catch (_) {}
  }

  String get _prompt {
    _options
      ..topic = _topic.text.trim()
      ..goal = _goal.text.trim();
    // Yeni kısım: kalıp, büyük kursun adını ve önceki kısımların ünitelerini de anlatır
    if (widget.group case final group? when widget.target == null && _buildingId == null) {
      _options
        ..series = group
        ..sections = [
          for (final c in AppScope.read(context).sectionsOf(group)) (title: c.title, units: [for (final u in c.units) u.title]),
        ];
    }
    final target = _building ?? widget.target;
    if (target != null) {
      final left = target.outline.length - target.units.length;
      final continueOptions = (left > 0 && _options.units > left)
          ? PromptOptions(
              topic: _options.topic,
              level: _options.level,
              goal: _options.goal,
              language: _options.language,
              units: left,
              lessons: _options.lessons,
              density: _options.density,
              perMessage: _options.perMessage,
            )
          : _options;
      return buildContinuePrompt(target, continueOptions);
    }
    return buildPrompt(_options);
  }

  bool _topicReady() {
    if (widget.target != null || _topic.text.trim().isNotEmpty) return true;
    toast(context, t('create.needTopic'));
    // Konu kutusu sayfanın en üstünde: oraya dön, sonra imleci kutuya koy
    _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut).then((_) {
      if (mounted) _topicFocus.requestFocus();
    });
    return false;
  }

  Future<void> _copy() async {
    if (!_topicReady()) return;
    final p = _prompt;
    _clipRaw = p;
    await copyText(p);
    Sfx.play('pop');
    if (!mounted) return;
    setState(() {
      _copied = true;
      _clipLabel = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _nextKey.currentContext;
      if (ctx != null && mounted) Scrollable.ensureVisible(ctx, alignment: 0.9, duration: const Duration(milliseconds: 300));
    });
  }

  Future<void> _generateWithAi() async {
    if (!_topicReady()) return;
    final s = AppScope.read(context).settings;
    if (s.aiKey.trim().isEmpty) return toast(context, t('create.aiMissingKey'));
    setState(() => _generating = true);
    try {
      _options
        ..topic = _topic.text.trim()
        ..goal = _goal.text.trim();
      if (widget.group case final group? when widget.target == null && _buildingId == null) {
        _options
          ..series = group
          ..sections = [
            for (final c in AppScope.read(context).sectionsOf(group)) (title: c.title, units: [for (final u in c.units) u.title]),
          ];
      }
      final aiOptions = PromptOptions(
        topic: _options.topic,
        level: _options.level,
        goal: _options.goal,
        language: _options.language,
        units: _options.units,
        lessons: _options.lessons,
        density: _options.density,
        perMessage: 1, // Doğrudan API çağrısında çıktı sınırı (8192 token) aşılmasın diye tek tek üretilir
      )
        ..series = _options.series
        ..sections = _options.sections;
      final target = _building ?? widget.target;
      final prompt = target == null ? buildPrompt(aiOptions) : buildContinuePrompt(target, aiOptions);
      final res = await callAi(provider: s.aiProvider, apiKey: s.aiKey, model: s.aiModel, prompt: prompt);
      if (!mounted) return;
      if (res.trim().isEmpty) throw t('create.aiEmpty');
      setState(() {
        _generating = false;
        _output.text = res;
      });
      _import();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      final raw = '$e';
      final err = s.aiKey.trim().isNotEmpty ? raw.replaceAll(s.aiKey.trim(), '•••').replaceAll(s.aiKey, '•••') : raw;
      toast(context, t('create.aiError', {'err': err}));
    }
  }

  Future<void> _generateNextWithAi() async {
    final building = _building;
    if (building == null) return;
    final s = AppScope.read(context).settings;
    if (s.aiKey.trim().isEmpty) return toast(context, t('create.aiMissingKey'));
    setState(() => _generating = true);
    try {
      final left = building.outline.length - building.units.length;
      if (left <= 0) return;
      final nextOptions = PromptOptions(
        topic: _options.topic,
        level: _options.level,
        goal: _options.goal,
        language: _options.language,
        units: 1, // Kalan plandan yalnızca sıradaki 1 ünite istenir (plan aşılmaz ve token sınırına takılmaz)
        lessons: _options.lessons,
        density: _options.density,
        perMessage: 1,
      );
      final prompt = buildContinuePrompt(building, nextOptions);
      final res = await callAi(provider: s.aiProvider, apiKey: s.aiKey, model: s.aiModel, prompt: prompt);
      if (!mounted) return;
      if (res.trim().isEmpty) throw t('create.aiEmpty');
      setState(() {
        _generating = false;
        _output.text = res;
      });
      _import();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      final raw = '$e';
      final err = s.aiKey.trim().isNotEmpty ? raw.replaceAll(s.aiKey.trim(), '•••').replaceAll(s.aiKey, '•••') : raw;
      toast(context, t('create.aiError', {'err': err}));
    }
  }

  /* ----- içe aktarma ----- */

  void _done(Course done, String message) {
    // Yeni kısım, büyük kursun grubuna girer
    final group = widget.group;
    final course = group == null || done.group == group ? done : done.copyWith(group: group);
    final app = AppScope.read(context);
    if (group != null) app.profile.sectionsAdded++;
    app.putCourse(course, own: true, imported: true);
    Sfx.play('complete');
    if (course.outline.length > course.units.length) {
      // Planlanan ünitelerin hepsi gelmedi: ekranda kal, sıradaki çıktıyı bekle
      setState(() {
        _buildingId = course.id;
        _output.clear();
        _errors = [];
        _tab = 1;
      });
      toast(context, t('import.addedPartial', {'done': course.units.length, 'total': course.outline.length}));
      return;
    }
    _leave(message);
  }

  void _leave([String? message]) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message, textAlign: TextAlign.center)));
  }

  void _import() {
    FocusManager.instance.primaryFocus?.unfocus();
    final app = AppScope.read(context);
    // Yapıştırılan şey hatalı sorular için bir düzeltme çıktısıysa işaretli sorulara uygulanır
    final fix = parseFixes(_output.text);
    if (fix != null) {
      setState(() => _errors = fix.errors);
      if (fix.errors.isEmpty) offerFixes(context, fix, onDone: _leave);
      return;
    }
    // Yapıştırılan şey bir kurs paketiyse bütün kursları birden ekle
    final pack = parsePack(_output.text);
    if (pack != null) {
      setState(() => _errors = pack.pack == null ? [...pack.errors, ...pack.warnings.take(6)] : []);
      if (pack.pack != null) offerPack(context, pack, onAdded: _leave);
      return;
    }
    final report = parseCourse(_output.text);
    final parsed = report.course;
    if (parsed == null) {
      // Atlanan parçalar hatanın nedenini gösterir (ör. yapay zekâ bir alanı yanlış adlandırmışsa)
      setState(() {
        _tab = 1;
        _errors = [...report.errors, ...report.notes, ...report.warnings.take(6)];
      });
      return;
    }
    setState(() => _errors = []);
    // Yeni kısım, var olan bir kursla aynı kimliği taşıyorsa ayrı bir kurs olarak eklenir (öbür kısmın üzerine yazılmaz)
    final id = widget.group != null && _building == null ? freeId(parsed.id, app.courses.containsKey) : parsed.id;
    final incoming = id == parsed.id ? parsed : parsed.copyWith(id: id);
    final building = _building;
    final existing = building ?? app.courses[incoming.id];
    final summary = _summary(incoming);
    final skipped = report.warnings.isEmpty && report.notes.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eksik kalan üniteler gibi kullanıcının bir şey yapmasını gerektiren notlar önce gelir
              for (final n in report.notes)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(n, style: ts(14.5, w: FontWeight.w800, color: context.p.goldInk))),
              if (report.warnings.isNotEmpty) Text(t('import.skipped', {'n': report.warnings.length}), style: ts(14.5, w: FontWeight.w800, color: context.p.ink2)),
              for (final w in report.warnings.take(8)) Text('• $w', style: ts(13.5, color: context.p.ink2)),
            ],
          );
    // Dosya ya da bağlantıdan gelen kurs kendini var olan bir büyük kursun kısmı olarak tanıtıyorsa önce sorulur
    final joins = widget.group == null && app.groups.contains(incoming.group);
    if (existing == null) {
      if (skipped == null && !joins) return _done(incoming, t('import.added', {'summary': summary}));
      showBilgeDialog(
        context,
        title: incoming.title,
        text: [t('import.willAdd', {'summary': summary}), if (joins) t('import.joins', {'group': incoming.group})].join('\n'),
        body: skipped,
        actions: [
          DialogAction(t('import.addCourse'), onPressed: () => _done(incoming, t('import.added', {'summary': summary}))),
          DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
        ],
      );
      return;
    }
    // Bu ekranda büyütülen bir kurs yoksa kimlik başka bir kursla çakışıyor demektir: kullanıcı seçer
    if (building == null) return _offerClash(context, existing: existing, incoming: incoming, body: skipped, onDone: _done);
    // Sıradaki üniteler geldiyse (kimlikleri yeni, atlanan bir şey yok) sormadan ekle
    if (skipped == null && incoming.units.every((u) => existing.units.every((x) => x.id != u.id))) {
      final m = mergeCourses(existing, incoming);
      return _done(m.course, t('import.merged', {'a': m.added, 'u': m.updated}));
    }
    final foreign = incoming.id != existing.id && !app.courses.containsKey(incoming.id);
    showBilgeDialog(
      context,
      title: t('import.updateTitle', {'title': existing.title}),
      text: [t('import.updateText', {'summary': summary}), if (foreign && joins) t('import.joinsSeparate', {'group': incoming.group})].join('\n'),
      body: skipped,
      actions: [
        DialogAction(t('import.merge'), onPressed: () {
          final m = mergeCourses(existing, incoming);
          _done(m.course, t('import.merged', {'a': m.added, 'u': m.updated}));
        }),
        foreign
            ? DialogAction(t('import.separate'), kind: ButtonKind.ghost, onPressed: () => _done(incoming, t('import.added', {'summary': summary})))
            : DialogAction(t('import.replace'), kind: ButtonKind.ghost, onPressed: () => _done(incoming.copyWith(id: existing.id, group: existing.group), t('import.replaced', {'summary': summary}))),
        DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
      ],
    );
  }

  Future<void> _paste() async {
    final text = await clipboardText();
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) return toast(context, t('import.clipboardEmpty'));
    setState(() => _output.text = text);
  }

  Future<void> _fromFile() async {
    try {
      final text = await pickTextFile();
      if (text == null || !mounted) return;
      setState(() => _output.text = text);
      _import();
    } on TooBigException catch (e) {
      if (mounted) toast(context, t('err.tooBig', {'mb': e.megabytes}));
    } catch (_) {
      if (mounted) toast(context, t('import.fileFailed'));
    }
  }

  void _fromUrl() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FromUrlSheet(
        onImport: (text) {
          if (!mounted) return;
          setState(() => _output.text = text);
          _import();
        },
      ),
    );
  }

  /* ----- arayüz ----- */

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.p;
    final target = widget.target;
    final hasAiKey = app.settings.aiKey.trim().isNotEmpty;
    Widget label(String text) => Padding(padding: const EdgeInsets.only(bottom: 6, top: 14), child: Text(text, style: ts(14, w: FontWeight.w900, color: p.ink2)));
    Widget tab(int i, String text) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _tab == i ? p.surface : null, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _tab == i ? p.primary : p.line, shape: BoxShape.circle),
                  child: Text('${i + 1}', style: ts(13, w: FontWeight.w900, color: _tab == i ? Colors.white : p.ink2, height: 1)),
                ),
                const SizedBox(width: 8),
                Text(text, style: ts(15, w: FontWeight.w900, color: _tab == i ? p.primaryInk : p.ink2)),
              ]),
            ),
          ),
        );

    final clipBanner = _clipLabel != null && _clipRaw != null
        ? Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: _Callout(
              color: p.goodSoft,
              children: [
                Row(
                  children: [
                    Icon(Icons.content_paste_go_rounded, size: 20, color: p.goodInk),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t('clip.found'), style: ts(14.5, w: FontWeight.w900, color: p.goodInk))),
                    GestureDetector(
                      onTap: () => setState(() => _clipLabel = null),
                      child: Icon(Icons.close_rounded, size: 20, color: p.goodInk),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ChunkyButton(
                  label: _clipLabel!,
                  kind: ButtonKind.good,
                  onPressed: () {
                    final raw = _clipRaw!;
                    setState(() {
                      _clipLabel = null;
                      _output.text = raw;
                    });
                    _import();
                  },
                ),
              ],
            ),
          )
        : null;

    final promptTab = <Widget>[
      ?clipBanner,
      if (target != null)
        _Callout(children: [
          Text(t('create.continuing', {'title': target.title}), style: ts(16, w: FontWeight.w900, color: p.ink)),
          Text(t('create.continuingText'), style: ts(15, color: p.ink2)),
        ])
      else ...[
        if (widget.group case final group?)
          _Callout(children: [
            Text(t('create.sectionTitle', {'group': group, 'n': app.sectionsOf(group).length + 1}), style: ts(16, w: FontWeight.w900, color: p.ink)),
            Text(t('create.sectionText'), style: ts(15, color: p.ink2)),
          ]),
        label(t('create.topic')),
        _Field(controller: _topic, focus: _topicFocus, hint: t('create.topicHint'), lines: 2, onChanged: (_) => setState(() {})),
        label(t('create.level')),
        _Segments(
          value: _options.level,
          options: {for (final k in promptLevels.keys) k: t('level.$k')},
          onChanged: (v) => setState(() => _options.level = v),
        ),
      ],
      // Konu ve seviye yeter: gerisi hazır değerlerle gelir, isteyen açıp değiştirir
      const SizedBox(height: 10),
      Semantics(
        button: true,
        child: GestureDetector(
          key: const ValueKey('create-details'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _details = !_details),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('create.details'), style: ts(14.5, w: FontWeight.w900, color: p.ink)),
                      Text(
                        [
                          t('create.summary', {
                            'u': _options.units,
                            'l': _options.lessons,
                            'd': t('density.${_options.density}').toLowerCase(),
                            'm': _options.perMessage == 0 ? t('create.sumAll') : t('create.sumPer', {'n': _options.perMessage}),
                          }),
                          if (_goal.text.trim().isNotEmpty) t('create.sumGoal'),
                        ].join(' · '),
                        style: ts(13.5, color: p.ink2),
                      ),
                    ],
                  ),
                ),
                Icon(_details ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.ink2),
              ],
            ),
          ),
        ),
      ),
      if (_details) ...[
        label(t(target == null ? 'create.goal' : 'create.focus')),
        _Field(controller: _goal, hint: t('create.goalHint'), onChanged: (_) => setState(() {})),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label(t(target == null ? 'create.units' : 'create.newUnits')), _Stepper(value: _options.units, min: 1, max: 12, onChanged: (v) => setState(() => _options.units = v))])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label(t('create.lessons')), _Stepper(value: _options.lessons, min: 2, max: 6, onChanged: (v) => setState(() => _options.lessons = v))])),
          ],
        ),
        label(t('create.density')),
        _Segments(
          value: _options.density,
          options: {for (final k in promptDensity.keys) k: t('density.$k')},
          onChanged: (v) => setState(() => _options.density = v),
        ),
        label(t('create.perMessage')),
        Segments<int>(
          value: _options.perMessage,
          options: {1: '1', 3: '3', 0: t('create.perAll')},
          onChanged: (v) => setState(() => _options.perMessage = v),
        ),
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('create.perHint'), style: ts(13.5, color: p.ink3))),
      ],
      const SizedBox(height: 18),
      if (hasAiKey) ...[
        ChunkyButton(
          label: t(_generating ? 'create.generating' : 'create.generateAi'),
          icon: Icons.auto_awesome_rounded,
          kind: ButtonKind.good,
          onPressed: _generating ? null : _generateWithAi,
        ),
        const SizedBox(height: 8),
      ],
      ChunkyButton(label: t('create.copy'), icon: Icons.copy_rounded, onPressed: _copy),
      const SizedBox(height: 8),
      ChunkyButton(
        label: t('create.shareTemplate'),
        icon: Icons.ios_share_rounded,
        kind: ButtonKind.ghost,
        onPressed: () => _topicReady() ? shareFile('bilge-kalip.md', _prompt) : null,
      ),
      if (_copied) ...[
        const SizedBox(height: 14),
        _Callout(key: _nextKey, children: [
          Text(t('create.next.title'), style: ts(16, w: FontWeight.w900, color: p.ink)),
          for (var i = 1; i <= 4; i++) Text('$i. ${t('create.next.$i')}', style: ts(15, color: p.ink)),
          Text(t('create.next.share'), style: ts(14.5, w: FontWeight.w700, color: p.ink2)),
          const SizedBox(height: 6),
          ChunkyButton(label: t('create.goImport'), onPressed: () => setState(() => _tab = 1)),
        ]),
      ],
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() => _showTemplate = !_showTemplate),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_showTemplate ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.ink2),
          Text(t('create.showTemplate'), style: ts(15, w: FontWeight.w800, color: p.ink2)),
        ]),
      ),
      if (_showTemplate)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF231D3A), borderRadius: BorderRadius.circular(12)),
          child: SelectableText(_prompt, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5, color: Color(0xFFEDE9FF))),
        ),
    ];

    Widget tool(IconData icon, String text, VoidCallback onTap) => TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 19, color: p.ink2),
          label: Text(text, style: ts(14, w: FontWeight.w800, color: p.ink2)),
        );
    final building = _building;
    final left = building == null ? 0 : building.outline.length - building.units.length;
    final importTab = <Widget>[
      ?clipBanner,
      const SizedBox(height: 14),
      if (building != null && left > 0) ...[
        // Parça parça gelen kurs: ne kadarının hazır olduğu ve şimdi ne yapılacağı
        _Callout(children: [
          Text(t('import.progress', {'done': building.units.length, 'total': building.outline.length}), style: ts(17, w: FontWeight.w900, color: p.ink)),
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Bar(value: building.units.length / building.outline.length, color: p.primary, track: p.surface, height: 10)),
          Text(t('import.nextUnit', {'title': building.outline[building.units.length]}), style: ts(15, w: FontWeight.w800, color: p.ink)),
          Text(t('import.sayContinue'), style: ts(15, color: p.ink)),
          if (hasAiKey) ...[
            const SizedBox(height: 10),
            ChunkyButton(
              label: t(_generating ? 'create.generating' : 'create.generateNextAi'),
              icon: Icons.auto_awesome_rounded,
              kind: ButtonKind.good,
              onPressed: _generating ? null : _generateNextWithAi,
            ),
          ],
        ]),
        const SizedBox(height: 10),
      ],
      _Field(controller: _output, hint: t('import.hint'), lines: 9, mono: true),
      Wrap(children: [
        tool(Icons.content_paste_rounded, t('import.paste'), _paste),
        tool(Icons.description_rounded, t('import.file'), _fromFile),
        tool(Icons.link_rounded, t('import.url'), _fromUrl),
      ]),
      const SizedBox(height: 6),
      ChunkyButton(label: t('import.check'), onPressed: _import),
      if (building != null && left > 0 && widget.target == null) ...[
        const SizedBox(height: 8),
        ChunkyButton(label: t('create.finishNow'), kind: ButtonKind.primary, onPressed: () => _leave(t('import.added', {'summary': _summary(building)}))),
        const SizedBox(height: 8),
        ChunkyButton(label: t('import.later'), kind: ButtonKind.ghost, onPressed: _leave),
      ],
      if (_errors.isNotEmpty) ...[
        const SizedBox(height: 14),
        _Callout(color: p.badSoft, children: [
          Text(t('import.failed'), style: ts(16, w: FontWeight.w900, color: p.badInk)),
          for (final e in _errors) Text('• $e', style: ts(14.5, color: p.badInk)),
        ]),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                  child: Row(children: [
                    IconTap(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).pop(), label: t('common.back')),
                    Expanded(child: Text(t(target == null ? 'create.title' : 'create.addUnitTitle'), style: ts(24, w: FontWeight.w900, color: p.ink, height: 1.2))),
                  ]),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [tab(0, t('create.tab1')), const SizedBox(width: 6), tab(1, t('create.tab2'))]),
                ),
                Expanded(
                  child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: _tab == 0 ? promptTab : importTab),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- Form parçaları ---------- */

class _Callout extends StatelessWidget {
  const _Callout({super.key, required this.children, this.color});
  final List<Widget> children;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: color ?? context.p.primarySoft, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 4), child: c)]),
      );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.lines = 1, this.mono = false, this.focus, this.keyboard, this.onChanged});
  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool mono;
  final FocusNode? focus;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    OutlineInputBorder border(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: 2));
    return TextField(
      controller: controller,
      focusNode: focus,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      keyboardType: keyboard ?? (lines > 1 ? TextInputType.multiline : null),
      autocorrect: !mono,
      enableSuggestions: !mono,
      onChanged: onChanged,
      style: mono ? TextStyle(fontFamily: 'monospace', fontSize: 13, color: p.ink, height: 1.4) : ts(16, color: p.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ts(mono ? 14 : 16, w: FontWeight.w600, color: p.ink3),
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: border(p.line2),
        focusedBorder: border(p.primary),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.value, required this.options, required this.onChanged});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Segments<String>(value: value, options: options, onChanged: onChanged);
}

/// Yan yana seçenek düğmeleri (seviye, tema, dil gibi).
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        for (final (i, e) in options.entries.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Sfx.play('tap');
                onChanged(e.key);
              },
              child: Container(
                height: 46,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: e.key == value ? p.primarySoft : p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: e.key == value ? p.primary : p.line2, width: 2),
                ),
                child: FittedBox(child: Text(e.value, style: ts(15, w: FontWeight.w800, color: e.key == value ? p.primaryInk : p.ink))),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget button(IconData icon, int delta) => IconButton(
          onPressed: () => onChanged((value + delta).clamp(min, max)),
          icon: Icon(icon, color: p.primaryInk),
        );
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line2, width: 2)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [button(Icons.remove_rounded, -1), Text('$value', style: ts(18, w: FontWeight.w900, color: p.ink)), button(Icons.add_rounded, 1)],
      ),
    );
  }
}

class _FromUrlSheet extends StatefulWidget {
  const _FromUrlSheet({required this.onImport});
  final void Function(String text) onImport;

  @override
  State<_FromUrlSheet> createState() => _FromUrlSheetState();
}

class _FromUrlSheetState extends State<_FromUrlSheet> {
  final TextEditingController url = TextEditingController();

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return sheetBody(
      context,
      padding: EdgeInsets.fromLTRB(20, 22, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      head: [
        Text(t('import.urlTitle'), style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25)),
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('import.urlText'), style: ts(15.5, color: p.ink2))),
      ],
      scroll: [
        Padding(padding: const EdgeInsets.only(top: 10), child: _Field(controller: url, hint: 'https://…/kurs.bilge.json', keyboard: TextInputType.url)),
      ],
      foot: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyButton(
            label: t('import.urlGet'),
            onPressed: () async {
              final link = url.text.trim();
              if (!RegExp(r'^https://\S+$', caseSensitive: false).hasMatch(link)) return toast(context, t('import.urlInvalid'));
              try {
                final text = await fetchText(link);
                if (!context.mounted) return;
                Navigator.of(context).pop();
                widget.onImport(text);
              } on TooBigException catch (e) {
                if (context.mounted) toast(context, t('err.tooBig', {'mb': e.megabytes}));
              } catch (_) {
                if (context.mounted) toast(context, t('import.urlFailed'));
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyButton(
            label: t('common.cancel'),
            kind: ButtonKind.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
