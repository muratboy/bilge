import 'package:flutter/widgets.dart';

import 'mascot_art.dart';
import 'rig_view.dart';

/// Bir maskotu gösterir: karakter vektör olarak çizilir ve iskeletiyle canlandırılır (rig.dart, actions.dart).
class MascotView extends StatelessWidget {
  const MascotView(this.id, {super.key, this.mood = Mood.happy, this.size = 96, this.still = false, this.calm = false, this.onPoke});

  final MascotId id;
  final Mood mood;
  final double size; // genişlik; yükseklik 1.15 katıdır
  final bool still; // hiç kıpırdamaz (küçük seçim kartları için)

  /// Ders içi: dikkat dağıtmasın diye imza hareketi yapmaz; uzun süre cevap gelmezse uyur ([drowsy]).
  final bool calm;

  /// Verilirse maskota dokunulabilir: dokununca bir imza hareketi yapar ve bu çağrılır (söz göstermek için).
  /// Ders içindeki ([calm]) ve kıpırdamayan ([still]) maskotlar dokunmaya tepki vermez.
  final VoidCallback? onPoke;

  /// Ders ekranı ayarlar: kullanıcı uzun süre cevap vermedi. Sakin ([calm]) maskotlar uyur; ekrana dokununca uyanırlar.
  static final drowsy = ValueNotifier<bool>(false);

  /// Testlerde süresiz animasyon kalmasın diye kapatılır.
  static bool animate = true;

  @override
  // Yatma, koltuk gibi yer isteyen hareketler yalnızca büyük gösterimlerde oynar
  Widget build(BuildContext context) => RigMascotView(id, mood: mood, size: size, still: still, roomy: size >= 140 && !calm, calm: calm, onPoke: onPoke);
}
