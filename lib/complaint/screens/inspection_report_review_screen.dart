import '../../core/widgets/app_search_field.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/widgets/admin_list_filters.dart';
import '../../core/widgets/government_list_tools.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/rectification_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/workflow_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/theme/app_theme.dart';
import '../../notifications/models/notification_model.dart';

class InspectionReportReviewScreen extends StatefulWidget {
  const InspectionReportReviewScreen({super.key});

  @override
  State<InspectionReportReviewScreen> createState() => _InspectionReportReviewScreenState();
}

class _InspectionReportReviewScreenState extends State<InspectionReportReviewScreen> {
  int _dateDays = 0;
  String _sortOrder = 'Oldest first';
  String _group = 'All';

  bool _isProcessing = false;
  bool _isLoading = false;
  InspectionModel? _selectedInspection;
  int _selectedTab = 0; // 0: Pending Review, 1: Endorsed / Approved, 2: All Reports
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRealData();
    RestaurantStoreService.inspectionsNotifier.addListener(_onDataUpdated);
    ComplaintStoreService.complaintsNotifier.addListener(_onDataUpdated);
  }

  @override
  void dispose() {
    RestaurantStoreService.inspectionsNotifier.removeListener(_onDataUpdated);
    ComplaintStoreService.complaintsNotifier.removeListener(_onDataUpdated);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDataUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRealData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await Future.wait([
        RestaurantStoreService.fetchInspections(),
        ComplaintStoreService.fetchAllComplaints(forceRefresh: true),
        RestaurantStoreService.fetchAllRestaurants(),
      ]);
    } catch (e) {
      debugPrint('[InspectionReportReview] Error fetching real inspections: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_') || rawId.startsWith('CMP_')) {
      return rawId.toUpperCase().replaceAll('_', '-');
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  String _formatDate(String? raw) => GovernmentRecordDate.format(raw);

  bool _isVisitRecorded(InspectionModel insp) {
    final hasConductedDate = insp.conductedDate != null &&
        insp.conductedDate!.isNotEmpty &&
        insp.conductedDate != 'null';
    final hasConductedOutcome = insp.outcome != InspectionOutcome.pending;
    return hasConductedDate && hasConductedOutcome;
  }

  bool _isInspectionAdminApproved(InspectionModel insp) {
    return insp.isAdminApproved ||
        RestaurantStoreService.isAdminInspectionApproved(
          insp.id,
          complaintId: insp.complaintId,
          restaurantId: insp.restaurantId,
        );
  }

  ComplaintModel? _findLinkedComplaint(InspectionModel insp) {
    final allComplaints = ComplaintStoreService.complaintsNotifier.value;
    for (final c in allComplaints) {
      if (insp.complaintId.isNotEmpty && c.id.toLowerCase() == insp.complaintId.toLowerCase()) {
        return c;
      }
      if (insp.restaurantId.isNotEmpty && c.restaurantId.toLowerCase() == insp.restaurantId.toLowerCase()) {
        return c;
      }
      if (c.restaurantName.toLowerCase().trim() == insp.restaurantName.toLowerCase().trim()) {
        return c;
      }
    }
    return null;
  }

  RestaurantModel? _findLinkedRestaurant(InspectionModel insp) {
    final allRestaurants = RestaurantStoreService.restaurantsNotifier.value;
    for (final r in allRestaurants) {
      if (insp.restaurantId.isNotEmpty && r.id.toLowerCase() == insp.restaurantId.toLowerCase()) {
        return r;
      }
      if (r.name.toLowerCase().trim() == insp.restaurantName.toLowerCase().trim()) {
        return r;
      }
    }
    return null;
  }

  void _showImagePreview(BuildContext context, String path, {String? tag}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: _buildPhotoWidget(path, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
            if (tag != null)
              Positioned(
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoWidget(String path, {BoxFit fit = BoxFit.cover, double? width, double? height}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (ctx, err, stack) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
        ),
      );
    } else {
      final f = File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
      if (f.existsSync()) {
        return Image.file(
          f,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (ctx, err, stack) => Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
          ),
        );
      }
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
      );
    }
  }

  // ==========================================
  // HIGH-QUALITY VERIFICATION ENDORSEMENT MODAL
  // ==========================================
  Future<void> _approveReport(InspectionModel insp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName);

        String recBadgeLabel = insp.outcome == InspectionOutcome.compliant ? 'COMPLIANT (PASS)' : 'ACTION REQUIRED';
        Color recColor = insp.outcome == InspectionOutcome.compliant ? const Color(0xFF059669) : const Color(0xFFDC2626);
        IconData recIcon = insp.outcome == InspectionOutcome.compliant ? Icons.check_circle_rounded : Icons.warning_amber_rounded;

        if (insp.issuedAction != EnforcementType.none) {
          recBadgeLabel = 'ACTION: ${insp.issuedAction.name.toUpperCase()}';
          recColor = const Color(0xFFDC2626);
          recIcon = Icons.gavel_rounded;
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header Icon + Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.verified_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify & Endorse Audit',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Government Statutory Review',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  'Review and approve this official health inspection report to allow Health Officer to issue the action or notice.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 14),

                // Inspection Report Summary Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      // Target Outlet
                      Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 16, color: isDark ? Colors.tealAccent : const Color(0xFF0F766E)),
                          const SizedBox(width: 8),
                          const Text('Target Outlet:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const Spacer(),
                          Text(
                            restName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),

                      // Outcome Status
                      Row(
                        children: [
                          Icon(recIcon, size: 16, color: recColor),
                          const SizedBox(width: 8),
                          const Text('Outcome Status:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: recColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: recColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              recBadgeLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: recColor),
                            ),
                          ),
                        ],
                      ),

                      if (insp.fineAmount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.price_check_rounded, size: 16, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            const Text('Statutory Compound:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const Spacer(),
                            Text(
                              'RM ${insp.fineAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined, size: 16, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          const Text('Inspecting Officer:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const Spacer(),
                          Text(
                            insp.officerName.isNotEmpty ? insp.officerName : 'Health Inspector (KKM)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Forwarding Note
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0284C7)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Notification will be dispatched to Health Officer (gov_001) to officially issue statutory penalty decree.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF0369A1), height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: const Text(
                          'Confirm & Endorse',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    if (!_isVisitRecorded(insp)) {
      if (mounted) {
        HygieneFeedback.showWarning(
          context,
          'Cannot endorse: The health officer has not recorded the on-site inspection visit yet.',
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final updatedInsp = insp.copyWith(isAdminApproved: true);
      await RestaurantStoreService.saveInspection(updatedInsp, stage: 'approve');

      // 3. Send Notification to Health Officer (gov_001)
      NotificationService.sendNotification(
        userId: 'gov_001',
        title: '✅ Inspection Audit Approved by Admin',
        message: 'Admin verified and endorsed your audit report for ${insp.restaurantName}. You can now determine and issue the statutory enforcement penalty & decree.',
        type: NotificationType.system,
        actionUrl: 'issue_enforcement',
      );

      // 5. Audit Trail
      AuditLogService.logAction(
        actionType: 'ADMIN_APPROVED_INSPECTION',
        category: 'Government',
        title: 'Inspection Report Endorsed by Admin',
        description: 'Admin verified ${insp.officerName}\'s inspection for ${insp.restaurantName}. Forwarded to Health Officer for statutory decree determination.',
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _selectedInspection = updatedInsp;
      });

      HygieneFeedback.showSuccess(
        context,
        'Inspection verified & approved! Forwarded to Officer ${insp.officerName} to issue decree.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      HygieneFeedback.showError(context, 'Error approving report: $e');
    }
  }

  // ==========================================
  // HIGH-QUALITY REVISION REQUEST MODAL
  // ==========================================
  Future<void> _requestRevision(InspectionModel insp) async {
    final noteCtrl = TextEditingController();
    final requested = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.assignment_return_rounded, color: Color(0xFFD97706), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reject Report & Reschedule',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Manual Re-inspection Required',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Explain why this report was rejected. Officer ${insp.officerName} must schedule and conduct a new visit:',
                  style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'e.g. Please re-evaluate cold storage temperatures and attach clearer swab test photos...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Reject & Return', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (requested == true) {
      final revisionNote = noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : 'Please review and clarify inspection findings.';

      if (insp.complaintId.isNotEmpty) {
        await WorkflowService.verifyAdminInspectionReport(
          complaintId: insp.complaintId,
          adminId: 'admin',
          isValid: false,
          revisionNotes: revisionNote,
        );
      }

      await RestaurantStoreService.rejectInspectionForRescheduling(
        insp,
        reviewNotes: revisionNote,
      );
      if (insp.complaintId.isNotEmpty) {
        await ComplaintStoreService.updateComplaintStatus(
          insp.complaintId,
          ComplaintStatus.investigating,
        );
      }

      NotificationService.sendNotification(
        userId: 'gov_001',
        title: '📝 Audit Revision Requested: ${insp.restaurantName}',
        message: 'Admin rejected the inspection report: "$revisionNote". Manually schedule a new visit and submit replacement findings.',
        type: NotificationType.system,
        actionUrl: 'verified_complaints_list',
      );

      if (mounted) {
        HygieneFeedback.showWarning(
          context,
          'Report rejected. A new inspection visit must be scheduled.',
        );
        setState(() => _selectedInspection = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;

    if (_selectedInspection == null && args is InspectionModel) {
      _selectedInspection = args;
    }

    return ValueListenableBuilder<List<InspectionModel>>(
      valueListenable: RestaurantStoreService.inspectionsNotifier,
      builder: (context, allInspections, _) {
        // Collect inspections + merge active complaints investigated/inspected by officers
        final List<InspectionModel> combinedInspections = List<InspectionModel>.from(allInspections);
        final allComplaints = ComplaintStoreService.complaintsNotifier.value;

        for (final c in allComplaints) {
          final alreadyExists = combinedInspections.any(
            (i) => i.complaintId == c.id ||
                (c.restaurantId.isNotEmpty && i.restaurantId == c.restaurantId) ||
                (i.restaurantName.toLowerCase().trim() == c.restaurantName.toLowerCase().trim()),
          );
          if (!alreadyExists &&
              (c.status == ComplaintStatus.inspecting ||
                  c.status == ComplaintStatus.investigating ||
                  c.status == ComplaintStatus.pendingInspection ||
                  c.isFlaggedForReview)) {
            combinedInspections.add(
              InspectionModel(
                id: 'insp_${c.id}',
                complaintId: c.id,
                restaurantId: c.restaurantId,
                restaurantName: RestaurantStoreService.resolveRestaurantName(c.restaurantName, fallback: c.restaurantName),
                scheduledDate: c.submittedAt.contains('T') ? c.submittedAt.split('T').first : c.submittedAt,
                conductedDate: null,
                officerName: 'Health Inspector (KKM)',
                outcome: InspectionOutcome.pending,
                findings: c.description.isNotEmpty
                    ? c.description
                    : (c.issues.isNotEmpty ? 'Reported issues: ${c.issues.join(", ")}' : 'Inspection pending.'),
                recommendedAction: EnforcementType.none,
                issuedAction: EnforcementType.none,
                justification: '',
                fineAmount: 0.0,
                statutoryCitation: null,
                enforcementStatus: EnforcementStatus.pending,
                isAdminApproved: false,
                photoUrls: c.photoUrls,
              ),
            );
          }
        }

        if (_selectedInspection != null) {
          final synced = combinedInspections.where((i) => i.id == _selectedInspection!.id).firstOrNull;
          final currentInsp = synced ?? _selectedInspection!;
          return _buildDetailView(context, currentInsp, isDark);
        }

        return _buildListView(context, combinedInspections, isDark);
      },
    );
  }

  // ==========================================
  // VIEW 1: STRUCTURED REPORT LIST
  // ==========================================
  Widget _buildListView(BuildContext context, List<InspectionModel> allInspections, bool isDark) {
    final query = _searchCtrl.text.trim().toLowerCase();

    final pendingReports = allInspections.where((i) => !_isInspectionAdminApproved(i) && _isVisitRecorded(i)).toList();
    final endorsedReports = allInspections.where((i) => _isInspectionAdminApproved(i)).toList();

    List<InspectionModel> displayList = (_selectedTab == 0
        ? pendingReports
        : (_selectedTab == 1 ? endorsedReports : _selectedTab == 3 ? allInspections.where((i) => !_isVisitRecorded(i)).toList() : allInspections));

    if (query.isNotEmpty) {
      displayList = displayList.where((i) {
        final rName = i.restaurantName.toLowerCase();
        final cId = i.complaintId.toLowerCase();
        final off = i.officerName.toLowerCase();
        return rName.contains(query) || cId.contains(query) || off.contains(query);
      }).toList();
    }
    displayList = displayList.where((i) => GovernmentRecordDate.matches(i.conductedDate ?? i.scheduledDate, _dateDays) && (_group == 'All' || (_group == 'Compliant' ? i.outcome == InspectionOutcome.compliant : i.outcome == InspectionOutcome.nonCompliant))).toList();
    displayList.sort((a,b) => GovernmentRecordDate.compare(a.conductedDate ?? a.scheduledDate, b.conductedDate ?? b.scheduledDate, _sortOrder == 'Oldest first'));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Review Reports',
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh Reports from Database',
            onPressed: _loadRealData,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _loadRealData,
          color: const Color(0xFF0F766E),
        child: Column(
          children: [
            // KPI Metric Header
            Container(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Pending Review',
                          count: '${pendingReports.length}',
                          color: const Color(0xFFD97706),
                          icon: Icons.hourglass_top_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Endorsed',
                          count: '${endorsedReports.length}',
                          color: const Color(0xFF059669),
                          icon: Icons.verified_user_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Total Audits',
                          count: '${allInspections.length}',
                          color: const Color(0xFF0F766E),
                          icon: Icons.receipt_long_rounded,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search Bar
                  AppSearchField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search audits by restaurant, ID, or officer...',
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tabs Filter Row
            Container(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabChip(0, 'Pending Review (${pendingReports.length})'),
                    const SizedBox(width: 8),
                    _buildTabChip(1, 'Endorsed (${endorsedReports.length})'),
                    const SizedBox(width: 8),
                    _buildTabChip(3, 'Awaiting Visit (${allInspections.where((i) => !_isVisitRecorded(i)).length})'),
                    const SizedBox(width: 8),
                    _buildTabChip(2, 'All Reports (${allInspections.length})'),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1),

AdminListFilters( guidance: 'Pending Review contains recorded visits ready for review; unrecorded visits are separate.', dateLabel: 'Visit', count: displayList.length, days: _dateDays, sort: _sortOrder, groups: const ['All', 'Compliant', 'Non-compliant'], group: _group, onGroup: (v) => setState(() => _group = v), onSort: (v) => setState(() => _sortOrder = v), onDays: (v) => setState(() => _dateDays = v), onSearch: () => setState(() {})),
            // List Body
            Expanded(
              child: _isLoading && allInspections.isEmpty
                  ? DualArcLoader.centered(message: 'Loading inspection reports...', isDark: isDark)
                  : displayList.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0F2FE),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.task_alt_rounded, size: 42, color: isDark ? Colors.tealAccent : const Color(0xFF0284C7)),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _selectedTab == 0 ? 'No Pending Inspection Reports' : 'No Reports Found',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _selectedTab == 0
                                          ? 'All officer inspection reports have been verified and processed.'
                                          : 'Try adjusting your search filters or check back later.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: displayList.length,
                          itemBuilder: (ctx, idx) {
                            final item = displayList[idx];
                            return _buildReportSummaryCard(item, isDark);
                          },
                        ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTabChip(int index, String label) {
    final isSelected = _selectedTab == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      showCheckmark: false,
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
        ),
      ),
      selectedColor: const Color(0xFF0F766E),
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9),
      side: BorderSide(
        color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
      ),
      onSelected: (val) {
        if (val) setState(() => _selectedTab = index);
      },
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
          const SizedBox(height: 3),
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

  Widget _buildReportSummaryCard(InspectionModel item, bool isDark) {
    final bool isVisitRecorded = _isVisitRecorded(item);
    final bool isApproved = _isInspectionAdminApproved(item);
    final bool isNonCompliant = item.outcome == InspectionOutcome.nonCompliant;
    final formattedId = _formatCaseId(item.complaintId.isNotEmpty ? item.complaintId : item.id);
    final restName = RestaurantStoreService.resolveRestaurantName(item.restaurantName, fallback: item.restaurantName);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !isVisitRecorded
              ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0))
              : (isApproved
                  ? const Color(0xFF059669).withValues(alpha: 0.3)
                  : const Color(0xFFD97706).withValues(alpha: 0.35)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
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
            if (!isVisitRecorded) {
              HygieneFeedback.showWarning(
                context,
                'Cannot review report: Health officer has not conducted and recorded the on-site inspection visit yet.',
              );
              return;
            }
            setState(() => _selectedInspection = item);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Case ID + Conducted / Scheduled Date
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formattedId,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          !isVisitRecorded ? Icons.event_note_rounded : Icons.calendar_today_rounded,
                          size: 12,
                          color: !isVisitRecorded
                              ? const Color(0xFF0284C7)
                              : (isDark ? Colors.white54 : Colors.grey.shade500),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          !isVisitRecorded
                              ? 'Scheduled: ${_formatDate(item.scheduledDate)}'
                              : _formatDate(item.conductedDate ?? item.scheduledDate),
                          style: TextStyle(
                            fontSize: 11,
                            color: !isVisitRecorded
                                ? const Color(0xFF0284C7)
                                : (isDark ? Colors.white54 : Colors.grey.shade600),
                            fontWeight: !isVisitRecorded ? FontWeight.bold : FontWeight.w500,
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
                  'Inspected by: ${item.officerName.isNotEmpty ? item.officerName : "Health Inspector (KKM)"}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 10),

                // Badges Row: Outcome + Admin Status
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (!isVisitRecorded) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pending_actions_rounded, size: 12, color: Color(0xFF0284C7)),
                            SizedBox(width: 4),
                            Text(
                              'Visit Pending',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_clock_rounded, size: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                            const SizedBox(width: 3.5),
                            Text(
                              'OFFICER VISIT REQUIRED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white60 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isNonCompliant
                              ? const Color(0xFFDC2626).withValues(alpha: 0.12)
                              : const Color(0xFF059669).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isNonCompliant
                                ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                                : const Color(0xFF059669).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isNonCompliant ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                              size: 12,
                              color: isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isNonCompliant ? 'Non-Compliant' : 'Compliant Pass',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isApproved
                              ? const Color(0xFF059669).withValues(alpha: 0.12)
                              : const Color(0xFFD97706).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isApproved
                                ? const Color(0xFF059669).withValues(alpha: 0.3)
                                : const Color(0xFFD97706).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isApproved ? Icons.verified_user_rounded : Icons.hourglass_top_rounded,
                              size: 11,
                              color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 3.5),
                            Text(
                              isApproved ? 'ADMIN ENDORSED' : 'AWAITING ADMIN REVIEW',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                if (item.findings.isNotEmpty) ...[
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
                      !isVisitRecorded
                          ? 'Scheduled Notes: ${item.findings}'
                          : 'Findings: ${item.findings}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Recommendation Highlight Box or Pending Notice Box
                if (!isVisitRecorded) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Action Pending: Officer has not recorded on-site inspection findings yet',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282828) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFFCD34D)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (item.issuedAction != EnforcementType.none || item.fineAmount > 0)
                              ? Icons.gavel_rounded
                              : (item.outcome == InspectionOutcome.compliant ? Icons.check_circle_rounded : Icons.pending_actions_rounded),
                          size: 14,
                          color: const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (item.issuedAction != EnforcementType.none || item.fineAmount > 0)
                                ? 'Action Issued: ${item.issuedAction.name.toUpperCase()} (RM ${item.fineAmount.toStringAsFixed(2)})'
                                : (item.outcome == InspectionOutcome.compliant
                                    ? 'Outcome: Compliant Pass (No Penalty)'
                                    : (isApproved ? 'Report Approved • Awaiting Officer Action' : 'Findings Filed • Awaiting Admin Review')),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                            ),
                          ),
                        ),
                        if (item.photoUrls.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.photo_camera, size: 11, color: Color(0xFFD97706)),
                                const SizedBox(width: 3),
                                Text(
                                  '${item.photoUrls.length}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // CTA Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isVisitRecorded
                        ? () {
                            setState(() => _selectedInspection = item);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isApproved ? const Color(0xFF0F766E) : const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isDark ? const Color(0xFF27272A) : const Color(0xFFE2E8F0),
                      disabledForegroundColor: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: Icon(
                      !isVisitRecorded
                          ? Icons.lock_clock_rounded
                          : (isApproved ? Icons.visibility_outlined : Icons.description_outlined),
                      size: 15,
                    ),
                    label: Text(
                      !isVisitRecorded
                          ? 'Visit Not Recorded Yet (Disabled)'
                          : (isApproved ? 'View Full Report →' : 'Review & Approve Report →'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: !isVisitRecorded
                            ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                            : Colors.white,
                      ),
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

  // ==========================================
  // VIEW 2: COMPREHENSIVE CASE REVIEW
  // ==========================================
  Widget _buildDetailView(BuildContext context, InspectionModel insp, bool isDark) {
    final linkedComplaint = _findLinkedComplaint(insp);
    final linkedRestaurant = _findLinkedRestaurant(insp);

    final bool isVisitRecorded = _isVisitRecorded(insp);
    final bool isApproved = _isInspectionAdminApproved(insp);
    final bool isActionIssued = insp.issuedAction != EnforcementType.none ||
        insp.fineAmount > 0 ||
        (insp.issuedDate != null &&
            insp.issuedDate!.isNotEmpty &&
            insp.issuedDate != 'null');
    final bool isFinePaid = insp.isFinePaid ||
        RestaurantStoreService.isOutletFinePaid(
          linkedRestaurant?.id ?? insp.restaurantId,
          complaintId: linkedComplaint?.id ?? insp.complaintId,
          inspectionId: insp.id,
        ) ||
        (linkedRestaurant?.isFinePaid == true);
    final bool isCaseClosed = insp.enforcementStatus == EnforcementStatus.completed ||
        RestaurantStoreService.isCaseClosed(
          inspectionId: insp.id,
          complaintId: linkedComplaint?.id ?? insp.complaintId,
        ) ||
        linkedComplaint?.status == ComplaintStatus.resolved;
    final bool isPenaltyStageComplete = isActionIssued &&
        (insp.fineAmount <= 0 || isFinePaid);

    final bool isNonCompliant = insp.outcome == InspectionOutcome.nonCompliant;
    final formattedId = _formatCaseId(insp.complaintId.isNotEmpty ? insp.complaintId : insp.id);
    final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName);
    final conductedDateFormatted = _formatDate(insp.conductedDate ?? insp.scheduledDate);

    // Retrieve Restaurant Owner Improvement Evidence
    final RectificationModel? ownerProof = RestaurantStoreService.getRectificationRecord(
      complaintId: insp.complaintId,
      inspectionId: insp.id,
      restaurantId: insp.restaurantId,
    );
    final List<String> ownerPhotos = (ownerProof != null && ownerProof.photoUrls.isNotEmpty)
        ? ownerProof.photoUrls.where((p) => p.trim().isNotEmpty).toList()
        : [];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Review Case Details',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        elevation: 0,
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0C2340),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(() => _selectedInspection = null),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Summary Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [AppTheme.darkSurfaceColor, AppTheme.darkSecondarySurface]
                      : [Colors.white, const Color(0xFFF8FAFC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isApproved
                      ? const Color(0xFF059669).withValues(alpha: 0.3)
                      : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                    blurRadius: 12,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.tag_rounded, size: 13, color: Color(0xFF0F766E)),
                            const SizedBox(width: 4),
                            Text(
                              formattedId,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isCaseClosed
                              ? const Color(0xFF0F766E).withValues(alpha: 0.12)
                              : (isFinePaid && insp.fineAmount > 0
                                  ? const Color(0xFF059669).withValues(alpha: 0.12)
                                  : (isActionIssued
                                      ? const Color(0xFFDC2626).withValues(alpha: 0.12)
                                      : (isApproved
                                          ? const Color(0xFF059669).withValues(alpha: 0.12)
                                          : const Color(0xFFD97706).withValues(alpha: 0.12)))),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCaseClosed
                                ? const Color(0xFF0F766E).withValues(alpha: 0.3)
                                : (isFinePaid && insp.fineAmount > 0
                                    ? const Color(0xFF059669).withValues(alpha: 0.3)
                                    : (isActionIssued
                                        ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                                        : (isApproved
                                            ? const Color(0xFF059669).withValues(alpha: 0.3)
                                            : const Color(0xFFD97706).withValues(alpha: 0.3)))),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCaseClosed
                                  ? Icons.verified_rounded
                                  : (isFinePaid && insp.fineAmount > 0
                                      ? Icons.paid_rounded
                                      : (isActionIssued
                                          ? Icons.gavel_rounded
                                          : (isApproved ? Icons.verified_user_rounded : Icons.hourglass_top_rounded))),
                              size: 13,
                              color: isCaseClosed
                                  ? const Color(0xFF0F766E)
                                  : (isFinePaid && insp.fineAmount > 0
                                      ? const Color(0xFF059669)
                                      : (isActionIssued
                                          ? const Color(0xFFDC2626)
                                          : (isApproved ? const Color(0xFF059669) : const Color(0xFFD97706)))),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isCaseClosed
                                  ? 'CASE CLOSED'
                                  : (isFinePaid && insp.fineAmount > 0
                                      ? 'FINE SETTLED'
                                      : (isActionIssued
                                          ? 'ACTION ISSUED'
                                          : (isApproved ? 'ADMIN APPROVED' : 'PENDING REVIEW'))),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isCaseClosed
                                    ? const Color(0xFF0F766E)
                                    : (isFinePaid && insp.fineAmount > 0
                                        ? const Color(0xFF059669)
                                        : (isActionIssued
                                            ? const Color(0xFFDC2626)
                                            : (isApproved ? const Color(0xFF059669) : const Color(0xFFD97706)))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    restName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                    ),
                  ),
                  if (linkedRestaurant != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: isDark ? Colors.white54 : Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${linkedRestaurant.address} • ${linkedRestaurant.category}',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.2),
                          child: const Icon(Icons.shield_rounded, size: 14, color: Color(0xFF0F766E)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Officer: ${insp.officerName.isNotEmpty ? insp.officerName : "Health Inspector (KKM)"}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : const Color(0xFF334155)),
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              conductedDateFormatted,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 2. TIMELINE OF CASE
            _buildSectionHeader('Case Progress Timeline', Icons.timeline_rounded, isDark),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildTimelineStep(
                    title: '1. Customer Complaint Submitted',
                    subtitle: linkedComplaint != null
                        ? 'Reported by ${linkedComplaint.userName.isNotEmpty ? linkedComplaint.userName : "Citizen"} on ${_formatDate(linkedComplaint.submittedAt)}'
                        : 'Initial hygiene violation report registered in system',
                    isDone: true,
                    isDark: isDark,
                  ),
                  _buildTimelineStep(
                    title: '2. Admin Verification',
                    subtitle: 'Verified authentic report and officer assigned for inspection',
                    isDone: true,
                    isDark: isDark,
                  ),
                  _buildTimelineStep(
                    title: isVisitRecorded ? '3. On-Site Inspection Conducted' : '3. On-Site Inspection Pending',
                    subtitle: isVisitRecorded
                        ? 'Officer ${insp.officerName} recorded inspection findings on $conductedDateFormatted'
                        : 'Awaiting Health Officer to conduct on-site visit and record findings',
                    isDone: isVisitRecorded,
                    isCurrent: !isVisitRecorded,
                    isDark: isDark,
                  ),
                  _buildTimelineStep(
                    title: '4. Admin Report Approval',
                    subtitle: isApproved
                        ? 'Admin approved inspection findings. Officer authorized to issue action notice.'
                        : (isVisitRecorded
                            ? 'Awaiting Admin review & approval (Current Step)'
                            : 'Locked until Health Officer records on-site visit'),
                    isDone: isApproved,
                    isCurrent: isVisitRecorded && !isApproved,
                    isDark: isDark,
                  ),
                  _buildTimelineStep(
                    title: '5. Penalty Issuance',
                    subtitle: !isActionIssued
                        ? (isApproved
                            ? 'Admin approved. Health Officer ready to issue the official penalty or action notice.'
                            : 'Locked until Admin approves inspection findings')
                        : (insp.fineAmount > 0 && !isFinePaid
                            ? 'Penalty issued: RM ${insp.fineAmount.toStringAsFixed(2)}. Awaiting settlement.'
                            : (insp.fineAmount > 0
                                ? 'Penalty issued and RM ${insp.fineAmount.toStringAsFixed(2)} settled. Ready for case closure.'
                                : 'Official ${insp.issuedAction.name.toUpperCase()} notice issued. Ready for case closure.')),
                    isDone: isPenaltyStageComplete,
                    isCurrent: isApproved && !isPenaltyStageComplete,
                    isDark: isDark,
                  ),
                  _buildTimelineStep(
                    title: '6. Case Closure',
                    subtitle: isCaseClosed
                        ? 'Case closed and officially archived. Re-certification complete.'
                        : (isPenaltyStageComplete
                            ? 'Penalty stage complete. Awaiting final Health Officer case closure.'
                            : 'Locked until penalty issuance and any required settlement are complete.'),
                    isDone: isCaseClosed,
                    isCurrent: isPenaltyStageComplete && !isCaseClosed,
                    isLast: true,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 3. ORIGINAL CUSTOMER COMPLAINT DETAILS
            _buildSectionHeader('1. Customer Complaint Details', Icons.assignment_late_outlined, isDark),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reported Category:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          linkedComplaint?.category.isNotEmpty == true ? linkedComplaint!.category : 'Food Safety Issue',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                        ),
                      ),
                    ],
                  ),
                  if (linkedComplaint?.issues.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: linkedComplaint!.issues.map((issue) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            issue,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Customer Description Statement:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF0C2340)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      linkedComplaint?.description.isNotEmpty == true
                          ? linkedComplaint!.description
                          : 'Customer reported unhygienic conditions and requested inspection.',
                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
                    ),
                  ),
                  if (linkedComplaint?.photoUrls.isNotEmpty == true) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Customer Photo Evidence (${linkedComplaint!.photoUrls.length}):',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF0C2340)),
                        ),
                        const Text(
                          'Tap to zoom',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: linkedComplaint.photoUrls.length,
                        itemBuilder: (ctx, i) {
                          final photo = linkedComplaint.photoUrls[i];
                          return GestureDetector(
                            onTap: () => _showImagePreview(context, photo, tag: 'Customer Evidence ${i + 1}'),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    _buildPhotoWidget(photo, width: 80, height: 80),
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
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
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 4. RESTAURANT OWNER IMPROVEMENT PROOF
            _buildSectionHeader('2. Restaurant Owner Improvement Proof', Icons.storefront_rounded, isDark),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Improvement Status:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: (ownerProof != null)
                              ? const Color(0xFF059669).withValues(alpha: 0.12)
                              : const Color(0xFFD97706).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (ownerProof != null)
                                ? const Color(0xFF059669).withValues(alpha: 0.3)
                                : const Color(0xFFD97706).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          ownerProof != null ? 'PROOF SUBMITTED' : 'NOT SUBMITTED',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: ownerProof != null ? const Color(0xFF059669) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Restaurant Owner Statement / Notes:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF0C2340)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      (ownerProof != null && ownerProof.notes.isNotEmpty)
                          ? ownerProof.notes
                          : (ownerProof != null
                              ? 'Restaurant owner uploaded fix proof photos.'
                              : 'No improvement notes or explanation submitted by restaurant owner.'),
                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Owner Photo Attachments (${ownerPhotos.length}):',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF0C2340)),
                      ),
                      if (ownerPhotos.isNotEmpty)
                        const Text(
                          'Tap to zoom',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (ownerPhotos.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 20, color: isDark ? Colors.white38 : Colors.grey.shade400),
                          const SizedBox(width: 8),
                          Text(
                            'No improvement photos uploaded by restaurant owner.',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: ownerPhotos.length,
                        itemBuilder: (ctx, i) {
                          final photo = ownerPhotos[i];
                          return GestureDetector(
                            onTap: () => _showImagePreview(context, photo, tag: 'Owner Improvement Photo ${i + 1}'),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    _buildPhotoWidget(photo, width: 90, height: 90),
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
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

            const SizedBox(height: 18),

            // 5. OFFICER ON-SITE INSPECTION FINDINGS & PHOTOS
            _buildSectionHeader('3. Officer On-Site Inspection Report', Icons.fact_check_outlined, isDark),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Inspection Outcome:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isNonCompliant
                              ? const Color(0xFFDC2626).withValues(alpha: 0.12)
                              : const Color(0xFF059669).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isNonCompliant
                                ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                                : const Color(0xFF059669).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isNonCompliant ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                              size: 13,
                              color: isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isNonCompliant ? 'NON-COMPLIANT' : 'COMPLIANT PASS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Inspector Official Findings:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF0C2340)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      insp.findings.isNotEmpty
                          ? insp.findings
                          : 'Official hygiene inspection conducted with non-compliance violations recorded.',
                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Officer Photo Evidence Attachments (${insp.photoUrls.length}):',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF0C2340)),
                      ),
                      if (insp.photoUrls.isNotEmpty)
                        const Text(
                          'Tap to zoom',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (insp.photoUrls.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 20, color: isDark ? Colors.white38 : Colors.grey.shade400),
                          const SizedBox(width: 8),
                          Text(
                            'No photos attached by inspecting officer.',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: insp.photoUrls.length,
                        itemBuilder: (ctx, i) {
                          final photo = insp.photoUrls[i];
                          return GestureDetector(
                            onTap: () => _showImagePreview(context, photo, tag: 'Officer Inspection Photo ${i + 1}'),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    _buildPhotoWidget(photo, width: 90, height: 90),
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
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

            const SizedBox(height: 18),

            // 6. ACTION & FINE STATUS
            _buildSectionHeader('4. Enforcement Action & Fine', Icons.gavel_rounded, isDark),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (insp.issuedAction != EnforcementType.none || insp.fineAmount > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Issued Enforcement Action:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            insp.issuedAction.name.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (insp.fineAmount > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Compound Fine Amount:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                          ),
                          Text(
                            'RM ${insp.fineAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.red),
                          ),
                        ],
                      ),
                    ],
                    if (insp.statutoryCitation != null && insp.statutoryCitation!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Enacted Law & Clause:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          insp.statutoryCitation!,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isDark ? Colors.tealAccent : const Color(0xFF0F766E)),
                        ),
                      ),
                    ],
                  ] else if (insp.outcome == InspectionOutcome.compliant) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Compliant Pass • No Penalty Required',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The establishment has passed the inspection. No compound fine or closure penalty is required.',
                      style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ] else if (!isApproved) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 16),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Action & Fine Status',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0C2340),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'PENDING APPROVAL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'No fine or legal action has been issued yet.\n\nOnce Admin approves this report, the Health Officer will be authorized to determine and issue the appropriate enforcement action, fine amount, and legal notice on the Issue Action screen.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ] else ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.gavel_rounded, color: Color(0xFF0F766E), size: 16),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Action Issuance Authorized',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0C2340),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'REPORT APPROVED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        'This inspection report is approved by Admin.\n\nThe Health Officer can now determine and submit the enforcement penalty, fine amount, and legal clause on the Issue Action screen.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 7. ADMIN VERIFICATION ACTIONS BAR
            if (!isApproved) ...[
              if (!isVisitRecorded) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock_rounded, color: Color(0xFFD97706), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'On-site visit not recorded yet. Health Officer must conduct the physical visit and record findings before admin approval.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CustomButton(
                  label: 'Visit Not Recorded Yet (Approval Locked)',
                  icon: Icons.hourglass_top_rounded,
                  backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                  onPressed: null,
                ),
              ] else ...[
                CustomButton(
                  label: 'Approve Inspection Report',
                  icon: Icons.verified_rounded,
                  backgroundColor: const Color(0xFF059669),
                  isLoading: _isProcessing,
                  onPressed: () => _approveReport(insp),
                ),
                const SizedBox(height: 10),
                CustomButton(
                  label: 'Reject Report & Require Reschedule',
                  icon: Icons.assignment_return_rounded,
                  backgroundColor: const Color(0xFFD97706),
                  onPressed: () => _requestRevision(insp),
                ),
              ],
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isCaseClosed
                      ? const Color(0xFF0F766E).withValues(alpha: 0.12)
                      : const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCaseClosed
                        ? const Color(0xFF0F766E).withValues(alpha: 0.35)
                        : const Color(0xFF059669).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCaseClosed
                          ? Icons.verified_rounded
                          : (isFinePaid && insp.fineAmount > 0
                              ? Icons.paid_rounded
                              : (isActionIssued ? Icons.gavel_rounded : Icons.check_circle_rounded)),
                      color: isCaseClosed ? const Color(0xFF0F766E) : const Color(0xFF059669),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isCaseClosed
                            ? 'Case officially closed and archived! Full compliance and resolution certificate verified.'
                            : (isFinePaid && insp.fineAmount > 0
                                ? 'Compound penalty paid & settled by restaurant owner. Awaiting Health Officer final case closure.'
                                : (isActionIssued
                                    ? 'Enforcement action notice issued (${insp.issuedAction.name.toUpperCase()}). Penalty settlement and compliance in progress.'
                                    : 'Inspection report approved! Health Officer has been notified to issue the penalty or action notice.')),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isCaseClosed ? const Color(0xFF0F766E) : const Color(0xFF059669),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFF0F766E), width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _selectedInspection = null),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to Review Reports List', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF0F766E).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFF0F766E)),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: isDark ? Colors.white : const Color(0xFF0C2340),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String subtitle,
    required bool isDone,
    bool isCurrent = false,
    bool isLast = false,
    required bool isDark,
  }) {
    final Color color = isDone
        ? const Color(0xFF059669)
        : (isCurrent ? const Color(0xFFD97706) : (isDark ? Colors.white30 : Colors.grey.shade400));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: const Color(0xFFD97706).withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isDone ? Icons.check_rounded : (isCurrent ? Icons.circle : Icons.circle_outlined),
                size: 13,
                color: color,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 38,
                color: color.withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isCurrent ? const Color(0xFFD97706) : (isDark ? Colors.white : const Color(0xFF0C2340)),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
