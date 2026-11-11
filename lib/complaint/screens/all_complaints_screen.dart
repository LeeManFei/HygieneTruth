import 'package:flutter/material.dart';
import '../../core/widgets/admin_list_filters.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/models/complaint_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/status_badge.dart';

class AllComplaintsScreen extends StatefulWidget {
  const AllComplaintsScreen({super.key});

  @override
  State<AllComplaintsScreen> createState() => _AllComplaintsScreenState();
}

class _AllComplaintsScreenState extends State<AllComplaintsScreen> {
  final TextEditingController _filterSearch = TextEditingController();
  int _dateDays = 0;
  String _sortOrder = 'Oldest first';
  String _group = 'All';

  String _selectedStatus = 'Submitted';
  String _selectedType = 'All Types';

  final List<String> _statusFilters = [
    'Submitted',
    'Under Review',
    'Officer Assigned',
    'Resolved',
    'All Reports',
  ];

  final List<Map<String, dynamic>> _typeFilters = [
    {'name': 'All Types', 'icon': Icons.all_inbox_rounded},
    {'name': 'Food Safety & Poisoning', 'icon': Icons.sick_rounded},
    {'name': 'Pest Infestation', 'icon': Icons.pest_control_rounded},
    {'name': 'Unclean Utensils', 'icon': Icons.flatware_rounded},
    {'name': 'Staff Hygiene', 'icon': Icons.clean_hands_rounded},
    {'name': 'Staff Conduct', 'icon': Icons.record_voice_over_rounded},
    {'name': 'Waste & Drainage', 'icon': Icons.delete_sweep_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  @override
  void dispose() { _filterSearch.dispose(); super.dispose(); }

  Future<void> _loadComplaints() async {
    await ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
    if (mounted) {
      setState(() {});
    }
  }

  String _formatReportId(String rawId) {
    if (rawId.isEmpty) return 'CMP-0000';
    if (rawId.toUpperCase().startsWith('CMP-')) {
      return rawId.toUpperCase();
    }
    final clean = rawId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final short = clean.length > 6 ? clean.substring(0, 6).toUpperCase() : clean.toUpperCase();
    return 'CMP-$short';
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final month = months[dt.month - 1];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day.toString().padLeft(2, '0')} $month ${dt.year}, $hour:$min $period';
    } catch (_) {
      if (raw.contains('T')) {
        return raw.split('T').first;
      }
      return raw;
    }
  }

  bool _matchesStatus(ComplaintModel c, String statusFilter) {
    switch (statusFilter) {
      case 'Submitted':
      case 'New Submissions':
      case 'New Action':
        return c.status == ComplaintStatus.submitted;
      case 'Under Review':
      case 'In Review':
      case 'Pending Review':
      case 'Pending Action':
        return c.status == ComplaintStatus.underReview;
      case 'Officer Assigned':
      case 'With Officer':
      case 'Investigating':
        return c.status == ComplaintStatus.investigating ||
            c.status == ComplaintStatus.inspecting ||
            c.status == ComplaintStatus.pendingInspection;
      case 'Resolved':
      case 'Actioned':
        return c.status == ComplaintStatus.resolved ||
            c.status == ComplaintStatus.rejected;
      case 'All Reports':
      case 'All Status':
      case 'All':
      default:
        return true;
    }
  }

  bool _matchesType(ComplaintModel c, String typeFilter) {
    if (typeFilter == 'All Types') return true;
    final cat = c.category.toLowerCase();
    switch (typeFilter) {
      case 'Food Safety & Poisoning':
        return cat.contains('food') || cat.contains('poison');
      case 'Pest Infestation':
        return cat.contains('pest') || cat.contains('cockroach') || cat.contains('rat');
      case 'Unclean Utensils':
        return cat.contains('utensil') || cat.contains('cutlery') || cat.contains('plate');
      case 'Staff Hygiene':
        return cat.contains('staff hygiene') || (cat.contains('hygiene') && !cat.contains('food'));
      case 'Staff Conduct':
        return cat.contains('rude') || cat.contains('conduct') || cat.contains('service') || cat.contains('employee');
      case 'Waste & Drainage':
        return cat.contains('waste') || cat.contains('drainage') || cat.contains('grease');
      default:
        return true;
    }
  }

  bool _isFoodComplaint(String cat) {
    final c = cat.toLowerCase();
    return c.contains('food') || c.contains('poison');
  }

  bool _isPestComplaint(String cat) {
    final c = cat.toLowerCase();
    return c.contains('pest') || c.contains('cockroach') || c.contains('rat');
  }

  bool _isStaffConductComplaint(String cat) {
    final c = cat.toLowerCase();
    return c.contains('rude') || cat.contains('conduct') || cat.contains('service') || cat.contains('employee');
  }

  int _getStatusCount(String statusFilter) {
    final list = ComplaintStoreService.complaintsNotifier.value.isNotEmpty
        ? ComplaintStoreService.complaintsNotifier.value
        : RestaurantStoreService.complaintsNotifier.value;
    if (statusFilter == 'All Reports' || statusFilter == 'All Status' || statusFilter == 'All') return list.length;
    return list.where((c) => _matchesStatus(c, statusFilter)).length;
  }

  int _getTypeCount(String typeFilter) {
    final list = ComplaintStoreService.complaintsNotifier.value.isNotEmpty
        ? ComplaintStoreService.complaintsNotifier.value
        : RestaurantStoreService.complaintsNotifier.value;
    if (typeFilter == 'All Types') return list.length;
    return list.where((c) => _matchesType(c, typeFilter)).length;
  }

  List<ComplaintModel> _getSortedComplaints() {
    final baseList = ComplaintStoreService.complaintsNotifier.value.isNotEmpty
        ? ComplaintStoreService.complaintsNotifier.value
        : RestaurantStoreService.complaintsNotifier.value;
    List<ComplaintModel> list = baseList
        .where((c) => _matchesStatus(c, _selectedStatus) && _matchesType(c, _selectedType))
        .toList();

    final q = _filterSearch.text.trim().toLowerCase();
    list = list.where((c) => GovernmentRecordDate.matches(c.submittedAt, _dateDays) && ('${c.restaurantName} ${c.id} ${_formatReportId(c.id)} ${c.userName} ${c.category}'.toLowerCase().contains(q))).toList();
    list.sort((a,b) => GovernmentRecordDate.compare(a.submittedAt, b.submittedAt, _sortOrder == 'Oldest first'));

    return list;
  }

  Color _getSeverityColor(SeverityLevel level) {
    switch (level) {
      case SeverityLevel.high:
        return const Color(0xFFDC2626);
      case SeverityLevel.medium:
        return const Color(0xFFD97706);
      case SeverityLevel.low:
        return const Color(0xFF16A34A);
    }
  }

  Widget _buildSummaryMetric(
    String title,
    String count,
    IconData icon,
    Color color,
    bool isDark, {
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: isDark ? 0.22 : 0.16)
                  : color.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: isDark ? 0.25 : 0.2),
                width: isSelected ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        count,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedList = _getSortedComplaints();

    final submittedCount = _getStatusCount('Submitted');
    final underReviewCount = _getStatusCount('Under Review');
    final investigatingCount = _getStatusCount('Officer Assigned');
    final resolvedCount = _getStatusCount('Resolved');

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Incoming Reports',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Reports',
            onPressed: () => _loadComplaints(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
          // 1. TOP TRIAGE SUMMARY STATS (2x2 Grid - 2 columns per row)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildSummaryMetric(
                      'Submitted',
                      '$submittedCount',
                      Icons.inbox_rounded,
                      const Color(0xFFEA580C),
                      isDark,
                      isSelected: _selectedStatus == 'Submitted',
                      onTap: () => setState(() => _selectedStatus = 'Submitted'),
                    ),
                    const SizedBox(width: 10),
                    _buildSummaryMetric(
                      'Under Review',
                      '$underReviewCount',
                      Icons.rate_review_rounded,
                      const Color(0xFFD97706),
                      isDark,
                      isSelected: _selectedStatus == 'Under Review',
                      onTap: () => setState(() => _selectedStatus = 'Under Review'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSummaryMetric(
                      'With Officer',
                      '$investigatingCount',
                      Icons.assignment_ind_rounded,
                      const Color(0xFF0284C7),
                      isDark,
                      isSelected: _selectedStatus == 'Officer Assigned',
                      onTap: () => setState(() => _selectedStatus = 'Officer Assigned'),
                    ),
                    const SizedBox(width: 10),
                    _buildSummaryMetric(
                      'Actioned',
                      '$resolvedCount',
                      Icons.check_circle_rounded,
                      const Color(0xFF059669),
                      isDark,
                      isSelected: _selectedStatus == 'Resolved',
                      onTap: () => setState(() => _selectedStatus = 'Resolved'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. DUAL FILTER BARS
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // STATUS FILTER ROW
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _statusFilters.map((st) {
                        final isSelected = _selectedStatus == st;
                        final count = _getStatusCount(st);

                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            showCheckmark: false,
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) setState(() => _selectedStatus = st);
                            },
                            selectedColor: const Color(0xFF0F766E),
                            backgroundColor: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  st,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.white.withValues(alpha: 0.25) : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // CATEGORY / ISSUE TYPE FILTER ROW
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _typeFilters.map((item) {
                        final typeName = item['name'] as String;
                        final typeIcon = item['icon'] as IconData;
                        final isSelected = _selectedType == typeName;
                        final count = _getTypeCount(typeName);

                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            showCheckmark: false,
                            selected: isSelected,
                            onSelected: (val) {
                              setState(() => _selectedType = typeName);
                            },
                            selectedColor: const Color(0xFF0D9488).withValues(alpha: 0.18),
                            backgroundColor: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF0D9488) : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                              width: isSelected ? 1.4 : 1,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            avatar: Icon(
                              typeIcon,
                              size: 14,
                              color: isSelected ? const Color(0xFF0D9488) : (isDark ? Colors.white60 : Colors.grey.shade600),
                            ),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  typeName,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF0D9488) : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '($count)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? const Color(0xFF0D9488) : (isDark ? Colors.white38 : Colors.grey.shade500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. COMPLAINT LIST CARDS
AdminListFilters(search: _filterSearch, hint: 'Search outlet, report ID, reporter or category', guidance: 'Review the oldest submitted reports first; search combines with status and category.', dateLabel: 'Reported', count: sortedList.length, days: _dateDays, sort: _sortOrder, groups: const [], group: _group, onGroup: (v) => setState(() => _group = v), onSort: (v) => setState(() => _sortOrder = v), onDays: (v) => setState(() => _dateDays = v), onSearch: () => setState(() {})),
          Expanded(
            child: sortedList.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Reports Found',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.navyColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectedStatus == 'All' && _selectedType == 'All Types'
                                ? 'No incoming customer hygiene reports currently recorded.'
                                : 'No reports found matching "$_selectedType" under "$_selectedStatus".',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          if (_selectedStatus != 'All' || _selectedType != 'All Types') ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedStatus = 'All';
                                  _selectedType = 'All Types';
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.clear_all_rounded, size: 16),
                              label: const Text('Reset All Filters'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: sortedList.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final c = sortedList[index];
                      final sevColor = _getSeverityColor(c.severity);
                      final isFood = _isFoodComplaint(c.category);
                      final isPest = _isPestComplaint(c.category);
                      final isStaffConduct = _isStaffConductComplaint(c.category);
                      final formattedReportId = _formatReportId(c.id);
                      final formattedTime = _formatTimestamp(c.submittedAt);

                      return Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: c.isFlaggedForReview
                                ? Colors.red.shade300
                                : (isFood || isPest
                                    ? (isDark ? const Color(0xFFE11D48).withValues(alpha: 0.3) : const Color(0xFFFECDD3))
                                    : (isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
                            width: (c.isFlaggedForReview || isFood || isPest) ? 1.3 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isFood || isPest
                                  ? const Color(0xFFE11D48).withValues(alpha: isDark ? 0.12 : 0.04)
                                  : Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await Navigator.pushNamed(
                                context,
                                AppRoutes.complaintReviewDetail,
                                arguments: c,
                              );
                              if (mounted) {
                                await _loadComplaints();
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Flagged Header Banner if applicable
                                if (c.isFlaggedForReview && c.flaggedReason != null)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                                      border: Border(bottom: BorderSide(color: Colors.red.shade100)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.flag_rounded, color: Colors.red.shade700, size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'FLAGGED: ${c.flaggedReason}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.red.shade800,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Card Content Body
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Restaurant Name + ID Pill
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              c.restaurantName,
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : const Color(0xFF0C2340),
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                                            ),
                                            child: Text(
                                              formattedReportId,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Category + KKM Priority Badges Row
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          // Main Category Badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                            decoration: BoxDecoration(
                                              color: isFood
                                                  ? const Color(0xFFE11D48).withValues(alpha: 0.1)
                                                  : (isPest
                                                      ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                                                      : (isStaffConduct
                                                          ? const Color(0xFFEA580C).withValues(alpha: 0.1)
                                                          : const Color(0xFF0F766E).withValues(alpha: 0.08))),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isFood
                                                      ? Icons.sick_rounded
                                                      : (isPest
                                                          ? Icons.pest_control_rounded
                                                          : (isStaffConduct
                                                              ? Icons.record_voice_over_rounded
                                                              : Icons.report_problem_rounded)),
                                                  size: 13,
                                                  color: isFood
                                                      ? const Color(0xFFE11D48)
                                                      : (isPest
                                                          ? const Color(0xFFDC2626)
                                                          : (isStaffConduct
                                                              ? const Color(0xFFEA580C)
                                                              : const Color(0xFF0F766E))),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  c.category,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isFood
                                                        ? const Color(0xFFE11D48)
                                                        : (isPest
                                                            ? const Color(0xFFDC2626)
                                                            : (isStaffConduct
                                                                ? const Color(0xFFEA580C)
                                                                : const Color(0xFF0F766E))),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // KKM Priority Classification Pill
                                          if (isFood)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFFECDD3)),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFDC2626)),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'KKM Food Safety Priority',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFBE123C),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else if (isPest)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFFECDD3)),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.pest_control_rounded, size: 12, color: Color(0xFFDC2626)),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'KKM Cleanliness Priority',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFDC2626),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else if (isStaffConduct)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFF7ED),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFFFEDD5)),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFFEA580C)),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Staff Conduct (Secondary)',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFC2410C),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // Severity Level Pill
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                            decoration: BoxDecoration(
                                              color: sevColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${c.severity.name.toUpperCase()} SEVERITY',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: sevColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Reported Issues Snippet / Preview
                                      if (c.issues.isNotEmpty) ...[
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: c.issues.take(3).map((iss) {
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                '• $iss',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                        const SizedBox(height: 8),
                                      ],

                                      // Reporter and Timestamp
                                      Row(
                                        children: [
                                          Icon(Icons.person_outline_rounded, size: 13, color: Colors.grey.shade500),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'User: ${c.userName}',
                                              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                                          const SizedBox(width: 4),
                                          Text(
                                            formattedTime,
                                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Status Badge + Action Button
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          StatusBadge.fromStatus(c.status.name),
                                          const SizedBox(width: 8),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                (c.status == ComplaintStatus.submitted ||
                                                        c.status == ComplaintStatus.underReview)
                                                    ? 'Assign Officer'
                                                    : 'Review Details',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0F766E),
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                size: 18,
                                                color: Color(0xFF0F766E),
                                              ),
                                            ],
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
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
