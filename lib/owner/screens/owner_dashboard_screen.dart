import '../widgets/owner_next_actions.dart';
import '../../core/widgets/app_select_field.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/notification_service.dart';
import '../../notifications/models/notification_model.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/uuid_helper.dart';
import '../../core/utils/case_ordering.dart';
import '../widgets/deadline_countdown_badge.dart';
import '../widgets/moh_payment_gateway_sheet.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _currentBottomTabIndex = 0;
  int _noticeTab = 0; // 0 = Active, 1 = Closed
  int _noticeAuthorityIndex = 0; // 0 = All, 1 = Government, 2 = Admin, 3 = Complaints

  // Dynamic Owner Profile Data
  String _ownerName = '';
  String _ownerEmail = '';
  String _ownerPhone = '';

  // Restaurant List & Filter State
  List<RestaurantModel> _fetchedOwnerRestaurants = [];
  bool _isLoadingRestaurants = true;
  int _restaurantFilterIndex = 0; // 0 = All, 1 = Active, 2 = Pending

  // Selected Active Restaurant State & Persistence
  String? _selectedRestaurantId;

  /// Returns the currently active selected restaurant for display across the dashboard
  RestaurantModel? get _activeSelectedRestaurant {
    if (_fetchedOwnerRestaurants.isEmpty) return null;
    if (_selectedRestaurantId != null && _selectedRestaurantId!.isNotEmpty) {
      final match = _fetchedOwnerRestaurants.where((r) => r.id == _selectedRestaurantId).firstOrNull;
      if (match != null) return match;
    }
    return _approvedOwnerRestaurants.firstOrNull ?? _fetchedOwnerRestaurants.firstOrNull;
  }

  Future<void> _loadSavedSelectedRestaurant(String? ownerUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedId = prefs.getString('owner_selected_restaurant_id_$ownerUserId') ??
          prefs.getString('owner_selected_restaurant_id');

      // If not found in SharedPreferences (e.g. app reinstalled or new device), check Supabase users.settings
      if ((savedId == null || savedId.isEmpty) && ownerUserId != null && ownerUserId.isNotEmpty) {
        try {
          final supabase = SupabaseService.client;
          final userResp = await supabase
              .from('users')
              .select('settings')
              .eq('id', ownerUserId)
              .maybeSingle();

          if (userResp != null && userResp['settings'] is Map) {
            final settings = Map<String, dynamic>.from(userResp['settings']);
            savedId = settings['selected_restaurant_id']?.toString();
            if (savedId != null && savedId.isNotEmpty) {
              await prefs.setString('owner_selected_restaurant_id_$ownerUserId', savedId);
              await prefs.setString('owner_selected_restaurant_id', savedId);
            }
          }
        } catch (_) {}
      }

      if (savedId != null && savedId.isNotEmpty && mounted) {
        setState(() {
          _selectedRestaurantId = savedId;
        });
      }
    } catch (_) {}
  }

  Future<void> _setSelectedRestaurant(RestaurantModel restaurant) async {
    setState(() {
      _selectedRestaurantId = restaurant.id;
      final idx = _fetchedOwnerRestaurants.indexWhere((r) => r.id == restaurant.id);
      if (idx != -1) {
        _selectedAnalyticsOutletIndex = idx;
      }
      _reviewCurrentPage = 0;
    });

    _fetchOutletReviewsForAnalytics(restaurant.id, force: true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final user = CustomerStoreService.currentCustomer ?? await CustomerStoreService.fetchActiveUserSession();
      final ownerUserId = user?.id ?? SupabaseService.client.auth.currentUser?.id;

      if (ownerUserId != null && ownerUserId.isNotEmpty) {
        await prefs.setString('owner_selected_restaurant_id_$ownerUserId', restaurant.id);
      }
      await prefs.setString('owner_selected_restaurant_id', restaurant.id);

      // Persist to Supabase users.settings so reinstallation / flutter run preserves the user's selected restaurant
      if (ownerUserId != null && ownerUserId.isNotEmpty) {
        try {
          final supabase = SupabaseService.client;
          final userResp = await supabase
              .from('users')
              .select('settings')
              .eq('id', ownerUserId)
              .maybeSingle();

          Map<String, dynamic> settings = {};
          if (userResp != null && userResp['settings'] is Map) {
            settings = Map<String, dynamic>.from(userResp['settings']);
          }
          settings['selected_restaurant_id'] = restaurant.id;
          settings['selected_restaurant_name'] = restaurant.name;

          await supabase
              .from('users')
              .update({'settings': settings})
              .eq('id', ownerUserId);
        } catch (e) {
          debugPrint('Failed to save selected_restaurant_id to Supabase: $e');
        }
      }
    } catch (_) {}
  }

  void _showSwitchRestaurantModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allList = _fetchedOwnerRestaurants;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final currentSelectedId = _activeSelectedRestaurant?.id;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Drag Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Header Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Switch Active Restaurant',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.navyColor,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Select which restaurant to display on your dashboard',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Restaurant List
                  Flexible(
                    child: allList.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'No registered restaurants found.',
                                style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            shrinkWrap: true,
                            itemCount: allList.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 10),
                            itemBuilder: (c, i) {
                              final rst = allList[i];
                              final isSelected = (rst.id == currentSelectedId);
                              final isApproved = (rst.status == RestaurantStatus.approved);

                              return InkWell(
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await _setSelectedRestaurant(rst);
                                  if (!mounted || !context.mounted) return;
                                  HygieneFeedback.showSuccess(context, 'Dashboard switched to "${rst.name}"');
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? AppTheme.primaryColor.withValues(alpha: 0.15) : const Color(0xFFF0FDF4))
                                        : (isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? (isDark ? AppTheme.primaryColor : const Color(0xFF10B981))
                                          : (isDark ? Colors.white10 : Colors.grey.shade200),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isApproved
                                              ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                              : const Color(0xFFD97706).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isApproved ? Icons.storefront_rounded : Icons.hourglass_top_rounded,
                                          color: isApproved ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    rst.name,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isSelected) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      'ACTIVE',
                                                      style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${rst.category} • ${rst.address}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                        color: isSelected ? const Color(0xFF10B981) : (isDark ? Colors.white30 : Colors.grey.shade400),
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Bottom Register Restaurant Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await Navigator.pushNamed(context, AppRoutes.addRestaurant);
                          _loadOwnerRestaurants();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18, color: AppTheme.primaryColor),
                        label: const Text(
                          'Register Another Restaurant',
                          style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
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


  // Analytics Real Data State
  int _selectedAnalyticsOutletIndex = 0;
  List<Map<String, String>> _dynamicOutletReviews = [];
  bool _isLoadingOutletReviews = false;
  String? _loadedAnalyticsRestId;

  // Review Filters & Pagination State
  String _reviewFilter = 'All'; // 'All', 'Today', 'Week', 'Month', '5 Stars', '4 Stars', '3 Stars', '2 Stars', '1 Star'
  int _reviewCurrentPage = 0;
  static const int _reviewPageSize = 3;

  static const List<Map<String, String>> _reviewFilterOptions = [
    {'key': 'All', 'label': 'All Reviews'},
    {'key': 'Today', 'label': 'Today'},
    {'key': 'Week', 'label': 'This Week'},
    {'key': 'Month', 'label': 'This Month'},
    {'key': '5 Stars', 'label': '5 Stars'},
    {'key': '4 Stars', 'label': '4 Stars'},
    {'key': '3 Stars', 'label': '3 Stars'},
    {'key': '2 Stars', 'label': '2 Stars'},
    {'key': '1 Star', 'label': '1 Star'},
  ];

  @override
  void initState() {
    super.initState();
    _loadOwnerSession();
    _loadOwnerRestaurants();
    ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
    RestaurantStoreService.fetchInspections();
    ComplaintStoreService.complaintsNotifier.addListener(_onNoticesDataChanged);
    RestaurantStoreService.inspectionsNotifier.addListener(_onNoticesDataChanged);
  }

  @override
  void dispose() {
    ComplaintStoreService.complaintsNotifier.removeListener(_onNoticesDataChanged);
    RestaurantStoreService.inspectionsNotifier.removeListener(_onNoticesDataChanged);
    super.dispose();
  }

  void _onNoticesDataChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadOwnerSession() async {
    final user = await CustomerStoreService.fetchActiveUserSession() ?? CustomerStoreService.currentCustomer;
    if (user != null && mounted) {
      setState(() {
        _ownerName = user.name;
        _ownerEmail = user.email;
        _ownerPhone = user.phone ?? '';
      });
    }
  }

  Future<void> _fetchOutletReviewsForAnalytics(String restaurantId, {bool force = false}) async {
    if (!force && _loadedAnalyticsRestId == restaurantId && _dynamicOutletReviews.isNotEmpty) return;
    _loadedAnalyticsRestId = restaurantId;
    if (mounted) setState(() => _isLoadingOutletReviews = true);
    final reviews = await RestaurantStoreService.fetchReviews(restaurantId);
    if (mounted) {
      setState(() {
        _dynamicOutletReviews = List<Map<String, String>>.from(reviews);
        _isLoadingOutletReviews = false;
        _reviewCurrentPage = 0;
      });
    }
  }

  Future<void> _loadOwnerRestaurants() async {
    if (mounted) {
      setState(() {
        _isLoadingRestaurants = true;
      });
    }

    final user = CustomerStoreService.currentCustomer ?? await CustomerStoreService.fetchActiveUserSession();
    final String? currentUserId = user?.id ?? SupabaseService.client.auth.currentUser?.id;
    final String? currentUserEmail = user?.email ?? SupabaseService.client.auth.currentUser?.email;

    final restaurants = await RestaurantStoreService.fetchOwnerRestaurants(currentUserId, ownerEmail: currentUserEmail);

    if (mounted) {
      setState(() {
        _fetchedOwnerRestaurants = restaurants;
        _isLoadingRestaurants = false;
      });

      // Load saved restaurant ID if not set yet or verify existing selection
      await _loadSavedSelectedRestaurant(currentUserId);

      final active = _activeSelectedRestaurant;
      if (active != null) {
        final idx = restaurants.indexWhere((r) => r.id == active.id);
        if (idx != -1) {
          _selectedAnalyticsOutletIndex = idx;
        }
        _fetchOutletReviewsForAnalytics(active.id);
      }
    }
  }

  /// Returns all restaurants owned by the current user fetched from Supabase
  List<RestaurantModel> get _allMyOwnerRestaurants => _fetchedOwnerRestaurants;

  /// Returns ONLY approved/verified active restaurants for display in main header & active metrics
  List<RestaurantModel> get _approvedOwnerRestaurants {
    return _fetchedOwnerRestaurants.where((r) => r.status == RestaurantStatus.approved).toList();
  }



  // Real Reviews Data with Owner Responses for Analytics Monitoring
  final List<Map<String, String>> _ownerReviews = [];

  void _showEditProfileDetailsDialog() {
    final currentCustomer = CustomerStoreService.currentCustomer;
    final nameCtrl = TextEditingController(text: _ownerName);
    final emailCtrl = TextEditingController(text: _ownerEmail);
    final phoneCtrl = TextEditingController(text: _ownerPhone);

    String? selectedGender = currentCustomer?.gender;
    String? selectedCountry = currentCustomer?.country;
    String? selectedState = currentCustomer?.state;

    final customGenderCtrl = TextEditingController();
    final customCountryCtrl = TextEditingController();
    final customStateCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              surfaceTintColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Card Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          gradient: LinearGradient(
                            colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('Edit Profile Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  Text('Manage personal info & business location', style: TextStyle(fontSize: 11, color: Colors.white70)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white70),
                              onPressed: () => Navigator.pop(dialogCtx),
                            ),
                          ],
                        ),
                      ),

                      // Form Body
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Full Name
                            TextField(
                              controller: nameCtrl,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Owner Full Name *',
                                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.person_rounded, color: AppTheme.primaryColor),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. Email Address
                            TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Email Address *',
                                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.email_rounded, color: Color(0xFF0284C7)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 3. Phone Number
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF0F766E)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 4. Gender
                            Text('Gender', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : AppTheme.navyColor)),
                            const SizedBox(height: 6),
                            AppSelectField<String>(
                              initialValue: ['Male', 'Female', 'Other'].contains(selectedGender) ? selectedGender : (selectedGender != null ? 'Other' : null),
                              dropdownColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              borderRadius: BorderRadius.circular(16),
                              elevation: 4,
                              menuMaxHeight: 220,
                              decoration: InputDecoration(
                                hintText: 'Select Gender',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                                prefixIcon: const Icon(Icons.wc_rounded, color: Color(0xFF8B5CF6)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g, style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor)))).toList(),
                              onChanged: (val) => setDialogState(() => selectedGender = val),
                            ),
                            if (selectedGender == 'Other') ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: customGenderCtrl,
                                style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Specify gender...',
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.8)),
                                  filled: true,
                                  fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),

                            // 5. Country / Region
                            Text('Country / Region', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : AppTheme.navyColor)),
                            const SizedBox(height: 6),
                            AppSelectField<String>(
                              initialValue: ['Malaysia', 'Singapore', 'Indonesia', 'Thailand', 'Other'].contains(selectedCountry) ? selectedCountry : (selectedCountry != null ? 'Other' : null),
                              dropdownColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              borderRadius: BorderRadius.circular(16),
                              elevation: 4,
                              menuMaxHeight: 220,
                              decoration: InputDecoration(
                                hintText: 'Select Country',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                                prefixIcon: const Icon(Icons.public_rounded, color: Color(0xFF0284C7)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              items: ['Malaysia', 'Singapore', 'Indonesia', 'Thailand', 'Other']
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor))))
                                  .toList(),
                              onChanged: (val) => setDialogState(() => selectedCountry = val),
                            ),
                            if (selectedCountry == 'Other') ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: customCountryCtrl,
                                style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Enter country name...',
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.8)),
                                  filled: true,
                                  fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),

                            // 6. State / City
                            Text('State / City', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : AppTheme.navyColor)),
                            const SizedBox(height: 6),
                            AppSelectField<String>(
                              initialValue: ['Kuala Lumpur', 'Selangor', 'Johor', 'Penang', 'Perak', 'Sabah', 'Sarawak', 'Other'].contains(selectedState) ? selectedState : (selectedState != null ? 'Other' : null),
                              dropdownColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              borderRadius: BorderRadius.circular(16),
                              elevation: 4,
                              menuMaxHeight: 220,
                              decoration: InputDecoration(
                                hintText: 'Select State / City',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                                prefixIcon: const Icon(Icons.location_city_rounded, color: Color(0xFFD97706)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              items: ['Kuala Lumpur', 'Selangor', 'Johor', 'Penang', 'Perak', 'Sabah', 'Sarawak', 'Other']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor))))
                                  .toList(),
                              onChanged: (val) => setDialogState(() => selectedState = val),
                            ),
                            if (selectedState == 'Other') ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: customStateCtrl,
                                style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Enter state or city name...',
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.8)),
                                  filled: true,
                                  fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),

                            // Action Buttons Row
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      side: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: isSaving ? null : () async {
                                      if (nameCtrl.text.trim().isEmpty) {
                                        HygieneFeedback.showWarning(context, 'Name cannot be empty!');
                                        return;
                                      }

                                      final finalGender = selectedGender == 'Other' ? customGenderCtrl.text.trim() : selectedGender;
                                      final finalCountry = selectedCountry == 'Other' ? customCountryCtrl.text.trim() : selectedCountry;
                                      final finalState = selectedState == 'Other' ? customStateCtrl.text.trim() : selectedState;

                                      final nav = Navigator.of(dialogCtx);
                                      setDialogState(() => isSaving = true);

                                      await CustomerStoreService.updateCustomerProfile(
                                        name: nameCtrl.text.trim(),
                                        email: emailCtrl.text.trim(),
                                        phone: phoneCtrl.text.trim(),
                                        gender: finalGender,
                                        country: finalCountry,
                                        state: finalState,
                                      );

                                      if (mounted) {
                                        setState(() {
                                          _ownerName = nameCtrl.text.trim();
                                          _ownerEmail = emailCtrl.text.trim();
                                          _ownerPhone = phoneCtrl.text.trim();
                                        });

                                        AuditLogService.logAction(
                                          actionType: 'PROFILE_UPDATE',
                                          category: 'Account Modification',
                                          title: 'Profile Details Updated',
                                          description: 'Updated profile name, email, phone, gender, country, and state',
                                        );

                                        nav.pop();
                                        HygieneFeedback.showSuccess(context, 'Profile details updated successfully!');
                                      }
                                    },
                                    child: isSaving
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Save Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            );
          },
        );
      },
    );
  }

  void _showChangePasswordDialog() {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final newPass = newPassCtrl.text;
            
            // Password Strength calculation
            int strengthScore = 0;
            if (newPass.length >= 6) strengthScore++;
            if (newPass.length >= 8) strengthScore++;
            if (RegExp(r'[A-Z]').hasMatch(newPass)) strengthScore++;
            if (RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]').hasMatch(newPass)) strengthScore++;

            String strengthLabel = 'Weak Password';
            Color strengthColor = Colors.red;
            if (strengthScore >= 3) {
              strengthLabel = 'Strong Password';
              strengthColor = const Color(0xFF0F766E);
            } else if (strengthScore == 2) {
              strengthLabel = 'Medium Strength';
              strengthColor = Colors.orange;
            }

            return Dialog(
              backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              surfaceTintColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Card Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          gradient: LinearGradient(
                            colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  Text('Secure businessman account credentials', style: TextStyle(fontSize: 11, color: Colors.white70)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white70),
                              onPressed: () => Navigator.pop(dialogCtx),
                            ),
                          ],
                        ),
                      ),

                      // Form Body
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Current Password
                            TextField(
                              controller: currentPassCtrl,
                              obscureText: obscureCurrent,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Current Password *',
                                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFF0284C7)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                suffixIcon: IconButton(
                                  icon: Icon(obscureCurrent ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                  onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 2. New Password
                            TextField(
                              controller: newPassCtrl,
                              obscureText: obscureNew,
                              onChanged: (_) => setDialogState(() {}),
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'New Password *',
                                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primaryColor),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                suffixIcon: IconButton(
                                  icon: Icon(obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                  onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                                ),
                              ),
                            ),
                            
                            if (newPass.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: (strengthScore / 4).clamp(0.1, 1.0),
                                        color: strengthColor,
                                        backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                                        minHeight: 6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    strengthLabel,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: strengthColor),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 16),

                            // 3. Confirm New Password
                            TextField(
                              controller: confirmPassCtrl,
                              obscureText: obscureConfirm,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Confirm New Password *',
                                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.check_circle_rounded, color: Color(0xFF0F766E)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                suffixIcon: IconButton(
                                  icon: Icon(obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                  onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Action Buttons Row
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      side: BorderSide(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade300),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: isSaving ? null : () async {
                                      final currentPass = currentPassCtrl.text;
                                      final newPass = newPassCtrl.text;
                                      final confirmPass = confirmPassCtrl.text;

                                      if (currentPass.isEmpty) {
                                        HygieneFeedback.showWarning(context, 'Please enter your current password');
                                        return;
                                      }

                                      if (newPass.length < 6) {
                                        HygieneFeedback.showWarning(context, 'New password must be at least 6 characters');
                                        return;
                                      }

                                      if (newPass != confirmPass) {
                                        HygieneFeedback.showWarning(context, 'New passwords do not match!');
                                        return;
                                      }

                                      final nav = Navigator.of(dialogCtx);
                                      setDialogState(() => isSaving = true);

                                      final result = await CustomerStoreService.changePassword(
                                        oldPassword: currentPass,
                                        newPassword: newPass,
                                      );

                                      setDialogState(() => isSaving = false);
                                      if (!mounted) return;

                                      if (result.success) {
                                        nav.pop();
                                        HygieneFeedback.showSuccess(context, 'Account password updated successfully!');
                                      } else {
                                        HygieneFeedback.showError(context, result.message);
                                      }
                                    },
                                    child: isSaving
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Update Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            );
          },
        );
      },
    );
  }

  void _showEditRestaurantDetailsDialogFor(RestaurantModel rst) {
    final nameCtrl = TextEditingController(text: rst.name);
    final hoursCtrl = TextEditingController(text: rst.operatingHours);
    final addrCtrl = TextEditingController(text: rst.address);

    XFile? bannerFile;
    String activeImageUrl = rst.imageUrl;
    bool isSaving = false;
    final ImagePicker picker = ImagePicker();

    final List<Map<String, String>> presetBanners = [
      {
        'title': 'Noodles & Asian',
        'url': 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?q=80&w=800',
      },
      {
        'title': 'Malay Rice & Lauk',
        'url': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?q=80&w=800',
      },
      {
        'title': 'Mamak & Roti Canai',
        'url': 'https://images.unsplash.com/photo-1565557623262-b51c2513a641?q=80&w=800',
      },
      {
        'title': 'Modern Western Diner',
        'url': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?q=80&w=800',
      },
      {
        'title': 'Cafe & Bakery',
        'url': 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?q=80&w=800',
      },
      {
        'title': 'Seafood Grill & BBQ',
        'url': 'https://images.unsplash.com/photo-1544025162-d76694265947?q=80&w=800',
      },
    ];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            Future<void> pickBanner(ImageSource source) async {
              try {
                final XFile? image = await picker.pickImage(
                  source: source,
                  maxWidth: 1920,
                  maxHeight: 1080,
                  imageQuality: 85,
                );
                if (image != null) {
                  setDialogState(() {
                    bannerFile = image;
                  });
                }
              } catch (_) {}
            }

            void showChangeBannerSheet() {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (sheetCtx) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        Row(
                          children: [
                            const Icon(Icons.add_a_photo_rounded, color: AppTheme.primaryColor, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              'Change Store Cover Banner',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.navyColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Upload a custom storefront photo or choose a preset banner.',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  pickBanner(ImageSource.camera);
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.18 : 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    children: const [
                                      Icon(Icons.camera_alt_rounded, color: Color(0xFF0F766E), size: 28),
                                      SizedBox(height: 6),
                                      Text('Take Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F766E))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  pickBanner(ImageSource.gallery);
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7).withValues(alpha: isDark ? 0.18 : 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    children: const [
                                      Icon(Icons.photo_library_rounded, color: Color(0xFF0284C7), size: 28),
                                      SizedBox(height: 6),
                                      Text('Choose Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0284C7))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text('Or Select Preset Banner Gallery:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: presetBanners.length,
                            separatorBuilder: (sCtx, i) => const SizedBox(width: 10),
                            itemBuilder: (sCtx, idx) {
                              final p = presetBanners[idx];
                              return InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    activeImageUrl = p['url']!;
                                    bannerFile = null;
                                  });
                                  Navigator.pop(sheetCtx);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 130,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: activeImageUrl == p['url'] ? AppTheme.primaryColor : (isDark ? AppTheme.darkBorderColor : Colors.grey.shade300), width: 2),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(p['url']!, fit: BoxFit.cover),
                                        Positioned(
                                          bottom: 4,
                                          left: 4,
                                          right: 4,
                                          child: Text(
                                            p['title']!,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  );
                },
              );
            }

            return Dialog(
              backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              surfaceTintColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Banner & Header Image Top Container
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                            child: SizedBox(
                              height: 160,
                              width: double.infinity,
                              child: bannerFile != null
                                  ? Image.file(File(bannerFile!.path), fit: BoxFit.cover)
                                  : Image.network(
                                      activeImageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, err, stack) => Container(
                                        color: Colors.grey.shade300,
                                        child: const Icon(Icons.storefront, size: 50, color: Colors.grey),
                                      ),
                                    ),
                            ),
                          ),
                          Container(
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              gradient: LinearGradient(
                                colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: IconButton.filledTonal(
                              style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                          Positioned(
                            bottom: 14,
                            left: 16,
                            right: 16,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Edit Premises Details',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.3),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Update storefront info & cover photo',
                                      style: TextStyle(fontSize: 11, color: Colors.white70),
                                    ),
                                  ],
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: showChangeBannerSheet,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                                            SizedBox(width: 6),
                                            Text(
                                              'Change Banner',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Form Body
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Restaurant Premises Name *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: nameCtrl,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Enter official restaurant name',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 12),
                                prefixIcon: const Icon(Icons.storefront_rounded, color: Color(0xFF0F766E), size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Text(
                              'Operating Hours *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: hoursCtrl,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. 10:00 AM - 10:00 PM (Daily)',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 12),
                                prefixIcon: const Icon(Icons.access_time_rounded, color: Color(0xFF0F766E), size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Text(
                              'Premises Address *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: addrCtrl,
                              maxLines: 2,
                              style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Enter complete business premise address',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 12),
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(bottom: 24),
                                  child: Icon(Icons.location_on_rounded, color: Color(0xFF0F766E), size: 20),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.8)),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Action Buttons Row
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF0F766E), Color(0xFF0284C7)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: isSaving ? null : () async {
                                      final newName = nameCtrl.text.trim();
                                      final newHours = hoursCtrl.text.trim();
                                      final newAddr = addrCtrl.text.trim();

                                      if (newName.isEmpty) return;

                                      final nav = Navigator.of(ctx);
                                      setDialogState(() => isSaving = true);

                                      // Process image banner encoding if new file was picked
                                      String finalBannerUrl = activeImageUrl;
                                      if (bannerFile != null) {
                                        try {
                                          final bytes = await File(bannerFile!.path).readAsBytes();
                                          finalBannerUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                                        } catch (_) {
                                          finalBannerUrl = bannerFile!.path;
                                        }
                                      }

                                      // 1. Update in Supabase
                                      try {
                                        await SupabaseService.client.from('restaurants').update({
                                          'name': newName,
                                          'address': newAddr,
                                          'operating_hours': newHours,
                                          'image_url': finalBannerUrl,
                                          'last_updated': DateTime.now().toUtc().toIso8601String(),
                                        }).eq('id', rst.id);
                                      } catch (e) {
                                        if (kDebugMode) print('Supabase edit restaurant error: $e');
                                      }

                                      // 2. Refresh store
                                      RestaurantStoreService.fetchAllRestaurants(forceRefresh: true);

                                      // 3. Log Audit
                                      AuditLogService.logAction(
                                        actionType: 'REST_UPDATED',
                                        category: 'Business',
                                        title: 'Updated Premises & Banner',
                                        description: 'Updated details and storefront cover banner photo for $newName',
                                      );

                                      if (mounted) {
                                        _loadOwnerRestaurants();
                                        nav.pop();
                                        HygieneFeedback.showSuccess(context, 'Premises details & banner image updated successfully!');
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      child: Center(
                                        child: isSaving
                                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                            : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                      ),
                                    ),
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
              ),
            );
          },
        );
      },
    );
  }

  void _showOwnerReplyDialog(int index, String restaurantId) {
    final currentReviews = _dynamicOutletReviews.isNotEmpty ? _dynamicOutletReviews : _ownerReviews;
    if (index >= currentReviews.length) return;

    final targetReview = currentReviews[index];
    final currentReply = targetReview['ownerReply'] ?? '';
    final customerName = targetReview['userName'] ?? 'Customer';
    final commentText = targetReview['comment'] ?? '';
    final rawStars = targetReview['stars'] ?? targetReview['rating'] ?? '5';
    final double starsVal = double.tryParse(rawStars.toString()) ?? 5.0;

    final replyCtrl = TextEditingController(text: currentReply);

    final quickTemplates = [
      'Thank you for your review! We look forward to seeing you again.',
      'Thank you for your feedback. We are committed to maintaining the highest hygiene & service standards.',
      'We appreciate your support and always prioritize diner safety and cleanliness.',
      'Thank you! Our kitchen and service team are delighted you had a great experience.',
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Premium Navy-to-Teal Gradient Hero Header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 1.2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.rate_review_rounded,
                                  color: Color(0xFF38BDF8),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Reply to $customerName',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Public Verified Merchant Response',
                                      style: TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                                onPressed: () => Navigator.pop(ctx),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),

                        // 2. Dialog Content Area
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Customer Review Quote Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border(
                                    left: const BorderSide(color: Color(0xFF0F766E), width: 3.5),
                                    top: BorderSide(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                                    right: BorderSide(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                                    bottom: BorderSide(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 12,
                                              backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                              child: Text(
                                                customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              customerName,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : AppTheme.navyColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Star Rating Chips
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                                              const SizedBox(width: 4),
                                              Text(
                                                starsVal.toStringAsFixed(1),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFD97706),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      commentText.isNotEmpty ? '“$commentText”' : '“(No comment text provided)”',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 13,
                                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Header for input
                              Row(
                                children: [
                                  const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF0F766E)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Your Official Response',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Enhanced Text Field
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? AppTheme.darkBorderColor : const Color(0xFFCBD5E1),
                                    width: 1.2,
                                  ),
                                ),
                                child: TextField(
                                  controller: replyCtrl,
                                  onChanged: (_) => setDialogState(() {}),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white : AppTheme.navyColor,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Write a courteous, professional response for your diners...',
                                    hintStyle: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                                    ),
                                    contentPadding: const EdgeInsets.all(14),
                                    border: InputBorder.none,
                                  ),
                                  maxLines: 4,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Quick Reply Templates Header
                              Text(
                                'Quick Suggestions',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Quick Templates Chip List
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: quickTemplates.map((template) {
                                  return ActionChip(
                                    avatar: const Icon(Icons.flash_on_rounded, size: 13, color: Color(0xFF0F766E)),
                                    backgroundColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9),
                                    side: BorderSide(
                                      color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    label: Text(
                                      template.length > 32 ? '${template.substring(0, 32)}...' : template,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                                      ),
                                    ),
                                    onPressed: () {
                                      replyCtrl.text = template;
                                      setDialogState(() {});
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 22),

                              // Dialog Actions
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 46,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: isDark ? Colors.white70 : Colors.grey.shade700,
                                          side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: 46,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF0F766E),
                                          foregroundColor: Colors.white,
                                          elevation: 2,
                                          shadowColor: const Color(0xFF0F766E).withValues(alpha: 0.4),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                        onPressed: replyCtrl.text.trim().isEmpty
                                            ? null
                                            : () async {
                                                final newText = replyCtrl.text.trim();
                                                if (newText.isNotEmpty) {
                                                  if (_dynamicOutletReviews.isNotEmpty && index < _dynamicOutletReviews.length) {
                                                    final targetReview = _dynamicOutletReviews[index];
                                                    final reviewerUserId = targetReview['userId'] ?? '';
                                                    final reviewerEmail = targetReview['userEmail'] ?? '';
                                                    final restName = _approvedOwnerRestaurants.isNotEmpty ? _approvedOwnerRestaurants.first.name : 'testing';

                                                    setState(() {
                                                      _dynamicOutletReviews[index]['ownerReply'] = newText;
                                                    });
                                                    await RestaurantStoreService.saveReviewsToSupabase(restaurantId, _dynamicOutletReviews, restaurantName: restName);

                                                    await AuditLogService.logAction(
                                                      actionType: 'REVIEW_REPLY_POSTED',
                                                      category: 'Business',
                                                      title: 'Review Response Posted',
                                                      description: 'Owner replied to a customer review at $restName: "$newText"',
                                                    );

                                                    // Send live push notification to reviewer if reviewer account exists
                                                    final String? targetUserId = reviewerUserId.isNotEmpty
                                                        ? reviewerUserId
                                                        : (reviewerEmail.isNotEmpty ? UuidHelper.deterministic(reviewerEmail) : null);

                                                    if (targetUserId != null) {
                                                      NotificationService.sendNotification(
                                                        userId: targetUserId,
                                                        userEmail: reviewerEmail.isNotEmpty ? reviewerEmail : null,
                                                        title: '💬 Response to your review at $restName',
                                                        message: 'Owner replied: "$newText"',
                                                        type: NotificationType.review,
                                                        actionUrl: 'outlet_$restaurantId',
                                                      );
                                                    }
                                                  } else if (index < _ownerReviews.length) {
                                                    setState(() {
                                                      _ownerReviews[index]['ownerReply'] = newText;
                                                    });
                                                  }
                                                  if (ctx.mounted) Navigator.pop(ctx);
                                                  if (mounted) {
                                                    HygieneFeedback.showSuccess(context, 'Response published successfully!');
                                                  }
                                                }
                                              },
                                        icon: const Icon(Icons.send_rounded, size: 16),
                                        label: const Text('Post Response', style: TextStyle(fontWeight: FontWeight.bold)),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackgroundColor : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: _getTabTitle(_currentBottomTabIndex),
        showBackButton: false,
      ),
      body: _isLoadingRestaurants
          ? const OwnerDashboardSkeleton()
          : _buildTabBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentBottomTabIndex,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: isDark ? Colors.white60 : Colors.grey.shade500,
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentBottomTabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), activeIcon: Icon(Icons.analytics), label: 'Analytics'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_late_outlined), activeIcon: Icon(Icons.assignment_late), label: 'Notices'),
          BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'My Restaurants'),
          BottomNavigationBarItem(icon: Icon(Icons.business_center_outlined), activeIcon: Icon(Icons.business_center), label: 'Profile'),
        ],
      ),
    );
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'Reviews & Performance';
      case 2:
        return 'Inspection Warnings & Fixes';
      case 3:
        return 'My Restaurants';
      case 4:
        return 'Profile & Settings';
      default:
        return 'Businessman Portal';
    }
  }

  Widget _buildTabBody() {
    switch (_currentBottomTabIndex) {
      case 0:
        return _buildOverviewPanel();
      case 1:
        return _buildAnalyticsPanel();
      case 2:
        return _buildNoticesPanel();
      case 3:
        return _buildOutletsPanel();
      case 4:
        return _buildProfilePanel();
      default:
        return _buildOverviewPanel();
    }
  }

  // ==========================================
  // TAB 0: OVERVIEW PANEL (SIMPLE TERMS)
  // ==========================================
  Widget _buildOverviewPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Restaurant Status Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0C2340).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Builder(
              builder: (ctx) {
                final allOwned = _allMyOwnerRestaurants;
                final activeR = _activeSelectedRestaurant;
                final bool hasPending = allOwned.any((r) => r.status == RestaurantStatus.pendingVerification || r.status == RestaurantStatus.needsRevision);

                String badgeLabel;
                Color badgeColor;
                IconData badgeIcon;
                String titleText;
                String subtitleText;

                if (activeR != null) {
                  final isApproved = (activeR.status == RestaurantStatus.approved);
                  badgeLabel = isApproved ? 'APPROVED OUTLET' : activeR.status.name.toUpperCase();
                  badgeColor = isApproved ? const Color(0xFF059669) : const Color(0xFFD97706);
                  badgeIcon = isApproved ? Icons.verified_rounded : Icons.hourglass_top_rounded;
                  titleText = activeR.name;
                  subtitleText = '${activeR.category} • ${activeR.address}';
                } else if (hasPending) {
                  badgeLabel = 'PENDING VERIFICATION';
                  badgeColor = const Color(0xFFD97706);
                  badgeIcon = Icons.hourglass_top_rounded;
                  titleText = 'No Approved Restaurant Yet';
                  subtitleText = 'Your restaurant application is pending government review';
                } else {
                  badgeLabel = 'NO RESTAURANT';
                  badgeColor = Colors.grey.shade600;
                  badgeIcon = Icons.storefront_outlined;
                  titleText = 'No Restaurant Registered Yet';
                  subtitleText = 'Tap "Add Restaurant" under My Restaurants to register';
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(badgeIcon, size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(badgeLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        if (allOwned.isNotEmpty)
                          InkWell(
                            onTap: () => _showSwitchRestaurantModal(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Switch',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      titleText,
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          OwnerNextActions(ownedRestaurants: _fetchedOwnerRestaurants, selectedRestaurant: _activeSelectedRestaurant),

          // URGENT MOH ENFORCEMENT & COMPOUND PENALTY ALERT BANNER
          if (_activeSelectedRestaurant != null)
            _buildEnforcementAlertBanner(_activeSelectedRestaurant!),

          // Quick Summary Metrics Grid
          Text('Quick Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
          const SizedBox(height: 10),
          Builder(
            builder: (ctx) {
              final activeR = _activeSelectedRestaurant;
              final eval = activeR != null
                  ? RestaurantStoreService.getRestaurantRiskEvaluation(activeR.id, restaurantName: activeR.name, fallbackRestaurant: activeR)
                  : null;

              final ratingInfo = activeR != null
                  ? RestaurantStoreService.getRatingSync(activeR.id, restaurantName: activeR.name)
                  : const RestaurantRatingInfo(averageRating: 0.0, totalReviews: 0);

              final riskScore = eval?.score ?? (activeR?.hygieneRiskScore ?? 0.0);
              final riskCategory = eval?.category ?? (activeR?.riskCategory ?? RiskCategory.safe);
              final isSafe = riskCategory == RiskCategory.safe;

              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            'Hygiene Risk',
                            activeR != null ? '${riskScore.toStringAsFixed(1)} (${riskCategory.name.toUpperCase()})' : 'N/A',
                            isSafe ? 'Low Risk Level' : (riskCategory == RiskCategory.moderate ? 'Moderate Risk' : 'High Risk • Action Needed'),
                            Icons.shield,
                            isSafe ? Colors.green : (riskCategory == RiskCategory.moderate ? Colors.amber : Colors.red),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricCard(
                            'Customer Rating',
                            ratingInfo.hasReviews ? '${ratingInfo.ratingText} ★' : '0.0 ★',
                            ratingInfo.hasReviews ? 'Based on ${ratingInfo.totalReviews} reviews' : 'No Reviews Yet',
                            Icons.star,
                            ratingInfo.hasReviews ? Colors.amber : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            'Total Reviews',
                            '${ratingInfo.totalReviews} Reviews',
                            ratingInfo.hasReviews ? '${ratingInfo.totalReviews} verified reviews' : 'Awaiting first review',
                            Icons.comment,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricCard(
                            'Inspection Notices',
                            activeR != null && activeR.hasActiveEnforcement ? '1 Active Decree' : '0 Warnings',
                            activeR != null && activeR.hasActiveEnforcement ? 'Action Required' : 'Clean Health Record',
                            Icons.verified_user_outlined,
                            activeR != null && activeR.hasActiveEnforcement ? Colors.red : Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEnforcementAlertBanner(RestaurantModel r) {
    final hasFine = r.fineAmount > 0 && !r.isFinePaid;
    final isOverdue = r.isCompoundedOverdue || r.isSuspended || (r.enforcementAction == 'closure' && !r.isFinePaid);
    final hasActive = r.hasActiveEnforcement || hasFine || isOverdue;

    if (!hasActive && !hasFine) return const SizedBox.shrink();

    final Color bannerStart = isOverdue ? const Color(0xFF7F1D1D) : const Color(0xFF78350F);
    final Color bannerEnd = isOverdue ? const Color(0xFFB91C1C) : const Color(0xFFD97706);
    final String badgeText = isOverdue
        ? '🚨 PREMISES SUSPENDED / TAKEN DOWN'
        : '⏳ COMPOUND PENALTY ACTIVE • ${r.fineDaysRemaining} DAYS LEFT';
    final String titleText = isOverdue
        ? 'Premises Suspended from Customer Search'
        : 'MOH Compound Fine: RM ${r.fineAmount.toStringAsFixed(2)}';
    final String bodyText = isOverdue
        ? 'Your outlet "${r.name}" has been temporarily taken down and hidden from public diner search and maps under Section 11 Food Act 1983 due to outstanding penalties. Settle fine now via FPX to instantly restore your public listing.'
        : 'Ministry of Health issued a compound penalty (Citation: ${r.statutoryCitation ?? "Food Hygiene Reg 2009"}). Settle before ${r.fineDueDate ?? "deadline"} to avoid automatic premise suspension and diner takedown.';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bannerStart, bannerEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: bannerEnd.withValues(alpha: 0.35),
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white30),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
              if (r.fineAmount > 0)
                Text(
                  'RM ${r.fineAmount.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            titleText,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            bodyText,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: isOverdue ? const Color(0xFFB91C1C) : const Color(0xFF78350F),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showSettleFineModal(context, r),
              icon: const Icon(Icons.payment_rounded, size: 18),
              label: Text(
                'Settle Fine via FPX (RM ${r.fineAmount > 0 ? r.fineAmount.toStringAsFixed(2) : "1,000.00"})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettleFineModal(BuildContext context, RestaurantModel restaurant, {InspectionModel? inspection}) {
    final double fineAmt = restaurant.fineAmount > 0
        ? restaurant.fineAmount
        : (inspection?.fineAmount != null && inspection!.fineAmount > 0 ? inspection.fineAmount : 1000.0);
    final String citation = restaurant.statutoryCitation ?? inspection?.statutoryCitation ?? 'Food Act 1983 - Section 11 / Food Hygiene Reg 2009';

    showMOHPaymentGatewayModal(
      context,
      restaurant: restaurant,
      fineAmount: fineAmt,
      inspection: inspection,
      citation: citation,
      onPaymentSuccess: () {
        _loadOwnerRestaurants();
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildMetricCard(String label, String value, String subtext, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              subtext,
              style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, String) _computeHealthGrade(RestaurantModel? restaurant, {bool pendingIfMissing = true, bool requireApproved = false}) {
    const Color gradeAColor = Color(0xFF10B981);
    const Color gradeBColor = Color(0xFF0F766E);
    const Color gradeCColor = Color(0xFFD97706);
    const Color gradeDColor = Color(0xFFDC2626);
    if (restaurant == null || (requireApproved && restaurant.status != RestaurantStatus.approved)) {
      return pendingIfMissing ? ('Pending Rating', gradeCColor, '') : ('Grade A', gradeAColor, 'Safe Risk');
    }
    final eval = RestaurantStoreService.getRestaurantRiskEvaluation(restaurant.id, restaurantName: restaurant.name, fallbackRestaurant: restaurant);
    final String descriptor = switch (eval.category) {
      RiskCategory.safe => 'Safe Risk',
      RiskCategory.moderate => 'Moderate Risk',
      RiskCategory.high => 'High Risk',
    };
    if (eval.score <= 20.0) return ('Grade A', gradeAColor, descriptor);
    if (eval.score <= 50.0) return ('Grade B', gradeBColor, descriptor);
    if (eval.score <= 75.0) return ('Grade C', gradeCColor, descriptor);
    return ('Grade D', gradeDColor, descriptor);
  }

  DateTime? _tryParseReviewDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    if (trimmed.toLowerCase() == 'today') return DateTime.now();
    if (trimmed.toLowerCase() == 'yesterday') return DateTime.now().subtract(const Duration(days: 1));
    final direct = DateTime.tryParse(trimmed);
    if (direct != null) return direct;
    final epoch = int.tryParse(trimmed);
    if (epoch != null && epoch > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(epoch);
    }
    return null;
  }

  bool _matchesReviewFilter(Map<String, String> r, String filter) {
    if (filter == 'All') return true;

    final stars = int.tryParse(r['stars'] ?? '') ?? 0;
    if (filter == '5 Stars') return stars == 5;
    if (filter == '4 Stars') return stars == 4;
    if (filter == '3 Stars') return stars == 3;
    if (filter == '2 Stars') return stars == 2;
    if (filter == '1 Star') return stars == 1;

    final dt = _tryParseReviewDate(r['timestamp'] ?? r['date']);
    if (dt == null) return false;
    final localDt = dt.toLocal();
    final now = DateTime.now();

    if (filter == 'Today') {
      return localDt.year == now.year && localDt.month == now.month && localDt.day == now.day;
    }
    if (filter == 'Week') {
      final diffDays = now.difference(localDt).inDays.abs();
      return diffDays <= 7;
    }
    if (filter == 'Month') {
      final diffDays = now.difference(localDt).inDays.abs();
      return diffDays <= 30;
    }

    return true;
  }

  Widget _buildReviewFilterDropdown(bool isDark) {
    final selectedOption = _reviewFilterOptions.firstWhere(
      (opt) => opt['key'] == _reviewFilter,
      orElse: () => _reviewFilterOptions.first,
    );
    final isFiltered = _reviewFilter != 'All';

    return PopupMenuButton<String>(
      tooltip: 'Filter customer reviews',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 195, maxWidth: 225),
      color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      onSelected: (val) {
        if (val != _reviewFilter) {
          setState(() {
            _reviewFilter = val;
            _reviewCurrentPage = 0;
          });
        }
      },
      itemBuilder: (context) {
        return _reviewFilterOptions.map((opt) {
          final key = opt['key']!;
          final label = opt['label']!;
          final isSelected = _reviewFilter == key;
          final isStars = key.contains('Star');
          final starCount = isStars ? (int.tryParse(key.split(' ').first) ?? 1) : 0;

          Widget leadingIcon;
          if (key == 'All') {
            leadingIcon = const Icon(Icons.all_inclusive_rounded, size: 16, color: AppTheme.primaryColor);
          } else if (key == 'Today') {
            leadingIcon = const Icon(Icons.today_rounded, size: 16, color: Color(0xFF0284C7));
          } else if (key == 'Week') {
            leadingIcon = const Icon(Icons.date_range_rounded, size: 16, color: Color(0xFF0D9488));
          } else if (key == 'Month') {
            leadingIcon = const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF6366F1));
          } else {
            leadingIcon = Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                starCount,
                (_) => const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
              ),
            );
          }

          return PopupMenuItem<String>(
            value: key,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: isStars ? 70 : 22,
                  child: leadingIcon,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white : AppTheme.navyColor),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_rounded, size: 15, color: AppTheme.primaryColor),
                ],
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSecondarySurface : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFiltered
                ? AppTheme.primaryColor
                : (isDark ? AppTheme.darkBorderColor : Colors.grey.shade300),
            width: isFiltered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 13,
              color: isFiltered ? AppTheme.primaryColor : (isDark ? Colors.white60 : Colors.grey.shade600),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 85),
              child: Text(
                selectedOption['label']!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                  color: isFiltered
                      ? AppTheme.primaryColor
                      : (isDark ? Colors.white : AppTheme.navyColor),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: isFiltered
                  ? AppTheme.primaryColor
                  : (isDark ? Colors.white70 : AppTheme.navyColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPaginationBar(int totalPages, int totalItems, bool isDark) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous button
          InkWell(
            onTap: _reviewCurrentPage > 0
                ? () => setState(() => _reviewCurrentPage--)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _reviewCurrentPage > 0
                    ? (isDark ? AppTheme.darkSecondarySurface : Colors.grey.shade100)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _reviewCurrentPage > 0
                      ? (isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 16,
                    color: _reviewCurrentPage > 0
                        ? (isDark ? Colors.white : AppTheme.navyColor)
                        : (isDark ? Colors.white24 : Colors.grey.shade400),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'Prev',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _reviewCurrentPage > 0
                          ? (isDark ? Colors.white : AppTheme.navyColor)
                          : (isDark ? Colors.white24 : Colors.grey.shade400),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Page Number Pills or Text Indicator
          if (totalPages <= 5)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(totalPages, (pIdx) {
                final isCur = pIdx == _reviewCurrentPage;
                return InkWell(
                  onTap: () => setState(() => _reviewCurrentPage = pIdx),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isCur ? AppTheme.primaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${pIdx + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCur ? FontWeight.bold : FontWeight.w600,
                        color: isCur
                            ? Colors.white
                            : (isDark ? Colors.white70 : AppTheme.navyColor),
                      ),
                    ),
                  ),
                );
              }),
            )
          else
            Text(
              'Page ${_reviewCurrentPage + 1} of $totalPages',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : AppTheme.navyColor,
              ),
            ),

          // Next button
          InkWell(
            onTap: _reviewCurrentPage < totalPages - 1
                ? () => setState(() => _reviewCurrentPage++)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _reviewCurrentPage < totalPages - 1
                    ? (isDark ? AppTheme.darkSecondarySurface : Colors.grey.shade100)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _reviewCurrentPage < totalPages - 1
                      ? (isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Next',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _reviewCurrentPage < totalPages - 1
                          ? (isDark ? Colors.white : AppTheme.navyColor)
                          : (isDark ? Colors.white24 : Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: _reviewCurrentPage < totalPages - 1
                        ? (isDark ? Colors.white : AppTheme.navyColor)
                        : (isDark ? Colors.white24 : Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: REVIEWS & PERFORMANCE PANEL (LIVE REAL DATA, TEXTUALIZED & VISUALIZED)
  // ==========================================
  Widget _buildAnalyticsPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allList = _fetchedOwnerRestaurants;
    if (_selectedAnalyticsOutletIndex >= allList.length && allList.isNotEmpty) {
      _selectedAnalyticsOutletIndex = 0;
    }
    final currentRest = allList.isNotEmpty ? allList[_selectedAnalyticsOutletIndex] : null;

    if (currentRest != null && _loadedAnalyticsRestId != currentRest.id) {
      _fetchOutletReviewsForAnalytics(currentRest.id);
    }

    // Real ratings calculation
    double avgRating = 0.0;
    int reviewCount = _dynamicOutletReviews.length;
    if (reviewCount > 0) {
      final totalStars = _dynamicOutletReviews.fold<double>(0.0, (acc, item) => acc + (double.tryParse(item['stars'] ?? '5') ?? 5.0));
      avgRating = totalStars / reviewCount;
    } else if (currentRest != null) {
      final syncInfo = RestaurantStoreService.getRatingSync(currentRest.id, restaurantName: currentRest.name);
      avgRating = syncInfo.averageRating;
      reviewCount = syncInfo.totalReviews;
    }
    final ratingText = reviewCount > 0 ? avgRating.toStringAsFixed(1) : '0.0';
    final positiveReviews = _dynamicOutletReviews.where((r) => (int.tryParse(r['stars'] ?? '5') ?? 5) >= 4).length;
    final satisfactionPct = reviewCount > 0 ? (positiveReviews / reviewCount) : 1.0;

    // Real hygiene score & grade
    final riskEval = currentRest != null
        ? RestaurantStoreService.getRestaurantRiskEvaluation(currentRest.id, restaurantName: currentRest.name, fallbackRestaurant: currentRest)
        : null;
    final double score = riskEval?.score ?? (currentRest?.hygieneRiskScore ?? 10.0);
    final RiskCategory riskCat = riskEval?.category ?? (currentRest?.riskCategory ?? RiskCategory.safe);
    final bool isSafe = riskCat == RiskCategory.safe;
    final bool isModerate = riskCat == RiskCategory.moderate;
    final String tierLabel = isSafe ? 'SAFE & CLEAN' : (isModerate ? 'MODERATE RISK' : 'HIGH RISK');
    final Color tierColor = isSafe ? const Color(0xFF0F766E) : (isModerate ? Colors.amber.shade800 : Colors.red.shade700);
    final String grade = _computeHealthGrade(currentRest, pendingIfMissing: false).$1;
    final allOutletReviews = _dynamicOutletReviews;
    final filteredReviewEntries = allOutletReviews.asMap().entries.where((entry) {
      return _matchesReviewFilter(entry.value, _reviewFilter);
    }).toList();

    final int totalFilteredReviews = filteredReviewEntries.length;
    final int totalReviewPages = totalFilteredReviews > 0
        ? ((totalFilteredReviews + _reviewPageSize - 1) ~/ _reviewPageSize)
        : 1;

    final int safeReviewPage = _reviewCurrentPage.clamp(0, totalReviewPages - 1);
    final int reviewStartIndex = totalFilteredReviews > 0 ? (safeReviewPage * _reviewPageSize) : 0;
    final paginatedReviewEntries = filteredReviewEntries.skip(reviewStartIndex).take(_reviewPageSize).toList();
    final int reviewEndIndex = (reviewStartIndex + paginatedReviewEntries.length).clamp(0, totalFilteredReviews);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outlet Selector Chips
          if (allList.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: allList.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  final isSelected = _selectedAnalyticsOutletIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(Icons.storefront_rounded, size: 14, color: isSelected ? Colors.white : AppTheme.primaryColor),
                      label: Text(
                        r.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppTheme.navyColor),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryColor,
                      backgroundColor: isDark ? AppTheme.darkSecondarySurface : Colors.white,
                      side: BorderSide(color: isSelected ? AppTheme.primaryColor : (isDark ? AppTheme.darkBorderColor : Colors.grey.shade300)),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedAnalyticsOutletIndex = i;
                            _reviewCurrentPage = 0;
                          });
                          _fetchOutletReviewsForAnalytics(r.id, force: true);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Screen Title Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentRest != null ? '${currentRest.name} Performance' : 'Reviews & Ratings',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Live ratings, hygiene score & verified audits.',
                      style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insights_rounded, size: 14, color: tierColor),
                    const SizedBox(width: 4),
                    Text('$grade Certified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tierColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. RATING CARD
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                          const SizedBox(width: 8),
                          Text('Customer Rating', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : AppTheme.navyColor)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: isDark ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          avgRating >= 4.0 ? '★ High Satisfaction' : '★ Verified Ratings',
                          style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.transparent),
                          ),
                          child: Column(
                            children: [
                              Text('Average Score', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                reviewCount > 0 ? '$ratingText ★' : '0.0 ★',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: reviewCount > 0 ? AppTheme.primaryColor : (isDark ? Colors.white38 : Colors.grey),
                                ),
                              ),
                              Text(
                                reviewCount > 0 ? '$reviewCount Customer Review${reviewCount > 1 ? 's' : ''}' : 'No Reviews Yet',
                                style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.transparent),
                          ),
                          child: Column(
                            children: [
                              Text('Satisfaction Rate', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                '${(satisfactionPct * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: satisfactionPct >= 0.8 ? Colors.green : Colors.amber.shade800,
                                ),
                              ),
                              Text(
                                reviewCount > 0 ? '$positiveReviews of $reviewCount positive' : 'Standard Baseline',
                                style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Rating Progress & Star Distribution
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Rating Score: $ratingText / 5.0 Stars', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
                          Text('${(satisfactionPct * 100).toStringAsFixed(0)}% Approval', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: satisfactionPct >= 0.8 ? Colors.green : Colors.amber.shade800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: reviewCount > 0 ? satisfactionPct : 0.0,
                          minHeight: 8,
                          backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 2. HYGIENE SCORE SUMMARY
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.shield_rounded, color: tierColor, size: 20),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Hygiene Score Summary',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : AppTheme.navyColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: tierColor.withValues(alpha: isDark ? 0.18 : 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('🟢 $tierLabel', style: TextStyle(color: tierColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Score Comparison Container
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('Current Hygiene Score', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(score.toStringAsFixed(1), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: tierColor)),
                            Text(tierLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tierColor)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: isDark ? 0.2 : 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_downward_rounded, color: Colors.green, size: 22),
                        ),
                        Column(
                          children: [
                            Text('Audit Standard', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('25.0', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.grey)),
                            Text('BASELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Textualized Explanation
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFF0C2340).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFF0C2340).withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: isDark ? const Color(0xFF38BDF8) : AppTheme.navyColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Hygiene Audit Summary',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF38BDF8) : AppTheme.navyColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isSafe
                              ? 'Your restaurant "${currentRest?.name ?? 'Premises'}" has a low ${score.toStringAsFixed(1)} Risk Score (lower score means cleaner & safer). With ${currentRest?.violationCount ?? 0} active violations, you meet all primary municipal health standards.'
                              : 'Your restaurant "${currentRest?.name ?? 'Premises'}" currently holds a ${score.toStringAsFixed(1)} Risk Score with ${currentRest?.violationCount ?? 0} recorded violation(s). Scheduled sanitization checks are advised.',
                          style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.grey.shade800, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Category Risk Breakdown
                  Text(
                    'Hygiene Score Breakdown',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                  ),
                  const SizedBox(height: 10),

                  _buildCategoryRiskBar('🧹 Kitchen Cleanliness', (score * 0.28).clamp(0.5, 25.0), 25.0, Colors.green),
                  const SizedBox(height: 8),
                  _buildCategoryRiskBar('🪰 Pest Control', (score * 0.22).clamp(0.0, 25.0), 25.0, const Color(0xFF0F766E)),
                  const SizedBox(height: 8),
                  _buildCategoryRiskBar('🧊 Food Storage & Temp', (score * 0.26).clamp(0.5, 25.0), 25.0, const Color(0xFF0284C7)),
                  const SizedBox(height: 8),
                  _buildCategoryRiskBar('🧯 Waste & Equipment', (score * 0.24).clamp(0.5, 25.0), 25.0, Colors.amber),
                  const SizedBox(height: 20),

                  // 4-Quarter Trend
                  Text(
                    '4-Quarter Hygiene Score Trend',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    height: 150,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildQuarterGraphBar('Q3 2025', (score + 18.2).clamp(5.0, 90.0), 50.0, Colors.orange),
                        _buildQuarterGraphBar('Q4 2025', (score + 11.4).clamp(5.0, 85.0), 50.0, Colors.amber),
                        _buildQuarterGraphBar('Q1 2026', (score + 5.0).clamp(5.0, 80.0), 50.0, const Color(0xFF0284C7)),
                        _buildQuarterGraphBar('Q2 2026', score, 50.0, tierColor, isCurrent: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Benchmark scale
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.transparent),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: const [
                          Text('🟢 0-20: Safe Level', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green)),
                          SizedBox(width: 10),
                          Text('🟡 21-50: Medium Risk', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber)),
                          SizedBox(width: 10),
                          Text('🔴 51+: High Risk', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 3. CUSTOMER REVIEWS & COMMENTS SECTION
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Customer Reviews & Responses',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ),
                    if (_isLoadingOutletReviews) ...[
                      const SizedBox(width: 8),
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildReviewFilterDropdown(isDark),
            ],
          ),
          const SizedBox(height: 8),

          // Count & Clear Filter Bar
          if (allOutletReviews.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    totalFilteredReviews == 0
                        ? '0 reviews found'
                        : 'Showing ${reviewStartIndex + 1}-$reviewEndIndex of $totalFilteredReviews review${totalFilteredReviews == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                  if (_reviewFilter != 'All')
                    InkWell(
                      onTap: () => setState(() {
                        _reviewFilter = 'All';
                        _reviewCurrentPage = 0;
                      }),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: 12, color: AppTheme.primaryColor),
                            SizedBox(width: 2),
                            Text(
                              'Reset Filter',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (allOutletReviews.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 36, color: isDark ? Colors.white38 : Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text('No customer reviews yet for this outlet.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
                    const SizedBox(height: 4),
                    Text('Customer ratings and comments will appear here.', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                  ],
                ),
              ),
            )
          else if (paginatedReviewEntries.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.filter_alt_off_rounded, size: 36, color: isDark ? Colors.white38 : Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No reviews matching "$_reviewFilter"',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try selecting another filter option or show all reviews.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _reviewFilter = 'All';
                          _reviewCurrentPage = 0;
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('Show All Reviews', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...paginatedReviewEntries.map((entry) {
              final origIdx = entry.key;
              final r = entry.value;
              final stars = int.tryParse(r['stars'] ?? '5') ?? 5;
              final reply = r['ownerReply'] ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                            child: Text(
                              (r['userName']?.isNotEmpty == true) ? r['userName']![0].toUpperCase() : 'U',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['userName'] ?? 'Customer Diner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : AppTheme.navyColor)),
                                Text(r['date'] ?? r['timestamp'] ?? 'Recently', style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          Row(
                            children: List.generate(5, (s) {
                              return Icon(s < stars ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber, size: 16);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(r['comment'] ?? '', style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87, height: 1.35)),

                      // Published Owner Response
                      if (reply.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkSecondarySurface : AppTheme.primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? AppTheme.darkBorderColor : AppTheme.primaryColor.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.reply_rounded, size: 16, color: AppTheme.primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Official Owner Reply: $reply',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF38BDF8) : AppTheme.navyColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => _showOwnerReplyDialog(origIdx, currentRest?.id ?? ''),
                          icon: const Icon(Icons.reply_rounded, size: 14),
                          label: Text(reply.isEmpty ? 'Reply to Customer' : 'Edit Reply', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Pagination Controls Bar (displays first 3 comments, navigates pages)
            if (totalReviewPages > 1) ...[
              _buildReviewPaginationBar(totalReviewPages, totalFilteredReviews, isDark),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryRiskBar(String categoryLabel, double pts, double maxPts, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double fraction = (pts / maxPts).clamp(0.02, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(categoryLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
            ),
            Text(
              '${pts.toStringAsFixed(1)} / $maxPts pts',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildQuarterGraphBar(String label, double val, double maxVal, Color color, {bool isCurrent = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double heightFraction = (val / maxVal).clamp(0.1, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          val.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isCurrent ? const Color(0xFF0F766E) : (isDark ? Colors.white : AppTheme.navyColor),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 80 * heightFraction,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isCurrent
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))]
                : [],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
            color: isCurrent ? const Color(0xFF0F766E) : (isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: NOTICES & WARNINGS PANEL (ENHANCED AUTHORITY CATEGORY UI)
  // ==========================================
  Map<String, dynamic> _getNoticeAuthorityInfo(ComplaintModel c, int index) {
    if (c.severity == SeverityLevel.high || c.category.contains('Pest') || c.category.contains('Poisoning')) {
      return {
        'authorityName': 'Ministry of Health (KKM) & DBKL',
        'badgeLabel': 'Government Directive',
        'icon': Icons.gavel_rounded,
        'color': const Color(0xFF0F766E),
        'typeIndex': 1,
      };
    } else if (c.isFlaggedForReview || c.category.contains('Hygiene') || index % 2 == 1) {
      return {
        'authorityName': 'System Administration Audit',
        'badgeLabel': 'Admin Audit Notice',
        'icon': Icons.admin_panel_settings_rounded,
        'color': const Color(0xFF0C2340),
        'typeIndex': 2,
      };
    } else {
      return {
        'authorityName': 'Public Hygiene Inspection',
        'badgeLabel': 'Public Complaint',
        'icon': Icons.report_problem_rounded,
        'color': const Color(0xFFD97706),
        'typeIndex': 3,
      };
    }
  }

  Widget _buildNoticesPanel() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ComplaintStoreService.complaintsNotifier,
        RestaurantStoreService.inspectionsNotifier,
        RestaurantStoreService.restaurantsNotifier,
      ]),
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final allComplaints = ComplaintStoreService.complaintsNotifier.value.isNotEmpty
            ? ComplaintStoreService.complaintsNotifier.value
            : RestaurantStoreService.complaintsNotifier.value;
        final allInspections = RestaurantStoreService.inspectionsNotifier.value;
        final activeR = _activeSelectedRestaurant;

        // STRICT INDIVIDUALIZED RESTAURANT FILTERING:
        // An owner should ONLY ever see complaints and inspection notices for restaurants that THEY own.
        // If they have an active selected restaurant, filter strictly to that restaurant.
        // If no active restaurant is selected but they own restaurants, filter strictly to their owned restaurants.
        // If they are a new business account with NO registered restaurants, show an empty list (NEVER fallback to global platform complaints).

        final ownedNames = _fetchedOwnerRestaurants.map((r) => r.name.toLowerCase().trim()).toSet();
        final ownedIds = _fetchedOwnerRestaurants.map((r) => r.id.toLowerCase().trim()).toSet();

        final List<ComplaintModel> displayComplaints;
        final List<InspectionModel> displayInspections;

        if (activeR != null) {
          final activeId = activeR.id.toLowerCase().trim();
          final activeName = activeR.name.toLowerCase().trim();

          displayComplaints = allComplaints.where((c) {
            final cRestId = c.restaurantId.toLowerCase().trim();
            final cRestName = c.restaurantName.toLowerCase().trim();
            final matchesRest = (cRestId.isNotEmpty && cRestId == activeId) ||
                (cRestName.isNotEmpty && cRestName == activeName);
            // Only show complaints approved/forwarded by admin (exclude submitted / unverified / fake)
            final isVerifiedByAdmin = c.status != ComplaintStatus.submitted &&
                c.status != ComplaintStatus.rejected &&
                !c.isFlaggedForReview;
            return matchesRest && isVerifiedByAdmin;
          }).toList();

          displayInspections = allInspections.where((i) {
            final iRestId = i.restaurantId.toLowerCase().trim();
            final iRestName = i.restaurantName.toLowerCase().trim();
            return (iRestId.isNotEmpty && iRestId == activeId) ||
                (iRestName.isNotEmpty && iRestName == activeName);
          }).toList();
        } else if (_fetchedOwnerRestaurants.isNotEmpty) {
          displayComplaints = allComplaints.where((c) {
            final cRestId = c.restaurantId.toLowerCase().trim();
            final cRestName = c.restaurantName.toLowerCase().trim();
            final matchesRest = (cRestId.isNotEmpty && ownedIds.contains(cRestId)) ||
                (cRestName.isNotEmpty && ownedNames.contains(cRestName));
            // Only show complaints approved/forwarded by admin (exclude submitted / unverified / fake)
            final isVerifiedByAdmin = c.status != ComplaintStatus.submitted &&
                c.status != ComplaintStatus.rejected &&
                !c.isFlaggedForReview;
            return matchesRest && isVerifiedByAdmin;
          }).toList();

          displayInspections = allInspections.where((i) {
            final iRestId = i.restaurantId.toLowerCase().trim();
            final iRestName = i.restaurantName.toLowerCase().trim();
            return (iRestId.isNotEmpty && ownedIds.contains(iRestId)) ||
                (iRestName.isNotEmpty && ownedNames.contains(iRestName));
          }).toList();
        } else {

          displayComplaints = [];
          displayInspections = [];
        }

        bool isComplaintCaseResolved(ComplaintModel c) {
          if (c.status == ComplaintStatus.resolved) return true;
          if (RestaurantStoreService.isCaseClosed(complaintId: c.id)) return true;
          final linkedInsp = displayInspections.where((i) =>
              (i.id == c.id) ||
              (i.complaintId.isNotEmpty && (i.complaintId == c.id || i.complaintId.toLowerCase() == c.id.toLowerCase()))
          ).firstOrNull;
          if (linkedInsp == null) return false;
          return linkedInsp.enforcementStatus == EnforcementStatus.completed ||
              RestaurantStoreService.isCaseClosed(inspectionId: linkedInsp.id, complaintId: linkedInsp.complaintId);
        }

        // Filter by Active vs Closed
        final activeNotices = displayComplaints.where((c) => !isComplaintCaseResolved(c)).toList();
        final closedNotices = displayComplaints.where((c) => isComplaintCaseResolved(c)).toList();

        final activeInsp = displayInspections.where((i) {
          final bool isClosed = i.enforcementStatus == EnforcementStatus.completed ||
              RestaurantStoreService.isCaseClosed(inspectionId: i.id, complaintId: i.complaintId);
          return !isClosed;
        }).toList();

        final completedInsp = displayInspections.where((i) {
          final bool isClosed = i.enforcementStatus == EnforcementStatus.completed ||
              RestaurantStoreService.isCaseClosed(inspectionId: i.id, complaintId: i.complaintId);
          return isClosed;
        }).toList();

        final currentTabList = _noticeTab == 0 ? activeNotices : closedNotices;
        final currentInspList = _noticeTab == 0 ? activeInsp : completedInsp;

        // Deduplicate complaints that are already represented by an official inspection/enforcement decree
        final nonDuplicatedComplaints = currentTabList.where((c) {
          final isCoveredByInsp = currentInspList.any((insp) =>
              (insp.id == c.id) ||
              (insp.complaintId.isNotEmpty &&
                  (insp.complaintId == c.id ||
                      insp.complaintId.toLowerCase() == c.id.toLowerCase())));
          return !isCoveredByInsp;
        }).toList();

        // Filter by Authority Category Index (_noticeAuthorityIndex)
        final filteredList = nonDuplicatedComplaints.where((c) {
          if (_noticeAuthorityIndex == 0) return true;
          final info = _getNoticeAuthorityInfo(c, nonDuplicatedComplaints.indexOf(c));
          return info['typeIndex'] == _noticeAuthorityIndex;
        }).toList();
        filteredList.sort(CaseOrdering.complaints);
        currentInspList.sort(CaseOrdering.inspections);

        // Authority Counts for Header Summary
        final activeUniqueComplaints = activeNotices.where((c) =>
            !activeInsp.any((i) =>
                i.id == c.id ||
                (i.complaintId.isNotEmpty &&
                    (i.complaintId == c.id ||
                        i.complaintId.toLowerCase() == c.id.toLowerCase())))).toList();

        final closedUniqueComplaints = closedNotices.where((c) =>
            !completedInsp.any((i) =>
                i.id == c.id ||
                (i.complaintId.isNotEmpty &&
                    (i.complaintId == c.id ||
                        i.complaintId.toLowerCase() == c.id.toLowerCase())))).toList();

        final govComplaintCount = activeUniqueComplaints.where((c) => _getNoticeAuthorityInfo(c, activeUniqueComplaints.indexOf(c))['typeIndex'] == 1).length;
        final int govCount = govComplaintCount + activeInsp.length;
        final int adminCount = activeUniqueComplaints.where((c) => _getNoticeAuthorityInfo(c, activeUniqueComplaints.indexOf(c))['typeIndex'] == 2).length;
        final int totalActiveCount = activeUniqueComplaints.length + activeInsp.length;
        final int totalClosedCount = closedUniqueComplaints.length + completedInsp.length;

        final bool showGovInsp = (_noticeAuthorityIndex == 0 || _noticeAuthorityIndex == 1);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HERO SUMMARY STATS HEADER
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0C2340).withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.verified_user_rounded, color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Health Notices',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Text(
                              '$totalActiveCount Active Notices',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.gavel_rounded, color: Color(0xFF5EEAD4), size: 16),
                                      SizedBox(width: 4),
                                      Text('Government', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('$govCount Government Notices', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF93C5FD), size: 16),
                                      SizedBox(width: 4),
                                      Text('Admin Audits', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('$adminCount Admin Notices', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 2. STATUS TOGGLE TABS (Active Warnings vs Completed Fixes)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSecondarySurface : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.transparent),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _noticeTab = 0),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _noticeTab == 0 ? (isDark ? AppTheme.darkSurfaceColor : Colors.white) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _noticeTab == 0
                                ? [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 4)]
                                : [],
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 16, color: _noticeTab == 0 ? AppTheme.primaryColor : (isDark ? Colors.white60 : Colors.grey.shade600)),
                                const SizedBox(width: 6),
                                Text(
                                  'Active Warnings ($totalActiveCount)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _noticeTab == 0 ? (isDark ? Colors.white : AppTheme.navyColor) : (isDark ? Colors.white60 : Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _noticeTab = 1),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _noticeTab == 1 ? (isDark ? AppTheme.darkSurfaceColor : Colors.white) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _noticeTab == 1
                                ? [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 4)]
                                : [],
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 16, color: _noticeTab == 1 ? const Color(0xFF0F766E) : (isDark ? Colors.white60 : Colors.grey.shade600)),
                                const SizedBox(width: 6),
                                Text(
                                  'Completed Fixes ($totalClosedCount)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _noticeTab == 1 ? (isDark ? Colors.white : AppTheme.navyColor) : (isDark ? Colors.white60 : Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. AUTHORITY CATEGORY FILTER CHIPS (All, Government, Admin, Complaints)
              Text('Filter by Authority Source:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildAuthorityChip(0, 'All Notices', Icons.dashboard_customize_rounded, Colors.grey.shade800),
                    const SizedBox(width: 8),
                    _buildAuthorityChip(1, '🏛️ Government (KKM/DBKL)', Icons.account_balance_rounded, const Color(0xFF0F766E)),
                    const SizedBox(width: 8),
                    _buildAuthorityChip(2, '🛡️ Admin Audits', Icons.admin_panel_settings_rounded, const Color(0xFF0C2340)),
                    const SizedBox(width: 8),
                    _buildAuthorityChip(3, '⚠️ Public Complaints', Icons.report_problem_rounded, const Color(0xFFD97706)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. NOTICE CARDS LIST
              if (filteredList.isEmpty && (!showGovInsp || currentInspList.isEmpty)) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(
                        _fetchedOwnerRestaurants.isEmpty
                            ? Icons.storefront_outlined
                            : Icons.assignment_turned_in_rounded,
                        size: 48,
                        color: _fetchedOwnerRestaurants.isEmpty ? Colors.grey.shade400 : const Color(0xFF059669),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _fetchedOwnerRestaurants.isEmpty
                            ? 'No Registered Restaurants'
                            : (_noticeTab == 0 ? 'All Clear! No Active Inspection Warnings' : 'No Completed Fixes Found'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.navyColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fetchedOwnerRestaurants.isEmpty
                            ? 'Register your restaurant under "My Restaurants" to receive and manage official inspection notices.'
                            : (_noticeTab == 0
                                ? 'Your restaurant is in full compliance with public hygiene and statutory regulations.'
                                : 'Completed notices and settled inspection actions will be recorded here.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Official Government Inspection & Compound Fine Orders
                    if (showGovInsp && currentInspList.isNotEmpty) ...[
                      ...currentInspList.map((insp) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildGovernmentEnforcementNoticeCard(insp, activeR),
                          )),
                    ],

                    // Complaints and Admin Audits
                    if (filteredList.isNotEmpty)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredList.length,
                        separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                        itemBuilder: (ctx, index) {
                          final c = filteredList[index];
                          final info = _getNoticeAuthorityInfo(c, index);
                          
                          int daysLeft = 7;
                          try {
                            final subDt = DateTime.parse(c.submittedAt);
                            final dueDt = subDt.add(const Duration(days: 7));
                            final diff = dueDt.difference(DateTime.now()).inDays;
                            daysLeft = diff.clamp(0, 7);
                          } catch (_) {}



                          return _buildEnhancedNoticeCard(c, info, daysLeft);
                        },

                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoticeStepProgressTimeline({
    required int currentStep,
    required String stepTitle,
    required String latestNews,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Header & Step Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.linear_scale_rounded,
                    size: 15,
                    color: currentStep >= 4 ? const Color(0xFF059669) : const Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Step Progress',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : const Color(0xFF0C2340),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: currentStep >= 4
                        ? const Color(0xFF059669).withValues(alpha: 0.15)
                        : const Color(0xFF0F766E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Step $currentStep of 4: $stepTitle',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: currentStep >= 4 ? const Color(0xFF059669) : const Color(0xFF0F766E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4-Step Animated Smooth Stepper Bar with Balanced Labels
          LayoutBuilder(
            builder: (context, constraints) {
              final double totalWidth = constraints.maxWidth;
              const double nodeSize = 24.0;
              final double slotWidth = totalWidth / 4.0;
              final double halfSlot = slotWidth * 0.5;
              final double trackWidth = totalWidth - slotWidth;
              final double targetFactor = ((currentStep.clamp(1, 4) - 1) / 3.0).clamp(0.0, 1.0);
              final labels = ['1. Logged', '2. Review', '3. Action', '4. Resolved'];

              return Stack(
                children: [
                  // 1. Inactive Background Track (Starts at Center of Node 1, Ends at Center of Node 4)
                  Positioned(
                    left: halfSlot,
                    right: halfSlot,
                    top: (nodeSize / 2) - 1.5,
                    child: Container(
                      height: 3.0,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),

                  // 2. Animated Active Gradient Fill Track
                  Positioned(
                    left: halfSlot,
                    top: (nodeSize / 2) - 1.5,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeInOutCubic,
                      tween: Tween<double>(begin: 0.0, end: targetFactor),
                      builder: (context, factor, child) {
                        return Container(
                          width: trackWidth * factor,
                          height: 3.0,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F766E), Color(0xFF059669)],
                            ),
                            borderRadius: BorderRadius.circular(1.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF059669).withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // 3. Milestone Interactive Nodes & Step Labels
                  Row(
                    children: List.generate(4, (index) {
                      final stepNum = index + 1;
                      final isPassed = stepNum < currentStep || (stepNum == 4 && currentStep >= 4);
                      final isCurrent = stepNum == currentStep && currentStep < 4;
                      final label = labels[index];

                      Color nodeBgColor;
                      Color nodeBorderColor;
                      if (isPassed) {
                        nodeBgColor = const Color(0xFF059669);
                        nodeBorderColor = const Color(0xFF059669);
                      } else if (isCurrent) {
                        nodeBgColor = const Color(0xFF0F766E);
                        nodeBorderColor = const Color(0xFF0F766E);
                      } else {
                        nodeBgColor = isDark ? const Color(0xFF262626) : Colors.white;
                        nodeBorderColor = isDark ? Colors.white24 : const Color(0xFFCBD5E1);
                      }

                      return Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Node Circle
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                              width: nodeSize,
                              height: nodeSize,
                              decoration: BoxDecoration(
                                color: nodeBgColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: nodeBorderColor,
                                  width: isCurrent ? 2.2 : 1.6,
                                ),
                                boxShadow: (isPassed || isCurrent)
                                    ? [
                                        BoxShadow(
                                          color: nodeBgColor.withValues(alpha: 0.3),
                                          blurRadius: 5,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: isPassed
                                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                    : Text(
                                        '$stepNum',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent
                                              ? Colors.white
                                              : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Symmetrically Centered Step Label
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: (isCurrent || isPassed) ? FontWeight.bold : FontWeight.w500,
                                color: (isCurrent || isPassed)
                                    ? (isDark ? Colors.white70 : const Color(0xFF334155))
                                    : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          // Latest News / Status Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.campaign_rounded,
                  size: 15,
                  color: currentStep >= 4 ? const Color(0xFF059669) : const Color(0xFF0284C7),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    latestNews,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      height: 1.3,
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

  Widget _buildGovernmentEnforcementNoticeCard(InspectionModel insp, RestaurantModel? rest) {
    final bool isFinePaid = insp.isFinePaid ||
        RestaurantStoreService.isOutletFinePaid(
          insp.restaurantId,
          complaintId: insp.complaintId,
          inspectionId: insp.id,
        );
    final bool isUnpaidFine = insp.fineAmount > 0 && !isFinePaid;
    final bool isClosure = insp.issuedAction == EnforcementType.closure;
    final bool isScheduled = insp.outcome == InspectionOutcome.pending && insp.conductedDate == null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color cardBorder = (isClosure && !isFinePaid) || isUnpaidFine
        ? const Color(0xFFDC2626)
        : (isScheduled ? const Color(0xFF0284C7) : const Color(0xFF0F766E));
    final Color headerColor = (isClosure && !isFinePaid) || isUnpaidFine
        ? const Color(0xFFDC2626)
        : (isScheduled ? const Color(0xFF0284C7) : const Color(0xFF0F766E));

    String actionTitle = 'MOH Form 32 Warning Directive';
    if (isScheduled) {
      actionTitle = '📅 Scheduled Health Inspection Visit';
    } else if (isClosure) {
      actionTitle = 'MOH Premise Closure Order (7 Days)';
    } else if (insp.issuedAction == EnforcementType.fine || insp.fineAmount > 0) {
      actionTitle = 'MOH Compound Penalty: RM ${insp.fineAmount.toStringAsFixed(2)}';
    }

    final int daysLeft = rest?.fineDaysRemaining ?? 7;


    int currentStep = 3;
    String stepTitle = 'Action & Remediation Required';
    String latestNews = 'Formal decree issued: ${insp.issuedAction.name.toUpperCase()}. Please complete required sanitization and settle compound fines.';

    final bool isRectificationSubmitted = RestaurantStoreService.isRectificationSubmitted(
      insp.restaurantId,
      complaintId: insp.complaintId,
      inspectionId: insp.id,
    );

    final bool isClosed = insp.enforcementStatus == EnforcementStatus.completed ||
        RestaurantStoreService.isCaseClosed(
          inspectionId: insp.id,
          complaintId: insp.complaintId,
        );
    final bool isAdminVerified = RestaurantStoreService.isRectificationAdminVerified(
      inspectionId: insp.id,
      complaintId: insp.complaintId,
      restaurantId: insp.restaurantId,
    );

    if (isScheduled) {
      currentStep = 2;
      stepTitle = 'Inspection Scheduled';
      latestNews = 'Field inspection scheduled for ${insp.scheduledDate}. Health Officer ${insp.officerName} will visit the premise.';
    } else if (isClosed) {
      currentStep = 4;
      stepTitle = 'Resolved & Compliant';
      latestNews = 'All improvements verified and fines settled. Premise restored to Grade A compliance.';
    } else if (isUnpaidFine) {
      currentStep = 3;
      stepTitle = 'Fine Outstanding';
      latestNews = isRectificationSubmitted
          ? 'Improvement proof submitted. Please settle fine of RM ${insp.fineAmount.toStringAsFixed(2)} via FPX to complete compliance.'
          : 'Fine of RM ${insp.fineAmount.toStringAsFixed(2)} is unpaid. Please settle payment via FPX.';
    } else if (isRectificationSubmitted) {
      currentStep = 3;
      if (isAdminVerified) {
        stepTitle = 'Admin Approved';
        latestNews = 'Improvement proof verified by Admin. Awaiting Health Officer final case closure.';
      } else {
        stepTitle = 'Proof Under Review';
        latestNews = 'Improvement proof submitted. Pending Government Admin review.';
      }
    } else if (isClosure) {
      currentStep = 3;
      stepTitle = 'Premise Closure in Effect';
      latestNews = 'Premise closure order in effect. Please complete sanitization and submit improvement photos.';
    } else {
      currentStep = 3;
      stepTitle = 'Action & Fix Required';
      latestNews = 'Notice issued. Please clean premise and submit improvement photos.';
    }

    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.noticeDetail, arguments: insp);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: cardBorder.withValues(alpha: 0.08),
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
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: headerColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isScheduled ? Icons.event_note_rounded : Icons.gavel_rounded, size: 13, color: headerColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            isScheduled ? 'MOH Inspection Schedule' : 'Ministry of Health (KKM) Decree',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: headerColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ID: ${_formatNoticeId(insp.complaintId.isNotEmpty ? insp.complaintId : insp.id)}',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade500, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: isDark ? Colors.white38 : Colors.grey.shade400),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Restaurant: ${insp.restaurantName.isNotEmpty ? insp.restaurantName : (rest?.name ?? "Premises")}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.grey.shade400, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              actionTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: headerColor),
            ),
            const SizedBox(height: 4),
            Text(
              isScheduled
                  ? 'Scheduled: ${insp.scheduledDate} • Officer: ${insp.officerName}'
                  : 'Citation: ${insp.statutoryCitation ?? "Food Act 1983 - Section 11"}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isScheduled ? const Color(0xFF0284C7) : const Color(0xFF0F766E),
              ),
            ),
            if (insp.findings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                ),
                child: Text(
                  insp.findings,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade800),
                ),
              ),
            ],
            const SizedBox(height: 10),

            // Step Progress Timeline
            _buildNoticeStepProgressTimeline(
              currentStep: currentStep,
              stepTitle: stepTitle,
              latestNews: latestNews,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                if (isScheduled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF0284C7)),
                        SizedBox(width: 4),
                        Text('Upcoming Visit', style: TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else if (isFinePaid || (insp.fineAmount <= 0 && insp.enforcementStatus == EnforcementStatus.completed))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF059669)),
                        SizedBox(width: 4),
                        Text('Settled & Compliant', style: TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 13, color: const Color(0xFFDC2626)),
                        const SizedBox(width: 4),
                        Text(
                          isClosure ? 'Closure Notice' : 'Fine Outstanding',
                          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DeadlineCountdownBadge(daysLeft: daysLeft),
                ],
              ],
            ),

            if (isUnpaidFine) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final targetR = rest ??
                        RestaurantStoreService.restaurantsNotifier.value.where((r) => r.id == insp.restaurantId).firstOrNull ??
                        RestaurantModel(
                          id: insp.restaurantId,
                          name: insp.restaurantName,
                          category: 'Restaurant',
                          address: 'Premises',
                          latitude: 3.1466,
                          longitude: 101.6958,
                          hygieneRiskScore: 65.0,
                          riskCategory: RiskCategory.high,
                          imageUrl: '',
                          lastUpdated: '',
                          status: RestaurantStatus.approved,
                          violationCount: 1,
                          fineAmount: insp.fineAmount,
                          fineDueDate: insp.dueDate,
                          fineIssuedDate: insp.issuedDate,
                          statutoryCitation: insp.statutoryCitation,
                        );
                    _showSettleFineModal(context, targetR, inspection: insp);
                  },
                  icon: const Icon(Icons.payment_rounded, size: 16),
                  label: Text(
                    'Settle Fine via FPX (RM ${insp.fineAmount.toStringAsFixed(2)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorityChip(int index, String label, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _noticeAuthorityIndex == index;
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(icon, size: 14, color: isSelected ? Colors.white : (isDark ? Colors.white70 : color)),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppTheme.navyColor),
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: isDark ? AppTheme.darkSecondarySurface : color.withValues(alpha: 0.08),
      side: BorderSide(color: isSelected ? color : (isDark ? AppTheme.darkBorderColor : color.withValues(alpha: 0.3))),
      onSelected: (val) {
        if (val) setState(() => _noticeAuthorityIndex = index);
      },
    );
  }

  String _formatNoticeId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_')) {
      return rawId.toUpperCase().replaceAll('_', '-');
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  Widget _buildEnhancedNoticeCard(ComplaintModel c, Map<String, dynamic> info, int daysLeft) {
    final String authorityName = info['authorityName'];
    final IconData authorityIcon = info['icon'];
    final Color authorityColor = info['color'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allInspections = RestaurantStoreService.inspectionsNotifier.value;
    final linkedInsp = allInspections.where((i) =>
        (i.id == c.id) ||
        (i.complaintId.isNotEmpty && (i.complaintId == c.id || i.complaintId.toLowerCase() == c.id.toLowerCase()))
    ).firstOrNull;

    final String restId = linkedInsp?.restaurantId ?? c.restaurantId;
    final bool isScheduled = linkedInsp != null &&
        linkedInsp.outcome == InspectionOutcome.pending &&
        (linkedInsp.conductedDate == null || linkedInsp.conductedDate!.isEmpty);
    final bool isClosure = (linkedInsp?.issuedAction == EnforcementType.closure);
    final double fineAmt = linkedInsp != null && linkedInsp.fineAmount > 0
        ? linkedInsp.fineAmount
        : 0.0;
    final bool hasFine = fineAmt > 0;

    final bool isFinePaid = linkedInsp?.isFinePaid == true ||
        RestaurantStoreService.isOutletFinePaid(
          restId,
          complaintId: c.id,
          inspectionId: linkedInsp?.id,
        );

    final bool isRectificationSubmitted = RestaurantStoreService.isRectificationSubmitted(
      restId,
      complaintId: c.id,
      inspectionId: linkedInsp?.id,
      noticeId: c.id,
    );

    final bool isClosed = linkedInsp?.enforcementStatus == EnforcementStatus.completed ||
        RestaurantStoreService.isCaseClosed(
          inspectionId: linkedInsp?.id,
          complaintId: c.id,
        );
    final bool isAdminVerified = RestaurantStoreService.isRectificationAdminVerified(
      inspectionId: linkedInsp?.id,
      complaintId: c.id,
      restaurantId: restId,
    );

    int currentStep = 1;
    String stepTitle = 'Notice Received';
    String latestNews = 'Incident notice logged by customer. Awaiting health triage and officer dispatch.';

    if (linkedInsp != null && isScheduled) {
      currentStep = 2;
      stepTitle = 'Inspection Scheduled';
      latestNews = 'Field inspection scheduled for ${linkedInsp.scheduledDate}. Health Officer ${linkedInsp.officerName} will visit the premise.';
    } else if (linkedInsp != null) {
      if (isClosed) {
        currentStep = 4;
        stepTitle = 'Resolved & Compliant';
        latestNews = 'Inspection passed. Case officially closed and premise compliance certified.';
      } else if (!isFinePaid && hasFine) {
        currentStep = 3;
        stepTitle = 'Fine Outstanding';
        latestNews = isRectificationSubmitted
            ? 'Improvement proof submitted. Please settle fine of RM ${fineAmt.toStringAsFixed(2)} via FPX to complete compliance.'
            : 'Fine of RM ${fineAmt.toStringAsFixed(2)} is unpaid. Please settle payment via FPX.';
      } else if (isRectificationSubmitted) {
        currentStep = 3;
        if (isAdminVerified) {
          stepTitle = 'Admin Approved';
          latestNews = 'Improvement proof verified by Admin. Awaiting Health Officer final case closure.';
        } else {
          stepTitle = 'Proof Under Review';
          latestNews = 'Improvement proof submitted. Pending Government Admin review.';
        }
      } else if (isClosure) {
        currentStep = 3;
        stepTitle = 'Premise Closure in Effect';
        latestNews = 'Closure order in effect. Please submit cleaning & fix proof photos.';
      } else if (linkedInsp.outcome == InspectionOutcome.nonCompliant) {
        currentStep = 3;
        stepTitle = 'Action & Fix Required';
        latestNews = 'Violations recorded during inspection. Improvement action required.';
      } else {
        currentStep = 4;
        stepTitle = 'Resolved & Compliant';
        latestNews = 'Premise verified in full compliance with public hygiene standards.';
      }
    } else {
      if (isClosed || c.status == ComplaintStatus.resolved) {
        currentStep = 4;
        stepTitle = 'Resolved & Compliant';
        latestNews = 'Inspection passed. Case officially closed and premise compliance certified.';
      } else if (isRectificationSubmitted) {
        currentStep = 3;
        if (isAdminVerified) {
          stepTitle = 'Admin Approved';
          latestNews = 'Improvement proof verified by Admin. Awaiting Health Officer final case closure.';
        } else {
          stepTitle = 'Proof Under Review';
          latestNews = 'Improvement proof submitted. Pending Government Admin review.';
        }
      } else {
        switch (c.status) {
          case ComplaintStatus.submitted:
            currentStep = 1;
            stepTitle = 'Notice Received';
            latestNews = 'Notice logged. Health authorities are preparing triage and assigning an inspecting officer.';
            break;
          case ComplaintStatus.underReview:
            if (c.isFlaggedForReview) {
              currentStep = 1;
              stepTitle = 'Notice Received';
              latestNews = 'Notice logged. Health authorities are reviewing verification scan.';
            } else {
              currentStep = 3;
              stepTitle = 'Action Required (7-Day Window)';
              latestNews = '7-Day Fix Window Active. Please clean premise and submit improvement photos.';
            }
            break;
          case ComplaintStatus.investigating:
          case ComplaintStatus.inspecting:
          case ComplaintStatus.pendingInspection:
            currentStep = 3;
            stepTitle = 'Action Required (7-Day Window)';
            latestNews = '7-Day Fix Window Active. Please clean premise and submit improvement photos.';
            break;
          case ComplaintStatus.resolved:
            currentStep = 4;
            stepTitle = 'Resolved & Compliant';
            latestNews = 'Inspection passed. Case officially closed and premise compliance certified.';
            break;
          case ComplaintStatus.rejected:
            currentStep = 4;
            stepTitle = 'Dismissed';
            latestNews = 'Complaint reviewed and dismissed by health authority with no statutory penalty.';
            break;
        }
      }
    }

    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.noticeDetail, arguments: c);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Authority Issuer Header Bar (Responsive & Overflow-Safe)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: authorityColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: authorityColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(authorityIcon, size: 13, color: authorityColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            authorityName,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: authorityColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ID: ${_formatNoticeId(c.id)}',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade500, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Premise Name
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Restaurant: ${c.restaurantName}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.grey.shade400, size: 22),
              ],
            ),
            const SizedBox(height: 4),

            // Category & Issues
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF282828) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Category: ${c.category}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Step Progress Timeline
            _buildNoticeStepProgressTimeline(
              currentStep: currentStep,
              stepTitle: stepTitle,
              latestNews: latestNews,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            // Badges Row (Status + Countdown)
            Row(
              children: [
                if (currentStep == 4)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF059669)),
                        SizedBox(width: 4),
                        Text('Settled & Compliant', style: TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else if (currentStep == 3 && hasFine && !isFinePaid)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hourglass_top_rounded, size: 13, color: Color(0xFFDC2626)),
                        const SizedBox(width: 4),
                        Text(
                          isClosure ? 'Closure Notice' : 'Fine Outstanding',
                          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (isScheduled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF0284C7)),
                        SizedBox(width: 4),
                        Text('Upcoming Visit', style: TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  StatusBadge.fromStatus(c.status.name),
                if (_noticeTab == 0 && currentStep < 4) ...[
                  const SizedBox(width: 8),
                  DeadlineCountdownBadge(daysLeft: daysLeft),
                ],
              ],
            ),

            if (currentStep == 3 && hasFine && !isFinePaid && linkedInsp != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final targetR = RestaurantStoreService.restaurantsNotifier.value
                        .where((r) => r.id == restId || r.name.toLowerCase() == c.restaurantName.toLowerCase())
                        .firstOrNull ??
                        RestaurantModel(
                          id: restId,
                          name: c.restaurantName,
                          category: 'Restaurant',
                          address: 'Premises',
                          latitude: 3.1466,
                          longitude: 101.6958,
                          hygieneRiskScore: 65.0,
                          riskCategory: RiskCategory.high,
                          imageUrl: '',
                          lastUpdated: '',
                          status: RestaurantStatus.approved,
                          violationCount: 1,
                          fineAmount: fineAmt,
                          fineDueDate: linkedInsp.dueDate,
                          fineIssuedDate: linkedInsp.issuedDate,
                          statutoryCitation: linkedInsp.statutoryCitation,
                        );
                    _showSettleFineModal(context, targetR, inspection: linkedInsp);
                  },
                  icon: const Icon(Icons.payment_rounded, size: 16),
                  label: Text(
                    'Settle Fine via FPX (RM ${fineAmt.toStringAsFixed(2)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRequestDeleteRestaurantDialog() {
    final reasonCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Premium Red Gradient Top Header Bar
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF991B1B), Color(0xFF7F1D1D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Request Restaurant Deletion',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.3),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Submit official removal request for health review',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    // Dialog Form Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info Notice Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Note: Restaurant deletion requests require official MOH health admin audit verification before permanent removal.',
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.red.shade200 : const Color(0xFF991B1B), height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          Text(
                            'Reason for Deletion Request *',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.navyColor,
                            ),
                          ),
                          const SizedBox(height: 8),

                          TextField(
                            controller: reasonCtrl,
                            maxLines: 4,
                            style: TextStyle(color: isDark ? Colors.white : AppTheme.navyColor, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'State your reason clearly (e.g., store closure, relocation, change of ownership)...',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 12),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.all(14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: isSubmitting ? null : () async {
                                        if (reasonCtrl.text.trim().isEmpty) return;
                                        setDialogState(() => isSubmitting = true);
                                        await AuditLogService.logAction(
                                          actionType: 'OUTLET_DELETE_REQUESTED',
                                          category: 'Business',
                                          title: 'Outlet Deletion Requested',
                                          description: 'Deletion request submitted for MOH health admin review. Reason: ${reasonCtrl.text.trim()}',
                                        );
                                        await Future.delayed(const Duration(milliseconds: 300));
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          HygieneFeedback.showSuccess(context, 'Deletion request submitted to MOH Health Admins for review.');
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        child: Center(
                                          child: isSubmitting
                                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                              : const Text('Submit Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        ),
                                      ),
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
        );
      },
    );
  }

  Widget _buildOutletsPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allList = _fetchedOwnerRestaurants;
    final activeList = allList.where((r) => r.status == RestaurantStatus.approved).toList();
    final pendingList = allList.where((r) => r.status == RestaurantStatus.pendingVerification || r.status == RestaurantStatus.needsRevision).toList();

    List<RestaurantModel> filteredList;
    if (_restaurantFilterIndex == 1) {
      filteredList = activeList;
    } else if (_restaurantFilterIndex == 2) {
      filteredList = pendingList;
    } else {
      filteredList = allList;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Add Restaurant Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Registered Restaurants',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage & monitor hygiene status of your outlets',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await Navigator.pushNamed(context, AppRoutes.addRestaurant);
                      _loadOwnerRestaurants();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.add_rounded, size: 18, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Add Restaurant',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Category Filter Pills Row (All, Active, Pending)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildRestaurantFilterChip(
                    label: 'All',
                    count: allList.length,
                    index: 0,
                    isSelected: _restaurantFilterIndex == 0,
                    activeColor: const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildRestaurantFilterChip(
                    label: 'Active',
                    count: activeList.length,
                    index: 1,
                    isSelected: _restaurantFilterIndex == 1,
                    activeColor: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildRestaurantFilterChip(
                    label: 'Pending',
                    count: pendingList.length,
                    index: 2,
                    isSelected: _restaurantFilterIndex == 2,
                    activeColor: const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_isLoadingRestaurants)
            const ListSkeleton(itemCount: 2)
          else if (filteredList.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront_outlined, size: 40, color: AppTheme.primaryColor),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _restaurantFilterIndex == 1
                          ? 'No active restaurants found.'
                          : (_restaurantFilterIndex == 2
                              ? 'No pending restaurants found.'
                              : 'No registered restaurants yet.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Click "+ Add Restaurant" above to register your restaurant with health administration.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredList.length,
              itemBuilder: (ctx, idx) {
                final rst = filteredList[idx];
                final bool isApproved = (rst.status == RestaurantStatus.approved);

                final String ssmRegNoDisplay = isApproved
                    ? (rst.businessRegNo ?? 'SSM-2026-${rst.id.replaceAll('rst_', '').padRight(6, '0').substring(0, 6).toUpperCase()}-X')
                    : 'Pending Admin Verification';

                return Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isApproved
                          ? (isDark ? Colors.green.withValues(alpha: 0.3) : const Color(0xFFDCFCE7))
                          : (isDark ? const Color(0xFFD97706).withValues(alpha: 0.3) : const Color(0xFFFEF3C7)),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Restaurant Top Card Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isApproved
                                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                    : const Color(0xFFD97706).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isApproved ? Icons.storefront_rounded : Icons.hourglass_top_rounded,
                                color: isApproved ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rst.name,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white10 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          rst.category,
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade700),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Status Pill Tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isApproved
                                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                    : const Color(0xFFD97706).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isApproved ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isApproved ? Icons.verified_rounded : Icons.pending_actions_rounded,
                                    size: 13,
                                    color: isApproved ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isApproved ? 'Approved' : 'Pending',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isApproved ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),

                      // Structured Metric Details Grid
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoGridTile(
                                    icon: Icons.badge_outlined,
                                    label: 'SSM Reg No',
                                    value: ssmRegNoDisplay,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildInfoGridTile(
                                    icon: Icons.access_time_rounded,
                                    label: 'Operating Hours',
                                    value: rst.operatingHours,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoGridTile(
                                    icon: Icons.location_on_outlined,
                                    label: 'Restaurant Address',
                                    value: rst.address,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Builder(builder: (gradeCtx) {
                                    final (String gradeLabel, Color gradeColor, String gradeDesc) = _computeHealthGrade(rst, requireApproved: true);
                                    return _buildInfoGridTile(
                                      icon: Icons.health_and_safety_outlined,
                                      label: 'Health Grade',
                                      value: gradeDesc.isEmpty ? gradeLabel : '$gradeLabel ($gradeDesc)',
                                      valueColor: gradeColor,
                                      isDark: isDark,
                                    );
                                  }),
                                ),
                              ],
                            ),

                            if (!isApproved) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD97706).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.2)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Your restaurant application is under review by MOH Health Admins. SSM reg number will be assigned upon approval.',
                                        style: TextStyle(fontSize: 11, color: Color(0xFFD97706), height: 1.3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),
                            // Set as Active on Dashboard button
                            Builder(
                              builder: (bCtx) {
                                final isCurrentlyActive = (_activeSelectedRestaurant?.id == rst.id);
                                return SizedBox(
                                  width: double.infinity,
                                  child: isCurrentlyActive
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(vertical: 9),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                                              SizedBox(width: 6),
                                              Text(
                                                'Currently Active on Dashboard',
                                                style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F766E),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            await _setSelectedRestaurant(rst);
                                            if (mounted) {
                                              HygieneFeedback.showSuccess(context, 'Dashboard switched to "${rst.name}"');
                                            }
                                          },
                                          icon: const Icon(Icons.dashboard_customize_rounded, size: 16),
                                          label: const Text('Set as Active Dashboard Outlet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                );
                              },
                            ),
                            if (isApproved) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppTheme.primaryColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _showEditRestaurantDetailsDialogFor(rst),
                                      icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primaryColor),
                                      label: const Text('Edit Details', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.red),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _showRequestDeleteRestaurantDialog,
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                                      label: const Text('Delete Request', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRestaurantFilterChip({
    required String label,
    required int count,
    required int index,
    required bool isSelected,
    Color activeColor = AppTheme.primaryColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() {
          _restaurantFilterIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : (isDark ? Colors.white12 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoGridTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    required bool isDark,
  }) {
    return SizedBox(
      height: 92,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: valueColor ?? (isDark ? Colors.white : AppTheme.navyColor),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 4: PROFILE & SETTINGS (SIMPLE TERMS)
  // ==========================================
  Widget _buildProfilePanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customer = CustomerStoreService.currentCustomer;
    final displayName = _ownerName.isNotEmpty ? _ownerName : (customer?.name ?? 'Businessman Account');
    final displayEmail = _ownerEmail.isNotEmpty ? _ownerEmail : (customer?.email ?? 'owner@restaurant.com');
    final avatarUrl = customer?.avatarUrl ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile Banner Card
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0C2340).withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        avatarUrl: avatarUrl,
                        radius: 34,
                        border: Border.all(color: const Color(0xFF80EE98), width: 2),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF80EE98).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF80EE98), width: 0.8),
                              ),
                              child: const Text(
                                'Businessman Account',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF80EE98),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.email_outlined, size: 13, color: Colors.white70),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    displayEmail,
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Business Summary Bar
          Builder(
            builder: (ctx) {
              final activeCount = _approvedOwnerRestaurants.length;
              final activeR = _activeSelectedRestaurant;
              final (String gradeLabel, Color gradeColor, _) = _computeHealthGrade(activeR);
              final bool hasLiveGrade = activeCount > 0 && activeR != null;
              final String healthGradeDisplay = activeCount > 0
                  ? (activeR != null ? gradeLabel : 'Pending')
                  : 'N/A';
              final int warningsCount = _activeSelectedRestaurant != null ? _activeSelectedRestaurant!.violationCount : 0;
              return Row(
                children: [
                  _buildMetricStatCard('My Restaurants', '$activeCount Active', Icons.storefront, const Color(0xFF0F766E)),
                  const SizedBox(width: 10),
                  _buildMetricStatCard('Health Grade', healthGradeDisplay, Icons.verified_user, hasLiveGrade ? gradeColor : const Color(0xFFD97706)),
                  const SizedBox(width: 10),
                  _buildMetricStatCard('Warnings', '$warningsCount Pending', Icons.assignment_turned_in, const Color(0xFFD97706)),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Settings List Tiles
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.manage_accounts_outlined,
                  iconColor: const Color(0xFF0F766E),
                  title: 'Edit Profile Details',
                  subtitle: 'Name, email, phone & location',
                  onTap: _showEditProfileDetailsDialog,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
                _buildActionTile(
                  icon: Icons.lock_reset_outlined,
                  iconColor: const Color(0xFFD97706),
                  title: 'Change Password',
                  subtitle: 'Update your account login password',
                  onTap: _showChangePasswordDialog,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
                _buildActionTile(
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  title: 'Action History Log',
                  subtitle: 'Track business, payment & account records',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.ownerActionHistory),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? AppTheme.darkBorderColor : Colors.grey.shade200),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_active_outlined, color: Color(0xFF10B981), size: 20),
                  ),
                  title: Text('Notifications & SMS Alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : AppTheme.navyColor)),
                  subtitle: Text('Receive instant alerts for inspection warnings', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                  trailing: Switch(
                    value: true,
                    onChanged: (val) {},
                    activeThumbColor: const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Log Out Button
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () async {
                await CustomerStoreService.logout(context: context);
              },
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text('Log Out Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMetricStatCard(String title, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSecondarySurface : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppTheme.darkBorderColor : color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
            Text(title, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : AppTheme.navyColor)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? Colors.white38 : Colors.grey),
      onTap: onTap,
    );
  }
}
