import 'dart:math';

import 'package:flutter/material.dart';

/// Ekranın üstünden bir kez patlayan konfeti. Dokunuşları engellemez.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.count = 120});
  final int count;

  /// Testlerde süresiz bekleyen animasyon kalmasın diye kapatılabilir.
  static bool enabled = true;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Piece {
  _Piece(Random r)
      : x = 0.5 + (r.nextDouble() - 0.5) * 0.3,
        vx = (r.nextDouble() - 0.5) * 1.5,
        vy = -(r.nextDouble() * 1.3 + 0.35),
        size = 6 + r.nextDouble() * 7,
        spin = (r.nextDouble() - 0.5) * 14,
        phase = r.nextDouble() * pi,
        color = _colors[r.nextInt(_colors.length)];
  final double x, vx, vy, size, spin, phase;
  final Color color;
  static const _colors = [Color(0xFF7C5CFF), Color(0xFFFFB800), Color(0xFF22B573), Color(0xFFFF5263), Color(0xFF3A8DFF), Color(0xFFF0559E)];
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final r = Random();
    _pieces = List.generate(Confetti.enabled ? widget.count : 0, (_) => _Piece(r));
    if (Confetti.enabled) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(animation: _controller, builder: (_, _) => CustomPaint(size: Size.infinite, painter: _Painter(_pieces, _controller.value))),
      );
}

class _Painter extends CustomPainter {
  _Painter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final time = t * 2.6; // saniye
    final paint = Paint();
    for (final p in pieces) {
      final x = (p.x + p.vx * time * 0.35) * size.width;
      final y = size.height * 0.34 + (p.vy * time + 0.9 * time * time) * size.height * 0.42;
      final angle = p.phase + p.spin * time;
      paint.color = p.color.withValues(alpha: (1 - t).clamp(0, 1).toDouble());
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(angle)
        ..drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * (0.4 + 0.6 * cos(angle * 2).abs())), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.t != t;
}
