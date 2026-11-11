import '../../core/widgets/customer_refresh_indicator.dart';
import '../../core/models/user_model.dart';
import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/audit_log_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';

class UserSettingsHistoryScreen extends StatefulWidget {
  const UserSettingsHistoryScreen({super.key});

  @override
  State<UserSettingsHistoryScreen> createState() => _UserSettingsHistoryScreenState();
}

class _UserSettingsHistoryScreenState extends State<UserSettingsHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = 'All';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<AuditLogModel> _allLogs = [];
  int _displayedCount = 6;
  final int _pageSize = 6;
  String _searchQuery = '';

  final List<String> _categories = [
    'All',
    'Security',
    'Profile',
    'Preferences',
    'Notifications',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserLogs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150 &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMoreLogs();
    }
  }

  Future<void> _loadUserLogs({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final user = CustomerStoreService.currentCustomer;
    final userId = user?.id;

    final fetched = await AuditLogService.fetchUserLogs(userId: userId);

    if (mounted) {
      setState(() {
        _allLogs = fetched;
        _displayedCount = _pageSize;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreLogs() async {
    final filtered = _getFilteredLogs();
    if (_displayedCount >= filtered.length) return;

    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() {
        _displayedCount = (_displayedCount + _pageSize).clamp(0, filtered.length);
        _isLoadingMore = false;
      });
    }
  }

  List<AuditLogModel> _getFilteredLogs() {
    return _allLogs.where((log) {
      final style = _getCategoryStyle(log.category, log.actionType);
      final tag = style['tag'] as String;

      if (_selectedCategory != 'All') {
        if (tag.toLowerCase() != _selectedCategory.toLowerCase() &&
            !log.category.toLowerCase().contains(_selectedCategory.toLowerCase())) {
          return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchTitle = log.title.toLowerCase().contains(query);
        final matchDesc = log.description.toLowerCase().contains(query);
        final matchCat = log.category.toLowerCase().contains(query);
        return matchTitle || matchDesc || matchCat;
      }

      return true;
    }).toList();
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');

    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return 'Today, $hour:$min';
    } else if (now.year == dt.year && now.month == dt.month && now.day - dt.day == 1) {
      return 'Yesterday, $hour:$min';
    }
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$min';
  }

  Map<String, dynamic> _getCategoryStyle(String category, String actionType) {
    final lowCat = category.toLowerCase();
    final lowAct = actionType.toLowerCase();

    if (lowAct.contains('pass') || lowCat.contains('secu')) {
      return {
        'icon': Icons.lock_reset_rounded,
        'color': const Color(0xFFD97706),
        'tag': 'Security',
      };
    } else if (lowAct.contains('theme') || lowAct.contains('lang') || lowCat.contains('pref')) {
      return {
        'icon': Icons.palette_outlined,
        'color': const Color(0xFF7C3AED),
        'tag': 'Preferences',
      };
    } else if (lowAct.contains('notif') || lowCat.contains('notif')) {
      return {
        'icon': Icons.notifications_active_outlined,
        'color': const Color(0xFF0284C7),
        'tag': 'Notifications',
      };
    } else if (lowAct.contains('login') || lowAct.contains('session')) {
      return {
        'icon': Icons.verified_user_rounded,
        'color': const Color(0xFF059669),
        'tag': 'Security',
      };
    } else {
      return {
        'icon': Icons.person_pin_rounded,
        'color': const Color(0xFF0F766E),
        'tag': 'Profile',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = CustomerStoreService.currentCustomer;
    final filteredLogs = _getFilteredLogs();
    final paginatedLogs = filteredLogs.take(_displayedCount).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackgroundColor : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Settings & Security Log',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Logs',
            onPressed: _loadUserLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const SettingsHistorySkeleton()
          : SafeArea(
              top: false,
              bottom: true,
              child: CustomerRefreshIndicator(enabled: CustomerStoreService.currentCustomer?.role == UserRole.user,
                onRefresh: () => _loadUserLogs(showLoading: !(CustomerStoreService.currentCustomer?.role == UserRole.user)),
                color: AppTheme.primaryColor,
                child: Column(
                children: [
                  // 1. TOP SUMMARY CARD
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                            : [const Color(0xFF0C2340), const Color(0xFF0F766E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.history_edu_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? 'User Account',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? 'Audit & Security Record History',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield_rounded, color: Color(0xFF34D399), size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Account Protected & Audited',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
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
                  ),

                  // 2. SEARCH BAR
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: AppSearchField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim();
                          _displayedCount = _pageSize;
                        });
                      },
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search settings, password, theme changes...',
                        hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ),

                  // 3. CATEGORY CHIPS ROW
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat),
                              selected: isSelected,
                              selectedColor: const Color(0xFF0F766E),
                              backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedCategory = val ? cat : 'All';
                                  _displayedCount = _pageSize;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 4. LOGS TIMELINE LIST WITH INFINITE SCROLL
                  Expanded(
                    child: filteredLogs.isEmpty
                        ? CustomerStoreService.currentCustomer?.role == UserRole.user
                          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [_buildEmptyState(isDark)])
                          : _buildEmptyState(isDark)
                        : ListView.builder(
                            controller: _scrollController,
                            physics: CustomerStoreService.currentCustomer?.role == UserRole.user ? const AlwaysScrollableScrollPhysics() : null,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: paginatedLogs.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == paginatedLogs.length) {
                                return _buildLoadingMoreIndicator(isDark);
                              }

                              final log = paginatedLogs[index];
                              final style = _getCategoryStyle(log.category, log.actionType);
                              final IconData icon = style['icon'] as IconData;
                              final Color iconColor = style['color'] as Color;
                              final String tag = style['tag'] as String;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: iconColor.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(icon, color: iconColor, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  log.title,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: isDark ? Colors.white : AppTheme.navyColor,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: iconColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  tag,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: iconColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            log.description,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.access_time_rounded,
                                                size: 12,
                                                color: isDark ? Colors.white38 : Colors.grey.shade400,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatTimestamp(log.timestamp),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
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
      ),
    );
  }

  Widget _buildLoadingMoreIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DualArcLoader(
            size: 20,
            strokeWidth: 2.2,
            color: isDark ? Colors.tealAccent : const Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading more logs...',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 40,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No Settings Logs Found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Any account changes like changing passwords, updating theme or preferences will be recorded here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
