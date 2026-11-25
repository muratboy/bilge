import 'dart:io';

import 'package:flutter/material.dart';

import '../core/store.dart';
import '../l10n/l10n.dart';
import 'piper_catalog.dart';
import 'piper_downloader.dart';
import 'speech.dart';
import 'theme.dart';
import 'widgets.dart';

/// Linux ortamında doğal ses modellerini listeleme, indirme, dinleme ve silme penceresi.
class NaturalVoicesSheet extends StatefulWidget {
  const NaturalVoicesSheet({super.key, required this.app});

  final AppState app;

  @override
  State<NaturalVoicesSheet> createState() => _NaturalVoicesSheetState();
}

class _NaturalVoicesSheetState extends State<NaturalVoicesSheet> {
  Set<String> _installedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    final models = await Speech.getInstalledVoiceModels();
    if (!mounted) return;
    final ids = <String>{};
    for (final m in models) {
      final name = m.uri.pathSegments.isNotEmpty ? m.uri.pathSegments.last : m.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.onnx')) {
        ids.add(name.substring(0, name.length - 5));
      }
    }
    setState(() {
      _installedIds = ids;
      _loading = false;
    });
  }

  Future<void> _listenPreview(PiperVoice voice) async {
    final sentence = PiperCatalog.previewSentenceFor(voice.primaryLang);
    // Önizleme için doğrudan bu sesi kullan
    final prevResolver = Speech.selectedVoiceResolver;
    Speech.selectedVoiceResolver = (_) => voice.id;
    try {
      await Speech.speak(sentence, lang: voice.lang);
    } finally {
      Speech.selectedVoiceResolver = prevResolver;
    }
  }

  Future<void> _startDownload(PiperVoice voice) async {
    final ok = await PiperVoiceDownloader.instance.download(voice);
    if (!mounted) return;
    await _refreshInstalled();
    if (!ok && PiperVoiceDownloader.instance.snapshot.status == PiperDownloadStatus.error) {
      final err = PiperVoiceDownloader.instance.snapshot.errorMessage ?? '';
      if (mounted) toast(context, t('naturalVoices.error', {'err': err}));
    }
  }

  Future<void> _deleteVoice(PiperVoice voice) async {
    showBilgeDialog(
      context,
      title: t('naturalVoices.deleteConfirm', {'name': voice.name}),
      actions: [
        DialogAction(
          t('naturalVoices.delete'),
          kind: ButtonKind.bad,
          onPressed: () async {
            await PiperVoiceDownloader.deleteVoice(voice.id);
            if (!mounted) return;
            if (widget.app.settings.selectedVoices[voice.primaryLang] == voice.id) {
              widget.app.settings.selectedVoices.remove(voice.primaryLang);
              widget.app.commit();
            }
            await _refreshInstalled();
          },
        ),
        DialogAction(t('common.cancel'), kind: ButtonKind.ghost),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final downloader = PiperVoiceDownloader.instance;

    return ListenableBuilder(
      listenable: downloader,
      builder: (sheetContext, _) {
        final snap = downloader.snapshot;

        // Diller sırası
        const langOrder = ['tr', 'en', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'ar', 'nl', 'zh'];

        return sheetBody(
          sheetContext,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          head: [
            Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Palette.blue.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.record_voice_over_rounded, color: Palette.blue, size: 24),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t('naturalVoices.title'),
              textAlign: TextAlign.center,
              style: ts(20, w: FontWeight.w900, color: p.ink),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: p.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('naturalVoices.note'),
                      style: ts(12.5, w: FontWeight.w700, color: p.ink2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          scroll: [
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else
              for (final primary in langOrder) ...[
                Builder(builder: (_) {
                  final voices = PiperCatalog.voices.where((v) => v.primaryLang == primary).toList();
                  if (voices.isEmpty) return const SizedBox.shrink();

                  final installedInLang = voices.where((v) => _installedIds.contains(v.id)).toList();
                  final selectedId = widget.app.settings.selectedVoices[primary] ??
                      (installedInLang.isNotEmpty ? installedInLang.first.id : null);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Text(
                          t('naturalVoices.lang.$primary'),
                          style: ts(15, w: FontWeight.w900, color: p.ink),
                        ),
                      ),
                      for (final voice in voices)
                        _buildVoiceCard(
                          voice: voice,
                          isInstalled: _installedIds.contains(voice.id),
                          isSelected: selectedId == voice.id,
                          showSelectOption: installedInLang.length > 1 && _installedIds.contains(voice.id),
                          snap: snap,
                          p: p,
                        ),
                    ],
                  );
                }),
              ],
          ],
          foot: [
            const SizedBox(height: 10),
            ChunkyButton(
              label: t('common.close'),
              kind: ButtonKind.ghost,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVoiceCard({
    required PiperVoice voice,
    required bool isInstalled,
    required bool isSelected,
    required bool showSelectOption,
    required PiperDownloadSnapshot snap,
    required Palette p,
  }) {
    final isBusyThis = snap.activeVoiceId == voice.id && snap.isBusy;

    return Container(
      key: ValueKey('voice-card-${voice.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected && isInstalled ? Palette.blue.withValues(alpha: 0.12) : p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected && isInstalled ? Palette.blue : p.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      voice.name,
                      style: ts(15, w: FontWeight.w900, color: p.ink),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${voice.lang})',
                      style: ts(13, w: FontWeight.w700, color: p.ink3),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${voice.sizeMb.toStringAsFixed(1)} MB',
                      style: ts(12.5, w: FontWeight.w700, color: p.ink2),
                    ),
                  ],
                ),
              ),
              if (voice.isNonCommercial)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.badSoft,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: p.bad.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    t('naturalVoices.nonCommercial'),
                    style: ts(11, w: FontWeight.w900, color: p.badInk),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                voice.license,
                style: ts(12, w: FontWeight.w700, color: p.ink3),
              ),
              const Spacer(),
              if (isInstalled && isSelected)
                Text(
                  '★ ${t('naturalVoices.selected')}',
                  style: ts(12, w: FontWeight.w900, color: Palette.blue),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isBusyThis) ...[
            Bar(value: snap.progress, color: Palette.blue, track: p.line, height: 8),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    snap.status == PiperDownloadStatus.verifying
                        ? t('naturalVoices.verifying')
                        : t('naturalVoices.downloading', {'p': (snap.progress * 100).round()}),
                    style: ts(12.5, w: FontWeight.w800, color: Palette.blue),
                  ),
                ),
                TextButton(
                  key: ValueKey('cancel-btn-${voice.id}'),
                  onPressed: () => PiperVoiceDownloader.instance.cancel(),
                  child: Text(t('common.cancel'), style: ts(13, w: FontWeight.w800, color: p.badInk)),
                ),
              ],
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isInstalled)
                  ChunkyButton(
                    key: ValueKey('download-btn-${voice.id}'),
                    label: t('naturalVoices.download'),
                    icon: Icons.download_rounded,
                    expand: false,
                    onPressed: snap.isBusy ? null : () => _startDownload(voice),
                  )
                else ...[
                  ChunkyButton(
                    key: ValueKey('listen-btn-${voice.id}'),
                    label: t('naturalVoices.listen'),
                    icon: Icons.volume_up_rounded,
                    expand: false,
                    onPressed: () => _listenPreview(voice),
                  ),
                  ChunkyButton(
                    key: ValueKey('delete-btn-${voice.id}'),
                    label: t('naturalVoices.delete'),
                    icon: Icons.delete_outline_rounded,
                    kind: ButtonKind.bad,
                    expand: false,
                    onPressed: () => _deleteVoice(voice),
                  ),
                  if (showSelectOption && !isSelected)
                    ChunkyButton(
                      key: ValueKey('select-btn-${voice.id}'),
                      label: t('naturalVoices.select'),
                      kind: ButtonKind.ghost,
                      expand: false,
                      onPressed: () => widget.app.selectVoice(voice.primaryLang, voice.id),
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
