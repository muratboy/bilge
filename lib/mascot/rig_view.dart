import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'actions.dart';
import 'mascot_art.dart';
import 'mascot_view.dart';
import 'pose.dart';
import 'rig.dart';

/// Maskotu iskeletiyle canlandırır: nefes alır, göz kırpar, ara sıra çevresine bakar ya da kıpırdanır ve rastgele
/// zamanlarda kendine özgü imza hareketlerinden birini yapar (actions.dart).
class RigMascotView extends StatefulWidget {
  const RigMascotView(this.id, {super.key, this.mood = Mood.happy, this.size = 96, this.still = false, this.roomy = false, this.calm = false, this.onPoke});

  /// Verilirse maskota dokunulabilir: dokununca bir imza hareketi yapar ve bu çağrılır.
  final VoidCallback? onPoke;

  /// Ders içi: imza hareketi yapmaz; [MascotView.drowsy] açıkken uyur.
  final bool calm;

  final MascotId id;
  final Mood mood;
  final double size; // genişlik; yükseklik 1.15 katıdır
  final bool still; // hiç kıpırdamaz (küçük seçim kartları için)

  /// Çevresinde boş yer var: yatma, koltuk gibi geniş hareketler de oynatılabilir.
  final bool roomy;

  @override
  State<RigMascotView> createState() => _RigMascotViewState();
}

/// Deneme derlemesi (`--dart-define=BILGE_DEMO=true`): imza hareketleri beklemeden, sırayla oynar.
const _demo = bool.fromEnvironment('BILGE_DEMO');

class _RigMascotViewState extends State<RigMascotView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _frame = ValueNotifier<int>(0);
  final _random = Random();
  late final double _seed = _random.nextDouble();
  Ticker? _ticker;
  Pose _pose = Pose();
  double _time = 0;

  Clip? _clip;
  String? _lastSignature;
  double _clipStart = 0;
  late double _nextAt = 1.0 + _random.nextDouble() * 1.5;
  late double _blinkAt = 1.5 + _random.nextDouble() * 2;
  int _sinceSignature = 0;
  double _moodAt = 0; // ruh hâlinin en son değiştiği an
  double _sleep = 0; // 0: uyanık … 1: uyuyor
  Timer? _sleepTimer;
  bool _isBackground = false;

  /// Sevinç gösterisi bu kadar sürer (saniye); sonra sakin, güler yüzlü duruşa döner.
  static const _cheerSeconds = 2.8;

  bool get _alive => MascotView.animate && !widget.still;

  @visibleForTesting
  bool get isSleepTimerActive => _sleepTimer != null && _sleepTimer!.isActive;

  @visibleForTesting
  bool get isTickerActive => _ticker != null && _ticker!.isActive;

  @visibleForTesting
  double get sleepValue => _sleep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MascotView.drowsy.addListener(_onDrowsyChanged);
    _pose = poseAt(widget.mood, 0, idle: false);
    if (_alive) _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (!enabled) {
      _stopSleepTimer();
    } else if (_sleep >= 1.0 && widget.calm && MascotView.drowsy.value && !_isBackground) {
      if (_sleepTimer == null || !_sleepTimer!.isActive) {
        _startSleepTimer();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (_isBackground) {
      _stopSleepTimer();
    } else {
      if (_sleep >= 1.0 && widget.calm && MascotView.drowsy.value && (_ticker == null || !_ticker!.isActive)) {
        _startSleepTimer();
      }
    }
  }

  void _onDrowsyChanged() {
    if (!MascotView.drowsy.value) {
      _wake();
    }
  }

  void _startSleepTimer() {
    _sleepTimer?.cancel();
    if (_alive && !_isBackground && mounted && TickerMode.valuesOf(context).enabled) {
      // Uykuda nefes animasyonu: saniyede ~9 kare (8-10 kare arası)
      _sleepTimer = Timer.periodic(const Duration(milliseconds: 110), (_) => _sleepTick());
    }
  }

  void _stopSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  void _sleepTick() {
    if (!mounted) return;
    if (!MascotView.drowsy.value) {
      _wake();
      return;
    }
    _time += 0.11;
    final t = _time;
    final p = poseAt(Mood.happy, t, seed: _seed);
    p.mix(
      Pose()
        ..lids = 1
        ..headTilt = 0.13 + wave(t, 3.4) * 0.03
        ..headY = 4
        ..lean = -0.04 + wave(t, 3.4) * 0.02
        ..squash = 0.25 + wave(t, 3.4, 0.25) * 0.2
        ..smile = 0.4
        ..zzz = 1,
      1.0,
    );
    _pose = p;
    _frame.value++;
  }

  void _wake() {
    _stopSleepTimer();
    if (_alive && _ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  @override
  void didUpdateWidget(RigMascotView old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.id != widget.id) {
      _clip = null; // tepki verirken yarım kalan hareketi bırak
      _nextAt = _time + 2;
      _moodAt = _time;
      if (!_alive) {
        _pose = poseAt(widget.mood, 0, idle: false);
        _frame.value++;
      }
    }
  }

  /// Sıradaki hareketi seçer: çoğunlukla küçük bir jest, arada bir imza hareketi.
  Clip _choose() {
    if (_demo) {
      final all = signatures[widget.id]!;
      final next = all[(all.indexWhere((c) => c.name == _lastSignature) + 1) % all.length];
      _lastSignature = next.name;
      return next;
    }
    final own = signatures[widget.id]!.where((c) => (widget.roomy || !c.wide) && c.name != _lastSignature).toList();
    // İmza hareketleri seyrek gelir (yaklaşık yarım dakikada bir); arası küçük jestlerle dolar.
    // Ders içinde ([RigMascotView.calm]) hiç oynamaz: dikkat dağıtır.
    if (!widget.calm && own.isNotEmpty && _sinceSignature >= 4 + _random.nextInt(3)) {
      _sinceSignature = 0;
      final pick = own[_random.nextInt(own.length)];
      _lastSignature = pick.name;
      return pick;
    }
    _sinceSignature++;
    return microGestures[_random.nextInt(microGestures.length)];
  }

  /// Oynayan hareketin adı (testler için).
  @visibleForTesting
  String? get clipName => _clip?.name;

  /// Maskota dokunuldu: beklemeden bir imza hareketi yapar. Zaten bir imza hareketinin ortasındaysa bölünmez
  /// (yarıda kesilen hareket sıçrama gibi görünür); üzgün ya da düşünceliyken de oynamaz.
  void _poke() {
    widget.onPoke?.call();
    final calm = widget.mood == Mood.happy || (widget.mood == Mood.cheer && _time - _moodAt > _cheerSeconds + 0.6);
    final all = signatures[widget.id]!;
    if (!_alive || !calm || _sleep > 0.02 || all.contains(_clip)) return;
    final own = all.where((c) => (widget.roomy || !c.wide) && c.name != _lastSignature).toList();
    if (own.isEmpty) return;
    final pick = own[_random.nextInt(own.length)];
    _lastSignature = pick.name;
    _sinceSignature = 0;
    _clip = pick;
    _clipStart = _time;
  }

  void _tick(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6 - _time;
    _time = elapsed.inMicroseconds / 1e6;
    final t = _time;
    // Uyku: yavaşça dalar, dokununca çabucak uyanır
    final drowsy = widget.calm && MascotView.drowsy.value;
    _sleep = (_sleep + dt * (drowsy ? 0.8 : -4)).clamp(0.0, 1.0);
    if (_sleep > 0.02) _clip = null;
    if (_sleep >= 1.0 && drowsy) {
      // Tam uykuya daldı: 60 FPS Ticker durdurulur, düşük kare hızlı zamanlayıcı başlar
      _ticker?.stop();
      _startSleepTimer();
      _sleepTick();
      return;
    }
    // Hareketler yalnızca maskot sakinken oynar; sevinç ve üzüntü kendi başına hareketlidir
    // Ders içinde ([RigMascotView.calm]) hiçbir jest oynamaz: uslu uslu cevabı bekler
    // Sevinç gösterisi bittikten sonra maskot sakin sayılır: jestlerini ve imza hareketlerini yapabilir
    final settled = !widget.calm && widget.mood == Mood.cheer && t - _moodAt > _cheerSeconds + 0.6;
    if ((widget.mood == Mood.happy || settled) && _sleep <= 0.02 && !widget.calm) {
      if (_clip == null && t >= _nextAt) {
        _clip = _choose();
        _clipStart = t;
      } else if (_clip != null && t - _clipStart >= _clip!.seconds) {
        _clip = null;
        _nextAt = t + (_demo ? 0.7 : 2.2 + _random.nextDouble() * 3.6);
      }
    }
    // Ders içinde sevinç de sakindir: zıplamaz, kollarını sallamaz; yalnızca gözleri gülerek kısılır
    final quietCheer = widget.calm && widget.mood == Mood.cheer;
    final p = poseAt(quietCheer || settled ? Mood.happy : widget.mood, t, seed: _seed, clip: widget.calm ? null : _clip, clipTime: t - _clipStart);
    if (quietCheer) {
      final k = 1 - ((t - _moodAt - _cheerSeconds) / 0.5).clamp(0.0, 1.0);
      p
        ..joy = k
        ..smile = 0.95
        ..open = 0.3 * k
        ..headTilt += 0.04 * k;
    }
    // Sevinç gösterisi bir süre sonra durur: zıplamayı bırakıp güler yüzle bekler
    if (widget.mood == Mood.cheer && !quietCheer && !settled) {
      final k = ((t - _moodAt - _cheerSeconds) / 0.5).clamp(0.0, 1.0);
      if (k > 0) p.mix(poseAt(Mood.happy, t, seed: _seed)..smile = 0.9, k * k * (3 - 2 * k));
    }
    if (_sleep > 0.02) {
      final s = _sleep * _sleep * (3 - 2 * _sleep);
      p.mix(
          Pose()
            ..lids = 1
            ..headTilt = 0.13 + wave(t, 3.4) * 0.03
            ..headY = 4
            ..lean = -0.04 + wave(t, 3.4) * 0.02
            ..squash = 0.25 + wave(t, 3.4, 0.25) * 0.2
            ..smile = 0.4
            ..zzz = 1,
          s);
    }
    // Göz kırpma (ara sıra iki kez üst üste)
    if (t >= _blinkAt) {
      final k = (t - _blinkAt) / 0.17;
      if (k >= 1) {
        _blinkAt = t + (_random.nextInt(5) == 0 ? 0.12 : 1.8 + _random.nextDouble() * 3.4);
      } else {
        final lid = sin(k * pi);
        p
          ..lidL = max(p.lidL, lid)
          ..lidR = max(p.lidR, lid);
      }
    }
    _pose = p;
    _frame.value++;
  }

  @override
  void dispose() {
    _stopSleepTimer();
    MascotView.drowsy.removeListener(_onDrowsyChanged);
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawing = RepaintBoundary(
      child: CustomPaint(size: Size(widget.size, widget.size * 1.15), painter: _RigPainter(this)),
    );
    if (widget.still) return drawing;
    if (widget.calm) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_sleep > 0) {
            MascotView.drowsy.value = false;
            _wake();
          }
        },
        child: drawing,
      );
    }
    if (widget.onPoke != null) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: _poke, child: drawing);
    }
    return drawing;
  }
}

class _RigPainter extends CustomPainter {
  _RigPainter(this.state) : super(repaint: state._frame);
  final _RigMascotViewState state;

  @override
  void paint(Canvas canvas, Size size) => paintMascot(canvas, size, state.widget.id, state._pose, state._time);

  @override
  bool shouldRepaint(_RigPainter old) => true;
}
