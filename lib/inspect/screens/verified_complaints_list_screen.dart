import '../../core/widgets/app_search_field.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/workflow_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../notifications/models/notification_model.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/status_badge.dart';

class VerifiedComplaintsListScreen extends StatefulWidget {
  const VerifiedComplaintsListScreen({super.key});

  @override
  State<VerifiedComplaintsListScreen> createState() => _VerifiedComplaintsListScreenState();
}

class _VerifiedComplaintsListScreenState extends State<VerifiedComplaintsListScreen> {
  int _dateDays = 0;
  String _sortOrder = 'Next action';
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _realtimeChannel;
  List<ComplaintModel> _realCases = [];
  String _selectedStatus = 'Active Cases';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _displayedCount = 20;
  final int _pageSize = 20;

  final List<String> _statusFilters = [
    'Active Cases',
    'All Assigned',
    'Priority Visits',
    'Investigating',
    'Scheduled',
    'Resolved',
  ];

  @override
  void initState() {
    super.initState();
    _loadRealData();
    _setupRealtimeSubscription();
    ComplaintStoreService.complaintsNotifier.addListener(_onNotifierUpdate);
    RestaurantStoreService.inspectionsNotifier.addListener(_onNotifierUpdate);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    ComplaintStoreService.complaintsNotifier.removeListener(_onNotifierUpdate);
    RestaurantStoreService.inspectionsNotifier.removeListener(_onNotifierUpdate);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onNotifierUpdate() {
    if (mounted) {
      setState(() {
        _realCases = List.from(ComplaintStoreService.complaintsNotifier.value);
      });
    }
  }

  Future<void> _loadRealData({bool isRefresh = false}) async {
    if (!isRefresh && _realCases.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final futures = await Future.wait([
        ComplaintStoreService.fetchAllComplaints(forceRefresh: true),
        RestaurantStoreService.fetchInspections(),
      ]);
      final fetched = futures[0] as List<ComplaintModel>;
      for (final complaint in fetched) {
        final workflow = await WorkflowService.loadWorkflow(complaint.id);
        final deadline = workflow?.rectificationDeadline;
        final hasOwnerEvidence = RestaurantStoreService.isRectificationSubmitted(
          complaint.restaurantId,
          complaintId: complaint.id,
        );
        if (workflow?.isOwnerRectificationActive == true &&
            deadline != null &&
            !deadline.isAfter(DateTime.now().toUtc()) &&
            !hasOwnerEvidence) {
          await WorkflowService.expireOwnerRectification(complaintId: complaint.id);
          NotificationService.sendNotification(
            userId: 'gov_officer_001',
            title: '⏰ Owner Evidence Window Expired',
            message: 'The 7-day owner evidence window for ${complaint.restaurantName} expired. The case is ready for manual inspection scheduling.',
            type: NotificationType.hygieneAlert,
            actionUrl: 'verified_complaints_list',
          );
        }
      }
      if (mounted) {
        setState(() {
          _realCases = fetched;
          _displayedCount = _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error fetching real complaints from Supabase: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealtimeSubscription() {
    try {
      _realtimeChannel = SupabaseService.client
          .channel('public:complaints_inspections:live_sync')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'complaints',
            callback: (payload) async {
              final freshList = await ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
              await RestaurantStoreService.fetchInspections();
              if (mounted) {
                setState(() {
                  _realCases = freshList;
                });
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inspections',
            callback: (payload) async {
              await RestaurantStoreService.fetchInspections();
              final freshList = await ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
              if (mounted) {
                setState(() {
                  _realCases = freshList;
                });
              }
            },
          )
          .subscribe();
    } catch (e) {
      if (kDebugMode) print('Realtime subscription error in VerifiedComplaintsList: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150 &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMoreCases();
    }
  }

  Future<void> _loadMoreCases() async {
    final filtered = _getFilteredCases();
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

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_')) {
      return rawId.toUpperCase();
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  List<ComplaintModel> _getFilteredCases({String? status, bool applySearch = true}) {
    final selectedStatus = status ?? _selectedStatus;
    final filtered = _realCases.where((c) {
      final restName = RestaurantStoreService.resolveRestaurantName(c.restaurantName, fallback: c.restaurantName).toLowerCase();
      final caseId = _formatCaseId(c.id).toLowerCase();
      final category = c.category.toLowerCase();

      final linkedInsp = RestaurantStoreService.inspectionsNotifier.value.where((i) {
        final matchId = i.id == c.id || (i.complaintId.isNotEmpty && (i.complaintId == c.id || i.complaintId.toLowerCase() == c.id.toLowerCase()));
        return matchId;
      }).firstOrNull;

      final isResolved = c.status == ComplaintStatus.resolved || (linkedInsp != null && linkedInsp.enforcementStatus == EnforcementStatus.completed);
      final isScheduled = c.status == ComplaintStatus.pendingInspection || (linkedInsp != null && linkedInsp.scheduledDate.isNotEmpty && linkedInsp.outcome == InspectionOutcome.pending);

      // Exclude reports still pending admin duplication scan / verification
      if (c.status == ComplaintStatus.submitted || c.isFlaggedForReview) return false;

      // Exclude rejected / fake reports
      if (c.status == ComplaintStatus.rejected) return false;

      // Check Priority Visit Criteria (Owner submitted evidence OR 7-day period expired)
      final bool hasOwnerEvidence = RestaurantStoreService.isRectificationSubmitted(
            c.restaurantId,
            complaintId: c.id,
            inspectionId: linkedInsp?.id,
          ) ||
          (linkedInsp != null &&
              RestaurantStoreService.isRectificationSubmitted(
                linkedInsp.restaurantId,
                inspectionId: linkedInsp.id,
              ));

      final workflow = WorkflowService.getCachedWorkflow(c.id);
      final bool is7DaysOverdue = !hasOwnerEvidence &&
          workflow?.isOfficerReviewPending == true &&
          workflow?.rectificationDeadline != null &&
          !workflow!.rectificationDeadline!.isAfter(DateTime.now().toUtc());
      final bool isPriorityVisit = (hasOwnerEvidence || is7DaysOverdue) && !isResolved && (linkedInsp?.conductedDate == null || linkedInsp?.outcome == InspectionOutcome.pending);

      if (applySearch && !GovernmentRecordDate.matches(c.submittedAt, _dateDays)) return false;
      if (selectedStatus == 'Active Cases' && isResolved) return false;

      // Only include cases that match selected filter
      if (selectedStatus == 'Priority Visits') {
        if (!isPriorityVisit) return false;
      } else if (selectedStatus == 'Investigating') {
        if (isResolved || isScheduled) return false;
      } else if (selectedStatus == 'Scheduled' || selectedStatus == 'Pending') {
        if (!isScheduled || isResolved) return false;
      } else if (selectedStatus == 'Resolved') {
        if (!isResolved) return false;
      }

      if (applySearch && _searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return restName.contains(query) || caseId.contains(query) || category.contains(query);
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sortOrder == 'Next action') {
        final rank = _queueRank(a).compareTo(_queueRank(b));
        if (rank != 0) return rank;
        final byDate = GovernmentRecordDate.compare(_queueDate(a), _queueDate(b), true);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      }
      return GovernmentRecordDate.compare(a.submittedAt, b.submittedAt, _sortOrder == 'Oldest first');
    });

    return filtered;
  }

  InspectionModel? _inspection(ComplaintModel c) => RestaurantStoreService.inspectionsNotifier.value.where((i) => i.complaintId.toLowerCase() == c.id.toLowerCase() || i.id == c.id).firstOrNull;

  int _queueRank(ComplaintModel c) {
    final i = _inspection(c);
    if (c.status == ComplaintStatus.resolved || i?.enforcementStatus == EnforcementStatus.completed) return 4;
    if (i?.outcome == InspectionOutcome.pending && DateTime.tryParse(i!.scheduledDate)?.isBefore(DateTime.now()) == true) return 0;
    if (i == null || i.requiresReschedule) return 1;
    if (i.outcome == InspectionOutcome.pending) return 2;
    return 3;
  }

  String _queueDate(ComplaintModel c) => _inspection(c)?.scheduledDate ?? c.submittedAt;

  String _nextAction(ComplaintModel c) {
    final i = _inspection(c);
    if (_queueRank(c) == 4) return 'Closed • View case summary';
    if (i?.requiresReschedule == true) return 'Next: Review feedback and reschedule';
    if (i == null) return 'Next: Review case and scheduling eligibility';
    if (i.outcome == InspectionOutcome.pending) return '${_queueRank(c) == 0 ? 'Overdue • ' : ''}Next: Open scheduled visit';
    return 'Next: Review inspection and enforcement progress';
  }

  Map<String, dynamic> _getCategoryIconInfo(String category) {
    final low = category.toLowerCase();
    if (low.contains('pest') || low.contains('rat') || low.contains('cockroach')) {
      return {
        'icon': Icons.pest_control_rounded,
        'color': const Color(0xFFDC2626),
        'bg': const Color(0xFFFEE2E2),
      };
    } else if (low.contains('poison') || low.contains('vomit') || low.contains('diarrhea')) {
      return {
        'icon': Icons.medical_services_outlined,
        'color': const Color(0xFF7C3AED),
        'bg': const Color(0xFFF3E8FF),
      };
    } else if (low.contains('hygiene') || low.contains('staff') || low.contains('clean')) {
      return {
        'icon': Icons.cleaning_services_rounded,
        'color': const Color(0xFF0F766E),
        'bg': const Color(0xFFCCFBF1),
      };
    } else {
      return {
        'icon': Icons.verified_user_rounded,
        'color': const Color(0xFF0284C7),
        'bg': const Color(0xFFE0F2FE),
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allCases = _getFilteredCases(status: 'All Assigned', applySearch: false);
    final filteredCases = _getFilteredCases();
    final paginatedCases = filteredCases.take(_displayedCount).toList();

    final pendingCount = _getFilteredCases(status: 'Scheduled', applySearch: false).length;
    final resolvedCount = _getFilteredCases(status: 'Resolved', applySearch: false).length;

    final activeInspectCount = (allCases.length - resolvedCount - pendingCount).clamp(0, allCases.length);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Assigned Cases',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh & Sync Cases',
            onPressed: () => _loadRealData(isRefresh: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const AssignedCasesSkeleton()
            : RefreshIndicator(
              onRefresh: () => _loadRealData(isRefresh: true),
              color: const Color(0xFF0F766E),
              child: Column(
                children: [
                  // 1. TOP SUMMARY METRICS (REAL SUPABASE COUNTS)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        _buildStatPill('Total Cases', '${allCases.length}', const Color(0xFF0F766E), isDark),
                        const SizedBox(width: 8),
                        _buildStatPill('Pending Visit', '$pendingCount', const Color(0xFFD97706), isDark),
                        const SizedBox(width: 8),
                        _buildStatPill('Other Active', '$activeInspectCount', const Color(0xFF0284C7), isDark),
                      ],
                    ),
                  ),

                  // 2. SEARCH BAR
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: AppSearchField(suggestions: _realCases.map((c) => c.restaurantName).toList(),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim();
                          _displayedCount = _pageSize;
                        });
                      },
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by outlet, case ID, or category...',
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

                  // 3. STATUS FILTER CHIPS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _statusFilters.map((st) {
                          final isSelected = (_selectedStatus == st);
                          final count = _getFilteredCases(status: st, applySearch: false).length;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text('$st ($count)'),
                              selected: isSelected,
                              selectedColor: const Color(0xFF0F766E),
                              backgroundColor: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
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
                                  _selectedStatus = val ? st : 'All Assigned';
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

                  // 4. ASSIGNED CASES LIST WITH INFINITE SCROLL
                  GovernmentListTools(guidance: 'Start with active cases: overdue visits, unscheduled cases, upcoming visits, then follow-up.', dateLabel: 'Reported',
                    count: filteredCases.length, days: _dateDays, sort: _sortOrder, sorts: const ['Next action', 'Newest first', 'Oldest first'],
                    onDays: (v) => setState(() { _dateDays = v; _displayedCount = _pageSize; }),
                    onSort: (v) => setState(() { _sortOrder = v; _displayedCount = _pageSize; })),
                  Expanded(
                    child: filteredCases.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            itemCount: paginatedCases.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == paginatedCases.length) {
                                return _buildLoadingMoreIndicator(isDark);
                              }

                              final c = paginatedCases[index];
                              final formattedId = _formatCaseId(c.id);
                              final restName = RestaurantStoreService.resolveRestaurantName(c.restaurantName, fallback: c.restaurantName);
                              final iconInfo = _getCategoryIconInfo(c.category);
                              final IconData catIcon = iconInfo['icon'] as IconData;
                              final Color catColor = iconInfo['color'] as Color;
                              final Color catBg = iconInfo['bg'] as Color;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
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
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.complaintFullDetail,
                                        arguments: c,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isDark ? catColor.withValues(alpha: 0.2) : catBg,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(catIcon, color: catColor, size: 22),
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
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.grey),
                                                  ],
                                                ),
                                                 const SizedBox(height: 6),
                                                 Wrap(
                                                   spacing: 6,
                                                   runSpacing: 4,
                                                   children: [
                                                     Container(
                                                       padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                       decoration: BoxDecoration(
                                                         color: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                                                         borderRadius: BorderRadius.circular(6),
                                                         border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                                                       ),
                                                       child: Text(
                                                         'Report ID: $formattedId',
                                                         style: TextStyle(
                                                           fontSize: 10.5,
                                                           fontWeight: FontWeight.bold,
                                                           color: isDark ? Colors.white70 : const Color(0xFF475569),
                                                         ),
                                                       ),
                                                     ),
                                                     Container(
                                                       padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                       decoration: BoxDecoration(
                                                         color: catColor.withValues(alpha: 0.1),
                                                         borderRadius: BorderRadius.circular(6),
                                                       ),
                                                       child: Text(
                                                         c.category,
                                                         style: TextStyle(
                                                           fontSize: 10.5,
                                                           fontWeight: FontWeight.bold,
                                                           color: catColor,
                                                         ),
                                                       ),
                                                     ),
                                                   ],
                                                 ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF0284C7)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'GPS: ${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                 const SizedBox(height: 8),
                                                 _buildDynamicCaseStatusBadge(c, isDark),
                                                 const SizedBox(height: 8),
                                                 Container(
                                                   width: double.infinity,
                                                   padding: const EdgeInsets.all(10),
                                                   decoration: BoxDecoration(
                                                     color: isDark ? const Color(0xFF282828) : const Color(0xFFF8FAFC),
                                                     borderRadius: BorderRadius.circular(10),
                                                   ),
                                                   child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                     Text('Reported: ${GovernmentRecordDate.format(c.submittedAt)}', style: TextStyle(fontSize: 11, height: 1.5, color: isDark ? Colors.white60 : const Color(0xFF64748B))),
                                                     if (_inspection(c) != null) Text('Visit: ${GovernmentRecordDate.format(_inspection(c)!.scheduledDate)}', style: TextStyle(fontSize: 11, height: 1.5, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                                                     const SizedBox(height: 6),
                                                     Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                       Icon(Icons.arrow_circle_right_outlined, size: 15, color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E)),
                                                       const SizedBox(width: 6),
                                                       Expanded(child: Text(_nextAction(c), style: TextStyle(fontSize: 11.5, height: 1.35, color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E), fontWeight: FontWeight.w600))),
                                                     ]),
                                                   ]),
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

  Widget _buildDynamicCaseStatusBadge(ComplaintModel c, bool isDark) {
    final linkedInsp = RestaurantStoreService.inspectionsNotifier.value.where((i) {
      final matchId = i.id == c.id || (i.complaintId.isNotEmpty && (i.complaintId == c.id || i.complaintId.toLowerCase() == c.id.toLowerCase()));
      return matchId;
    }).firstOrNull;

    if (c.status == ComplaintStatus.resolved || (linkedInsp != null && linkedInsp.enforcementStatus == EnforcementStatus.completed)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFF059669).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
            SizedBox(width: 4),
            Text(
              'Resolved (Case Closed)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
            ),
          ],
        ),
      );
    }

    if (linkedInsp != null && linkedInsp.issuedDate != null && linkedInsp.issuedDate!.isNotEmpty && linkedInsp.issuedAction != EnforcementType.none) {
      final isClosure = linkedInsp.issuedAction == EnforcementType.closure;
      final Color color = isClosure ? const Color(0xFFDC2626) : const Color(0xFFD97706);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isClosure ? Icons.block_rounded : Icons.gavel_rounded, size: 12, color: color),
            SizedBox(width: 4),
            Text(
              isClosure ? 'Decree: Closure Notice' : 'Decree: Compound (RM ${linkedInsp.fineAmount.toStringAsFixed(0)})',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      );
    }

    if (linkedInsp != null && linkedInsp.conductedDate != null && linkedInsp.conductedDate!.isNotEmpty) {
      final isCompliant = linkedInsp.outcome == InspectionOutcome.compliant;
      final Color color = isCompliant ? const Color(0xFF059669) : const Color(0xFFDC2626);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isCompliant ? Icons.verified_rounded : Icons.warning_amber_rounded, size: 12, color: color),
            SizedBox(width: 4),
            Text(
              isCompliant ? 'Audit Passed' : 'Audit Conducted (Action Needed)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      );
    }

    if (c.status == ComplaintStatus.pendingInspection || (linkedInsp != null && linkedInsp.scheduledDate.isNotEmpty && linkedInsp.outcome == InspectionOutcome.pending)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF0284C7)),
            SizedBox(width: 4),
            Text(
              'Visit Scheduled',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
            ),
          ],
        ),
      );
    }

    return StatusBadge.fromStatus(c.status.name);
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
            'Loading more assigned cases...',
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
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
              child: Icon(
                Icons.assignment_turned_in_outlined,
                size: 40,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No Assigned Cases Found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF0C2340),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No complaint inspection cases match your selected filter or search term.',
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
