import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Foundational skeleton widget with smooth shimmer animation adapted for Light/Dark mode.
class BaseSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Widget? child;

  const BaseSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade300,
      highlightColor: isDark ? const Color(0xFF282828) : Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: child,
      ),
    );
  }
}

/// Card Skeleton for lists and grid items
class CardSkeleton extends StatelessWidget {
  final double height;
  const CardSkeleton({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: BaseSkeleton(
        width: double.infinity,
        height: height,
        borderRadius: 16,
      ),
    );
  }
}

/// List View Skeleton
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  const ListSkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      itemBuilder: (context, index) => const CardSkeleton(height: 90),
    );
  }
}

class _SkeletonChipRow extends StatelessWidget {
  final double baseWidth;
  final double widthIncrement;
  final double height;

  const _SkeletonChipRow({
    required this.baseWidth,
    this.widthIncrement = 0,
    this.height = 32,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (var index = 0; index < 4; index++) {
      if (index > 0) chips.add(const SizedBox(width: 8));
      chips.add(
        Expanded(
          flex: (baseWidth + (index * widthIncrement)).round(),
          child: BaseSkeleton(
            width: double.infinity,
            height: height,
            borderRadius: height / 2,
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(children: chips),
    );
  }
}

/// Form Screen Skeleton for Reset Password / Auth Forms
class FormSkeleton extends StatelessWidget {
  const FormSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Center(
            child: BaseSkeleton(width: 80, height: 80, borderRadius: 40),
          ),
          const SizedBox(height: 20),
          const Center(
            child: BaseSkeleton(width: 200, height: 26, borderRadius: 8),
          ),
          const SizedBox(height: 12),
          const Center(
            child: BaseSkeleton(width: 260, height: 16, borderRadius: 6),
          ),
          const SizedBox(height: 32),
          const BaseSkeleton(
            width: double.infinity,
            height: 56,
            borderRadius: 16,
          ),
          const SizedBox(height: 20),
          const BaseSkeleton(
            width: double.infinity,
            height: 50,
            borderRadius: 14,
          ),
          const SizedBox(height: 32),
          const BaseSkeleton(
            width: double.infinity,
            height: 80,
            borderRadius: 16,
          ),
        ],
      ),
    );
  }
}

/// Ultra-Premium Profile Screen Skeleton with Top Cover, Avatar, Badges & Section Cards
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Cover Banner + Overlapping Avatar
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              const BaseSkeleton(
                width: double.infinity,
                height: 140,
                borderRadius: 0,
              ),
              Positioned(
                top: 85,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  ),
                  child: const BaseSkeleton(
                    width: 92,
                    height: 92,
                    borderRadius: 46,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 52),

          // 2. User Info Headings Skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const BaseSkeleton(width: 150, height: 22, borderRadius: 6),
                const SizedBox(height: 8),
                const BaseSkeleton(width: 210, height: 14, borderRadius: 4),
                const SizedBox(height: 12),
                const BaseSkeleton(width: 130, height: 28, borderRadius: 14),
                const SizedBox(height: 24),

                // 3. User Detail Info Cards (3 rows)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          BaseSkeleton(width: 36, height: 36, borderRadius: 10),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BaseSkeleton(
                                  width: 80,
                                  height: 10,
                                  borderRadius: 3,
                                ),
                                SizedBox(height: 6),
                                BaseSkeleton(
                                  width: 140,
                                  height: 14,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 20),
                      Row(
                        children: [
                          BaseSkeleton(width: 36, height: 36, borderRadius: 10),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BaseSkeleton(
                                  width: 80,
                                  height: 10,
                                  borderRadius: 3,
                                ),
                                SizedBox(height: 6),
                                BaseSkeleton(
                                  width: 180,
                                  height: 14,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 20),
                      Row(
                        children: [
                          BaseSkeleton(width: 36, height: 36, borderRadius: 10),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BaseSkeleton(
                                  width: 80,
                                  height: 10,
                                  borderRadius: 3,
                                ),
                                SizedBox(height: 6),
                                BaseSkeleton(
                                  width: 120,
                                  height: 14,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Quick Action Cards Skeleton
                BaseSkeleton(
                  width: double.infinity,
                  height: 60,
                  borderRadius: 16,
                ),
                SizedBox(height: 10),
                BaseSkeleton(
                  width: double.infinity,
                  height: 60,
                  borderRadius: 16,
                ),
                SizedBox(height: 10),
                BaseSkeleton(
                  width: double.infinity,
                  height: 60,
                  borderRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/// Dashboard Screen Skeleton
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BaseSkeleton(
            width: double.infinity,
            height: 140,
            borderRadius: 20,
          ),
          const SizedBox(height: 24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BaseSkeleton(width: 140, height: 20),
              BaseSkeleton(width: 60, height: 20),
            ],
          ),
          const SizedBox(height: 16),
          const CardSkeleton(height: 100),
          const CardSkeleton(height: 100),
          const CardSkeleton(height: 100),
        ],
      ),
    );
  }
}

/// Premium Map View Skeleton Loader
class MapSkeletonLoader extends StatelessWidget {
  const MapSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // 1. Shimmering Background Map Canvas
        const BaseSkeleton(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 0,
        ),

        // 2. Top Floating Search Bar & Risk Legend Shimmer
        const Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // Search Input Bar Shimmer
              BaseSkeleton(
                width: double.infinity,
                height: 52,
                borderRadius: 28,
              ),
              SizedBox(height: 8),
              // Risk Legend Bar Shimmer
              BaseSkeleton(
                width: double.infinity,
                height: 34,
                borderRadius: 20,
              ),
            ],
          ),
        ),

        // 3. Right Floating Map Controls FAB Shimmer
        const Positioned(
          right: 16,
          bottom: 260,
          child: Column(
            children: [
              BaseSkeleton(width: 44, height: 44, borderRadius: 22),
              SizedBox(height: 12),
              BaseSkeleton(width: 44, height: 44, borderRadius: 22),
              SizedBox(height: 12),
              BaseSkeleton(width: 44, height: 44, borderRadius: 22),
            ],
          ),
        ),

        // 4. Bottom Restaurant Card Carousel Shimmer Preview
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BaseSkeleton(
                  width: double.infinity,
                  height: 140,
                  borderRadius: 16,
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    BaseSkeleton(width: 180, height: 20, borderRadius: 6),
                    BaseSkeleton(width: 50, height: 20, borderRadius: 10),
                  ],
                ),
                SizedBox(height: 8),
                BaseSkeleton(width: 220, height: 14, borderRadius: 4),
                SizedBox(height: 12),
                Row(
                  children: [
                    BaseSkeleton(width: 90, height: 24, borderRadius: 12),
                    SizedBox(width: 8),
                    BaseSkeleton(width: 110, height: 24, borderRadius: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Admin Portal Dashboard Skeleton Loader
class AdminDashboardSkeleton extends StatelessWidget {
  const AdminDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark Header Summary Banner Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 110,
            borderRadius: 16,
          ),
          const SizedBox(height: 24),

          // Admin Grid Title Shimmer
          const BaseSkeleton(width: 120, height: 18, borderRadius: 4),
          const SizedBox(height: 12),

          // 2x2 Grid Stat Cards Shimmer
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: const [
              BaseSkeleton(
                width: double.infinity,
                height: 110,
                borderRadius: 16,
              ),
              BaseSkeleton(
                width: double.infinity,
                height: 110,
                borderRadius: 16,
              ),
              BaseSkeleton(
                width: double.infinity,
                height: 110,
                borderRadius: 16,
              ),
              BaseSkeleton(
                width: double.infinity,
                height: 110,
                borderRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Admin Tools Title Shimmer
          const BaseSkeleton(width: 120, height: 18, borderRadius: 4),
          const SizedBox(height: 12),

          // Admin Tool Tiles Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 60,
            borderRadius: 12,
          ),
          const SizedBox(height: 10),
          const BaseSkeleton(
            width: double.infinity,
            height: 60,
            borderRadius: 12,
          ),
          const SizedBox(height: 10),
          const BaseSkeleton(
            width: double.infinity,
            height: 60,
            borderRadius: 12,
          ),
          const SizedBox(height: 10),
          const BaseSkeleton(
            width: double.infinity,
            height: 60,
            borderRadius: 12,
          ),
        ],
      ),
    );
  }
}

/// Outlet Review / Verification Detail Screen Skeleton Loader (including Map Shimmer)
class OutletReviewSkeleton extends StatelessWidget {
  const OutletReviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Hero Outlet Image Card Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 140,
            borderRadius: 20,
          ),
          const SizedBox(height: 14),
          const BaseSkeleton(width: 180, height: 24, borderRadius: 6),
          const SizedBox(height: 8),
          const BaseSkeleton(width: 120, height: 20, borderRadius: 8),
          const SizedBox(height: 24),

          // 2. Application Details Header & Card Shimmer
          const Row(
            children: [
              BaseSkeleton(width: 20, height: 20, borderRadius: 4),
              SizedBox(width: 8),
              BaseSkeleton(width: 150, height: 18, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 10),
          const BaseSkeleton(
            width: double.infinity,
            height: 110,
            borderRadius: 16,
          ),
          const SizedBox(height: 24),

          // 3. Map Location Header & Embedded Map Canvas Shimmer
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  BaseSkeleton(width: 20, height: 20, borderRadius: 4),
                  SizedBox(width: 8),
                  BaseSkeleton(width: 120, height: 18, borderRadius: 4),
                ],
              ),
              BaseSkeleton(width: 110, height: 22, borderRadius: 6),
            ],
          ),
          const SizedBox(height: 10),
          // Embedded Map Shimmer Container
          const BaseSkeleton(
            width: double.infinity,
            height: 200,
            borderRadius: 16,
          ),
          const SizedBox(height: 24),

          // 4. Official Assessment Input Box Shimmer
          const BaseSkeleton(width: 180, height: 16, borderRadius: 4),
          const SizedBox(height: 8),
          const BaseSkeleton(
            width: double.infinity,
            height: 80,
            borderRadius: 14,
          ),
          const SizedBox(height: 24),

          // 5. Action Buttons Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 50,
            borderRadius: 14,
          ),
          const SizedBox(height: 10),
          const BaseSkeleton(
            width: double.infinity,
            height: 50,
            borderRadius: 14,
          ),
          const SizedBox(height: 10),
          const BaseSkeleton(
            width: double.infinity,
            height: 50,
            borderRadius: 14,
          ),
        ],
      ),
    );
  }
}

/// Notification Card Skeleton for Notification Center (100% Synced with real card layout)
class NotificationCardSkeleton extends StatelessWidget {
  const NotificationCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Shimmer.fromColors(
        baseColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
        highlightColor: isDark ? const Color(0xFF282828) : Colors.grey.shade50,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121212) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon avatar skeleton
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF282828)
                      : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Title bar
                        Container(
                          width: 150,
                          height: 14,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF282828)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Date bar
                        Container(
                          width: 60,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF282828)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Message line 1
                    Container(
                      width: double.infinity,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF282828)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Message line 2
                    Container(
                      width: 180,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF282828)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification List Skeleton for Notification Center TabBarView
class NotificationListSkeleton extends StatelessWidget {
  final int itemCount;
  const NotificationListSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) => const NotificationCardSkeleton(),
    );
  }
}

/// Assigned Cases List Screen Skeleton (with Stats, Search, and Cards)
class AssignedCasesSkeleton extends StatelessWidget {
  final int itemCount;
  const AssignedCasesSkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          // Top Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 50,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 50,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 50,
                    borderRadius: 12,
                  ),
                ),
              ],
            ),
          ),
          // Search Bar
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: BaseSkeleton(
              width: double.infinity,
              height: 44,
              borderRadius: 12,
            ),
          ),
          // Filter Chips Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const _SkeletonChipRow(baseWidth: 70, widthIncrement: 10),
          ),
          const SizedBox(height: 8),
          // List Cards
          ...List.generate(
            itemCount,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BaseSkeleton(width: 44, height: 44, borderRadius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BaseSkeleton(
                          width: 160,
                          height: 16,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 8),
                        const BaseSkeleton(
                          width: 220,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 6),
                        const BaseSkeleton(
                          width: 130,
                          height: 11,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 8),
                        const BaseSkeleton(
                          width: 80,
                          height: 20,
                          borderRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Case Details Screen Skeleton
class CaseDetailsSkeleton extends StatelessWidget {
  const CaseDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          BaseSkeleton(width: double.infinity, height: 110, borderRadius: 18),
          SizedBox(height: 16),
          // Description Card
          BaseSkeleton(width: double.infinity, height: 120, borderRadius: 16),
          SizedBox(height: 16),
          // Evidence Photos Card
          BaseSkeleton(width: double.infinity, height: 240, borderRadius: 16),
          SizedBox(height: 16),
          // GPS Map Card
          BaseSkeleton(width: double.infinity, height: 220, borderRadius: 16),
          SizedBox(height: 24),
          // Action Buttons
          BaseSkeleton(width: double.infinity, height: 48, borderRadius: 12),
          SizedBox(height: 12),
          BaseSkeleton(width: double.infinity, height: 48, borderRadius: 12),
        ],
      ),
    );
  }
}

/// Settings & Security History Screen Skeleton
class SettingsHistorySkeleton extends StatelessWidget {
  final int itemCount;
  const SettingsHistorySkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          // Top Summary Banner
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: BaseSkeleton(
              width: double.infinity,
              height: 95,
              borderRadius: 16,
            ),
          ),
          // Search Input
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: BaseSkeleton(
              width: double.infinity,
              height: 42,
              borderRadius: 12,
            ),
          ),
          // Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: const _SkeletonChipRow(baseWidth: 75),
          ),
          const SizedBox(height: 8),
          // Timeline Cards
          ...List.generate(
            itemCount,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BaseSkeleton(width: 40, height: 40, borderRadius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            BaseSkeleton(
                              width: 140,
                              height: 15,
                              borderRadius: 4,
                            ),
                            BaseSkeleton(
                              width: 60,
                              height: 16,
                              borderRadius: 6,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const BaseSkeleton(
                          width: double.infinity,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 4),
                        const BaseSkeleton(
                          width: 180,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 8),
                        const BaseSkeleton(
                          width: 90,
                          height: 10,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Enforcement Action History Screen Skeleton
class ActionHistorySkeleton extends StatelessWidget {
  final int itemCount;
  const ActionHistorySkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          // Top Summary Metrics
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 52,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 52,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 52,
                    borderRadius: 12,
                  ),
                ),
              ],
            ),
          ),
          // Search Input
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: BaseSkeleton(
              width: double.infinity,
              height: 42,
              borderRadius: 12,
            ),
          ),
          // Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const _SkeletonChipRow(baseWidth: 70, widthIncrement: 10),
          ),
          const SizedBox(height: 8),
          // Cards
          ...List.generate(
            itemCount,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BaseSkeleton(width: 44, height: 44, borderRadius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            BaseSkeleton(
                              width: 160,
                              height: 16,
                              borderRadius: 4,
                            ),
                            BaseSkeleton(
                              width: 70,
                              height: 18,
                              borderRadius: 6,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const BaseSkeleton(
                          width: 220,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 6),
                        const BaseSkeleton(
                          width: 120,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 8),
                        const BaseSkeleton(
                          width: 90,
                          height: 10,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recommendation Home Screen Skeleton Loader
class RecommendationSkeleton extends StatelessWidget {
  const RecommendationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Hero Recommendation Banner Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 135,
            borderRadius: 20,
          ),
          const SizedBox(height: 16),

          // 2. Search & GPS Filter Row Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 48,
            borderRadius: 16,
          ),
          const SizedBox(height: 14),

          // 3. Distance Category Filter Pills Shimmer
          const _SkeletonChipRow(baseWidth: 75, widthIncrement: 8),
          const SizedBox(height: 20),

          // 4. Section Header Shimmer
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BaseSkeleton(width: 170, height: 18, borderRadius: 4),
              BaseSkeleton(width: 60, height: 14, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 14),

          // 5. Restaurant Card Skeletons (3 items)
          ...List.generate(
            3,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo Thumbnail
                  BaseSkeleton(width: 90, height: 90, borderRadius: 14),
                  SizedBox(width: 12),
                  // Details Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            BaseSkeleton(
                              width: 130,
                              height: 16,
                              borderRadius: 4,
                            ),
                            BaseSkeleton(
                              width: 45,
                              height: 14,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        BaseSkeleton(width: 100, height: 12, borderRadius: 4),
                        SizedBox(height: 8),
                        BaseSkeleton(width: 160, height: 11, borderRadius: 4),
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            BaseSkeleton(
                              width: 80,
                              height: 20,
                              borderRadius: 6,
                            ),
                            BaseSkeleton(
                              width: 70,
                              height: 20,
                              borderRadius: 6,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Risk Ranking List Screen Skeleton Loader
class RiskRankingSkeleton extends StatelessWidget {
  const RiskRankingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top League Ribbon Header Shimmer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF282828)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 12,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 12,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 12,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: BaseSkeleton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 12,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. Search Input Shimmer
                const BaseSkeleton(
                  width: double.infinity,
                  height: 48,
                  borderRadius: 14,
                ),
                const SizedBox(height: 14),

                // 3. Period Tabs Toggle Shimmer (Today vs Week)
                const BaseSkeleton(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 14,
                ),
                const SizedBox(height: 12),

                // 4. League Tier Filter Chips Shimmer
                const _SkeletonChipRow(
                  baseWidth: 70,
                  widthIncrement: 6,
                  height: 30,
                ),
                const SizedBox(height: 16),

                // 5. Ranked Outlet Cards (4 items)
                ...List.generate(
                  4,
                  (index) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: const Row(
                      children: [
                        // Rank Badge Pill
                        BaseSkeleton(width: 34, height: 34, borderRadius: 17),
                        SizedBox(width: 12),
                        // Outlet Thumbnail
                        BaseSkeleton(width: 52, height: 52, borderRadius: 12),
                        SizedBox(width: 12),
                        // Outlet Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  BaseSkeleton(
                                    width: 120,
                                    height: 15,
                                    borderRadius: 4,
                                  ),
                                  BaseSkeleton(
                                    width: 60,
                                    height: 20,
                                    borderRadius: 8,
                                  ),
                                ],
                              ),
                              SizedBox(height: 6),
                              BaseSkeleton(
                                width: 150,
                                height: 11,
                                borderRadius: 4,
                              ),
                              SizedBox(height: 6),
                              BaseSkeleton(
                                width: 90,
                                height: 11,
                                borderRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Restaurant Detail Screen Skeleton Loader
class RestaurantDetailSkeleton extends StatelessWidget {
  const RestaurantDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Cover / Carousel Hero Shimmer
          Stack(
            children: [
              const BaseSkeleton(
                width: double.infinity,
                height: 220,
                borderRadius: 0,
              ),
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black54 : Colors.white70,
                    shape: BoxShape.circle,
                  ),
                  child: const BaseSkeleton(
                    width: 36,
                    height: 36,
                    borderRadius: 18,
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black54 : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                      child: const BaseSkeleton(
                        width: 36,
                        height: 36,
                        borderRadius: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black54 : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                      child: const BaseSkeleton(
                        width: 36,
                        height: 36,
                        borderRadius: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. Restaurant Title & Category
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    BaseSkeleton(width: 200, height: 24, borderRadius: 6),
                    BaseSkeleton(width: 50, height: 22, borderRadius: 8),
                  ],
                ),
                const SizedBox(height: 8),
                const BaseSkeleton(width: 140, height: 14, borderRadius: 4),
                const SizedBox(height: 10),
                const BaseSkeleton(
                  width: double.infinity,
                  height: 12,
                  borderRadius: 4,
                ),
                const SizedBox(height: 16),

                // 3. Hygiene Risk Gauge / MOH Decree Card Shimmer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          BaseSkeleton(width: 140, height: 16, borderRadius: 4),
                          BaseSkeleton(width: 80, height: 22, borderRadius: 10),
                        ],
                      ),
                      SizedBox(height: 12),
                      BaseSkeleton(
                        width: double.infinity,
                        height: 8,
                        borderRadius: 4,
                      ),
                      SizedBox(height: 12),
                      BaseSkeleton(width: 220, height: 12, borderRadius: 4),
                      SizedBox(height: 6),
                      BaseSkeleton(width: 180, height: 12, borderRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 4. Tab Bar Shimmer
                const Row(
                  children: [
                    Expanded(
                      child: BaseSkeleton(
                        width: double.infinity,
                        height: 40,
                        borderRadius: 12,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: BaseSkeleton(
                        width: double.infinity,
                        height: 40,
                        borderRadius: 12,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: BaseSkeleton(
                        width: double.infinity,
                        height: 40,
                        borderRadius: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 5. Operating Details Card Shimmer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          BaseSkeleton(width: 32, height: 32, borderRadius: 8),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BaseSkeleton(
                                  width: 80,
                                  height: 10,
                                  borderRadius: 3,
                                ),
                                SizedBox(height: 6),
                                BaseSkeleton(
                                  width: 160,
                                  height: 13,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 20),
                      Row(
                        children: [
                          BaseSkeleton(width: 32, height: 32, borderRadius: 8),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BaseSkeleton(
                                  width: 80,
                                  height: 10,
                                  borderRadius: 3,
                                ),
                                SizedBox(height: 6),
                                BaseSkeleton(
                                  width: 200,
                                  height: 13,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Action Button Shimmer
                const BaseSkeleton(
                  width: double.infinity,
                  height: 52,
                  borderRadius: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Owner Portal Dashboard Skeleton Loader
class OwnerDashboardSkeleton extends StatelessWidget {
  const OwnerDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Store Status Header Card
          const BaseSkeleton(
            width: double.infinity,
            height: 125,
            borderRadius: 20,
          ),
          const SizedBox(height: 16),

          // 2. Risk Evaluation / Inspection Banner Shimmer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              ),
            ),
            child: const Row(
              children: [
                BaseSkeleton(width: 44, height: 44, borderRadius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BaseSkeleton(width: 140, height: 15, borderRadius: 4),
                      SizedBox(height: 6),
                      BaseSkeleton(width: 190, height: 12, borderRadius: 4),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                BaseSkeleton(width: 50, height: 24, borderRadius: 8),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 3. 2x2 Metric Grid Cards Shimmer
          const BaseSkeleton(width: 120, height: 18, borderRadius: 4),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: const [
              BaseSkeleton(
                width: double.infinity,
                height: 100,
                borderRadius: 16,
              ),
              BaseSkeleton(
                width: double.infinity,
                height: 100,
                borderRadius: 16,
              ),
              BaseSkeleton(
                width: double.infinity,
                height: 100,
                borderRadius: 16,
              ),
              BaseSkeleton(
                width: double.infinity,
                height: 100,
                borderRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4. Quick Action Button Row Shimmer
          const Row(
            children: [
              Expanded(
                child: BaseSkeleton(
                  width: double.infinity,
                  height: 48,
                  borderRadius: 12,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: BaseSkeleton(
                  width: double.infinity,
                  height: 48,
                  borderRadius: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 5. Recent Warnings & Customer Reports Section Shimmer
          const BaseSkeleton(width: 150, height: 18, borderRadius: 4),
          const SizedBox(height: 10),
          ...List.generate(
            2,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Row(
                children: [
                  BaseSkeleton(width: 38, height: 38, borderRadius: 10),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BaseSkeleton(width: 130, height: 14, borderRadius: 4),
                        SizedBox(height: 6),
                        BaseSkeleton(width: 170, height: 11, borderRadius: 4),
                      ],
                    ),
                  ),
                  BaseSkeleton(width: 60, height: 20, borderRadius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Complaint History / User Reports Screen Skeleton Loader
class ComplaintHistorySkeleton extends StatelessWidget {
  final int itemCount;
  const ComplaintHistorySkeleton({super.key, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Summary Banner Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 90,
            borderRadius: 18,
          ),
          const SizedBox(height: 16),

          // 2. Filter Status Chips Shimmer
          const _SkeletonChipRow(baseWidth: 72, widthIncrement: 6),
          const SizedBox(height: 16),

          // 3. Complaint Cards List
          ...List.generate(
            itemCount,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      BaseSkeleton(width: 110, height: 14, borderRadius: 4),
                      BaseSkeleton(width: 75, height: 20, borderRadius: 8),
                    ],
                  ),
                  SizedBox(height: 10),
                  BaseSkeleton(width: 170, height: 16, borderRadius: 4),
                  SizedBox(height: 8),
                  BaseSkeleton(
                    width: double.infinity,
                    height: 12,
                    borderRadius: 4,
                  ),
                  SizedBox(height: 6),
                  BaseSkeleton(width: 200, height: 12, borderRadius: 4),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      BaseSkeleton(width: 50, height: 50, borderRadius: 10),
                      SizedBox(width: 8),
                      BaseSkeleton(width: 50, height: 50, borderRadius: 10),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      BaseSkeleton(width: 90, height: 12, borderRadius: 4),
                      BaseSkeleton(width: 80, height: 14, borderRadius: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// User Accounts Management Screen Skeleton Loader
class UserAccountsSkeleton extends StatelessWidget {
  final int itemCount;
  const UserAccountsSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 1. Top Search Bar Shimmer
          const BaseSkeleton(
            width: double.infinity,
            height: 46,
            borderRadius: 14,
          ),
          const SizedBox(height: 12),

          // 2. Role Category Chips Shimmer
          const _SkeletonChipRow(baseWidth: 75, widthIncrement: 6),
          const SizedBox(height: 14),

          // 3. User Item Tiles Shimmer
          ...List.generate(
            itemCount,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Row(
                children: [
                  BaseSkeleton(width: 44, height: 44, borderRadius: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BaseSkeleton(width: 140, height: 15, borderRadius: 4),
                        SizedBox(height: 6),
                        BaseSkeleton(width: 180, height: 12, borderRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  BaseSkeleton(width: 70, height: 22, borderRadius: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
