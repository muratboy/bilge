// Grafikler: veri doğrulaması, fonksiyon çözümleyici ve (BILGE_SHOTS verilirse) çizimlerin görüntüsü.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilge/core/expr.dart';
import 'package:bilge/core/schema.dart';
import 'package:bilge/ui/chart.dart';
import 'package:bilge/ui/theme.dart';
import 'package:bilge/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic>? chartOf(String chartJson) {
  final r = parseCourse('{"title":"T","units":[{"title":"U","lessons":[{"title":"L","exercises":[{"type":"info","body":"B","chart":$chartJson}]}]}]}');
  return r.course?.units.first.lessons.first.exercises.first.chart;
}

const samples = <String>[
  '{"type":"bar","title":"Gezegenlerin uydu sayısı","labels":["Dünya","Mars","Neptün","Uranüs"],"values":[1,2,16,28],"y":"Uydu"}',
  '{"type":"bar","title":"Sınav ortalamaları","labels":["1. sınav","2. sınav","3. sınav"],"series":[{"name":"A şubesi","values":[62,71,80]},{"name":"B şubesi","values":[70,68,77]}]}',
  '{"type":"line","title":"Aylık sıcaklık","labels":["Oca","Şub","Mar","Nis","May","Haz"],"values":[3,5,9,14,19,24],"y":"°C"}',
  '{"type":"line","title":"Nüfus","x":"Yıl","y":"milyon","series":[{"name":"Kent","points":[[1990,33],[2000,44],[2010,56],[2020,64]]},{"name":"Kır","points":[[1990,23],[2000,23],[2010,18],[2020,19]]}]}',
  '{"type":"function","title":"Parabol","fn":"x^2-3","from":-3,"to":3}',
  '{"type":"function","fn":["sin(x)","x/2"],"from":-6.3,"to":6.3}',
  '{"type":"pie","title":"Dünya yüzeyi","labels":["Su","Kara"],"values":[71,29]}',
  '{"type":"pie","title":"Atmosfer","labels":["Azot","Oksijen","Argon","Diğer"],"values":[78,21,0.9,0.1]}',
  '{"type":"scatter","title":"Boy ve kilo","x":"Boy (cm)","y":"kg","points":[[150,48],[158,55],[163,60],[170,66],[176,74],[182,80],[168,59]]}',
  '{"type":"function","title":"Ters orantı","fn":"1/x","from":-4,"to":4}',
];

void main() {
  test('fonksiyon çözümleyici', () {
    double? at(String f, double x) => parseFunction(f)?.call(x);
    expect(at('x^2-3', 2), 1);
    expect(at('2x+1', 3), 7);
    expect(at('-x^2', 3), -9);
    expect(at('3(x+1)(x-1)', 2), 9);
    expect(at('2^3^2', 0), 512);
    expect(at('y = 0,5x', 4), 2);
    expect(at('sin(x)/x', 0)!.isNaN, isTrue);
    expect(at('sqrt(x)+|x-5|', 4), 3);
    expect(at('2pi', 0), closeTo(6.2832, 1e-4));
    expect(at('x² − 3·x', 5), 10);
    expect(at('√x', 9), 3);
    expect(at('ln(e)+log(100)+exp(0)', 1), closeTo(4, 1e-9));
    for (final bad in ['', 'x+', 'system(1)', 'x^', '2y', 'a.b', '(x', 'x)', 'x x x'.padRight(90, 'x')]) {
      expect(parseFunction(bad), isNull, reason: bad);
    }
  });

  test('grafik verisi: farklı yazımlar tek biçime gelir, bozuk grafik adımı atlatır', () {
    for (final s in samples) {
      expect(chartOf(s), isNotNull, reason: s);
    }
    expect(chartOf('{"type":"bar","data":[["Pzt",5],["Sal",8]]}'), containsPair('labels', ['Pzt', 'Sal']));
    expect(chartOf('{"labels":["a","b"],"values":[1,2]}')!['type'], 'bar');
    expect(chartOf('{"fn":"2x"}'), allOf(containsPair('type', 'function'), containsPair('from', -5), containsPair('to', 5)));
    expect(chartOf('{"type":"column","series":{"A":[1,2],"B":[3,4]},"labels":["x","y"]}')!['series'], hasLength(2));
    expect(chartOf('{"type":"line","points":[[2,5],[1,3]]}')!['series'][0]['points'], [[1, 3], [2, 5]], reason: 'noktalar x sırasına dizilir');
    // Dördüncü seri alınmaz
    expect(chartOf('{"type":"line","labels":["a","b"],"series":[{"values":[1,2]},{"values":[2,3]},{"values":[3,4]},{"values":[4,5]}]}')!['series'], hasLength(3));
    // Çizilemeyenler
    for (final bad in [
      '{"type":"bar","labels":["a","b"],"values":[1]}',
      '{"type":"bar","labels":["a"],"values":[1]}',
      '{"type":"pie","labels":["a","b"],"values":[1,-1]}',
      '{"type":"pie","labels":["a","b","c","d","e","f","g"],"values":[1,1,1,1,1,1,1]}',
      '{"type":"function","fn":"rm -rf"}',
      '{"type":"function","fn":"x","from":3,"to":1}',
      '{"type":"function","fn":"sqrt(x)","from":-9,"to":-1}',
      '{"type":"scatter","labels":["a","b"],"values":[1,2]}',
      '{"type":"radar","values":[1,2]}',
      '{"type":"bar","values":["bir","iki"]}',
      '"grafik"',
    ]) {
      expect(chartOf(bad), isNull, reason: bad);
    }
    final r = parseCourse('{"title":"T","units":[{"title":"U","lessons":[{"title":"L","exercises":[{"type":"info","body":"B"},{"type":"info","body":"B","chart":{"type":"bar","values":[1]}}]}]}]}');
    expect(r.warnings.single, contains('grafikte 2 ile 12 arasında değer olmalı'));
  });

  test('ölçek yuvarlak aralıklar verir', () {
    expect(niceScale(0, 28).ticks, [0, 10, 20, 30]);
    expect(niceScale(3, 24).ticks, [0, 10, 20, 30]);
    expect(niceScale(0, 19).ticks, [0, 5, 10, 15, 20]);
    expect(niceScale(-3, 6).ticks, [-5, 0, 5, 10]);
    expect(niceScale(0, 0.9).decimals, 1);
    expect(niceScale(5, 5).ticks.length, greaterThan(1));
  });

  test('niceScale sonsuz ve NaN değerlerle çökmez, güvenli ölçek döner', () {
    final s1 = niceScale(-1e308, 1e308);
    expect(s1.ticks.every((t) => t.isFinite), isTrue);
    expect(s1.min.isFinite, isTrue);
    expect(s1.max.isFinite, isTrue);

    final s2 = niceScale(double.nan, 10);
    expect(s2.ticks.every((t) => t.isFinite), isTrue);

    final s3 = niceScale(-double.infinity, double.infinity);
    expect(s3.ticks.every((t) => t.isFinite), isTrue);

    final s4 = niceScale(double.nan, double.nan);
    expect(s4.ticks.every((t) => t.isFinite), isTrue);
  });

  // Yazı tipleri gerçek dosyadan okunur; test saatinin dışında yüklenmeli
  setUpAll(() async {
    final nunito = FontLoader('Nunito');
    for (final w in [600, 700, 800, 900]) {
      nunito.addFont(File('assets/fonts/Nunito-$w.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await nunito.load();
    final icons = File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)))).load();
  });

  testWidgets('çizim: her tür, açık ve koyu temada', (tester) async {
    final dir = Platform.environment['BILGE_SHOTS'];
    final charts = [for (final s in samples) chartOf(s)!];
    for (final (name, palette) in [('acik', Palette.light), ('koyu', Palette.night)]) {
      tester.view
        ..physicalSize = const Size(1180, 1500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: buildTheme(palette),
          home: Scaffold(
            backgroundColor: palette.bg,
            body: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final c in charts) SizedBox(width: 380, child: Panel(padding: const EdgeInsets.all(14), child: ChartView(c)))],
              ),
            ),
          ),
        ),
      ));
      expect(find.byType(ChartView), findsNWidgets(samples.length));
      expect(tester.takeException(), isNull);
      // Dokunma: değer kutusu çıkar; tablo düğmesi aynı veriyi tablo yapar
      await tester.tapAt(tester.getCenter(find.byType(ChartView).at(2)) + const Offset(30, 20));
      await tester.tapAt(tester.getCenter(find.byType(ChartView).at(4)) + const Offset(40, 20));
      await tester.tap(find.byIcon(Icons.table_rows_rounded).at(1));
      await tester.pump();
      expect(find.text('B şubesi'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      if (dir != null) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/grafikler-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }
  });
}
