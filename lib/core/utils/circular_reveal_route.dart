import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// A custom page route that reveals the new page using a circular growth animation
/// starting from a specific [centerOffset].
class CircularRevealPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Offset centerOffset;

  /// Static helper to push with circular reveal from a GlobalKey
  static Future<T?> push<T>(BuildContext context, GlobalKey key, Widget page) {
    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    final Offset center = renderBox != null
        ? renderBox.localToGlobal(renderBox.size.center(Offset.zero))
        : Offset(MediaQuery.of(context).size.width - 50, 60);

    return Navigator.push<T>(
      context,
      CircularRevealPageRoute<T>(page: page, centerOffset: center),
    );
  }

  /// Static helper to push replacement with circular reveal from a GlobalKey or Offset
  static Future<T?> pushReplacement<T>(
    BuildContext context,
    Widget page, {
    GlobalKey? key,
    Offset? centerOffset,
  }) {
    Offset center = centerOffset ?? Offset(MediaQuery.of(context).size.width - 50, 60);

    if (key?.currentContext != null) {
      final RenderBox? renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        center = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
      }
    }

    return Navigator.pushReplacement<T, dynamic>(
      context,
      CircularRevealPageRoute<T>(page: page, centerOffset: center),
    );
  }

  CircularRevealPageRoute({
    required this.page,
    required this.centerOffset,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 550),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          opaque: false,
          barrierDismissible: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final Animation<double> curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );

            return Stack(
              children: [
                // 1. Frosted Backdrop Blur
                AnimatedBuilder(
                  animation: curvedAnimation,
                  builder: (context, _) {
                    return BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: curvedAnimation.value * 6.0,
                        sigmaY: curvedAnimation.value * 6.0,
                      ),
                      child: Container(
                        color: Colors.black.withValues(
                          alpha: curvedAnimation.value * 0.12,
                        ),
                      ),
                    );
                  },
                ),
                // 2. Circular Reveal Clipping
                AnimatedBuilder(
                  animation: curvedAnimation,
                  builder: (context, child) {
                    return ClipPath(
                      clipper: CircularRevealClipper(
                        fraction: curvedAnimation.value,
                        center: centerOffset,
                      ),
                      child: child,
                    );
                  },
                  child: child,
                ),
              ],
            );
          },
        );
}

class CircularRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;

  CircularRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final double maxRadius = _calculateMaxRadius(size, center);
    final double radius = maxRadius * fraction;

    final Path path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    return path;
  }

  double _calculateMaxRadius(Size size, Offset center) {
    final double dx = max(center.dx, size.width - center.dx);
    final double dy = max(center.dy, size.height - center.dy);
    return sqrt(dx * dx + dy * dy);
  }

  @override
  bool shouldReclip(CircularRevealClipper oldClipper) {
    return oldClipper.fraction != fraction || oldClipper.center != center;
  }
}
