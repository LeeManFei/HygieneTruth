import '../../core/widgets/app_search_field.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/audit_log_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';

class GovernmentAuditLogScreen extends StatefulWidget {
  const GovernmentAuditLogScreen({super.key});

  @override
  State<GovernmentAuditLogScreen> createState() => _GovernmentAuditLogScreenState();
}

class _GovernmentAuditLogScreenState extends State<GovernmentAuditLogScreen> {
  int _dateDays = 0;
  String _sortOrder = 'Newest first';
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _realtimeChannel;
  List<AuditLogModel> _allLogs = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _displayedCount = 6;
  final int _pageSize = 6;

  final List<String> _categories = [
    'All',
    'Admin Assigned',
    'Field Visits',
    'Enforcement',
    'Case Closures',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _setupRealtime();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = SupabaseService.client
          .channel('public:audit:gov_sync')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'complaints',
            callback: (payload) async {
              if (kDebugMode) print('⚡ Realtime Complaint update received for Gov Audit: ${payload.eventType}');
              final fresh = await AuditLogService.fetchGovernmentAuditLogs();
              if (mounted) {
                setState(() => _allLogs = fresh);
              }
            },
          )
          .subscribe();
    } catch (e) {
      if (kDebugMode) print('Realtime channel error: $e');
    }
  }

  Future<void> _loadLogs({bool isRefresh = false}) async {
    if (!isRefresh && _allLogs.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final fetched = await AuditLogService.fetchGovernmentAuditLogs();
      if (mounted) {
        setState(() {
          _allLogs = fetched;
          _displayedCount = _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading gov audit logs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150 &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMoreLogs();
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
    final filtered = _allLogs.where((log) {
      if (!GovernmentRecordDate.matches(log.timestamp.toIso8601String(), _dateDays)) return false;
      final act = log.actionType.toUpperCase();
      final cat = log.category.toLowerCase();
      final title = log.title.toLowerCase();
      final desc = log.description.toLowerCase();

      if (_selectedCategory != 'All') {
        if (_selectedCategory == 'Admin Assigned' && !act.contains('ASSIGN') && !title.contains('assign')) {
          return false;
        }
        if (_selectedCategory == 'Field Visits' && !act.contains('INSPECT') && !title.contains('inspect') && !title.contains('visit')) {
          return false;
        }
        if (_selectedCategory == 'Enforcement' && !act.contains('ENFORCE') && !title.contains('enforce') && !title.contains('closure') && !title.contains('fine')) {
          return false;
        }
        if (_selectedCategory == 'Case Closures' && !act.contains('CASE_CLOSED') && !title.contains('closed') && !title.contains('archive')) {
          return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return title.contains(q) || desc.contains(q) || cat.contains(q) || log.userEmail.toLowerCase().contains(q);
      }

      return true;
    }).toList();
    filtered.sort((a, b) => _sortOrder == 'Oldest first' ? CaseOrdering.auditLogs(b, a) : CaseOrdering.auditLogs(a, b));
    return filtered;
  }

  String _formatTimestamp(DateTime dt) => GovernmentRecordDate.format(dt.toIso8601String());

  Map<String, dynamic> _getLogVisuals(AuditLogModel log) {
    final act = log.actionType.toUpperCase();
    final title = log.title.toLowerCase();

    if (act.contains('ASSIGN') || title.contains('assign')) {
      return {
        'icon': Icons.move_to_inbox_rounded,
        'color': const Color(0xFF0284C7),
        'bg': const Color(0xFFE0F2FE),
        'tag': 'Incoming Admin Assigned',
      };
    } else if (act.contains('ENFORCE') || title.contains('closure') || title.contains('fine')) {
      return {
        'icon': Icons.gavel_rounded,
        'color': const Color(0xFFDC2626),
        'bg': const Color(0xFFFEE2E2),
        'tag': 'Enforcement Decree',
      };
    } else if (act.contains('CASE_CLOSED') || title.contains('closed')) {
      return {
        'icon': Icons.verified_user_rounded,
        'color': const Color(0xFF059669),
        'bg': const Color(0xFFD1FAE5),
        'tag': 'Case Closed & Archive',
      };
    } else if (title.contains('scheduled') || act.contains('SCHEDULED')) {
      return {
        'icon': Icons.event_available_rounded,
        'color': const Color(0xFFD97706),
        'bg': const Color(0xFFFEF3C7),
        'tag': 'Inspection Scheduled',
      };
    } else {
      return {
        'icon': Icons.fact_check_rounded,
        'color': const Color(0xFF0F766E),
        'bg': const Color(0xFFCCFBF1),
        'tag': 'Field Inspection',
      };
    }
  }

  void _showDetailDialog(BuildContext context, AuditLogModel log) {
    final visuals = _getLogVisuals(log);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color themeColor = visuals['color'] as Color;
    final Color themeBg = visuals['bg'] as Color;
    final String tag = visuals['tag'] as String;
    final IconData icon = visuals['icon'] as IconData;

    final shortId = log.id.length > 8 ? log.id.substring(0, 8).toUpperCase() : log.id.toUpperCase();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. TOP HEADER BANNER
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? themeColor.withValues(alpha: 0.15) : themeBg.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    bottom: BorderSide(
                      color: themeColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: themeColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: themeColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Government Audit Record',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: themeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                      onPressed: () => Navigator.pop(ctx),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),

              // 2. BODY CONTENT
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Title
                    Text(
                      log.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF0C2340),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Description / Notes Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141414) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        log.description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Key-Value Grid
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            Icons.category_outlined,
                            'Category',
                            log.category.isNotEmpty ? log.category : 'Government',
                            isDark,
                          ),
                          const Divider(height: 14),
                          _buildDetailRow(
                            Icons.access_time_rounded,
                            'Timestamp',
                            _formatTimestamp(log.timestamp),
                            isDark,
                          ),
                          const Divider(height: 14),
                          _buildDetailRow(
                            Icons.person_outline_rounded,
                            'Initiator Officer',
                            log.userEmail.isNotEmpty ? log.userEmail : 'System Admin',
                            isDark,
                          ),
                          const Divider(height: 14),
                          _buildRecordIdRow(
                            'AUD-$shortId',
                            log.id,
                            isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Close Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Dismiss Record',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white60 : const Color(0xFF64748B),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordIdRow(String shortId, String fullId, bool isDark) {
    return Builder(
      builder: (context) {
        return Row(
          children: [
            Icon(Icons.fingerprint_rounded, size: 16, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Text(
              'Record ID',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shortId,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: fullId));
                      HygieneFeedback.showSuccess(context, 'Record ID copied to clipboard');
                    },
                    child: Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allLogs = _allLogs;
    final filtered = _getFilteredLogs();
    final paginated = filtered.take(_displayedCount).toList();

    final adminAssignedCount = allLogs.where((l) {
      final act = l.actionType.toUpperCase();
      final t = l.title.toLowerCase();
      return act.contains('ASSIGN') || t.contains('assign');
    }).length;

    final enforcementCount = allLogs.where((l) {
      final act = l.actionType.toUpperCase();
      final t = l.title.toLowerCase();
      return act.contains('ENFORCE') || t.contains('closure') || t.contains('fine');
    }).length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Government Audit Log',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Live Refresh',
            onPressed: () => _loadLogs(isRefresh: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const ActionHistorySkeleton()
            : RefreshIndicator(
              onRefresh: () => _loadLogs(isRefresh: true),
              color: const Color(0xFF0F766E),
              child: Column(
                children: [
                  // 1. TOP SUMMARY METRICS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        _buildStatPill('Total Logs', '${allLogs.length}', const Color(0xFF0F766E), isDark),
                        const SizedBox(width: 8),
                        _buildStatPill('Admin Assigned', '$adminAssignedCount', const Color(0xFF0284C7), isDark),
                        const SizedBox(width: 8),
                        _buildStatPill('Enforcements', '$enforcementCount', const Color(0xFFDC2626), isDark),
                      ],
                    ),
                  ),

                  // 2. SEARCH BAR
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: AppSearchField(suggestions: _allLogs.map((l) => l.title).toList(),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim();
                          _displayedCount = _pageSize;
                        });
                      },
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search audit trail by outlet, case ID, officer...',
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

                  // 3. CATEGORY FILTER CHIPS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = (_selectedCategory == cat);
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

                  // 4. TIMELINE AUDIT LIST WITH INFINITE SCROLL
                  GovernmentListTools(guidance: 'Activity history • Open a record for details; start new work in Assigned Cases.', dateLabel: 'Event',
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

                              final log = paginated[index];
                              final visuals = _getLogVisuals(log);
                              final IconData icon = visuals['icon'] as IconData;
                              final Color iconColor = visuals['color'] as Color;
                              final Color iconBg = visuals['bg'] as Color;
                              final String tag = visuals['tag'] as String;

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
                                    onTap: () => _showDetailDialog(context, log),
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
                                            child: Icon(icon, color: iconColor, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(log.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                Text(_formatTimestamp(log.timestamp), style: const TextStyle(fontSize: 12)),
                                                const SizedBox(height: 4),
                                                Text(
                                                  log.description,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                                    height: 1.35,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        tag,
                                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      'Officer: ${log.userEmail.split("@").first}',
                                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
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
            'Loading more audit logs...',
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
              child: Icon(Icons.assignment_turned_in_outlined, size: 40, color: isDark ? Colors.white38 : Colors.grey.shade400),
            ),
            const SizedBox(height: 14),
            Text(
              'No Government Audit Logs Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : const Color(0xFF0C2340)),
            ),
            const SizedBox(height: 6),
            Text(
              'All health inspections, incoming admin assigned complaints, and enforcement actions will be logged here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.grey.shade600, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
