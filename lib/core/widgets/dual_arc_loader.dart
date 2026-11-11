import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A sleek, modern indeterminate loading spinner featuring two complementary
/// rotating arcs on opposite sides for a balanced, premium feel.
class DualArcLoader extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? secondaryColor;
  final Duration duration;

  const DualArcLoader({
    super.key,
    this.size = 28.0,
    this.strokeWidth = 2.5,
    this.color,
    this.secondaryColor,
    this.duration = const Duration(milliseconds: 950),
  });

  /// Convenient helper for a centered full-card or page loader
  static Widget centered({
    double size = 32.0,
    double strokeWidth = 2.8,
    Color? color,
    String? message,
    bool isDark = false,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DualArcLoader(
            size: size,
            strokeWidth: strokeWidth,
            color: color,
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  State<DualArcLoader> createState() => _DualArcLoaderState();
}

class _DualArcLoaderState extends State<DualArcLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = widget.color ?? (isDark ? Colors.tealAccent : const Color(0xFF0F766E));
    final secondaryColor = widget.secondaryColor ?? primaryColor.withValues(alpha: 0.75);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _DualArcPainter(
              progress: _controller.value,
              strokeWidth: widget.strokeWidth,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
            ),
          );
        },
      ),
    );
  }
}

class _DualArcPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color primaryColor;
  final Color secondaryColor;

  _DualArcPainter({
    required this.progress,
    required this.strokeWidth,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Continuous smooth rotation
    final baseAngle = progress * 2 * math.pi;

    // Arc length: ~75 degrees (0.42 * pi)
    const sweepAngle = math.pi * 0.42;

    // Primary Arc Paint (Rounded tips)
    final paint1 = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Secondary Opposite Arc Paint
    final paint2 = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw Arc 1 (Top-Left quadrant)
    canvas.drawArc(rect, baseAngle, sweepAngle, false, paint1);

    // Draw Arc 2 (Opposite 180-deg Bottom-Right quadrant)
    canvas.drawArc(rect, baseAngle + math.pi, sweepAngle, false, paint2);
  }

  @override
  bool shouldRepaint(covariant _DualArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
