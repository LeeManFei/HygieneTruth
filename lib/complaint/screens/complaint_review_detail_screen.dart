import 'dart:io';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/rectification_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/status_badge.dart';

class ComplaintReviewDetailScreen extends StatelessWidget {
  const ComplaintReviewDetailScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;
    ComplaintModel? c;
    if (args is ComplaintModel) {
      c = args;
    } else if (RestaurantStoreService.complaintsNotifier.value.isNotEmpty) {
      c = RestaurantStoreService.complaintsNotifier.value.first;
    }

    if (c == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Review Report'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.description_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No report details available.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    // Resolve live updated complaint from store
    final allComplaints = RestaurantStoreService.complaintsNotifier.value;
    final allInspections = RestaurantStoreService.inspectionsNotifier.value;
    final rawId = c.id;
    final liveComp = allComplaints.where((item) {
      if (item.id == rawId) return true;
      if (item.id.toLowerCase().trim() == rawId.toLowerCase().trim()) return true;
      return false;
    }).firstOrNull;
    if (liveComp != null) {
      c = liveComp;
    }

    // Match all related inspections across the whole related UUID / complaint / restaurant
    final matchingInspections = allInspections.where((insp) {
      final isDirectComp = insp.id == c?.id ||
          insp.complaintId == c?.id ||
          (c != null &&
              insp.complaintId.isNotEmpty &&
              insp.complaintId.toLowerCase().trim() ==
                  c.id.toLowerCase().trim());
      return isDirectComp;
    }).toList();
    matchingInspections.sort(CaseOrdering.inspections);

    final linkedInsp = matchingInspections.firstOrNull;
    final closedInspection =
        linkedInsp?.enforcementStatus == EnforcementStatus.completed
            ? linkedInsp
            : null;
    final inProgressInspection =
        linkedInsp?.enforcementStatus == EnforcementStatus.inProgress
            ? linkedInsp
            : null;

    // 1. Customer Complaint Media
    final List<String> customerPhotos = c.photoUrls.where((p) => p.trim().isNotEmpty).toList();

    // 2. Restaurant Owner Rectification Evidence
    final RectificationModel? rectificationRecord = RestaurantStoreService.getRectificationRecord(
      complaintId: c.id,
      inspectionId: linkedInsp?.id,
      restaurantId: c.restaurantId,
    );
    final List<String> ownerPhotos = (rectificationRecord != null && rectificationRecord.photoUrls.isNotEmpty)
        ? rectificationRecord.photoUrls.where((p) => p.trim().isNotEmpty).toList()
        : [];

    // 3. Officer Inspection Record Media
    final List<String> officerPhotos = (linkedInsp != null && linkedInsp.photoUrls.isNotEmpty)
        ? linkedInsp.photoUrls.where((p) => p.trim().isNotEmpty).toList()
        : [];

    final int totalMediaCount = customerPhotos.length + ownerPhotos.length + officerPhotos.length;
    final bool isOwnerEvidenceSubmitted = RestaurantStoreService.isRectificationSubmitted(
      c.restaurantId,
      complaintId: c.id,
      inspectionId: linkedInsp?.id,
    );

    final bool isCaseClosed = closedInspection != null || c.status == ComplaintStatus.resolved;
    final bool isVisitConducted = linkedInsp != null &&
        linkedInsp.conductedDate != null &&
        linkedInsp.conductedDate!.isNotEmpty &&
        linkedInsp.conductedDate != 'null' &&
        linkedInsp.outcome != InspectionOutcome.pending;
    final bool isAdminApproved = isVisitConducted &&
        (linkedInsp.isAdminApproved ||
            RestaurantStoreService.isAdminInspectionApproved(
              linkedInsp.id,
              complaintId: linkedInsp.complaintId,
              restaurantId: linkedInsp.restaurantId,
            ));
    final bool isUnderInvestigation = !isCaseClosed && (inProgressInspection != null || c.status == ComplaintStatus.investigating || c.status == ComplaintStatus.inspecting || c.status == ComplaintStatus.pendingInspection);
    final bool isRejected = c.status == ComplaintStatus.rejected;

    final sevColor = _getSeverityColor(c.severity);
    final reportIdFormatted = _formatReportId(c.id);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(title: 'Report: ${c.category}'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. FLAGGED BANNER IF APPLICABLE
            if (c.isFlaggedForReview && c.flaggedReason != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.12) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.35) : Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.25) : Colors.red.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.flag_rounded, color: isDark ? const Color(0xFFFCA5A5) : Colors.red.shade700, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI ANOMALY FLAGGED FOR REVIEW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFFFCA5A5) : Colors.red.shade900,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.flaggedReason!,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFFFECACA) : Colors.red.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 1.5 CLOSED CASE RESOLUTION SUMMARY BANNER (IF CASE CLOSED)
            if (isCaseClosed) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF059669).withValues(alpha: isDark ? 0.5 : 0.6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF059669),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CASE STATUTORILY CLOSED & RESOLVED',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                'Compliance verified • Outlet re-certified',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? Colors.white70 : const Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (closedInspection != null) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: Color(0xFF059669)),
                      const SizedBox(height: 10),
                      Text(
                        'Officer in Charge: ${closedInspection.officerName.isNotEmpty ? closedInspection.officerName : "MOH Health Enforcement Inspector"}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Statutory Decree: ${closedInspection.issuedAction.name.toUpperCase()} (Settled)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : const Color(0xFF047857),
                        ),
                      ),
                      if (closedInspection.justification.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Remarks: ${closedInspection.justification}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.white60 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 2. REPORT HEADER CARD
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
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
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            'Report ID: $reportIdFormatted',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge.fromStatus(
                        isCaseClosed
                            ? 'Resolved'
                            : (isUnderInvestigation ? 'Investigating' : (isRejected ? 'Rejected' : c.status.name)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    c.restaurantName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            'Reported by ${c.userName}',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimestamp(c.submittedAt),
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // KKM PRIORITY ASSESSMENT BANNER
            if (c.category.toLowerCase().contains('food') ||
                c.category.toLowerCase().contains('poison') ||
                c.category.toLowerCase().contains('pest') ||
                c.category.toLowerCase().contains('cockroach')) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_hospital_rounded, color: Color(0xFFDC2626), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRITICAL KKM FOOD SAFETY PRIORITY',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF991B1B),
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Highest inspection priority for health officers. Mandates immediate on-site food cold storage audit and microbial swab evaluation.',
                            style: TextStyle(fontSize: 11, color: Color(0xFFB91C1C), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (c.category.toLowerCase().contains('rude') ||
                c.category.toLowerCase().contains('conduct') ||
                c.category.toLowerCase().contains('employee') ||
                c.category.toLowerCase().contains('service')) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFEDD5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEDD5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.info_rounded, color: Color(0xFFEA580C), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STAFF CONDUCT REPORT (SECONDARY PRIORITY)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF9A3412),
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Note: KKM officers prioritize kitchen cleanliness & food safety. Staff service concerns are addressed as secondary advisory notices.',
                            style: TextStyle(fontSize: 11, color: Color(0xFFC2410C), height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 3. DETAILS & EVIDENCE BREAKDOWN CARD
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.navyColor,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Category & Severity (Equal Height & Consistent UI)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.15 : 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.3 : 0.15),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Category',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c.category,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: sevColor.withValues(alpha: isDark ? 0.15 : 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sevColor.withValues(alpha: isDark ? 0.3 : 0.15),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Severity Rank',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${c.severity.name.toUpperCase()} PRIORITY',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? sevColor.withValues(alpha: 0.95) : sevColor,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Specific Issues
                  Text(
                    'Reported Issues',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (c.issues.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'General Hygiene Concern',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: c.issues.map((issue) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF451A03).withValues(alpha: 0.5) : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? const Color(0xFFB45309).withValues(alpha: 0.5) : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.report_problem_rounded,
                                size: 12,
                                color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                issue,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),

                  // Description
                  Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      c.description.isNotEmpty ? c.description : 'No description provided.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF0C2340),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // GPS Coordinates
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: isDark ? 0.2 : 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF0284C7)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reported GPS Location',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)} (Within Area)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF0C2340),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Non-interactive GPS Map Preview for Admin
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          IgnorePointer(
                            ignoring: true,
                            child: GoogleMap(
                              style: AppMapTheme.getMapStyle(isDark),
                              onMapCreated: (ctrl) => AppMapTheme.applyTheme(ctrl, isDark),
                              initialCameraPosition: CameraPosition(
                                target: LatLng(c.latitude, c.longitude),
                                zoom: 16.0,
                              ),
                              markers: {
                                Marker(
                                  markerId: MarkerId(c.id),
                                  position: LatLng(c.latitude, c.longitude),
                                  infoWindow: InfoWindow(
                                    title: c.restaurantName,
                                    snippet: 'Report Location: ${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}',
                                  ),
                                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                                ),
                              },
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              myLocationButtonEnabled: false,
                              compassEnabled: false,
                              scrollGesturesEnabled: false,
                              zoomGesturesEnabled: false,
                              rotateGesturesEnabled: false,
                              tiltGesturesEnabled: false,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'GPS Preview',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3.5 PROOF MEDIA & INSPECTION LOGS (3 CATEGORIES: CUSTOMER, OWNER, OFFICER)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF181818) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.perm_media_rounded, color: Color(0xFF0F766E), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            'Proof Media & Inspection Logs',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          '$totalMediaCount Total Photo${totalMediaCount != 1 ? "s" : ""}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Multi-party statutory evidence categorized across customer report, restaurant owner rectification, and officer on-site findings.',
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),

                  // CATEGORY 1: Customer Complaint Media
                  _buildCategoryMediaBlock(
                    context: context,
                    categoryTitle: '1. Customer Complaint Media',
                    categorySubtitle: 'Visual evidence reported by customer upon filing initial complaint.',
                    icon: Icons.person_pin_rounded,
                    accentColor: const Color(0xFFD97706),
                    photos: customerPhotos,
                    tagPrefix: 'Customer Proof',
                    emptyMessage: 'No customer photos attached to this report.',
                    isDark: isDark,
                    caseId: reportIdFormatted,
                  ),

                  // CATEGORY 2: Restaurant Owner Evidence
                  _buildCategoryMediaBlock(
                    context: context,
                    categoryTitle: '2. Restaurant Owner Evidence',
                    categorySubtitle: 'Corrective improvement & sanitization photos submitted by restaurant management.',
                    icon: Icons.storefront_rounded,
                    accentColor: const Color(0xFF0F766E),
                    photos: ownerPhotos,
                    tagPrefix: 'Owner Fix',
                    emptyMessage: isOwnerEvidenceSubmitted
                        ? 'Owner submitted rectification statement (no additional photos attached).'
                        : 'No owner rectification photos submitted yet.',
                    extraNotes: rectificationRecord?.notes.isNotEmpty == true ? rectificationRecord!.notes : null,
                    isDark: isDark,
                    caseId: reportIdFormatted,
                  ),

                  // CATEGORY 3: Officer Inspection Record Media
                  _buildCategoryMediaBlock(
                    context: context,
                    categoryTitle: '3. Officer Inspection Record Media',
                    categorySubtitle: 'On-site physical inspection evidence logged by ${linkedInsp?.officerName.isNotEmpty == true ? linkedInsp!.officerName : "Health Inspector (KKM)"}.',
                    icon: Icons.policy_rounded,
                    accentColor: const Color(0xFF0284C7),
                    photos: officerPhotos,
                    tagPrefix: 'Officer Audit',
                    emptyMessage: 'No on-site officer inspection photos logged yet.',
                    isDark: isDark,
                    caseId: reportIdFormatted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. ACTION BUTTONS (DYNAMICALLY ADAPTED BASED ON CASE CLOSURE / VERIFICATION STATUS)
            if (isCaseClosed) ...[
              CustomButton(
                label: 'View Case Closure Details',
                icon: Icons.history_rounded,
                backgroundColor: const Color(0xFF0F766E),
                onPressed: () {
                  if (closedInspection != null) {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.closeCaseDetail,
                      arguments: closedInspection,
                    );
                  } else {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.enforcementHistory,
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.enforcementHistory,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFF0F766E), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(Icons.history_rounded, size: 18, color: isDark ? Colors.white70 : const Color(0xFF0F766E)),
                  label: Text(
                    'View Action & Enforcement History',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F766E),
                    ),
                  ),
                ),
              ),
            ] else if (isVisitConducted && !isAdminApproved) ...[
              CustomButton(
                label: 'Review Officer Inspection Report & Approve',
                icon: Icons.gavel_rounded,
                backgroundColor: const Color(0xFF0F766E),
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.inspectionReportReview,
                    arguments: linkedInsp,
                  );
                },
              ),
            ] else if (isVisitConducted && isAdminApproved) ...[
              CustomButton(
                label: 'Inspection Report Approved • Awaiting Officer Action',
                icon: Icons.hourglass_top_rounded,
                backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.inspectionReportReview,
                    arguments: linkedInsp,
                  );
                },
              ),
            ] else if (isUnderInvestigation) ...[
              CustomButton(
                label: c.status == ComplaintStatus.pendingInspection ? 'Field Inspection Scheduled' : 'Investigation In Progress',
                icon: Icons.hourglass_top_rounded,
                backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                onPressed: null,
              ),
            ] else if (isRejected) ...[
              CustomButton(
                label: 'Report Rejected • Closed Without Penalty',
                icon: Icons.cancel_outlined,
                backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                onPressed: null,
              ),
            ] else if (c.status != ComplaintStatus.submitted && !c.isFlaggedForReview) ...[
              CustomButton(
                label: 'Report Verified • 7-Day Owner Fix Window Active',
                icon: Icons.hourglass_top_rounded,
                backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                onPressed: null,
              ),
            ] else ...[
              CustomButton(
                label: 'Verify',
                icon: Icons.fact_check_rounded,
                backgroundColor: const Color(0xFF0F766E),
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.verifyEvidence,
                    arguments: c,
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryMediaBlock({
    required BuildContext context,
    required String categoryTitle,
    required String categorySubtitle,
    required IconData icon,
    required Color accentColor,
    required List<String> photos,
    required String tagPrefix,
    required String emptyMessage,
    String? extraNotes,
    required bool isDark,
    required String caseId,
  }) {
    final bool hasPhotos = photos.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPhotos
              ? accentColor.withValues(alpha: 0.3)
              : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
          width: hasPhotos ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  categoryTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0C2340),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: hasPhotos ? accentColor.withValues(alpha: 0.12) : (isDark ? Colors.white10 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasPhotos ? accentColor.withValues(alpha: 0.3) : Colors.transparent,
                  ),
                ),
                child: Text(
                  hasPhotos ? '${photos.length} Photo${photos.length > 1 ? "s" : ""}' : '0 Photos',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: hasPhotos ? accentColor : (isDark ? Colors.white54 : Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            categorySubtitle,
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
          if (extraNotes != null && extraNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Owner Statement: $extraNotes',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!hasPhotos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(Icons.no_photography_outlined, size: 16, color: isDark ? Colors.white38 : Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      emptyMessage,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 115,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                itemBuilder: (context, idx) {
                  final path = photos[idx];
                  return Padding(
                    padding: const EdgeInsets.only(right: 10.0),
                    child: GestureDetector(
                      onTap: () => _showLightbox(context, path, '$caseId • $categoryTitle #${idx + 1}'),
                      child: Container(
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildEvidenceImage(path, height: 115, width: 140),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$tagPrefix #${idx + 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                      const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                                    ],
                                  ),
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
    );
  }

  Widget _buildEvidenceImage(String path, {double height = 180, double? width, BoxFit fit = BoxFit.cover}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        height: height,
        width: width ?? double.infinity,
        fit: fit,
        errorBuilder: (ctx, err, stack) => _buildFallbackEvidencePlaceholder(height, width ?? double.infinity),
      );
    } else {
      String cleanPath = path;
      if (cleanPath.startsWith('file://')) {
        try {
          cleanPath = Uri.parse(cleanPath).toFilePath();
        } catch (_) {
          cleanPath = cleanPath.replaceFirst('file://', '');
        }
      }
      final file = File(cleanPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          height: height,
          width: width ?? double.infinity,
          fit: fit,
          errorBuilder: (ctx, err, stack) => _buildFallbackEvidencePlaceholder(height, width ?? double.infinity),
        );
      } else {
        return _buildFallbackEvidencePlaceholder(height, width ?? double.infinity);
      }
    }
  }

  Widget _buildFallbackEvidencePlaceholder(double height, double width) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 32, color: Color(0xFF94A3B8)),
          SizedBox(height: 6),
          Text(
            'Verified Evidence Photo',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  void _showLightbox(BuildContext context, String path, String caseId) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0C2340),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Evidence Photo • $caseId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Container(
                color: Colors.black,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: _buildEvidenceImage(path, height: 400, fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
