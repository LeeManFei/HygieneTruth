import '../../core/utils/outlet_image_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/widgets/status_badge.dart';
import '../../risk/widgets/risk_score_badge.dart';

class RestaurantCard extends StatelessWidget {
  final RestaurantModel restaurant;
  final VoidCallback? onTap;
  final int? rankIndex; // 0 for #1, 1 for #2, 2 for #3, etc.
  final double? userLat;
  final double? userLng;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    this.onTap,
    this.rankIndex,
    this.userLat,
    this.userLng,
  });

  Map<String, dynamic>? _getRankVisuals(int index, {bool hasReviews = false}) {
    switch (index) {
      case 0:
        return {
          'title': hasReviews ? '🥇 1st Place • Top Rated' : '🥇 1st Place • Safe Pick',
          'gradient': const [Color(0xFFF59E0B), Color(0xFFD97706)],
          'border': const Color(0xFFFBBF24),
          'shadow': const Color(0xFFF59E0B),
        };
      case 1:
        return {
          'title': hasReviews ? '🥈 2nd Place • High Star' : '🥈 2nd Place • Safe Pick',
          'gradient': const [Color(0xFF0284C7), Color(0xFF0F766E)],
          'border': const Color(0xFF38BDF8),
          'shadow': const Color(0xFF0284C7),
        };
      case 2:
        return {
          'title': '🥉 3rd Place • Safe Choice',
          'gradient': const [Color(0xFF059669), Color(0xFF047857)],
          'border': const Color(0xFF34D399),
          'shadow': const Color(0xFF059669),
        };
      default:
        return {
          'title': '#${index + 1} Safe Pick',
          'gradient': const [Color(0xFF333333), Color(0xFF1E1E1E)],
          'border': const Color(0xFF666666),
          'shadow': const Color(0xFF1E1E1E),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ratingInfo = RestaurantStoreService.getRatingSync(restaurant.id, restaurantName: restaurant.name);
    final displayRating = ratingInfo.hasReviews ? ratingInfo.ratingText : '0.0';
    final displayReviews = ratingInfo.hasReviews ? '${ratingInfo.totalReviews}' : '0';
    final safetyPct = (100 - restaurant.hygieneRiskScore).clamp(80, 100).toInt();
    final rankVisuals = rankIndex != null ? _getRankVisuals(rankIndex!, hasReviews: ratingInfo.hasReviews) : null;
    final distKm = (userLat != null && userLng != null)
        ? (Geolocator.distanceBetween(userLat!, userLng!, restaurant.latitude, restaurant.longitude) / 1000.0)
        : null;
    final distText = distKm != null ? (distKm < 1.0 ? '${(distKm * 1000).toInt()} m' : '${distKm.toStringAsFixed(1)} km') : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rankIndex == 0
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
          width: rankIndex == 0 ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ??
                () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.restaurantDetail,
                    arguments: restaurant,
                  );
                },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP HERO IMAGE COVER WITH BADGES
                Stack(
                  children: [
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: Image(
                        image: outletImageProvider(restaurant.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9),
                          child: Center(
                            child: Icon(
                              Icons.restaurant_rounded,
                              size: 44,
                              color: isDark ? Colors.white24 : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Gradient Overlay for High Contrast
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.65),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),

                    // Top Left: Ranking Medal or Status Badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: rankVisuals != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: rankVisuals['gradient'] as List<Color>),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: (rankVisuals['border'] as Color).withValues(alpha: 0.8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: (rankVisuals['shadow'] as Color).withValues(alpha: 0.45),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                rankVisuals['title'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            )
                          : StatusBadge.fromStatus(restaurant.status.name, isOnImage: true),
                    ),

                    // Top Right: Risk Score Badge
                    Positioned(
                      top: 10,
                      right: 10,
                      child: RiskScoreBadge(category: restaurant.riskCategory),
                    ),

                    // Bottom Right: Star Rating Overlay Chip
                    Positioned(
                      bottom: 8,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ratingInfo.hasReviews ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 14,
                              color: ratingInfo.hasReviews ? const Color(0xFFFBBF24) : Colors.white70,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ratingInfo.hasReviews
                                  ? '$displayRating ★ ($displayReviews reviews)'
                                  : 'New (No reviews yet)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // 2. RESTAURANT DETAILS & METADATA
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name & Arrow
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              restaurant.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0C2340),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: isDark ? Colors.white38 : Colors.grey.shade400,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),

                      // Category & Hygiene Safety Score Pills
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restaurant_menu_rounded,
                                  size: 12,
                                  color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  restaurant.category,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_rounded, size: 11, color: Color(0xFF059669)),
                                const SizedBox(width: 3),
                                Text(
                                  '$safetyPct% Safe • 0 Reports',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),

                      // Address & Nearby Distance with Pin
                      Row(
                        children: [
                          Icon(
                            distText != null ? Icons.near_me_rounded : Icons.location_on_outlined,
                            size: 13,
                            color: const Color(0xFF0284C7),
                          ),
                          const SizedBox(width: 4),
                          if (distText != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withValues(alpha: isDark ? 0.25 : 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                distText,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              restaurant.address,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }
}
