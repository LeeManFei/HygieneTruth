import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../notifications/models/notification_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/shimmer_skeletons.dart';

class CloseCaseScreen extends StatefulWidget {
  const CloseCaseScreen({super.key});

  @override
  State<CloseCaseScreen> createState() => _CloseCaseScreenState();
}

class _CloseCaseScreenState extends State<CloseCaseScreen> {
  String? _selectedInspectionId;
  bool _isSubmitting = false;

  final TextEditingController _remarksCtrl = TextEditingController();

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_') || rawId.startsWith('CMP_')) {
      return rawId.toUpperCase().replaceAll('_', '-');
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final allInspections = RestaurantStoreService.inspectionsNotifier.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (allInspections.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
        appBar: const CustomAppBar(title: 'Close Case'),
        body: const FormSkeleton(),
      );
    }

    final args = ModalRoute.of(context)?.settings.arguments;
    if (_selectedInspectionId == null) {
      if (args is InspectionModel) {
        _selectedInspectionId = args.id;
      } else {
        final eligibleCases = allInspections.where((i) {
          final isConducted = i.outcome != InspectionOutcome.pending && i.conductedDate != null;
          final isApproved = i.isAdminApproved ||
              RestaurantStoreService.isAdminInspectionApproved(i.id, complaintId: i.complaintId, restaurantId: i.restaurantId);
          final hasDecree = (i.issuedDate != null && i.issuedDate!.isNotEmpty && i.issuedDate != 'null') ||
              i.issuedAction != EnforcementType.none ||
              i.outcome == InspectionOutcome.compliant;
          return isConducted && isApproved && hasDecree;
        }).toList();

        final openCase = eligibleCases.where((i) => i.enforcementStatus == EnforcementStatus.inProgress).firstOrNull;
        _selectedInspectionId = openCase?.id ?? (eligibleCases.isNotEmpty ? eligibleCases.first.id : (allInspections.isNotEmpty ? allInspections.first.id : null));
      }
    }

    final targetInsp = allInspections.where((i) => i.id == _selectedInspectionId).firstOrNull ?? (allInspections.isNotEmpty ? allInspections.first : null);

    if (targetInsp == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
        appBar: const CustomAppBar(title: 'Case Closure Details'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No Case Selected for Closure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to List'),
              ),
            ],
          ),
        ),
      );
    }

    final formattedId = _formatCaseId(targetInsp.complaintId.isNotEmpty ? targetInsp.complaintId : targetInsp.id);
    final restName = RestaurantStoreService.resolveRestaurantName(targetInsp.restaurantName, fallback: targetInsp.restaurantName);
    final isAlreadyClosed = targetInsp.enforcementStatus == EnforcementStatus.completed;

    final bool isReportApproved = (targetInsp.isAdminApproved ||
            RestaurantStoreService.isAdminInspectionApproved(targetInsp.id, complaintId: targetInsp.complaintId, restaurantId: targetInsp.restaurantId)) &&
        (targetInsp.conductedDate != null && targetInsp.conductedDate!.isNotEmpty && targetInsp.conductedDate != 'null') &&
        targetInsp.outcome != InspectionOutcome.pending;

    final bool isDecreeIssued = (targetInsp.issuedDate != null && targetInsp.issuedDate!.isNotEmpty && targetInsp.issuedDate != 'null') ||
        targetInsp.issuedAction != EnforcementType.none ||
        targetInsp.outcome == InspectionOutcome.compliant;

    final bool isFinePaid = targetInsp.fineAmount <= 0 ||
        (RestaurantStoreService.isOutletFinePaid(
          targetInsp.restaurantId,
          restaurantName: targetInsp.restaurantName,
          complaintId: targetInsp.complaintId,
          inspectionId: targetInsp.id,
        ) || (targetInsp.isFinePaid && targetInsp.enforcementStatus == EnforcementStatus.completed));

    final bool isActionCompleted = targetInsp.outcome == InspectionOutcome.compliant ||
        RestaurantStoreService.isRectificationSubmitted(
          targetInsp.restaurantId,
          complaintId: targetInsp.complaintId,
          inspectionId: targetInsp.id,
        ) ||
        RestaurantStoreService.isRectificationVerified(
          complaintId: targetInsp.complaintId,
          inspectionId: targetInsp.id,
          restaurantId: targetInsp.restaurantId,
        ) ||
        targetInsp.enforcementStatus == EnforcementStatus.completed;

    int verifiedCount = 0;
    if (isActionCompleted) verifiedCount++;
    if (isReportApproved) verifiedCount++;
    if (isDecreeIssued) verifiedCount++;
    if (isFinePaid) verifiedCount++;

    final bool allRequirementsMet = verifiedCount == 4;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Case Closure Details'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                      : [const Color(0xFF0C2340), const Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          formattedId,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                      StatusBadge.fromStatus(
                        isAlreadyClosed ? 'Resolved' : 'In Progress',
                        isOnDark: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restName,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enforcement Decree: ${targetInsp.issuedAction.name.toUpperCase()} (RM ${targetInsp.fineAmount.toStringAsFixed(2)})',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (allRequirementsMet ? const Color(0xFF0F766E) : const Color(0xFFD97706)).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              allRequirementsMet ? Icons.verified_user_rounded : Icons.pending_actions_rounded,
                              color: allRequirementsMet ? const Color(0xFF0F766E) : const Color(0xFFD97706),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Case Closure Checklist',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (allRequirementsMet ? const Color(0xFF059669) : const Color(0xFFD97706)).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (allRequirementsMet ? const Color(0xFF059669) : const Color(0xFFD97706)).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '$verifiedCount/4 Verified',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: allRequirementsMet ? const Color(0xFF059669) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    allRequirementsMet
                        ? 'All requirements have been fully verified. Case is ready to be closed.'
                        : 'Pending requirements before case can be closed:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildSystemVerificationItem(
                    stepNumber: 1,
                    title: 'Restaurant Improvement & Fix Proof',
                    description: isActionCompleted
                        ? 'Sanitization & improvements verified by Health Officer'
                        : 'Restaurant owner has not yet submitted improvement proof',
                    statusTag: isActionCompleted ? 'Proof Verified' : 'Pending Proof',
                    isVerified: isActionCompleted,
                    isDark: isDark,
                  ),
                  const Divider(height: 16),
                  _buildSystemVerificationItem(
                    stepNumber: 2,
                    title: 'Official Inspection Report Approved',
                    description: isReportApproved
                        ? 'Field inspection filed and approved by Admin (${targetInsp.officerName})'
                        : 'Field visit conducted but pending Government Admin review & approval',
                    statusTag: isReportApproved ? 'System Verified' : 'Pending Admin Review',
                    isVerified: isReportApproved,
                    isDark: isDark,
                  ),
                  const Divider(height: 16),
                  _buildSystemVerificationItem(
                    stepNumber: 3,
                    title: 'Enforcement Action / Notice Issued',
                    description: isDecreeIssued
                        ? (targetInsp.issuedAction != EnforcementType.none
                            ? 'Official Action: ${targetInsp.issuedAction.name.toUpperCase()} (Issued on ${targetInsp.issuedDate ?? "Recent Date"})'
                            : 'Inspection passed clean compliance standard (No Penalty)')
                        : 'Enforcement penalty or notice has not been officially issued by officer yet',
                    statusTag: isDecreeIssued ? 'Action Active' : 'Pending Action',
                    isVerified: isDecreeIssued,
                    isDark: isDark,
                  ),
                  const Divider(height: 16),
                  _buildSystemVerificationItem(
                    stepNumber: 4,
                    title: 'Penalty Compound Paid & Settled',
                    description: targetInsp.fineAmount > 0
                        ? (isFinePaid
                            ? 'RM ${targetInsp.fineAmount.toStringAsFixed(2)} • Settled via Online Payment Gateway'
                            : 'RM ${targetInsp.fineAmount.toStringAsFixed(2)} • Pending payment from premise owner')
                        : 'No monetary compound penalty attached to this notice',
                    statusTag: targetInsp.fineAmount > 0 ? (isFinePaid ? 'Payment Cleared' : 'Unpaid Fine') : 'Cleared (RM 0)',
                    isVerified: isFinePaid,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Officer Final Closure Directives *',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: isAlreadyClosed && _remarksCtrl.text.isEmpty && targetInsp.justification.isNotEmpty
                        ? TextEditingController(text: targetInsp.justification)
                        : _remarksCtrl,
                    maxLines: 3,
                    enabled: !isAlreadyClosed,
                    style: TextStyle(
                      color: isAlreadyClosed
                          ? (isDark ? Colors.white54 : const Color(0xFF64748B))
                          : (isDark ? Colors.white : Colors.black87),
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: isAlreadyClosed
                          ? 'Case officially closed and archived. Directives recorded.'
                          : 'Enter official closure summary (e.g. All violations rectified, penalties settled, premise re-certified Grade A)...',
                      hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            CustomButton(
              label: isAlreadyClosed
                  ? 'Closed Case Completed'
                  : (!allRequirementsMet
                      ? 'Prerequisites Incomplete ($verifiedCount/4 Verified)'
                      : (_isSubmitting ? 'Archiving Case Record...' : 'Confirm & Complete Case Closure')),
              icon: isAlreadyClosed
                  ? Icons.check_circle_outline_rounded
                  : (!allRequirementsMet ? Icons.hourglass_top_rounded : Icons.check_circle_rounded),
              isLoading: _isSubmitting,
              backgroundColor: isAlreadyClosed
                  ? (isDark ? const Color(0xFF27272A) : const Color(0xFFE2E8F0))
                  : (allRequirementsMet ? const Color(0xFF0F766E) : (isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E))),
              textColor: isAlreadyClosed
                  ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                  : Colors.white,
              onPressed: isAlreadyClosed
                  ? null
                  : () => _handleCloseCase(targetInsp, restName, allRequirementsMet, verifiedCount, formattedId),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _handleCloseCase(
    InspectionModel targetInsp,
    String restName,
    bool allRequirementsMet,
    int verifiedCount,
    String formattedId,
  ) async {
    if (_isSubmitting) return;

    // Validation 1: All prerequisites met
    if (!allRequirementsMet) {
      HygieneFeedback.showWarning(
        context,
        'Prerequisites incomplete ($verifiedCount/4). All statutory steps must be verified before closure.',
      );
      return;
    }

    // Validation 2: Closure remarks
    final remarks = _remarksCtrl.text.trim();
    if (remarks.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please enter officer final closure remarks.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await RestaurantStoreService.closeCase(
        inspectionId: targetInsp.id, complaintId: targetInsp.complaintId,
        restaurantId: targetInsp.restaurantId, officerRemarks: remarks,
      );

      // Update linked restaurant record in memory, SharedPreferences, and Supabase database with official inspected grade
      await RestaurantStoreService.syncRestaurantRiskAndGrade(targetInsp.restaurantId, restaurantName: restName);
      final eval = RestaurantStoreService.getRestaurantRiskEvaluation(targetInsp.restaurantId, restaurantName: restName);
      final String gradeLetter = eval.score <= 20.0 ? 'A' : (eval.score <= 50.0 ? 'B' : (eval.score <= 75.0 ? 'C' : 'D'));

      // Audit log record
      AuditLogService.logAction(
        actionType: 'CASE_CLOSED',
        category: 'Government',
        title: 'Case #$formattedId Closed & Archived',
        description: 'Statutory verification completed (4/4 criteria verified). Graded $restName Grade $gradeLetter.',
      );

      // Push notification to premise owner
      NotificationService.sendNotification(
        userId: 'own_001',
        title: 'Case #$formattedId Formally Resolved & Closed',
        message: 'Ministry of Health has archived Case #$formattedId. Premise officially graded Grade $gradeLetter based on inspection audit.',
        type: NotificationType.hygieneAlert,
        actionUrl: 'case_closed',
      );

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showSuccess(context, 'Case #$formattedId closed & archived!');

      // If there are still open cases, select the next open case, otherwise pop
      final remainingOpen = RestaurantStoreService.inspectionsNotifier.value
          .where((i) => i.id != targetInsp.id && i.enforcementStatus == EnforcementStatus.inProgress)
          .firstOrNull;

      if (remainingOpen != null) {
        setState(() {
          _selectedInspectionId = remainingOpen.id;
        });
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showError(context, 'Failed to close case: $e');
    }
  }

  Widget _buildSystemVerificationItem({
    required int stepNumber,
    required String title,
    required String description,
    required String statusTag,
    required bool isVerified,
    required bool isDark,
  }) {
    final statusColor = isVerified ? const Color(0xFF059669) : const Color(0xFFD97706);
    final statusBg = isVerified
        ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFECFDF5))
        : (isDark ? const Color(0xFF78350F).withValues(alpha: 0.5) : const Color(0xFFFFFBEB));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDark ? 0.25 : 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Icon(
              isVerified ? Icons.check_rounded : Icons.pending_actions_rounded,
              size: 15,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$stepNumber. $title',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVerified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                            size: 11,
                            color: statusColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            statusTag,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
