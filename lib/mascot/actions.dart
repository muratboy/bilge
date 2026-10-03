/// Maskotların hareketleri: ruh hâli duruşları, sürekli kıpırtılar, küçük jestler ve
/// her karakterin kişiliğini yansıtan imza hareketleri.
library;

import 'dart:math' as math;

import 'mascot_art.dart';
import 'pose.dart';

/// Belirli bir süre oynayan hareket. [apply], duruşu hareketin o anına göre değiştirir.
class Clip {
  const Clip(this.name, this.seconds, this.apply, {this.wide = false});
  final String name;
  final double seconds;

  /// t: hareketin 0…1 arasındaki ilerlemesi; s: başlangıçtan beri geçen saniye.
  final void Function(Pose p, double t, double s) apply;

  /// Çevresinde yer ister (yatma, koltuk); dar yerlerde oynatılmaz.
  final bool wide;
}

double _up(double v) => v > 0 ? v : 0;

/* ---------- Ruh hâli ve sürekli kıpırtı ---------- */

void applyMood(Pose p, Mood mood, double s) {
  switch (mood) {
    case Mood.happy:
      break;
    case Mood.cheer:
      final hop = wave(s, 0.62).abs();
      p
        ..joy = 1
        ..smile = 1
        ..open = 0.75
        ..y = hop * 12
        ..squash = 0.5 - hop * 1.1
        ..arms = 1.75 + wave(s, 0.31) * 0.12
        ..tail = wave(s, 0.4) * 0.8
        ..ear = 0.4;
    case Mood.sad:
      p
        ..smile = -0.8
        ..browTilt = 0.9
        ..brow = -0.2
        ..lids = 0.2
        ..lookY = 0.5
        ..headY = 5
        ..headTilt = 0.06 + wave(s, 4) * 0.02
        ..squash = 0.5
        ..tear = 1
        ..ear = -0.5
        ..tail = -0.3;
    case Mood.think:
      p
        ..lookX = 0.65
        ..lookY = -0.6
        ..brow = 0.7
        ..smile = 0.15
        ..armR = -1.55
        ..headTilt = -0.1 + wave(s, 3) * 0.02;
    case Mood.wow:
      p
        ..wide = 1
        ..brow = 1
        ..round = 1
        ..open = 0.5
        ..arms = 0.55
        ..ear = 0.6;
  }
}

/// Nefes alma ve hafif salınım: maskot hiçbir şey yapmazken bile canlı durur.
void applyIdle(Pose p, double s, double seed) {
  p
    ..squash += wave(s, 3.2, seed) * 0.2
    ..headY += wave(s, 3.2, seed + 0.12) * 1.2
    ..tail += wave(s, 2.7, seed) * 0.14
    ..ear += wave(s, 4.3, seed) * 0.06
    ..armL += wave(s, 3.2, seed + 0.2) * 0.04
    ..armR += wave(s, 3.2, seed + 0.3) * 0.04;
}

/* ---------- Küçük jestler: bütün karakterler yapar ---------- */

final microGestures = <Clip>[
  Clip('look', 2.8, (p, t, s) {
    p
      ..lookX = kf(t, [0, 1, 1, 0, -1, -1, 0])
      ..headX += kf(t, [0, 3, 3, 0, -3, -3, 0])
      ..headTilt += kf(t, [0, 0.05, 0.05, 0, -0.05, -0.05, 0]);
  }),
  Clip('fidget', 1.9, (p, t, s) {
    p
      ..armL += kf(t, [0, 0.55, 0.15, 0.5, 0])
      ..armR += kf(t, [0, 0.25, 0.55, 0.2, 0])
      ..ear += kf(t, [0, 0.6, 0, 0.6, 0]);
  }),
  Clip('wag', 1.7, (p, t, s) {
    final h = hold(t, 0.2);
    p
      ..tail += math.sin(t * math.pi * 6) * h * 0.9
      ..ear += wave(s, 0.4).abs() * h * 0.7
      ..lean += math.sin(t * math.pi * 6) * h * 0.02;
  }),
  Clip('shift', 2.6, (p, t, s) {
    p
      ..lean += kf(t, [0, 0.06, 0.06, -0.06, -0.06, 0])
      ..legR += kf(t, [0, 0.7, 0.7, 0, 0, 0])
      ..legL += kf(t, [0, 0, 0, 0.7, 0.7, 0])
      ..lookX = kf(t, [0, -0.4, -0.4, 0.4, 0.4, 0]);
  }),
  Clip('tilt', 2.1, (p, t, s) {
    p
      ..headTilt += kf(t, [0, 0.17, 0.17, 0.17, 0])
      ..brow = kf(t, [0, 0.8, 0.8, 0.8, 0])
      ..lookX = kf(t, [0, -0.5, -0.5, -0.5, 0])
      ..ear += kf(t, [0, 0.5, 0.2, 0.5, 0]);
  }),
  Clip('hop', 0.95, (p, t, s) {
    p
      ..y += math.sin(t * math.pi) * 15
      ..squash += kf(t, [0, 0.9, -0.7, -0.2, 0.8, 0])
      ..armL += kf(t, [0, 0.2, 0.8, 0.4, 0])
      ..armR += kf(t, [0, 0.2, 0.8, 0.4, 0])
      ..tail += kf(t, [0, -0.5, 0.6, 0.2, 0]);
  }),
  Clip('stretch', 3.0, (p, t, s) {
    final yawn = kf(t, [0, 1, 1, 0.4, 0]);
    p
      ..armL += kf(t, [0, 1.9, 1.9, 1.2, 0])
      ..armR += kf(t, [0, 1.8, 1.9, 1.3, 0])
      ..squash += kf(t, [0, -1.0, -1.0, -0.4, 0])
      ..lids = yawn * 0.9
      ..round = yawn > 0.5 ? 1 : 0
      ..open = yawn * 0.8
      ..headTilt += kf(t, [0, -0.08, -0.08, 0, 0]);
  }),
];

/* ---------- İmza hareketleri: karakterin kişiliğini anlatır ---------- */

final signatures = <MascotId, List<Clip>>{
  // Puhu: bilge profesör
  MascotId.puhu: [
    Clip('kitap okur', 8.5, (p, t, s) {
      final h = hold(t);
      p
        ..prop = Prop.book
        ..propA = h
        ..propT = (s / 2.8) % 1
        ..arms = -0.42 * h
        ..headY += 5 * h
        ..lookY = 0.85 * h
        ..lookX = wave(s, 1.4) * 0.6 * h
        ..lids = 0.2 * h
        ..smile = 0.6 - 0.25 * h
        ..brow = kf(t, [0, 0, 0.8, 0, 0, 0.8, 0]);
    }),
    Clip('derin düşünür', 6.0, (p, t, s) {
      final h = hold(t);
      final idea = kf(t, [0, 0, 0, 0, 0, 1, 1, 0]); // sonunda aklına bir fikir gelir
      p
        ..armR = -1.55 * h * (1 - idea)
        ..armL += idea * 1.2
        ..headTilt += -0.12 * h * (1 - idea)
        ..lookX = 0.6 * h * (1 - idea)
        ..lookY = -0.7 * h
        ..brow = 0.7 * h
        ..smile = 0.1 + idea * 0.9
        ..open = idea * 0.5
        ..wide = idea * 0.7
        ..y += math.sin(idea * math.pi) * 8
        ..prop = Prop.bulb
        ..propA = idea
        ..ear += idea * 0.8;
    }),
    Clip('uyuklar, bozuntuya vermez', 8.0, (p, t, s) {
      final sleep = kf(t, [0, 0.5, 1, 1, 1, 1, 0, 0, 0, 0]);
      final jolt = kf(t, [0, 0, 0, 0, 0, 0, 1, 0, 0, 0]);
      final after = kf(t, [0, 0, 0, 0, 0, 0, 0, 1, 1, 0]); // hiçbir şey olmamış gibi yapar
      p
        ..lids = sleep
        ..headY += sleep * (8 + wave(s, 2.2) * 2)
        ..headTilt += sleep * 0.15
        ..squash += sleep * 0.6
        ..zzz = kf(t, [0, 0, 1, 1, 1, 0.5, 0, 0, 0, 0])
        ..y += jolt * 12
        ..wide = jolt
        ..armL += jolt * 1.3
        ..armR += jolt * 1.3
        ..ear += jolt
        ..lookX = kf(t, [0, 0, 0, 0, 0, 0, 0, -1, 1, 0])
        ..brow = after * 0.6
        ..smile = 0.6 - sleep * 0.4 + after * 0.2
        ..armR += after * -0.9; // papyonunu düzeltir
    }),
  ],

  // Tarçın: kurnaz şakacı
  MascotId.tarcin: [
    Clip('top sektirir', 7.0, (p, t, s) {
      final h = hold(t, 0.1);
      final b = math.sin(s * 5.0).abs(); // 0: ayağında, 1: tepede
      p
        ..prop = Prop.ball
        ..propA = h
        ..propT = b
        ..legR += (1 - b) * 1.2 * h
        ..lookY = (0.6 - b * 1.5) * h
        ..arms = 0.55 * h + wave(s, 0.63) * 0.1 * h
        ..lean += wave(s, 2.2) * 0.04 * h
        ..dx = wave(s, 2.2) * 5 * h
        ..tail += wave(s, 0.63) * 0.6 * h
        ..smile = 0.9
        ..open = 0.3 * h;
    }),
    Clip('dürbünle etrafı gözetler', 11.0, (p, t, s) {
      // Dürbün yandaki elinde büyüyerek belirir; tek eliyle yüzüne getirir, etrafı tarar; bir an indirip çıplak gözle
      // bakınca şaşırır (gözler faltaşı, ağız "o", küçük bir sıçrama, başının üstünde ünlem); yeniden kaldırır;
      // işi bitince aynı eliyle yana indirirken dürbün küçülerek kaybolur
      final h = hold(t, 0.09);
      final up = kf(t, [0, 0, 1, 1, 1, 0.25, 0.25, 0.25, 1, 1, 1, 0.45, 0]);
      final scan = ((up - 0.85) / 0.15).clamp(0.0, 1.0);
      final shock = kf(t, [0, 0, 0, 0, 0, 0.6, 1, 1, 0, 0, 0, 0, 0]);
      p
        ..prop = Prop.binoculars
        ..propA = h
        ..armR = 1.575 * up
        ..armL = 0.12 * h + 0.5 * shock
        ..lookX = wave(s, 2.6) * 0.95 * scan
        ..headX += wave(s, 2.6) * 5 * scan
        ..headTilt += wave(s, 2.6, 0.1) * 0.05 * scan
        ..lean += wave(s, 2.6) * 0.03 * scan - 0.05 * shock
        ..wide = shock
        ..brow = shock
        ..round = shock > 0.5 ? 1 : 0
        ..open = 0.7 * shock
        ..y += kf(t, [0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0])
        ..squash += kf(t, [0, 0, 0, 0, 0, -0.4, 0.3, 0, 0, 0, 0, 0, 0])
        ..ear += 0.6 * h + 0.6 * shock
        ..tail += wave(s, 0.9) * 0.5 * h
        ..smile = 0.7 - 0.5 * shock;
    }),
    Clip('sakarlık yapar, ıslık çalar', 6.5, (p, t, s) {
      p
        ..lean += kf(t, [0, -0.1, 0.5, 0.1, 0, 0, 0, 0, 0, 0])
        ..y += kf(t, [0, 0, 16, 0, 0, 0, 0, 0, 0, 0])
        ..squash += kf(t, [0, 0, -0.5, 1.5, 0.2, 0, 0, 0, 0, 0])
        ..armL += kf(t, [0, 0.3, 1.9, 1.2, 0.2, 0, 0, 0, 0, 0])
        ..armR += kf(t, [0, 0.3, 1.7, 1.4, 0.2, 0, 0, 0, 0, 0])
        ..wide = kf(t, [0, 0.2, 1, 1, 0.3, 0, 0, 0, 0, 0])
        ..round = kf(t, [0, 0, 1, 1, 0, 0, 1, 1, 1, 0]) > 0.5 ? 1 : 0
        ..open = kf(t, [0, 0, 0.7, 0.5, 0, 0, 0.15, 0.15, 0.15, 0])
        ..lookX = kf(t, [0, 0, 0, 0, -0.9, 0.9, 0.9, 0.9, 0.9, 0])
        ..lookY = kf(t, [0, 0, 0, 0, 0, 0, -0.6, -0.6, -0.6, 0])
        ..notes = kf(t, [0, 0, 0, 0, 0, 0, 1, 1, 1, 0])
        ..sweat = kf(t, [0, 0, 0, 1, 1, 0, 0, 0, 0, 0])
        ..tail += kf(t, [0, 0, 1, -0.6, 0, 0, 0.4, -0.4, 0.4, 0])
        ..headTilt += kf(t, [0, 0, 0, 0, 0, 0, 0.1, 0.1, 0.1, 0]);
    }),
    Clip('sinsi sinsi yürür', 5.5, (p, t, s) {
      final h = hold(t);
      p
        ..squash += 0.9 * h
        ..lookX = kf(t, [0, -1, -1, 1, 1, 0])
        ..dx = kf(t, [0, -9, -9, 9, 9, 0])
        ..lids = 0.36 * h
        ..smile = 0.6 + 0.4 * h
        ..legL += _up(wave(s, 0.6)) * 0.55 * h
        ..legR += _up(-wave(s, 0.6)) * 0.55 * h
        ..arms = 0.35 * h
        ..tail += wave(s, 1.1) * 0.7 * h
        ..ear += 0.5 * h;
    }),
  ],

  // Zifir: alaycı gözlemci
  MascotId.zifir: [
    Clip('müzik dinler', 8.5, (p, t, s) {
      final h = hold(t);
      final beat = wave(s, 0.55) * 0.5 + 0.5;
      p
        ..prop = Prop.headphones
        ..propA = h
        ..lids = h
        ..notes = h
        ..headY += beat * 4 * h
        ..headTilt += wave(s, 2.2) * 0.08 * h
        ..lean += wave(s, 1.1) * 0.03 * h
        ..legR += _up(wave(s, 0.55)) * 0.45 * h
        ..armL += (0.25 + beat * 0.1) * h
        ..tail += wave(s, 1.1) * 0.35 * h
        ..smile = 0.6 - 0.2 * h;
    }),
    Clip('göz devirir, omuz silker', 4.4, (p, t, s) {
      p
        ..lookY = kf(t, [0, -1, -1, -0.3, 0, 0])
        ..lookX = kf(t, [0, -0.7, 0.7, 0.9, 0, 0])
        ..armL += kf(t, [0, 0, 0.2, 0.75, 0.75, 0])
        ..armR += kf(t, [0, 0, 0.2, 0.75, 0.75, 0])
        ..headTilt += kf(t, [0, 0, 0, 0.12, 0.12, 0])
        ..brow = kf(t, [0, 0.5, 0.5, 0.9, 0.9, 0])
        ..smile = 0.6 - kf(t, [0, 0.3, 0.4, 0.8, 0.8, 0])
        ..ear += kf(t, [0, 0, 0.4, 0.8, 0.3, 0]);
    }),
    Clip('parlak şeye hayran kalır', 6.5, (p, t, s) {
      final h = hold(t);
      p
        ..prop = Prop.gem
        ..propA = h
        ..armR = 1.45 * h
        ..lookX = 0.8 * h
        ..lookY = -0.55 * h
        ..wide = h // alaycı bakış bir anlığına kaybolur: kaşlar kalkar, gözler ışıldar, gagası aralanır
        ..brow = 0.9 * h
        ..open = 0.3 * h
        ..sparkle = h
        ..headTilt += wave(s, 2.4) * 0.1 * h
        ..smile = 0.6 + 0.3 * h
        ..ear += 0.6 * h
        ..tail += wave(s, 0.8) * 0.4 * h;
    }),
    Clip('güneş gözlüğünü takıp poz verir', 11.0, (p, t, s) {
      // Küçük, yuvarlak, sapsız gözlük yandaki kanadında büyüyerek belirir; kanadıyla yüzüne takar, havalı bir
      // poz verir; sonra aynı kanadıyla çıkarır ve yana indirirken gözlük küçülerek kaybolur
      final h = hold(t, 0.09);
      final cool = kf(t, [0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0]);
      p
        ..prop = Prop.sunglasses
        ..propA = h
        ..propT = kf(t, [0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0]) // 0: kanatta, 1: yüzde
        ..armR = kf(t, [0, 0, 2.6, 2.6, 0.15, 0.15, 0.15, 2.6, 2.6, 1.0, 0])
        // Öbür kanadını öne uzatır: avucunda bir mavi, bir kırmızı hap
        ..armL = 1.25 * kf(t, [0, 0, 0.4, 1, 1, 1, 1, 0.6, 0, 0, 0])
        ..headTilt += -0.07 * cool + wave(s, 3.0) * 0.02 * cool
        ..lean += -0.04 * cool
        ..brow = 0.5 * cool
        ..smile = 0.6 + 0.35 * cool
        ..ear += 0.7 * cool
        ..tail += wave(s, 1.1) * 0.3 * cool;
    }),
  ],

  // Tosbi: sabırlı dost
  MascotId.tosbi: [
    Clip('sallanan koltukta çay içer', 9.5, (p, t, s) {
      final h = hold(t, 0.1);
      p
        ..prop = Prop.chair
        ..propA = h
        ..lean += wave(s, 2.6) * 0.12 * h
        ..lids = 0.5 * h
        ..legs = 0.9 * h
        ..armR = -0.5 * h
        ..armL = 0.2 * h
        ..smile = 0.7
        ..headTilt += wave(s, 2.6, 0.2) * 0.04 * h;
    }, wide: true),
    Clip('bastonuna yaslanıp ayakta uyuklar', 9.0, (p, t, s) {
      final h = hold(t, 0.12);
      p
        ..lids = h
        ..headTilt += (0.13 + wave(s, 3.2) * 0.03) * h
        ..headY += 4 * h
        ..lean += (-0.05 + wave(s, 3.2) * 0.025) * h
        ..squash += (0.25 + wave(s, 3.2, 0.25) * 0.2) * h // derin, ağır nefes
        ..zzz = kf(t, [0, 0.6, 1, 1, 1, 1, 0.5, 0])
        ..smile = 0.45;
    }),
    Clip('kabuğuna çekilir', 6.5, (p, t, s) {
      p
        ..special = kf(t, [0, 0.4, 1, 1, 1, 0.55, 0.55, 0])
        ..lookX = kf(t, [0, 0, 0, 0, 0, -1, 1, 0])
        ..wide = kf(t, [0, 0, 0, 0, 0, 0.5, 0.5, 0])
        ..squash += kf(t, [0, 0.3, 0.6, 0.6, 0.6, 0.3, 0.3, 0]);
    }),
    Clip('ninja göz bandını takıp poz verir', 11.5, (p, t, s) {
      // Mor göz bandı yandaki elinde büyüyerek belirir; eliyle yüzüne takar, bastonunu sopa gibi kaldırıp ninja pozu
      // verir; sonra aynı eliyle çıkarır ve yana indirirken bant küçülerek kaybolur
      final h = hold(t, 0.08);
      final pose = kf(t, [0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0]);
      p
        ..prop = Prop.mask
        ..propA = h
        ..propT = kf(t, [0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0]) // 0: elde, 1: yüzde
        ..armR = kf(t, [0, 0, 1.9, 1.9, 1.1, 1.1, 1.1, 1.1, 1.9, 1.9, 0.9, 0])
        ..armL = 1.3 * pose
        ..browTilt = -0.9 * pose // kararlı, çatık bakış
        ..lids = math.max(p.lidL, 0.22 * pose)
        ..smile = 0.6 - 0.35 * pose
        ..lean += 0.06 * pose
        ..headTilt += -0.05 * pose
        ..squash += 0.45 * pose
        ..y += kf(t, [0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0]);
    }),
  ],

  // Paşa: hafıza ustası
  MascotId.pasa: [
    Clip('not alır', 12.5, (p, t, s) {
      // Önce monoklünü takar: monokl sağ elinde büyüyerek belirir, eliyle sağ gözüne yerleştirir. Sonra defterine not
      // alır. Yazı bitince aynı eliyle monoklü çıkarır; elini yana indirirken monokl küçülerek kaybolur.
      final h = kf(t, [0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0]); // defter ve kalem
      final reach = kf(t, [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0]); // sağ el göze uzanır
      p
        ..gear = kf(t, [0, 1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 1, 0])
        ..prop = Prop.notebook
        ..propA = h
        ..propT = (s / 1.2) % 1
        ..armL = -0.4 * h
        ..armR = 1.8 * reach + (-0.55 + wave(s, 0.35) * 0.05) * h
        ..lookY = 0.7 * h
        ..lookX = -0.3 * h + 0.5 * reach
        ..headY += 3 * h
        ..headTilt += 0.05 * reach
        ..special = wave(s, 2.4) * 0.08 * h
        ..brow = kf(t, [0, 0, 0.5, 0.5, 0, 0, 0.8, 0, 0, 0.5, 0.5, 0, 0])
        ..ear += kf(t, [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    }),
    Clip('eski telefonla konuşur', 12.0, (p, t, s) {
      // Ahizesi ayrı, şamdan biçimli eski telefon ellerinde büyüyerek belirir; sol eliyle ahizeyi kulağına, sağ eliyle
      // mikrofonu ağzına götürür; konuşur, dinler, yine konuşur; ellerini indirirken telefon küçülerek kaybolur
      final up = kf(t, [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0]);
      final talk = kf(t, [0, 0, 0, 1, 1, 0, 0, 1, 1, 0.3, 0, 0]);
      final listen = kf(t, [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0]);
      p
        ..prop = Prop.phone
        ..propA = kf(t, [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0])
        ..armL = 1.45 * up
        ..armR = -0.85 * up
        ..open = talk * (0.3 + 0.3 * wave(s, 0.32))
        ..headY += wave(s, 0.9) * 1.5 * talk
        ..headTilt += -0.05 * up
        ..lookX = -0.6 * listen
        ..lookY = -0.4 * listen
        ..brow = 0.6 * listen + 0.3 * talk
        ..smile = 0.7;
    }),
    Clip('kulaklarını çırpıp borazan çalar', 4.8, (p, t, s) {
      final h = hold(t);
      p
        ..special = 0.85 * h
        ..ear += wave(s, 0.3).abs() * h
        ..notes = h
        ..y += math.sin(t * math.pi * 4).abs() * 8 * h
        ..arms = 1.2 * h
        ..smile = 1
        ..open = 0.6 * h
        ..tail += wave(s, 0.4) * h;
    }),
    Clip('köstekli saatine bakar', 10.5, (p, t, s) {
      // Sağ eliyle yeleğinin cebinden köstekli saatini çıkarır, yana kaldırıp kapağını açar, saate bakar, onaylar
      // gibi başını sallar; kapağı kapatıp saati cebine geri koyar
      final up = kf(t, [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0]);
      final lid = kf(t, [0, 0, 0, 0, 0.6, 1, 1, 1, 1, 0, 0, 0, 0]);
      final read = kf(t, [0, 0, 0, 0, 0.5, 1, 1, 1, 0.5, 0, 0, 0, 0]);
      p
        ..prop = Prop.pocketWatch
        ..propA = kf(t, [0, 0, 0.45, 1, 1, 1, 1, 1, 1, 1, 0.45, 0, 0]) // cepten çıkarken büyür, girerken küçülür
        ..propT = up + lid // 0–1: cepten çıkıp kalkar, 1–2: kapağı açılır
        ..armR = kf(t, [0, -0.55, -0.55, 0.72, 0.72, 0.72, 0.72, 0.72, 0.72, 0.72, -0.55, -0.55, 0])
        ..armL = 0.1 * up
        ..lookX = kf(t, [0, 0.5, 0.5, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.5, 0.5, 0])
        ..lookY = kf(t, [0, 0.9, 0.9, 0.45, 0.45, 0.45, 0.45, 0.45, 0.45, 0.45, 0.9, 0.9, 0])
        ..headTilt += 0.1 * up
        ..headX += 4 * up
        ..headY += kf(t, [0, 2, 2, 0, 0, 0, 3, 0, 3, 0, 2, 2, 0])
        ..lids = 0.18 * read
        ..brow = 0.6 * read
        ..smile = 0.6 + 0.3 * kf(t, [0, 0, 0, 0, 0, 0, 1, 1, 1, 0.5, 0, 0, 0])
        ..ear += 0.4 * up;
    }),
  ],

  // Sekiz: meraklı mucit
  MascotId.sekiz: [
    Clip('gözlüğünü takıp erlenmayerdeki deneyi inceler', 8.5, (p, t, s) {
      final h = hold(t);
      p
        ..prop = Prop.beaker // gözlük gözüne iner, erlenmayer göz hizasına kalkar
        ..propA = h
        ..propT = (s / 1.3) % 1
        ..armR = 0.98 * h
        ..armL = 0.2 * h
        ..lookX = (0.8 + wave(s, 2.2) * 0.12) * h
        ..lookY = -0.1 * h
        ..lids = kf(t, [0, 0.3, 0.3, 0.3, 0, 0, 0]) // önce kısık gözle inceler, sonra bir şey fark eder
        ..headTilt += (0.07 + wave(s, 2.6) * 0.03) * h
        ..headX += 2 * h
        ..brow = kf(t, [0, 0, 0.2, 0.2, 0.9, 0.9, 0])
        ..wide = kf(t, [0, 0, 0, 0, 0.6, 0.4, 0])
        ..smile = 0.6 - 0.3 * h + kf(t, [0, 0, 0, 0, 0.5, 0.5, 0])
        ..open = kf(t, [0, 0, 0, 0, 0.45, 0.3, 0]);
    }),
    Clip('aletlerle hokkabazlık yapar', 7.5, (p, t, s) {
      final h = hold(t);
      p
        ..prop = Prop.gadgets
        ..propA = h
        ..propT = (s / 1.5) % 1
        ..armL = (1.25 + wave(s, 0.75) * 0.25) * h
        ..armR = (1.25 - wave(s, 0.75) * 0.25) * h
        ..lookY = -0.8 * h
        ..lookX = wave(s, 1.5) * 0.8 * h
        ..smile = 0.9
        ..open = 0.4 * h
        ..ear += h;
    }),
    Clip('mikroskopta inceleme yapar', 10.0, (p, t, s) {
      // Mikroskop yanında büyüyerek belirir; göz merceğine eğilir, öbür gözünü kısar, netlik düğmesini çevirir;
      // bir şey fark edip doğrulur, sevinir, yeniden bakar
      final h = hold(t, 0.09);
      final look = kf(t, [0, 0, 1, 1, 1, 0.1, 0.1, 1, 1, 0.3, 0]);
      final found = kf(t, [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0]);
      p
        ..prop = Prop.microscope
        ..propA = h
        ..headTilt += 0.13 * look
        ..headX += 5 * look
        ..headY += 3 * look
        ..lidL = math.max(p.lidL, 0.95 * look)
        ..lookX = 0.5 * look
        ..lookY = 0.6 * look
        ..armR = (0.42 + wave(s, 0.8) * 0.07) * look
        ..brow = found
        ..wide = 0.7 * found
        ..smile = 0.5 + 0.4 * found
        ..open = 0.5 * found
        ..squash += 0.2 * look;
    }),
  ],

  // Dalga: enerjik amigo
  MascotId.dalga: [
    Clip('halter kaldırır', 7.5, (p, t, s) {
      final h = hold(t);
      final rep = wave(s, 1.3) * 0.5 + 0.5; // 0: aşağıda, 1: yukarıda
      p
        ..prop = Prop.barbell
        ..propA = h
        ..arms = (0.9 + rep * 0.95) * h
        ..squash += (0.9 - rep * 1.6) * h
        ..browTilt = -0.5 * h
        ..brow = -0.3 * h
        ..smile = 0.6 - 0.5 * h
        ..open = (1 - rep) * 0.4 * h
        ..sweat = kf(t, [0, 0, 0, 1, 1, 1, 0])
        ..tail += wave(s, 1.3) * 0.3 * h;
    }),
    Clip('burnunda top çevirir', 7.5, (p, t, s) {
      final h = hold(t);
      final b = wave(s, 0.8).abs();
      p
        ..prop = Prop.beachBall
        ..propA = h
        ..propT = b
        ..lookY = -0.9 * h
        ..headTilt += wave(s, 1.6) * 0.12 * h
        ..lean += wave(s, 1.6) * 0.05 * h
        ..arms = (0.7 + wave(s, 0.8) * 0.15) * h
        ..y += (1 - b) * 4 * h
        ..tail += wave(s, 0.8) * 0.5 * h
        ..smile = 0.9;
    }),
    Clip('yorulur, dinlenir, toparlanır', 8.0, (p, t, s) {
      final pant = wave(s, 0.5) * 0.5 + 0.5;
      final tired = kf(t, [0, 1, 1, 1, 0.4, 0, 0]);
      p
        ..squash += (0.9 + pant * 0.5) * tired
        ..open = (0.35 + pant * 0.35) * tired
        ..lids = 0.55 * tired
        ..browTilt = 0.6 * tired
        ..sweat = tired
        ..armR = kf(t, [0, 0, -1.7, -1.7, 0, 1.6, 0]) // alnını siler, sonra kolunu kaldırır
        ..armL += kf(t, [0, 0, 0, 0, 0, 1.6, 0])
        ..headTilt += tired * 0.1
        ..smile = kf(t, [0.6, -0.2, -0.2, -0.2, 0.3, 1, 0.6])
        ..y += kf(t, [0, 0, 0, 0, 0, 12, 0])
        ..tail += kf(t, [0, -0.4, -0.4, -0.4, 0, 0.8, 0]);
    }),
  ],
};

/// Belirli bir andaki duruş: ruh hâli + sürekli kıpırtı + (varsa) oynayan hareket.
Pose poseAt(Mood mood, double s, {double seed = 0, Clip? clip, double clipTime = 0, bool idle = true}) {
  final p = Pose();
  applyMood(p, mood, s);
  if (idle) applyIdle(p, s, seed);
  if (clip != null) clip.apply(p, (clipTime / clip.seconds).clamp(0, 1).toDouble(), clipTime);
  return p;
}
