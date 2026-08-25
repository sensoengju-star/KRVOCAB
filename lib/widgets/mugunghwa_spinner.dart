import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A custom-painted mugunghwa (Rose of Sharon) petal spinner.
class MugunghwaSpinner extends StatefulWidget {
  const MugunghwaSpinner({super.key, this.size = 48});
  final double size;

  @override
  State<MugunghwaSpinner> createState() => _MugunghwaSpinnerState();
}

class _MugunghwaSpinnerState extends State<MugunghwaSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _PetalPainter(_c.value)),
        ),
      ),
    );
  }
}

class _PetalPainter extends CustomPainter {
  _PetalPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * 2 * pi);

    const petals = 5;
    final petalRect = Rect.fromLTWH(-r, -r, r * 2, r * 2);

    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(r * 0.25, -r * 0.45, 0, -r * 0.95)
      ..quadraticBezierTo(-r * 0.25, -r * 0.45, 0, 0)
      ..close();

    for (var i = 0; i < petals; i++) {
      canvas.save();
      canvas.rotate(2 * pi * i / petals);
      final phase = (t + i / petals) % 1.0;
      final alpha = (0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 2 * pi))).clamp(0.0, 1.0);
      // Linear gold gradient as the petal fill, with per-petal alpha applied.
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.lightGold.withValues(alpha: alpha),
            AppColors.deepGold.withValues(alpha: alpha),
          ],
        ).createShader(petalRect);
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    final dot = Paint()..color = AppColors.deepGold.withValues(alpha: 0.9);
    canvas.drawCircle(Offset.zero, r * 0.13, dot);
  }

  @override
  bool shouldRepaint(covariant _PetalPainter oldDelegate) => oldDelegate.t != t;
}
