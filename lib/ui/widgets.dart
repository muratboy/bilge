/// Ortak arayüz parçaları: düğme, kart, ilerleme çubuğu, biçimli metin, pencere.
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../l10n/l10n.dart';
import 'sfx.dart';
import 'theme.dart';

/* ---------- Düğme: altı kalın, basınca çöken ---------- */

enum ButtonKind { primary, good, bad, ghost, light }

class ChunkyButton extends StatefulWidget {
  const ChunkyButton({super.key, required this.label, this.onPressed, this.icon, this.kind = ButtonKind.primary, this.expand = true, this.color});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final bool expand;

  /// [ButtonKind.light] için yazı rengi (renkli zemin üstündeki beyaz düğme).
  final Color? color;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final enabled = widget.onPressed != null;
    final (Color bg, Color edge, Color fg) = !enabled
        ? (p.line, p.line2, p.ink3)
        : switch (widget.kind) {
            ButtonKind.primary => (p.primary, p.primaryD, Colors.white),
            ButtonKind.good => (p.good, p.goodD, Colors.white),
            ButtonKind.bad => (p.bad, p.badD, Colors.white),
            ButtonKind.ghost => (p.surface, p.line2, p.primaryInk),
            ButtonKind.light => (Colors.white, Colors.black.withValues(alpha: 0.25), widget.color ?? p.primary),
          };
    final pressed = _down && enabled;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      margin: EdgeInsets.only(top: pressed ? 4 : 0, bottom: pressed ? 0 : 4),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: widget.kind == ButtonKind.ghost && enabled ? Border.all(color: p.line2, width: 2) : null,
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, pressed ? 0 : 4))],
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 22, color: fg), const SizedBox(width: 8)],
          Flexible(child: Text(upper(widget.label), textAlign: TextAlign.center, style: ts(16, w: FontWeight.w900, color: fg, height: 1.2, spacing: 0.6))),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: child,
      ),
    );
  }
}

/* ---------- Dokunulabilir kart: şık, parça, eşleştirme öğesi ---------- */

enum CardState { idle, selected, good, bad, used, matched }

class TapCard extends StatelessWidget {
  const TapCard({super.key, required this.child, this.onTap, this.state = CardState.idle, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12), this.radius = 16, this.depth = 4});

  final Widget child;
  final VoidCallback? onTap;
  final CardState state;
  final EdgeInsets padding;
  final double radius, depth;

  static ({Color bg, Color border, Color fg}) colors(Palette p, CardState s) => switch (s) {
        CardState.idle => (bg: p.surface, border: p.line, fg: p.ink),
        CardState.selected => (bg: p.primarySoft, border: p.primary, fg: p.primaryInk),
        CardState.good => (bg: p.goodSoft, border: p.good, fg: p.goodInk),
        CardState.matched => (bg: p.goodSoft, border: p.good, fg: p.goodInk),
        CardState.bad => (bg: p.badSoft, border: p.bad, fg: p.badInk),
        CardState.used => (bg: p.surface2, border: p.surface2, fg: Colors.transparent),
      };

  @override
  Widget build(BuildContext context) {
    final c = colors(context.p, state);
    return Semantics(
      container: true,
      button: onTap != null,
      selected: state == CardState.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: padding,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border(
              top: BorderSide(color: c.border, width: 2),
              left: BorderSide(color: c.border, width: 2),
              right: BorderSide(color: c.border, width: 2),
              bottom: BorderSide(color: c.border, width: depth),
            ),
          ),
          child: DefaultTextStyle.merge(style: TextStyle(color: c.fg), child: Opacity(opacity: state == CardState.matched ? 0.55 : 1, child: child)),
        ),
      ),
    );
  }
}

/// Düz kenarlıklı yüzey (bilgi kartı, ayar grubu, istatistik kutusu).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? color, border;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? context.p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border ?? context.p.line, width: 2),
        ),
        child: child,
      );
}

class Bar extends StatelessWidget {
  const Bar({super.key, required this.value, this.color, this.track, this.height = 10});
  final double value;
  final Color? color, track;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: height,
          color: track ?? context.p.surface2,
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            widthFactor: value.clamp(0, 1).toDouble(),
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: color ?? context.p.primary, borderRadius: BorderRadius.circular(99))),
          ),
        ),
      );
}

/// Küçük, büyük harfli etiket ("DOĞRU CEVABI SEÇ", "1. ÜNİTE").
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(upper(text), style: ts(13, w: FontWeight.w900, color: color ?? context.p.ink3, spacing: 1));
}

/* ---------- Biçimli metin ----------
   Kurs içeriği dışarıdan gelir; yalnızca şu biçimler işlenir: **kalın**, *italik*, `kod`, $formül$ (LaTeX), listeler,
   ``` kod blokları. Formül yalnızca çizilir; çizilemeyen formül yazıldığı gibi metin olarak kalır. */

// Formül sınırları: açılıştan sonra ve kapanıştan önce boşluk olmaz, kapanışı rakam izlemez ("5$ ve 10$" formül değildir).
final _inline = RegExp(r'`(?<code>[^`\n]+)`'
    r'|(?<![\w$\\])\$\$(?<block>[^$]+?)\$\$'
    r'|(?<![\w$\\])\$(?!\s)(?<math>(?:\\.|[^$\\\n])+?)(?<!\s)\$(?![\d$])'
    r'|\\\((?<paren>.+?)\\\)'
    r'|\\\[(?<bracket>.+?)\\\]'
    r'|\*\*(?!\s)(?<bold>[^*\n]+?)(?<!\s)\*\*'
    r'|(?<![\w*])\*(?!\s)(?<italic>[^*\n]+?)(?<!\s)\*(?![\w*])');

List<InlineSpan> mdSpans(String text, Palette p, {Color? strong, TextStyle? style}) {
  final out = <InlineSpan>[];
  void plain(String s) => out.add(TextSpan(text: s.replaceAll(r'\$', r'$')));
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > last) plain(text.substring(last, m.start));
    final tex = m.namedGroup('math') ?? m.namedGroup('block') ?? m.namedGroup('paren') ?? m.namedGroup('bracket');
    if (tex != null) {
      out.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: Formula(tex.trim(), style: style)));
    } else if (m.namedGroup('code') != null) {
      out.add(TextSpan(text: m.namedGroup('code'), style: TextStyle(fontFamily: 'monospace', fontSize: 14.5, backgroundColor: p.surface2)));
    } else if (m.namedGroup('bold') != null) {
      out.add(TextSpan(children: mdSpans(m.namedGroup('bold')!, p, style: style), style: TextStyle(fontWeight: FontWeight.w900, color: strong)));
    } else {
      out.add(TextSpan(children: mdSpans(m.namedGroup('italic')!, p, style: style), style: const TextStyle(fontStyle: FontStyle.italic)));
    }
    last = m.end;
  }
  if (last < text.length) plain(text.substring(last));
  return out;
}

// Kalın metnin içindeki formül: harfler kalın italik, rakamlar kalın
const _boldMath = FontOptions(
  fontFamily: 'Math',
  fontWeight: FontWeight.bold,
  fontShape: FontStyle.italic,
  fallback: [FontOptions(fontFamily: 'Main', fontWeight: FontWeight.bold)],
);

/// LaTeX formülü. Çevresindeki yazının boyutuna, rengine ve kalınlığına uyar; satıra sığmazsa küçülür.
/// Ayrıştırılamayan formülün kaynağı düz metin olarak gösterilir.
class Formula extends StatelessWidget {
  const Formula(this.tex, {super.key, this.style, this.display = false});
  final String tex;
  final TextStyle? style;
  final bool display; // kendi satırında, biraz daha büyük

  @override
  Widget build(BuildContext context) {
    final s = DefaultTextStyle.of(context).style.merge(style);
    final size = (s.fontSize ?? 16) * (display ? 1.25 : 1.1);
    return Semantics(
      label: tex,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Math.tex(
          tex,
          // Kesirler küçük ekranda okunaklı kalsın diye satır içinde de büyük biçim kullanılır
          options: MathOptions(
            style: MathStyle.display,
            fontSize: MediaQuery.textScalerOf(context).scale(size),
            color: s.color ?? context.p.ink,
            mathFontOptions: (s.fontWeight ?? FontWeight.normal).value >= 700 ? _boldMath : null,
          ),
          onErrorFallback: (_) => Text(display ? tex : '\$$tex\$', style: s),
        ),
      ),
    );
  }
}

class MdInline extends StatelessWidget {
  const MdInline(this.text, {super.key, this.style, this.align});
  final String text;
  final TextStyle? style;
  final TextAlign? align;
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: mdSpans(text, context.p, style: style)), style: style, textAlign: align);
}

final _displayMath = RegExp(r'(?<![\w$\\])\$\$([^$]+?)\$\$|\\\[([\s\S]+?)\\\]');

class MdBlock extends StatelessWidget {
  const MdBlock(this.text, {super.key, this.style, this.strong, this.align = CrossAxisAlignment.start});
  final String text;
  final TextStyle? style;
  final Color? strong;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final blocks = <Widget>[];
    Widget para(String s) => Text.rich(TextSpan(children: mdSpans(s, p, strong: strong, style: style)),
        style: style, textAlign: align == CrossAxisAlignment.center ? TextAlign.center : TextAlign.start);
    final chunks = text.replaceAll('\r\n', '\n').split('```');
    for (var i = 0; i < chunks.length; i++) {
      if (i.isOdd) {
        final code = chunks[i].replaceFirst(RegExp(r'^[\w+#-]*\n'), '').replaceFirst(RegExp(r'\n$'), '');
        blocks.add(Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF231D3A), borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.5, color: Color(0xFFEDE9FF))),
          ),
        ));
        continue;
      }
      final lines = <String>[];
      void flush() {
        if (lines.isNotEmpty) blocks.add(para(lines.join('\n')));
        lines.clear();
      }

      // Kendi satırında duran $$...$$ ya da \[...\]: ortalanmış, büyük formül
      final shown = chunks[i].replaceAllMapped(_displayMath, (m) => '\n\u0001${(m[1] ?? m[2])!.replaceAll('\n', ' ').trim()}\n');
      for (final line in shown.split('\n')) {
        if (line.startsWith('\u0001')) {
          flush();
          blocks.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(child: Formula(line.substring(1), style: style, display: true)),
          ));
          continue;
        }
        final item = RegExp(r'^\s*(?:[-•*]|(\d{1,2})[.)])\s+(.*)$').firstMatch(line);
        if (item != null) {
          flush();
          blocks.add(Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 24, child: Text(item[1] != null ? '${item[1]}.' : '•', style: style)),
                Expanded(child: para(item[2]!)),
              ],
            ),
          ));
        } else if (line.trim().isEmpty) {
          flush();
        } else {
          lines.add(line);
        }
      }
      flush();
    }
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [for (final (i, b) in blocks.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: b)],
    );
  }
}

/* ---------- Pencere ve bildirim ---------- */

class DialogAction {
  const DialogAction(this.label, {this.kind = ButtonKind.primary, this.onPressed});
  final String label;
  final ButtonKind kind;
  final VoidCallback? onPressed;
}

/// Bundan alçak alan "dar" sayılır (yan çevrilmiş telefon, açık klavye): pencereler tümüyle kayar, ders
/// ekranındaki maskotlar küçülür. Eşik yalnızca burada durur.
const compactHeight = 560.0;

/// Ekranın kullanılabilir yüksekliği (durum çubuğu ve klavye düşülünce) dar mı.
bool isCompact(BuildContext context) {
  final media = MediaQuery.of(context);
  return media.size.height - media.padding.vertical - media.viewInsets.bottom < compactHeight;
}

/// Alttan açılan pencerelerin ortak gövdesi: [head] üstte, [scroll] ortada, [foot] altta durur.
/// Yüksek alanda yalnızca orta bölüm kayar, alttaki düğmeler yerinde kalır. Dar alanda (yan çevrilmiş telefon,
/// açık klavye) hepsi birlikte kayar: en alttaki düğme ekranın dışında kalmaz. Karar ekranın boyuna değil,
/// pencereye gerçekten verilen yüksekliğe göre verilir.
/// Pencere `isScrollControlled: true, useSafeArea: true` ile açılmalıdır; yoksa yüksekliği ekranın yarısıyla sınırlı kalır.
Widget sheetBody(
  BuildContext sheet, {
  required EdgeInsets padding,
  List<Widget> head = const [],
  List<Widget> scroll = const [],
  List<Widget> foot = const [],
}) {
  Widget column(List<Widget> children) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  return LayoutBuilder(
    builder: (context, constraints) {
      final room = constraints.hasBoundedHeight ? constraints.maxHeight : MediaQuery.sizeOf(context).height;
      final roomy = room >= compactHeight;
      final insets = MediaQuery.viewInsetsOf(context);
      final effPadding = insets.bottom > 0 && padding.bottom < insets.bottom
          ? padding.copyWith(bottom: padding.bottom + insets.bottom)
          : padding;
      return SafeArea(
        child: roomy
            ? Padding(
                padding: effPadding,
                child: column([...head, if (scroll.isNotEmpty) Flexible(child: SingleChildScrollView(child: column(scroll))), ...foot]),
              )
            : SingleChildScrollView(padding: effPadding, child: column([...head, ...scroll, ...foot])),
      );
    },
  );
}

/// Alttan açılan onay penceresi. Düğmeler yukarıdan aşağı verildiği sırayla dizilir.
Future<void> showBilgeDialog(BuildContext context, {required String title, String? text, Widget? body, required List<DialogAction> actions}) {
  final p = context.p;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => sheetBody(
      sheet,
      padding: EdgeInsets.fromLTRB(20, 22, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
      head: [
        Text(title, style: ts(20, w: FontWeight.w900, color: p.ink, height: 1.25)),
        if (text != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(text, style: ts(15.5, color: p.ink2))),
      ],
      scroll: [if (body != null) Padding(padding: const EdgeInsets.only(top: 10), child: body)],
      foot: [
        const SizedBox(height: 16),
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyButton(
              label: a.label,
              kind: a.kind,
              onPressed: () {
                Navigator.of(sheet).pop();
                a.onPressed?.call();
              },
            ),
          ),
      ],
    ),
  );
}

class SheetAction {
  const SheetAction(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger; // silme gibi geri alınamayan işlemler kırmızı yazılır
}

/// Alttan açılan seçenek listesi (bir kartın "⋮" menüsü).
Future<void> showActionSheet(BuildContext context, {required String title, required List<SheetAction> actions}) {
  final p = context.p;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => sheetBody(
      sheet,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 10),
      head: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(19, w: FontWeight.w900, color: p.ink, height: 1.25)),
        ),
      ],
      scroll: [
        for (final a in actions)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.of(sheet).pop();
              a.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(a.icon, size: 24, color: a.danger ? p.badInk : p.ink2),
                  const SizedBox(width: 14),
                  Expanded(child: Text(a.label, style: ts(16.5, w: FontWeight.w800, color: a.danger ? p.badInk : p.ink))),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

void toast(BuildContext context, String message, {bool floating = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, textAlign: TextAlign.center),
      duration: Duration(milliseconds: floating ? 1600 : 2600),
      behavior: floating ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
      margin: floating ? const EdgeInsets.only(bottom: 84, left: 24, right: 24) : null,
    ));
}

/// Dokununca hafif ses veren, basit simge düğmesi.
class IconTap extends StatelessWidget {
  const IconTap({super.key, required this.icon, required this.onTap, required this.label, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () {
          Sfx.play('tap');
          onTap();
        },
        tooltip: label,
        icon: Icon(icon, color: color ?? context.p.ink3, size: 26),
      );
}
