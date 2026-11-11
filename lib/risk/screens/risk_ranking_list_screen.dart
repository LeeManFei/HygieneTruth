import '../../core/utils/outlet_image_provider.dart';
import '../../core/widgets/customer_refresh_indicator.dart';
import 'package:flutter/material.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';

import '../../core/widgets/shimmer_skeletons.dart';

enum RankingLeagueTier { bronze, silver, gold, platinum }

class RiskRankingListScreen extends StatefulWidget {
  const RiskRankingListScreen({super.key});

  @override
  State<RiskRankingListScreen> createState() => _RiskRankingListScreenState();
}

class _RiskRankingListScreenState extends State<RiskRankingListScreen> {
  String _selectedPeriod = 'Today'; // 'Today' or 'Week'
  String _selectedTierFilter = 'All'; // 'All', 'Platinum', 'Gold', 'Silver', 'Bronze'

  @override
  void initState() {
    super.initState();
    _syncCloudData();
  }

  Future<void> _syncCloudData() async {
    await Future.wait([
      RestaurantStoreService.fetchAllRestaurants(forceRefresh: true),
      RestaurantStoreService.fetchAllComplaints(forceRefresh: true),
      RestaurantStoreService.fetchAllInspections(),
    ]);
    if (mounted) setState(() {});
  }

  // Determine League Tier based on Hygiene Risk Score:
  RankingLeagueTier _getRestaurantTier(RestaurantModel r) {
    if (r.hygieneRiskScore < 15.0) {
      return RankingLeagueTier.platinum;
    }
    if (r.hygieneRiskScore < 30.0) {
      return RankingLeagueTier.gold;
    }
    if (r.hygieneRiskScore <= 60.0) {
      return RankingLeagueTier.silver;
    }
    return RankingLeagueTier.bronze;
  }

  String _getTierName(RankingLeagueTier tier) {
    switch (tier) {
      case RankingLeagueTier.bronze:
        return 'Bronze';
      case RankingLeagueTier.silver:
        return 'Silver';
      case RankingLeagueTier.gold:
        return 'Gold';
      case RankingLeagueTier.platinum:
        return 'Platinum';
    }
  }

  Color _getTierColor(RankingLeagueTier tier) {
    switch (tier) {
      case RankingLeagueTier.bronze:
        return const Color(0xFFD97706); // Bronze Amber
      case RankingLeagueTier.silver:
        return const Color(0xFF64748B); // Silver Slate
      case RankingLeagueTier.gold:
        return const Color(0xFFEAB308); // Gold Yellow
      case RankingLeagueTier.platinum:
        return const Color(0xFF0EA5E9); // Platinum Cyan Blue
    }
  }

  Color _getTierBgColor(RankingLeagueTier tier) {
    switch (tier) {
      case RankingLeagueTier.bronze:
        return const Color(0xFFFEF3C7);
      case RankingLeagueTier.silver:
        return const Color(0xFFF1F5F9);
      case RankingLeagueTier.gold:
        return const Color(0xFFFEF9C3);
      case RankingLeagueTier.platinum:
        return const Color(0xFFE0F2FE);
    }
  }

  IconData _getTierIcon(RankingLeagueTier tier) {
    return Icons.military_tech_rounded;
  }

  void _showRankingInfoDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          elevation: 16,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.info_outline_rounded, color: AppTheme.primaryColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ranking Criteria Info',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: isDark ? Colors.white60 : Colors.grey, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Outlets are categorized into tiers based on verified hygiene risk scores and ratings (lower score is cleaner):',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade600, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    tierName: 'Platinum Tier',
                    riskTitle: 'Elite Clean (< 15.0)',
                    subtitle: 'Pristine hygiene score with flawless audit record.',
                    color: const Color(0xFF0EA5E9),
                    bgColor: isDark ? const Color(0xFF0C4A6E).withValues(alpha: 0.35) : const Color(0xFFE0F2FE),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    tierName: 'Gold Tier',
                    riskTitle: 'Low Risk (15.0 - 30.0)',
                    subtitle: 'High sanitation standards & clean dining environment.',
                    color: const Color(0xFFEAB308),
                    bgColor: isDark ? const Color(0xFF713F12).withValues(alpha: 0.35) : const Color(0xFFFEF9C3),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    tierName: 'Silver Tier',
                    riskTitle: 'Moderate Risk (30.0 - 60.0)',
                    subtitle: 'Standard hygiene standards with periodic monitoring.',
                    color: const Color(0xFF64748B),
                    bgColor: isDark ? const Color(0xFF282828).withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    tierName: 'Bronze Tier',
                    riskTitle: 'High Risk (> 60.0)',
                    subtitle: 'Requires immediate sanitation inspection & action.',
                    color: const Color(0xFFD97706),
                    bgColor: isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Got It',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow({
    required String tierName,
    required String riskTitle,
    required String subtitle,
    required Color color,
    required Color bgColor,
    bool isDark = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.5 : 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.military_tech_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: tierName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: color,
                    ),
                    children: [
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '($riskTitle)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Calculate Today's Real-Time Safety Score (higher is cleaner, 0 - 100)
  double _getTodayScore(RestaurantModel r) {
    final base = (100.0 - (r.hygieneRiskScore * 0.85)).clamp(0.0, 100.0);
    final ratingInfo = RestaurantStoreService.getRatingSync(r.id, restaurantName: r.name);
    final ratingBonus = ratingInfo.averageRating > 0 ? (ratingInfo.averageRating / 5.0) * 4.0 : 2.0;
    final violationPenalty = r.violationCount * 3.5;
    return (base + ratingBonus - violationPenalty).clamp(15.0, 99.9);
  }

  // Calculate 7-Day Rolling Consistency Index (higher is more reliable, 0 - 100)
  double _getWeekScore(RestaurantModel r) {
    final base = (100.0 - (r.hygieneRiskScore * 0.75)).clamp(0.0, 100.0);
    final ratingInfo = RestaurantStoreService.getRatingSync(r.id, restaurantName: r.name);
    final ratingBonus = ratingInfo.averageRating > 0 ? (ratingInfo.averageRating / 5.0) * 8.0 : 4.0;
    final reviewTrust = ratingInfo.totalReviews > 0 ? (ratingInfo.totalReviews.clamp(1, 10) * 0.3) : 0.5;
    final streakBonus = (r.violationCount == 0 ? 5.5 : -(r.violationCount * 4.0));
    return (base + ratingBonus + reviewTrust + streakBonus).clamp(10.0, 100.0);
  }

  List<RestaurantModel> _getRankedList(List<RestaurantModel> sourceList) {
    final List<RestaurantModel> list = List.from(sourceList);

    if (_selectedPeriod == 'Week') {
      list.sort((a, b) {
        // 1. Primary: 7-Day Consistency Score (descending)
        final scoreA = _getWeekScore(a);
        final scoreB = _getWeekScore(b);
        final scoreComp = scoreB.compareTo(scoreA);
        if (scoreComp != 0) return scoreComp;

        // 2. Secondary: Customer Average Rating (descending)
        final ratingA = RestaurantStoreService.getRatingSync(a.id, restaurantName: a.name);
        final ratingB = RestaurantStoreService.getRatingSync(b.id, restaurantName: b.name);
        final ratingComp = ratingB.averageRating.compareTo(ratingA.averageRating);
        if (ratingComp != 0) return ratingComp;

        // 3. Tertiary: Total Reviews count (descending)
        final countComp = ratingB.totalReviews.compareTo(ratingA.totalReviews);
        if (countComp != 0) return countComp;

        // 4. Quaternary: Violation Count (ascending - fewer violations first)
        final violComp = a.violationCount.compareTo(b.violationCount);
        if (violComp != 0) return violComp;

        // 5. Quinary: Baseline Risk Score (ascending - lower risk first)
        final riskComp = a.hygieneRiskScore.compareTo(b.hygieneRiskScore);
        if (riskComp != 0) return riskComp;

        // 6. Deterministic Name & ID Tie-Breakers (Identical across all devices)
        final nameComp = a.name.toLowerCase().trim().compareTo(b.name.toLowerCase().trim());
        if (nameComp != 0) return nameComp;

        return a.id.compareTo(b.id);
      });
    } else {
      list.sort((a, b) {
        // 1. Primary: Today's Safety Score (descending)
        final scoreA = _getTodayScore(a);
        final scoreB = _getTodayScore(b);
        final scoreComp = scoreB.compareTo(scoreA);
        if (scoreComp != 0) return scoreComp;

        // 2. Secondary: Customer Average Rating (descending)
        final ratingA = RestaurantStoreService.getRatingSync(a.id, restaurantName: a.name);
        final ratingB = RestaurantStoreService.getRatingSync(b.id, restaurantName: b.name);
        final ratingComp = ratingB.averageRating.compareTo(ratingA.averageRating);
        if (ratingComp != 0) return ratingComp;

        // 3. Tertiary: Baseline Risk Score (ascending - cleaner first)
        final riskComp = a.hygieneRiskScore.compareTo(b.hygieneRiskScore);
        if (riskComp != 0) return riskComp;

        // 4. Quaternary: Violation Count (ascending)
        final violComp = a.violationCount.compareTo(b.violationCount);
        if (violComp != 0) return violComp;

        // 5. Quinary: Total Reviews count (descending)
        final countComp = ratingB.totalReviews.compareTo(ratingA.totalReviews);
        if (countComp != 0) return countComp;

        // 6. Deterministic Name & ID Tie-Breakers (Identical across all devices)
        final nameComp = a.name.toLowerCase().trim().compareTo(b.name.toLowerCase().trim());
        if (nameComp != 0) return nameComp;

        return a.id.compareTo(b.id);
      });
    }

    if (_selectedTierFilter != 'All') {
      return list.where((r) {
        final tier = _getRestaurantTier(r);
        return _getTierName(tier).toLowerCase() == _selectedTierFilter.toLowerCase();
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Risk Rankings',
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: isDark ? Colors.white : AppTheme.navyColor),
            tooltip: 'Ranking Criteria Info',
            onPressed: _showRankingInfoDialog,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomerRefreshIndicator(
        onRefresh: _syncCloudData,
        child: ValueListenableBuilder<List<RestaurantModel>>(
          valueListenable: RestaurantStoreService.restaurantsNotifier,
          builder: (context, allRestaurants, _) {
            if (allRestaurants.isEmpty) {
              return const RiskRankingSkeleton();
            }

            final rankedList = _getRankedList(allRestaurants);

            // Calculate counts per tier for badges
            int bronzeCount = 0;
            int silverCount = 0;
            int goldCount = 0;
            int platinumCount = 0;

            for (final r in allRestaurants) {
              final tier = _getRestaurantTier(r);
              switch (tier) {
                case RankingLeagueTier.bronze:
                  bronzeCount++;
                  break;
                case RankingLeagueTier.silver:
                  silverCount++;
                  break;
                case RankingLeagueTier.gold:
                  goldCount++;
                  break;
                case RankingLeagueTier.platinum:
                  platinumCount++;
                  break;
              }
            }

            final RestaurantModel? firstPlace = rankedList.isNotEmpty ? rankedList[0] : null;
            final RestaurantModel? secondPlace = rankedList.length > 1 ? rankedList[1] : null;
            final RestaurantModel? thirdPlace = rankedList.length > 2 ? rankedList[2] : null;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // 1. TOP LEAGUE BADGES RIBBON HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? const Color(0xFF282828) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildLeagueRibbonBadge('Platinum', platinumCount, const Color(0xFF0EA5E9), isDark),
                      _buildLeagueRibbonBadge('Gold', goldCount, const Color(0xFFEAB308), isDark),
                      _buildLeagueRibbonBadge('Silver', silverCount, const Color(0xFF64748B), isDark),
                      _buildLeagueRibbonBadge('Bronze', bronzeCount, const Color(0xFFD97706), isDark),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 2. SEGMENTED TOGGLE PILL: TODAY vs WEEK
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282828) : const Color(0xFFE2E8F0).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_selectedPeriod != 'Today') {
                                setState(() {
                                  _selectedPeriod = 'Today';
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: _selectedPeriod == 'Today' ? const Color(0xFF00A88F) : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: _selectedPeriod == 'Today'
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF00A88F).withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 16,
                                    color: _selectedPeriod == 'Today'
                                        ? Colors.white
                                        : (isDark ? Colors.white70 : Colors.grey.shade700),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Today',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedPeriod == 'Today'
                                          ? Colors.white
                                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_selectedPeriod != 'Week') {
                                setState(() {
                                  _selectedPeriod = 'Week';
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: _selectedPeriod == 'Week' ? const Color(0xFF00A88F) : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: _selectedPeriod == 'Week'
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF00A88F).withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 15,
                                    color: _selectedPeriod == 'Week'
                                        ? Colors.white
                                        : (isDark ? Colors.white70 : Colors.grey.shade700),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Week',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedPeriod == 'Week'
                                          ? Colors.white
                                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 3. TOP WINNERS PODIUM GRAPHIC (Leaderboard Top 3)
                if (rankedList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _selectedPeriod == 'Today' ? Icons.emoji_events_rounded : Icons.military_tech_rounded,
                                    color: const Color(0xFFEAB308),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Leaderboard ($_selectedPeriod)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _selectedPeriod == 'Today'
                                      ? const Color(0xFF00A88F).withValues(alpha: 0.12)
                                      : const Color(0xFF6366F1).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _selectedPeriod == 'Today' ? '⚡ Today\'s Top Outlets' : '🏆 Weekly Champions',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedPeriod == 'Today' ? const Color(0xFF00A88F) : const Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // 2nd Place (Left)
                              if (secondPlace != null)
                                Expanded(
                                  child: _buildPodiumItem(
                                    restaurant: secondPlace,
                                    rank: 2,
                                    pillarHeight: 85,
                                    isDark: isDark,
                                  ),
                                )
                              else
                                const Spacer(),
                              const SizedBox(width: 8),

                              // 1st Place (Center - Highest)
                              if (firstPlace != null)
                                Expanded(
                                  child: _buildPodiumItem(
                                    restaurant: firstPlace,
                                    rank: 1,
                                    pillarHeight: 115,
                                    isDark: isDark,
                                  ),
                                ),
                              const SizedBox(width: 8),

                              // 3rd Place (Right)
                              if (thirdPlace != null)
                                Expanded(
                                  child: _buildPodiumItem(
                                    restaurant: thirdPlace,
                                    rank: 3,
                                    pillarHeight: 65,
                                    isDark: isDark,
                                  ),
                                )
                              else
                                const Spacer(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // 4. TIER FILTER CHIPS ROW
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Filter Tier:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: ['All', 'Platinum', 'Gold', 'Silver', 'Bronze'].map((tier) {
                              final isSelected = _selectedTierFilter == tier;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text(tier),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF00A88F),
                                  backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected
                                          ? const Color(0xFF00A88F)
                                          : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                  onSelected: (val) {
                                    setState(() {
                                      _selectedTierFilter = val ? tier : 'All';
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 5. RANKINGS LIST CARDS OR EMPTY STATE
                if (rankedList.isEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    padding: const EdgeInsets.all(24),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A88F).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.military_tech_rounded, size: 36, color: Color(0xFF00A88F)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Outlets in $_selectedTierFilter Tier',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Outlets with matching risk scores will automatically appear here once registered.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00A88F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedTierFilter = 'All';
                            });
                          },
                          child: const Text('Show All Tiers'),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: rankedList.length,
                    itemBuilder: (context, index) {
                      final restaurant = rankedList[index];
                      final tier = _getRestaurantTier(restaurant);
                      final rankNum = index + 1;

                      return GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, AppRoutes.restaurantDetail, arguments: restaurant);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Rank Number Badge
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: rankNum == 1
                                        ? const Color(0xFFFEF9C3)
                                        : rankNum == 2
                                            ? const Color(0xFFF1F5F9)
                                            : rankNum == 3
                                                ? const Color(0xFFFEF3C7)
                                                : (isDark ? const Color(0xFF282828) : const Color(0xFFF8FAFC)),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: rankNum == 1
                                          ? const Color(0xFFEAB308)
                                          : rankNum == 2
                                              ? const Color(0xFF94A3B8)
                                              : rankNum == 3
                                                  ? const Color(0xFFD97706)
                                                  : Colors.transparent,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      rankNum < 10 ? '0$rankNum' : '$rankNum',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: rankNum == 1
                                            ? const Color(0xFFB45309)
                                            : rankNum == 2
                                                ? const Color(0xFF475569)
                                                : rankNum == 3
                                                    ? const Color(0xFF9A3412)
                                                    : (isDark ? Colors.white70 : Colors.grey.shade600),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Outlet Avatar Image
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isDark ? const Color(0xFF282828) : Colors.grey.shade200,
                                  backgroundImage: restaurant.imageUrl.isNotEmpty
                                      ? outletImageProvider(restaurant.imageUrl)
                                      : null,
                                  child: restaurant.imageUrl.isEmpty
                                      ? Text(
                                          restaurant.name.isNotEmpty ? restaurant.name[0].toUpperCase() : 'R',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),

                                // Outlet Info & Tier Badge
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        restaurant.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? Colors.white : AppTheme.navyColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? _getTierColor(tier).withValues(alpha: 0.2)
                                                  : _getTierBgColor(tier),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: _getTierColor(tier).withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(_getTierIcon(tier), size: 12, color: _getTierColor(tier)),
                                                const SizedBox(width: 3),
                                                Text(
                                                  _getTierName(tier),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: _getTierColor(tier),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              restaurant.category,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.white60 : Colors.grey.shade500,
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

                                // Score & Rating Column
                                Builder(
                                  builder: (context) {
                                    final periodScore = _selectedPeriod == 'Today'
                                        ? _getTodayScore(restaurant)
                                        : _getWeekScore(restaurant);

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                          decoration: BoxDecoration(
                                            color: _selectedPeriod == 'Today'
                                                ? (isDark
                                                    ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                                                    : const Color(0xFFECFDF5))
                                                : (isDark
                                                    ? const Color(0xFF312E81).withValues(alpha: 0.35)
                                                    : const Color(0xFFEEF2FF)),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: _selectedPeriod == 'Today'
                                                  ? const Color(0xFF059669).withValues(alpha: 0.3)
                                                  : const Color(0xFF6366F1).withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _selectedPeriod == 'Today' ? Icons.bolt_rounded : Icons.trending_up_rounded,
                                                size: 13,
                                                color: _selectedPeriod == 'Today'
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFF6366F1),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '${_selectedPeriod == 'Today' ? 'Today' : '7-Day'}: ${periodScore.toStringAsFixed(1)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: _selectedPeriod == 'Today'
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFF6366F1),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Period-specific badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: _selectedPeriod == 'Today'
                                                    ? (restaurant.violationCount == 0
                                                        ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.25) : const Color(0xFFF0FDF4))
                                                        : (isDark ? const Color(0xFF78350F).withValues(alpha: 0.25) : const Color(0xFFFFFBEB)))
                                                    : (isDark ? const Color(0xFF312E81).withValues(alpha: 0.25) : const Color(0xFFF5F3FF)),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                _selectedPeriod == 'Today'
                                                    ? (restaurant.violationCount == 0 ? '🟢 Clean' : '⚠️ Alert')
                                                    : (restaurant.violationCount == 0 ? '🔥 7D Streak' : '▲ Active'),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color: _selectedPeriod == 'Today'
                                                      ? (restaurant.violationCount == 0 ? const Color(0xFF16A34A) : const Color(0xFFD97706))
                                                      : const Color(0xFF7C3AED),
                                                ),
                                              ),
                                            ),
                                            Builder(
                                              builder: (context) {
                                                final ratingInfo = RestaurantStoreService.getRatingSync(
                                                  restaurant.id,
                                                  restaurantName: restaurant.name,
                                                );
                                                return Row(
                                                  children: [
                                                    Icon(
                                                      ratingInfo.hasReviews ? Icons.star_rounded : Icons.star_border_rounded,
                                                      color: ratingInfo.hasReviews
                                                          ? Colors.amber
                                                          : (isDark ? Colors.white24 : Colors.grey.shade400),
                                                      size: 13,
                                                    ),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      ratingInfo.ratingText,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 11.5,
                                                        color: ratingInfo.hasReviews
                                                            ? (isDark ? Colors.white : Colors.black87)
                                                            : (isDark ? Colors.white54 : Colors.grey.shade600),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    ),
    ),
  );
}

  Widget _buildPodiumItem({
    required RestaurantModel restaurant,
    required int rank,
    required double pillarHeight,
    required bool isDark,
  }) {
    final tier = _getRestaurantTier(restaurant);

    Color badgeColor;
    Color ringColor;
    List<Color> pillarGradient;
    String medalEmoji;

    if (rank == 1) {
      badgeColor = const Color(0xFFEAB308);
      ringColor = const Color(0xFFFFD700);
      medalEmoji = _selectedPeriod == 'Today' ? '👑' : '🏆';
      pillarGradient = [
        const Color(0xFFFFE082),
        const Color(0xFFFFD700),
        const Color(0xFFF59E0B),
        const Color(0xFFD97706),
      ];
    } else if (rank == 2) {
      badgeColor = const Color(0xFF94A3B8);
      ringColor = const Color(0xFFCBD5E1);
      medalEmoji = '🥈';
      pillarGradient = [
        const Color(0xFFFFFFFF),
        const Color(0xFFE2E8F0),
        const Color(0xFF94A3B8),
        const Color(0xFF64748B),
      ];
    } else {
      badgeColor = const Color(0xFFD97706);
      ringColor = const Color(0xFFFB923C);
      medalEmoji = '🥉';
      pillarGradient = [
        const Color(0xFFFFEDD5),
        const Color(0xFFFB923C),
        const Color(0xFFEA580C),
        const Color(0xFFC2410C),
      ];
    }

    final periodScore = _selectedPeriod == 'Today'
        ? _getTodayScore(restaurant)
        : _getWeekScore(restaurant);

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.restaurantDetail, arguments: restaurant);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Crown / Medal Icon
          Text(
            medalEmoji,
            style: TextStyle(fontSize: rank == 1 ? 22 : 18),
          ),
          const SizedBox(height: 2),

          // Avatar with Rank Border
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: rank == 1 ? 2.5 : 2.0),
              boxShadow: [
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: rank == 1 ? 24 : 20,
              backgroundColor: isDark ? const Color(0xFF282828) : Colors.grey.shade200,
              backgroundImage: restaurant.imageUrl.isNotEmpty ? outletImageProvider(restaurant.imageUrl) : null,
              child: restaurant.imageUrl.isEmpty
                  ? Text(
                      restaurant.name.isNotEmpty ? restaurant.name[0].toUpperCase() : 'R',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: rank == 1 ? 16 : 13,
                        color: badgeColor,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),

          // Restaurant Name
          Text(
            restaurant.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isDark ? Colors.white : AppTheme.navyColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

          // Tier Badge Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: isDark ? _getTierColor(tier).withValues(alpha: 0.2) : _getTierBgColor(tier),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _getTierName(tier),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: _getTierColor(tier),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Metallic Podium Pillar
          Container(
            width: double.infinity,
            height: pillarHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: pillarGradient,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: rank == 1 ? 26 : 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${periodScore.toStringAsFixed(1)} pts',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _selectedPeriod == 'Today' ? '⚡ Today' : '📈 7-Day',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeagueRibbonBadge(String name, int count, Color color, bool isDark) {
    final isSelected = _selectedTierFilter.toLowerCase() == name.toLowerCase();

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTierFilter = isSelected ? 'All' : name;
        });
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isSelected ? color : color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : color,
                width: isSelected ? 2.2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected ? color.withValues(alpha: 0.4) : color.withValues(alpha: 0.15),
                  blurRadius: isSelected ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.military_tech_rounded,
                color: isSelected ? Colors.white : color,
                size: 24,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected
                  ? const Color(0xFF00A88F)
                  : (isDark ? Colors.white : AppTheme.navyColor),
            ),
          ),
          Text(
            '($count)',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white54 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
