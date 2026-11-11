import '../../core/widgets/customer_refresh_indicator.dart';
import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/gps_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/voice_search_modal.dart';

import '../../gps/widgets/restaurant_card.dart';

class RecommendationHomeScreen extends StatefulWidget {
  final bool showAppBar;

  const RecommendationHomeScreen({
    super.key,
    this.showAppBar = true,
  });

  @override
  State<RecommendationHomeScreen> createState() => _RecommendationHomeScreenState();
}

class _RecommendationHomeScreenState extends State<RecommendationHomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  double _userLat = 3.1466;
  double _userLng = 101.6958;
  bool _hasUserLocation = false;
  String _selectedDistanceFilter = 'All'; // 'All', '0-5km', '5-10km', '10-20km'

  @override
  void initState() {
    super.initState();
    _fetchUserGpsLocation();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUserGpsLocation() async {
    try {
      final position = await GpsService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _userLat = position.latitude;
          _userLng = position.longitude;
          _hasUserLocation = true;
        });
      }
    } catch (_) {
      // Graceful fallback to default KL location
    }
  }

  double _getDistanceKm(RestaurantModel r) {
    return Geolocator.distanceBetween(_userLat, _userLng, r.latitude, r.longitude) / 1000.0;
  }

  List<RestaurantModel> _getSafeRestaurants(List<RestaurantModel> allRestaurants) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final list = allRestaurants
        .where((r) => r.status == RestaurantStatus.approved && (r.riskCategory == RiskCategory.safe || r.hygieneRiskScore <= 25.0))
        .where((r) {
          if (query.isEmpty) return true;
          return r.name.toLowerCase().contains(query) ||
              r.category.toLowerCase().contains(query) ||
              r.address.toLowerCase().contains(query);
        })
        .toList();

    // Sort primarily by nearest distance, then highest star rating & safety score
    list.sort((a, b) {
      final distA = _getDistanceKm(a);
      final distB = _getDistanceKm(b);
      final distComp = distA.compareTo(distB);
      if (distComp != 0) return distComp;

      final ratingA = RestaurantStoreService.getRatingSync(a.id, restaurantName: a.name);
      final ratingB = RestaurantStoreService.getRatingSync(b.id, restaurantName: b.name);
      return ratingB.averageRating.compareTo(ratingA.averageRating);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: widget.showAppBar
          ? const CustomAppBar(
              title: 'Recommendation',
              showBackButton: false,
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomerRefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            RestaurantStoreService.fetchAllRestaurants(forceRefresh: true),
            _fetchUserGpsLocation(),
          ]);
          if (mounted) setState(() {});
        },
        child: ValueListenableBuilder<List<RestaurantModel>>(
          valueListenable: RestaurantStoreService.restaurantsNotifier,
          builder: (context, allRestaurants, _) {
            if (allRestaurants.isEmpty) {
              return const SingleChildScrollView(physics: AlwaysScrollableScrollPhysics(),
                child: SizedBox(height: 320, child: Center(child: Text('No restaurants available. Pull down to try again.'))));
            }

            final safeList = _getSafeRestaurants(allRestaurants);

            // Group into distance tiers in sequence: 0~5km, 5~10km, 10~20km, 20+km
            final tier0to5 = <RestaurantModel>[];
            final tier5to10 = <RestaurantModel>[];
            final tier10to20 = <RestaurantModel>[];
            final tierAbove20 = <RestaurantModel>[];

            for (final r in safeList) {
              final dist = _getDistanceKm(r);
              if (dist <= 5.0) {
                tier0to5.add(r);
              } else if (dist <= 10.0) {
                tier5to10.add(r);
              } else if (dist <= 20.0) {
                tier10to20.add(r);
              } else {
                tierAbove20.add(r);
              }
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.all(16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP HERO RECOMMENDATION BANNER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E1E1E), const Color(0xFF00A88F).withValues(alpha: 0.75)]
                          : const [Color(0xFF0C2340), Color(0xFF00A88F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.near_me_rounded, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _hasUserLocation ? 'GPS Location Active' : 'Nearby Safe Outlets',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          if (safeList.isEmpty)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.pushNamed(context, AppRoutes.riskRankingList);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.emoji_events_rounded,
                                    color: Color(0xFFFFD700),
                                    size: 19,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Suggested Safe Outlets',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Handpicked dining places sorted by proximity to your current GPS location.',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 2. SEARCH BAR BELOW BANNER
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _searchCtrl.text.isNotEmpty
                          ? const Color(0xFF00A88F).withValues(alpha: 0.6)
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      width: _searchCtrl.text.isNotEmpty ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: AppSearchField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppTheme.navyColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search safe restaurants by name or cuisine...',
                      hintStyle: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.normal,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF00A88F),
                        size: 22,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchCtrl.text.isNotEmpty)
                            IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.mic_rounded,
                              color: Color(0xFF00A88F),
                              size: 22,
                            ),
                            tooltip: 'Voice Search',
                            onPressed: () {
                              VoiceSearchModal.show(
                                context: context,
                                initialText: _searchCtrl.text,
                                onResult: (text) {
                                  setState(() {
                                    _searchCtrl.text = text;
                                  });
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 3. INTERACTIVE DISTANCE TIER FILTER CHIPS
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDistanceFilterChip(
                        label: 'All Distances (${safeList.length})',
                        value: 'All',
                        isDark: isDark,
                      ),
                      _buildDistanceFilterChip(
                        label: '📍 0 ~ 5 km (${tier0to5.length})',
                        value: '0-5km',
                        isDark: isDark,
                      ),
                      _buildDistanceFilterChip(
                        label: '🚗 5 ~ 10 km (${tier5to10.length})',
                        value: '5-10km',
                        isDark: isDark,
                      ),
                      _buildDistanceFilterChip(
                        label: '🛣️ 10 ~ 20 km (${tier10to20.length})',
                        value: '10-20km',
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 4. SEQUENTIAL DISTANCE SECTIONS OR EMPTY SEARCH STATE
                if (safeList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.restaurant_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _searchCtrl.text.isNotEmpty
                                ? 'No safe restaurants found matching "${_searchCtrl.text.trim()}".'
                                : 'No safe outlets found in your area.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                          if (_searchCtrl.text.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text('Clear Search'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF00A88F),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else ...[
                  // SECTION 1: 0 ~ 5 KM
                  if ((_selectedDistanceFilter == 'All' || _selectedDistanceFilter == '0-5km') && tier0to5.isNotEmpty)
                    _buildDistanceSection(
                      title: '0 ~ 5 km (Immediate Nearby)',
                      subtitle: 'Walking distance & short drive away',
                      color: const Color(0xFF059669),
                      icon: Icons.directions_walk_rounded,
                      restaurants: tier0to5,
                      isDark: isDark,
                    ),

                  // SECTION 2: 5 ~ 10 KM
                  if ((_selectedDistanceFilter == 'All' || _selectedDistanceFilter == '5-10km') && tier5to10.isNotEmpty)
                    _buildDistanceSection(
                      title: '5 ~ 10 km (Short Drive)',
                      subtitle: 'Nearby neighborhoods & commercial districts',
                      color: const Color(0xFF0284C7),
                      icon: Icons.directions_car_rounded,
                      restaurants: tier5to10,
                      isDark: isDark,
                    ),

                  // SECTION 3: 10 ~ 20 KM
                  if ((_selectedDistanceFilter == 'All' || _selectedDistanceFilter == '10-20km') && tier10to20.isNotEmpty)
                    _buildDistanceSection(
                      title: '10 ~ 20 km (Extended City Area)',
                      subtitle: 'Metropolitan region with Grade A sanitation',
                      color: const Color(0xFF6366F1),
                      icon: Icons.explore_rounded,
                      restaurants: tier10to20,
                      isDark: isDark,
                    ),

                  // SECTION 4: 20+ KM (if any)
                  if (_selectedDistanceFilter == 'All' && tierAbove20.isNotEmpty)
                    _buildDistanceSection(
                      title: '20+ km (Greater Region)',
                      subtitle: 'Further destinations certified safe',
                      color: const Color(0xFF64748B),
                      icon: Icons.map_rounded,
                      restaurants: tierAbove20,
                      isDark: isDark,
                    ),
                ],

                // 4. RISK RANKINGS CALL-TO-ACTION CARD (Only shown when safe restaurants are displayed)
                if (safeList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A88F).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.military_tech_rounded, color: Color(0xFF00A88F), size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Risk Rankings',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Compare all restaurant hygiene scores by tier.',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        CustomButton(
                          label: 'View Risk Rankings',
                          onPressed: () {
                            Navigator.pushNamed(context, AppRoutes.riskRankingList);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
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

  Widget _buildDistanceFilterChip({
    required String label,
    required String value,
    required bool isDark,
  }) {
    final isSelected = (_selectedDistanceFilter == value);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF282828)),
          ),
        ),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedDistanceFilter = value),
        selectedColor: AppTheme.primaryColor,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        side: BorderSide(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildDistanceSection({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required List<RestaurantModel> restaurants,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.25 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${restaurants.length} Places',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Restaurant Cards
          for (final r in restaurants)
            RestaurantCard(
              restaurant: r,
              userLat: _userLat,
              userLng: _userLng,
            ),
        ],
      ),
    );
  }
}
