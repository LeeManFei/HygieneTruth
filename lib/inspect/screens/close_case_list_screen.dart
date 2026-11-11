import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/widgets/custom_app_bar.dart';

class CloseCaseListScreen extends StatefulWidget {
  const CloseCaseListScreen({super.key});

  @override
  State<CloseCaseListScreen> createState() => _CloseCaseListScreenState();
}

class _CloseCaseListScreenState extends State<CloseCaseListScreen> {
  int _dateDays = 0;
  String _sortOrder = 'Newest first';
  final TextEditingController _searchCtrl = TextEditingController();
  int _selectedTab = 0; // 0: Ready for Closure, 1: All Active Cases, 2: Closed History

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await Future.wait([
        RestaurantStoreService.fetchInspections(),
        RestaurantStoreService.fetchAllRestaurants(),
        ComplaintStoreService.fetchAllComplaints(forceRefresh: true),
      ]);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_') || rawId.startsWith('CMP_')) {
      return rawId.toUpperCase().replaceAll('_', '-');
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  String _formatDate(String? raw) => GovernmentRecordDate.format(raw);

  bool _isValidForCloseCaseScreen(InspectionModel insp) {
    // Only cases where visit was conducted, admin approved, and decree was issued (or compliant audit)
    if (insp.outcome == InspectionOutcome.pending) return false;
    if (insp.conductedDate == null || insp.conductedDate!.isEmpty || insp.conductedDate == 'null') return false;

    final bool isApproved = insp.isAdminApproved ||
        RestaurantStoreService.isAdminInspectionApproved(
          insp.id,
          complaintId: insp.complaintId,
          restaurantId: insp.restaurantId,
        );
    if (!isApproved) return false;

    final bool hasDecree = (insp.issuedDate != null && insp.issuedDate!.isNotEmpty && insp.issuedDate != 'null') ||
        insp.issuedAction != EnforcementType.none ||
        insp.outcome == InspectionOutcome.compliant;
    if (!hasDecree) return false;

    return true;
  }

  bool _isReadyForClosure(InspectionModel insp) {
    if (!_isValidForCloseCaseScreen(insp)) return false;
    if (insp.enforcementStatus == EnforcementStatus.completed) return false;

    final bool isFinePaid = insp.fineAmount <= 0 ||
        (RestaurantStoreService.isOutletFinePaid(
          insp.restaurantId,
          restaurantName: insp.restaurantName,
          complaintId: insp.complaintId,
          inspectionId: insp.id,
        ) || (insp.isFinePaid && insp.enforcementStatus == EnforcementStatus.completed));
    if (!isFinePaid) return false;

    // Check owner remediation if non-compliant
    final bool isRemediationDone = insp.outcome == InspectionOutcome.compliant ||
        RestaurantStoreService.isRectificationSubmitted(
          insp.restaurantId,
          complaintId: insp.complaintId,
          inspectionId: insp.id,
        ) ||
        RestaurantStoreService.isRectificationVerified(
          complaintId: insp.complaintId,
          inspectionId: insp.id,
          restaurantId: insp.restaurantId,
        );

    return isRemediationDone;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Close Case Management',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Cases',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 22),
            tooltip: 'Enforcement History',
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.enforcementHistory);
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ValueListenableBuilder<List<InspectionModel>>(
          valueListenable: RestaurantStoreService.inspectionsNotifier,
        builder: (context, allInspections, _) {
          final query = _searchCtrl.text.trim().toLowerCase();

          // Filter groups
          final validInspections = allInspections.where(_isValidForCloseCaseScreen).toList();
          final readyCases = validInspections.where((insp) => _isReadyForClosure(insp)).toList();
          final activeCases = validInspections.where((insp) => insp.enforcementStatus != EnforcementStatus.completed).toList();
          final closedCases = allInspections.where((insp) => insp.enforcementStatus == EnforcementStatus.completed).toList();

          List<InspectionModel> baseList;
          if (_selectedTab == 0) {
            baseList = readyCases;
          } else if (_selectedTab == 1) {
            baseList = activeCases;
          } else {
            baseList = closedCases;
          }

          final currentDisplayList = baseList.where((insp) {
            if (!GovernmentRecordDate.matches(insp.issuedDate ?? insp.conductedDate, _dateDays)) return false;
            if (query.isNotEmpty) {
              final rName = insp.restaurantName.toLowerCase();
              final cId = insp.complaintId.toLowerCase();
              final iId = insp.id.toLowerCase();
              final cit = (insp.statutoryCitation ?? '').toLowerCase();
              if (!rName.contains(query) && !cId.contains(query) && !iId.contains(query) && !cit.contains(query)) {
                return false;
              }
            }
            return true;
          }).toList();
          currentDisplayList.sort((a, b) => GovernmentRecordDate.compare(a.issuedDate ?? a.conductedDate, b.issuedDate ?? b.conductedDate, _sortOrder == 'Oldest first'));

          return Column(
            children: [
              // Top KPI Summary Banner
              Container(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Ready to Close',
                              count: '${readyCases.length}',
                              color: const Color(0xFF059669),
                              icon: Icons.check_circle_outline_rounded,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'In Progress',
                              count: '${activeCases.length}',
                              color: const Color(0xFFD97706),
                              icon: Icons.pending_actions_rounded,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Closed Cases',
                              count: '${closedCases.length}',
                              color: const Color(0xFF0F766E),
                              icon: Icons.folder_off_outlined,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Search Bar
                    AppSearchField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search cases by restaurant, citation, or ID...',
                        hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
                        prefixIcon: Icon(Icons.search_rounded, size: 18, color: isDark ? Colors.white54 : Colors.grey.shade500),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setState(() => _searchCtrl.clear()),
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Queue Filter Tabs
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip(0, 'Ready for Closure (${readyCases.length})'),
                    _buildFilterChip(1, 'All Active Cases (${activeCases.length})'),
                    _buildFilterChip(2, 'Closed Cases (${closedCases.length})'),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

                  GovernmentListTools(guidance: 'Close ready cases first; use All Active Cases to review unpaid fines or outstanding evidence.', dateLabel: 'Action',
                    count: currentDisplayList.length, days: _dateDays, sort: _sortOrder, sorts: const ['Newest first', 'Oldest first'],
                    onDays: (v) => setState(() { _dateDays = v;  }),
                    onSort: (v) => setState(() { _sortOrder = v;  })),
              // Content List
              Expanded(
                child: currentDisplayList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.verified_rounded, size: 48, color: Color(0xFF059669)),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _selectedTab == 0
                                    ? 'No matching cases ready to close'
                                    : (_selectedTab == 1 ? 'No Active Enforcement Cases' : 'No Closed Cases Recorded'),
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0C2340),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _selectedTab == 0
                                    ? 'Try All Active Cases to review outstanding requirements, or widen your search and date filter.'
                                    : 'All enforcement records will appear here as field audits and corrective actions progress.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() { _selectedTab = 1; _dateDays = 0; _searchCtrl.clear(); });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.history_rounded, size: 16),
                                label: const Text('View Active Cases'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: currentDisplayList.length,
                        itemBuilder: (context, index) {
                          final insp = currentDisplayList[index];
                          return _buildCaseRecordCard(insp, isDark);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String count,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedTab == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        showCheckmark: false,
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF0F766E),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        ),
        onSelected: (val) {
          if (val) setState(() => _selectedTab = index);
        },
      ),
    );
  }

  Widget _buildCaseRecordCard(InspectionModel insp, bool isDark) {
    final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName);
    final formattedId = _formatCaseId(insp.complaintId.isNotEmpty ? insp.complaintId : insp.id);
    final isCompleted = insp.enforcementStatus == EnforcementStatus.completed;
    final isReady = _isReadyForClosure(insp);

    // Enforcement decree label
    String decreeLabel;
    Color decreeColor;
    if (insp.issuedAction == EnforcementType.closure) {
      decreeLabel = insp.fineAmount > 0
          ? 'CLOSURE (RM ${insp.fineAmount.toStringAsFixed(2)})'
          : 'CLOSURE (Order)';
      decreeColor = const Color(0xFFDC2626);
    } else if (insp.issuedAction == EnforcementType.fine || insp.fineAmount > 0) {
      decreeLabel = 'COMPOUND (RM ${insp.fineAmount.toStringAsFixed(2)})';
      decreeColor = const Color(0xFFD97706);
    } else if (insp.issuedAction == EnforcementType.warning) {
      decreeLabel = 'FORM 32 WARNING';
      decreeColor = const Color(0xFF0284C7);
    } else {
      decreeLabel = 'STATUTORY DIRECTIVE';
      decreeColor = const Color(0xFF0F766E);
    }

    final bool isFinePaid = insp.fineAmount <= 0 ||
        (RestaurantStoreService.isOutletFinePaid(
          insp.restaurantId,
          restaurantName: insp.restaurantName,
          complaintId: insp.complaintId,
          inspectionId: insp.id,
        ) || (insp.isFinePaid && insp.enforcementStatus == EnforcementStatus.completed));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady
              ? const Color(0xFF059669).withValues(alpha: isDark ? 0.4 : 0.6)
              : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
          width: isReady ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isReady
                ? const Color(0xFF059669).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
              AppRoutes.closeCaseDetail,
              arguments: insp,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row: Case ID, Decree Pill, Status Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C2340),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formattedId,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: decreeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: decreeColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          decreeLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: decreeColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : (isReady
                                ? const Color(0xFF059669).withValues(alpha: 0.12)
                                : const Color(0xFFD97706).withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCompleted
                                ? Icons.check_circle_rounded
                                : (isReady ? Icons.task_alt_rounded : Icons.hourglass_empty_rounded),
                            size: 13,
                            color: isCompleted
                                ? const Color(0xFF10B981)
                                : (isReady ? const Color(0xFF059669) : const Color(0xFFD97706)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCompleted ? 'Resolved' : (isReady ? 'Ready to Close' : 'In Progress'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCompleted
                                  ? const Color(0xFF10B981)
                                  : (isReady ? const Color(0xFF059669) : const Color(0xFFD97706)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Restaurant Name
                Text(
                  restName,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0C2340),
                  ),
                ),
                const SizedBox(height: 6),

                // Statutory Citation & Officer Info
                Text(
                  insp.statutoryCitation ?? 'Food Act 1983 - Section 11 (Statutory Enforcement)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                // Mini Case Closure Checklist Badges
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildMiniBadge('Improvement Done', true, isDark),
                    _buildMiniBadge('Report Approved', true, isDark),
                    _buildMiniBadge('Action Issued', true, isDark),
                    _buildMiniBadge(
                      isFinePaid ? 'Fine Paid (Cleared)' : 'Fine Pending',
                      isFinePaid,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Bottom Action Row
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 12.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          'Issued: ${_formatDate(insp.issuedDate ?? insp.conductedDate)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? (isDark ? const Color(0xFF222222) : const Color(0xFFF1F5F9))
                            : const Color(0xFF0F766E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isCompleted ? 'View Closed Summary' : (isReady ? 'Review & Close Case' : 'View Requirements'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isCompleted
                                  ? (isDark ? Colors.white70 : const Color(0xFF475569))
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: isCompleted
                                ? (isDark ? Colors.white70 : const Color(0xFF475569))
                                : Colors.white,
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
      ),
    );
  }

  Widget _buildMiniBadge(String label, bool isPassed, bool isDark) {
    final color = isPassed ? const Color(0xFF059669) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPassed ? Icons.check_circle_rounded : Icons.pending_rounded,
            size: 10.5,
            color: color,
          ),
          const SizedBox(width: 3.5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
