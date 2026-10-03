// Uygulama simgesi. Simge ayrı bir çizim değildir: uygulamanın kendi tilki çiziminden (Tarçın, rig_vector.dart)
// üretilir; baş ve fular simgeyi doldurur. Tilkinin çizimi değişirse simge şu komutla yeniden yazılır:
//
//   BILGE_ICON=1 flutter test test/icon_test.dart
//
// Komut android/app/src/main/res/mipmap-*/ içindeki ic_launcher_foreground.png (uyarlanabilir simgenin ön katmanı,
// Android 8+) ve ic_launcher.png (Android 7 için hazır yuvarlak simge) dosyalarını yazar. Ortam değişkeni yokken
// test yalnızca bu dosyaların yerinde ve doğru boyda olduğunu denetler.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilge/mascot/actions.dart';
import 'package:bilge/mascot/mascot_art.dart';
import 'package:bilge/mascot/rig.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

/// Yoğunluk klasörü → dp başına piksel.
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// Simgenin zemini (values/ic_launcher_background.xml ile aynı olmalı): uygulamanın ana moru.
const _background = Color(0xFF7C5CFF);

// Uyarlanabilir simgenin tuvali 108 dp'dir; başlatıcı bunun ortasındaki 72 dp'yi kendi maskesiyle (daire, yumuşak
// kare…) gösterir ve her maskede görünen "güvenli alan" ortadaki 66 dp'lik dairedir.
const _canvas = 108.0, _viewport = 72.0;

// Tilki 1024 birim genişliğindeki kendi çizim uzayında çizilir (paintMascot, Size(1024, 1024 * 1.15)).
const _art = Size(1024, 1024 * 1.15);
const _headX = 512.0; // başın yatay ortası
const _earTop = 126.0; // kulak uçlarının yüksekliği
const _unit = 0.095; // çizim birimi başına dp: baş yaklaşık 56 dp genişliğinde
const _top = 30.4; // kulak uçlarının tuvaldeki yüksekliği (dp): uçlar güvenli dairenin tam içinde kalır

/// Kadraj (çizim uzayında): baş, fular ve omuzlar. Sınır, kuyrukla gövde arasındaki boşluktan geçer; kuyruk
/// simgenin köşesinde yarım bir parça olarak görünmesin diye kadrajın dışında kalır.
const _frame = <Offset>[
  Offset(0, 0), Offset(1024, 0), Offset(1024, 1178), Offset(330, 1178), Offset(330, 840), Offset(327, 820), Offset(322, 800),
  Offset(320, 780), Offset(323, 760), Offset(327, 740), Offset(326, 720), Offset(323, 700), Offset(310, 680), Offset(289, 660),
  Offset(286, 640), Offset(295, 620), Offset(270, 600), Offset(243, 580), Offset(217, 560), Offset(205, 538), Offset(0, 538),
];

/// Tilkiyi 108 dp'lik tuvale, dp başına [px] pikselle çizer.
void _paintFox(Canvas canvas, double px) {
  canvas.save();
  canvas.translate((_canvas / 2 - _headX * _unit) * px, (_top - _earTop * _unit) * px);
  canvas.scale(_unit * px);
  canvas.clipPath(Path()..addPolygon(_frame, true));
  paintMascot(canvas, _art, MascotId.tarcin, poseAt(Mood.happy, 0, idle: false), 0);
  canvas.restore();
}

/// Ön katman: saydam zeminde tilki.
ui.Picture _foreground(double px) {
  final recorder = ui.PictureRecorder();
  _paintFox(Canvas(recorder), px);
  return recorder.endRecording();
}

/// Android 7 simgesi (48 dp): mor daire içinde, uyarlanabilir simgenin görünen alanıyla aynı kadraj.
ui.Picture _legacy(double px) {
  const size = 48.0, disc = 44.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final circle = Path()..addOval(Rect.fromCircle(center: Offset(size / 2 * px, size / 2 * px), radius: disc / 2 * px));
  canvas.drawPath(circle, Paint()..color = _background);
  canvas.clipPath(circle);
  canvas.translate(size / 2 * px, size / 2 * px);
  canvas.scale(disc / _viewport);
  canvas.translate(-_canvas / 2 * px, -_canvas / 2 * px);
  _paintFox(canvas, px);
  return recorder.endRecording();
}

/// PNG dosyasının başlığındaki genişlik ve yükseklik.
(int, int) _pngSize(File file) {
  final head = ByteData.sublistView(file.readAsBytesSync(), 0, 24);
  return (head.getUint32(16), head.getUint32(20));
}

void main() {
  testWidgets('simge dosyalarını tilkinin çiziminden yeniden üretir (BILGE_ICON=1 ile)', (tester) async {
    if (Platform.environment['BILGE_ICON'] == null) return;
    for (final MapEntry(key: name, value: px) in _densities.entries) {
      for (final (file, picture, dp) in [('ic_launcher_foreground.png', _foreground(px), _canvas), ('ic_launcher.png', _legacy(px), 48.0)]) {
        await tester.runAsync(() async {
          final image = await picture.toImage((dp * px).round(), (dp * px).round());
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_res/mipmap-$name/$file').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }
  });

  test('simge dosyaları yerinde ve doğru boyda', () {
    for (final MapEntry(key: name, value: px) in _densities.entries) {
      expect(_pngSize(File('$_res/mipmap-$name/ic_launcher_foreground.png')), ((_canvas * px).round(), (_canvas * px).round()), reason: name);
      expect(_pngSize(File('$_res/mipmap-$name/ic_launcher.png')), ((48 * px).round(), (48 * px).round()), reason: name);
    }
    final adaptive = File('$_res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
    expect(adaptive, contains('@color/ic_launcher_background'));
    final hex = _background.toARGB32().toRadixString(16).substring(2).toUpperCase();
    expect(File('$_res/values/ic_launcher_background.xml').readAsStringSync().toUpperCase(), contains('#$hex'), reason: 'zemin rengi üreticideki renkle aynı olmalı');
    expect(File('$_res/drawable/ic_launcher_foreground.xml').existsSync(), isFalse, reason: 'eski düz çizimli tilki simgesi kalmamalı');
  });

  test('tilkinin kulak uçları her maskede görünen güvenli dairenin içinde', () {
    // Kulak uçları çizim uzayında yaklaşık (266, 129) ve (736, 126): tuvalin ortasına uzaklıkları 33 dp'yi aşmamalı
    for (final ear in const [Offset(266, 129), Offset(736, 126)]) {
      final at = Offset(_canvas / 2 + (ear.dx - _headX) * _unit, _top + (ear.dy - _earTop) * _unit);
      expect((at - const Offset(_canvas / 2, _canvas / 2)).distance, lessThanOrEqualTo(33.05));
    }
  });
}
