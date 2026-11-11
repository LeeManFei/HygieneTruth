import '../../core/utils/outlet_image_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../risk/widgets/risk_score_gauge.dart';

class RestaurantDetailScreen extends StatefulWidget {
  const RestaurantDetailScreen({super.key});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  bool _isSaved = false;

  final _newCommentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  int _selectedRating = 5;

  final _scrollController = ScrollController();
  List<Map<String, String>> _reviews = [];
  String? _loadedRestaurantId;
  RestaurantModel? _currentRestaurant;

  int _selectedFilterStar = 0;
  String _selectedSortOption = 'helpful'; // 'helpful' (Top Helpful), 'recent', 'highest', 'lowest'
  int _currentReviewPage = 1;
  static const int _reviewsPerPage = 3;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _setupRealtime();
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = SupabaseService.client
          .channel('public:restaurant_detail_helpful_sync')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'audit_logs',
            callback: (payload) async {
              if (mounted && _loadedRestaurantId != null) {
                _loadReviewsForRestaurant(_loadedRestaurantId!, restaurantName: _currentRestaurant?.name);
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dynamic args = ModalRoute.of(context)?.settings.arguments;
    RestaurantModel? restaurant;
    bool shouldScrollToReviews = false;

    if (args is RestaurantModel) {
      restaurant = args;
    } else if (args is Map) {
      if (args['restaurant'] is RestaurantModel) {
        restaurant = args['restaurant'] as RestaurantModel;
      } else if (args['restaurantId'] != null || args['id'] != null) {
        final rId = (args['restaurantId'] ?? args['id']).toString();
        restaurant = RestaurantStoreService.restaurantsNotifier.value
            .where((r) => r.id == rId || r.name.toLowerCase() == rId.toLowerCase())
            .firstOrNull;
      }
      shouldScrollToReviews = args['scrollToReviews'] == true;
    }

    if (restaurant != null) {
      _currentRestaurant = restaurant;
      if (restaurant.id != _loadedRestaurantId) {
        _loadedRestaurantId = restaurant.id;
        _isSaved = BookmarkService.isBookmarked(restaurant.id);
        _loadReviewsForRestaurant(restaurant.id, restaurantName: restaurant.name);
        RestaurantStoreService.recordRecentVisit(restaurant);

        if (shouldScrollToReviews) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent * 0.75,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                );
              }
            });
          });
        }
      }
    }
  }

  Future<void> _loadReviewsForRestaurant(String restaurantId, {String? restaurantName}) async {
    final loaded = await RestaurantStoreService.fetchReviews(
      restaurantId,
      restaurantName: restaurantName ?? _currentRestaurant?.name,
    );
    if (mounted) {
      setState(() {
        _reviews = List<Map<String, String>>.from(loaded);
      });
    }
  }

  Future<void> _saveReviewsForRestaurant(String restaurantId) async {
    try {
      await RestaurantStoreService.saveReviewsToSupabase(
        restaurantId,
        _reviews,
        restaurantName: _currentRestaurant?.name,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _realtimeChannel?.unsubscribe();
    } catch (_) {}
    _scrollController.dispose();
    _newCommentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Map<String, String>? _findUserExistingReview() {
    final user = CustomerStoreService.currentCustomer;
    if (user == null) return null;
    final currentUserId = user.id.trim();
    final currentUserEmail = user.email.trim().toLowerCase();
    final currentUserName = user.name.trim().toLowerCase();

    for (final r in _reviews) {
      final rUserId = (r['userId'] ?? '').trim();
      final rUserEmail = (r['userEmail'] ?? '').trim().toLowerCase();
      final rUserName = (r['userName'] ?? '').trim().toLowerCase();

      if (currentUserId.isNotEmpty && rUserId == currentUserId) {
        return r;
      }
      if (currentUserEmail.isNotEmpty && rUserEmail == currentUserEmail) {
        return r;
      }
      if (currentUserName.isNotEmpty && rUserName == currentUserName) {
        return r;
      }
      if ((currentUserName == 'ahmeng' || currentUserName == 'ahmad') &&
          (rUserName == 'ahmad' || rUserName == 'ahmeng')) {
        return r;
      }
    }
    return null;
  }

  String _formatReviewTimestamp(String raw) {
    if (raw.isEmpty) return 'Recently';
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      final msiaDt = dt.toUtc().add(const Duration(hours: 8));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = msiaDt.hour.toString().padLeft(2, '0');
      final minute = msiaDt.minute.toString().padLeft(2, '0');
      if (raw.contains('T') || raw.contains(':')) {
        return '${msiaDt.day} ${months[msiaDt.month - 1]} ${msiaDt.year}, $hour:$minute';
      } else {
        return '${msiaDt.day} ${months[msiaDt.month - 1]} ${msiaDt.year}';
      }
    }
    return raw;
  }

  void _submitComment() {
    if (_findUserExistingReview() != null) {
      HygieneFeedback.showWarning(context, 'You have already submitted a review for this restaurant.');
      return;
    }

    final commentText = _newCommentController.text.trim();
    if (commentText.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please write a comment before submitting.');
      return;
    }

    final currentUser = CustomerStoreService.currentCustomer;
    final userName = currentUser?.name ?? 'Verified Customer';
    final userId = currentUser?.id ?? '';
    final userEmail = currentUser?.email ?? '';
    final userAvatar = currentUser?.avatarUrl ?? '';
    final now = DateTime.now();

    final newReview = {
      'id': 'rev_${now.millisecondsSinceEpoch}',
      'userId': userId,
      'userEmail': userEmail,
      'userName': userName,
      'userAvatar': userAvatar,
      'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'timestamp': now.toUtc().toIso8601String(),
      'stars': '$_selectedRating',
      'comment': commentText,
      'likedUserIds': '[]',
      'helpfulCount': '0',
    };

    setState(() {
      _reviews.insert(0, newReview);
      _newCommentController.clear();
      _selectedRating = 5;
    });

    if (_loadedRestaurantId != null) {
      final rName = _currentRestaurant?.name ?? _loadedRestaurantId!;
      _saveReviewsForRestaurant(_loadedRestaurantId!);
      RestaurantStoreService.logUserReviewActivity(
        restaurantId: _loadedRestaurantId!,
        restaurantName: rName,
        stars: int.tryParse(newReview['stars'] ?? '5') ?? 5,
        comment: commentText,
        timestamp: newReview['timestamp'],
      );
    }

    FocusScope.of(context).unfocus();
    HygieneFeedback.showSuccess(context, 'Review published successfully!');
  }



  void _showReportOptionsDialog([RestaurantModel? targetRestaurant]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final restaurant = targetRestaurant ??
        _currentRestaurant ??
        (RestaurantStoreService.restaurantsNotifier.value.isNotEmpty
            ? RestaurantStoreService.restaurantsNotifier.value.first
            : null);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Drag Handle Bar
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with Icon & Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryColor, Color(0xFF14B8A6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Restaurant Actions',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppTheme.navyColor,
                                ),
                              ),
                              if (restaurant != null)
                                SizedBox(
                                  width: MediaQuery.of(context).size.width * 0.55,
                                  child: Text(
                                    restaurant.name,
                                    style: TextStyle(
                                      fontSize: 12,
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
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.grey.shade700),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Action 1: Report Hygiene Issue Card
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, AppRoutes.submitComplaint, arguments: restaurant);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF282828) : const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: isDark ? 0.4 : 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE11D48), Color(0xFFF43F5E)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.report_problem_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Report Hygiene Issue',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFFE11D48),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Inspectors',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFE11D48),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Submit a formal complaint to public health enforcement',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFE11D48), size: 15),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Action 2: Share Restaurant Profile Card
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (restaurant == null) return;

                        final ratingInfo = RestaurantStoreService.getRatingSync(
                          restaurant.id,
                          restaurantName: restaurant.name,
                        );

                        final String shareContent = '''🍽️ Check out ${restaurant.name} on HygieneTruth!

📍 Address: ${restaurant.address}
🏷️ Cuisine: ${restaurant.category}
⭐ Rating: ${ratingInfo.ratingText} ★ ${ratingInfo.hasReviews ? '(${ratingInfo.totalReviews} reviews)' : ''}
🛡️ Hygiene Status: ${restaurant.riskCategory.name.toUpperCase()} (Score: ${restaurant.hygieneRiskScore.toStringAsFixed(1)} / 100)
⏰ Operating Hours: ${restaurant.operatingHours}

🗺️ View on Google Maps: https://www.google.com/maps/search/?api=1&query=${restaurant.latitude},${restaurant.longitude}

📱 Discover clean dining and real-time hygiene audit certificates on HygieneTruth!''';

                        try {
                          await SharePlus.instance.share(
                            ShareParams(
                              text: shareContent,
                              subject: 'Check out ${restaurant.name} on HygieneTruth',
                            ),
                          );
                        } catch (e) {
                          await Clipboard.setData(ClipboardData(text: shareContent));
                          if (mounted) {
                            HygieneFeedback.showSuccess(context, 'Restaurant profile copied to clipboard!');
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF282828) : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.4 : 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.share_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Share Restaurant Profile',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? Colors.white : AppTheme.navyColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Share',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Share hygiene rating, location & safety score link',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF0F766E), size: 15),
                          ],
                        ),
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

  Widget _buildOutletQuickActions(RestaurantModel restaurant) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _quickActionButton(
              icon: Icons.near_me_rounded,
              label: 'Directions',
              color: const Color(0xFF00A88F),
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.restaurantMap,
                  arguments: {
                    'restaurant': restaurant,
                    'showDirections': true,
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _quickActionButton(
              icon: Icons.phone_rounded,
              label: 'Call Outlet',
              color: const Color(0xFF0284C7),
              onTap: () {
                HygieneFeedback.showSuccess(context, 'Calling outlet contact number...');
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _quickActionButton(
              icon: Icons.report_problem_rounded,
              label: 'Report Issue',
              color: const Color(0xFFDC2626),
              isRed: true,
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.submitComplaint,
                  arguments: restaurant,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isRed = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isRed
              ? (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.35) : const Color(0xFFFEF2F2))
              : color.withValues(alpha: isDark ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRed
                ? (isDark ? const Color(0xFFDC2626).withValues(alpha: 0.5) : const Color(0xFFFCA5A5))
                : color.withValues(alpha: isDark ? 0.35 : 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isDark && !isRed ? color.withValues(alpha: 0.9) : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark && isRed ? const Color(0xFFFCA5A5) : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentInputCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = CustomerStoreService.currentCustomer;
    final userName = currentUser?.name ?? 'Verified Customer';
    final avatarUrl = currentUser?.avatarUrl ?? '';

    final ratingLabels = ['Poor', 'Fair', 'Average', 'Good', 'Excellent'];

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                avatarUrl: avatarUrl,
                radius: 18,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : AppTheme.navyColor,
                    ),
                  ),
                  Text(
                    'Share your dining hygiene experience',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: TextField(
              controller: _newCommentController,
              focusNode: _commentFocusNode,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                hintText: 'Describe kitchen cleanliness, staff hygiene, utensils, or food quality...',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
            ),
          ),
          const SizedBox(height: 12),
          // Quick Tags
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _quickTagChip('#CleanKitchen'),
              _quickTagChip('#GoodSanitation'),
              _quickTagChip('#FreshFood'),
              _quickTagChip('#WashedUtensils'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          final starVal = index + 1;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedRating = starVal;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Icon(
                                starVal <= _selectedRating ? Icons.star_rounded : Icons.star_border_rounded,
                                color: Colors.amber,
                                size: 22,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ratingLabels[_selectedRating - 1],
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A88F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  elevation: 0,
                ),
                onPressed: _submitComment,
                icon: const Icon(Icons.send_rounded, size: 14),
                label: const Text(
                  'Post Review',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyReviewedCard(Map<String, String> existingReview) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final starsCount = int.tryParse(existingReview['stars'] ?? '5') ?? 5;
    final dateStr = _formatReviewTimestamp(existingReview['timestamp'] ?? existingReview['date'] ?? '');
    final comment = existingReview['comment'] ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF059669).withValues(alpha: 0.5) : const Color(0xFF86EFAC), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thank You for Reviewing this Restaurant',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF14532D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your hygiene experience review has been submitted and verified.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFDCFCE7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < starsCount ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 17,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF065F46) : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$starsCount ★ Your Review',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    comment,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      height: 1.35,
                    ),
                  ),
                  if ((existingReview['ownerReply'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF121212) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? const Color(0xFF059669).withValues(alpha: 0.5) : const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.storefront_rounded, size: 16, color: isDark ? const Color(0xFF34D399) : const Color(0xFF15803D)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Official Response from Restaurant Owner',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF14532D),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  existingReview['ownerReply']!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark ? Colors.white70 : const Color(0xFF166534),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF15803D)),
              const SizedBox(width: 6),
              Text(
                'Reviewed on: $dateStr',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF15803D),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickTagChip(String label) {
    return GestureDetector(
      onTap: () {
        final currentText = _newCommentController.text;
        _newCommentController.text = currentText.isEmpty ? label : '$currentText $label';
        _newCommentController.selection = TextSelection.fromPosition(
          TextPosition(offset: _newCommentController.text.length),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildOutletImage(RestaurantModel restaurant) {
    final imageUrl = restaurant.imageUrl.trim();
    Widget imageWidget;

    if (imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('data:image/') || imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        imageWidget = Image(
          image: outletImageProvider(imageUrl),
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackImagePlaceholder(restaurant),
        );
      } else if (imageUrl.startsWith('assets/')) {
        imageWidget = Image.asset(
          imageUrl,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackImagePlaceholder(restaurant),
        );
      } else {
        try {
          final file = File(imageUrl);
          if (file.existsSync()) {
            imageWidget = Image.file(
              file,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallbackImagePlaceholder(restaurant),
            );
          } else {
            imageWidget = _buildFallbackImagePlaceholder(restaurant);
          }
        } catch (_) {
          imageWidget = _buildFallbackImagePlaceholder(restaurant);
        }
      }
    } else {
      imageWidget = _buildFallbackImagePlaceholder(restaurant);
    }

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: imageWidget,
      ),
    );
  }

  Widget _buildFallbackImagePlaceholder(RestaurantModel restaurant) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF181818), Color(0xFF282828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              Icons.storefront_rounded,
              size: 180,
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A88F).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00A88F).withValues(alpha: 0.5)),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 40,
                  color: Color(0xFF00A88F),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                restaurant.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  restaurant.category,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSummaryCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double avgRating = 0.0;
    if (_reviews.isNotEmpty) {
      double sum = 0;
      for (var r in _reviews) {
        sum += (double.tryParse(r['stars'] ?? '0') ?? 0);
      }
      avgRating = sum / _reviews.length;
    }

    final hasReviews = _reviews.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left Big Score Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hasReviews
                  ? (isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7))
                  : (isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasReviews
                    ? (isDark ? Colors.amber.shade700 : const Color(0xFFFCD34D))
                    : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hasReviews ? avgRating.toStringAsFixed(1) : '0.0',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: hasReviews ? Colors.amber : (isDark ? Colors.white54 : Colors.grey.shade600),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: List.generate(5, (index) {
                    if (!hasReviews) {
                      return Icon(Icons.star_border_rounded, color: isDark ? Colors.white24 : Colors.grey.shade400, size: 14);
                    }
                    final starValue = index + 1;
                    if (avgRating >= starValue) {
                      return const Icon(Icons.star_rounded, color: Colors.amber, size: 14);
                    } else if (avgRating >= starValue - 0.5) {
                      return const Icon(Icons.star_half_rounded, color: Colors.amber, size: 14);
                    } else {
                      return Icon(Icons.star_border_rounded, color: isDark ? Colors.white24 : Colors.grey.shade400, size: 14);
                    }
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Right Summary Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hasReviews ? 'Customer Rating' : 'No Ratings Yet',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : AppTheme.navyColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasReviews
                      ? '${_reviews.length} ${_reviews.length == 1 ? 'review' : 'reviews'}'
                      : 'New restaurant',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasReviews
                        ? (isDark ? const Color(0xFF065F46).withValues(alpha: 0.4) : const Color(0xFFECFDF5))
                        : (isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasReviews
                          ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasReviews ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                        size: 13,
                        color: hasReviews ? const Color(0xFF059669) : (isDark ? Colors.white54 : Colors.grey),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          hasReviews ? 'Verified Reviews' : 'No reviews yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: hasReviews ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669)) : (isDark ? Colors.white60 : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMapSection(RestaurantModel restaurant) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final LatLng pos = LatLng(
      restaurant.latitude != 0.0 ? restaurant.latitude : 3.1466,
      restaurant.longitude != 0.0 ? restaurant.longitude : 101.6958,
    );

    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            IgnorePointer(
              ignoring: true,
              child: GoogleMap(
                style: AppMapTheme.getMapStyle(isDark),
                onMapCreated: (ctrl) => AppMapTheme.applyTheme(ctrl, isDark),
                initialCameraPosition: CameraPosition(
                  target: pos,
                  zoom: 16.0,
                ),
                markers: {
                  Marker(
                    markerId: MarkerId(restaurant.id),
                    position: pos,
                    infoWindow: InfoWindow(
                      title: restaurant.name,
                      snippet: restaurant.address,
                    ),
                  ),
                },
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                tiltGesturesEnabled: false,
                rotateGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Builder(
                builder: (context) {
                  final isMapDark = Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMapDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.94) : Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isMapDark ? Colors.white12 : Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: AppTheme.primaryColor, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'GPS: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isMapDark ? Colors.white : AppTheme.navyColor),
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.restaurantMap,
                            arguments: {
                              'restaurant': restaurant,
                              'showDirections': false,
                            },
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.map_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text('Full Map', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskScoreCard(RestaurantModel restaurant) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eval = RestaurantStoreService.getRestaurantRiskEvaluation(
      restaurant.id,
      restaurantName: restaurant.name,
      fallbackRestaurant: restaurant,
    );
    final score = eval.score;
    final isSafe = eval.category == RiskCategory.safe;
    final isModerate = eval.category == RiskCategory.moderate;

    final Color statusColor = isSafe
        ? const Color(0xFF059669) // Emerald
        : isModerate
            ? const Color(0xFFD97706) // Amber
            : const Color(0xFFDC2626); // Red

    final Color bgColor = isSafe
        ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFECFDF5))
        : isModerate
            ? (isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7))
            : (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.35) : const Color(0xFFFEF2F2));

    final String statusText = isSafe
        ? 'Safe'
        : isModerate
            ? 'Moderate'
            : 'High Risk';

    final String headlineDesc = eval.headline;
    final String explanatoryText = eval.explanation;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Hygiene Risk',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : AppTheme.navyColor),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Risk Scale: 0 (Safest) to 100 (Highest Risk)',
                    child: Icon(Icons.info_outline_rounded, size: 16, color: isDark ? Colors.white38 : Colors.grey.shade400),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main Gauge + Meaning Info
          Row(
            children: [
              RiskScoreGauge(score: score, size: 76),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headlineDesc,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      explanatoryText,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _riskMetricRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Last Updated',
                            value: restaurant.lastUpdated,
                            valueColor: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: eval.isFromOfficer
                            ? (eval.category == RiskCategory.high
                                ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                                : const Color(0xFF0F766E).withValues(alpha: 0.1))
                            : (isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: eval.isFromOfficer
                              ? (eval.category == RiskCategory.high ? const Color(0xFFDC2626) : const Color(0xFF0F766E)).withValues(alpha: 0.3)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            eval.isFromOfficer ? Icons.verified_user_rounded : Icons.star_rate_rounded,
                            size: 12,
                            color: eval.isFromOfficer
                                ? (eval.category == RiskCategory.high ? const Color(0xFFDC2626) : const Color(0xFF0F766E))
                                : Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Basis: ${eval.source}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: eval.isFromOfficer
                                    ? (eval.category == RiskCategory.high ? const Color(0xFFDC2626) : const Color(0xFF0F766E))
                                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Visual 3-Segment Risk Meter Bar (0 to 100 Scale)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Risk Meter Scale',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                    Text(
                      '${score.toStringAsFixed(1)} / 100',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Multi-color Segment Bar with Needle Indicator
                LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final clampedScore = score.clamp(0.0, 100.0);
                    final pointerLeft = ((clampedScore / 100.0) * totalWidth).clamp(0.0, totalWidth - 12);

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Segmented bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 25,
                                child: Container(height: 8, color: const Color(0xFF10B981)), // Safe: 0-25
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                flex: 35,
                                child: Container(height: 8, color: const Color(0xFFF59E0B)), // Moderate: 26-60
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                flex: 40,
                                child: Container(height: 8, color: const Color(0xFFEF4444)), // High: 61-100
                              ),
                            ],
                          ),
                        ),
                        // Current Score Indicator Marker
                        Positioned(
                          left: pointerLeft,
                          top: -3,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: statusColor, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),

                // Range Legend Text
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        const Text('0-25 Safe', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        const Text('26-60 Moderate', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        const Text('61-100 High', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskMetricRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetId = _currentRestaurant?.id ?? '';
    final targetName = _currentRestaurant?.name ?? '';

    return ValueListenableBuilder<List<RestaurantModel>>(
      valueListenable: RestaurantStoreService.restaurantsNotifier,
      builder: (context, allRestaurants, _) {
        final restaurant = allRestaurants
                .where((r) =>
                    r.id == targetId ||
                    (targetName.isNotEmpty && r.name.toLowerCase() == targetName.toLowerCase()))
                .firstOrNull ??
            _currentRestaurant ??
            (allRestaurants.isNotEmpty ? allRestaurants.first : null);

        if (restaurant == null) {
          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
            appBar: const CustomAppBar(title: 'Restaurant Details'),
            body: const RestaurantDetailSkeleton(),
          );
        }

    final processedReviews = _getSortedAndFilteredReviews();
    final totalCount = processedReviews.length;
    final totalPages = (totalCount / _reviewsPerPage).ceil().clamp(1, 999);
    final currentPage = _currentReviewPage.clamp(1, totalPages);
    final startIndex = (currentPage - 1) * _reviewsPerPage;
    final paginatedReviews = processedReviews.skip(startIndex).take(_reviewsPerPage).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: restaurant.name,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showReportOptionsDialog(restaurant),
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Outlet Image with Banner Icons
            Stack(
              children: [
                _buildOutletImage(restaurant),
                // Approved Status Badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: StatusBadge.fromStatus(restaurant.status.name, isOnImage: true),
                ),
                // Safe Shield Status Icon
                Positioned(
                  top: 48,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF047857),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF047857).withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                // Saved Bookmark Banner Icon
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () async {
                      final saved = await BookmarkService.toggleBookmark(restaurant.id);
                      if (!mounted || !context.mounted) return;
                      setState(() {
                        _isSaved = saved;
                      });
                      HygieneFeedback.showSuccess(
                        context,
                        saved
                            ? '${restaurant.name} saved to your wishlist!'
                            : '${restaurant.name} removed from wishlist.',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: _isSaved ? const Color(0xFF0F766E) : Colors.grey,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Enforcement Banner (if applicable)
            if (restaurant.hasActiveEnforcement) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.35) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MOH Temporary Suspension Order',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            restaurant.isCompoundedOverdue
                                ? 'This food premises has been temporarily taken down and suspended due to overdue statutory compound penalties under Section 11 Food Act 1983.'
                                : 'This food premises is temporarily suspended by the Ministry of Health under Section 11 Food Act 1983 pending rectification and fine settlement.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.red.shade200 : const Color(0xFFB91C1C),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Restaurant Title & Category
            Text(
              restaurant.name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              restaurant.category,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 8),

            // Location Row
            Row(
              children: [
                const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    restaurant.address,
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),

            // Quick Actions Bar (Directions, Call, Report Issue)
            _buildOutletQuickActions(restaurant),
            const SizedBox(height: 8),

            // Dynamic Rating Summary Card
            _buildRatingSummaryCard(),
            const SizedBox(height: 16),

            // Embedded Interactive Map Section
            _buildInteractiveMapSection(restaurant),
            const SizedBox(height: 20),

            // Customer Reviews Header & Sort Dropdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.comment_bank_outlined, color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Customer Reviews (${_reviews.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                      ),
                    ),
                  ],
                ),
                _buildSortDropdown(isDark),
              ],
            ),
            const SizedBox(height: 8),

            // Comment Input Box OR Thank You Card for existing reviewer
            if (_findUserExistingReview() != null)
              _buildAlreadyReviewedCard(_findUserExistingReview()!)
            else
              _buildCommentInputCard(),

            // Review Filter Chips Bar
            if (_reviews.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All (${_reviews.length})', 0),
                    _filterChip('5 ★ Best', 5),
                    _filterChip('4 ★ Good', 4),
                    _filterChip('3 ★ Fair', 3),
                    _filterChip('1-2 ★ Poor', 2),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Active Sort Status & Info Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedSortOption == 'helpful'
                        ? 'Helpful Reviews'
                        : (_selectedSortOption == 'highest'
                            ? 'Highest Star Rating'
                            : (_selectedSortOption == 'lowest'
                                ? 'Critical Feedback'
                                : 'Most Recent')),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                    ),
                  ),
                  if (processedReviews.isNotEmpty)
                    Text(
                      'Page $currentPage of $totalPages',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Review Cards List or Empty State
            if (processedReviews.isEmpty)
              _buildEmptyReviewsState(isDark)
            else ...[
              ...paginatedReviews.asMap().entries.map((entry) {
                final pageIdx = entry.key;
                final globalIdx = startIndex + pageIdx;
                final review = entry.value;
                final starsCount = int.tryParse(review['stars'] ?? '5') ?? 5;
                final reviewKey = _getReviewKey(review, globalIdx);
                final isLiked = _isReviewLikedByCurrentUser(review);
                final helpfulCount = _getHelpfulCount(review, globalIdx);

                return _buildReviewCard(
                  review: review,
                  starsCount: starsCount,
                  isLiked: isLiked,
                  helpfulCount: helpfulCount,
                  isDark: isDark,
                  onHelpfulTap: () async {
                    final userIdent = _getCurrentUserIdentifier();
                    final rest = _currentRestaurant;
                    if (rest == null) return;

                    // Optimistic update of local review state
                    final rawLiked = review['likedUserIds'] ?? '[]';
                    List<String> list = [];
                    try {
                      if (rawLiked.startsWith('[')) {
                        list = List<String>.from(jsonDecode(rawLiked) as List);
                      } else if (rawLiked.isNotEmpty) {
                        list = rawLiked.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      }
                    } catch (_) {}

                    final clean = userIdent.toLowerCase().trim();
                    final customerEmail = (CustomerStoreService.currentCustomer?.email ?? '').toLowerCase().trim();
                    final bool wasLiked = list.map((e) => e.toLowerCase()).contains(clean) ||
                        (customerEmail.isNotEmpty && list.map((e) => e.toLowerCase()).contains(customerEmail));
                    final bool willBeLiked = !wasLiked;

                    setState(() {
                      if (willBeLiked) {
                        if (!list.map((e) => e.toLowerCase()).contains(clean)) {
                          list.add(userIdent.trim());
                        }
                      } else {
                        list.removeWhere((e) => e.toLowerCase() == clean || (customerEmail.isNotEmpty && e.toLowerCase() == customerEmail));
                      }
                      review['likedUserIds'] = jsonEncode(list);
                      review['helpfulCount'] = '${list.length}';
                    });

                    // Sync to Supabase cloud across all accounts and devices
                    final res = await RestaurantStoreService.toggleReviewHelpfulVote(
                      restaurantId: rest.id,
                      reviewIdOrKey: reviewKey,
                      userIdentifier: userIdent,
                      restaurantName: rest.name,
                      setLiked: willBeLiked,
                    );

                    if (mounted) {
                      setState(() {
                        final dynamic resReviews = res['reviews'];
                        if (resReviews is List) {
                          for (final r in resReviews) {
                            if (r is Map) {
                              final rId = r['id']?.toString() ?? '';
                              if (rId.isNotEmpty && (rId == review['id'] || review['id']?.contains(rId) == true)) {
                                review['likedUserIds'] = r['likedUserIds']?.toString() ?? jsonEncode(list);
                                break;
                              }
                            }
                          }
                        }
                        review['helpfulCount'] = '${res['helpfulCount'] ?? list.length}';
                      });
                    }
                  },
                );
              }),

              // Pagination Controls
              if (totalPages > 1) ...[
                const SizedBox(height: 8),
                _buildPaginationControls(
                  currentPage: currentPage,
                  totalPages: totalPages,
                  startIndex: startIndex,
                  totalCount: totalCount,
                  paginatedLength: paginatedReviews.length,
                  isDark: isDark,
                ),
              ],
            ],
            const SizedBox(height: 16),

            // Ultra-Premium Hygiene Risk Score Panel
            _buildRiskScoreCard(restaurant),
            const SizedBox(height: 20),

            // Bottom Action Comparison Button
            CustomButton(
              label: 'View Risk Rankings',
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.riskRankingList);
              },
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  String _getCurrentUserIdentifier() {
    final customer = CustomerStoreService.currentCustomer;
    if (customer != null && customer.id.trim().isNotEmpty) {
      return customer.id.trim();
    }
    if (customer != null && customer.email.trim().isNotEmpty) {
      return customer.email.trim();
    }
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser != null) {
      if (authUser.email != null && authUser.email!.isNotEmpty) {
        return authUser.email!.trim();
      }
      return authUser.id;
    }
    return 'customer_user';
  }

  bool _isReviewLikedByCurrentUser(Map<String, String> review) {
    final userIdent = _getCurrentUserIdentifier().toLowerCase();
    final customerEmail = (CustomerStoreService.currentCustomer?.email ?? '').toLowerCase().trim();
    final rawLiked = review['likedUserIds'] ?? '[]';
    List<String> list = [];
    try {
      if (rawLiked.startsWith('[')) {
        list = List<String>.from(jsonDecode(rawLiked) as List);
      } else if (rawLiked.isNotEmpty) {
        list = rawLiked.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}

    return list.map((e) => e.toLowerCase()).contains(userIdent) ||
        (customerEmail.isNotEmpty && list.map((e) => e.toLowerCase()).contains(customerEmail));
  }

  String _getReviewKey(Map<String, String> review, int fallbackIndex) {
    final user = review['userName'] ?? 'user';
    final date = review['date'] ?? '';
    final comment = review['comment'] ?? '';
    return review['id'] ?? '$user-$date-${comment.hashCode}-$fallbackIndex';
  }

  int _getHelpfulCount(Map<String, String> review, int fallbackIndex) {
    final rawLiked = review['likedUserIds'] ?? '[]';
    List<String> list = [];
    try {
      if (rawLiked.startsWith('[')) {
        list = List<String>.from(jsonDecode(rawLiked) as List);
      } else if (rawLiked.isNotEmpty) {
        list = rawLiked.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}

    return list.length;
  }

  List<Map<String, String>> _getSortedAndFilteredReviews() {
    // 1. Star Rating Filter
    List<Map<String, String>> list = _selectedFilterStar == 0
        ? List<Map<String, String>>.from(_reviews)
        : _reviews.where((r) {
            final s = int.tryParse(r['stars'] ?? '5') ?? 5;
            if (_selectedFilterStar == 2) {
              return s <= 2;
            }
            return s == _selectedFilterStar;
          }).toList();

    // Helper to extract true helpful thumbs up count
    int getHelpfulCount(Map<String, String> r) {
      final rawLiked = r['likedUserIds'] ?? '[]';
      List<String> likedList = [];
      try {
        if (rawLiked.startsWith('[')) {
          likedList = List<String>.from(jsonDecode(rawLiked) as List);
        } else if (rawLiked.isNotEmpty) {
          likedList = rawLiked.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {}

      return likedList.length;
    }

    // 2. Sorting: 5-Star with most helpful thumbs up displayed first on top
    if (_selectedSortOption == 'helpful' || _selectedSortOption == 'highest') {
      list.sort((a, b) {
        final aStars = int.tryParse(a['stars'] ?? '5') ?? 5;
        final bStars = int.tryParse(b['stars'] ?? '5') ?? 5;

        // Primary: Highest Rating Star First (5-star on top, then 4, 3, 2, 1)
        final starComp = bStars.compareTo(aStars);
        if (starComp != 0) return starComp;

        // Secondary: Most Helpful Thumbs Up votes on top
        final aHelpful = getHelpfulCount(a);
        final bHelpful = getHelpfulCount(b);
        final helpfulComp = bHelpful.compareTo(aHelpful);
        if (helpfulComp != 0) return helpfulComp;

        // Tertiary: Owner response & constructive comment depth
        final aHasReply = (a['ownerReply'] ?? '').isNotEmpty ? 10 : 0;
        final bHasReply = (b['ownerReply'] ?? '').isNotEmpty ? 10 : 0;
        final aDepth = aHasReply + (a['comment']?.length ?? 0);
        final bDepth = bHasReply + (b['comment']?.length ?? 0);
        return bDepth.compareTo(aDepth);
      });
    } else if (_selectedSortOption == 'lowest') {
      list.sort((a, b) {
        final aStars = int.tryParse(a['stars'] ?? '5') ?? 5;
        final bStars = int.tryParse(b['stars'] ?? '5') ?? 5;

        // Primary: Lowest Star Rating First (1 star on top)
        final starComp = aStars.compareTo(bStars);
        if (starComp != 0) return starComp;

        // Secondary: Most Helpful Thumbs Up votes on top
        final aHelpful = getHelpfulCount(a);
        final bHelpful = getHelpfulCount(b);
        return bHelpful.compareTo(aHelpful);
      });
    } else if (_selectedSortOption == 'recent') {
      // Natural chronological order / timestamp
    }

    return list;
  }

  Widget _buildSortDropdown(bool isDark) {
    return PopupMenuButton<String>(
      initialValue: _selectedSortOption,
      tooltip: 'Sort Reviews',
      onSelected: (val) {
        setState(() {
          _selectedSortOption = val;
          _currentReviewPage = 1;
        });
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'helpful',
          child: Row(
            children: [
              Icon(Icons.thumb_up_rounded, color: Color(0xFF0F766E), size: 18),
              SizedBox(width: 8),
              Text('Top Helpful', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'recent',
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, color: Color(0xFF0284C7), size: 18),
              SizedBox(width: 8),
              Text('Most Recent', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'highest',
          child: Row(
            children: [
              Icon(Icons.star_rounded, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Text('Highest Star Rating', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'lowest',
          child: Row(
            children: [
              Icon(Icons.star_outline_rounded, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text('Critical Feedback', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.2) : const Color(0xFFE6FFFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF14B8A6).withValues(alpha: 0.4) : const Color(0xFF99F6E4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedSortOption == 'helpful'
                  ? Icons.thumb_up_rounded
                  : (_selectedSortOption == 'highest'
                      ? Icons.star_rounded
                      : (_selectedSortOption == 'lowest' ? Icons.star_outline_rounded : Icons.schedule_rounded)),
              size: 14,
              color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
            ),
            const SizedBox(width: 4),
            Text(
              _selectedSortOption == 'helpful'
                  ? 'Top Helpful'
                  : (_selectedSortOption == 'highest'
                      ? 'Highest ★'
                      : (_selectedSortOption == 'lowest' ? 'Critical' : 'Recent')),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyReviewsState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.star_outline_rounded, size: 36, color: Colors.amber.shade700),
          ),
          const SizedBox(height: 12),
          Text(
            _selectedFilterStar == 0 ? 'No Customer Reviews Yet' : 'No $_selectedFilterStar Star Reviews',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : AppTheme.navyColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedFilterStar == 0
                ? 'Be the first to leave a review for this outlet!'
                : 'No reviews found matching this star rating filter.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard({
    required Map<String, String> review,
    required int starsCount,
    required bool isLiked,
    required int helpfulCount,
    required bool isDark,
    required VoidCallback onHelpfulTap,
  }) {
    final currentCustomer = CustomerStoreService.currentCustomer;
    final currentCustId = currentCustomer?.id.trim();
    final currentCustEmail = currentCustomer?.email.trim().toLowerCase();
    final currentCustName = currentCustomer?.name.trim();

    final rUserId = (review['userId'] ?? '').trim();
    final rUserEmail = (review['userEmail'] ?? '').trim().toLowerCase();
    final rUserName = (review['userName'] ?? 'Customer').trim();

    String displayAuthor = rUserName;
    String? displayAvatar = review['userAvatar'] ?? review['avatarUrl'];

    bool isCurrentUserReview = false;
    if (currentCustId != null && currentCustId.isNotEmpty && rUserId == currentCustId) {
      isCurrentUserReview = true;
    } else if (currentCustEmail != null && currentCustEmail.isNotEmpty && rUserEmail == currentCustEmail) {
      isCurrentUserReview = true;
    } else if (currentCustName != null && currentCustName.isNotEmpty && rUserName.toLowerCase() == currentCustName.toLowerCase()) {
      isCurrentUserReview = true;
    } else if (currentCustName != null &&
        (currentCustName.toLowerCase() == 'ahmeng' || currentCustName.toLowerCase() == 'ahmad') &&
        (rUserName.toLowerCase() == 'ahmad' || rUserName.toLowerCase() == 'ahmeng')) {
      isCurrentUserReview = true;
    }

    if (isCurrentUserReview && currentCustName != null && currentCustName.isNotEmpty) {
      displayAuthor = currentCustName;
      if (currentCustomer?.avatarUrl != null && currentCustomer!.avatarUrl.isNotEmpty) {
        displayAvatar = currentCustomer.avatarUrl;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                avatarUrl: displayAvatar,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayAuthor,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      review['date'] ?? '',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (starIndex) {
                  return Icon(
                    starIndex < starsCount ? Icons.star_rounded : Icons.star_border_rounded,
                    color: starIndex < starsCount ? Colors.amber : (isDark ? Colors.white24 : Colors.grey.shade400),
                    size: 16,
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            review['comment'] ?? '',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87, height: 1.4),
          ),
          if ((review['ownerReply'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121212) : const Color(0xFF0C2340).withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.5) : AppTheme.primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.storefront_rounded, size: 14, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Official Response from Restaurant Owner',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF5EEAD4) : AppTheme.navyColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          review['ownerReply']!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white70 : const Color(0xFF282828),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⭐ $starsCount/5 Rating',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade700),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onHelpfulTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLiked
                        ? (isDark ? const Color(0xFF0F766E).withValues(alpha: 0.28) : const Color(0xFFE6FFFA))
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isLiked
                          ? (isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488))
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        size: 13,
                        color: isLiked
                            ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E))
                            : (isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        helpfulCount > 0 ? 'Helpful ($helpfulCount)' : 'Helpful',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isLiked ? FontWeight.bold : FontWeight.w500,
                          color: isLiked
                              ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E))
                              : (isDark ? Colors.white70 : Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls({
    required int currentPage,
    required int totalPages,
    required int startIndex,
    required int totalCount,
    required int paginatedLength,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Previous Page Button
              OutlinedButton.icon(
                onPressed: currentPage > 1
                    ? () {
                        setState(() {
                          _currentReviewPage = currentPage - 1;
                        });
                      }
                    : null,
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 12),
                label: const Text('Prev', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side: BorderSide(
                    color: currentPage > 1 ? const Color(0xFF0F766E) : (isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                  foregroundColor: const Color(0xFF0F766E),
                  disabledForegroundColor: isDark ? Colors.white24 : Colors.grey.shade400,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),

              // Page Number Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(totalPages, (idx) {
                  final pageNum = idx + 1;
                  final isCurrent = pageNum == currentPage;

                  return GestureDetector(
                    onTap: () {
                      if (_currentReviewPage != pageNum) {
                        setState(() {
                          _currentReviewPage = pageNum;
                        });
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF0F766E) : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        '$pageNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCurrent ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // Next Page Button
              OutlinedButton(
                onPressed: currentPage < totalPages
                    ? () {
                        setState(() {
                          _currentReviewPage = currentPage + 1;
                        });
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side: BorderSide(
                    color: currentPage < totalPages ? const Color(0xFF0F766E) : (isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                  foregroundColor: const Color(0xFF0F766E),
                  disabledForegroundColor: isDark ? Colors.white24 : Colors.grey.shade400,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Next', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Showing ${startIndex + 1}–${(startIndex + paginatedLength).clamp(0, totalCount)} of $totalCount verified reviews',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int starVal) {
    final isSelected = _selectedFilterStar == starVal;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF00A88F),
        backgroundColor: const Color(0xFFF1F5F9),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : const Color(0xFF475569),
        ),
        onSelected: (selected) {
          setState(() {
            _selectedFilterStar = selected ? starVal : 0;
            _currentReviewPage = 1;
          });
        },
      ),
    );
  }
}
