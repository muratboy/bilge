/// "Profil" sekmesi: seviye, hafta, istatistikler, ekip, rozetler, ayarlar ve yedek.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Badge;

import '../app_scope.dart';
import '../core/store.dart';
import '../core/text_utils.dart';
import '../l10n/l10n.dart';
import '../mascot/cast.dart';
import '../mascot/mascot_art.dart';
import '../mascot/mascot_view.dart';
import '../ui/io.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'manage.dart' show Segments;
import 'welcome.dart' show CharacterCard, CharacterPicker;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  MascotId? _viewing; // ekipte incelenen karakter

  Future<void> _restore(AppState app) async {
    try {
      final text = await pickTextFile(maxBytes: maxBackupBytes);
      if (text == null) return;
      await app.restoreFrom(text);
      if (mounted) toast(context, t('profile.restored'));
    } on TooBigException catch (e) {
      if (mounted) toast(context, t('err.tooBig', {'mb': e.megabytes}));
    } catch (_) {
      if (mounted) toast(context, t('profile.restoreFailed'));
    }
  }

  Future<void> _backup(AppState app) async {
    try {
      await app.manualBackup();
      if (mounted) toast(context, t('backup.done'));
    } catch (_) {
      if (mounted) toast(context, t('backup.failed'));
    }
  }

  void _restoreBackup(AppState app, BackupInfo backup) => showBilgeDialog(
        context,
        title: t('backup.restoreTitle'),
        text: t('backup.restoreText', {'date': formatStamp(backup.time)}),
        actions: [
          DialogAction(t('backup.restore'), onPressed: () async {
            try {
              await app.restoreBackup(backup);
              if (mounted) toast(context, t('profile.restored'));
            } catch (_) {
              if (mounted) toast(context, t('profile.restoreFailed'));
            }
          }),
          DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
        ],
      );

  Future<void> _shareBackup(AppState app, BackupInfo backup) async {
    final text = await app.backupText(backup);
    if (text != null) await shareFile('bilge-yedek-${dayKey(backup.time)}.json', text);
  }

  void _syncReminder(AppState app) {
    final s = app.settings;
    scheduleReminder(
      enabled: s.reminder,
      hour: s.reminderHour,
      title: t('reminder.notifTitle'),
      body: t('reminder.notifBody'),
      lastActive: app.profile.lastActive,
    );
  }

  void _showBadgeDetail(AppState app, Badge b) {
    final p = context.p;
    final earnedDate = app.profile.badges[b.id];
    final prog = earnedDate == null ? app.badgeProgress(b) : null;
    final maxLabel = prog == null ? '' : (prog.unit != null ? '${prog.max} ${prog.unit}' : '${prog.max}');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => sheetBody(
        sheet,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        head: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: earnedDate != null ? p.goldSoft : p.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: earnedDate != null ? Palette.gold : p.line, width: 2.5),
              ),
              child: Opacity(
                opacity: earnedDate != null ? 1 : 0.45,
                child: Text(b.icon, style: const TextStyle(fontSize: 40)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(b.name, textAlign: TextAlign.center, style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25)),
          const SizedBox(height: 6),
          Text(b.desc, textAlign: TextAlign.center, style: ts(15, w: FontWeight.w700, color: p.ink2)),
          const SizedBox(height: 14),
        ],
        scroll: [
          if (earnedDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_rounded, color: Palette.gold, size: 20),
                  const SizedBox(width: 8),
                  Text(t('badge.earnedOn', {'date': earnedDate}), style: ts(14.5, w: FontWeight.w900, color: p.goldInk)),
                ],
              ),
            )
          else if (prog != null) ...[
            Bar(value: prog.max == 0 ? 0 : prog.cur / prog.max, color: Palette.gold, track: p.line, height: 12),
            const SizedBox(height: 8),
            Text(
              t('badge.progress', {'cur': prog.cur, 'max': maxLabel}),
              textAlign: TextAlign.center,
              style: ts(14, w: FontWeight.w800, color: p.ink2),
            ),
          ] else
            Text(t('badge.locked'), textAlign: TextAlign.center, style: ts(14, w: FontWeight.w800, color: p.ink3)),
        ],
        foot: [
          const SizedBox(height: 14),
          ChunkyButton(
            label: t('common.close'),
            kind: ButtonKind.ghost,
            onPressed: () => Navigator.of(sheet).pop(),
          ),
        ],
      ),
    );
  }

  void _showAiSettings(AppState app) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AiSettingsSheet(app: app),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.p;
    final set = app.settings;
    final prof = app.profile;
    final lv = app.level;
    final viewing = characterOf(_viewing ?? app.buddy.id);
    final days = L.list('profile.days');

    Widget title(String text) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text(text, style: ts(19, w: FontWeight.w900, color: p.ink)));
    Widget stat(IconData icon, Color color, String value, String label) => Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.15)),
                Text(label, style: ts(13, w: FontWeight.w800, color: p.ink3, height: 1.25)),
              ]),
            ),
          ]),
        );
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged, {String? hint, Key? key}) => InkWell(
          key: key,
          onTap: () {
            onChanged(!value);
            app.commit();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: ts(16, w: FontWeight.w800, color: p.ink)),
                  if (hint != null) Text(hint, style: ts(13.5, color: p.ink2)),
                ]),
              ),
              Switch(
                value: value,
                activeTrackColor: p.good,
                onChanged: (v) {
                  onChanged(v);
                  app.commit();
                },
              ),
            ]),
          ),
        );
    Widget choice<T>(String label, T value, Map<T, String> options, ValueChanged<T> onChanged) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(label, style: ts(16, w: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 8),
            Segments<T>(
              value: value,
              options: options,
              onChanged: (v) {
                onChanged(v);
                app.commit();
              },
            ),
          ]),
        );
    final divider = Container(height: 2, color: p.line);

    final heatmapDays = [for (var i = 83; i >= 0; i--) addDays(app.today, -i)];
    final activeDaysCount = heatmapDays.where((d) => (prof.xpByDay[d] ?? 0) > 0).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: p.primaryD, offset: const Offset(0, 5))]),
              child: Row(children: [
                MascotView(app.buddy.id, size: 128),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('profile.level', {'n': lv.level}), style: ts(24, w: FontWeight.w900, color: Colors.white, height: 1.1)),
                    const SizedBox(height: 8),
                    Bar(value: lv.fraction, color: Palette.gold, track: Colors.white.withValues(alpha: 0.28), height: 12),
                    const SizedBox(height: 6),
                    Builder(builder: (_) {
                      final curXp = math.max(prof.xp, prof.totalXp);
                      return Text(t('profile.xpNext', {'xp': curXp, 'left': lv.to - curXp}), style: ts(14, w: FontWeight.w800, color: Colors.white.withValues(alpha: 0.92)));
                    }),
                  ]),
                ),
              ]),
            ),
            title(t('profile.week')),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Row(
                children: [
                  for (var i = 6; i >= 0; i--)
                    Expanded(
                      child: Builder(builder: (_) {
                        final day = addDays(app.today, -i);
                        final xp = prof.xpByDay[day] ?? 0;
                        final met = xp >= set.dailyGoal;
                        final parts = day.split('-').map(int.parse).toList();
                        return Column(children: [
                          Tooltip(
                            message: '$day · $xp XP',
                            triggerMode: TooltipTriggerMode.tap,
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: met ? Palette.gold : (xp > 0 ? p.goldSoft : p.surface2),
                                    shape: BoxShape.circle,
                                    border: i == 0 ? Border.all(color: p.primary, width: 2.5) : null,
                                  ),
                                  child: met
                                      ? const Icon(Icons.check_rounded, size: 20, color: Color(0xFF5A3F00))
                                      : Text(xp > 0 ? '$xp' : '', style: ts(12, w: FontWeight.w900, color: p.goldInk, height: 1)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(days[DateTime(parts[0], parts[1], parts[2]).weekday - 1], style: ts(12, w: FontWeight.w800, color: i == 0 ? p.primaryInk : p.ink3)),
                        ]);
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: stat(Icons.local_fire_department_rounded, Palette.fire, '${app.streak}', t('stat.streak'))),
              const SizedBox(width: 10),
              Expanded(child: stat(Icons.bolt_rounded, Palette.gold, '${prof.xp}', t('stat.xp'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: stat(Icons.check_rounded, p.good, '${prof.lessonsDone}', t('stat.lessons'))),
              const SizedBox(width: 10),
              Expanded(child: stat(Icons.star_rounded, Palette.blue, prof.answered == 0 ? '–' : '${(prof.correct / prof.answered * 100).round()}%', t('stat.accuracy'))),
            ]),
            const SizedBox(height: 10),
            // Seri dondurma (Streak Freeze)
            Panel(
              key: const ValueKey('freeze-card'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.ac_unit_rounded, color: Palette.blue, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(t('freeze.title'), style: ts(15.5, w: FontWeight.w900, color: p.ink)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Palette.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
                              child: Text(t('freeze.have', {'n': prof.freezes}), style: ts(12, w: FontWeight.w900, color: Palette.blue)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(t('freeze.desc'), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12.5, color: p.ink2)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey('buy-freeze-btn'),
                    onPressed: prof.freezes < 2 && prof.xp >= 50
                        ? () {
                            if (app.buyFreeze()) toast(context, t('freeze.bought'));
                          }
                        : null,
                    child: Text(
                      prof.freezes >= 2
                          ? t('freeze.maxed')
                          : (prof.xp < 50 ? t('freeze.needXp', {'xp': 50}) : t('freeze.buy', {'xp': 50})),
                      style: ts(13, w: FontWeight.w900, color: prof.freezes < 2 && prof.xp >= 50 ? Palette.blue : p.ink3),
                    ),
                  ),
                ],
              ),
            ),

            // 12 haftalık etkinlik ısı haritası
            title(t('profile.heatmap')),
            Panel(
              key: const ValueKey('heatmap-panel'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Kicker(t('profile.activeDays', {'n': activeDaysCount})),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var w = 0; w < 12; w++)
                        Column(
                          children: [
                            for (var d = 0; d < 7; d++)
                              Builder(builder: (_) {
                                final day = heatmapDays[w * 7 + d];
                                final xp = prof.xpByDay[day] ?? 0;
                                final color = xp == 0
                                    ? p.surface2
                                    : (xp >= set.dailyGoal ? p.good : p.good.withValues(alpha: 0.45));
                                return Tooltip(
                                  message: '$day · $xp XP',
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),

            title(t('profile.badges')),
            LayoutBuilder(
              builder: (_, box) {
                final cols = (box.maxWidth / 90).floor().clamp(3, 6);
                const gap = 8.0;
                final width = (box.maxWidth - (cols - 1) * gap) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final b in badges)
                      SizedBox(
                        width: width,
                        child: Builder(builder: (_) {
                          final on = prof.badges.containsKey(b.id);
                          return GestureDetector(
                            key: ValueKey('badge-${b.id}'),
                            onTap: () => _showBadgeDetail(app, b),
                            child: Panel(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                              color: on ? p.goldSoft : p.surface,
                              border: on ? Palette.gold : p.line,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Opacity(
                                        opacity: on ? 1.0 : 0.35,
                                        child: Text(b.icon, style: const TextStyle(fontSize: 32, height: 1.15)),
                                      ),
                                      if (!on)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(color: p.surface2, shape: BoxShape.circle),
                                            child: Icon(Icons.lock_rounded, size: 11, color: p.ink3),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    b.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: ts(12, w: FontWeight.w800, color: on ? p.ink : p.ink3, height: 1.15),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                );
              },
            ),

            title(t('profile.crew')),
            CharacterPicker(selected: viewing.id, onPick: (id) => setState(() => _viewing = id)),
            const SizedBox(height: 10),
            CharacterCard(character: viewing),
            const SizedBox(height: 8),
            if (viewing.id == app.buddy.id)
              Center(child: Text('★ ${t('profile.isCompanion')}', style: ts(14.5, w: FontWeight.w900, color: p.goldInk)))
            else
              ChunkyButton(
                label: t('profile.makeCompanion'),
                kind: ButtonKind.ghost,
                onPressed: () => app
                  ..companion = viewing.id
                  ..commit(),
              ),

            title(t('profile.settings')),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                choice<String>(t('set.lang'), set.lang, {'auto': t('lang.auto'), 'tr': 'Türkçe', 'en': 'English'}, (v) {
                  set.lang = v;
                  _syncReminder(app);
                }),
                divider,
                choice<String>(t('set.theme'), set.theme, {'auto': t('theme.auto'), 'light': t('theme.light'), 'dark': t('theme.dark')}, (v) => set.theme = v),
                divider,
                choice<int>(t('set.goal'), set.dailyGoal, {for (final g in [10, 20, 30, 50]) g: '$g XP'}, (v) => set.dailyGoal = v),
                divider,
                toggle(t('set.sound'), set.sound, (v) => set.sound = v),
                divider,
                toggle(t('set.hearts'), set.hearts, (v) => set.hearts = v, hint: t('set.heartsHint')),
                divider,
                toggle(t('set.free'), set.freeMode, (v) => set.freeMode = v, hint: t('set.freeHint')),
                divider,
                toggle(
                  t('set.reminder'),
                  set.reminder,
                  (v) {
                    set.reminder = v;
                    _syncReminder(app);
                  },
                  hint: t('set.reminderHint'),
                  key: const ValueKey('set-reminder-toggle'),
                ),
                if (set.reminder)
                  choice<int>(
                    t('set.reminderTime'),
                    set.reminderHour,
                    {for (final h in [8, 12, 18, 20, 22]) h: '${h.toString().padLeft(2, '0')}:00'},
                    (v) {
                      set.reminderHour = v;
                      _syncReminder(app);
                    },
                  ),
                divider,
                InkWell(
                  key: const ValueKey('set-ai-row'),
                  onTap: () => _showAiSettings(app),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('set.ai'), style: ts(16, w: FontWeight.w800, color: p.ink)),
                              Text(
                                set.aiKey.trim().isEmpty ? t('set.aiHint') : '${set.aiProvider.toUpperCase()} · ••••',
                                style: ts(13.5, color: set.aiKey.trim().isEmpty ? p.ink2 : p.goodInk),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: p.ink3),
                      ],
                    ),
                  ),
                ),
              ]),
            ),

            title(t('profile.data')),
            Text(t('profile.dataText'), style: ts(15, color: p.ink2)),
            const SizedBox(height: 12),
            ChunkyButton(label: t('profile.backup'), icon: Icons.save_rounded, onPressed: () => _backup(app)),
            const SizedBox(height: 12),
            // Cihazdaki yedekler: elle alınan en üstte, ardından otomatikler (en yenisi önce)
            if (app.backups.isEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t('backup.none'), style: ts(14.5, color: p.ink3)))
            else
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, b) in [...app.backups.where((b) => b.manual), ...app.backups.where((b) => !b.manual)].indexed) ...[
                      if (i > 0) divider,
                      Padding(
                        key: ValueKey('backup-${b.name}'),
                        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                        child: Row(
                          children: [
                            Icon(b.manual ? Icons.push_pin_rounded : Icons.autorenew_rounded, size: 22, color: b.manual ? p.goldInk : p.ink3),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t(b.manual ? 'backup.manual' : 'backup.auto'), style: ts(15.5, w: FontWeight.w900, color: p.ink, height: 1.25)),
                                  Text(formatStamp(b.time), style: ts(13.5, w: FontWeight.w700, color: p.ink2, height: 1.25)),
                                ],
                              ),
                            ),
                            IconTap(icon: Icons.ios_share_rounded, label: t('backup.share'), color: p.ink2, onTap: () => _shareBackup(app, b)),
                            TextButton(onPressed: () => _restoreBackup(app, b), child: Text(t('backup.restore'), style: ts(14, w: FontWeight.w900, color: p.primaryInk))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            ChunkyButton(label: t('profile.restore'), icon: Icons.upload_rounded, kind: ButtonKind.ghost, onPressed: () => _restore(app)),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => showBilgeDialog(
                  context,
                  title: t('profile.resetTitle'),
                  text: t('profile.resetText'),
                  actions: [DialogAction(t('profile.resetConfirm'), kind: ButtonKind.bad, onPressed: app.resetWithBackup), DialogAction(t('common.cancel'), kind: ButtonKind.ghost)],
                ),
                icon: Icon(Icons.delete_rounded, color: p.badInk, size: 20),
                label: Text(t('profile.reset'), style: ts(14.5, w: FontWeight.w800, color: p.badInk)),
              ),
            ),
            Center(child: Text('Bilge 0.15.0-beta', style: ts(12.5, w: FontWeight.w800, color: p.ink3))),
          ],
        ),
      ),
    );
  }
}

class _AiSettingsSheet extends StatefulWidget {
  const _AiSettingsSheet({required this.app});
  final AppState app;

  @override
  State<_AiSettingsSheet> createState() => _AiSettingsSheetState();
}

class _AiSettingsSheetState extends State<_AiSettingsSheet> {
  late String provider = widget.app.settings.aiProvider;
  late final TextEditingController keyCtrl = TextEditingController(text: widget.app.settings.aiKey);
  late final TextEditingController modelCtrl = TextEditingController(text: widget.app.settings.aiModel);

  @override
  void dispose() {
    keyCtrl.dispose();
    modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final set = widget.app.settings;
    return sheetBody(
      context,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      head: [
        Text(t('set.ai'), style: ts(20, w: FontWeight.w900, color: p.ink)),
        const SizedBox(height: 4),
        Text(t('set.aiHint'), style: ts(14, color: p.ink2)),
        const SizedBox(height: 12),
      ],
      scroll: [
        Kicker(t('set.aiProvider')),
        const SizedBox(height: 6),
        Segments<String>(
          value: provider,
          options: const {'gemini': 'Gemini', 'openai': 'OpenAI', 'claude': 'Claude'},
          onChanged: (v) => setState(() => provider = v),
        ),
        const SizedBox(height: 14),
        Kicker(t('set.aiKey')),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('ai-key-field'),
          controller: keyCtrl,
          obscureText: true,
          style: ts(15, w: FontWeight.w700, color: p.ink),
          decoration: InputDecoration(hintText: t('set.aiKeyHint')),
        ),
        const SizedBox(height: 14),
        Kicker(t('set.aiModel')),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('ai-model-field'),
          controller: modelCtrl,
          style: ts(15, w: FontWeight.w700, color: p.ink),
          decoration: InputDecoration(hintText: t('set.aiModelHint')),
        ),
      ],
      foot: [
        const SizedBox(height: 12),
        ChunkyButton(
          label: t('common.save'),
          onPressed: () {
            set
              ..aiProvider = provider
              ..aiKey = keyCtrl.text.trim()
              ..aiModel = modelCtrl.text.trim();
            widget.app.commit();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
