/// Maskotların çizimi. Her karakter eklemli bir iskelettir: [Pose] değerlerine göre her karede
/// yeniden çizilir (200 × 230 birimlik bir tuvalde; ayaklar y = 212'de yere basar).
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:path_parsing/path_parsing.dart';

import 'mascot_art.dart';
import 'pose.dart';

part 'rig_paths.dart';
part 'rig_vector.dart';

const _ink = Color(0xFF33272A);
const _pink = Color(0xFFFF8FA3);
const _white = Color(0xFFFFFFFF);

class _Proxy extends PathProxy {
  final path = Path();
  @override
  void close() => path.close();
  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) => path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

final _paths = <String, Path>{};

/// SVG yol yazımını (M, L, C, Q, Z…) [Path]'e çevirir; sonuç önbelleğe alınır.
Path _path(String d) => _paths[d] ??= (() {
      final proxy = _Proxy();
      writeSvgPathDataToPath(d, proxy);
      return proxy.path;
    })();

/// Gözlerin üstündeki çizginin gücü: 0 hiç yok, 0.5 yumuşak, 1 belirgin.
double eyeLineStrength = 0.5;

Color _darker(Color c, [double t = 0.22]) => Color.lerp(c, const Color(0xFF000000), t)!;
Color _lighter(Color c, [double t = 0.25]) => Color.lerp(c, _white, t)!;

/// Kontur rengi: açık renklerde koyu ton, çok koyu renklerde (koyu temada kaybolmasın diye) açık ton.
Color _edge(Color c) => c.computeLuminance() < 0.09 ? _lighter(c, 0.24) : _darker(c, 0.36);

/// Çizim bağlamı: tuval, duruş ve bütün karakterlerin paylaştığı yardımcılar.
class _C {
  _C(this.canvas, this.p, this.time);
  final Canvas canvas;
  final Pose p;
  final double time;
  final _fill = Paint()..isAntiAlias = true;
  final _line = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Eşyaların tutulacağı noktalar (gövde uzayında); her karakter kollarını çizerken doldurur.
  Offset handL = const Offset(70, 180), handR = const Offset(130, 180);

  /// Kafanın yaklaşık kutusu (gövde uzayında): kulaklık, bulut, ampul gibi eşyalar buna göre yerleşir.
  Offset head = const Offset(100, 90);
  double headRx = 46, headTop = 46;

  /// Karaktere özgü tutma noktası (filin hortum ucu).
  Offset tip = const Offset(100, 150);

  void fill(Path path, Color c) => canvas.drawPath(path, _fill..color = c);
  void shape(String d, Color c) => fill(_path(d), c);
  void oval(double cx, double cy, double rx, double ry, Color c) =>
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2), _fill..color = c);
  void stroke(Path path, Color c, double w) => canvas.drawPath(
      path,
      _line
        ..color = c
        ..strokeWidth = w);
  void line(String d, Color c, double w) => stroke(_path(d), c, w);
  void seg(Offset a, Offset b, Color c, double w) => canvas.drawLine(
      a,
      b,
      _line
        ..color = c
        ..strokeWidth = w);

  /// [draw]'ı (x, y) noktası çevresinde döndürerek / ölçekleyerek çizer.
  void at(double x, double y, double rot, void Function() draw, {double sx = 1, double sy = 1, double dx = 0, double dy = 0}) {
    canvas.save();
    canvas.translate(x + dx, y + dy);
    if (rot != 0) canvas.rotate(rot);
    if (sx != 1 || sy != 1) canvas.scale(sx, sy);
    canvas.translate(-x, -y);
    draw();
    canvas.restore();
  }

  /// Sol tarafı çizer, sonra aynısını aynalayıp sağ tarafın değerleriyle bir daha çizer.
  void both(void Function(bool left, double arm, double leg) draw, {double width = 200}) {
    draw(true, p.armL, p.legL);
    canvas.save();
    canvas.translate(width, 0);
    canvas.scale(-1, 1);
    draw(false, p.armR, p.legR);
    canvas.restore();
  }

  void _hand(bool left, Offset h) => left ? handL = h : handR = Offset(200 - h.dx, h.dy);

  /// İçi dolu, koyu konturlu kalın çizgi (uzuvlar, dokunaçlar).
  void tube(Path path, Color c, double w) {
    stroke(path, _edge(c), w + 3.4);
    stroke(path, c, w);
  }

  /// Konturlu oval (eller, ayaklar).
  void blob(double cx, double cy, double rx, double ry, Color c) {
    oval(cx, cy, rx + 1.6, ry + 1.6, _edge(c));
    oval(cx, cy, rx, ry, c);
  }

  /// Dirsekten bükülen kol; el noktasını kaydeder. Kol gövdenin önüne geldikçe (negatif değer)
  /// dirsek daha çok bükülür: kitap tutma, eli çeneye götürme gibi duruşlar doğal görünür.
  void arm(bool left, double arm, double sx, double sy, double len, double w, Color c, {Color? hand, double handR = 0}) {
    final a1 = arm < 0 ? 0.2 + arm * 1.3 : 0.2 + arm * 1.5;
    final a2 = arm < 0 ? -0.1 + arm * 1.9 : a1 - 0.3 + math.min(arm, 1.0) * 0.5;
    final half = len * 0.54;
    final elbow = Offset(sx - math.sin(a1) * half, sy + math.cos(a1) * half);
    final h = Offset(elbow.dx - math.sin(a2) * half, elbow.dy + math.cos(a2) * half);
    // Dirsekte kırılmak yerine yumuşakça bükülür (eğri dirsek noktasından geçer)
    final bend = elbow * 2 - (Offset(sx, sy) + h) / 2;
    tube(
        Path()
          ..moveTo(sx, sy)
          ..quadraticBezierTo(bend.dx, bend.dy, h.dx, h.dy),
        c,
        w);
    if (hand != null) {
      // Başparmaklı eldiven el
      final thumb = Offset(h.dx + math.cos(a2) * handR * 0.95, h.dy + math.sin(a2) * handR * 0.95);
      final edge = _darker(hand, 0.34);
      oval(thumb.dx, thumb.dy, handR * 0.5 + 1.6, handR * 0.5 + 1.6, edge);
      oval(h.dx, h.dy, handR + 1.6, handR + 1.6, edge);
      oval(thumb.dx, thumb.dy, handR * 0.5, handR * 0.5, hand);
      oval(h.dx, h.dy, handR, handR, hand);
      oval(h.dx - handR * 0.3, h.dy - handR * 0.35, handR * 0.32, handR * 0.24, _lighter(hand, 0.3));
      // Parmak araları
      final along = Offset(-math.sin(a2), math.cos(a2)), across = Offset(math.cos(a2), math.sin(a2));
      for (final k in const [-0.3, 0.22]) {
        seg(h + along * (handR * 0.3) + across * (handR * k), h + along * (handR * 0.92) + across * (handR * k * 1.2), edge, 1.5);
      }
    }
    _hand(left, h);
  }

  /// Kanat / yüzgeç: [d] aşağı sarkık hâlidir, omuz çevresinde döner.
  void wing(bool left, double arm, String d, double px, double py, double len, Color c, {Color? tip}) {
    final a = arm * 1.5;
    at(px, py, a, () {
      final path = _path(d);
      volume(path, c, dx: -3, dy: -3);
      if (tip != null) {
        // Tüy katmanları: üstte iki sıra örtü tüyü, uçta uzun uçma tüyleri
        canvas.save();
        canvas.clipPath(path);
        final rows = Path();
        for (final (row, y) in const [(0, 0.2), (1, 0.37)]) {
          for (var x = -27.0 + row * 4; x < 12; x += 8) {
            rows
              ..moveTo(px + x, py + len * y)
              ..relativeQuadraticBezierTo(4, 7, 8, 0);
          }
        }
        stroke(rows, tip, 2);
        for (final x in const [-15.0, -8.5, -2.0, 4.0]) {
          seg(Offset(px + x, py + len * 0.54), Offset(px + x * 0.45 - 1.5, py + len * 1.08), tip, 2);
        }
        canvas.restore();
      }
    });
    _hand(left, Offset(px - math.sin(a) * len, py + math.cos(a) * len));
  }

  /// Ayak: kaldırıldığında hafifçe öne ve yukarı çıkar.
  void foot(double leg, double cx, double cy, double rx, double ry, Color c) {
    final x = cx - leg * 5, y = cy - leg * 12, h = ry * (1 - leg * 0.15);
    blob(x, y, rx, h, c);
    oval(x - rx * 0.3, y - h * 0.35, rx * 0.36, h * 0.26, _lighter(c, 0.28));
    for (final k in const [-0.26, 0.22]) {
      seg(Offset(x + rx * k, y + h * 0.05), Offset(x + rx * k * 1.25, y + h * 0.8), _edge(c), 1.5);
    }
  }

  static final _crescents = Expando<Path>();

  /// Şekle hacim verir: sol üstten ışık alan yumuşak geçiş, sağ altta gölge hilali ve koyu kontur.
  void volume(Path shape, Color base, {double dx = -5, double dy = -6, double shade = 0.14}) {
    final b = shape.getBounds();
    canvas.drawPath(
        shape,
        Paint()
          ..isAntiAlias = true
          ..shader = Gradient.radial(Offset(b.left + b.width * 0.32, b.top + b.height * 0.24), b.longestSide * 0.95,
              [_lighter(base, 0.2), base, _darker(base, 0.13)], const [0, 0.55, 1]));
    final crescent = _crescents[shape] ??= Path.combine(PathOperation.difference, shape, shape.shift(Offset(dx, dy)));
    fill(crescent, _darker(base, 0.3).withValues(alpha: shade * 2.2));
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(b.left + b.width * 0.3, b.top + b.height * 0.2), width: b.width * 0.44, height: b.height * 0.2),
        Paint()
          ..color = const Color(0x3DFFFFFF)
          ..maskFilter = _blur(b.shortestSide * 0.05));
    canvas.restore();
    stroke(shape, _edge(base), 2.4);
  }

  static final _ovals = <String, Path>{};

  /// Sabit ölçülü oval yol (önbellekli; her karede değişen ölçüler için kullanma).
  Path ovalPath(double cx, double cy, double rx, double ry) =>
      _ovals['$cx,$cy,$rx,$ry'] ??= (Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2)));

  static final _blurs = <double, MaskFilter>{};
  MaskFilter _blur(double sigma) => _blurs[(sigma * 2).roundToDouble() / 2] ??= MaskFilter.blur(BlurStyle.normal, (sigma * 2).roundToDouble() / 2);

  /// Şeklin içine düşen yumuşak gölge: kafanın gövdeye, kolun karna düşürdüğü gölge gibi.
  void shadowOn(Path clip, double cx, double cy, double rx, double ry, [double alpha = 0.2]) {
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
        Paint()
          ..color = Color.fromRGBO(20, 14, 40, alpha)
          ..maskFilter = _blur(6));
    canvas.restore();
  }

  /// Şeklin içinde renkli, yumuşak parıltı (kuzgun tüyündeki mavi-mor yanardönerlik gibi).
  void glow(Path clip, double cx, double cy, double rx, double ry, Color color) {
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
        Paint()
          ..color = color
          ..maskFilter = _blur(5));
    canvas.restore();
  }

  /// Karın gibi açık renkli yama: ortası hafifçe daha aydınlık, kenarı gölgeli.
  void patch(double cx, double cy, double rx, double ry, Color c) => canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      Paint()
        ..isAntiAlias = true
        ..shader = Gradient.radial(Offset(cx - rx * 0.2, cy - ry * 0.3), math.max(rx, ry) * 1.25, [_lighter(c, 0.4), c, _darker(c, 0.12)], const [0, 0.6, 1]));

  /* ----- Yüz ----- */

  void _eye(double cx, double cy, double r, double lidValue, bool left, Color lid, Color iris, bool lashes) {
    if (p.joy > 0.5) {
      stroke(
          Path()
            ..moveTo(cx - r * 0.9, cy + r * 0.3)
            ..quadraticBezierTo(cx, cy - r * 1.05, cx + r * 0.9, cy + r * 0.3),
          _ink,
          r * 0.36);
      return;
    }
    final close = lidValue.clamp(0.0, 1.0);
    if (close > 0.9) {
      stroke(
          Path()
            ..moveTo(cx - r * 0.85, cy + r * 0.1)
            ..quadraticBezierTo(cx, cy + r * 0.6, cx + r * 0.85, cy + r * 0.1),
          _ink,
          r * 0.3);
      return;
    }
    final rx = r * (1 + p.wide * 0.14), ry = r * 1.14 * (1 + p.wide * 0.14);
    final eye = Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
    fill(eye, _white);
    canvas.save();
    canvas.clipPath(eye);
    oval(cx, cy - ry * 0.98, rx * 1.25, ry * 0.5, const Color(0x1F2A2342)); // üst kapağın gölgesi
    final px = cx + p.lookX * r * 0.3, py = cy + p.lookY * r * 0.3 + r * 0.06;
    final ir = r * (0.76 - p.wide * 0.14);
    oval(px, py, ir, ir * 1.05, _darker(iris, 0.3));
    oval(px, py + ir * 0.08, ir * 0.88, ir * 0.9, iris);
    oval(px, py + ir * 0.5, ir * 0.66, ir * 0.42, _lighter(iris, 0.38)); // alt yarıdaki ışıltı
    oval(px, py, ir * 0.56, ir * 0.6, _ink);
    oval(px + ir * 0.36, py - ir * 0.42, ir * 0.3, ir * 0.3, _white);
    oval(px - ir * 0.38, py + ir * 0.4, ir * 0.14, ir * 0.14, _white);
    // Gülümserken alt kapak hafifçe yükselir
    if (p.smile > 0.72 && close < 0.5) oval(cx, cy + ry * 1.72 - (p.smile - 0.72) * ry * 1.1, rx * 1.5, ry, lid);
    // Üst kapak: üstten iner; üzgünken dışa doğru eğilir
    if (close > 0.02 || p.browTilt.abs() > 0.05) {
      final edge = cy - ry + 2 * ry * close;
      final slant = (left ? -1 : 1) * p.browTilt * 0.34;
      at(cx, edge, slant, () {
        canvas.drawRect(Rect.fromLTRB(cx - rx * 2, cy - ry * 3, cx + rx * 2, edge), _fill..color = lid);
        seg(Offset(cx - rx * 2, edge), Offset(cx + rx * 2, edge), _ink, r * 0.14);
      });
    }
    canvas.restore();
    stroke(eye, const Color(0x3D33272A), 1.5);
    // Üst göz çizgisi: bakışı belirginleştirir
    if (eyeLineStrength > 0) {
      stroke(Path()..addArc(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2), math.pi + 0.22, math.pi - 0.44),
          Color.fromRGBO(51, 39, 42, 0.85 * eyeLineStrength), r * (0.08 + 0.09 * eyeLineStrength));
    }
    if (lashes) {
      final side = left ? -1.0 : 1.0;
      seg(Offset(cx + side * rx * 0.84, cy - ry * 0.52), Offset(cx + side * (rx * 0.84 + r * 0.4), cy - ry * 0.52 - r * 0.3), _ink, r * 0.14);
      seg(Offset(cx + side * rx * 0.6, cy - ry * 0.8), Offset(cx + side * (rx * 0.6 + r * 0.28), cy - ry * 0.8 - r * 0.38), _ink, r * 0.14);
    }
    // Kapak kıvrımı: göze derinlik verir
    stroke(Path()..addArc(Rect.fromCenter(center: Offset(cx, cy - ry * 0.1), width: rx * 2.3, height: ry * 2.3), -2.5, 1.86), _darker(lid, 0.22), r * 0.12);
  }

  /// [base]: karakterin kaşlarının doğal eğimi (baykuşta içe doğru inen, bilgiç kaşlar).
  void _brow(double cx, double cy, double r, bool left, Color c, double base) {
    final y = cy - r * 1.75 - p.brow * r * 0.5;
    at(cx, y, (left ? -1 : 1) * (p.browTilt * 0.5 - p.brow * 0.08 - base), () => seg(Offset(cx - r * 0.6, y), Offset(cx + r * 0.6, y), c, r * 0.28));
  }

  /// İki göz ve kaşlar. [rest]: karakterin dinlenirkenki kapak düşüklüğü (bakışına kişilik verir).
  void eyes(double lx, double rx, double y, double r, {required Color lid, required Color brow, Color iris = const Color(0xFF7A5238), double rest = 0, bool brows = false, double browAngle = 0, bool lashes = false}) {
    final shift = p.lookX * 1.6; // kafa bakış yönüne hafifçe döner gibi görünsün
    rest *= 1 - p.wide.clamp(0.0, 1.0);
    _eye(lx + shift, y, r, rest + p.lidL * (1 - rest), true, lid, iris, lashes);
    _eye(rx + shift, y, r, rest + p.lidR * (1 - rest), false, lid, iris, lashes);
    if (brows || p.brow.abs() > 0.12 || p.browTilt.abs() > 0.12) {
      _brow(lx + shift, y, r, true, brow, browAngle);
      _brow(rx + shift, y, r, false, brow, browAngle);
    }
  }

  void mouth(double cx, double cy, double w, {double? thick}) {
    cx += p.lookX * 1.6;
    if (p.round > 0.5) {
      oval(cx, cy + w * 0.35, w * 0.44, w * (0.34 + p.open * 0.36), _ink);
      return;
    }
    final s = p.smile, o = p.open;
    if (o < 0.12) {
      final y = cy - s * w * 0.15, t = thick ?? w * 0.3;
      stroke(
          Path()
            ..moveTo(cx - w, y)
            ..quadraticBezierTo(cx, cy + s * w, cx + w, y),
          _ink,
          t);
      // Gülümserken ağız köşeleri hafifçe yukarı kıvrılır
      if (s > 0.3) {
        final k = (s - 0.3) * w * 0.5;
        seg(Offset(cx - w, y), Offset(cx - w - k * 0.45, y - k), _ink, t);
        seg(Offset(cx + w, y), Offset(cx + w + k * 0.45, y - k), _ink, t);
      }
      return;
    }
    final m = Path()
      ..moveTo(cx - w * 1.05, cy)
      ..quadraticBezierTo(cx, cy + s * w * 0.3, cx + w * 1.05, cy)
      ..quadraticBezierTo(cx, cy + s * w * 0.6 + o * w * 2.3, cx - w * 1.05, cy)
      ..close();
    fill(m, _ink);
    canvas.save();
    canvas.clipPath(m);
    oval(cx, cy + s * w * 0.3 + o * w * 1.15, w * 0.6, w * 0.42, _pink);
    canvas.restore();
  }

  /// Gaga: [Pose.open] ile açılır.
  void beak(double x, double y, double w, double h, Color c, Color dark) {
    x += p.lookX * 1.6;
    final o = p.open;
    if (o > 0.12) {
      fill(
          Path()
            ..moveTo(x - w * 0.75, y + h * 0.25)
            ..lineTo(x + w * 0.75, y + h * 0.25)
            ..lineTo(x, y + h * (0.75 + o * 0.6))
            ..close(),
          dark);
    }
    fill(
        Path()
          ..moveTo(x - w, y)
          ..quadraticBezierTo(x, y - h * 0.25, x + w, y)
          ..lineTo(x, y + h * (1 - o * 0.42))
          ..close(),
        c);
    oval(x - w * 0.3, y + h * 0.08, w * 0.3, h * 0.07, _lighter(c, 0.4));
    if (w > 10) {
      oval(x - w * 0.34, y + h * 0.2, 1.6, 1.1, dark);
      oval(x + w * 0.34, y + h * 0.2, 1.6, 1.1, dark);
    }
  }

  void blush(double lx, double rx, double y, [double r = 7]) {
    final c = _pink.withValues(alpha: 0.55);
    oval(lx, y, r, r * 0.62, c);
    oval(rx, y, r, r * 0.62, c);
  }

  /* ----- Eşyalar ----- */

  void _scaled(Offset o, void Function() draw) => at(o.dx, o.dy, 0, draw, sx: p.propA, sy: p.propA);

  /// Elde tutulan eşyalar; kollar çizildikten sonra çağrılır.
  void held() {
    if (p.propA < 0.02) return;
    final mid = Offset((handL.dx + handR.dx) / 2, (handL.dy + handR.dy) / 2);
    switch (p.prop) {
      case Prop.book:
        final o = mid.translate(0, -16);
        _scaled(o, () {
          canvas.save();
          canvas.translate(o.dx, o.dy);
          fill(_path('M-34 -17 Q-17 -24 0 -16 Q17 -24 34 -17 L34 19 Q17 12 0 20 Q-17 12 -34 19 Z'), const Color(0xFF4F7CFF));
          fill(_path('M-30 -18 Q-15 -24 0 -17 L0 16 Q-15 9 -30 15 Z'), _white);
          fill(_path('M30 -18 Q15 -24 0 -17 L0 16 Q15 9 30 15 Z'), const Color(0xFFF4F1FF));
          line('M-24 -10 Q-14 -14 -5 -9 M-24 -3 Q-14 -7 -5 -2 M-24 4 Q-14 0 -5 5 M24 -10 Q14 -14 5 -9 M24 -3 Q14 -7 5 -2', const Color(0xFFB9B2D6), 1.6);
          // Sayfa çevirme: sayfa sağdan sola yay çizer
          final t = p.propT;
          if (t > 0.72) {
            final k = (t - 0.72) / 0.28;
            final x = 28 - k * 56;
            fill(
                Path()
                  ..moveTo(0, -17)
                  ..quadraticBezierTo(x * 0.5, -30 + (k - 0.5).abs() * 14, x, -18)
                  ..lineTo(x, 15)
                  ..quadraticBezierTo(x * 0.5, 4 + (k - 0.5).abs() * 14, 0, 16)
                  ..close(),
                const Color(0xFFE9E5FA));
          }
          seg(const Offset(0, -17), const Offset(0, 18), const Color(0xFFB9B2D6), 1.6);
          canvas.restore();
        });
      case Prop.notebook:
        _scaled(handL, () {
          at(handL.dx, handL.dy, -0.2, () {
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: handL.translate(2, -10), width: 30, height: 38), const Radius.circular(4)), _fill..color = const Color(0xFFFFD86B));
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: handL.translate(4, -10), width: 22, height: 30), const Radius.circular(2)), _fill..color = _white);
            for (var i = 0; i < 4; i++) {
              final len = i == 3 ? 8.0 * p.propT + 3 : 14.0;
              seg(handL.translate(-4, -20.0 + i * 6), handL.translate(-4 + len, -20.0 + i * 6), const Color(0xFF9C95B8), 1.5);
            }
          });
        });
        _pencil(handR.translate(-2, -4), -0.5 + wave(time, 0.35) * 0.12);
      case Prop.ruler:
        final ang = math.atan2(handR.dy - handL.dy, handR.dx - handL.dx);
        final len = (handR - handL).distance + 26;
        _scaled(mid, () {
          at(mid.dx, mid.dy, ang, () {
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: mid, width: len, height: 13), const Radius.circular(3)), _fill..color = const Color(0xFFFFD23F));
            for (var x = -len / 2 + 6; x < len / 2 - 3; x += 7) {
              seg(Offset(mid.dx + x, mid.dy - 6.5), Offset(mid.dx + x, mid.dy - ((x / 7).round().isEven ? 0.5 : 3)), const Color(0xFF8F6400), 1.3);
            }
          });
        });
      case Prop.barbell:
        _scaled(mid, () {
          seg(handL.translate(-16, 0), handR.translate(16, 0), const Color(0xFF6B6488), 5);
          for (final (h, side) in [(handL.translate(-18, 0), -1.0), (handR.translate(18, 0), 1.0)]) {
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: h, width: 11, height: 34), const Radius.circular(4)), _fill..color = const Color(0xFF2A2342));
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: h.translate(side * 9, 0), width: 8, height: 24), const Radius.circular(3)), _fill..color = const Color(0xFF4A4266));
          }
        });
      case Prop.gem:
        final o = handR.translate(0, -12);
        _scaled(o, () {
          fill(
              Path()
                ..moveTo(o.dx, o.dy + 13)
                ..lineTo(o.dx - 12, o.dy - 2)
                ..lineTo(o.dx - 6, o.dy - 10)
                ..lineTo(o.dx + 6, o.dy - 10)
                ..lineTo(o.dx + 12, o.dy - 2)
                ..close(),
              const Color(0xFF4FD8E8));
          fill(
              Path()
                ..moveTo(o.dx - 12, o.dy - 2)
                ..lineTo(o.dx - 6, o.dy - 10)
                ..lineTo(o.dx + 6, o.dy - 10)
                ..lineTo(o.dx + 12, o.dy - 2)
                ..close(),
              const Color(0xFFB8F4FA));
          star(o.translate(12, -12), 6 + wave(time, 0.7) * 2, _white);
        });
      case Prop.chair:
        final o = handR.translate(4, -6); // çay fincanı
        _scaled(o, () {
          canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromCenter(center: o, width: 17, height: 14), bottomLeft: const Radius.circular(6), bottomRight: const Radius.circular(6)), _fill..color = _white);
          stroke(Path()..addArc(Rect.fromCenter(center: o.translate(10, 0), width: 9, height: 9), -1.4, 2.8), _white, 2.6);
          oval(o.dx, o.dy - 6, 7.5, 2.4, const Color(0xFFB5651D));
          final s = wave(time, 1.6) * 2;
          for (final x in [o.dx - 3 + s, o.dx + 4 - s]) {
            stroke(
                Path()
                  ..moveTo(x, o.dy - 11)
                  ..relativeQuadraticBezierTo(-4, -5, 0, -9),
                const Color(0xAAFFFFFF),
                2);
          }
        });
      default:
        break;
    }
  }

  void _pencil(Offset o, double rot) => _scaled(o, () {
        at(o.dx, o.dy, rot, () {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 3, o.dy - 26, 6, 26), const Radius.circular(2)), _fill..color = const Color(0xFFFF8A3D));
          fill(
              Path()
                ..moveTo(o.dx - 3, o.dy)
                ..lineTo(o.dx + 3, o.dy)
                ..lineTo(o.dx, o.dy + 7)
                ..close(),
              const Color(0xFF4A332D));
          canvas.drawRect(Rect.fromLTWH(o.dx - 3, o.dy - 29, 6, 4), _fill..color = _pink);
        });
      });

  /// Sallanan koltuk: gövdenin arkasına, ilk iş çizilir.
  void behind() {
    if (p.prop != Prop.chair || p.propA < 0.02) return;
    const wood = Color(0xFFB07A4A), dark = Color(0xFF8A5A32);
    at(100, 212, 0, () {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(52, 92, 148, 196), const Radius.circular(18)), _fill..color = wood);
      for (final x in [72.0, 100.0, 128.0]) {
        seg(Offset(x, 104), Offset(x, 186), dark, 4);
      }
      line('M34 204 Q100 232 166 204', dark, 8);
      line('M44 166 H64 M136 166 H156', dark, 9);
      line('M48 170 V208 M152 170 V208', dark, 6);
    }, sx: p.propA, sy: p.propA);
  }

  /// Kafa uzayındaki eşyalar: kulaklık.
  void onHead(double cx, double top, double rx, double earY) {
    if (p.prop != Prop.headphones || p.propA < 0.02) return;
    at(cx, earY, 0, () {
      stroke(Path()..addArc(Rect.fromLTRB(cx - rx - 4, top - 10, cx + rx + 4, earY * 2 - top + 10), math.pi, math.pi), const Color(0xFF2A2342), 7);
      for (final s in [-1.0, 1.0]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx + s * (rx + 3), earY), width: 17, height: 30), const Radius.circular(8)), _fill..color = const Color(0xFFFF5263));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx + s * (rx + 8), earY), width: 7, height: 20), const Radius.circular(4)), _fill..color = const Color(0xFF2A2342));
      }
    }, sx: p.propA, sy: p.propA);
  }

  void star(Offset o, double r, Color c) => fill(
      Path()
        ..moveTo(o.dx, o.dy - r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
        ..close(),
      c);

  void note(Offset o, double s, Color c) {
    oval(o.dx, o.dy, 4.2 * s, 3.3 * s, c);
    seg(o.translate(3.6 * s, -1), o.translate(3.6 * s, -15 * s), c, 2.2 * s);
    seg(o.translate(3.6 * s, -15 * s), o.translate(10 * s, -12 * s), c, 2.6 * s);
  }

  void drop(Offset o, double s, Color c) => fill(
      Path()
        ..moveTo(o.dx, o.dy - 7 * s)
        ..quadraticBezierTo(o.dx - 5 * s, o.dy + 1 * s, o.dx, o.dy + 4 * s)
        ..quadraticBezierTo(o.dx + 5 * s, o.dy + 1 * s, o.dx, o.dy - 7 * s)
        ..close(),
      c);

  void ball(Offset o, double r, {required bool beach}) {
    final b = ovalPath(o.dx, o.dy, r, r);
    fill(b, _white);
    canvas.save();
    canvas.clipPath(b);
    at(o.dx, o.dy, time * (beach ? 1.4 : 5), () {
      if (beach) {
        for (final (i, col) in const [Color(0xFFFF5263), Color(0xFFFFB800), Color(0xFF3A8DFF)].indexed) {
          fill(
              Path()
                ..moveTo(o.dx, o.dy)
                ..arcTo(Rect.fromCircle(center: o, radius: r * 1.2), i * 2.094, 1.05, false)
                ..close(),
              col);
        }
      } else {
        oval(o.dx, o.dy, r * 0.36, r * 0.36, _ink);
        for (var i = 0; i < 5; i++) {
          final a = i * 1.2566;
          oval(o.dx + math.cos(a) * r * 0.95, o.dy + math.sin(a) * r * 0.95, r * 0.3, r * 0.3, _ink);
        }
      }
    });
    canvas.restore();
    stroke(b, const Color(0x33000000), 1.5);
  }
}

/* ================= Karakterler ================= */

// Puhu'nun ilk çizimi (yeni çizim: rig_vector.dart). Geri dönülebilsin diye duruyor.
// ignore: unused_element
void _puhuClassic(_C c) {
  const body = Color(0xFF8A6652), dark = Color(0xFF6B4C3C), belly = Color(0xFFF7E8CF), disc = Color(0xFFE2C8AC), beak = Color(0xFFF5A623);
  final p = c.p;
  c.head = const Offset(100, 90);
  c.headRx = 55;
  c.headTop = 40;
  c.behind();
  c.both((left, arm, leg) {
    c.foot(leg, 84, 210, 13, 6.5, beak);
    c.at(0, 0, 0, () => c.line('M76 212 l-3 3 M84 213 v4 M92 212 l3 3', const Color(0xFFC97F0A), 2.4), dx: -leg * 5, dy: -leg * 12);
  });
  c.volume(c.ovalPath(100, 166, 44, 46), body);
  c.patch(100, 175, 29, 35, belly);
  c.shadowOn(c.ovalPath(100, 166, 44, 46), 100, 128, 44, 20);
  c.line('M82 158 q5 6 10 0 M95 158 q5 6 10 0 M108 158 q5 6 10 0 M88 171 q5 6 10 0 M102 171 q5 6 10 0 M82 184 q5 6 10 0 M95 184 q5 6 10 0 M108 184 q5 6 10 0 M90 197 q5 5 10 0 M102 197 q5 5 10 0', disc, 2.4);
  c.both((left, arm, leg) => c.wing(left, arm, 'M60 146 C38 160 38 194 58 206 C70 190 70 164 60 146 Z', 60, 150, 52, dark, tip: body));
  c.at(100, 128, p.headTilt, () {
    c.canvas.translate(40, 28);
    // Kulak püskülleri: dışı koyu, içi açık tüy
    c.both((left, arm, leg) => c.at(26, 30, -p.ear * 0.35, () {
          c.volume(_path('M14 46 C7 31 3 14 3 -3 C21 4 37 14 48 27 Z'), dark, dx: -2, dy: -2);
          c.shape('M17 35 C13 26 11 16 10 7 C19 11 28 17 35 24 Z', _lighter(body, 0.12));
        }), width: 120);
    c.volume(c.ovalPath(60, 62, 56, 48), body);
    c.line('M50 22 q5 6 10 0 q5 6 10 0 M45 30 q5 6 10 0 q5 6 10 0 q5 6 10 0', dark, 2.2);
    // Kalp biçimli yüz diski
    c.shape('M60 40 C70 28 104 32 107 60 C109 82 88 96 60 102 C32 96 11 82 13 60 C16 32 50 28 60 40 Z', _darker(disc, 0.2));
    c.shape('M60 44 C70 33 100 36 103 60 C105 80 86 92 60 98 C34 92 15 80 17 60 C20 36 50 33 60 44 Z', disc);
    c.patch(39, 63, 22, 23, _lighter(disc, 0.1));
    c.patch(81, 63, 22, 23, _lighter(disc, 0.1));
    c.eyes(39, 81, 63, 15.5, lid: disc, brow: dark, iris: const Color(0xFFE8A02E), rest: 0.12, brows: true, browAngle: 0.3);
    c.beak(60, 74, 8.5, 16, beak, const Color(0xFFC97F0A));
    c.onHead(60, 14, 56, 62);
  }, dx: p.headX, dy: p.headY);
  // Papyon
  c.shape('M100 130 L80 118 L80 142 Z', const Color(0xFFE5484D));
  c.shape('M100 130 L120 118 L120 142 Z', const Color(0xFFE5484D));
  c.oval(100, 130, 5.5, 5.5, const Color(0xFFB8323A));
  c.held();
}

// tarcin: ilk çizim (yenisi rig_vector.dart içinde).
// ignore: unused_element
void _tarcinClassic(_C c) {
  const fur = Color(0xFFFF8A3D), dark = Color(0xFF4A332D), cream = Color(0xFFFFF4E6), deep = Color(0xFFE56A1E);
  final p = c.p;
  c.head = const Offset(100, 84);
  c.headRx = 53;
  c.headTop = 40;
  c.behind();
  c.at(128, 186, p.tail * 0.55, () {
    c.volume(_path('M124 198 C180 208 200 156 172 114 C174 148 152 166 126 170 Z'), fur, dx: -4, dy: -3);
    c.shape('M172 114 C188 132 190 152 182 168 C174 154 170 138 172 114 Z', cream);
    c.line('M146 180 q16 -8 22 -28 M156 190 q14 -8 20 -22', deep, 2.6);
  });
  c.both((left, arm, leg) {
    c.tube(
        Path()
          ..moveTo(88, 194)
          ..lineTo(86 - leg * 5, 204 - leg * 12),
        deep,
        12);
    c.foot(leg, 83, 208, 16, 8.5, dark);
  });
  final torso = _path('M100 132 C118 132 130 146 132 164 C136 190 122 208 100 208 C78 208 64 190 68 164 C70 146 82 132 100 132 Z');
  c.volume(torso, fur);
  c.patch(100, 179, 20, 27, cream);
  c.shadowOn(torso, 100, 130, 36, 18);
  c.shape('M86 156 l5 9 l4 -7 l5 9 l5 -9 l4 7 l5 -9 Q100 146 86 156 Z', cream);
  // Boyun fuları: göz rengiyle uyumlu, puantiyeli
  const scarf = Color(0xFF1F9E8F);
  c.at(100, 134, wave(c.time, 3.1) * 0.03 - p.lean * 0.4, () {
    c.volume(_path('M73 133 Q100 145 127 133 Q121 150 100 163 Q79 150 73 133 Z'), scarf, dx: -2, dy: -2);
    for (final (x, y) in const [(89.0, 145.0), (100.0, 152.0), (111.0, 145.0), (100.0, 141.0)]) {
      c.oval(x, y, 1.9, 1.9, const Color(0xCCFFFFFF));
    }
  });
  c.both((left, arm, leg) => c.arm(left, arm, 74, 150, 34, 15, deep, hand: dark, handR: 9));
  c.at(100, 126, p.headTilt, () {
    c.canvas.translate(34, 5.5);
    c.canvas.scale(1.1);
    // Kulaklar: ucu koyu, içi açık tüylü
    c.both((left, arm, leg) => c.at(30, 50, -p.ear * 0.3, () {
          final ear = _path('M18 64 C12 42 10 24 11 12 C12 8 16 7 19 9 C33 17 47 27 57 37 Z');
          c.volume(ear, fur, dx: -2, dy: -2);
          c.canvas.save();
          c.canvas.clipPath(ear);
          c.oval(12, 8, 15, 17, dark);
          c.canvas.restore();
          c.shape('M24 53 C20 41 18 30 18 21 C28 26 37 32 45 39 Z', const Color(0xFFFFE2C8));
          c.line('M26 47 l1 -9 M31 46 l3 -8 M36 44 l3 -6', const Color(0xFFF5C39E), 1.8);
        }), width: 120);
    c.volume(_path('M60 32c25 0 41 15 46 35 3 12-17 43-46 43S11 79 14 67c5-20 21-35 46-35z'), fur);
    c.shape('M50 34 l6 -12 l5 9 l6 -11 l4 14 Z', fur);
    c.both((left, arm, leg) => c.shape('M15 70 l-11 4 l9 5 l-7 7 l13 0 Z', fur), width: 120);
    c.shape('M14 75c15 1 33 5 46 12 13-7 31-11 46-12 0 12-18 35-46 35S14 87 14 75z', cream);
    c.blush(27, 93, 90, 7);
    c.eyes(41, 79, 59, 13, lid: fur, brow: dark, iris: const Color(0xFF4FA35A));
    // Öne çıkan burun: hafif kabarık, altı gölgeli
    final mx = 60 + p.lookX * 1.6;
    c.oval(mx, 95, 19, 12.5, const Color(0x24A0522D));
    c.patch(mx, 92.5, 18, 12, _white);
    c.oval(mx, 86.5, 7.5, 5.2, _ink);
    c.oval(mx - 2, 85, 2.4, 1.5, const Color(0x99FFFFFF));
    c.seg(Offset(mx, 91.5), Offset(mx, 95.5), _ink, 2);
    for (final (x, y) in const [(-12.0, 91.0), (-9.0, 95.5), (12.0, 91.0), (9.0, 95.5)]) {
      c.oval(mx + x, y, 1.1, 1.1, const Color(0x66A0522D)); // bıyık dipleri
    }
    c.mouth(60, 96, 8.5);
    c.onHead(60, 30, 47, 66);
  }, dx: p.headX, dy: p.headY);
  c.held();
}

// zifir: ilk çizim (yenisi rig_vector.dart içinde).
// ignore: unused_element
void _zifirClassic(_C c) {
  const body = Color(0xFF342E4E), light = Color(0xFF4E456F), beak = Color(0xFFB3ACD2), foot = Color(0xFFF5A623), scarf = Color(0xFF8A5CF6);
  final p = c.p;
  c.head = const Offset(100, 92);
  c.headRx = 46;
  c.headTop = 44;
  c.behind();
  c.at(118, 194, p.tail * 0.5, () {
    for (final (i, d) in const [
      'M114 184 C140 190 164 204 172 220 C150 220 128 210 116 198 Z',
      'M114 190 C134 198 152 210 158 224 C140 222 124 214 114 202 Z',
      'M112 196 C126 204 138 214 142 226 C128 224 116 216 110 206 Z',
    ].indexed) {
      c.volume(_path(d), i.isEven ? light : _darker(light, 0.18), dx: -2, dy: -2);
    }
  });
  c.both((left, arm, leg) {
    c.foot(leg, 86, 210, 12, 6, foot);
    c.at(0, 0, 0, () => c.line('M79 212 l-3 3 M86 213 v4 M93 212 l3 3', const Color(0xFFC97F0A), 2.2), dx: -leg * 5, dy: -leg * 12);
  });
  c.volume(c.ovalPath(100, 168, 38, 42), body);
  c.patch(100, 180, 22, 27, light);
  c.shadowOn(c.ovalPath(100, 168, 38, 42), 100, 132, 38, 18, 0.3);
  c.line('M90 176 l4 5 l4 -5 M102 176 l4 5 l4 -5 M96 188 l4 5 l4 -5 M90 199 l4 5 l4 -5 M102 199 l4 5 l4 -5', body, 2.2);
  c.shape('M80 138 l5 12 l4 -8 l4 11 l4 -9 l3 11 l4 -11 l4 9 l4 -11 l4 8 l4 -12 Z', body); // boyun tüyleri
  c.both((left, arm, leg) => c.wing(left, arm, 'M62 146 C40 162 42 196 62 206 C72 190 72 164 62 146 Z', 62, 150, 52, light, tip: body));
  c.at(100, 130, p.headTilt, () {
    c.canvas.translate(40, 30);
    c.fill(
        Path()
          ..moveTo(44, 28)
          ..lineTo(48, 4 - p.ear * 6)
          ..lineTo(58, 20)
          ..lineTo(66, 0 - p.ear * 8)
          ..lineTo(72, 20)
          ..lineTo(80, 8 - p.ear * 5)
          ..lineTo(78, 30)
          ..close(),
        body);
    c.volume(c.ovalPath(60, 62, 46, 44), body);
    c.glow(c.ovalPath(60, 62, 46, 44), 38, 34, 26, 11, const Color(0x664E6BFF)); // tüylerdeki mavi-mor parıltı
    c.eyes(40, 80, 57, 13.5, lid: body, brow: const Color(0xFF8E86B0), iris: const Color(0xFFA99BFF), rest: 0.26);
    // Kuzgun gagası: iri ve sivri; açılınca üst gaga kalkar, altından alt gaga ve dil görünür
    final bx = 60 + p.lookX * 1.6, drop = p.open * 9;
    if (p.open > 0.12) {
      c.fill(
          Path()
            ..moveTo(bx - 10, 81)
            ..lineTo(bx + 10, 81)
            ..lineTo(bx, 93 + p.open * 15)
            ..close(),
          const Color(0xFF3D3752));
      c.fill(
          Path()
            ..moveTo(bx - 6, 82)
            ..lineTo(bx + 6, 82)
            ..lineTo(bx, 88 + p.open * 8)
            ..close(),
          _pink);
    }
    final upper = Path()
      ..moveTo(bx - 15.5, 73)
      ..quadraticBezierTo(bx, 64, bx + 15.5, 73)
      ..quadraticBezierTo(bx + 10, 87, bx + 2.2, 100 - drop)
      ..quadraticBezierTo(bx, 103.5 - drop, bx - 2.2, 100 - drop)
      ..quadraticBezierTo(bx - 10, 87, bx - 15.5, 73)
      ..close();
    c.canvas.drawPath(upper, Paint()..shader = Gradient.linear(Offset(bx, 64), Offset(bx, 102), [_lighter(beak, 0.25), _darker(beak, 0.3)]));
    c.stroke(upper, const Color(0xFF4B4468), 2);
    c.seg(Offset(bx - 4, 73), Offset(bx - 1.5, 92 - drop), const Color(0x73FFFFFF), 3);
    c.oval(bx - 7, 77, 2, 1.3, const Color(0xFF4B4468));
    c.oval(bx + 7, 77, 2, 1.3, const Color(0xFF4B4468));

    c.onHead(60, 20, 46, 60);
  }, dx: p.headX, dy: p.headY);
  // Atkı
  c.oval(100, 131, 30, 9, scarf);
  c.at(120, 134, 0.25 + wave(c.time, 2.6) * 0.08 - p.lean, () => c.shape('M114 132 L132 134 L134 164 L126 158 L120 166 Z', _darker(scarf, 0.12)));
  c.held();
}

// tosbi: ilk çizim (yenisi rig_vector.dart içinde).
// ignore: unused_element
void _tosbiClassic(_C c) {
  const skin = Color(0xFF8FD07A), dark = Color(0xFF5FA552), shell = Color(0xFF3F8F5F), rim = Color(0xFF2F6E49), plate = Color(0xFFF6E7A8);
  final p = c.p;
  final hide = p.special.clamp(0.0, 1.0);
  c.head = Offset(100, 86 + hide * 60);
  c.headRx = 44;
  c.headTop = 46;
  c.behind();
  c.oval(142, 196, 9, 5, skin);
  c.both((left, arm, leg) => c.at(100, 196, 0, () => c.foot(leg, 81, 206, 16, 9.5, skin), sx: 1 - hide * 0.35));
  c.oval(100, 168, 51, 45, rim);
  c.volume(c.ovalPath(100, 166, 47, 42), shell);
  for (final (x, y) in const [(62.0, 146.0), (138.0, 146.0), (56.0, 170.0), (144.0, 170.0), (64.0, 194.0), (136.0, 194.0), (100.0, 130.0)]) {
    c.oval(x, y, 9.5, 8.5, rim);
    c.oval(x - 0.8, y - 0.8, 7.5, 6.5, _lighter(shell, 0.16));
  }
  void headGroup() => c.at(100, 128, p.headTilt, () {
        c.blob(100, 127, 17, 15, skin);
        c.line('M90 126 q10 4 20 0 M92 133 q8 3 16 0', dark, 1.8);
        c.canvas.translate(40, 22);
        c.volume(c.ovalPath(60, 62, 44, 40), skin);
        // Yaşlılık: alın çizgileri ve benekler
        final crease = _darker(skin, 0.3);
        c.line('M46 31 q14 -5 28 0 M50 38 q10 -3 20 0', crease, 1.8);
        c.oval(27, 50, 3, 2.4, _darker(skin, 0.16));
        c.oval(92, 44, 2.6, 2.1, _darker(skin, 0.16));
        c.oval(88, 51, 1.8, 1.5, _darker(skin, 0.16));
        c.blush(25, 95, 78, 8);
        c.eyes(41, 79, 58, 13, lid: skin, brow: const Color(0x00000000), iris: const Color(0xFF8A5A32), rest: 0.3);
        // Göz altı torbaları ve gülme çizgileri
        c.line('M30 75 q11 6 22 0 M68 75 q11 6 22 0', crease, 1.8);
        c.line('M45 84 q-3 4 -1 8 M75 84 q3 4 1 8', crease, 1.6);
        c.mouth(60, 84, 9);
        // Gür beyaz kaşlar: dış uçları aşağı sarkar, ifadeyle birlikte oynar
        c.both((left, arm, leg) => c.at(40, 42, -(p.browTilt * 0.5 - p.brow * 0.08), () {
              c.line('M25 47 Q36 35 54 42', const Color(0xFFB9B4A6), 9);
              c.line('M25 47 Q36 35 54 42', const Color(0xFFFAF7EF), 6.2);
            }, dy: -p.brow * 6), width: 120);
        // Yuvarlak tel gözlük
        const rim = Color(0xFFB07A2A);
        for (final x in const [41.0, 79.0]) {
          c.stroke(c.ovalPath(x, 58.5, 17, 17.5), rim, 2.2);
        }
        c.line('M58 57 q2 -3 4 0 M24 56 l-7 -3 M96 56 l7 -3', rim, 2.2);
        // Küçük beyaz sakal
        c.shape('M49 97 Q60 122 71 97 Q60 104 49 97 Z', const Color(0xFFB9B4A6));
        c.shape('M51.5 99.5 Q60 117 68.5 99.5 Q60 105 51.5 99.5 Z', const Color(0xFFFAF7EF));
        c.onHead(60, 22, 44, 60);
      }, dx: p.headX, dy: p.headY + hide * 62, sx: 1 - hide * 0.5, sy: 1 - hide * 0.5);
  if (hide > 0.02) headGroup(); // kabuğa çekilirken kafa göğüs plakasının arkasında kalır
  final cane = p.propA < 0.05 && hide < 0.3;
  c.both((left, arm, leg) => c.at(100, 150, 0, () => c.arm(left, arm + (!left && cane && arm > -0.2 ? 0.35 : 0), 62, 152, 34, 17, skin, hand: _darker(skin, 0.1), handR: 9), sx: 1 - hide * 0.4));
  if (cane) {
    final h = c.handR;
    final stick = Path()
      ..moveTo(h.dx - 10, h.dy - 6)
      ..quadraticBezierTo(h.dx - 4, h.dy - 20, h.dx + 3, h.dy - 8)
      ..lineTo(h.dx + 5, math.min(212.0, h.dy + 46));
    c.stroke(stick, const Color(0xFF6B4423), 6.5);
    c.stroke(stick, const Color(0xFFA9743F), 3.6);
  }
  c.oval(100, 170, 33.5, 34.5, _darker(plate, 0.2));
  c.patch(100, 170, 32, 33, plate);
  c.shadowOn(c.ovalPath(100, 170, 32, 33), 100, 136, 30, 14, 0.16);
  c.line('M100 138 V202 M70 162 H130 M75 185 H125', const Color(0xFFDCC777), 2.8);
  if (hide <= 0.02) headGroup();
  c.held();
}

// pasa: ilk çizim (yenisi rig_vector.dart içinde).
// ignore: unused_element
void _pasaClassic(_C c) {
  const skin = Color(0xFF93A8C6), dark = Color(0xFF7389AA), ear = Color(0xFFF4B6C6), belly = Color(0xFFB8C8DE);
  final p = c.p;
  c.head = const Offset(100, 77);
  c.headRx = 49;
  c.headTop = 32;
  c.behind();
  c.at(138, 184, p.tail * 0.6, () {
    c.line('M138 184 q14 2 16 14', dark, 4);
    c.oval(155, 200, 5, 6, _darker(dark, 0.2));
  });
  c.both((left, arm, leg) {
    c.foot(leg, 80, 200, 17, 15, skin);
    c.at(0, 0, 0, () => c.line('M69 209 q3 -4 6 0 M83 209 q3 -4 6 0', belly, 2.6), dx: -leg * 5, dy: -leg * 12);
  });
  c.volume(c.ovalPath(100, 168, 43, 41), skin);
  c.patch(100, 177, 27, 29, belly);
  c.shadowOn(c.ovalPath(100, 168, 43, 41), 100, 128, 44, 20);
  c.both((left, arm, leg) => c.arm(left, arm, 64, 154, 36, 18, dark, hand: _darker(dark, 0.08), handR: 10));
  c.at(100, 124, p.headTilt, () {
    c.canvas.translate(32.8, 14.5);
    c.canvas.scale(1.12);
    c.both((left, arm, leg) => c.at(34, 54, 0, () {
          c.blob(12, 54, 28, 31, dark);
          c.oval(13, 56, 14, 18, ear);
          c.oval(9, 50, 6, 9, _lighter(ear, 0.3));
        }, sx: 1 + p.ear * 0.22, sy: 1 - p.ear * 0.05), width: 120);
    c.volume(c.ovalPath(60, 56, 42, 40), skin);
    // Fes: hafif yana yatık; püskülü kafayla birlikte sallanır
    c.at(63, 19, 0.17, () {
      const fez = Color(0xFFD63B4B);
      c.volume(_path('M49 21 L54 1 Q63 -2 72 1 L77 21 Q63 26 49 21 Z'), fez, dx: -2, dy: -2);
      c.oval(63, 1, 9, 2.4, _darker(fez, 0.2));
      c.at(63, 1, wave(c.time, 2.4) * 0.1 - p.headTilt * 1.4 - p.lean, () {
        c.line('M63 1 Q75 -3 79 7 V14', _ink, 1.6);
        c.shape('M76 13 h6 l2 11 q-5 2 -10 0 Z', _ink);
        c.line('M76 15 h6', const Color(0xFFFFC83D), 2);
      });
    });
    c.blush(30, 90, 71, 7);
    // Fildişleri: hortumun iki yanından aşağı kıvrılır
    c.both((left, arm, leg) {
      const tusk = 'M52 79 C52 89 48 96 41 100 C43 93 44 86 45 79 Z';
      c.shape(tusk, const Color(0xFFFFF8E7));
      c.line(tusk, const Color(0xFFCDBB95), 1.5);
    }, width: 120);
    c.eyes(41, 79, 50, 12, lid: skin, brow: dark, iris: const Color(0xFF4E7BB8), lashes: true);
    c.at(38, 84, 0, () => c.mouth(40, 84, 6));
    // Hortum: [special] arttıkça yukarı doğru kıvrılır
    final trunk = Path()..moveTo(60 + p.lookX * 1.6, 62);
    var x = 60 + p.lookX * 1.6, y = 62.0, ang = 0.0;
    final turn = 0.07 + p.special * 0.44;
    for (var i = 0; i < 7; i++) {
      ang += i < 2 ? 0 : turn * 1.15;
      x += math.sin(ang) * 6.6;
      y += math.cos(ang) * 6.6;
      trunk.lineTo(x, y);
    }
    c.stroke(trunk, dark, 21);
    c.stroke(trunk, skin, 17);
    // Hortum kırışıkları: yol boyunca kısa çizgiler
    final metric = trunk.computeMetrics().first;
    for (final f in const [0.3, 0.5, 0.7, 0.88]) {
      final tan = metric.getTangentForOffset(metric.length * f)!;
      final n = Offset(-tan.vector.dy, tan.vector.dx);
      c.seg(tan.position - n * 6.5, tan.position + n * 6.5, dark, 1.8);
    }
    c.tip = Offset(32.8 + x * 1.12, 14.5 + y * 1.12); // gövde uzayına çevrilmiş hortum ucu
    c.onHead(60, 16, 42, 54);
  }, dx: p.headX, dy: p.headY);
  c.held();
}

// sekiz: ilk çizim (yenisi rig_vector.dart içinde).
// ignore: unused_element
void _sekizClassic(_C c) {
  const skin = Color(0xFFF06C9B), dark = Color(0xFFD24D80), spot = Color(0xFFFFA9C6);
  final p = c.p;
  c.head = const Offset(100, 100);
  c.headRx = 60;
  c.headTop = 62;
  c.behind();
  // Dokunaçlar: uçları sürekli kıpırdar; dıştakiler kol gibi kalkar
  Path tentacle(List<double> d, List<double> u, double k, double phase) {
    double v(int i) => d[i] + (u[i] - d[i]) * k;
    final w = wave(c.time, 1.7, phase) * (3 + p.ear * 5);
    return Path()
      ..moveTo(v(0), v(1))
      ..cubicTo(v(2), v(3), v(4) + w * 0.6, v(5), v(6) + w, v(7) - w.abs() * 0.3);
  }

  c.both((left, arm, leg) {
    // Arkada kalan dördüncü çift: adı üstünde, sekiz kol
    c.tube(tentacle(const [66, 150, 54, 174, 44, 190, 37, 207], const [66, 150, 52, 170, 38, 182, 28, 198], leg * 0.6, left ? 0.45 : 0.95), _darker(dark, 0.16), 13);
    final k = (arm / 1.6).clamp(-0.2, 1.2).toDouble();
    final outer = tentacle(const [56, 146, 40, 168, 26, 176, 20, 198], const [52, 134, 30, 126, 20, 104, 26, 80], k, left ? 0 : 0.5);
    c.tube(outer, dark, 15);
    final end = outer.computeMetrics().first;
    final h = end.getTangentForOffset(end.length)!.position;
    c._hand(left, h);
    c.blob(h.dx, h.dy, 8, 8, dark);
    for (final f in const [0.5, 0.68, 0.86]) {
      final cup = end.getTangentForOffset(end.length * f)!.position;
      c.oval(cup.dx, cup.dy, 3.2, 3.2, spot);
    }
    final mid = tentacle(const [76, 158, 68, 182, 56, 192, 50, 210], const [76, 158, 60, 176, 44, 182, 34, 196], leg, left ? 0.3 : 0.8);
    c.tube(mid, skin, 15);
    final midMetric = mid.computeMetrics().first;
    for (final f in const [0.55, 0.74, 0.92]) {
      final cup = midMetric.getTangentForOffset(midMetric.length * f)!.position;
      c.oval(cup.dx, cup.dy, 3, 3, spot);
    }
    c.tube(tentacle(const [92, 162, 90, 186, 86, 198, 88, 212], const [92, 162, 90, 186, 86, 198, 88, 212], 0, left ? 0.6 : 0.1), _darker(skin, 0.08), 15);
  });
  c.at(100, 165, p.headTilt, () {
    c.volume(_path('M40 112 C40 50 160 50 160 112 C160 146 138 170 100 170 C62 170 40 146 40 112 Z'), skin);
    c.oval(70, 132, 8, 5.5, spot.withValues(alpha: 0.7));
    c.oval(136, 138, 6, 4.5, spot.withValues(alpha: 0.7));
    c.blush(58, 142, 124, 8.5);
    c.eyes(77, 123, 104, 16, lid: skin, brow: dark, iris: const Color(0xFF2FA7A0));
    c.mouth(100, 128, 9);
    // Alnına itilmiş mucit gözlüğü
    c.line('M44 92 Q100 58 156 92', const Color(0xFF4A332D), 6);
    for (final x in [83.0, 117.0]) {
      c.oval(x, 76, 14, 13, const Color(0xFF4A332D));
      c.oval(x, 76, 10, 9, const Color(0xFF9BE3F2));
      c.oval(x - 3, 73, 3.5, 2.5, const Color(0xAAFFFFFF));
    }
    c.onHead(100, 62, 60, 110);
  }, dx: p.headX, dy: p.headY);
  c.held();
}

// dalga: ilk çizim (yenisi rig_vector.dart içinde).
// ignore: unused_element
void _dalgaClassic(_C c) {
  const skin = Color(0xFF3BA4EC), dark = Color(0xFF2380C4), belly = Color(0xFFE3F4FF), band = Color(0xFFFF5263);
  final p = c.p;
  c.head = const Offset(100, 78);
  c.headRx = 46;
  c.headTop = 30;
  c.behind();
  c.at(104, 196, p.tail * 0.45, () => c.volume(_path('M104 192 C78 196 60 210 54 224 C80 226 96 218 104 206 C112 218 128 226 154 224 C148 210 130 196 104 192 Z'), dark, dx: -3, dy: -3));
  c.volume(_path('M136 62 C158 46 172 56 176 76 C164 70 152 74 146 88 Z'), dark, dx: -3, dy: -3);
  c.both((left, arm, leg) => c.wing(left, arm, 'M60 120 C38 132 30 156 38 176 C56 164 66 146 68 128 Z', 62, 124, 50, dark));
  c.at(100, 196, p.headTilt * 0.6, () {
    final torso = _path('M100 30 C142 30 154 84 146 132 C140 168 122 192 104 200 C88 192 60 168 54 132 C46 84 58 30 100 30 Z');
    c.volume(torso, skin);
    // Açık renk çene ve karın: üst kenarı ağız çizgisini izler (yunusun alt çenesi beyazdır)
    const mw = 19.0, my = 104.0;
    final mx = 100 + p.lookX * 1.6, corner = my - p.smile * mw * 0.15;
    final bib = Path()
      ..moveTo(mx - mw, corner)
      ..quadraticBezierTo(mx, my + p.smile * mw, mx + mw, corner)
      ..cubicTo(mx + mw + 9, corner + 14, 130, 132, 126, 152)
      ..cubicTo(120, 174, 110, 190, 104, 196)
      ..cubicTo(96, 190, 80, 174, 74, 152)
      ..cubicTo(70, 132, mx - mw - 9, corner + 14, mx - mw, corner)
      ..close();
    c.fill(bib, belly);
    c.glow(bib, mx, my + 22, 22, 6, const Color(0x1F1F5FA8)); // çenenin karna düşen gölgesi
    // Spor bandı: uçları dalgalanır
    c.line('M60 61 Q100 45 140 61', band, 9.5);
    final f = wave(c.time, 0.9) * 4 + p.ear * 8;
    c.fill(
        Path()
          ..moveTo(140, 59)
          ..relativeLineTo(17 + f * 0.4, -9 - f)
          ..relativeLineTo(-3, 11)
          ..relativeLineTo(12 + f * 0.3, 5 + f * 0.6)
          ..relativeLineTo(-22, 3)
          ..close(),
        band);
    c.blush(64, 136, 98, 7.5);
    c.eyes(79, 121, 79, 13, lid: skin, brow: dark, iris: const Color(0xFF1F5FA8));
    // Üst çene: hafif kabarık, kontursuz; altında yunusun geniş gülümsemesi
    c.patch(mx, my - 6.5, 21, 9.5, _lighter(skin, 0.16));
    c.mouth(100, my, mw, thick: 4.2);
    c.onHead(100, 30, 46, 80);
  }, dx: p.headX, dy: p.headY);
  c.held();
}

const _painters = {
  MascotId.puhu: _puhu,
  MascotId.tarcin: _tarcin,
  MascotId.zifir: _zifir,
  MascotId.tosbi: _tosbi,
  MascotId.pasa: _pasa,
  MascotId.sekiz: _sekiz,
  MascotId.dalga: _dalga,
};

/* ================= Sahne ================= */

/// Gövde uzayındaki bir noktayı (zıplama, eğilme, yatma uygulanmış hâliyle) tuvale çevirir.
Offset _toScene(Pose p, Offset o) {
  final sx = 1 + p.squash * 0.08, sy = 1 - p.squash * 0.1;
  final x = (o.dx - 100) * sx, y = (o.dy - p.y - 212) * sy;
  final a = p.rot + p.lean;
  final lying = (p.rot.abs() / 1.57).clamp(0.0, 1.0);
  return Offset(100 + p.dx + x * math.cos(a) - y * math.sin(a), 212 - 44 * lying + x * math.sin(a) + y * math.cos(a));
}

/// Kafanın çevresinde yüzen efektler ve gövdeye bağlı olmayan eşyalar.
void _floaters(_C c) {
  final p = c.p;
  final t = c.time;
  final head = _toScene(p, c.head);
  final top = _toScene(p, Offset(c.head.dx, c.headTop));
  if (p.zzz > 0.02) {
    for (var i = 0; i < 3; i++) {
      final k = ((t / 2.4) + i / 3) % 1;
      final o = top.translate(34 + k * 26 + wave(t, 1.8, i / 3) * 4, -6 - k * 46);
      final s = (0.7 + k * 0.9) * p.zzz;
      c.stroke(
          Path()
            ..moveTo(o.dx - 5 * s, o.dy - 5 * s)
            ..relativeLineTo(10 * s, 0)
            ..relativeLineTo(-10 * s, 10 * s)
            ..relativeLineTo(10 * s, 0),
          const Color(0xFF7C5CFF).withValues(alpha: (1 - k) * p.zzz),
          2.6 * s);
    }
  }
  if (p.notes > 0.02) {
    for (var i = 0; i < 3; i++) {
      final k = ((t / 2.2) + i / 3) % 1;
      final side = i.isEven ? 1.0 : -1.0;
      c.note(top.translate(side * (40 + k * 22) + wave(t, 1.3, i / 3) * 5, 14 - k * 52), 0.9 + k * 0.4,
          [const Color(0xFF7C5CFF), const Color(0xFFFF5263), const Color(0xFF22B573)][i].withValues(alpha: (1 - k * k) * p.notes));
    }
  }
  if (p.sweat > 0.02) {
    for (var i = 0; i < 2; i++) {
      final k = ((t / 1.1) + i / 2) % 1;
      c.drop(top.translate((i == 0 ? -1 : 1) * (c.headRx * 0.8 + k * 8), 16 + k * 26), 0.9, const Color(0xFF7CC7FF).withValues(alpha: (1 - k) * p.sweat));
    }
  }
  if (p.tear > 0.02) c.drop(head.translate(-c.headRx * 0.62, 6 + ((t / 1.6) % 1) * 12), 0.9, const Color(0xFF7CC7FF).withValues(alpha: p.tear));
  if (p.sparkle > 0.02) {
    for (var i = 0; i < 4; i++) {
      final a = i * 1.57 + t * 1.2;
      c.star(head.translate(math.cos(a) * (c.headRx + 20), math.sin(a) * 46 - 8), (4 + wave(t, 0.8, i / 4) * 2.5) * p.sparkle, const Color(0xFFFFC83D));
    }
  }
  if (p.propA < 0.02) return;
  final a = p.propA;
  switch (p.prop) {
    case Prop.bulb:
      final o = top.translate(0, -30 - wave(t, 1.4) * 3);
      c.at(o.dx, o.dy, 0, () {
        for (var i = 0; i < 7; i++) {
          final ang = -math.pi + i * math.pi / 6;
          c.seg(o.translate(math.cos(ang) * 22, math.sin(ang) * 22), o.translate(math.cos(ang) * 30, math.sin(ang) * 30), const Color(0xFFFFC83D), 3);
        }
        c.oval(o.dx, o.dy, 15, 16, const Color(0xFFFFD84D));
        c.canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o.translate(0, 19), width: 13, height: 9), const Radius.circular(3)), Paint()..color = const Color(0xFF8E86B0));
        c.oval(o.dx - 5, o.dy - 5, 4, 5, const Color(0xAAFFFFFF));
      }, sx: a, sy: a);
    case Prop.cloud:
      final o = Offset(100 + p.dx * 0.2 + 30, 70 - wave(t, 3) * 4);
      c.at(o.dx, o.dy + 40, 0, () {
        c.oval(o.dx - 44, o.dy + 46, 5, 5, _white);
        c.oval(o.dx - 32, o.dy + 32, 8, 8, _white);
        for (final (dx, dy, r) in const [(-22.0, 6.0, 20.0), (0.0, -6.0, 26.0), (24.0, 4.0, 21.0), (2.0, 12.0, 24.0)]) {
          c.oval(o.dx + dx, o.dy + dy, r, r * 0.86, _white);
        }
        c.star(o.translate(-10, 2), 8 + wave(t, 1.1) * 2, const Color(0xFFFFC83D));
        c.star(o.translate(12, 8), 5 + wave(t, 0.9, 0.3) * 1.5, const Color(0xFF7C5CFF));
      }, sx: a, sy: a);
    case Prop.ball:
      final k = p.propT; // 0 yerde (ayakta), 1 tepede
      c.at(100, 150, 0, () => c.ball(_toScene(p, Offset(100 + wave(t, 2.2) * 26, 196 - k * 150)), 14, beach: false), sx: a, sy: a);
    case Prop.beachBall:
      c.at(top.dx, top.dy, 0, () => c.ball(top.translate(wave(t, 1.6) * 5, -20 - p.propT * 34), 21, beach: true), sx: a, sy: a);
    case Prop.gadgets:
      for (var i = 0; i < 3; i++) {
        final ang = (p.propT + i / 3) * 2 * math.pi;
        final o = top.translate(math.cos(ang) * 46, -34 + math.sin(ang) * 22);
        c.at(o.dx, o.dy, t * 2 + i, () {
          if (i == 0) {
            for (var j = 0; j < 6; j++) {
              c.oval(o.dx + math.cos(j * 1.047) * 9, o.dy + math.sin(j * 1.047) * 9, 3.4, 3.4, const Color(0xFF8E86B0));
            }
            c.oval(o.dx, o.dy, 8.5, 8.5, const Color(0xFF8E86B0));
            c.oval(o.dx, o.dy, 3.5, 3.5, _white);
          } else if (i == 1) {
            c.seg(o.translate(-9, 0), o.translate(9, 0), const Color(0xFF3A8DFF), 5);
            c.oval(o.dx + 10, o.dy, 6, 6, const Color(0xFF3A8DFF));
            c.oval(o.dx + 12, o.dy, 2.6, 2.6, _white);
          } else {
            c.oval(o.dx, o.dy, 8, 8.5, const Color(0xFFFFD84D));
            c.canvas.drawRect(Rect.fromCenter(center: o.translate(0, 10), width: 7, height: 5), Paint()..color = const Color(0xFF8E86B0));
          }
        }, sx: a, sy: a);
      }
    case Prop.smoke:
      final k = p.propT;
      for (final (dx, dy, r) in const [(-20.0, 0.0, 22.0), (8.0, -10.0, 28.0), (30.0, 4.0, 20.0), (4.0, 12.0, 24.0)]) {
        c.oval(100 + p.dx + dx * (1 + k), 150 + dy - k * 40, r * (0.5 + k) * a, r * (0.45 + k * 0.9) * a, const Color(0xFF9C95B8).withValues(alpha: (1 - k) * 0.85));
      }
    case Prop.water:
      final tip = _toScene(p, c.tip);
      for (var i = 0; i < 7; i++) {
        final k = ((t / 0.9) + i / 7) % 1;
        c.drop(tip.translate(-10 + k * 58 - 20, -8 - math.sin(k * math.pi) * 50 + k * 60), 0.8 + (i % 3) * 0.2, const Color(0xFF7CC7FF).withValues(alpha: a * (1 - k * 0.6)));
      }
    default:
      break;
  }
}

void paintMascot(Canvas canvas, Size size, MascotId id, Pose p, double time) {
  final s = size.width / 200;
  canvas.save();
  canvas.scale(s);
  final c = _C(canvas, p, time);
  final lying = (p.rot.abs() / 1.57).clamp(0.0, 1.0);
  final shadowRx = (50 + lying * 44) * (1 - p.y / 170).clamp(0.45, 1.0);
  canvas.drawOval(
      Rect.fromCenter(center: Offset(100 + p.dx + lying * 61 * p.rot.sign, 214), width: shadowRx * 2, height: 15),
      Paint()
        ..color = const Color(0x33140E28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5));
  canvas.save();
  canvas.translate(p.dx, -44 * lying);
  c.at(100, 212, p.rot + p.lean, () {
    canvas.translate(0, -p.y);
    _painters[id]!(c);
  }, sx: 1 + p.squash * 0.08, sy: 1 - p.squash * 0.1);
  canvas.restore();
  _floaters(c);
  canvas.restore();
}
