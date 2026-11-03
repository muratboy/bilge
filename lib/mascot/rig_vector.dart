part of 'rig.dart';

/* Vektör karakterler (koyu kontur, düz renk, iri parlak gözler).
   Her karakter 1024 birimlik kendi çizim uzayında tanımlıdır; [_Art.art] bu uzayı sahneye oturtur.
   Eklemler sahne uzayında döner, böylece hareketlerin hepsi ([Pose]) aynen uygulanır. */

const _vInk = Color(0xFF3A1A14);

/// Şu an çizilen karakterin kontur rengi (her karakter kendi koyusunu kullanır).
Color _inkNow = _vInk;

/// Karakterin çizim uzayı: [k] çizim birimini sahne birimine çevirir; [cx] karakterin ortası, [ground] ayak tabanıdır.
class _Space {
  const _Space(this.k, this.cx, this.ground);
  final double k, cx, ground;

  /// Çizim uzayındaki bir noktanın sahnedeki yeri (karakter ortalı, ayak tabanı zeminde).
  Offset at(double x, double y) => Offset(100 + (x - cx) * k, 214 - (ground - y) * k);
}

const _puhuSpace = _Space(190 / 771, 512, 902);

const _spaces = {
  MascotId.puhu: _puhuSpace,
  MascotId.tarcin: _tarcinSpace,
  MascotId.zifir: _zifirSpace,
  MascotId.tosbi: _tosbiSpace,
  MascotId.pasa: _pasaSpace,
  MascotId.sekiz: _sekizSpace,
  MascotId.dalga: _dalgaSpace,
};

/// Karakteri kendi 1024 birimlik çizim uzayında çizer (çizim birimi = piksel).
void paintMascotArt(Canvas canvas, MascotId id, Pose p) {
  final sp = _spaces[id]!;
  canvas.save();
  canvas.translate(sp.cx - 100 / sp.k, sp.ground - 214 / sp.k);
  paintMascot(canvas, Size(200 / sp.k, 230 / sp.k), id, p, 0);
  canvas.restore();
}

final _vBrown = Paint()
  ..shader = Gradient.radial(const Offset(430, 260), 520, const [Color(0xFFB9834F), Color(0xFFA46F42), Color(0xFF875732)], const [0, 0.5, 1]);
final _vBodyBrown = Paint()
  ..shader = Gradient.radial(const Offset(430, 560), 380, const [Color(0xFFB9834F), Color(0xFFA46F42), Color(0xFF875732)], const [0, 0.5, 1]);
final _vCream = Paint()..shader = Gradient.linear(const Offset(0, 250), const Offset(0, 820), const [Color(0xFFFFFAE3), Color(0xFFF4E6BD)]);
final _vFlat = Paint()..isAntiAlias = true;

extension _Art on _C {
  /// [draw]'ı karakterin 1024 birimlik çizim uzayında çalıştırır.
  void art(_Space s, void Function() draw) {
    canvas.save();
    canvas.translate(100, 214);
    canvas.scale(s.k);
    canvas.translate(-s.cx, -s.ground);
    draw();
    canvas.restore();
  }

  /// Koyu konturlu dolu biçim.
  void inked(String d, Paint paint, {double w = 7}) {
    final path = _path(d);
    canvas.drawPath(path, paint);
    stroke(path, _inkNow, w);
  }

  /// [draw]'ı [d] biçiminin içine kırparak çizer.
  void clipped(String d, void Function() draw) {
    canvas.save();
    canvas.clipPath(_path(d));
    draw();
    canvas.restore();
  }

  /// Koyu konturlu oval.
  void inkOval(double cx, double cy, double rx, double ry, Paint paint, {double w = 7}) {
    final r = Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
    canvas.drawOval(r, paint);
    stroke(Path()..addOval(r), _inkNow, w);
  }

  /// Koyu konturlu kalın çizgi (kol, bacak, dokunaç, hortum).
  void inkTube(Path path, Color color, double w, {double edge = 7}) {
    stroke(path, _inkNow, w + edge * 2);
    stroke(path, color, w);
  }

  /// Ağız: gülümseme eğrisi; açıldıkça içi ve dili görünür.
  /// [rest]: karakter gülümserken ağzının doğal açıklığı (dili görünen, açık gülüş).
  void grin(double cx, double cy, double w, {Color tongue = const Color(0xFFF2918F), double rest = 0}) {
    final s = p.smile.clamp(-1.0, 1.0);
    final o = math.max(p.open.clamp(0.0, 1.0), rest * ((s - 0.2) / 0.4).clamp(0.0, 1.0));
    if (p.round > 0.5) {
      // Şaşkınlık: yuvarlak "o" ağız
      final r = Rect.fromCenter(center: Offset(cx, cy + w * 0.16), width: w * 0.34, height: w * (0.3 + o * 0.22));
      canvas.drawOval(r, flat(const Color(0xFF7A2030)));
      stroke(Path()..addOval(r), _inkNow, 6);
      return;
    }
    final ends = cy - s * w * 0.10, dip = cy + s * w * 0.36;
    if (o > 0.15) {
      final deep = ends + w * (0.5 + o * 0.9);
      final mouth = Path()
        ..moveTo(cx - w / 2, ends)
        ..quadraticBezierTo(cx, ends + s * w * 0.12, cx + w / 2, ends)
        ..quadraticBezierTo(cx, deep, cx - w / 2, ends)
        ..close();
      canvas.drawPath(mouth, flat(const Color(0xFF7A2030)));
      canvas.save();
      canvas.clipPath(mouth);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, ends + (deep - ends) * 0.52), width: w * 0.62, height: w * 0.34), flat(tongue));
      canvas.restore();
      stroke(mouth, _inkNow, 6);
    } else {
      stroke(Path()..moveTo(cx - w / 2, ends)..quadraticBezierTo(cx, dip, cx + w / 2, ends), _inkNow, 6.5);
    }
  }

  /// Kaşlar: [rise] kaldırır; üzüntüde iç uçları kalkar, kızgınlıkta iner ([base]: karakterin doğal eğimi).
  void brows(double lx, double rx, double y, double len, {double w = 7, double base = 0, Color? color}) {
    for (final side in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(side < 0 ? lx : rx, y - p.brow * 9);
      canvas.rotate(side * (p.browTilt * 0.35 - base));
      stroke(Path()..moveTo(-len / 2, 0)..quadraticBezierTo(0, -len * 0.18, len / 2, 0), color ?? _inkNow, w);
      canvas.restore();
    }
  }

  void cheeks(double lx, double rx, double y, [double rw = 40, double rh = 24, Color color = const Color(0x66F58FA0)]) {
    for (final x in [lx, rx]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: rw * 2, height: rh * 2), flat(color));
    }
  }

  Paint flat(Color color) => _vFlat..color = color;

  /// İri, parlak göz: göz kapağı üstten iner, bakış göz bebeğini kaydırır, sevinçte ve uykuda yay olur.
  void bigEye(double cx, double cy, double lid,
      {required Color iris,
      required Color irisDark,
      required Color lidColor,
      double size = 63,
      Color pupilColor = const Color(0xFF4A2618),
      Color pupilDark = const Color(0xFF2A120B),
      double adore = 0}) {
    final u = size / 63; // ölçek
    if (p.joy > 0.5) {
      stroke(Path()..moveTo(cx - 46 * u, cy + 12 * u)..quadraticBezierTo(cx, cy - 44 * u, cx + 46 * u, cy + 12 * u), _inkNow, 9 * u);
      return;
    }
    if (lid > 0.85) {
      stroke(Path()..moveTo(cx - 48 * u, cy - 2 * u)..quadraticBezierTo(cx, cy + 30 * u, cx + 48 * u, cy - 2 * u), _inkNow, 8 * u);
      return;
    }
    final r = size * (1 + 0.08 * p.wide);
    final center = Offset(cx, cy);
    final look = Offset(p.lookX * 11, p.lookY * 11) * u;
    canvas.drawCircle(center, r, flat(_inkNow));
    canvas.drawCircle(center, r - 6.5 * u, Paint()..shader = Gradient.radial(Offset(cx, cy + r * 0.3), r * 1.25, [iris, iris, irisDark], const [0, 0.5, 1]));
    // Şaşkınlıkta göz bebeği küçülür; hayranlıkta ([adore]) büyür ve içinde yıldız parlar
    final pupil = r * 0.70 * (1 - 0.22 * p.wide * (1 - adore)) * (1 + 0.14 * adore);
    canvas.drawCircle(center + look, pupil, flat(pupilColor));
    canvas.drawCircle(center + look + Offset(1, 5) * u, pupil * 0.72, flat(pupilDark));
    canvas.drawCircle(center + look * 0.6 + Offset(-18, -27) * u, 14.5 * u, flat(const Color(0xFFFFFFFF)));
    canvas.drawCircle(center + look * 0.6 + Offset(25, 29) * u, 7.5 * u, flat(const Color(0xEBFFFFFF)));
    if (adore > 0.05) star(center + look + Offset(12, 8) * u, 17 * u * adore, const Color(0xFFFFFFFF));
    if (lid > 0.05) {
      // Göz kapağı: gözün üstünü yüzün rengiyle örter, altına kirpik çizgisi gelir
      final y = cy - r + 2 * r * lid;
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r + 1)));
      canvas.drawRect(Rect.fromLTRB(cx - r - 2, cy - r - 2, cx + r + 2, y), flat(lidColor));
      canvas.restore();
      final half = math.sqrt(math.max(0, r * r - (y - cy) * (y - cy)));
      seg(Offset(cx - half, y), Offset(cx + half, y), _inkNow, 6.5 * u);
      stroke(Path()..addArc(Rect.fromCircle(center: center, radius: r - 3 * u), math.pi, math.pi), _inkNow, 6 * u);
    }
  }
}

void _puhu(_C c) {
  final p = c.p;
  const sp = _puhuSpace;
  _inkNow = _vInk;
  c.head = sp.at(512, 345);
  c.headRx = 232 * sp.k;
  c.headTop = sp.at(512, 92).dy; // mantar şapkanın tepesi
  c.behind();

  // Ayaklar: kaldırılınca hafifçe öne ve yukarı çıkar
  c.both((left, arm, leg) => c.art(sp, () {
        c.canvas.translate(-84 - leg * 14, -166 - leg * 44);
        c.canvas.scale(1.2);
        c.inked('M406 834 L403 864 L439 864 L436 834 Z', c.flat(const Color(0xFFD39A38)));
        c.inked('M370 880 C368 862 386 854 402 860 C410 850 432 850 440 860 C456 854 472 862 470 880 C470 894 454 898 444 890 C436 902 406 902 398 890 C388 898 370 894 370 880 Z', c.flat(const Color(0xFFE6B04A)));
        c.line('M402 862 C400 872 400 880 398 890 M440 862 C442 872 442 880 444 890', _inkNow, 5);
        c.shape('M372 886 l-10 10 l13 0 Z M415 898 l6 13 l6 -13 Z M468 886 l10 10 l-13 0 Z', _inkNow);
      }));

  // Gövde ve karın
  c.art(sp, () {
    c.inked('M512 498 C404 498 322 566 306 664 C298 742 372 850 512 850 C652 850 726 742 718 664 C702 566 620 498 512 498 Z', _vBodyBrown);
    c.canvas.drawPath(_path('M512 586 C442 586 396 636 388 704 C384 752 402 788 428 800 C442 814 462 808 472 798 C486 818 512 820 524 802 C540 818 566 814 578 798 C596 810 618 802 626 788 C646 770 648 730 640 700 C630 636 584 586 512 586 Z'), _vCream);
    c.line('M512 586 C442 586 396 636 388 704 C384 752 402 788 428 800 C442 814 462 808 472 798 C486 818 512 820 524 802 C540 818 566 814 578 798 C596 810 618 802 626 788 C646 770 648 730 640 700 C630 636 584 586 512 586 Z', const Color(0xFFE0CC9A), 5);
    c.line('M426 646 q10 12 22 0 M468 660 q10 12 22 0 M546 660 q10 12 22 0 M588 646 q10 12 22 0 M506 684 q10 12 22 0', const Color(0xFFD9C38C), 5);
  });

  // Entelektüel arkeolog: haki saha yeleği (cebinde fırça), çapraz askılı deri çanta
  const khaki = Color(0xFFC6AD72), khakiDark = Color(0xFFA68D52), leather = Color(0xFF8A5A32);
  c.art(sp, () {
    const body = 'M512 498 C404 498 322 566 306 664 C298 742 372 850 512 850 C652 850 726 742 718 664 C702 566 620 498 512 498 Z';
    c.clipped(body, () {
      for (final side in const [-1.0, 1.0]) {
        c.canvas.save();
        c.canvas.translate(512, 0);
        c.canvas.scale(side, 1);
        c.inked('M-230 470 L-52 470 C-74 560 -84 660 -70 760 L-96 822 L-230 822 Z', c.flat(khaki), w: 6);
        c.canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-148, 668, 62, 60), const Radius.circular(9)), c.flat(khakiDark));
        c.stroke(Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-148, 668, 62, 60), const Radius.circular(9))), _inkNow, 5);
        c.line('M-148 688 h62', _inkNow, 5);
        c.canvas.restore();
      }
      // Cepteki kazı fırçası
      c.line('M392 668 L384 626', _inkNow, 13);
      c.line('M392 668 L384 626', const Color(0xFFB8763A), 7);
      c.inked('M372 628 L396 624 L392 598 L370 602 Z', c.flat(const Color(0xFFF1E3B8)), w: 4);
      // Çanta askısı: sol omuzdan sağ kalçaya
      c.line('M396 520 C470 610 570 700 652 770', _inkNow, 24);
      c.line('M396 520 C470 610 570 700 652 770', leather, 15);
    });
    c.line(body, _inkNow, 7);
  });

  // Kanatlar: omuzdan döner; ucu "el" sayılır (eşyalar oraya gelir)
  final shoulder = sp.at(346, 540);
  final reach = 237.7 * sp.k; // sarkık kanadın boyu
  const rest = 0.118; // ve dikeyden sapması
  c.both((left, arm, leg) {
    final a = arm * 1.15; // kanat sevinçte başın arkasına girmez, yana ve yukarı açılır
    c.at(shoulder.dx, shoulder.dy, a, () => c.art(sp, () {
          c.inked('M338 524 C300 546 266 610 262 672 C260 706 268 732 284 752 Q296 746 302 732 Q306 760 318 776 Q332 766 338 750 Q344 770 356 780 C376 740 382 668 370 596 C364 558 354 534 338 524 Z', c.flat(const Color(0xFF96633B)));
          c.line('M300 732 C294 694 298 656 310 624 M336 750 C332 708 334 668 344 632', const Color(0xB33A1A14), 4.5);
          c.line('M300 566 C282 596 274 630 274 664', const Color(0xB3B9834F), 7);
        }));
    c._hand(left, Offset(shoulder.dx - math.sin(a + rest) * reach, shoulder.dy + math.cos(a + rest) * reach));
  });

  // Deri çanta sağ kalçada durur; içinden rulo bir harita çıkar
  c.art(sp, () {
    c.inked('M640 716 L664 690 L690 706 L668 734 Z', c.flat(const Color(0xFFF4E9C8)), w: 5);
    c.inked('M606 742 C606 730 616 722 628 722 L712 722 C724 722 734 730 734 742 L734 812 C734 826 724 836 710 836 L630 836 C616 836 606 826 606 812 Z', c.flat(leather));
    c.inked('M606 742 C606 730 616 722 628 722 L712 722 C724 722 734 730 734 742 L734 770 C700 792 640 792 606 770 Z', c.flat(const Color(0xFFA06A3C)), w: 5);
    c.inkOval(670, 784, 10, 10, c.flat(const Color(0xFFE5B63E)), w: 4);
  });

  c.art(sp, () => c.inked('M352 500 C400 536 462 548 512 548 C562 548 624 536 672 500 L676 526 C628 562 564 576 512 576 C460 576 396 562 348 526 Z', c.flat(const Color(0xFFB4302A))));

  // Baş: boyundan eğilir; kulak tüyleri başla tek biçimdir
  final neck = sp.at(512, 505);
  c.at(neck.dx, neck.dy, p.headTilt, () {
    c.art(sp, () {
      final head = _path('M512 514 C440 514 372 512 334 500 C312 486 300 464 295 444 C284 420 280 390 282 352 C284 322 290 300 300 284 C306 270 314 258 320 250 Q298 244 278 228 Q294 222 300 208 Q282 200 266 184 Q284 180 294 166 Q290 150 286 134 C326 146 370 168 404 184 C440 172 476 164 512 164 C548 164 584 172 620 184 C654 168 698 146 738 134 Q734 150 730 166 Q740 180 758 184 Q742 200 724 208 Q730 222 746 228 Q726 244 704 250 C710 258 718 270 724 284 C734 300 740 322 742 352 C744 390 740 420 729 444 C724 464 712 486 690 500 C652 512 584 514 512 514 Z');
      c.canvas.drawPath(head, _vBrown);
      c.canvas.save();
      c.canvas.clipPath(head);
      c.canvas.drawPath(_path('M512 334 C492 290 452 258 410 258 C350 258 300 306 300 366 C300 412 326 454 372 482 C420 506 470 508 512 506 C554 508 604 506 652 482 C698 454 724 412 724 366 C724 306 674 258 614 258 C572 258 532 290 512 334 Z'), _vCream);
      c.canvas.drawOval(Rect.fromCenter(center: const Offset(350, 436), width: 72, height: 42), c.flat(const Color(0x61F2A79E)));
      c.canvas.drawOval(Rect.fromCenter(center: const Offset(674, 436), width: 72, height: 42), c.flat(const Color(0x61F2A79E)));
      c.canvas.restore();
      c.stroke(head, _inkNow, 7);
      c.line('M298 208 C312 216 326 220 342 220 M726 208 C712 216 698 220 682 220', const Color(0xA63A1A14), 4.5);
      // Mantar şapka (kâşif şapkası): kulak tüylerinin arasına oturur
      c.inked('M420 190 C420 78 604 78 604 190 Z', c.flat(const Color(0xFFDCC78E)));
      c.line('M512 100 V186', const Color(0x66A68D52), 5);
      c.shape('M424 168 C470 156 554 156 600 168 L604 190 L420 190 Z', const Color(0xFF8A5A32));
      c.inked('M384 196 C440 168 584 168 640 196 C600 214 424 214 384 196 Z', c.flat(const Color(0xFFCDB67A)));
      c.inkOval(512, 92, 10, 7, c.flat(const Color(0xFFCDB67A)), w: 4);
      // Kaşlar: alnın kahverengisi iki gözün arasına V biçiminde iner; üzüntüde iç uçları kalkar
      for (final side in const [-1.0, 1.0]) {
        c.canvas.save();
        c.canvas.translate(512 + side * 186, 296 - p.brow * 8);
        c.canvas.rotate(side * p.browTilt * 0.22);
        c.canvas.scale(side, 1);
        c.line('M-186 38 C-166 -6 -126 -38 -84 -38 C-50 -38 -20 -24 0 0', _inkNow, 5.5);
        c.canvas.restore();
      }
      c.bigEye(412, 362, p.lidL, iris: const Color(0xFFEBA63C), irisDark: const Color(0xFFC5761A), lidColor: const Color(0xFFF3E4BA));
      c.bigEye(612, 362, p.lidR, iris: const Color(0xFFEBA63C), irisDark: const Color(0xFFC5761A), lidColor: const Color(0xFFF3E4BA));
      // İnce telli yuvarlak gözlük
      final rims = Path()
        ..addOval(Rect.fromCircle(center: const Offset(412, 362), radius: 74))
        ..addOval(Rect.fromCircle(center: const Offset(612, 362), radius: 74))
        ..moveTo(484, 348)
        ..quadraticBezierTo(512, 330, 540, 348)
        ..moveTo(338, 356)
        ..lineTo(296, 344)
        ..moveTo(686, 356)
        ..lineTo(728, 344);
      c.stroke(rims, _inkNow, 10);
      c.stroke(rims, const Color(0xFFE5B63E), 5);
      // Gaga: ağız açıldıkça alt yarısı iner
      if (p.open > 0.12) {
        c.canvas.drawOval(Rect.fromCenter(center: Offset(514, 436 + p.open * 8), width: 40, height: 26 + p.open * 30), c.flat(const Color(0xFF5A1E1A)));
        c.canvas.save();
        c.canvas.translate(0, p.open * 22);
        c.shape('M494 418 C500 438 508 452 514 458 C520 452 528 438 534 418 C522 426 506 426 494 418 Z', const Color(0xFFC4872B));
        c.line('M494 418 C500 438 508 452 514 458 C520 452 528 438 534 418 C522 426 506 426 494 418 Z', _inkNow, 5);
        c.canvas.restore();
      }
      c.inked('M512 376 C496 376 485 388 487 406 C491 432 503 452 514 462 C525 452 537 432 541 406 C543 388 528 376 512 376 Z', c.flat(const Color(0xFFE6B04A)));
      if (p.open <= 0.12) c.shape('M494 418 C500 438 508 452 514 458 C520 452 528 438 534 418 C522 426 506 426 494 418 Z', const Color(0xD9C4872B));
      c.line('M504 392 l3 7 M522 392 l-3 7', _inkNow, 4);
    });
    c.onHead(100, c.headTop, c.headRx, sp.at(512, 362).dy);
  }, dx: p.headX, dy: p.headY);

  // Papyon
  c.art(sp, () {
    c.inked('M506 556 C478 528 446 514 428 518 C418 546 418 584 430 604 C452 608 484 592 506 574 Z', c.flat(const Color(0xFFC63C33)));
    c.inked('M518 556 C546 528 578 514 596 518 C606 546 606 584 594 604 C572 608 540 592 518 574 Z', c.flat(const Color(0xFFC63C33)));
    c.line('M440 532 C456 534 474 544 490 556 M584 532 C568 534 550 544 534 556', const Color(0xFFE4736A), 6);
    c.line('M446 590 C462 588 480 580 494 570 M578 590 C562 588 544 580 530 570', const Color(0xB38E2420), 5);
    c.canvas.drawOval(Rect.fromCenter(center: const Offset(512, 564), width: 46, height: 50), c.flat(const Color(0xFFB4302A)));
    c.stroke(Path()..addOval(Rect.fromCenter(center: const Offset(512, 564), width: 46, height: 50)), _inkNow, 7);
    c.canvas.drawOval(Rect.fromCenter(center: const Offset(506, 556), width: 16, height: 14), c.flat(const Color(0xFFE4736A)));
  });
  c.held();
}

/// Kol ya da kanat: [draw] sarkık hâlini çizim uzayında çizer; omuz ([sx], [sy]) çevresinde döner ve ucu ([hx], [hy])
/// "el" olarak kaydedilir (eşyalar oraya gelir).
///
/// [swing]: kol değeri başına dönüş (radyan). Kısa omuzlu, iri başlı karakterlerde (kuşlar) küçük tutulur: kanat
/// yukarı kalkınca başın arkasında kaybolmak yerine yana ve yukarı açılır.
///
/// [sides]: 0 iki kol, 1 yalnız sol, 2 yalnız sağ (bir kol başın önünde, öbürü arkasında çizilecekse).
void _limbs(_C c, _Space sp, double sx, double sy, double hx, double hy, void Function() draw, {double swing = 1.5, int sides = 0}) {
  final pivot = sp.at(sx, sy);
  final rest = math.atan2(sx - hx, hy - sy), reach = Offset(hx - sx, hy - sy).distance * sp.k;
  void one(bool left, double arm) {
    final a = arm * swing;
    c.at(pivot.dx, pivot.dy, a, () => c.art(sp, draw));
    c._hand(left, Offset(pivot.dx - math.sin(a + rest) * reach, pivot.dy + math.cos(a + rest) * reach));
  }

  if (sides != 2) one(true, c.p.armL);
  if (sides != 1) {
    c.canvas.save();
    c.canvas.translate(200, 0);
    c.canvas.scale(-1, 1);
    one(false, c.p.armR);
    c.canvas.restore();
  }
}

/// Ayaklar: [draw] sol ayağı çizim uzayında çizer; kaldırılınca yukarı çıkar.
void _feet(_C c, _Space sp, void Function() draw) => c.both((left, arm, leg) => c.art(sp, () {
      c.canvas.translate(-leg * 14, -leg * 46);
      draw();
    }));

/// Baş: boyun ([nx], [ny]) çevresinde eğilir; [draw] çizim uzayında çizer, [after] sahne uzayında (kulaklık gibi eşyalar).
void _headGroup(_C c, _Space sp, double nx, double ny, void Function() draw, {double scale = 1, double drop = 0}) {
  final neck = sp.at(nx, ny);
  c.at(neck.dx, neck.dy, c.p.headTilt, () {
    c.art(sp, draw);
    c.onHead(100, c.headTop, c.headRx, c.head.dy + 4);
  }, dx: c.p.headX, dy: c.p.headY + drop, sx: scale, sy: scale);
}

Paint _radial(double x, double y, double r, Color light, Color mid, Color dark) =>
    Paint()..shader = Gradient.radial(Offset(x, y), r, [light, mid, dark], const [0, 0.5, 1]);

/* ---------- Tarçın ---------- */

const _tarcinSpace = _Space(190 / 825, 523, 925);
final _tOrange = _radial(470, 250, 520, const Color(0xFFFFA63D), const Color(0xFFF68A1E), const Color(0xFFE2700E));
final _tBody = _radial(420, 560, 420, const Color(0xFFFFA63D), const Color(0xFFF68A1E), const Color(0xFFE2700E));

void _tarcin(_C c) {
  final p = c.p;
  const sp = _tarcinSpace;
  const fur = Color(0xFFF68A1E), dark = Color(0xFF4A2E1E), white = Color(0xFFFFFBF4), teal = Color(0xFF20A698);
  _inkNow = const Color(0xFF3A1E12);
  final bino = p.prop == Prop.binoculars ? p.propA.clamp(0.0, 1.0) : 0.0;
  c.head = sp.at(523, 350);
  c.headRx = 250 * sp.k;
  c.headTop = sp.at(523, 170).dy;
  c.behind();

  // Kuyruk: gövdenin arkasında, kökünden sallanır
  final root = sp.at(404, 800);
  c.at(root.dx, root.dy, p.tail * 0.4, () => c.art(sp, () {
        c.canvas.drawPath(_path(_tarcinTail), _tBody);
        c.clipped(_tarcinTail, () => c.shape(_tarcinTailTip, white));
        c.line(_tarcinTail, _inkNow, 7);
      }));

  // Maceraperest kampçı: sırt çantası, haki yelek, çapraz tırmanış ipi, kemer, şort ve bağcıklı botlar
  const khaki = Color(0xFFCBAA68), khakiDark = Color(0xFFA98A4C), strap = Color(0xFF7A4A2A), olive = Color(0xFF5F6E3C), pack = Color(0xFF4E7C4C), rope = Color(0xFFEBDCA8);
  c.art(sp, () {
    // Sırt çantası gövdenin arkasında, iki yandan taşar; üstünde sarılı mat
    c.inked('M398 572 C396 556 408 546 424 546 L622 546 C638 546 650 556 648 572 L658 738 C658 758 646 770 630 770 L416 770 C400 770 388 758 388 738 Z', c.flat(pack));
    c.inked('M392 640 L376 648 L376 716 L392 724 Z M654 640 L670 648 L670 716 L654 724 Z', c.flat(const Color(0xFF3F6A40)));
    const torso = 'M446 556 C424 640 414 720 418 804 L628 804 C632 720 622 640 600 556 Z';
    c.inked(torso, c.flat(khaki));
    c.clipped(torso, () {
      // Yeleğin önü açık: göğsün beyaz kürkü görünür
      c.shape('M490 550 L556 550 C566 620 568 690 562 742 L484 742 C478 690 480 620 490 550 Z', white);
      c.line('M490 550 C480 620 478 690 484 742 M556 550 C566 620 568 690 562 742', _inkNow, 5);
      // Cepler
      for (final x in const [428.0, 574.0]) {
        c.canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 672, 46, 50), const Radius.circular(8)), c.flat(khakiDark));
        c.stroke(Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 672, 46, 50), const Radius.circular(8))), _inkNow, 4);
        c.line('M$x 688 h46', _inkNow, 4);
        c.canvas.drawCircle(Offset(x + 23, 690), 4.5, c.flat(const Color(0xFFE5B63E)));
      }
      // Şort ve kemer
      c.shape('M400 752 H650 V820 H400 Z', olive);
      c.shape('M400 738 H650 V758 H400 Z', strap);
      c.line('M400 738 H650 M400 758 H650', _inkNow, 4);
      c.canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(507, 736, 32, 24), const Radius.circular(5)), c.flat(const Color(0xFFE5B63E)));
      c.stroke(Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(507, 736, 32, 24), const Radius.circular(5))), _inkNow, 4);
      // Çanta askıları
      c.line('M462 552 C452 620 448 690 452 740 M584 552 C594 620 598 690 594 740', _inkNow, 22);
      c.line('M462 552 C452 620 448 690 452 740 M584 552 C594 620 598 690 594 740', strap, 14);
      // Omuzdan kalçaya çapraz sarılı tırmanış ipi
      for (final d in const [0.0, 15.0]) {
        final coil = Path()
          ..moveTo(474 + d, 556)
          ..cubicTo(520 + d, 620, 574 + d, 690, 606 + d, 742);
        c.stroke(coil, _inkNow, 15);
        c.stroke(coil, rope, 9);
      }
      c.line('M494 592 l14 -8 M530 646 l14 -8 M566 700 l14 -8', const Color(0xFFC25A3A), 5);
    });
    c.line(torso, _inkNow, 7);
  });

  // Bacaklar gövdenin üstüne, üst kenarı çizgisiz çizilir: kalçada dikiş görünmez
  _feet(c, sp, () {
    c.shape('M420 770 L428 868 L502 868 L508 770 Z', fur);
    c.shape('M420 770 L424 828 L506 828 L508 770 Z', olive); // şortun paçası
    c.line('M424 828 L506 828', _inkNow, 5);
    c.line('M420 796 L428 868 M508 796 L502 868', _inkNow, 7);
    // Bağcıklı dağ botu: kalın taban, açık renk bilek bandı
    c.inked('M428 850 C422 872 400 890 398 906 C398 924 430 926 462 924 C490 924 510 920 510 904 C510 886 504 870 502 850 Z', c.flat(dark));
    c.line('M400 916 C430 928 490 926 510 912', const Color(0xFFD9B36A), 8);
    c.line('M430 856 L500 856', const Color(0xFFD9B36A), 9);
    c.line('M440 876 l34 -4 M436 892 l40 -4', const Color(0xFFE84A3A), 5);
  });

  // Kollar: turuncu kol, koyu kahverengi el. Dürbün tutarken başın ve dürbünün önünde çizilir.
  void arms() => _limbs(c, sp, 436, 608, 388, 746, () {
        c.inkTube(Path()..moveTo(436, 608)..lineTo(402, 700), fur, 44);
        c.inkTube(Path()..moveTo(404, 694)..lineTo(388, 742), dark, 44);
      });
  final armsInFront = bino > 0.02;
  if (!armsInFront) arms();

  // Fular: düğümler ve öndeki üçgen
  c.art(sp, () {
    for (final d in const [_tarcinScarf1, _tarcinScarf2, _tarcinScarf3, _tarcinScarf0]) {
      c.inked(d, c.flat(teal));
    }
  });

  _headGroup(c, sp, 523, 545, () {
    c.canvas.drawPath(_path(_tarcinHead), _tOrange);
    c.clipped(_tarcinHead, () {
      c.shape(_tarcinFace, white);
      // Göz yuvaları: hedef çizimden izlenen beyaz bölge gözlerin alt kenarını da sarıyor; gözler kapanınca orada
      // beyaz çizgi kalmasın diye gözün yeri başın kendi renk geçişiyle boyanır
      for (final x in const [438.0, 607.0]) {
        c.canvas.drawOval(Rect.fromCenter(center: Offset(x, 384), width: 100, height: 112), _tOrange);
      }
      // Kulakların koyu kenarı ve beyaz içi
      c.line(_tarcinEar0, dark, 34);
      c.line(_tarcinEar2, dark, 34);
      for (final d in const [_tarcinEar0, _tarcinEar1, _tarcinEar2]) {
        c.shape(d, white);
      }
      c.line(_tarcinEar1, _inkNow, 5);
      // Hedef çizimde sağ kulağın iç tüyü ayrı bir bölge değil: soldaki, başın eksenine göre aynalanır
      c.canvas.save();
      c.canvas.translate(1033, 0);
      c.canvas.scale(-1, 1);
      c.shape(_tarcinEar1, white);
      c.line(_tarcinEar1, _inkNow, 5);
      c.canvas.restore();
      c.cheeks(384, 664, 452, 34, 20);
    });
    c.line(_tarcinHead, _inkNow, 7);
    c.brows(436, 608, 316, 58, w: 6);
    for (final (x, lid) in [(438.0, p.lidL), (607.0, p.lidR)]) {
      c.canvas.save();
      c.canvas.translate(x, 384);
      c.canvas.scale(1, 1.14);
      c.bigEye(0, 0, lid, size: 44, iris: const Color(0xFF7CCB3E), irisDark: const Color(0xFF3F8F22), lidColor: fur, pupilColor: const Color(0xFF2E3B14), pupilDark: const Color(0xFF151C08));
      c.canvas.restore();
    }
    c.inkOval(525, 452, 17, 12, c.flat(const Color(0xFF2A1810)), w: 3);
    c.grin(525, 474, 124);
  });

  // Dürbün: elde tutulan bir eşyadır. Göğüs hizasından göze kaldırılır, sonunda yine indirilir; göz hizasındayken
  // öndeki büyük camlardan gözleri büyümüş görünür.
  if (bino > 0.02) {
    const body = Color(0xFF2B2E36), band = Color(0xFF4A5060), rimColor = Color(0xFF79808F);
    // Dürbün sağ eldedir ve elle birlikte hareket eder (kollarla aynı hesap): kol aşağıdayken elin altında sarkar,
    // kol kalktıkça yüzün önüne gelir. Hareketin başında elde büyüyerek belirir, sonunda yana inerken elde küçülerek kaybolur.
    final theta = p.armR * 1.5 + math.atan2(436 - 388.0, 746 - 608.0);
    final hand = Offset(2 * 523 - (436 - math.sin(theta) * 146.1), 608 + math.cos(theta) * 146.1);
    final u = (p.armR / 1.575).clamp(0.0, 1.0), atEyes = ((u - 0.85) / 0.15).clamp(0.0, 1.0);
    final at = hand + Offset.lerp(const Offset(0, 36), const Offset(-150, -78), u)!;
    const y = 398.0;
    c.art(sp, () {
      c.canvas.save();
      c.canvas.translate(p.headX / sp.k * atEyes, p.headY / sp.k * atEyes);
      c.canvas.translate(hand.dx, hand.dy);
      c.canvas.scale(bino);
      c.canvas.translate(-hand.dx, -hand.dy);
      c.canvas.translate(at.dx - 523, at.dy - y);
      // Köprü ve netlik tekeri
      c.inked('M476 ${y - 70} L570 ${y - 70} L566 ${y + 22} L480 ${y + 22} Z', c.flat(body));
      c.inked('M500 ${y - 96} L546 ${y - 96} L546 ${y - 54} L500 ${y - 54} Z', c.flat(band), w: 5);
      c.line('M511 ${y - 92} V${y - 58} M523 ${y - 92} V${y - 58} M535 ${y - 92} V${y - 58}', body, 4);
      for (final (x, lid) in [(430.0, p.lidL), (616.0, p.lidR)]) {
        // Gövde: arkadaki dar göz merceğinden öndeki geniş cama doğru genişleyen silindir
        final back = Offset(x + (523 - x) * 0.22, y - 78), front = Offset(x, y);
        for (final ink in [true, false]) {
          for (var i = 0; i <= 6; i++) {
            final at = Offset.lerp(back, front, i / 6)!, r = 52 + (92 - 52) * i / 6;
            c.canvas.drawCircle(at, ink ? r + 4 : r, c.flat(ink ? _inkNow : body));
          }
        }
        final mid = Offset.lerp(back, front, 0.4)!;
        c.stroke(Path()..addArc(Rect.fromCircle(center: mid, radius: 66), math.pi * 1.1, math.pi * 0.8), band, 13);
        c.stroke(Path()..addOval(Rect.fromCircle(center: front, radius: 84)), rimColor, 9);
        final glass = Path()..addOval(Rect.fromCircle(center: front, radius: 72));
        c.canvas.drawPath(
            glass, Paint()..shader = Gradient.linear(front.translate(-50, -60), front.translate(50, 60), const [Color(0xFFE6F7FF), Color(0xFF8FC7E8), Color(0xFF4F8FBF)], const [0, 0.55, 1]));
        if (atEyes > 0.5) {
          c.canvas.save();
          c.canvas.clipPath(glass);
          c.canvas.translate(front.dx, front.dy + 3);
          c.canvas.scale(1, 1.08);
          c.bigEye(0, 0, lid, size: 62, iris: const Color(0xFF7CCB3E), irisDark: const Color(0xFF3F8F22), lidColor: fur, pupilColor: const Color(0xFF2E3B14), pupilDark: const Color(0xFF151C08));
          c.canvas.restore();
        }
        c.stroke(glass, _inkNow, 5);
        c.stroke(Path()..addArc(Rect.fromCircle(center: front, radius: 61), 3.45, 0.9), const Color(0xDDFFFFFF), 7);
        c.stroke(Path()..addArc(Rect.fromCircle(center: front, radius: 61), 0.5, 0.35), const Color(0x99FFFFFF), 5);
      }
      c.canvas.restore();
    });
  }
  if (armsInFront) arms();
  c.held();
}

/* ---------- Zifir ---------- */

const _zifirSpace = _Space(190 / 861, 511, 932);
final _zBody = _radial(450, 300, 640, const Color(0xFF3F4184), const Color(0xFF2C2D62), const Color(0xFF1D1E48));

void _zifir(_C c) {
  final p = c.p;
  const sp = _zifirSpace;
  const feather = Color(0xFF2C2D62), deep = Color(0xFF242552), grey = Color(0xFF85858F), scarf = Color(0xFF6E33AA), scarfDark = Color(0xFF4F2180);
  _inkNow = const Color(0xFF12112A);
  c.head = sp.at(511, 330);
  c.headRx = 225 * sp.k;
  c.headTop = sp.at(511, 150).dy;
  c.behind();

  _feet(c, sp, () => c.inked(_zifirFoot, c.flat(grey), w: 6));

  c.art(sp, () => c.inked('M511 498 C376 498 330 600 330 700 C330 804 400 874 511 874 C622 874 692 804 692 700 C692 600 646 498 511 498 Z', _zBody));

  // Kanatlar. Güneş gözlüğünü takıp çıkarırken sağ kanat başın önünde çizilir.
  final shades = p.prop == Prop.sunglasses ? p.propA.clamp(0.0, 1.0) : 0.0;
  final wingFront = shades > 0.02 && p.armR > 1.3;
  void wings(int sides) => _limbs(c, sp, 380, 592, 304, 836, () {
    c.inked('M382 572 C330 590 262 650 250 730 C246 762 250 788 258 806 Q272 800 278 786 Q282 818 294 838 Q310 826 316 806 Q322 834 338 850 Q352 834 356 812 Q364 834 378 842 C404 790 416 700 410 630 C406 600 398 580 382 572 Z', c.flat(deep));
    c.line('M278 786 C272 740 280 690 300 650 M316 806 C310 756 316 706 334 664 M356 812 C352 764 356 716 370 676', const Color(0xAA494B95), 5);
    c.line('M300 640 C320 612 346 596 372 588', const Color(0x66494B95), 5);
      }, swing: 1.12, sides: sides);
  wings(wingFront ? 1 : 0);

  // Atkı: öne sarkan ucu ve boyun sargısı
  c.art(sp, () {
    c.inked(_zifirScarf1, c.flat(scarf));
    c.line('M568 644 L574 740 M598 642 L604 742 M626 640 L634 740', scarfDark, 5);
    c.inked(_zifirScarf0, c.flat(scarf));
    c.line('M334 546 C420 594 600 594 692 542', scarfDark, 5);
  });

  _headGroup(c, sp, 511, 530, () {
    c.canvas.drawPath(_path(_zifirHead), _zBody);
    c.clipped(_zifirHead, () {
      c.canvas.save();
      c.canvas.translate(560, 170);
      c.canvas.rotate(p.ear * 0.12);
      c.canvas.translate(-560, -170);
      c.shape(_zifirCrest, const Color(0xFF4A3692));
      c.line(_zifirCrest, _inkNow, 5);
      c.canvas.restore();
    });
    c.line(_zifirHead, _inkNow, 7);
    // Hayranlık (parlak taş): çatık kaşlar düzleşip kalkar, gözler ışıldar
    final adore = p.sparkle.clamp(0.0, 1.0);
    c.bigEye(410, 367, p.lidL, size: 47, iris: const Color(0xFF9A5CF0), irisDark: const Color(0xFF5C2CB0), lidColor: feather, pupilColor: const Color(0xFF2A1450), pupilDark: const Color(0xFF12082A), adore: adore);
    c.bigEye(613, 367, p.lidR, size: 47, iris: const Color(0xFF9A5CF0), irisDark: const Color(0xFF5C2CB0), lidColor: feather, pupilColor: const Color(0xFF2A1450), pupilDark: const Color(0xFF12082A), adore: adore);
    c.canvas.save();
    c.canvas.translate(0, -16 * adore);
    c.brows(408, 615, 314, 116, w: 15 - 4 * adore, base: 0.34 * (1 - 1.5 * adore), color: const Color(0xFF0B0A1C));
    c.canvas.restore();
    // Gaga: ağız açıldıkça alt yarısı iner
    final open = p.open.clamp(0.0, 1.0) * 30;
    if (open > 4) c.canvas.drawOval(Rect.fromCenter(center: Offset(514, 470 + open / 2), width: 130, height: 30 + open), c.flat(const Color(0xFF5A1E2A)));
    c.canvas.save();
    c.canvas.translate(0, open);
    c.inked(_zifirBeakLow, c.flat(const Color(0xFF6B6B76)));
    c.canvas.restore();
    c.inked(_zifirBeakUp, c.flat(grey));
    c.line('M496 398 l6 10 M532 398 l-6 10', _inkNow, 5);
  });

  // Güneş gözlüğü: küçük, yuvarlak, sapsız, aynalı camlar. Sağ kanatta büyüyerek belirir, kanatla yüze gelir
  // (propT: 0 kanatta, 1 yüzde), çıkarılınca yine kanatta küçülerek kaybolur.
  if (shades > 0.02) {
    final theta = p.armR * 1.12 + math.atan2(380 - 304.0, 836 - 592.0);
    final tip = Offset(2 * 511 - (380 - math.sin(theta) * 255.6), 592 + math.cos(theta) * 255.6);
    final w = p.propT.clamp(0.0, 1.0), worn = w * w * (3 - 2 * w);
    final face = Offset(511.5 + p.headX / sp.k, 367 + p.headY / sp.k);
    final at = Offset.lerp(tip + const Offset(-64, 6), face, worn)!;
    c.art(sp, () {
      c.canvas.translate(tip.dx, tip.dy);
      c.canvas.scale(shades);
      c.canvas.translate(-tip.dx, -tip.dy);
      c.canvas.translate(at.dx - 511.5, at.dy - 367);
      const silver = Color(0xFFC3CAD2);
      final bridge = Path()
        ..moveTo(462, 360)
        ..quadraticBezierTo(511.5, 336, 561, 360);
      c.stroke(bridge, _inkNow, 11);
      c.stroke(bridge, silver, 5);
      for (final x in const [410.0, 613.0]) {
        final lens = Rect.fromCenter(center: Offset(x, 367), width: 118, height: 112);
        c.canvas.drawOval(lens, Paint()..shader = Gradient.linear(Offset(x - 44, 318), Offset(x + 44, 420), const [Color(0xFF46564F), Color(0xFF141A1E), Color(0xFF05070A)], const [0, 0.45, 1]));
        c.stroke(Path()..addOval(lens), _inkNow, 8);
        c.stroke(Path()..addOval(lens.deflate(1)), silver, 3);
        c.line('M${x - 32} 352 L${x - 6} 326 M${x - 12} 366 L${x + 6} 348', const Color(0xB3FFFFFF), 6);
      }
    });
  }
  // Gözlüğü takarken öne uzattığı sol kanadında bir mavi, bir kırmızı hap durur; kanat uzandıkça belirir
  final pills = shades > 0.02 ? ((p.armL - 0.55) / 0.55).clamp(0.0, 1.0) : 0.0;
  if (pills > 0.02) {
    final th = p.armL * 1.12 + math.atan2(380 - 304.0, 836 - 592.0);
    final tip = Offset(380 - math.sin(th) * 255.6, 592 + math.cos(th) * 255.6);
    c.art(sp, () {
      c.canvas.translate(tip.dx, tip.dy);
      c.canvas.scale(pills * 1.45);
      c.canvas.translate(-tip.dx, -tip.dy);
      void pill(double x, double y, double turn, Color color, Color shine) {
        c.canvas.save();
        c.canvas.translate(x, y);
        c.canvas.rotate(turn);
        final capsule = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 62, height: 30), const Radius.circular(15));
        c.canvas.drawRRect(capsule, c.flat(color));
        c.stroke(Path()..addRRect(capsule), const Color(0xFF0B0A1C), 6);
        c.line('M-18 -6 h20', shine, 5);
        c.canvas.restore();
      }

      pill(tip.dx + 34, tip.dy - 44, -0.3, const Color(0xFF2F8BFF), const Color(0xFFBFE0FF));
      pill(tip.dx + 100, tip.dy - 34, 0.25, const Color(0xFFE8303A), const Color(0xFFFFC2C6));
    });
  }
  if (wingFront) wings(2);
  c.held();
}

/* ---------- Tosbi ---------- */

const _tosbiSpace = _Space(190 / 801, 522, 925);
final _oSkin = _radial(450, 220, 560, const Color(0xFFA9D068), const Color(0xFF8DBB52), const Color(0xFF6E9A3C));

void _tosbi(_C c) {
  final p = c.p;
  const sp = _tosbiSpace;
  const skin = Color(0xFF8DBB52), shell = Color(0xFF8B5A2B), shellLight = Color(0xFFD9A85A), plate = Color(0xFFF3D584), plateLine = Color(0xFFD2AC52), gold = Color(0xFFE2AA2E);
  _inkNow = const Color(0xFF2E2A14);
  final hide = p.special.clamp(0.0, 1.0); // kabuğa çekilme: baş, kollar ve bacaklar kabuğun içine girer
  final sink = hide * 24; // bacaklar içeri girince kabuk yere oturur
  c.head = sp.at(513, 318) + Offset(0, hide * 30 + sink);
  c.headRx = 222 * sp.k * (1 - hide * 0.5);
  c.headTop = sp.at(513, 130).dy + hide * 52 + sink;
  // Ninja göz bandı (propT: 0 elde, 1 yüzde). Yüze varana kadar elde taşınan küçük hâli, sonra başa bağlı hâli çizilir.
  const purple = Color(0xFF7B4FC9), purpleDark = Color(0xFF5B36A0);
  final mask = p.prop == Prop.mask ? p.propA.clamp(0.0, 1.0) : 0.0;
  final worn = mask > 0.02 ? p.propT.clamp(0.0, 1.0) : 0.0, onFace = worn >= 0.5;
  final armFront = mask > 0.02 && p.armR > 1.0;
  c.behind();
  c.canvas.save();
  c.canvas.translate(0, sink);

  _feet(c, sp, () {
    c.canvas.translate(0, -hide * 86);
    c.inked(_tosbiLeg, c.flat(skin));
    c.line('M394 902 l0 -13 M418 906 l0 -13 M442 904 l0 -13', _inkNow, 5);
  });

  // Baş: kabuğa çekilirken küçülür, aşağı iner ve karın plakasının arkasında kalır; gözleri plakanın üstünden bakar
  void head() => _headGroup(c, sp, 513, 505, () {
        if (onFace) {
          // Bandın düğümü ve arkada dalgalanan iki ucu
          final flap = wave(c.time, 0.9) * 12;
          for (final (dy, len) in const [(0.0, 150.0), (36.0, 118.0)]) {
            final tail = Path()
              ..moveTo(716, 300 + dy)
              ..quadraticBezierTo(790, 296 + dy + flap, 716 + len, 344 + dy * 1.5 - flap);
            c.stroke(tail, _inkNow, 36);
            c.stroke(tail, purple, 24);
          }
          c.inkOval(736, 314, 24, 28, c.flat(purpleDark), w: 6);
        }
        c.canvas.drawPath(_path(_tosbiHead), _oSkin);
        c.clipped(_tosbiHead, () {
          for (final (x, y, w, h) in const [(470.0, 168.0, 44.0, 26.0), (600.0, 160.0, 34.0, 20.0), (540.0, 150.0, 22.0, 14.0)]) {
            c.canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: w, height: h), c.flat(const Color(0x66B9DC7A)));
          }
          c.cheeks(352, 680, 402, 40, 24, const Color(0x55E59A6A));
          if (onFace) {
            c.shape('M270 262 C400 230 640 230 770 262 L770 368 C640 394 400 394 270 368 Z', purple);
            c.line('M270 262 C400 230 640 230 770 262 M270 368 C400 394 640 394 770 368', purpleDark, 6);
          }
        });
        c.line(_tosbiHead, _inkNow, 7);
        c.bigEye(428, 311, p.lidL, size: 42, iris: const Color(0xFF9A6634), irisDark: const Color(0xFF5A3418), lidColor: skin);
        c.bigEye(610, 313, p.lidR, size: 42, iris: const Color(0xFF9A6634), irisDark: const Color(0xFF5A3418), lidColor: skin);
        // Gözlük
        final rings = Path()
          ..addOval(Rect.fromCircle(center: const Offset(428, 311), radius: 68))
          ..addOval(Rect.fromCircle(center: const Offset(610, 313), radius: 68));
        const bars = 'M495 306 C508 292 530 292 543 306 M361 300 L316 292 M677 302 L716 294';
        c.stroke(rings, _inkNow, 21);
        c.line(bars, _inkNow, 19);
        c.stroke(rings, gold, 11);
        c.line(bars, gold, 9);
        // Beyaz, gür kaşlar
        for (final (x, y, side) in const [(428.0, 214.0, -1.0), (628.0, 208.0, 1.0)]) {
          c.canvas.save();
          c.canvas.translate(x, y - p.brow * 9);
          c.canvas.rotate(side * (p.browTilt * 0.3 - 0.16));
          c.inkOval(0, 0, 54, 23, c.flat(const Color(0xFFF6F6F0)), w: 6);
          c.line('M-30 4 q10 -12 22 -2 M-4 6 q10 -12 24 -2', const Color(0xFFCFCFC4), 4);
          c.canvas.restore();
        }
        c.grin(520, 414, 190);
      }, scale: 1 - hide * 0.5, drop: hide * 30);

  // Kabuk ve boyun (kabuğa çekilince boyun yeri kabuğun karanlık ağzı olur)
  c.art(sp, () {
    c.inkOval(540, 646, 212, 172, c.flat(shell));
    c.canvas.drawOval(Rect.fromCenter(center: const Offset(536, 644), width: 376, height: 300), c.flat(shellLight));
    c.inked('M436 470 L600 470 L606 566 L430 566 Z', c.flat(Color.lerp(skin, const Color(0xFF3A2A16), hide)!));
  });
  if (hide > 0.02) head();
  c.art(sp, () {
    const belly = 'M512 536 C440 536 384 580 382 660 C380 730 430 786 512 786 C594 786 644 730 642 660 C640 580 584 536 512 536 Z';
    c.inked(belly, c.flat(plate));
    c.clipped(belly, () => c.line('M512 530 L512 800 M380 616 C440 634 590 634 644 616 M380 706 C440 690 590 690 644 706', plateLine, 6));
  });

  // Baston sol eldedir ve elle birlikte hareket eder; yalnızca çay içerken ve kabuğa çekilirken bırakılır
  final rest = math.atan2(392 - 340.0, 712 - 592.0), reach = const Offset(340 - 392, 712 - 592).distance * sp.k;
  final shoulder = sp.at(392, 592), a = p.armL * 1.5;
  final hand = Offset(shoulder.dx - math.sin(a + rest) * reach, shoulder.dy + math.cos(a + rest) * reach);
  final cane = (1 - (p.prop == Prop.chair ? p.propA : 0.0) * 4).clamp(0.0, 1.0) * (1 - hide * 3.3).clamp(0.0, 1.0);
  if (cane > 0.02) {
    final stick = Path()
      ..moveTo(hand.dx + 8, hand.dy - 1)
      ..quadraticBezierTo(hand.dx + 1, hand.dy - 15, hand.dx - 6, hand.dy - 2)
      ..lineTo(hand.dx - 5, math.min(213.0, hand.dy + 50));
    c.canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, cane));
    c.stroke(stick, _inkNow, 6.6);
    c.stroke(stick, const Color(0xFF9A6A3A), 3.6);
    c.canvas.restore();
  }
  void arms(int sides) => _limbs(c, sp, 392, 592, 340, 712, () {
        c.canvas.translate(392, 592);
        c.canvas.scale(1 - hide * 0.9);
        c.canvas.translate(-392, -592);
        c.inkTube(Path()..moveTo(392, 592)..lineTo(346, 698), skin, 52);
        c.inkOval(340, 712, 31, 29, c.flat(skin));
      }, sides: sides);
  arms(armFront ? 1 : 0);

  if (hide <= 0.02) head();
  // Elde taşınan bant: sağ elde büyüyerek belirir, el kalktıkça yüze doğru gider
  if (mask > 0.02 && !onFace) {
    final th = p.armR * 1.5 + math.atan2(392 - 340.0, 712 - 592.0);
    final hand = Offset(2 * 522 - (392 - math.sin(th) * 130.8), 592 + math.cos(th) * 130.8);
    final f = (worn * 2).clamp(0.0, 1.0), at = Offset.lerp(hand + const Offset(-20, -34), const Offset(513, 314), f * f * (3 - 2 * f))!;
    c.art(sp, () {
      c.canvas.translate(hand.dx, hand.dy);
      c.canvas.scale(mask);
      c.canvas.translate(-hand.dx, -hand.dy);
      c.canvas.translate(at.dx, at.dy);
      c.canvas.scale(0.55 + 0.45 * f);
      final tail = Path()
        ..moveTo(180, -6)
        ..quadraticBezierTo(250, 0, 290, 40);
      c.stroke(tail, _inkNow, 34);
      c.stroke(tail, purple, 22);
      c.inked('M-230 -48 C-100 -76 100 -76 230 -48 L230 50 C100 74 -100 74 -230 50 Z', c.flat(purple), w: 6);
      c.inkOval(-96, 0, 56, 44, c.flat(const Color(0xFF2A1B4A)), w: 5);
      c.inkOval(96, 0, 56, 44, c.flat(const Color(0xFF2A1B4A)), w: 5);
    });
  }
  if (armFront) arms(2);
  c.canvas.restore();
  c.held();
}

/* ---------- Paşa ---------- */

const _pasaSpace = _Space(190 / 825, 512, 912);
final _pSkin = _radial(450, 300, 600, const Color(0xFFB0C6D2), const Color(0xFF93AFBF), const Color(0xFF7A96A7));

void _pasa(_C c) {
  final p = c.p;
  const sp = _pasaSpace;
  const skin = Color(0xFF93AFBF), pink = Color(0xFFF9B4C0), fez = Color(0xFFC9282F), nail = Color(0xFFFDFCF8);
  _inkNow = const Color(0xFF26283F);
  c.head = sp.at(514, 400);
  c.headRx = 205 * sp.k;
  c.headTop = sp.at(514, 107).dy;
  final watch = p.prop == Prop.pocketWatch ? p.propA.clamp(0.0, 1.0) : 0.0; // köstekli saat elde
  c.behind();

  // Kuyruk
  final root = sp.at(668, 786);
  c.at(root.dx, root.dy, p.tail * 0.6, () => c.art(sp, () {
        c.inkTube(Path()..moveTo(668, 790)..quadraticBezierTo(736, 800, 756, 748), skin, 12, edge: 6);
        c.inkOval(764, 730, 15, 21, c.flat(const Color(0xFF55607A)), w: 6);
      }));

  // Osmanlı beyefendisi: lacivert İstanbulin ceket, bordo yelek, altın düğmeler, köstekli saat zinciri ve pantolon
  const coat = Color(0xFF26335A), coatLight = Color(0xFF34467A), vest = Color(0xFF8C2F3F), gold = Color(0xFFE5B63E), trousers = Color(0xFF2C303C);

  // Bacaklar: gövdenin arkasında kalır; kıyafet bacakların üst kısmını örter
  _feet(c, sp, () {
    c.shape('M379 730 L379 886 C379 902 392 908 404 908 L486 908 C498 908 504 902 504 886 L504 730 Z', skin);
    c.shape('M379 730 L379 868 L504 868 L504 730 Z', trousers); // pantolon
    c.line('M379 868 L504 868', _inkNow, 5);
    c.line('M379 780 L379 886 C379 902 392 908 404 908 L486 908 C498 908 504 902 504 886 L504 780', _inkNow, 7);
    c.inked('M392 908 q12 -20 24 0 Z M424 908 q12 -20 24 0 Z M456 908 q12 -20 24 0 Z', c.flat(nail), w: 4);
  });

  c.art(sp, () {
    const torso = 'M404 586 C352 624 344 706 378 804 L646 804 C680 706 672 624 620 586 Z';
    c.inked(torso, c.flat(coat));
    c.clipped(torso, () {
      c.shape('M448 580 L576 580 L598 810 L426 810 Z', vest);
      c.shape('M470 580 L554 580 L512 650 Z', const Color(0xFFFDFCF8)); // gömlek yakası
      c.line('M448 580 L426 810 M576 580 L598 810', _inkNow, 6);
      c.line('M470 580 L512 650 L554 580', _inkNow, 5);
      c.line('M418 610 C404 680 404 740 414 800 M606 610 C620 680 620 740 610 800', coatLight, 7); // ceket yakası kıvrımı
    });
    c.line(torso, _inkNow, 7);
    for (final y in const [676.0, 722.0, 768.0]) {
      c.inkOval(512, y, 9, 9, c.flat(gold), w: 4);
    }
    if (watch <= 0.02) {
      // Saat cepteyken: zincir düğmeden cebe iner
      c.line('M512 722 C540 760 566 752 578 716', const Color(0xFF8A6A1C), 7);
      c.line('M512 722 C540 760 566 752 578 716', gold, 4);
      c.inkOval(580, 712, 8, 8, c.flat(gold), w: 3);
    }
  });

  // Kollar. Telefonla konuşurken başın ve telefonun önünde çizilir (eller ahizeyi ve mikrofonu kavrar).
  final phone = p.prop == Prop.phone ? p.propA.clamp(0.0, 1.0) : 0.0;
  // Monokl (not alırken tek gözünde): 0 yok, 0–1 sağ elde büyür, 1–2 elden göze gider, 2 gözde.
  // El monoklü taşırken sağ kol başın önünde çizilir.
  final gear = p.gear.clamp(0.0, 2.0);
  final carrying = gear > 0.02 && gear < 1.98;
  void arms([int sides = 0]) => _limbs(c, sp, 384, 634, 334, 742, () {
    c.inkTube(Path()..moveTo(384, 634)..lineTo(338, 728), skin, 62);
    // Ceket kolu ve beyaz manşet; el açıkta kalır
    c.inkTube(Path()..moveTo(384, 634)..lineTo(352, 700), coat, 62);
    c.stroke(Path()..moveTo(326, 690)..lineTo(376, 714), _inkNow, 15);
    c.stroke(Path()..moveTo(326, 690)..lineTo(376, 714), const Color(0xFFFDFCF8), 8);
    c.inked('M312 752 q10 -16 20 0 Z M334 760 q10 -16 20 0 Z', c.flat(nail), w: 4);
  }, sides: sides);
  if (phone <= 0.02) arms(carrying ? 1 : 0);

  _headGroup(c, sp, 512, 590, () {
    // Kulaklar: çırpılınca yana açılır
    for (final (ear, inner, x) in const [(_pasaEar0, _pasaEarIn0, 362.0), (_pasaEar1, _pasaEarIn1, 668.0)]) {
      c.canvas.save();
      c.canvas.translate(x, 372);
      c.canvas.scale(1 + p.ear * 0.2, 1 - p.ear * 0.04);
      c.canvas.translate(-x, -372);
      c.inked(ear, c.flat(skin));
      c.shape(inner, pink);
      c.canvas.restore();
    }
    c.inkOval(514, 410, 207, 190, _pSkin);
    // Fes ve püskülü
    c.inked(_pasaFez, c.flat(fez));
    c.line('M392 246 C450 226 584 224 642 242', const Color(0x80861A20), 6);
    c.inkTube(Path()..moveTo(628, 118)..quadraticBezierTo(690, 128, 694, 196), const Color(0xFF26283F), 5, edge: 3);
    c.inkOval(696, 212, 12, 22, c.flat(const Color(0xFF26283F)), w: 4);
    c.cheeks(356, 672, 468, 36, 22);
    c.brows(411, 613, 338, 46, w: 7);
    c.bigEye(411, 401, p.lidL, size: 44, iris: const Color(0xFF3A3F58), irisDark: const Color(0xFF141624), lidColor: skin, pupilColor: const Color(0xFF14151F), pupilDark: const Color(0xFF05060A));
    c.bigEye(613, 402, p.lidR, size: 44, iris: const Color(0xFF3A3F58), irisDark: const Color(0xFF141624), lidColor: skin, pupilColor: const Color(0xFF14151F), pupilDark: const Color(0xFF05060A));
    c.grin(584, 544, 46);
    c.inked('M448 524 C441 538 443 554 452 562 C461 552 464 536 462 526 Z', c.flat(nail), w: 5);
    // Pos bıyık: hortumun iki yanından dışa kıvrılır
    for (final side in const [-1.0, 1.0]) {
      c.canvas.save();
      c.canvas.translate(514, 0);
      c.canvas.scale(side, 1);
      c.inked('M-36 494 C-60 504 -92 500 -112 474 C-110 510 -78 526 -36 512 Z', c.flat(const Color(0xFF2E2838)), w: 5);
      c.canvas.restore();
    }
    // Hortum: iki gözün arasından çıkar, uca doğru incelir ve düz sarkar. Su püskürtme ve borazan hareketlerinde
    // kökten sert dönmez; uca doğru artan bir kıvrımla öne ve yukarı kalkar.
    final curl = p.special.clamp(0.0, 1.0) * 2.5;
    const n = 16, length = 190.0;
    final mid = <Offset>[], dirs = <Offset>[], halves = <double>[];
    var at = const Offset(514, 434);
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final a = math.pi / 2 + curl * math.pow(t, 1.3);
      mid.add(at);
      dirs.add(Offset(math.cos(a), math.sin(a)));
      halves.add(47 - 22 * t);
      at += dirs.last * (length / n);
    }
    Offset edge(int i, double side) => mid[i] + Offset(-dirs[i].dy, dirs[i].dx) * (halves[i] * side);
    final tipEnd = mid[n] + dirs[n] * (halves[n] * 1.25);
    Path outline(int from) {
      final path = Path()..moveTo(edge(from, 1).dx, edge(from, 1).dy);
      for (var i = from + 1; i <= n; i++) {
        path.lineTo(edge(i, 1).dx, edge(i, 1).dy);
      }
      // Yuvarlak uç
      path.cubicTo(edge(n, 1).dx + dirs[n].dx * halves[n] * 1.3, edge(n, 1).dy + dirs[n].dy * halves[n] * 1.3, edge(n, -1).dx + dirs[n].dx * halves[n] * 1.3,
          edge(n, -1).dy + dirs[n].dy * halves[n] * 1.3, edge(n, -1).dx, edge(n, -1).dy);
      for (var i = n - 1; i >= from; i--) {
        path.lineTo(edge(i, -1).dx, edge(i, -1).dy);
      }
      return path;
    }

    // Dolgu kökte yüzle aynı renktir ve kök çizgisizdir: hortum yüze yapıştırılmış gibi değil, yüzden çıkıyor gibi durur
    c.canvas.drawPath(outline(0)..close(), c.flat(skin));
    final belly = Path()..moveTo(mid[2].dx, mid[2].dy);
    for (var i = 3; i <= n - 1; i++) {
      belly.lineTo(mid[i].dx, mid[i].dy);
    }
    c.stroke(belly, const Color(0x80B4CAD6), 20);
    c.stroke(outline(1), _inkNow, 7);
    // Boğumlar: uca doğru hafifçe bombeli enine çizgiler
    for (final i in const [3, 6, 9, 12, 14]) {
      final l = Offset.lerp(edge(i, 1), edge(i, -1), 0.16)!, r = Offset.lerp(edge(i, 1), edge(i, -1), 0.84)!, k = mid[i] + dirs[i] * 8;
      c.stroke(Path()..moveTo(l.dx, l.dy)..quadraticBezierTo(k.dx, k.dy, r.dx, r.dy), const Color(0x6626283F), 4);
    }
    // Burun deliği
    final hole = mid[n] + dirs[n] * (halves[n] * 0.55);
    c.canvas.save();
    c.canvas.translate(hole.dx, hole.dy);
    c.canvas.rotate(math.atan2(dirs[n].dy, dirs[n].dx) - math.pi / 2);
    c.canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 22, height: 9), c.flat(const Color(0x8826283F)));
    c.canvas.restore();
    c.tip = sp.at(tipEnd.dx, tipEnd.dy);
  });
  // Monokl: altın çerçeveli tek cam; ince kordonu ceketin yakasına bağlıdır
  if (gear > 0.02) {
    final thR = p.armR * 1.5 + math.atan2(384 - 334.0, 742 - 634.0);
    final rh = Offset(2 * 512 - (384 - math.sin(thR) * 119.0), 634 + math.cos(thR) * 119.0);
    final w = (gear - 1).clamp(0.0, 1.0), worn = w * w * (3 - 2 * w);
    final eye = Offset(613 + p.headX / sp.k, 402 + p.headY / sp.k);
    final at = Offset.lerp(rh + const Offset(-10, -58), eye, worn)!;
    final grow = gear.clamp(0.0, 1.0);
    c.art(sp, () {
      final loop = at + const Offset(46, 40) * grow;
      final cord = Path()
        ..moveTo(loop.dx, loop.dy)
        ..quadraticBezierTo(loop.dx + 56, loop.dy + 130, 634, 614);
      c.stroke(cord, _inkNow, 4);
      c.canvas.translate(at.dx, at.dy);
      c.canvas.scale(grow);
      final ring = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 60));
      c.canvas.drawPath(ring, c.flat(const Color(0x1CFFFFFF)));
      c.stroke(ring, _inkNow, 13);
      c.stroke(ring, gold, 7);
      c.stroke(Path()..addArc(Rect.fromCircle(center: Offset.zero, radius: 47), 3.5, 0.8), const Color(0xCCFFFFFF), 6);
      c.inkOval(46, 40, 8, 8, c.flat(gold), w: 4);
    });
  }
  if (carrying) arms(2);

  // Eski telefon: şamdan biçimli gövde (mikrofon) sağ elde, ayrı ahize sol elde; aralarında kordon.
  // İkisi de ellerde büyüyerek belirir ve ellerle birlikte hareket eder.
  if (phone > 0.02) {
    const black = Color(0xFF2B2B33), brass = Color(0xFFD9A93C);
    final rest = math.atan2(384 - 334.0, 742 - 634.0);
    final thL = p.armL * 1.5 + rest, thR = p.armR * 1.5 + rest;
    final lh = Offset(384 - math.sin(thL) * 119.0, 634 + math.cos(thL) * 119.0);
    final rh = Offset(2 * 512 - (384 - math.sin(thR) * 119.0), 634 + math.cos(thR) * 119.0);
    c.art(sp, () {
      // Kordon: ahizenin ucundan gövdenin tabanına sarkar
      final from = lh + const Offset(4, 26) * (phone * 1.3), to = rh + const Offset(-30, 46) * (phone * 1.3);
      final cord = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo((from.dx + to.dx) / 2, math.max(from.dy, to.dy) + 90, to.dx, to.dy);
      c.stroke(cord, _inkNow, 9);
      c.stroke(cord, const Color(0xFF5A4636), 4.5);
      // Gövde: siyah taban, pirinç direk, ahize çatalı ve ağza dönük huni mikrofon
      const brassDark = Color(0xFFA87B1E);
      c.canvas.save();
      c.canvas.translate(rh.dx, rh.dy);
      c.canvas.scale(phone * 1.3);
      c.inkOval(8, 46, 46, 15, c.flat(black));
      c.line('M-26 42 C-10 50 26 50 42 42', brass, 4);
      c.inkTube(Path()..moveTo(8, 40)..lineTo(8, -70), brass, 15);
      c.line('M1 -8 h14 M1 -44 h14', brassDark, 3.5);
      c.line('M2 -30 H-26 V-48', _inkNow, 11);
      c.line('M2 -30 H-26 V-48', brass, 5);
      c.inkOval(8, -72, 13, 8, c.flat(black), w: 5);
      c.canvas.save();
      c.canvas.translate(10, -78);
      c.canvas.rotate(-0.62);
      c.inked('M0 -8 L34 -18 L34 18 L0 8 Z', c.flat(black));
      c.inkOval(34, 0, 8, 18, c.flat(const Color(0xFF15151B)), w: 5);
      c.stroke(Path()..addOval(Rect.fromCenter(center: const Offset(34, 0), width: 11, height: 30)), brass, 3);
      c.canvas.restore();
      c.canvas.restore();
      // Ahize: pirinç bilezikli sap ve kulağa dayanan geniş başlık
      c.canvas.save();
      c.canvas.translate(lh.dx, lh.dy);
      c.canvas.scale(phone * 1.3);
      c.inkTube(Path()..moveTo(3, 20)..lineTo(-24, -66), black, 20);
      c.line('M-20 -30 l20 -8', brass, 5);
      c.canvas.translate(-30, -84);
      c.canvas.rotate(-0.35);
      c.inkOval(0, 0, 30, 17, c.flat(black));
      c.stroke(Path()..addOval(Rect.fromCenter(center: Offset.zero, width: 42, height: 20)), brass, 3.5);
      c.canvas.restore();
    });
    arms();
  }

  // Köstekli saat: sağ eliyle cebinden çıkarır ve yana kaldırır (propT 0→1), kapağı açılır (1→2).
  // Zinciri yeleğin düğmesine bağlıdır ve saatle birlikte uzar.
  if (watch > 0.02) {
    const r = 56.0;
    final theta = p.armR * 1.5 + math.atan2(384 - 334.0, 742 - 634.0);
    final hand = Offset(2 * 512 - (384 - math.sin(theta) * 119.0), 634 + math.cos(theta) * 119.0);
    final up = p.propT.clamp(0.0, 1.0), lid = (p.propT - 1).clamp(0.0, 1.0);
    final at = hand + Offset.lerp(const Offset(-6, -30), const Offset(6, -58), up)!;
    c.art(sp, () {
      final crown = at + Offset(0, -(r + 16) * watch);
      final chain = Path()
        ..moveTo(512, 722)
        ..quadraticBezierTo((512 + crown.dx) / 2, math.max(722.0, crown.dy) + 46, crown.dx, crown.dy);
      c.stroke(chain, const Color(0xFF8A6A1C), 7);
      c.stroke(chain, gold, 4);
      c.canvas.translate(at.dx, at.dy);
      c.canvas.scale(watch);
      // Kurma kolu ve halkası
      final ring = Path()..addOval(Rect.fromCircle(center: const Offset(0, -r - 16), radius: 9));
      c.stroke(ring, _inkNow, 7);
      c.stroke(ring, gold, 3.5);
      c.inked('M-9 -66 h18 v12 h-18 Z', c.flat(gold), w: 4);
      // Kasa ve kadran
      c.inkOval(0, 0, r, r, c.flat(gold), w: 6);
      c.canvas.drawCircle(Offset.zero, r - 10, c.flat(const Color(0xFFFFFDF5)));
      c.stroke(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 10)), const Color(0xFF8A6A1C), 3);
      for (var i = 0; i < 12; i++) {
        final d = Offset(math.sin(i * math.pi / 6), -math.cos(i * math.pi / 6));
        c.seg(d * (r - 15), d * (r - (i % 3 == 0 ? 26 : 21)), _inkNow, i % 3 == 0 ? 4 : 2.5);
      }
      c.seg(Offset.zero, const Offset(-15, -13), _inkNow, 5); // akrep
      final minute = c.time * 0.9; // yelkovan yavaşça döner
      c.seg(Offset.zero, Offset(math.sin(minute), -math.cos(minute)) * (r - 22), _inkNow, 3.5);
      c.canvas.drawCircle(Offset.zero, 4.5, c.flat(const Color(0xFFC0392B)));
      // Kapak: sol kenarından menteşeli; kapalıyken kadranı örter, açılınca yana yatar
      final open = math.cos(lid * 2.6);
      if (open.abs() > 0.04) {
        final cover = Rect.fromCenter(center: Offset(-r + r * open, 0), width: 2 * r * open.abs(), height: 2 * r);
        c.canvas.drawOval(cover, c.flat(open > 0 ? gold : const Color(0xFFF2D27A)));
        c.stroke(Path()..addOval(cover), _inkNow, 6);
        if (open > 0.3) c.stroke(Path()..addOval(cover.deflate(13 * open)), const Color(0xFF8A6A1C), 3);
      }
    });
  }
  c.held();
}

/* ---------- Sekiz ---------- */

// İlk çizimin oranları: iri baş (sahnede y 50–170), altında kısa dokunaçlar
const _sekizSpace = _Space(0.282, 515, 706);
final _sSkin = _radial(450, 240, 560, const Color(0xFFFBB6CE), const Color(0xFFF58FB3), const Color(0xFFE2709A));

void _sekiz(_C c) {
  final p = c.p;
  const sp = _sekizSpace;
  const skin = Color(0xFFF58FB3), back = Color(0xFFDD6F98), mid = Color(0xFFEC81A8), spot = Color(0xFFFFC4D8), teal = Color(0xFF5FD6C8), rim = Color(0xFF8E939B);
  _inkNow = const Color(0xFF6E2748);
  c.head = sp.at(515, 330);
  c.headRx = 220 * sp.k;
  c.headTop = sp.at(515, 124).dy;
  final on = p.prop == Prop.beaker ? p.propA.clamp(0.0, 1.0) : 0.0; // gözlük gözde, erlenmayer elde
  c.behind();

  // Dokunaçlar ilk çizimdekiyle aynıdır (sahne biriminde): uçları sürekli kıpırdar, dıştakiler kol gibi kalkar
  Path tentacle(List<double> d, List<double> u, double k, double phase) {
    double v(int i) => d[i] + (u[i] - d[i]) * k;
    final w = wave(c.time, 1.7, phase) * (3 + p.ear * 5);
    return Path()
      ..moveTo(v(0), v(1))
      ..cubicTo(v(2), v(3), v(4) + w * 0.6, v(5), v(6) + w, v(7) - w.abs() * 0.3);
  }

  void tube(Path path, Color color, double w) {
    c.stroke(path, _inkNow, w + 3.4);
    c.stroke(path, color, w);
  }

  void cups(Path path, List<double> at) {
    final metric = path.computeMetrics().first;
    for (final f in at) {
      final cup = metric.getTangentForOffset(metric.length * f)!.position;
      c.oval(cup.dx, cup.dy, 3.1, 3.1, spot);
    }
  }

  c.both((left, arm, leg) {
    // Arkada kalan dördüncü çift: adı üstünde, sekiz kol
    tube(tentacle(const [66, 150, 54, 174, 44, 190, 37, 207], const [66, 150, 52, 170, 38, 182, 28, 198], leg * 0.6, left ? 0.45 : 0.95), back, 13);
    final k = (arm / 1.6).clamp(-0.05, 1.2).toDouble();
    final outer = tentacle(const [56, 146, 40, 168, 26, 176, 20, 198], const [52, 134, 30, 126, 20, 104, 26, 80], k, left ? 0 : 0.5);
    tube(outer, mid, 15);
    cups(outer, const [0.5, 0.68, 0.86]);
    final end = outer.computeMetrics().first;
    c._hand(left, end.getTangentForOffset(end.length)!.position);
    final middle = tentacle(const [76, 158, 68, 182, 56, 192, 50, 210], const [76, 158, 60, 176, 44, 182, 34, 196], leg, left ? 0.3 : 0.8);
    tube(middle, skin, 15);
    cups(middle, const [0.55, 0.74, 0.92]);
    tube(tentacle(const [92, 162, 90, 186, 86, 198, 88, 212], const [92, 162, 90, 186, 86, 198, 88, 212], 0, left ? 0.6 : 0.1), skin, 15);
  });

  _headGroup(c, sp, 515, 540, () {
    const head = 'M515 124 C390 124 295 216 295 326 C295 446 384 550 515 550 C646 550 735 446 735 326 C735 216 640 124 515 124 Z';
    c.canvas.drawPath(_path(head), _sSkin);
    c.clipped(head, () {
      c.canvas.drawOval(Rect.fromCenter(center: const Offset(372, 300), width: 60, height: 110), c.flat(const Color(0x40FFFFFF)));
      c.cheeks(368, 664, 448, 40, 24);
    });
    c.line(head, _inkNow, 7);
    c.brows(431, 604, 330, 46, w: 6);
    c.bigEye(431, 399, p.lidL, size: 50, iris: const Color(0xFF3FCAB8), irisDark: const Color(0xFF1E8C7E), lidColor: skin, pupilColor: const Color(0xFF123A3A), pupilDark: const Color(0xFF061C1C));
    c.bigEye(604, 399, p.lidR, size: 50, iris: const Color(0xFF3FCAB8), irisDark: const Color(0xFF1E8C7E), lidColor: skin, pupilColor: const Color(0xFF123A3A), pupilDark: const Color(0xFF061C1C));
    // Kirpikler
    c.line('M386 372 L370 360 M380 392 L362 388 M649 372 L665 360 M655 392 L673 388', _inkNow, 6);
    c.grin(517, 474, 96, rest: 0.5);
    // Yüzücü gözlüğü: alında durur; deney incelerken gözlerinin üstüne iner (camı saydamlaşır, gözler görünür)
    final y = 208 + 191 * on, bend = 34 * (1 - on);
    final strap = Path()
      ..moveTo(270, y + 60 + bend)
      ..quadraticBezierTo(330, y + 6, 380, y + 2)
      ..moveTo(760, y + 60 + bend)
      ..quadraticBezierTo(700, y + 6, 650, y + 2)
      ..moveTo(484, y - 4)
      ..lineTo(550, y - 4);
    c.clipped(head, () {
      c.stroke(strap, _inkNow, 26);
      c.stroke(strap, rim, 14);
    });
    for (final (x0, x1, a) in const [(417.0, 431.0, -0.10), (618.0, 604.0, 0.08)]) {
      c.canvas.save();
      c.canvas.translate(x0 + (x1 - x0) * on, y);
      c.canvas.rotate(a * (1 - on));
      // Çerçeve halka olarak çizilir: cam saydamlaşınca arkasındaki göz görünür
      final ring = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: 129, height: 93 + 16 * on));
      c.stroke(ring, _inkNow, 26);
      c.stroke(ring, rim, 13);
      c.inkOval(0, 0, 56, 39 + 8 * on, c.flat(teal.withValues(alpha: 1 - 0.66 * on)), w: 5);
      c.line('M-34 -10 L-10 -22 M-26 8 L8 -14', const Color(0xCCFFFFFF), 7);
      c.canvas.restore();
    }
  });

  // Erlenmayer: sağ koldaki dokunaçla göz hizasında tutulur; içindeki sıvı kabarcıklanır
  if (on > 0.02) {
    final h = c.handR;
    c.at(h.dx, h.dy, 0.1, () {
      final x = h.dx + 1, top = h.dy - 37.0, neck = top + 11, base = h.dy - 6.0, bottom = h.dy - 2.0;
      // Dar boyun, aşağı doğru genişleyen konik gövde
      final glass = Path()
        ..moveTo(x - 3.6, top)
        ..lineTo(x - 3.6, neck)
        ..lineTo(x - 13.5, base)
        ..quadraticBezierTo(x - 15, bottom, x - 10.5, bottom)
        ..lineTo(x + 10.5, bottom)
        ..quadraticBezierTo(x + 15, bottom, x + 13.5, base)
        ..lineTo(x + 3.6, neck)
        ..lineTo(x + 3.6, top);
      final level = base - 11, half = 3.6 + 9.9 * (level - neck) / (base - neck);
      final liquid = Path()
        ..moveTo(x - half, level)
        ..lineTo(x - 13.5, base)
        ..quadraticBezierTo(x - 15, bottom, x - 10.5, bottom)
        ..lineTo(x + 10.5, bottom)
        ..quadraticBezierTo(x + 15, bottom, x + 13.5, base)
        ..lineTo(x + half, level)
        ..close();
      c.fill(Path.from(glass)..close(), const Color(0x66FFFFFF));
      c.fill(liquid, const Color(0xFF6FDC8C));
      c.seg(Offset(x - half + 1, level), Offset(x + half - 1, level), const Color(0xFFB8F2C6), 1.4);
      // Kabarcıklar sıvıdan boyna doğru yükselir, ağızdan çıkıp kaybolur
      for (final (dx, phase) in const [(-4.0, 0.0), (2.0, 0.4), (5.0, 0.75)]) {
        final k = (p.propT + phase) % 1;
        c.oval(x + dx * (1 - k), bottom - 4 - k * 38, 1.5 + k * 1.1, 1.5 + k * 1.1, Color.fromRGBO(255, 255, 255, 0.9 * (1 - k * 0.8)));
      }
      c.stroke(glass, _inkNow, 2.4);
      c.seg(Offset(x - 5.6, top), Offset(x + 5.6, top), _inkNow, 2.8);
      c.line('M${x + 4} ${base - 4} h4 M${x + 2} ${base - 9} h4', const Color(0x996E2748), 1.3);
      // Dokunacın ucu şişenin boynunu sarar
      c.oval(h.dx - 3, h.dy - 22, 6.0, 4.6, _inkNow);
      c.oval(h.dx - 3, h.dy - 22, 4.4, 3.0, mid);
    }, sx: on * 1.3, sy: on * 1.3);
  }
  // Mikroskop: sağ önünde yerde durur; göz merceği, eğilen başın sağ gözüne denk gelir
  final scope = p.prop == Prop.microscope ? p.propA.clamp(0.0, 1.0) : 0.0;
  if (scope > 0.02) {
    const bx = 157.0, by = 212.0, body = Color(0xFF3B3F4A), metal = Color(0xFF9AA0A9);
    c.at(bx, by, 0, () {
      void bar(Offset a, Offset b, Color color, double w) {
        c.seg(a, b, _inkNow, w + 2.8);
        c.seg(a, b, color, w);
      }

      bar(const Offset(bx - 16, by - 3), const Offset(bx + 16, by - 3), body, 5.5); // taban
      final arm = Path()
        ..moveTo(bx + 11, by - 5)
        ..cubicTo(bx + 21, by - 30, bx + 15, by - 58, bx - 5, by - 63);
      c.stroke(arm, _inkNow, 8.8);
      c.stroke(arm, body, 6);
      bar(const Offset(bx - 17, by - 27), const Offset(bx + 8, by - 27), metal, 3.6); // tabla
      c.seg(const Offset(bx - 11, by - 30), const Offset(bx - 1, by - 30), const Color(0xFF9BE3F2), 2.2); // lam
      const lens = Offset(bx - 6, by - 34), eye = Offset(bx - 20, by - 78);
      bar(lens, eye, body, 8.6); // tüp
      bar(lens, Offset.lerp(lens, eye, 0.16)!, metal, 6.4); // objektif
      bar(Offset.lerp(lens, eye, 0.84)!, eye, metal, 10); // göz merceği
      c.oval(bx + 13, by - 42, 5.8, 5.8, _inkNow); // netlik düğmesi
      c.oval(bx + 13, by - 42, 4.3, 4.3, metal);
      c.seg(const Offset(bx + 11, by - 42), const Offset(bx + 15, by - 42), body, 1.4);
    }, sx: scope, sy: scope);
  }
  c.held();
}

/* ---------- Dalga ---------- */

const _dalgaSpace = _Space(190 / 820, 515, 915);
final _dBlue = _radial(450, 240, 620, const Color(0xFF86C2F0), const Color(0xFF5CA2DE), const Color(0xFF3F82C4));

void _dalga(_C c) {
  final p = c.p;
  const sp = _dalgaSpace;
  const blue = Color(0xFF5CA2DE), deep = Color(0xFF4A8CD0), white = Color(0xFFFDFEFF), band = Color(0xFFE63B47);
  _inkNow = const Color(0xFF1C2850);
  c.head = sp.at(515, 330);
  c.headRx = 205 * sp.k;
  c.headTop = sp.at(515, 150).dy;
  c.behind();

  // Kuyruk yüzgeci
  final root = sp.at(515, 806);
  c.at(root.dx, root.dy, p.tail * 0.45, () => c.art(sp, () => c.inked(_dalgaTail, c.flat(deep))));

  c.art(sp, () {
    c.canvas.drawPath(_path(_dalgaBody), _dBlue);
    // Jimnastik kıyafeti: saç bandıyla aynı kırmızıda atlet, lacivert şort
    c.clipped(_dalgaBody, () {
      c.shape(_dalgaBelly, white);
      c.shape('M330 480 H700 V694 H330 Z', band);
      c.line('M330 606 H700 M330 630 H700', white, 9);
      c.shape('M330 694 H700 V776 H330 Z', const Color(0xFF223E72));
      c.line('M330 694 H700', white, 9);
      c.line('M330 776 H700', _inkNow, 5);
      c.line('M432 700 V776 M598 700 V776', white, 7);
    });
    c.line(_dalgaBody, _inkNow, 7);
  });

  // Yüzgeçler
  _limbs(c, sp, 392, 560, 318, 674, () {
    c.canvas.translate(392, 560);
    c.canvas.scale(1.25);
    c.canvas.translate(-392, -560);
    c.inked(_dalgaFlipper, c.flat(deep));
    // Bileklik (ter bandı)
    c.clipped(_dalgaFlipper, () {
      c.line('M326 618 L384 648', _inkNow, 24);
      c.line('M326 618 L384 648', white, 16);
      c.line('M326 618 L384 648', band, 5);
    });
  });

  void face() {
    c.canvas.drawPath(_path(_dalgaHead), _dBlue);
    c.clipped(_dalgaHead, () {
      c.shape(_dalgaFace, white);
      c.cheeks(384, 664, 430, 38, 22);
    });
    c.line(_dalgaHead, _inkNow, 7);
    // Spor bandı: alında, düğümü yanda
    c.inked(_dalgaKnot0, c.flat(band));
    c.inked(_dalgaKnot1, c.flat(band));
    c.inked(_dalgaBand, c.flat(band));
    c.bigEye(408, 350, p.lidL, size: 46, iris: const Color(0xFF34457A), irisDark: const Color(0xFF141C3C), lidColor: blue, pupilColor: const Color(0xFF141C3C), pupilDark: const Color(0xFF070B1C));
    c.bigEye(602, 350, p.lidR, size: 46, iris: const Color(0xFF34457A), irisDark: const Color(0xFF141C3C), lidColor: blue, pupilColor: const Color(0xFF141C3C), pupilDark: const Color(0xFF070B1C));
    c.stroke(Path()..moveTo(486, 398)..quadraticBezierTo(512, 380, 538, 398), _inkNow, 6);
    c.grin(516, 436, 150, rest: 0.55);
  }

  // Yüzgeçler kısa, baş iri: halter baş hizasına kalkınca başın arkasından geçer, yüzü kapatmaz
  final behindHead = p.prop == Prop.barbell && math.min(c.handL.dy, c.handR.dy) < sp.at(515, 500).dy;
  if (behindHead) c.held();
  _headGroup(c, sp, 515, 520, face);
  if (!behindHead) c.held();
}
