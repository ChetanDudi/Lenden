import 'package:flutter/material.dart';
import 'dart:math';

class PremiumWaveBackground extends StatefulWidget {
  const PremiumWaveBackground({super.key});

  @override
  State<PremiumWaveBackground> createState() => _PremiumWaveBackgroundState();
}

class _PremiumWaveBackgroundState extends State<PremiumWaveBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          children: [
            CustomPaint(
              painter: WavePainter(
                controller.value,
                0.8,
                25,
                const Color(0xFF00B4D8).withValues(alpha: 0.4),
              ),
              size: Size.infinite,
            ),
            CustomPaint(
              painter: WavePainter(
                controller.value * 1.5,
                0.82,
                30,
                const Color(0xFF00B4D8).withValues(alpha: 0.6),
              ),
              size: Size.infinite,
            ),
            CustomPaint(
              painter: WavePainter(
                controller.value * 2,
                0.85,
                35,
                const Color(0xFF0096C7),
              ),
              size: Size.infinite,
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;
  final double heightPercent;
  final double waveHeight;
  final Color color;

  WavePainter(
    this.animationValue,
    this.heightPercent,
    this.waveHeight,
    this.color,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    // Draw a filled area at the top of the widget with a wavy bottom edge.
    // This makes the wave appear at the top of the screen (underneath the app bar).
    final baseHeight = size.height * heightPercent;

    path.moveTo(0, 0);
    path.lineTo(0, baseHeight);

    for (double i = 0; i <= size.width; i++) {
      path.lineTo(
        i,
        baseHeight +
            sin((i / size.width * 2 * pi) + animationValue * 2 * pi) *
                waveHeight,
      );
    }

    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
