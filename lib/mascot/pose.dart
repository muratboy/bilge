/// Bir maskotun tek bir andaki duruşu. Animasyon, her karede bu değerleri değiştirerek yapılır.
library;

import 'dart:math' as math;

/// Maskotun elinde ya da çevresinde beliren eşyalar.
enum Prop { none, book, headphones, ball, chair, cloud, notebook, water, ruler, gadgets, smoke, bulb, barbell, beachBall, gem, beaker, binoculars, microscope, sunglasses, mask, pocketWatch, phone }

class Pose {
  // Gövde
  double y = 0; // zıplama (yukarı +)
  double dx = 0; // yatay kayma
  double rot = 0; // tüm gövdenin dönmesi (sırt üstü yatmak için)
  double lean = 0; // sağa sola eğilme
  double squash = 0; // + basık, − uzamış

  // Kafa ve yüz
  double headTilt = 0, headX = 0, headY = 0;
  double lookX = 0, lookY = 0; // bakış yönü (−1…1)
  double lidL = 0, lidR = 0; // göz kapağı: 0 açık … 1 kapalı
  double wide = 0; // şaşkınlıkta gözler büyür
  double joy = 0; // sevinçte gözler "^ ^" olur
  double brow = 0; // + kalkık
  double browTilt = 0; // + üzgün, − çatık
  double smile = 0.6, open = 0, round = 0; // ağız

  // Uzuvlar: 0 aşağıda, 1 yana açık, 2 yukarıda; negatif değer gövdenin önüne
  double armL = 0, armR = 0;
  double legL = 0, legR = 0; // ayak kaldırma
  double tail = 0, ear = 0;
  double special = 0; // karaktere özgü: hortum kıvrımı, kabuğa girme

  // Eşya ve efektler
  Prop prop = Prop.none;
  double propT = 0; // eşyanın kendi hareketi (0…1 döngü)
  double propA = 0; // eşyanın belirme oranı (0…1)
  double zzz = 0, notes = 0, sweat = 0, sparkle = 0, tear = 0;

  /// Karaktere özgü takılan aksesuar (Paşa'nın monoklü): 0 yok, 0–1 elde büyür, 1–2 elden yerine gider, 2 takılı.
  double gear = 0;

  /// Bu duruşu [k] oranında [o] duruşuna yaklaştırır (0: değişmez, 1: [o] olur). Eşya ve onun değerleri değişmez.
  void mix(Pose o, double k) {
    double f(double a, double b) => a + (b - a) * k;
    y = f(y, o.y);
    dx = f(dx, o.dx);
    rot = f(rot, o.rot);
    lean = f(lean, o.lean);
    squash = f(squash, o.squash);
    headTilt = f(headTilt, o.headTilt);
    headX = f(headX, o.headX);
    headY = f(headY, o.headY);
    lookX = f(lookX, o.lookX);
    lookY = f(lookY, o.lookY);
    lidL = f(lidL, o.lidL);
    lidR = f(lidR, o.lidR);
    wide = f(wide, o.wide);
    joy = f(joy, o.joy);
    brow = f(brow, o.brow);
    browTilt = f(browTilt, o.browTilt);
    smile = f(smile, o.smile);
    open = f(open, o.open);
    round = f(round, o.round);
    armL = f(armL, o.armL);
    armR = f(armR, o.armR);
    legL = f(legL, o.legL);
    legR = f(legR, o.legR);
    tail = f(tail, o.tail);
    ear = f(ear, o.ear);
    special = f(special, o.special);
    zzz = f(zzz, o.zzz);
    notes = f(notes, o.notes);
    sweat = f(sweat, o.sweat);
    sparkle = f(sparkle, o.sparkle);
    tear = f(tear, o.tear);
    gear = f(gear, o.gear);
  }

  set lids(double v) => lidL = lidR = v;
  set arms(double v) => armL = armR = v;
  set legs(double v) => legL = legR = v;
}

/// [t] 0…1 arasında; [v] eşit aralıklı duraklardır, araları yumuşak geçilir.
double kf(double t, List<double> v) {
  if (t <= 0) return v.first;
  if (t >= 1) return v.last;
  final x = t * (v.length - 1);
  final i = x.floor();
  final f = x - i;
  return v[i] + (v[i + 1] - v[i]) * f * f * (3 - 2 * f);
}

/// Hareketin başında ve sonunda yumuşakça açılıp kapanan zarf (0 → 1 → 0).
double hold(double t, [double edge = 0.12]) => math.min(1, math.min(t, 1 - t) / edge).clamp(0, 1).toDouble().smooth;

/// Saniye cinsinden [s] zamanı için [period] saniyelik salınım (−1…1).
double wave(double s, double period, [double phase = 0]) => math.sin((s / period + phase) * 2 * math.pi);

extension on double {
  double get smooth => this * this * (3 - 2 * this);
}
