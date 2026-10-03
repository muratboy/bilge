import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/l10n.dart';
import '../mascot/cast.dart';
import '../mascot/mascot_art.dart';
import '../mascot/mascot_view.dart';
import '../ui/sfx.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// İlk açılış: ekip kendini tanıtır, kullanıcı yol arkadaşını seçer.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  MascotId _pick = MascotId.puhu;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = characterOf(_pick);
    final compact = isCompact(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, compact ? 10 : 20, 16, compact ? 12 : 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cihaz dili yanlış tahmin edildiyse ilk ekranda düzeltilebilsin
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final (code, name) in const [('tr', 'Türkçe'), ('en', 'English')])
                        GestureDetector(
                          onTap: () => AppScope.read(context)
                            ..settings.lang = code
                            ..commit(),
                          child: Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: L.code == code ? p.primarySoft : null,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: L.code == code ? p.primary : p.line2, width: 2),
                            ),
                            child: Text(name, style: ts(13.5, w: FontWeight.w800, color: L.code == code ? p.primaryInk : p.ink2, height: 1.2)),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? 6 : 14),
                  Text(t('welcome.title'), textAlign: TextAlign.center, style: ts(compact ? 22 : 28, w: FontWeight.w900, color: p.ink, height: 1.2)),
                  SizedBox(height: compact ? 2 : 6),
                  Text(t('welcome.lead'), textAlign: TextAlign.center, style: ts(compact ? 14.5 : 16.5, color: p.ink2)),
                  SizedBox(height: compact ? 8 : 18),
                  Kicker(t('welcome.pick')),
                  const SizedBox(height: 8),
                  CharacterPicker(selected: _pick, onPick: (id) => setState(() => _pick = id)),
                  SizedBox(height: compact ? 8 : 14),
                  CharacterCard(character: c, mood: Mood.cheer),
                  SizedBox(height: compact ? 4 : 6),
                  Text(t('welcome.pickHint'), textAlign: TextAlign.center, style: ts(14, color: p.ink3)),
                  SizedBox(height: compact ? 8 : 16),
                  ChunkyButton(
                    label: t('welcome.start', {'name': c.name}),
                    onPressed: () {
                      Sfx.play('pop');
                      AppScope.read(context)
                        ..companion = _pick
                        ..commit();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ekibin tamamını yan yana gösterir; biri seçilebilir.
class CharacterPicker extends StatelessWidget {
  const CharacterPicker({super.key, required this.selected, required this.onPick});
  final MascotId selected;
  final ValueChanged<MascotId> onPick;

  @override
  Widget build(BuildContext context) {
    if (isCompact(context)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final c in cast)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: 64,
                  child: TapCard(
                    state: c.id == selected ? CardState.selected : CardState.idle,
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                    onTap: () {
                      Sfx.play('tap');
                      onPick(c.id);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MascotView(c.id, size: 40, still: true),
                        const SizedBox(height: 2),
                        FittedBox(child: Text(c.name, style: ts(12, w: FontWeight.w900, height: 1.1))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, box) {
        final width = (box.maxWidth - 3 * 8) / 4;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cast)
              SizedBox(
                width: width,
                child: TapCard(
                  state: c.id == selected ? CardState.selected : CardState.idle,
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  onTap: () {
                    Sfx.play('tap');
                    onPick(c.id);
                  },
                  child: Column(children: [
                    MascotView(c.id, size: 64, still: true),
                    const SizedBox(height: 2),
                    FittedBox(child: Text(c.name, style: ts(14, w: FontWeight.w900, height: 1.2))),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bir karakterin tanıtım kartı: çizim, tür, kişilik ve kendi ağzından bir selam.
class CharacterCard extends StatelessWidget {
  const CharacterCard({super.key, required this.character, this.mood = Mood.happy});
  final Character character;
  final Mood mood;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = character;
    final v = c.voice;
    return Panel(
      border: Color(c.color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MascotView(c.id, mood: mood, size: 150, key: ValueKey(c.id)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, style: ts(22, w: FontWeight.w900, color: p.ink, height: 1.15)),
                Text('${v.species} · ${v.trait}', style: ts(14, w: FontWeight.w900, color: Color(c.color))),
                const SizedBox(height: 6),
                Text(v.bio, style: ts(14.5, color: p.ink2, height: 1.35)),
                const SizedBox(height: 6),
                Text('“${v.greet}”', style: ts(14.5, w: FontWeight.w800, color: p.ink, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
