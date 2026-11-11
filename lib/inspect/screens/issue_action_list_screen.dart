import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/custom_app_bar.dart';

class IssueActionListScreen extends StatefulWidget {
  const IssueActionListScreen({super.key});

  @override
  State<IssueActionListScreen> createState() => _IssueActionListScreenState();
}

class _IssueActionListScreenState extends State<IssueActionListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _selectedTab = 0; // 0: Pending Penalty Queue, 1: All Action Records

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await Future.wait([
        RestaurantStoreService.fetchInspections(),
        ComplaintStoreService.fetchAllComplaints(forceRefresh: true),
      ]);
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
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

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return 'Recent Audit';
    try {
      final dt = DateTime.parse(rawDate);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return rawDate;
    }
  }

  bool _isPendingEnforcement(InspectionModel insp) {
    // An inspection is pending enforcement only if on-site visit was conducted, non-compliant, and decree has NOT yet been issued
    if (insp.outcome != InspectionOutcome.nonCompliant) return false;
    if (insp.conductedDate == null || insp.conductedDate!.isEmpty || insp.conductedDate == 'null') return false;

    final hasNoIssuedDate = insp.issuedDate == null || insp.issuedDate!.isEmpty || insp.issuedDate == 'null';
    final isNoneAction = insp.issuedAction == EnforcementType.none;
    final isPendingStatus = insp.enforcementStatus == EnforcementStatus.pending;
    final isClosed = RestaurantStoreService.isCaseClosed(
      inspectionId: insp.id,
      complaintId: insp.complaintId,
    );
    if (isClosed) return false;
    return (hasNoIssuedDate || isNoneAction || isPendingStatus);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Issue Enforcement Action',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Queue',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 22),
            tooltip: 'View Action History',
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

          // Only include inspections where an on-site visit was actually conducted
          final List<InspectionModel> conductedInspections = allInspections.where((insp) {
            return insp.outcome != InspectionOutcome.pending &&
                insp.conductedDate != null &&
                insp.conductedDate!.isNotEmpty &&
                insp.conductedDate != 'null';
          }).toList();

          // Separate pending requests from already issued decrees
          final pendingRequests = conductedInspections.where((insp) => _isPendingEnforcement(insp)).toList();
          final decreedActions = conductedInspections.where((insp) => !_isPendingEnforcement(insp)).toList();

          final currentDisplayList = (_selectedTab == 0 ? pendingRequests : conductedInspections).where((insp) {
            if (query.isNotEmpty) {
              final rName = insp.restaurantName.toLowerCase();
              final cId = insp.complaintId.toLowerCase();
              final iId = insp.id.toLowerCase();
              if (!rName.contains(query) && !cId.contains(query) && !iId.contains(query)) {
                return false;
              }
            }
            return true;
          }).toList();
          currentDisplayList.sort(CaseOrdering.inspections);

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
                              label: 'Pending Decrees',
                              count: '${pendingRequests.length}',
                              color: const Color(0xFFDC2626),
                              icon: Icons.hourglass_top_rounded,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Decrees Issued',
                              count: '${decreedActions.length}',
                              color: const Color(0xFF0F766E),
                              icon: Icons.gavel_rounded,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.pushNamed(context, AppRoutes.enforcementHistory),
                              child: _buildMetricTile(
                                label: 'Action History →',
                                count: 'View',
                                color: const Color(0xFFD97706),
                                icon: Icons.history_rounded,
                                isDark: isDark,
                              ),
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
                        hintText: 'Search pending requests by restaurant or ID...',
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
                    _buildFilterChip(0, 'Pending Actions (${pendingRequests.length})'),
                    _buildFilterChip(1, 'All Inspections (${allInspections.length})'),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 1),

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
                                _selectedTab == 0 ? 'All Penalty Requests Cleared 🎉' : 'No Submitted Audits Found',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0C2340),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _selectedTab == 0
                                    ? 'No inspection visits are currently pending enforcement decrees. All penalties have been issued and moved to Action History.'
                                    : 'Submit a physical inspection report via "Record Visit" to issue penalties and decrees here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, AppRoutes.enforcementHistory);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.history_rounded, size: 16),
                                label: const Text('View Action History'),
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
                          return _buildComplianceRecordCard(insp, isDark);
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

  Future<void> _showAdminVerificationDialog(bool isDark) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.lock_clock_rounded, color: Color(0xFFD97706), size: 23),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Admin Verification Required',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'The inspection report is awaiting Government Admin review. Action issuance stays locked until the report is approved.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComplianceRecordCard(InspectionModel insp, bool isDark) {
    final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName);
    final formattedId = _formatCaseId(insp.complaintId.isNotEmpty ? insp.complaintId : insp.id);
    final isNonCompliant = insp.outcome == InspectionOutcome.nonCompliant;
    final isPending = _isPendingEnforcement(insp);

    Color badgeColor;
    String outcomeLabel;
    IconData outcomeIcon;

    if (isNonCompliant) {
      badgeColor = const Color(0xFFDC2626);
      outcomeLabel = 'Non-Compliant (Violations)';
      outcomeIcon = Icons.warning_amber_rounded;
    } else {
      badgeColor = const Color(0xFF059669);
      outcomeLabel = 'Compliant (Pass Grade A/B)';
      outcomeIcon = Icons.check_circle_rounded;
    }

    final bool isAdminApproved = insp.isAdminApproved ||
        RestaurantStoreService.isAdminInspectionApproved(
          insp.id,
          complaintId: insp.complaintId,
          restaurantId: insp.restaurantId,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? (isAdminApproved ? const Color(0xFFDC2626).withValues(alpha: 0.3) : const Color(0xFFD97706).withValues(alpha: 0.3))
              : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
          width: isPending ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
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
            if (isPending && !isAdminApproved) {
              _showAdminVerificationDialog(isDark);
              return;
            }
            Navigator.pushNamed(
              context,
              AppRoutes.issueEnforcementDetail,
              arguments: insp,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Case ID & Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formattedId,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: isDark ? Colors.white54 : Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(insp.conductedDate ?? insp.scheduledDate),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Restaurant Name & Officer
                Text(
                  restName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0C2340),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Inspected by: ${insp.officerName.isNotEmpty ? insp.officerName : "Health Inspector (KKM)"}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 10),

                // Compliance Outcome Status Pill
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(outcomeIcon, size: 12, color: badgeColor),
                          const SizedBox(width: 4),
                          Text(
                            outcomeLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isPending) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isAdminApproved
                              ? const Color(0xFF059669).withValues(alpha: 0.12)
                              : const Color(0xFFD97706).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAdminApproved
                                ? const Color(0xFF059669).withValues(alpha: 0.3)
                                : const Color(0xFFD97706).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAdminApproved ? Icons.verified_user_rounded : Icons.hourglass_top_rounded,
                              size: 11,
                              color: isAdminApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 3.5),
                            Text(
                              isAdminApproved ? 'ADMIN APPROVED • READY' : 'AWAITING ADMIN REVIEW',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isAdminApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'ACTION ISSUED: ${insp.issuedAction.name.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Inspector Findings
                if (insp.findings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'Findings: ${insp.findings}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Dynamic Status & Recommendation Box
                if (isPending && !isAdminApproved) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282828) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFFCD34D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock_rounded, size: 16, color: Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Action Locked • Awaiting Admin Approval',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Admin must review & approve inspection report before fine and action notice can be issued.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? Colors.white60 : Colors.brown.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (isPending && isAdminApproved) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.2) : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gavel_rounded, size: 16, color: Color(0xFF059669)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin Approved • Ready to Issue Action',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap below to select action type (Fine/Closure/Warning), fine amount, and legal clause.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? Colors.white60 : const Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Action Issued: ${insp.issuedAction.name.toUpperCase()} (Fine: RM ${insp.fineAmount.toStringAsFixed(2)})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // CTA Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isPending && !isAdminApproved) {
                        _showAdminVerificationDialog(isDark);
                        return;
                      }
                      Navigator.pushNamed(
                        context,
                        AppRoutes.issueEnforcementDetail,
                        arguments: insp,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (isPending && !isAdminApproved)
                          ? (isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E))
                          : (isPending ? const Color(0xFFDC2626) : const Color(0xFF0F766E)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: Icon(
                      (isPending && !isAdminApproved)
                          ? Icons.lock_clock_rounded
                          : (isPending ? Icons.gavel_rounded : Icons.visibility_rounded),
                      size: 15,
                    ),
                    label: Text(
                      (isPending && !isAdminApproved)
                          ? 'Awaiting Admin Approval (Locked)'
                          : (isPending ? 'Issue Action & Notice →' : 'View Action Notice'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
