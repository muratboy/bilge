// Maskot iskeleti ve hareketleri. BILGE_SHOTS bir klasörü gösterirse, bütün karakterlerin
// ruh hâllerini ve imza hareketlerini tek bir görüntüye (maskotlar.png), her karakterin yakın planını da
// ayrı bir görüntüye (yakin-<ad>.png), her karakterin her ruh hâlini de beyaz zeminde tek tek (tek-<ad>-<ruh hâli>.png) döker.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilge/mascot/actions.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/mascot/pose.dart';
import 'package:bilge/mascot/rig.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<double> _numbers(Pose p) => [
      p.y, p.dx, p.rot, p.lean, p.squash, p.headTilt, p.headX, p.headY, p.lookX, p.lookY, p.lidL, p.lidR, p.wide, p.joy, p.brow, p.browTilt,
      p.smile, p.open, p.round, p.armL, p.armR, p.legL, p.legR, p.tail, p.ear, p.special, p.propT, p.propA, p.zzz, p.notes, p.sweat, p.sparkle, p.tear,
    ];

void main() {
  test('her karakterin en az 3 imza hareketi var; adları benzersiz', () {
    for (final id in MascotId.values) {
      final own = signatures[id]!;
      expect(own.length, greaterThanOrEqualTo(3), reason: id.name);
      expect(own.map((c) => c.name).toSet().length, own.length);
      expect(own.where((c) => !c.wide).length, greaterThanOrEqualTo(1), reason: 'dar yerde de oynayacak bir hareket olmalı');
    }
  });

  test('bütün hareketler nötr başlar, nötr biter ve her anında çizilebilir', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final id in MascotId.values) {
      for (final mood in Mood.values) {
        for (var s = 0.0; s < 3; s += 0.37) {
          paintMascot(canvas, const Size(120, 138), id, poseAt(mood, s, seed: 0.3), s);
        }
      }
      for (final clip in [...microGestures, ...signatures[id]!]) {
        for (final edge in [0.0, clip.seconds]) {
          final p = poseAt(Mood.happy, 0, clip: clip, clipTime: edge, idle: false);
          expect([p.y, p.dx, p.rot, p.lean, p.propA, p.zzz, p.notes, p.sweat, p.special].every((v) => v.abs() < 0.02), isTrue,
              reason: '${clip.name} ${edge == 0 ? 'başta' : 'sonda'} sıçrama yapıyor');
        }
        for (var s = 0.0; s <= clip.seconds; s += clip.seconds / 23) {
          final p = poseAt(Mood.happy, s, clip: clip, clipTime: s);
          expect(_numbers(p).every((v) => v.isFinite), isTrue, reason: '${clip.name} @ $s');
          paintMascot(canvas, const Size(120, 138), id, p, s);
        }
      }
    }
    recorder.endRecording().dispose();
  });

  testWidgets('önizleme görüntüsü', (tester) async {
    final dir = Platform.environment['BILGE_SHOTS'];
    if (dir == null) return;
    const w = 150.0, h = 172.0;
    final columns = <(String, Pose Function(MascotId))>[
      for (final m in Mood.values) (m.name, (id) => poseAt(m, 0.4, seed: 0.2)),
      for (var i = 0; i < 3; i++)
        for (final f in [0.3, 0.72])
          ('imza ${i + 1}', (id) {
            final clip = signatures[id]![i];
            return poseAt(Mood.happy, clip.seconds * f, clip: clip, clipTime: clip.seconds * f);
          }),
    ];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, w * columns.length, h * MascotId.values.length), Paint()..color = const Color(0xFFF7F4FB));
    for (final (row, id) in MascotId.values.indexed) {
      for (final (col, (_, pose)) in columns.indexed) {
        canvas.save();
        canvas.translate(col * w + 25, row * h + 46);
        paintMascot(canvas, const Size(100, 115), id, pose(id), 1.3);
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage((w * columns.length).round(), (h * MascotId.values.length).round());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/maskotlar.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // Çizim ayrıntılarını görmek için büyük boy
    final big = ui.PictureRecorder();
    final bc = Canvas(big);
    bc.drawRect(const Rect.fromLTWH(0, 0, 1040, 640), Paint()..color = const Color(0xFFF7F4FB));
    for (final (i, id) in MascotId.values.indexed) {
      bc.save();
      bc.translate(20.0 + (i % 4) * 260, 30.0 + (i ~/ 4) * 310);
      paintMascot(bc, const Size(220, 253), id, poseAt(Mood.happy, 0.4, seed: 0.2), 1.3);
      bc.restore();
    }
    // Yakın plan: her karakter açık zeminde (mutlu, şaşkın) ve koyu zeminde (sevinçli)
    for (final id in MascotId.values) {
      final close = ui.PictureRecorder();
      final cc = Canvas(close);
      cc.drawRect(const Rect.fromLTWH(0, 0, 800, 450), Paint()..color = const Color(0xFFF7F4FB));
      cc.drawRect(const Rect.fromLTWH(800, 0, 400, 450), Paint()..color = const Color(0xFF17132B));
      for (final (i, mood) in const [Mood.happy, Mood.wow, Mood.cheer].indexed) {
        cc.save();
        cc.translate(25.0 + i * 400, 20);
        paintMascot(cc, const Size(350, 402), id, poseAt(mood, 0.4, seed: 0.2), 1.3);
        cc.restore();
      }
      final closePicture = close.endRecording();
      await tester.runAsync(() async {
        final image = await closePicture.toImage(1200, 450);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/yakin-${id.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    // Tek karakter, beyaz zeminde büyük boy (tek-<ad>-<ruh hâli>.png): dış araçlara (çizim, yapay zekâ) referans için
    for (final id in MascotId.values) {
      for (final mood in Mood.values) {
        final one = ui.PictureRecorder();
        final oc = Canvas(one);
        oc.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = const Color(0xFFFFFFFF));
        oc.translate(172, 120);
        paintMascot(oc, const Size(680, 782), id, poseAt(mood, 0.4, seed: 0.2), 1.3);
        final onePicture = one.endRecording();
        await tester.runAsync(() async {
          final image = await onePicture.toImage(1024, 1024);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/tek-${id.name}-${mood.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }

    // Karakterin kendi çizim uzayında, kıpırtısız duruşu (art-<ad>.png): hedef görselle üst üste karşılaştırmak için
    for (final id in MascotId.values) {
      final art = ui.PictureRecorder();
      final ac = Canvas(art);
      ac.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = const Color(0xFFFFFFFF));
      paintMascotArt(ac, id, poseAt(Mood.happy, 0, idle: false));
      final artPicture = art.endRecording();
      await tester.runAsync(() async {
        final image = await artPicture.toImage(1024, 1024);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/art-${id.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    final bigPicture = big.endRecording();
    await tester.runAsync(() async {
      final image = await bigPicture.toImage(1040, 640);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/maskotlar-buyuk.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
