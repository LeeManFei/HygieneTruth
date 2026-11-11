import '../../core/widgets/customer_refresh_indicator.dart';
import '../../core/widgets/app_search_field.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/language_manager.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/translations.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/voice_search_modal.dart';
import '../widgets/restaurant_card.dart';

class RestaurantSearchScreen extends StatefulWidget {
  const RestaurantSearchScreen({super.key});

  @override
  State<RestaurantSearchScreen> createState() => _RestaurantSearchScreenState();
}

class _RestaurantSearchScreenState extends State<RestaurantSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  bool _isLoading = true;

  StreamSubscription? _realtimeSub;

  // Filter States
  String _selectedCategory = 'All';
  String _selectedRanking = 'All'; // 'All', 'Low', 'Medium', 'High'
  bool _isNearbyOnly = false;

  List<RestaurantModel> _allRestaurants = [];
  List<RestaurantModel> _filteredList = [];

  // Reference User Location for Nearby calculation (Kuala Lumpur City Center)
  final double _userLat = 3.1466;
  final double _userLng = 101.6958;

  bool _initializedArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedArgs) {
      _initializedArgs = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _selectedCategory = args;
        _applyFilters();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscription();
    _loadRestaurantsFromSupabase();
    RestaurantStoreService.restaurantsNotifier.addListener(_onRestaurantsUpdated);
  }

  void _onRestaurantsUpdated() {
    if (mounted) {
      setState(() {
        _allRestaurants = RestaurantStoreService.restaurantsNotifier.value;
      });
      _applyFilters();
    }
  }

  Future<void> _loadRestaurantsFromSupabase({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final list = await RestaurantStoreService.fetchAllRestaurants(forceRefresh: true);
    if (mounted) {
      setState(() {
        _allRestaurants = list;
        _isLoading = false;
      });
      _applyFilters();
    }
  }

  void _setupRealtimeSubscription() {
    try {
      final supabase = SupabaseService.client;
      _realtimeSub = supabase
          .from('restaurants')
          .stream(primaryKey: ['id'])
          .listen((data) async {
            final updatedList = await RestaurantStoreService.fetchAllRestaurants(forceRefresh: true);
            if (mounted) {
              setState(() {
                _allRestaurants = updatedList;
              });
              _applyFilters();
            }
          });
    } catch (e) {
      debugPrint('Realtime search stream error: $e');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _realtimeSub?.cancel();
    RestaurantStoreService.restaurantsNotifier.removeListener(_onRestaurantsUpdated);
    super.dispose();
  }



  void _startVoiceSearch() {
    VoiceSearchModal.show(
      context: context,
      initialText: _searchCtrl.text,
      speechToText: _speechToText,
      suggestions: const [
        'Golden Dragon',
        'Halal Bistro',
        'Dim Sum',
        'Noodles',
        'Mamak',
        'Café',
        'Bakery',
      ],
      onResult: (text) {
        if (mounted) {
          setState(() {
            _searchCtrl.text = text;
            _applyFilters();
          });
        }
      },
    );
  }

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      _filteredList = _allRestaurants.where((r) {
        final matchesVisibility = r.isPubliclyVisible;

        final matchesQuery = query.isEmpty ||
            r.name.toLowerCase().contains(query) ||
            r.category.toLowerCase().contains(query) ||
            r.address.toLowerCase().contains(query);

        final matchesCategory = _selectedCategory == 'All' ||
            r.category.toLowerCase() == _selectedCategory.toLowerCase();

        bool matchesRanking = true;
        if (_selectedRanking == 'Low') {
          matchesRanking = r.riskCategory == RiskCategory.safe;
        } else if (_selectedRanking == 'Medium') {
          matchesRanking = r.riskCategory == RiskCategory.moderate;
        } else if (_selectedRanking == 'High') {
          matchesRanking = r.riskCategory == RiskCategory.high;
        }

        bool matchesNearby = true;
        if (_isNearbyOnly) {
          final distanceMeters = Geolocator.distanceBetween(
            _userLat,
            _userLng,
            r.latitude,
            r.longitude,
          );
          matchesNearby = (distanceMeters / 1000) <= 8.0;
        }

        return matchesVisibility && matchesQuery && matchesCategory && matchesRanking && matchesNearby;
      }).toList();

      if (_isNearbyOnly) {
        _filteredList.sort((a, b) {
          final distA = Geolocator.distanceBetween(_userLat, _userLng, a.latitude, a.longitude);
          final distB = Geolocator.distanceBetween(_userLat, _userLng, b.latitude, b.longitude);
          return distA.compareTo(distB);
        });
      }
    });
  }

  void _openFilterBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> categories = [
      'All',
      ..._allRestaurants.map((r) => r.category).where((c) => c.isNotEmpty).toSet(),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setFilterState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Row with Reset Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Outlets',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setFilterState(() {
                            _selectedCategory = 'All';
                            _selectedRanking = 'All';
                            _isNearbyOnly = false;
                          });
                        },
                        child: const Text('Reset All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Category Section
                  Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : AppTheme.navyColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: isDark ? const Color(0xFF282828) : Colors.grey.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setFilterState(() {
                              _selectedCategory = cat;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Risk / Hygiene Ranking Section
                  Text(
                    'Hygiene Risk Level',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : AppTheme.navyColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['All', 'Low', 'Medium', 'High'].map((rank) {
                      final isSelected = _selectedRanking == rank;
                      return ChoiceChip(
                        label: Text(rank == 'All' ? 'All Risks' : '$rank Risk'),
                        selected: isSelected,
                        selectedColor: rank == 'Low'
                            ? const Color(0xFF059669)
                            : (rank == 'Medium'
                                ? const Color(0xFFD97706)
                                : (rank == 'High' ? const Color(0xFFDC2626) : AppTheme.primaryColor)),
                        backgroundColor: isDark ? const Color(0xFF282828) : Colors.grey.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setFilterState(() {
                              _selectedRanking = rank;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Nearby Only Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Nearby Outlets Only (< 8 km)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                    ),
                    subtitle: Text(
                      'Sort outlets closest to your current GPS location',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                    value: _isNearbyOnly,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      setFilterState(() {
                        _isNearbyOnly = val;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Apply Filter Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _applyFilters();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool get _hasActiveFilters =>
      _selectedCategory != 'All' || _selectedRanking != 'All' || _isNearbyOnly;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: languageManager,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
          appBar: CustomAppBar(title: t('search_outlets').split('.').first),
          body: SafeArea(
            top: false,
            bottom: true,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                // Search Input Bar with Speech-to-Text Mic and Custom Equalizer Filter Icon at Far Right
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppSearchField(suggestions: _allRestaurants.where((r) => r.isPubliclyVisible).map((r) => r.name).toList(),
                          controller: _searchCtrl,
                          onChanged: (_) => _applyFilters(),
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search outlets...',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            prefixIcon: Icon(Icons.search, color: isDark ? Colors.white70 : AppTheme.navyColor),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchCtrl.text.isNotEmpty)
                                  IconButton(
                                    icon: Icon(Icons.clear, size: 20, color: isDark ? Colors.white60 : Colors.grey),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _applyFilters();
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.mic_rounded,
                                    color: AppTheme.primaryColor,
                                  ),
                                  tooltip: 'Voice Search',
                                  onPressed: _startVoiceSearch,
                                ),
                              ],
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Custom Equalizer Slider Filter Button at FAR RIGHT
                      Stack(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: _hasActiveFilters ? AppTheme.primaryColor : (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _hasActiveFilters ? AppTheme.primaryColor : (isDark ? Colors.white24 : Colors.grey.shade300),
                                width: 1.2,
                              ),
                            ),
                            child: IconButton(
                              icon: Icon(
                                Icons.tune_rounded,
                                color: _hasActiveFilters ? Colors.white : (isDark ? Colors.white : AppTheme.navyColor),
                              ),
                              tooltip: 'Filter Outlets',
                              onPressed: _openFilterBottomSheet,
                            ),
                          ),
                          if (_hasActiveFilters)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF80EE98),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Active Filter Chips Summary (if any)
                if (_hasActiveFilters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (_selectedCategory != 'All')
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Chip(
                                label: Text('Category: $_selectedCategory'),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setState(() {
                                    _selectedCategory = 'All';
                                    _applyFilters();
                                  });
                                },
                                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                              ),
                            ),
                          if (_selectedRanking != 'All')
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Chip(
                                label: Text('Risk: $_selectedRanking'),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setState(() {
                                    _selectedRanking = 'All';
                                    _applyFilters();
                                  });
                                },
                                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                              ),
                            ),
                          if (_isNearbyOnly)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Chip(
                                label: const Text('Nearby Only (< 8 km)'),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setState(() {
                                    _isNearbyOnly = false;
                                    _applyFilters();
                                  });
                                },
                                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Outlets Count & Map View Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_filteredList.length} Outlets',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('Map View'),
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.restaurantMap),
                      ),
                    ],
                  ),
                ),

                // Outlet Results List with Pull to Refresh & Shimmer Loading
                Expanded(
                  child: _isLoading
                      ? ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: 4,
                          itemBuilder: (context, index) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
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
                                BaseSkeleton(width: 90, height: 90, borderRadius: 14),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          BaseSkeleton(width: 130, height: 16, borderRadius: 4),
                                          BaseSkeleton(width: 50, height: 14, borderRadius: 4),
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
                                          BaseSkeleton(width: 80, height: 20, borderRadius: 6),
                                          BaseSkeleton(width: 70, height: 20, borderRadius: 6),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : CustomerRefreshIndicator(
                          onRefresh: () => _loadRestaurantsFromSupabase(showLoading: false),
                          color: AppTheme.primaryColor,
                          child: _filteredList.isEmpty
                              ? ListView(physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    const SizedBox(height: 80),
                                    Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'No outlets match your filters',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: () {
                                              setState(() {
                                                _searchCtrl.clear();
                                                _selectedCategory = 'All';
                                                _selectedRanking = 'All';
                                                _isNearbyOnly = false;
                                                _applyFilters();
                                              });
                                            },
                                            child: const Text('Reset All Search Filters'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _filteredList.length,
                                  itemBuilder: (context, index) {
                                    return RestaurantCard(restaurant: _filteredList[index]);
                                  },
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
}
