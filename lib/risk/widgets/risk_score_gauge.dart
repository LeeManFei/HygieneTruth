import 'dart:math' as math;
import 'package:flutter/material.dart';

class RiskScoreGauge extends StatelessWidget {
  final double score; // 0.0 (safest) to 100.0 (highest risk)
  final double size;

  const RiskScoreGauge({
    super.key,
    required this.score,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    if (score < 30) {
      color = const Color(0xFF10B981); // Emerald Green
    } else if (score < 60) {
      color = const Color(0xFFF59E0B); // Amber
    } else {
      color = const Color(0xFFEF4444); // Red
    }

    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _GaugeArcPainter(
                score: score,
                color: color,
                trackColor: const Color(0xFFE2E8F0),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    score.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: size * 0.26,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ),
                Text(
                  'RISK',
                  style: TextStyle(
                    fontSize: size * 0.13,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugeArcPainter extends CustomPainter {
  final double score;
  final Color color;
  final Color trackColor;

  _GaugeArcPainter({
    required this.score,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - 10) / 2;
    final strokeWidth = math.max(5.0, size.width * 0.1);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2; // Top center
    const totalSweep = 2 * math.pi * 0.85; // 85% radial arc gauge

    // Draw background circular track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      trackPaint,
    );

    // Draw active progress radial arc
    final sweepAngle = totalSweep * (score.clamp(0.0, 100.0) / 100.0);
    if (sweepAngle > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugeArcPainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.color != color;
  }
}
