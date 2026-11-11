import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/admin_list_filters.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/models/user_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/user_avatar.dart';
import '../widgets/role_badge.dart';

class ManageUserAccountsScreen extends StatefulWidget {
  const ManageUserAccountsScreen({super.key});

  @override
  State<ManageUserAccountsScreen> createState() => _ManageUserAccountsScreenState();
}

class _ManageUserAccountsScreenState extends State<ManageUserAccountsScreen> {
  int _dateDays = 0;
  String _sortOrder = 'Newest first';
  String _group = 'All';

  List<UserModel> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 10;

  int _selectedCategoryIndex = 0; // 0 = All, 1 = Customer, 2 = Businessman, 3 = Government
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialUsers();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadMoreUsers();
      }
    }
  }

  Future<void> _loadInitialUsers() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _hasMore = true;
        _users = [];
      });
    }

    final result = await CustomerStoreService.fetchUsersPaginated(
      page: 0,
      pageSize: _pageSize,
    );

    // Fallback to fetchAllRealUsers if pagination returned empty
    List<UserModel> fetchedList = result.users;
    bool hasNext = result.hasMore;
    if (fetchedList.isEmpty) {
      fetchedList = await CustomerStoreService.fetchAllRealUsers();
      hasNext = false;
    }

    if (mounted) {
      setState(() {
        _users = fetchedList;
        _hasMore = hasNext;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final nextPage = _currentPage + 1;
    final result = await CustomerStoreService.fetchUsersPaginated(
      page: nextPage,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _currentPage = nextPage;
        _users.addAll(result.users);
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter out Admin users
    final nonAdminUsers = _users.where((u) => u.role != UserRole.admin).toList();

    final customerList = nonAdminUsers.where((u) => u.role == UserRole.user).toList();
    final businessmanList = nonAdminUsers.where((u) => u.role == UserRole.owner).toList();
    final governmentList = nonAdminUsers.where((u) => u.role == UserRole.government).toList();

    List<UserModel> categoryFilteredUsers;
    if (_selectedCategoryIndex == 1) {
      categoryFilteredUsers = customerList;
    } else if (_selectedCategoryIndex == 2) {
      categoryFilteredUsers = businessmanList;
    } else if (_selectedCategoryIndex == 3) {
      categoryFilteredUsers = governmentList;
    } else {
      categoryFilteredUsers = nonAdminUsers;
    }

    // Apply Search Query Filter
    final finalFilteredUsers = categoryFilteredUsers.where((u) {
      if (!GovernmentRecordDate.matches(u.joinedDate, _dateDays)) return false;
      if (_group != 'All' && u.status.name != _group) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q) || (u.phone != null && u.phone!.contains(q));
    }).toList();
    finalFilteredUsers.sort((a,b) => _sortOrder == 'Oldest first' ? CaseOrdering.users(b,a) : CaseOrdering.users(a,b));

    final activeCount = nonAdminUsers.where((u) => u.status == AccountStatus.active).toList().length;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Manage Users'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const UserAccountsSkeleton()
            : Column(
              children: [
                // Top Search & Quick Stats Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      // Search Bar
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                        ),
                        child: AppSearchField(suggestions: _users.map((u) => u.name).toList(),
                          controller: _searchCtrl,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by user name or email...',
                            hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                            prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Quick Stats Sub-Bar
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniStatTile('Loaded Accounts', '${nonAdminUsers.length}', Icons.people_alt_outlined, const Color(0xFF0F766E), isDark),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMiniStatTile('Active Users', '$activeCount', Icons.check_circle_outline, const Color(0xFF10B981), isDark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Category Filter Pills Row (All, Customer, Businessman, Government)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    children: [
                      _buildCategoryChip('All', nonAdminUsers.length, 0, _selectedCategoryIndex == 0, const Color(0xFF0F766E)),
                      const SizedBox(width: 6),
                      _buildCategoryChip('Customer', customerList.length, 1, _selectedCategoryIndex == 1, const Color(0xFF0284C7)),
                      const SizedBox(width: 6),
                      _buildCategoryChip('Businessman', businessmanList.length, 2, _selectedCategoryIndex == 2, const Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      _buildCategoryChip('Government', governmentList.length, 3, _selectedCategoryIndex == 3, const Color(0xFF7C3AED)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Main Accounts List View
AdminListFilters( guidance: 'Filters apply to loaded accounts; load more to include additional accounts.', dateLabel: 'Joined', count: finalFilteredUsers.length, days: _dateDays, sort: _sortOrder, groups: const ['All', 'active', 'pendingVerification', 'suspended', 'deactivated'], group: _group, onGroup: (v) => setState(() => _group = v), onSort: (v) => setState(() => _sortOrder = v), onDays: (v) => setState(() => _dateDays = v), onSearch: () => setState(() {})),
                if (_hasMore) TextButton.icon(onPressed: _isLoadingMore ? null : _loadMoreUsers, icon: const Icon(Icons.expand_more_rounded), label: Text(_isLoadingMore ? 'Loading accounts...' : 'Load more accounts to include in filters')),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadInitialUsers,
                    child: finalFilteredUsers.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 60),
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.person_search_outlined, size: 40, color: AppTheme.primaryColor),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No matching users found for "$_searchQuery"'
                                          : (_selectedCategoryIndex == 1
                                              ? 'No Customer accounts found'
                                              : (_selectedCategoryIndex == 2
                                                  ? 'No Businessman accounts found'
                                                  : (_selectedCategoryIndex == 3
                                                      ? 'No Government Official accounts found'
                                                      : 'No user accounts registered yet'))),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : AppTheme.navyColor),
                                    ),
                                    if (_searchQuery.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                        icon: const Icon(Icons.refresh_rounded, size: 16),
                                        label: const Text('Clear Search Filter'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: finalFilteredUsers.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == finalFilteredUsers.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        DualArcLoader(
                                          size: 20,
                                          strokeWidth: 2.2,
                                          color: AppTheme.primaryColor,
                                        ),
                                        SizedBox(width: 10),
                                        Text('Loading more user accounts...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final user = finalFilteredUsers[index];

                              Color roleBorderColor = const Color(0xFF0284C7);
                              if (user.role == UserRole.owner) roleBorderColor = const Color(0xFFD97706);
                              if (user.role == UserRole.government) roleBorderColor = const Color(0xFF7C3AED);

                              final locationStr = [user.state, user.country].where((s) => s != null && s.isNotEmpty).join(', ');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // User Card Top Row (Avatar, Name, Badges)
                                      Row(
                                        children: [
                                          UserAvatar(
                                            avatarUrl: user.avatarUrl,
                                            radius: 24,
                                            border: Border.all(color: roleBorderColor, width: 2),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user.name,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark ? Colors.white : AppTheme.navyColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Icon(Icons.email_outlined, size: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        user.email,
                                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
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
                                      const SizedBox(height: 12),

                                      // Badges & Details Row
                                      Row(
                                        children: [
                                          RoleBadge(role: user.role),
                                          const SizedBox(width: 8),
                                          StatusBadge.fromStatus(user.status.name),
                                          const Spacer(),
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              foregroundColor: AppTheme.primaryColor,
                                            ),
                                            onPressed: () async {
                                              await Navigator.pushNamed(
                                                context,
                                                AppRoutes.accountDetail,
                                                arguments: user,
                                              );
                                              _loadInitialUsers();
                                            },
                                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                                            label: const Text('Manage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          ),
                                        ],
                                      ),

                                      if (locationStr.isNotEmpty || user.joinedDate != null) ...[
                                        const SizedBox(height: 8),
                                        Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                                        const SizedBox(height: 8),
                                        Wrap(spacing: 4, runSpacing: 6,
                                          children: [
                                            if (locationStr.isNotEmpty) ...[
                                              Icon(Icons.location_on_outlined, size: 12, color: isDark ? Colors.white38 : Colors.grey.shade500),
                                              const SizedBox(width: 3),
                                              Text(
                                                locationStr,
                                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                                              ),

                                            ],
                                            if (user.joinedDate != null) ...[
                                              Icon(Icons.calendar_today_outlined, size: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                                              const SizedBox(width: 3),
                                              Text(
                                                'Joined: ${user.joinedDate}',
                                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildMiniStatTile(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, int count, int index, bool isSelected, Color activeColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategoryIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : (isDark ? Colors.white10 : Colors.grey.shade300),
          ),
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
          mainAxisSize: MainAxisSize.min,
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
}
