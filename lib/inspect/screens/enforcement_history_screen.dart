import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/payment_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/stripe_payment_service.dart';
import '../../core/utils/uuid_helper.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/status_badge.dart';

class EnforcementHistoryScreen extends StatefulWidget {
  const EnforcementHistoryScreen({super.key});

  @override
  State<EnforcementHistoryScreen> createState() => _EnforcementHistoryScreenState();
}

class _EnforcementHistoryScreenState extends State<EnforcementHistoryScreen> {
  int _dateDays = 0;
  String _sortOrder = 'Newest first';
  final ScrollController _scrollController = ScrollController();
  String _selectedFilter = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _displayedCount = 10;
  final int _pageSize = 10;
  List<PaymentModel> _paymentLedger = [];

  final List<String> _filterOptions = [
    'All',
    'Pending',
    'In Progress',
    'Completed',
    'Closure',
    'Fine',
    'Warning',
  ];

  String _formatDate(String? raw) => GovernmentRecordDate.format(raw);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        StripePaymentService.getAllPayments(),
        RestaurantStoreService.fetchInspections(),
        RestaurantStoreService.fetchAllRestaurants(),
      ]);
      _paymentLedger = futures[0] as List<PaymentModel>;
    } catch (_) {
      _paymentLedger = [];
    }
    if (mounted) {
      setState(() {
        _displayedCount = _pageSize;
        _isLoading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150 &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMoreActions();
    }
  }

  Future<void> _loadMoreActions() async {
    final filtered = _getFilteredList();
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

  bool _isDecreedAction(InspectionModel insp) {
    // A record belongs in Action History ONLY if an enforcement decree has been officially issued, completed, or compliant audit conducted
    if (insp.outcome == InspectionOutcome.pending) return false;
    if (insp.conductedDate == null || insp.conductedDate!.isEmpty || insp.conductedDate == 'null') return false;
    final hasIssuedDate = insp.issuedDate != null && insp.issuedDate!.isNotEmpty && insp.issuedDate != 'null';
    final hasIssuedAction = insp.issuedAction != EnforcementType.none;
    final isCompleted = insp.enforcementStatus == EnforcementStatus.completed;
    final isCompliantAudit = insp.outcome == InspectionOutcome.compliant;
    return hasIssuedDate || hasIssuedAction || isCompleted || isCompliantAudit;
  }

  List<InspectionModel> _getFilteredList() {
    final filtered = RestaurantStoreService.inspectionsNotifier.value.where((insp) {
      if (!GovernmentRecordDate.matches(insp.issuedDate ?? insp.conductedDate, _dateDays)) return false;
      if (!_isDecreedAction(insp)) return false;

      final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName).toLowerCase();
      final actionStr = insp.issuedAction.name.toLowerCase();
      final statusStr = insp.enforcementStatus.name.toLowerCase();

      if (_selectedFilter != 'All') {
        if (_selectedFilter == 'Pending' && statusStr != 'pending') return false;
        if (_selectedFilter == 'In Progress' && statusStr != 'inprogress') return false;
        if (_selectedFilter == 'Completed' && statusStr != 'completed') return false;
        if (_selectedFilter == 'Closure' && actionStr != 'closure') return false;
        if (_selectedFilter == 'Fine' && actionStr != 'fine') return false;
        if (_selectedFilter == 'Warning' && actionStr != 'warning') return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return restName.contains(q) || actionStr.contains(q) || insp.officerName.toLowerCase().contains(q);
      }

      return true;
    }).toList();
    filtered.sort((a, b) => GovernmentRecordDate.compare(a.issuedDate ?? a.conductedDate, b.issuedDate ?? b.conductedDate, _sortOrder == 'Oldest first'));
    return filtered;
  }

  bool _isEffectivelyPaid(InspectionModel insp) {
    if (insp.isFinePaid) return true;
    if (_paymentLedger.isEmpty || insp.fineAmount <= 0) return false;
    final String nameKey = insp.restaurantName.toLowerCase().trim();
    final String uuidKey = UuidHelper.toDeterministicUuid(insp.restaurantId);
    return _paymentLedger.any((p) {
      if (p.status != 'succeeded') return false;
      final pName = p.restaurantName.toLowerCase().trim();
      final metaComplaint = p.metadata['complaint_id']?.toString() ?? '';
      return p.restaurantId == insp.restaurantId ||
          p.restaurantId == uuidKey ||
          (nameKey.isNotEmpty && pName == nameKey) ||
          (insp.complaintId.isNotEmpty && metaComplaint == insp.complaintId);
    });
  }

  Map<String, dynamic> _getActionVisuals(EnforcementType type) {
    switch (type) {
      case EnforcementType.closure:
        return {
          'icon': Icons.block_rounded,
          'color': const Color(0xFFDC2626),
          'bg': const Color(0xFFFEE2E2),
          'label': 'Closure Notice',
        };
      case EnforcementType.fine:
        return {
          'icon': Icons.payments_rounded,
          'color': const Color(0xFFD97706),
          'bg': const Color(0xFFFEF3C7),
          'label': 'Compound Fine',
        };
      case EnforcementType.warning:
        return {
          'icon': Icons.warning_amber_rounded,
          'color': const Color(0xFF2563EB),
          'bg': const Color(0xFFDBEAFE),
          'label': 'Warning Directive',
        };
      case EnforcementType.none:
        return {
          'icon': Icons.check_circle_outline_rounded,
          'color': const Color(0xFF059669),
          'bg': const Color(0xFFD1FAE5),
          'label': 'Compliant',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allList = RestaurantStoreService.inspectionsNotifier.value.where(_isDecreedAction).toList();
    final filtered = _getFilteredList();
    final paginated = filtered.take(_displayedCount).toList();

    final totalFines = allList.fold<double>(0, (sum, i) => sum + i.fineAmount);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Action History',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Actions',
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const ActionHistorySkeleton()
            : RefreshIndicator(
              onRefresh: _loadInitialData,
              color: const Color(0xFF0F766E),
              child: Column(
                children: [
                  // 1. TOP STATS COUNTER PILLS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        _buildStatPill('Total Actions', '${allList.length}', const Color(0xFF0F766E), isDark),
                        const SizedBox(width: 8),
                        _buildStatPill('Total Fines', 'RM ${totalFines.toInt()}', const Color(0xFFDC2626), isDark),
                        const SizedBox(width: 8),
                        _buildStatPill('In Progress', '${allList.where((i) => i.enforcementStatus == EnforcementStatus.inProgress).length}', const Color(0xFFD97706), isDark),
                      ],
                    ),
                  ),

                  // 2. SEARCH BAR
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: AppSearchField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim();
                          _displayedCount = _pageSize;
                        });
                      },
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search actions by premise, fine, or officer...',
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

                  // 3. FILTER CHIPS ROW
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filterOptions.map((opt) {
                          final isSelected = (_selectedFilter == opt);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(opt),
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
                                  _selectedFilter = val ? opt : 'All';
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

                  // 4. ACTION HISTORY LIST WITH INFINITE SCROLL
                  GovernmentListTools(guidance: 'Review issued actions • Filter Pending or In Progress for follow-up; paid fines may still need case closure.', dateLabel: 'Action',
                    count: filtered.length, days: _dateDays, sort: _sortOrder, sorts: const ['Newest first', 'Oldest first'],
                    onDays: (v) => setState(() { _dateDays = v; _displayedCount = _pageSize; }),
                    onSort: (v) => setState(() { _sortOrder = v; _displayedCount = _pageSize; })),
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            itemCount: paginated.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == paginated.length) {
                                return _buildLoadingMoreIndicator(isDark);
                              }

                              final insp = paginated[index];
                              final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName);
                              final visuals = _getActionVisuals(insp.issuedAction);
                              final IconData icon = visuals['icon'] as IconData;
                              final Color iconColor = visuals['color'] as Color;
                              final Color iconBg = visuals['bg'] as Color;
                              final String actionLabel = visuals['label'] as String;
                              final bool finePaid = _isEffectivelyPaid(insp);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      Navigator.pushNamed(context, AppRoutes.closeCaseDetail, arguments: insp);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isDark ? iconColor.withValues(alpha: 0.2) : iconBg,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(icon, color: iconColor, size: 22),
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
                                                        restName,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 15,
                                                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                                                        ),

                                                      ),
                                                    ),
                                                    StatusBadge.fromStatus(insp.enforcementStatus.name),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Decree: $actionLabel',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: iconColor,
                                                  ),
                                                ),
                                                if (insp.fineAmount > 0) ...[
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'Compound Penalty: RM ${insp.fineAmount.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Color(0xFFDC2626),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: finePaid ? const Color(0xFF059669).withValues(alpha: 0.1) : const Color(0xFFDC2626).withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          finePaid ? 'PAID' : 'UNPAID',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: finePaid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.badge_outlined, size: 13, color: Colors.grey),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        'Officer: ${insp.officerName}\n${insp.issuedDate == null ? 'Inspected' : 'Issued'}: ${_formatDate(insp.issuedDate ?? insp.conductedDate)}\nCase: ${insp.complaintId}\nPayment and case progress are tracked separately.',
                                                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),

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
            'Loading more actions...',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : const Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String count, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
              child: Icon(Icons.history_toggle_off_rounded, size: 40, color: isDark ? Colors.white38 : Colors.grey.shade400),
            ),
            const SizedBox(height: 14),
            Text(
              'No Enforcement Actions Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : const Color(0xFF0C2340)),
            ),
            const SizedBox(height: 6),
            Text(
              'No enforcement history records match your search query or selected filter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.grey.shade600, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
