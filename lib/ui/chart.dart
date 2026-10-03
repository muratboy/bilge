/// Kurs içindeki grafikler. Veri kurs dosyasından gelir (bkz. schema.dart, _chart); çizim burada yapılır.
///
/// Seri renkleri sabit bir sıradan alınır ve bu sıra, uygulamanın açık ve koyu zeminlerinde renk körlüğü
/// ayrımı için doğrulanmıştır: en çok 3 seri, pastada en çok 6 dilim. Yazılar seri rengini almaz;
/// kimliği yanlarındaki renkli işaret taşır. Her grafiğin bir tablo görünümü vardır.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/expr.dart';
import '../core/text_utils.dart';
import '../l10n/l10n.dart';
import 'theme.dart';

const _seriesLight = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100), Color(0xFFE87BA4), Color(0xFF008300)];
const _seriesDark = [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500), Color(0xFFD55181), Color(0xFF008300)];

class _Series {
  _Series(this.name, this.values, this.points);
  final String name;
  final List<double> values; // etiketli grafiklerde
  final List<Offset> points; // sayısal eksenli grafiklerde
}

class _Data {
  _Data(Map<String, dynamic> c)
      : type = c['type'] as String,
        title = (c['title'] as String?) ?? '',
        xLabel = (c['x'] as String?) ?? '',
        yLabel = (c['y'] as String?) ?? '',
        labels = ((c['labels'] as List?) ?? const []).cast<String>(),
        fns = ((c['fn'] as List?) ?? const []).cast<String>(),
        from = ((c['from'] as num?) ?? -5).toDouble(),
        to = ((c['to'] as num?) ?? 5).toDouble(),
        series = [
          for (final s in (c['series'] as List?) ?? const [])
            _Series(
              (s['name'] as String?) ?? '',
              [for (final v in (s['values'] as List?) ?? const []) (v as num).toDouble()],
              [for (final p in (s['points'] as List?) ?? const []) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
            ),
        ];

  final String type, title, xLabel, yLabel;
  final List<String> labels, fns;
  final double from, to;
  final List<_Series> series;

  bool get isPie => type == 'pie';
  bool get isFunction => type == 'function';
  bool get categorical => labels.isNotEmpty;
  late final List<Fn> functions = [for (final f in fns) parseFunction(f) ?? (_) => double.nan];

  /// Kimliği renkle ayrılan öğelerin adları (lejant için); tek seride lejant gerekmez.
  List<String> get legend => isPie
      ? labels
      : isFunction
          ? [for (final f in fns) 'y = ${prettyFunction(f)}']
          : (series.length > 1 ? [for (final (i, s) in series.indexed) s.name.isEmpty ? '${i + 1}' : s.name] : const []);
}

/// "x^2-3*x" → "x² − 3·x": lejantta ve tabloda okunur biçim.
String prettyFunction(String f) => f
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll('^2', '²')
    .replaceAll('^3', '³')
    .replaceAll('*', '·')
    .replaceAllMapped(RegExp(r'(?<=[\w)²³])([+\-])'), (m) => ' ${m[1] == '-' ? '−' : '+'} ');

/// Eksen için "yuvarlak" aralıklar: 1, 2 ya da 5'in onluk katları.
({List<double> ticks, double min, double max, int decimals}) niceScale(double lo, double hi, {int target = 4}) {
  if (!lo.isFinite || !hi.isFinite) {
    if (!lo.isFinite && !hi.isFinite) {
      lo = 0;
      hi = 1;
    } else if (!lo.isFinite) {
      lo = hi - 1;
    } else {
      hi = lo + 1;
    }
  }
  if (lo > hi) {
    final t = lo;
    lo = hi;
    hi = t;
  }
  const maxSafe = 1e300;
  if (lo < -maxSafe) lo = -maxSafe;
  if (hi > maxSafe) hi = maxSafe;
  var span = hi - lo;
  if (!span.isFinite || span <= 0) {
    span = 1.0;
    lo = 0;
    hi = 1;
  }
  if (span < 1e-12) {
    final pad = lo == 0 ? 1.0 : lo.abs() * 0.5;
    lo -= pad;
    hi += pad;
    span = hi - lo;
  }
  final raw = span / target;
  if (!raw.isFinite || raw <= 0) {
    return (ticks: [lo, hi], min: lo, max: hi, decimals: 0);
  }
  final exp = (math.log(raw) / math.ln10).floor().clamp(-300, 300);
  final mag = math.pow(10, exp).toDouble();
  final norm = mag == 0 ? 1.0 : raw / mag;
  final step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag;
  if (!step.isFinite || step <= 0) {
    return (ticks: [lo, hi], min: lo, max: hi, decimals: 0);
  }
  final min = (lo / step + 1e-9).floor() * step, max = (hi / step - 1e-9).ceil() * step;
  final decimals = math.max(0, math.min(10, -(math.log(step) / math.ln10 + 1e-9).floor()));
  final ticks = <double>[];
  for (var i = 0; i < 50; i++) {
    final v = min + i * step;
    if (v > max + step * 1e-6) break;
    ticks.add(v);
  }
  if (ticks.isEmpty) ticks.addAll([min, max]);
  return (ticks: ticks, min: min, max: max, decimals: decimals);
}

class ChartView extends StatefulWidget {
  const ChartView(this.chart, {super.key, this.locale = 'tr'});
  final Map<String, dynamic> chart;
  final String locale; // sayıların yazımı için kursun dili

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  late _Data _data = _Data(widget.chart);
  bool _table = false;
  final ValueNotifier<Offset?> _probe = ValueNotifier(null);

  @override
  void dispose() {
    _probe.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChartView old) {
    super.didUpdateWidget(old);
    if (!identical(old.chart, widget.chart)) {
      _data = _Data(widget.chart);
      _probe.value = null;
    }
  }

  String _n(num v, [int? decimals]) {
    if (!v.isFinite) return v.isNaN ? '—' : (v.isNegative ? '−∞' : '∞');
    return formatNumber(decimals == null ? v : num.parse(v.toStringAsFixed(decimals)), locale: widget.locale, groupFrom: 4);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final d = _data;
    final colors = p.dark ? _seriesDark : _seriesLight;
    final legend = d.legend;
    final total = d.isPie ? d.series.first.values.fold(0.0, (a, b) => a + b) : 0.0;
    return Semantics(
      label: [if (d.title.isNotEmpty) d.title, t('chart.semantics')].join(' · '),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.title.isNotEmpty) Text(d.title, style: ts(15.5, w: FontWeight.w900, color: p.ink, height: 1.25)),
                    if (d.yLabel.isNotEmpty && !_table && !d.isPie) Text(d.yLabel, style: ts(12, w: FontWeight.w800, color: p.ink3, height: 1.3)),
                  ],
                ),
              ),
              // Grafiği okuyamayan ya da tam değeri görmek isteyen için aynı veri, tablo olarak
              Semantics(
                button: true,
                label: t(_table ? 'chart.asChart' : 'chart.asTable'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _table = !_table);
                    _probe.value = null;
                  },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(_table ? Icons.bar_chart_rounded : Icons.table_rows_rounded, size: 22, color: p.ink3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_table)
            _DataTable(data: d, format: _n)
          else if (d.isPie)
            Row(
              children: [
                GestureDetector(
                  onTapDown: (e) => _probe.value = e.localPosition,
                  child: CustomPaint(size: const Size(132, 132), painter: _PiePainter(d, p, colors, _probe, _n)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, name) in legend.indexed)
                        _Key(color: colors[i], text: name, value: '%${_n(d.series.first.values[i] / total * 100, d.series.first.values[i] / total < 0.1 ? 1 : 0)}', line: false),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            LayoutBuilder(
              builder: (_, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) => _probe.value = e.localPosition,
                onHorizontalDragUpdate: (e) => _probe.value = e.localPosition,
                child: CustomPaint(size: Size(box.maxWidth, 190), painter: _PlotPainter(d, p, colors, _probe, _n)),
              ),
            ),
            if (d.xLabel.isNotEmpty) Center(child: Text(d.xLabel, style: ts(12, w: FontWeight.w800, color: p.ink3, height: 1.3))),
            if (legend.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [for (final (i, name) in legend.indexed) _Key(color: colors[i], text: name, line: d.type != 'bar')],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Lejant satırı: renkli işaret kimliği taşır, yazı metin renginde kalır.
class _Key extends StatelessWidget {
  const _Key({required this.color, required this.text, required this.line, this.value});
  final Color color;
  final String text;
  final String? value;
  final bool line; // çizgi grafiğinde kısa çizgi, sütun ve pastada kare

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: value == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(width: line ? 16 : 11, height: line ? 3 : 11, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(line ? 2 : 3))),
          const SizedBox(width: 7),
          Flexible(child: Text(text, style: ts(13.5, w: FontWeight.w700, color: p.ink2, height: 1.25))),
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(value!, style: ts(13.5, w: FontWeight.w900, color: p.ink, height: 1.25)),
          ],
        ],
      ),
    );
  }
}

TextPainter _text(String s, TextStyle style, {double maxWidth = double.infinity, int maxLines = 1, TextAlign align = TextAlign.left}) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: maxLines, ellipsis: '…', textAlign: align)..layout(maxWidth: maxWidth);

/* ---------- Eksenli grafikler: sütun, çizgi, saçılım, fonksiyon ---------- */

class _PlotPainter extends CustomPainter {
  _PlotPainter(this.d, this.p, this.colors, this.probeNotifier, this.n) : super(repaint: probeNotifier);
  final _Data d;
  final Palette p;
  final List<Color> colors;
  final ValueNotifier<Offset?> probeNotifier;
  final String Function(num, [int?]) n;

  Offset? get probe => probeNotifier.value;

  static const _samples = 160;

  TextStyle get _tick => ts(11, w: FontWeight.w700, color: p.ink3, height: 1.15);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = p.line2
      ..strokeWidth = 1;

    // 1) Çizilecek noktalar ve değer aralığı
    final curves = <List<Offset>>[]; // veri uzayında, seri başına
    if (d.isFunction) {
      final from = d.from.isFinite ? d.from : -5.0;
      final to = d.to.isFinite ? d.to : 5.0;
      for (final f in d.functions) {
        curves.add([for (var i = 0; i <= _samples; i++) Offset(from + (to - from) * i / _samples, f(from + (to - from) * i / _samples))]);
      }
    } else if (d.categorical) {
      for (final s in d.series) {
        curves.add([for (final (i, v) in s.values.indexed) Offset(i.toDouble(), v)]);
      }
    } else {
      for (final s in d.series) {
        curves.add(s.points);
      }
    }
    final ys = [for (final c in curves) for (final o in c) if (o.dy.isFinite) o.dy]..sort();
    if (ys.isEmpty) return;
    var lo = ys.first, hi = ys.last;
    if (d.isFunction && ys.length > 20) {
      // Sonsuza giden fonksiyonlarda (1/x, tan x) uç değerler ölçeği bozmasın
      final a = ys[(ys.length * 0.04).floor()], b = ys[(ys.length * 0.96).ceil() - 1];
      if (hi - lo > (b - a) * 4) {
        lo = a - (b - a) * 0.1;
        hi = b + (b - a) * 0.1;
      }
    }
    if (d.type == 'bar' || (lo >= 0 && lo <= hi * 0.5)) lo = math.min(lo, 0);
    if (d.type == 'bar') hi = math.max(hi, 0);
    final y = niceScale(lo, hi);

    // 2) Kenar boşlukları: eksen yazıları kutunun içinde kalır
    final yLabels = [for (final v in y.ticks) _text(n(v, y.decimals), _tick)];
    final left = yLabels.fold(0.0, (w, tp) => math.max(w, tp.width)) + 7;
    final names = d.type == 'line' && d.series.length > 1 ? [for (final s in d.series) _text(s.name, ts(11.5, w: FontWeight.w800, color: p.ink2, height: 1.15), maxWidth: 62)] : <TextPainter>[];
    final right = names.isEmpty ? 10.0 : names.fold(0.0, (w, tp) => math.max(w, tp.width)) + 12;
    final plotW = size.width - left - right;
    final count = d.categorical ? d.labels.length : 0;
    final band = count == 0 ? 0.0 : plotW / count;
    final finiteXs = curves.expand((c) => c).where((o) => o.dx.isFinite).map((o) => o.dx).toList();
    final xMinRaw = d.isFunction ? (d.from.isFinite ? d.from : -5.0) : (finiteXs.isEmpty ? 0.0 : finiteXs.reduce(math.min));
    final xMaxRaw = d.isFunction ? (d.to.isFinite ? d.to : 5.0) : (finiteXs.isEmpty ? 1.0 : finiteXs.reduce(math.max));
    final xNumeric = d.categorical ? null : niceScale(xMinRaw, xMaxRaw, target: 5);
    final xMin = d.isFunction ? (d.from.isFinite ? d.from : -5.0) : xNumeric?.min ?? 0.0, xMax = d.isFunction ? (d.to.isFinite ? d.to : 5.0) : xNumeric?.max ?? 1.0;
    final xLabels = d.categorical
        ? [for (final l in d.labels) _text(l, _tick, maxWidth: math.max(18, band - 3), maxLines: 2, align: TextAlign.center)]
        : [for (final v in xNumeric!.ticks) _text(n(v, xNumeric.decimals), _tick)];
    final bottom = xLabels.fold(0.0, (h, tp) => math.max(h, tp.height)) + 6;
    final plot = Rect.fromLTRB(left, 8, size.width - right, size.height - bottom);

    double sy(double v) {
      final span = y.max - y.min;
      if (!span.isFinite || span <= 0 || !v.isFinite) return plot.bottom;
      return plot.bottom - (v - y.min) / span * plot.height;
    }
    double sx(double v) {
      if (d.categorical) return plot.left + band * (v + 0.5);
      final span = xMax - xMin;
      if (!span.isFinite || span <= 0 || !v.isFinite) return plot.left;
      return plot.left + (v - xMin) / span * plot.width;
    }

    // 3) Izgara ve eksenler: ince, düz, geri planda
    for (final (i, v) in y.ticks.indexed) {
      canvas.drawLine(Offset(plot.left, sy(v)), Offset(plot.right, sy(v)), grid);
      yLabels[i].paint(canvas, Offset(left - 7 - yLabels[i].width, sy(v) - yLabels[i].height / 2));
    }
    if (d.categorical) {
      for (final (i, tp) in xLabels.indexed) {
        tp.paint(canvas, Offset(sx(i.toDouble()) - tp.width / 2, plot.bottom + 5));
      }
    } else {
      for (final (i, v) in xNumeric!.ticks.indexed) {
        if (v < xMin - 1e-9 || v > xMax + 1e-9) continue;
        if (d.isFunction || d.type == 'scatter') canvas.drawLine(Offset(sx(v), plot.top), Offset(sx(v), plot.bottom), grid);
        xLabels[i].paint(canvas, Offset((sx(v) - xLabels[i].width / 2).clamp(0.0, size.width - xLabels[i].width), plot.bottom + 5));
      }
    }
    final zeroY = sy(y.min <= 0 && y.max >= 0 ? 0 : y.min);
    canvas.drawLine(Offset(plot.left, zeroY), Offset(plot.right, zeroY), axis);
    if (!d.categorical && xMin <= 0 && xMax >= 0) canvas.drawLine(Offset(sx(0), plot.top), Offset(sx(0), plot.bottom), axis);

    // 4) Dokunulan yer: en yakın etiket ya da x değeri
    int? hit; // etiketli grafikte sütun sırası
    double? hitX; // sayısal eksende x değeri
    final at = probe;
    if (at != null && at.dx >= plot.left - 12 && at.dx <= plot.right + 12) {
      if (d.categorical) {
        hit = ((at.dx - plot.left) / band).floor().clamp(0, count - 1).toInt();
        canvas.drawRect(Rect.fromLTWH(plot.left + band * hit, plot.top, band, plot.height), Paint()..color = p.surface2);
      } else {
        final raw = xMin + ((at.dx - plot.left) / plot.width).clamp(0.0, 1.0) * (xMax - xMin);
        // Noktalı grafikte en yakın noktaya, fonksiyonda yuvarlak bir x değerine yapış
        hitX = d.isFunction
            ? ((raw / (xNumeric!.ticks[1] - xNumeric.ticks[0]) * 4).round() / 4 * (xNumeric.ticks[1] - xNumeric.ticks[0])).clamp(xMin, xMax).toDouble()
            : curves.expand((c) => c).map((o) => o.dx).reduce((a, b) => (a - raw).abs() <= (b - raw).abs() ? a : b);
        canvas.drawLine(Offset(sx(hitX), plot.top), Offset(sx(hitX), plot.bottom), Paint()..color = p.ink3..strokeWidth = 1);
      }
    }

    // 5) İşaretler
    final surface = Paint()..color = p.surface;
    if (d.type == 'bar') {
      final m = d.series.length;
      final barW = math.min(24.0, (band * 0.74 - (m - 1) * 2) / m);
      final groupW = barW * m + (m - 1) * 2;
      for (final (si, s) in d.series.indexed) {
        for (final (i, v) in s.values.indexed) {
          if (!v.isFinite) continue;
          final x0 = sx(i.toDouble()) - groupW / 2 + si * (barW + 2);
          final top = sy(v), base = sy(0);
          final r = Radius.circular(math.min(4, (top - base).abs()));
          canvas.drawRRect(
              RRect.fromRectAndCorners(Rect.fromLTRB(x0, math.min(top, base), x0 + barW, math.max(top, base)),
                  topLeft: v >= 0 ? r : Radius.zero, topRight: v >= 0 ? r : Radius.zero, bottomLeft: v < 0 ? r : Radius.zero, bottomRight: v < 0 ? r : Radius.zero),
              Paint()..color = colors[si]);
        }
      }
      // Tek seride yalnızca en büyük değer yazılır; gerisini eksen ve tablo taşır
      if (m == 1 && hit == null) {
        final values = d.series.first.values;
        final best = values.indexOf(values.reduce(math.max));
        final tp = _text(n(values[best]), ts(11.5, w: FontWeight.w900, color: p.ink, height: 1.15));
        final top = sy(values[best]) - tp.height - 2;
        if (top >= 0) tp.paint(canvas, Offset(sx(best.toDouble()) - tp.width / 2, top));
      }
    } else {
      canvas.save();
      canvas.clipRect(plot.inflate(6));
      for (final (si, c) in curves.indexed) {
        final pen = Paint()
          ..color = colors[si]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (d.type != 'scatter') {
          final path = Path();
          var pen0 = false;
          Offset? prev;
          for (final o in c) {
            final ok = o.dy.isFinite;
            final pt = ok ? Offset(sx(o.dx), sy(o.dy).clamp(plot.top - 400, plot.bottom + 400)) : null;
            // Tanımsız noktada ve düşey asimptotta çizgi kopar
            final jump = pt != null && prev != null && (pt.dy - prev.dy).abs() > plot.height * 1.5;
            if (pt == null || jump) {
              pen0 = false;
            }
            if (pt != null) {
              pen0 ? path.lineTo(pt.dx, pt.dy) : path.moveTo(pt.dx, pt.dy);
              pen0 = true;
            }
            prev = pt;
          }
          canvas.drawPath(path, pen);
        }
        if (!d.isFunction && (d.type == 'scatter' || c.length <= 24)) {
          for (final o in c) {
            if (!o.dx.isFinite || !o.dy.isFinite) continue;
            final pt = Offset(sx(o.dx), sy(o.dy));
            canvas.drawCircle(pt, d.type == 'scatter' ? 6.5 : 6, surface); // zemin renginde halka
            canvas.drawCircle(pt, d.type == 'scatter' ? 4.5 : 4, Paint()..color = colors[si]);
          }
        }
      }
      canvas.restore();
      if (d.type == 'line' && hit == null && hitX == null) {
        if (names.isEmpty) {
          // Tek seri: yalnızca son değer yazılır
          final last = curves.firstOrNull?.lastOrNull;
          if (last != null && last.dy.isFinite && last.dx.isFinite) {
            final tp = _text(n(last.dy), ts(11.5, w: FontWeight.w900, color: p.ink, height: 1.15));
            final pos = Offset((sx(last.dx) - tp.width / 2).clamp(plot.left, size.width - tp.width), sy(last.dy) - tp.height - 8);
            if (pos.dy >= 0) tp.paint(canvas, pos);
          }
        } else {
          // Çok seri: adlar çizgilerin ucuna yazılır; uçlar birbirine girerse lejant yeter
          final ends = [for (final c in curves) if (c.isNotEmpty && c.last.dy.isFinite) sy(c.last.dy)];
          if (ends.length == names.length) {
            final sorted = [...ends]..sort();
            final apart = [for (var i = 1; i < sorted.length; i++) sorted[i] - sorted[i - 1]].every((gap) => gap >= 13);
            if (apart) {
              for (final (i, tp) in names.indexed) {
                tp.paint(canvas, Offset(plot.right + 9, ends[i] - tp.height / 2));
              }
            }
          }
        }
      }
    }

    // 6) Dokunulan yerin değerleri: sayı önde, ad arkada
    if (hit != null || hitX != null) {
      final head = hit != null ? d.labels[hit] : 'x = ${n(hitX!, 2)}';
      final rows = <(Color, String, String)>[];
      for (final (si, c) in curves.indexed) {
        double? v;
        if (hit != null) {
          v = c[hit].dy;
        } else if (d.isFunction) {
          v = d.functions[si](hitX!);
        } else {
          v = c.where((o) => o.dx == hitX).map((o) => o.dy).firstOrNull;
        }
        if (v == null) continue;
        rows.add((colors[si], v.isFinite ? n(v, d.isFunction ? 2 : null) : '—', d.legend.isEmpty ? '' : d.legend[si]));
      }
      final headTp = _text(head, ts(11.5, w: FontWeight.w800, color: p.ink2, height: 1.2), maxWidth: 150);
      final valueTps = [for (final r in rows) _text(r.$2, ts(13, w: FontWeight.w900, color: p.ink, height: 1.2))];
      final nameTps = [for (final r in rows) _text(r.$3, ts(11.5, w: FontWeight.w700, color: p.ink2, height: 1.2), maxWidth: 96)];
      var w = headTp.width;
      for (var i = 0; i < rows.length; i++) {
        w = math.max(w, 16 + valueTps[i].width + (rows[i].$3.isEmpty ? 0 : 6 + nameTps[i].width));
      }
      final h = headTp.height + 3 + rows.length * 17.0;
      final cx = hit != null ? sx(hit.toDouble()) : sx(hitX!);
      final box = Rect.fromLTWH((cx + 10 + w + 16 > size.width ? cx - 10 - w - 16 : cx + 10).clamp(0.0, math.max(0.0, size.width - w - 16)), plot.top, w + 16, h + 12);
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(10));
      canvas.drawRRect(rr.shift(const Offset(0, 2)), Paint()..color = const Color(0x22000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawRRect(rr, Paint()..color = p.surface);
      canvas.drawRRect(rr, Paint()..color = p.line2..style = PaintingStyle.stroke..strokeWidth = 1);
      headTp.paint(canvas, box.topLeft + const Offset(8, 6));
      for (var i = 0; i < rows.length; i++) {
        final top = box.top + 6 + headTp.height + 3 + i * 17;
        canvas.drawLine(Offset(box.left + 8, top + 8.5), Offset(box.left + 18, top + 8.5), Paint()..color = rows[i].$1..strokeWidth = 3..strokeCap = StrokeCap.round);
        valueTps[i].paint(canvas, Offset(box.left + 24, top));
        if (rows[i].$3.isNotEmpty) nameTps[i].paint(canvas, Offset(box.left + 30 + valueTps[i].width, top + 1.5));
      }
    }
  }

  @override
  bool shouldRepaint(_PlotPainter old) => old.d != d || old.p != p || old.colors != colors;
}

/* ---------- Pasta ---------- */

class _PiePainter extends CustomPainter {
  _PiePainter(this.d, this.p, this.colors, this.probeNotifier, this.n) : super(repaint: probeNotifier);
  final _Data d;
  final Palette p;
  final List<Color> colors;
  final ValueNotifier<Offset?> probeNotifier;
  final String Function(num, [int?]) n;

  Offset? get probe => probeNotifier.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (d.series.isEmpty) return;
    final values = [for (final v in d.series.first.values) v.isFinite && v > 0 ? v : 0.0];
    final total = values.fold(0.0, (a, b) => a + b);
    if (!total.isFinite || total <= 0) return;
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2, inner = outer * 0.56;
    // Dokunulan dilim
    int? hit;
    final at = probe;
    if (at != null && (at - c).distance <= outer + 8) {
      var angle = (math.atan2(at.dy - c.dy, at.dx - c.dx) + math.pi / 2) % (2 * math.pi);
      if (angle < 0) angle += 2 * math.pi;
      var acc = 0.0;
      for (final (i, v) in values.indexed) {
        acc += v / total * 2 * math.pi;
        if (angle <= acc) {
          hit = i;
          break;
        }
      }
    }
    var start = -math.pi / 2;
    for (final (i, v) in values.indexed) {
      final sweep = v / total * 2 * math.pi;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: (outer + inner) / 2),
          start,
          sweep,
          false,
          Paint()
            ..color = hit == null || hit == i ? colors[i] : colors[i].withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = outer - inner);
      start += sweep;
    }
    // Dilimleri çizgi değil, zemin renginde 2 birimlik boşluk ayırır
    start = -math.pi / 2;
    for (final v in values) {
      canvas.drawLine(c + Offset(math.cos(start), math.sin(start)) * (inner - 1), c + Offset(math.cos(start), math.sin(start)) * (outer + 1), Paint()..color = p.surface..strokeWidth = 2);
      start += v / total * 2 * math.pi;
    }
    // Ortadaki okuma: dokunulan dilimin değeri, yoksa toplam
    final top = _text(hit == null ? t('chart.total') : d.labels[hit], ts(11, w: FontWeight.w800, color: p.ink2, height: 1.15), maxWidth: inner * 1.7, maxLines: 2, align: TextAlign.center);
    final bottom = _text(n(hit == null ? total : values[hit]), ts(16, w: FontWeight.w900, color: p.ink, height: 1.15), maxWidth: inner * 1.8);
    final h = top.height + bottom.height;
    top.paint(canvas, Offset(c.dx - top.width / 2, c.dy - h / 2));
    bottom.paint(canvas, Offset(c.dx - bottom.width / 2, c.dy - h / 2 + top.height));
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.d != d || old.p != p || old.colors != colors;
}

/* ---------- Tablo görünümü ---------- */

class _DataTable extends StatelessWidget {
  const _DataTable({required this.data, required this.format});
  final _Data data;
  final String Function(num, [int?]) format;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final d = data;
    final header = <String>[], rows = <List<String>>[];
    String name(int i) => d.series[i].name.isEmpty ? (d.yLabel.isEmpty ? t('chart.value') : d.yLabel) : d.series[i].name;
    if (d.isFunction) {
      final x = niceScale(d.from, d.to, target: 6);
      header.addAll(['x', for (final f in d.fns) prettyFunction(f)]);
      for (final v in x.ticks.where((v) => v >= d.from - 1e-9 && v <= d.to + 1e-9)) {
        rows.add([format(v, x.decimals), for (final f in d.functions) f(v).isFinite ? format(f(v), 2) : '—']);
      }
    } else if (d.categorical) {
      header.addAll([d.xLabel, for (var i = 0; i < d.series.length; i++) name(i), if (d.isPie) '%']);
      final total = d.isPie ? d.series.first.values.fold(0.0, (a, b) => a + b) : 1.0;
      for (final (i, l) in d.labels.indexed) {
        rows.add([l, for (final s in d.series) format(s.values[i]), if (d.isPie) format(d.series.first.values[i] / total * 100, 1)]);
      }
    } else {
      // Sayısal eksen: her serinin kendi noktaları
      header.addAll([if (d.series.length > 1) '', d.xLabel.isEmpty ? 'x' : d.xLabel, d.yLabel.isEmpty ? 'y' : d.yLabel]);
      for (final (i, s) in d.series.indexed) {
        for (final o in s.points) {
          rows.add([if (d.series.length > 1) name(i), format(o.dx), format(o.dy)]);
        }
      }
    }
    Widget cell(String s, {bool head = false, bool first = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(s, textAlign: first ? TextAlign.left : TextAlign.right, style: ts(13.5, w: head ? FontWeight.w900 : FontWeight.w700, color: head ? p.ink2 : p.ink, height: 1.25)),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 230),
      child: SingleChildScrollView(
        child: Table(
          defaultColumnWidth: const FlexColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: p.line, width: 1)),
          children: [
            TableRow(children: [for (final (i, h) in header.indexed) cell(h, head: true, first: i == 0)]),
            for (final r in rows) TableRow(children: [for (final (i, c) in r.indexed) cell(c, first: i == 0)]),
          ],
        ),
      ),
    );
  }
}
