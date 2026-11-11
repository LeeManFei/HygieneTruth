import 'package:flutter/material.dart';

class GoogleGLogoWidget extends StatelessWidget {
  final double size;
  const GoogleGLogoWidget({super.key, this.size = 20.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: const _OfficialGoogleGLogoPainter(),
      ),
    );
  }
}

/// Official Google 'G' Logo Path Painter using exact Bezier curves
class _OfficialGoogleGLogoPainter extends CustomPainter {
  const _OfficialGoogleGLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final double scale = s / 24.0;

    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;

    // 1. Blue Path (#4285F4)
    paint.color = const Color(0xFF4285F4);
    final Path bluePath = Path()
      ..moveTo(23.745 * scale, 12.27 * scale)
      ..cubicTo(23.745 * scale, 11.47 * scale, 23.675 * scale, 10.7 * scale, 23.545 * scale, 9.96 * scale)
      ..lineTo(12.0 * scale, 9.96 * scale)
      ..lineTo(12.0 * scale, 14.62 * scale)
      ..lineTo(18.58 * scale, 14.62 * scale)
      ..cubicTo(18.3 * scale, 16.14 * scale, 17.44 * scale, 17.43 * scale, 16.15 * scale, 18.29 * scale)
      ..lineTo(16.15 * scale, 21.35 * scale)
      ..lineTo(20.08 * scale, 21.35 * scale)
      ..cubicTo(22.38 * scale, 19.23 * scale, 23.745 * scale, 16.1 * scale, 23.745 * scale, 12.27 * scale)
      ..close();
    canvas.drawPath(bluePath, paint);

    // 2. Green Path (#34A853)
    paint.color = const Color(0xFF34A853);
    final Path greenPath = Path()
      ..moveTo(12.0 * scale, 24.0 * scale)
      ..cubicTo(15.24 * scale, 24.0 * scale, 17.96 * scale, 22.92 * scale, 20.08 * scale, 20.97 * scale)
      ..lineTo(16.15 * scale, 17.91 * scale)
      ..cubicTo(15.07 * scale, 18.63 * scale, 13.66 * scale, 19.06 * scale, 12.0 * scale, 19.06 * scale)
      ..cubicTo(8.87 * scale, 19.06 * scale, 6.18 * scale, 16.92 * scale, 5.22 * scale, 14.04 * scale)
      ..lineTo(1.16 * scale, 14.04 * scale)
      ..lineTo(1.16 * scale, 17.19 * scale)
      ..cubicTo(3.23 * scale, 21.3 * scale, 7.31 * scale, 24.0 * scale, 12.0 * scale, 24.0 * scale)
      ..close();
    canvas.drawPath(greenPath, paint);

    // 3. Yellow Path (#FBBC05)
    paint.color = const Color(0xFFFBBC05);
    final Path yellowPath = Path()
      ..moveTo(5.22 * scale, 14.04 * scale)
      ..cubicTo(4.97 * scale, 13.29 * scale, 4.83 * scale, 12.49 * scale, 4.83 * scale, 11.66 * scale)
      ..cubicTo(4.83 * scale, 10.83 * scale, 4.97 * scale, 10.03 * scale, 5.22 * scale, 9.28 * scale)
      ..lineTo(5.22 * scale, 6.13 * scale)
      ..lineTo(1.16 * scale, 6.13 * scale)
      ..cubicTo(0.42 * scale, 7.6 * scale, 0.0 * scale, 9.26 * scale, 0.0 * scale, 11.66 * scale)
      ..cubicTo(0.0 * scale, 14.06 * scale, 0.42 * scale, 15.72 * scale, 1.16 * scale, 17.19 * scale)
      ..lineTo(5.22 * scale, 14.04 * scale)
      ..close();
    canvas.drawPath(yellowPath, paint);

    // 4. Red Path (#EA4335)
    paint.color = const Color(0xFFEA4335);
    final Path redPath = Path()
      ..moveTo(12.0 * scale, 4.26 * scale)
      ..cubicTo(13.76 * scale, 4.26 * scale, 15.34 * scale, 4.87 * scale, 16.59 * scale, 6.06 * scale)
      ..lineTo(20.17 * scale, 2.48 * scale)
      ..cubicTo(17.95 * scale, 0.42 * scale, 15.24 * scale, 0.0 * scale, 12.0 * scale, 0.0 * scale)
      ..cubicTo(7.31 * scale, 0.0 * scale, 3.23 * scale, 2.7 * scale, 1.16 * scale, 6.81 * scale)
      ..lineTo(5.22 * scale, 9.96 * scale)
      ..cubicTo(6.18 * scale, 7.08 * scale, 8.87 * scale, 4.26 * scale, 12.0 * scale, 4.26 * scale)
      ..close();
    canvas.drawPath(redPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum GoogleButtonStyle {
  outline, // White background with subtle border
  dark,    // Dark grey-black background (#1F1F1F)
  filled,  // Soft filled grey/backdrop white background
}

class GoogleSignInButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double width;
  final GoogleButtonStyle? style;

  const GoogleSignInButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.width = double.infinity,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final GoogleButtonStyle effectiveStyle = style ?? (isDark ? GoogleButtonStyle.dark : GoogleButtonStyle.outline);

    Color bgColor;
    Color textColor;
    Color borderColor;

    switch (effectiveStyle) {
      case GoogleButtonStyle.dark:
        bgColor = const Color(0xFF1F1F1F); // Dark grey-black matching official spec
        textColor = const Color(0xFFF3F4F6);
        borderColor = const Color(0xFF3C3C3C);
        break;
      case GoogleButtonStyle.filled:
        bgColor = const Color(0xFFF2F4F8); // Soft filled backdrop white
        textColor = const Color(0xFF1F1F1F);
        borderColor = Colors.transparent;
        break;
      case GoogleButtonStyle.outline:
        bgColor = Colors.white;
        textColor = const Color(0xFF1F1F1F);
        borderColor = const Color(0xFF747775);
        break;
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: isLoading ? 50 : width,
        height: 50,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: bgColor,
            foregroundColor: textColor,
            side: BorderSide(
              color: borderColor,
              width: borderColor == Colors.transparent ? 0 : 1.2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25), // Pill Stadium shape
            ),
            elevation: 0,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? const SizedBox(
                    key: ValueKey('google_btn_spinner'),
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4285F4),
                    ),
                  )
                : SingleChildScrollView(
                    key: const ValueKey('google_btn_content'),
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GoogleGLogoWidget(size: 20),
                        const SizedBox(width: 12),
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
