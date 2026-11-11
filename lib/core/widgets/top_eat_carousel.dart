import '../utils/outlet_image_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/restaurant_model.dart';
import '../routes/app_routes.dart';
import '../services/restaurant_store_service.dart';

class TopEatCarousel extends StatefulWidget {
  final List<RestaurantModel> restaurants;
  final double? userLat;
  final double? userLng;

  const TopEatCarousel({
    super.key,
    required this.restaurants,
    this.userLat,
    this.userLng,
  });

  @override
  State<TopEatCarousel> createState() => _TopEatCarouselState();
}

class _TopEatCarouselState extends State<TopEatCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _autoSwipeTimer;

  @override
  void initState() {
    super.initState();
    _startAutoSwipeTimer();
  }

  void _startAutoSwipeTimer() {
    _autoSwipeTimer?.cancel();
    _autoSwipeTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_pageController.hasClients) return;
      final topSafe = _getTopSafeRestaurants();
      if (topSafe.length <= 1) return;

      final nextPage = (_currentPage + 1) % topSafe.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 650),
        curve: Curves.fastEaseInToSlowEaseOut, // Buttery smooth 60fps transition
      );
    });
  }

  @override
  void dispose() {
    _autoSwipeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  List<RestaurantModel> _getTopSafeRestaurants() {
    final list = widget.restaurants.where((r) => r.status == RestaurantStatus.approved && r.isPubliclyVisible).toList();

    list.sort((a, b) {
      final ratingA = RestaurantStoreService.getRatingSync(a.id, restaurantName: a.name);
      final ratingB = RestaurantStoreService.getRatingSync(b.id, restaurantName: b.name);

      final bool hasReviewsA = ratingA.hasReviews && ratingA.totalReviews > 0;
      final bool hasReviewsB = ratingB.hasReviews && ratingB.totalReviews > 0;

      // 1. Established restaurants with reviews ALWAYS rank before unreviewed/new restaurants
      if (hasReviewsA && !hasReviewsB) return -1;
      if (!hasReviewsA && hasReviewsB) return 1;

      // 2. Both have verified reviews: Sort primarily by rating score and review count
      if (hasReviewsA && hasReviewsB) {
        if ((ratingB.averageRating - ratingA.averageRating).abs() > 0.05) {
          return ratingB.averageRating.compareTo(ratingA.averageRating);
        }
        if (ratingB.totalReviews != ratingA.totalReviews) {
          return ratingB.totalReviews.compareTo(ratingA.totalReviews);
        }
      } else {
        // 3. Neither has reviews: Sort chronologically by registration date (older registered first, newest behind)
        final dateA = DateTime.tryParse(a.createdAt ?? a.lastUpdated) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b.createdAt ?? b.lastUpdated) ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (dateA != dateB) {
          return dateA.compareTo(dateB); // Ascending: older first, newer behind
        }
      }

      // Secondary tie-breaker: hygiene score and proximity
      final distA = (widget.userLat != null && widget.userLng != null)
          ? Geolocator.distanceBetween(widget.userLat!, widget.userLng!, a.latitude, a.longitude) / 1000.0
          : 0.0;
      final distB = (widget.userLat != null && widget.userLng != null)
          ? Geolocator.distanceBetween(widget.userLat!, widget.userLng!, b.latitude, b.longitude) / 1000.0
          : 0.0;

      final scoreA = ((100.0 - a.hygieneRiskScore) * 0.5) - (distA * 0.2) - (a.violationCount * 2.0);
      final scoreB = ((100.0 - b.hygieneRiskScore) * 0.5) - (distB * 0.2) - (b.violationCount * 2.0);

      return scoreB.compareTo(scoreA);
    });

    if (list.isEmpty) {
      return widget.restaurants.take(3).toList();
    }
    return list.take(3).toList();
  }

  Map<String, dynamic> _getRankBadge(int index, RestaurantModel restaurant) {
    final ratingInfo = RestaurantStoreService.getRatingSync(restaurant.id, restaurantName: restaurant.name);
    final ratingStr = ratingInfo.hasReviews
        ? '${ratingInfo.ratingText} ★ (${ratingInfo.totalReviews} reviews)'
        : 'New (0 reviews)';

    switch (index) {
      case 0:
        return {
          'title': ratingInfo.hasReviews ? '🥇 #1 Top Safe Eat' : '🥇 #1 Top Clean Outlet',
          'gradient': const [Color(0xFFF59E0B), Color(0xFFD97706)],
          'border': const Color(0xFFFBBF24),
          'rating': ratingStr,
          'recommendation': '✨ 0 Hygiene Complaints • 100% KKM Cleanliness Pass',
        };
      case 1:
        return {
          'title': ratingInfo.hasReviews ? '🥈 #2 Recommended Clean' : '🥈 #2 Verified Outlet',
          'gradient': const [Color(0xFF0284C7), Color(0xFF0F766E)],
          'border': const Color(0xFF38BDF8),
          'rating': ratingStr,
          'recommendation': '✨ Excellent Sanitation • High Customer Trust',
        };
      case 2:
      default:
        return {
          'title': '🥉 #3 Verified Healthy Pick',
          'gradient': const [Color(0xFF059669), Color(0xFF047857)],
          'border': const Color(0xFF34D399),
          'rating': ratingStr,
          'recommendation': '✨ Verified Clean Prep Area • Grade A Certified',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = _getTopSafeRestaurants();
    if (topSafe.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 205,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) {
              setState(() => _currentPage = idx);
              _startAutoSwipeTimer(); // Reset auto-swipe interval after user swipe
            },
            itemCount: topSafe.length,
            itemBuilder: (context, index) {
              final r = topSafe[index];
              final isSelected = (_currentPage == index);
              final badgeInfo = _getRankBadge(index, r);
              final List<Color> badgeGrad = badgeInfo['gradient'] as List<Color>;
              final Color badgeBorder = badgeInfo['border'] as Color;
              final String badgeTitle = badgeInfo['title'] as String;
              final String ratingStr = badgeInfo['rating'] as String;
              final String recHighlight = badgeInfo['recommendation'] as String;
              final safetyPct = (100 - r.hygieneRiskScore).clamp(80, 100).toInt();

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. BACKGROUND RESTAURANT IMAGE (CRYSTAL CLEAR HD)
                      Image(
                        image: outletImageProvider(r.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFF121212),
                          child: const Icon(Icons.restaurant_rounded, size: 60, color: Colors.white24),
                        ),
                      ),

                      // 2. ULTRA LIGHT BACKDROP FILTER & HIGH-CONTRAST GRADIENT OVERLAY
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 0.2, sigmaY: 0.2), // Reduced for crystal clear image view
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.78),
                                Colors.black.withValues(alpha: 0.40),
                                const Color(0xFF0F766E).withValues(alpha: 0.50),
                              ],
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                            ),
                          ),
                        ),
                      ),

                      // 3. ANIMATED WATERMARK SHIELD ICON (SMOOTH TRANSITION ON SLIDE SELECTION)
                      Positioned(
                        right: -10,
                        bottom: -15,
                        child: AnimatedScale(
                          scale: isSelected ? 1.0 : 0.72,
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: isSelected ? 0.18 : 0.03,
                            duration: const Duration(milliseconds: 500),
                            child: const Icon(
                              Icons.verified_user_rounded,
                              size: 125,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // 4. MAIN CARD CONTENT
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top Row: Rank Badge & Rating Pill
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: badgeGrad),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: badgeBorder.withValues(alpha: 0.8)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: badgeGrad.first.withValues(alpha: 0.45),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        badgeTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white30),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFBBF24)),
                                      const SizedBox(width: 3),
                                      Text(
                                        ratingStr,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Middle: Restaurant Name, Category & Recommendation Highlight
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17.5,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 6,
                                        offset: Offset(0, 1.5),
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${r.category} • $safetyPct% Safe Index',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black38,
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Text(
                                    recHighlight,
                                    style: const TextStyle(
                                      color: Color(0xFFF1F5F9),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            // Bottom Row: "View Details" Button & Animated Safe Verified Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0F766E),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 3,
                                  ),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.restaurantDetail,
                                      arguments: r,
                                    );
                                  },
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 13),
                                  label: const Text(
                                    'View Details',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),

                                // Smooth Transitioning Safe Verified Seal
                                AnimatedOpacity(
                                  opacity: isSelected ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 500),
                                  child: AnimatedScale(
                                    scale: isSelected ? 1.0 : 0.65,
                                    duration: const Duration(milliseconds: 650),
                                    curve: Curves.easeOutBack,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF059669).withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.7)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF059669).withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified_rounded, size: 13, color: Color(0xFF34D399)),
                                          SizedBox(width: 4),
                                          Text(
                                            'KKM Safe Verified',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Animated Page Indicators (Dots)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(topSafe.length, (idx) {
            final isCurrent = (_currentPage == idx);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isCurrent ? 22 : 6,
              height: 5,
              decoration: BoxDecoration(
                color: isCurrent
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFCBD5E1).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
            );
          }),
        ),
      ],
    );
  }
}
