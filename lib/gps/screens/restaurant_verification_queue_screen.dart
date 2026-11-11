import 'package:flutter/material.dart';
import '../../core/widgets/admin_list_filters.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/status_badge.dart';

class RestaurantVerificationQueueScreen extends StatefulWidget {
  const RestaurantVerificationQueueScreen({super.key});

  @override
  State<RestaurantVerificationQueueScreen> createState() => _RestaurantVerificationQueueScreenState();
}

class _RestaurantVerificationQueueScreenState extends State<RestaurantVerificationQueueScreen> {
  final TextEditingController _filterSearch = TextEditingController();
  int _dateDays = 0;
  String _sortOrder = 'Oldest first';
  String _group = 'All';

  final ScrollController _scrollController = ScrollController();
  final List<RestaurantModel> _pendingOutlets = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadInitialPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _filterSearch.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore && !_isLoading) {
        _loadMoreOutlets();
      }
    }
  }

  Future<void> _loadInitialPage() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _hasMore = true;
        _pendingOutlets.clear();
      });
    }

    final newOutlets = (await RestaurantStoreService.fetchAllRestaurants(forceRefresh: true)).where((r) => r.status == RestaurantStatus.pendingVerification).toList();
    if (mounted) {
      setState(() {
        _pendingOutlets.addAll(newOutlets);
        _pendingOutlets.sort(CaseOrdering.restaurants);
        _isLoading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _loadMoreOutlets() async {
    if (_isLoadingMore || !_hasMore) return;

    if (mounted) {
      setState(() => _isLoadingMore = true);
    }

    final nextPage = _currentPage + 1;
    final newOutlets = await RestaurantStoreService.fetchPendingRestaurantsPaginated(
      page: nextPage,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _currentPage = nextPage;
        _pendingOutlets.addAll(newOutlets);
        _pendingOutlets.sort(CaseOrdering.restaurants);
        _isLoadingMore = false;
        if (newOutlets.length < _pageSize) {
          _hasMore = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = _filterSearch.text.trim().toLowerCase();
    final groups = ['All', ...(_pendingOutlets.map((r) => r.category).toSet().toList()..sort())];
    final filtered = _pendingOutlets.where((r) => (_group == 'All' || r.category == _group) && GovernmentRecordDate.matches(r.createdAt, _dateDays) && '${r.name} ${r.id} ${r.category}'.toLowerCase().contains(q)).toList()..sort((a,b) => GovernmentRecordDate.compare(a.createdAt,b.createdAt,_sortOrder == 'Oldest first'));

    return Scaffold(
      appBar: const CustomAppBar(title: 'Pending Outlets'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const ListSkeleton(itemCount: 3)
            : RefreshIndicator(
                onRefresh: _loadInitialPage,
              child: Column(children: [
              AdminListFilters(search: _filterSearch, hint: 'Search outlet, application ID or category', guidance: 'Review older applications first; filter by outlet category or search name and ID.', dateLabel: 'Submitted', count: filtered.length, days: _dateDays, sort: _sortOrder, groups: groups, group: _group, onGroup: (v) => setState(() => _group = v), onSort: (v) => setState(() => _sortOrder = v), onDays: (v) => setState(() => _dateDays = v), onSearch: () => setState(() {})),

              Expanded(child: filtered.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.verified_rounded, size: 48, color: Colors.green),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No Matching Outlet Requests',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : AppTheme.navyColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'No matching applications. Try clearing search or changing the filters.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == filtered.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const DualArcLoader(
                                    size: 20,
                                    strokeWidth: 2.2,
                                    color: Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Loading more pending outlets...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final r = filtered[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? Colors.white10 : Colors.amber.withValues(alpha: 0.3)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        r.imageUrl,
                                        width: 54,
                                        height: 54,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          width: 54,
                                          height: 54,
                                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                                          child: const Icon(Icons.restaurant, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : AppTheme.navyColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text('Submitted: ${GovernmentRecordDate.format(r.createdAt)}', style: TextStyle(fontSize: 11, height: 1.5, color: isDark ? Colors.white60 : AppTheme.subtitleColor)),
                                          const SizedBox(height: 6),
                                          Wrap(spacing: 6, runSpacing: 6,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  r.category,
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              StatusBadge.fromStatus(r.status.name),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        r.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      r.operatingHours.isNotEmpty ? r.operatingHours : '10:00 AM - 10:00 PM',
                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                                    ),
                                    const Spacer(),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFD97706),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        elevation: 0,
                                      ),
                                      onPressed: () async {
                                        await Navigator.pushNamed(
                                          context,
                                          AppRoutes.restaurantVerificationDetail,
                                          arguments: r,
                                        );
                                        if (mounted) {
                                          _loadInitialPage();
                                        }
                                      },
                                      icon: const Icon(Icons.rate_review_rounded, size: 16),
                                      label: const Text('Review Application', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )),
              ]),
            ),
      ),
    );
  }
}
