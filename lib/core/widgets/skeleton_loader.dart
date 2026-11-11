import 'package:flutter/material.dart';

/// Animated Shimmer Effect Widget
class ShimmerEffect extends StatefulWidget {
  final Widget child;

  const ShimmerEffect({super.key, required this.child});

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: isDark
                  ? const [
                      Color(0xFF1E1E1E),
                      Color(0xFF282828),
                      Color(0xFF1E1E1E),
                    ]
                  : const [
                      Color(0xFFE2E8F0),
                      Color(0xFFF8FAFC),
                      Color(0xFFE2E8F0),
                    ],
              stops: const [0.0, 0.5, 1.0],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              transform: _SlidingGradientTransform(_controller.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0, 0);
  }
}

/// Core Skeleton Box (Atomic Shimmer Placeholder)
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton Card Loader (Simulates Restaurant / Complaint List Item)
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShimmerEffect(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 60, height: 60, borderRadius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 140, height: 16, borderRadius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(width: 100, height: 12, borderRadius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(width: 60, height: 12, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton List Loader (Renders multiple shimmering cards)
class SkeletonListLoader extends StatelessWidget {
  final int itemCount;

  const SkeletonListLoader({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      itemBuilder: (context, index) => const SkeletonCard(),
    );
  }
}

/// Skeleton Dashboard Loader (Simulates Header + Stat Grid + List)
class SkeletonDashboardLoader extends StatelessWidget {
  const SkeletonDashboardLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar Skeleton
            const SkeletonBox(height: 48, borderRadius: 12),
            const SizedBox(height: 16),

            // Chips Row Skeleton
            Row(
              children: const [
                SkeletonBox(width: 80, height: 32, borderRadius: 16),
                SizedBox(width: 8),
                SkeletonBox(width: 80, height: 32, borderRadius: 16),
                SizedBox(width: 8),
                SkeletonBox(width: 80, height: 32, borderRadius: 16),
              ],
            ),
            const SizedBox(height: 20),

            // Featured Card Skeleton
            const SkeletonBox(height: 140, borderRadius: 16),
            const SizedBox(height: 20),

            // Stat Cards 2x2 Grid Skeleton
            Row(
              children: const [
                Expanded(child: SkeletonBox(height: 90, borderRadius: 12)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 90, borderRadius: 12)),
              ],
            ),
            const SizedBox(height: 20),

            // List Items
            const SkeletonCard(),
            const SkeletonCard(),
            const SkeletonCard(),
          ],
        ),
      ),
    );
  }
}

/// Full-Screen Skeleton Wrapper with Refresh / Simulation Control
class SkeletonScreenWrapper extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final Widget? skeletonView;

  const SkeletonScreenWrapper({
    super.key,
    required this.isLoading,
    required this.child,
    this.skeletonView,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return skeletonView ?? const SkeletonDashboardLoader();
    }
    return child;
  }
}
