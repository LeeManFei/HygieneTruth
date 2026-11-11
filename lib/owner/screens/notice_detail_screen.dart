import '../widgets/owner_compliance_checklist.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/rectification_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/models/workflow_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/pdf_invoice_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/stripe_payment_service.dart';
import '../../core/services/workflow_service.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../widgets/deadline_countdown_badge.dart';
import '../widgets/moh_payment_gateway_sheet.dart';

class NoticeDetailScreen extends StatefulWidget {
  const NoticeDetailScreen({super.key});

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  WorkflowState? _workflow;
  bool _workflowLoadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workflowLoadStarted) return;
    _workflowLoadStarted = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    final complaintId = args is ComplaintModel
        ? args.id
        : args is InspectionModel
            ? args.complaintId
            : RestaurantStoreService.complaintsNotifier.value.firstOrNull?.id;
    if (complaintId == null || complaintId.isEmpty) return;

    WorkflowService.loadWorkflow(complaintId).then((workflow) {
      if (mounted) setState(() => _workflow = workflow);
    });
  }

  Map<String, dynamic> _getAuthorityInfo({ComplaintModel? c, InspectionModel? insp,}) {
    if (insp != null) {
      final isClosure = insp.issuedAction == EnforcementType.closure;
      final isScheduled = insp.outcome == InspectionOutcome.pending && (insp.conductedDate == null || insp.conductedDate!.isEmpty);
      return {
        'authorityName': 'Ministry of Health (KKM) & DBKL Enforcement',
        'badgeLabel': isScheduled ? 'Official MOH Scheduled Inspection Directive' : 'Official MOH Statutory Enforcement Decree',
        'icon': isScheduled ? Icons.calendar_month_rounded : Icons.gavel_rounded,
        'color': isClosure ? const Color(0xFFDC2626) : (isScheduled ? const Color(0xFF0284C7) : const Color(0xFF0F766E)),
      };
    }

    if (c != null) {
      if (c.severity == SeverityLevel.high || c.category.contains('Pest') || c.category.contains('Poisoning')) {
        return {
          'authorityName': 'Ministry of Health (KKM) & DBKL Enforcement',
          'badgeLabel': 'Official Government Directive',
          'icon': Icons.gavel_rounded,
          'color': const Color(0xFF0F766E),
        };
      } else if (c.isFlaggedForReview || c.category.contains('Hygiene')) {
        return {
          'authorityName': 'System Administration Audit Division',
          'badgeLabel': 'Admin Audit Compliance Notice',
          'icon': Icons.admin_panel_settings_rounded,
          'color': const Color(0xFF0C2340),
        };
      } else {
        return {
          'authorityName': 'Public Hygiene Inspection Bureau',
          'badgeLabel': 'Verified Public Complaint Directive',
          'icon': Icons.report_problem_rounded,
          'color': const Color(0xFFD97706),
        };
      }
    }

    return {
      'authorityName': 'Ministry of Health (KKM)',
      'badgeLabel': 'Official Health Notice',
      'icon': Icons.gavel_rounded,
      'color': const Color(0xFF0F766E),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;

    ComplaintModel? initialComplaint;
    InspectionModel? initialInspection;

    if (args is InspectionModel) {
      initialInspection = args;
      initialComplaint = RestaurantStoreService.complaintsNotifier.value
          .where((c) => c.id == args.complaintId)
          .firstOrNull;
    } else if (args is ComplaintModel) {
      initialComplaint = args;
      initialInspection = RestaurantStoreService.inspectionsNotifier.value
          .where((i) => i.complaintId.isNotEmpty && (i.complaintId == args.id || i.complaintId.toLowerCase() == args.id.toLowerCase()),)
          .firstOrNull;
    } else if (RestaurantStoreService.complaintsNotifier.value.isNotEmpty) {
      final firstComp = RestaurantStoreService.complaintsNotifier.value.first;
      initialComplaint = firstComp;
      initialInspection = RestaurantStoreService.inspectionsNotifier.value
          .where((i) => i.complaintId.isNotEmpty && (i.complaintId == firstComp.id || i.complaintId.toLowerCase() == firstComp.id.toLowerCase()),)
          .firstOrNull;
    } else if (RestaurantStoreService.inspectionsNotifier.value.isNotEmpty) {
      initialInspection = RestaurantStoreService.inspectionsNotifier.value.first;
    }

    if (initialComplaint == null && initialInspection == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Notice & Directive Details'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.assignment_late_outlined, size: 48, color: Colors.grey,),
              const SizedBox(height: 12),
              const Text('No notice or directive details available.', style: TextStyle(color: Colors.grey),),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back'),),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        RestaurantStoreService.rectificationNotifier,
        RestaurantStoreService.complaintsNotifier,
      ]),
      builder: (context, child) {
        return ValueListenableBuilder<List<InspectionModel>>(
          valueListenable: RestaurantStoreService.inspectionsNotifier,
          builder: (context, allInspections, _) {
            return ValueListenableBuilder<List<RestaurantModel>>(
              valueListenable: RestaurantStoreService.restaurantsNotifier,
              builder: (context, allRestaurants, _) {
            final initInsp = initialInspection;
            final linkedComplaintId = initialComplaint?.id ?? initInsp?.complaintId;
            final inspection = (initInsp == null ? null : allInspections.where((i) => i.id == initInsp.id).firstOrNull) ??
                (linkedComplaintId == null || linkedComplaintId.isEmpty ? null :
                    allInspections.where((i) => i.complaintId == linkedComplaintId).firstOrNull) ?? initInsp;

            final initComp = initialComplaint;
            final complaint = initComp != null
                ? (RestaurantStoreService.complaintsNotifier.value.where((c) => c.id == initComp.id).firstOrNull ?? initComp)
                : null;

            // Resolve restaurant details
            final String restId = inspection?.restaurantId ?? (complaint?.restaurantId ?? '');
            final String restName = (inspection != null && inspection.restaurantName.isNotEmpty)
                ? inspection.restaurantName
                : (complaint?.restaurantName ?? 'Premises');

            final RestaurantModel? restaurant = allRestaurants
                .where((r) => r.id == restId || r.name.toLowerCase() == restName.toLowerCase(),)
                .firstOrNull;

            final double lat = restaurant?.latitude ?? (complaint?.latitude ?? 3.1475);
            final double lng = restaurant?.longitude ?? (complaint?.longitude ?? 101.7085);
            final String address = restaurant?.address ?? 'Premises Location';

            final authInfo = _getAuthorityInfo(c: complaint, insp: inspection,);
            final Color authColor = authInfo['color'];

            // Timeline & Fine calculation
            final bool isScheduled = inspection != null &&
                inspection.outcome == InspectionOutcome.pending &&
                (inspection.conductedDate == null || inspection.conductedDate!.isEmpty);
            final bool isClosure = (inspection?.issuedAction == EnforcementType.closure) || (restaurant?.isSuspended ?? false);
            final double fineAmt = inspection != null && inspection.fineAmount > 0
                ? inspection.fineAmount
                : (restaurant?.fineAmount ?? 0.0);

            final bool hasFine = fineAmt > 0;

            // Accurate Fine Paid State: Must be explicitly verified as paid
            bool isFinePaid = !hasFine;
            if (hasFine) {
              isFinePaid = (inspection?.isFinePaid == true) ||
                  RestaurantStoreService.isOutletFinePaid(
                    restaurant?.id ?? inspection?.restaurantId,
                    complaintId: complaint?.id ?? inspection?.complaintId,
                    inspectionId: inspection?.id,
                  );
            }

            final String noticeId = (inspection != null && inspection.complaintId.isNotEmpty)
                ? inspection.complaintId
                : (inspection != null ? inspection.id : (complaint?.id ?? 'CMP-2026'));
            final String formattedNoticeId = noticeId.startsWith('CMP-') || noticeId.startsWith('cmp_')
                ? noticeId.toUpperCase().replaceAll('_', '-')
                : 'CMP-${noticeId.length > 8 ? noticeId.substring(0, 8).toUpperCase() : noticeId.toUpperCase()}';

            final workflow = complaint == null
                ? null
                : (_workflow?.complaintId == complaint.id
                    ? _workflow
                    : WorkflowService.getCachedWorkflow(complaint.id));
            final deadline = workflow?.rectificationDeadline;
            final int daysLeft = deadline == null
                ? 7
                : (deadline.difference(DateTime.now().toUtc()).inSeconds /
                        Duration.secondsPerDay)
                    .ceil()
                    .clamp(0, 7)
                    .toInt();

            final bool isRectificationSubmitted = RestaurantStoreService.isRectificationSubmitted(
              restId,
              complaintId: complaint?.id ?? inspection?.complaintId,
              inspectionId: inspection?.id,
              noticeId: formattedNoticeId,
            );

            final bool isClosed = (inspection != null && inspection.enforcementStatus == EnforcementStatus.completed) ||
                RestaurantStoreService.isCaseClosed(
                  inspectionId: inspection?.id,
                  complaintId: complaint?.id ?? inspection?.complaintId,
                  noticeId: formattedNoticeId,
                ) || (complaint?.status == ComplaintStatus.resolved);

            final bool isAdminVerified = RestaurantStoreService.isRectificationAdminVerified(
              inspectionId: inspection?.id,
              complaintId: complaint?.id ?? inspection?.complaintId,
              restaurantId: restId,
              noticeId: formattedNoticeId,
            );

            final bool acceptedForOwnerAction = complaint != null &&
                !complaint.isFlaggedForReview &&
                complaint.status != ComplaintStatus.submitted &&
                complaint.status != ComplaintStatus.rejected &&
                complaint.status != ComplaintStatus.resolved;
            final bool ownerWindowActive =
                workflow?.isOwnerRectificationActive ?? acceptedForOwnerAction;
            final bool canSubmitRectification = ownerWindowActive &&
                !isRectificationSubmitted &&
                !isClosed &&
                !isScheduled &&
                daysLeft > 0;
            final bool ownerWindowExpired = !isRectificationSubmitted &&
                !isClosed &&
                (workflow?.isOfficerReviewPending == true ||
                    (deadline != null && daysLeft == 0));

            int currentStep = 3;
            String stepTitle = 'Action & Remediation Required';
            String latestNews = 'Formal statutory notice issued. Please complete required sanitization and submit evidence.';

            if (isScheduled) {
              currentStep = 2;
              stepTitle = 'Inspection Scheduled';
              latestNews = 'Field inspection scheduled for ${inspection.scheduledDate}. Health Officer ${inspection.officerName} will visit the premise.';
            } else if (isClosed) {
              currentStep = 4;
              stepTitle = 'Resolved & Compliant';
              latestNews = 'All corrective rectifications verified and penalties settled. Premise restored to full Grade A compliance.';
            } else if (canSubmitRectification) {
              currentStep = 3;
              stepTitle = 'Action Required ($daysLeft-Day Window)';
              latestNews = 'Submit corrective-action photos before the deadline. Payment is only applicable after enforcement is issued.';
            } else if (ownerWindowExpired) {
              currentStep = 3;
              stepTitle = 'Owner Window Expired';
              latestNews = 'The 7-day evidence window has expired. A Health Officer can now manually schedule an inspection.';
            } else if (!isFinePaid && hasFine && isRectificationSubmitted) {
              currentStep = 3;
              stepTitle = 'Fine Outstanding';
              latestNews = isRectificationSubmitted
                  ? 'Rectification submitted. Please settle MOH Compound Penalty of RM ${fineAmt.toStringAsFixed(2)} via FPX to complete compliance.'
                  : 'MOH Compound Penalty of RM ${fineAmt.toStringAsFixed(2)} is outstanding. Please settle compound via FPX.';
            } else if (isRectificationSubmitted) {
              currentStep = 3;
              if (isAdminVerified) {
                stepTitle = 'Admin Endorsed';
                latestNews = 'Improvement proof verified by Admin. Awaiting Health Officer statutory case closure decree.';
              } else {
                stepTitle = 'Proof Under Review';
                latestNews = 'Corrective action proof submitted. Pending Government Admin audit verification.';
              }
            } else if (isClosure) {
              currentStep = 3;
              stepTitle = 'Premise Closure in Effect';
              latestNews = 'Closure order in effect. Please complete sanitization and submit rectification proof.';
            } else if (inspection != null) {
              currentStep = 3;
              stepTitle = 'Action & Remediation Required';
              latestNews = 'Statutory notice issued by Health Officer. Please complete required sanitization and rectify violations.';
            } else if (complaint != null) {
              if (complaint.status == ComplaintStatus.submitted || (complaint.status == ComplaintStatus.underReview && complaint.isFlaggedForReview)) {
                currentStep = 1;
                stepTitle = 'Notice Received';
                latestNews = 'Official incident notice logged. Health authorities are reviewing verification scan.';
              } else if (complaint.status == ComplaintStatus.underReview ||
                  complaint.status == ComplaintStatus.investigating ||
                  complaint.status == ComplaintStatus.inspecting ||
                  complaint.status == ComplaintStatus.pendingInspection) {
                currentStep = 3;
                stepTitle = 'Action Required (7-Day Window)';
                latestNews = '7-Day Statutory Rectification Window Active. Please carry out corrective measures and submit evidence.';
              } else if (complaint.status == ComplaintStatus.resolved) {
                currentStep = 4;
                stepTitle = 'Resolved & Compliant';
                latestNews = 'Statutory case resolved and verified compliant.';
              } else if (complaint.status == ComplaintStatus.rejected) {
                currentStep = 4;
                stepTitle = 'Rejected / Duplicate';
                latestNews = 'Report flagged as duplicate or invalid evidence. Case dismissed.';
              }
            }

            final String actionTitle = isScheduled
                ? '📅 Scheduled MOH Field Inspection'
                : (isClosure
                    ? 'MOH Premise Closure Order (7 Days)'
                    : (fineAmt > 0
                        ? 'MOH Statutory Compound: RM ${fineAmt.toStringAsFixed(2)}'
                        : (inspection?.issuedAction == EnforcementType.warning
                            ? 'MOH Form 32 Health Warning Directive'
                            : (complaint != null ? 'Public Health Notice (${complaint.category})' : 'MOH Statutory Decree'))));


            final String statutoryCitation = inspection?.statutoryCitation ??
                (restaurant?.statutoryCitation ?? 'Food Act 1983 - Section 11 (Hygiene Non-Compliance)');
            final String officerName = (inspection != null && inspection.officerName.isNotEmpty)
                ? inspection.officerName
                : 'Assigned Senior Health Officer';
            final String findings = (inspection != null && inspection.findings.isNotEmpty)
                ? inspection.findings
                : (complaint?.description ?? 'Unsanitary conditions detected requiring immediate sanitation.');
            final List<String> issuesList = (complaint != null && complaint.issues.isNotEmpty)
                ? complaint.issues
                : (inspection?.findings.split('. ').where((s) => s.trim().isNotEmpty).toList() ??
                    ['Unsanitary food storage', 'Pest control remediation required',]);

            // 1. Customer Complaint Media
            final List<String> customerPhotos = (complaint != null && complaint.photoUrls.isNotEmpty)
                ? complaint.photoUrls.where((p) => p.trim().isNotEmpty).toList()
                : [];

            // 2. Restaurant Owner Rectification Evidence
            final RectificationModel? rectificationRecord = RestaurantStoreService.getRectificationRecord(
              complaintId: complaint?.id ?? inspection?.complaintId,
              inspectionId: inspection?.id,
              noticeId: formattedNoticeId,
              restaurantId: restId,
            );
            final List<String> ownerPhotos = (rectificationRecord != null && rectificationRecord.photoUrls.isNotEmpty)
                ? rectificationRecord.photoUrls.where((p) => p.trim().isNotEmpty).toList()
                : [];

            // 3. Health Officer On-Site Inspection Media
            final List<String> officerPhotos = (inspection != null && inspection.photoUrls.isNotEmpty)
                ? inspection.photoUrls.where((p) => p.trim().isNotEmpty).toList()
                : [];

            final int totalMediaCount = customerPhotos.length + ownerPhotos.length + officerPhotos.length;

            return Scaffold(
              backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
              appBar: const CustomAppBar(title: 'Notice & Directive Details',),
              body: SafeArea(
                    top: false,
                    bottom: true,
                    child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. ISSUING AUTHORITY BANNER CARD
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: authColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: authColor.withValues(alpha: 0.3),),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: authColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(authInfo['icon'], color: Colors.white, size: 24,),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  authInfo['badgeLabel'],
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: authColor,),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  authInfo['authorityName'],
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor,),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. PREMISE NAME & DEADLINE
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Restaurant: $restName',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor,),
                          ),
                        ),
                        DeadlineCountdownBadge(daysLeft: daysLeft),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4,),
                          decoration: BoxDecoration(
                            color: isClosure
                                ? const Color(0xFFFEE2E2)
                                : (isScheduled ? const Color(0xFFE0F2FE) : (hasFine && !isFinePaid ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7))),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isClosure ? 'Closure Notice' : (isScheduled ? 'Scheduled Visit' : (hasFine && !isFinePaid ? 'Fine Outstanding' : (fineAmt > 0 ? 'Compound Settled' : 'Warning Notice'))),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isClosure ? const Color(0xFFDC2626) : (isScheduled ? const Color(0xFF0284C7) : (hasFine && !isFinePaid ? const Color(0xFFDC2626) : const Color(0xFFD97706))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Directive ID: $formattedNoticeId',
                            style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600,),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. STEP PROGRESS TIMELINE
                    _buildNoticeStepProgressTimeline(
                      currentStep: currentStep,
                      stepTitle: stepTitle,
                      latestNews: latestNews,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    OwnerComplianceChecklist(submitted: isRectificationSubmitted, reviewed: isAdminVerified,
                      closed: isClosed, hasFine: hasFine, paid: isFinePaid,
                      canSubmit: canSubmitRectification, scheduled: isScheduled, expired: ownerWindowExpired),
                    const SizedBox(height: 16),

                    // 4. STATUTORY DIRECTIVES & DETAILS CARD
                    Card(
                      elevation: 0,
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200,),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.gavel_rounded, size: 18, color: authColor,),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    actionTitle,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: authColor,),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),

                            _buildInfoRow(
                              icon: Icons.article_outlined,
                              label: 'Statutory Citation',
                              value: statutoryCitation,
                              valueColor: const Color(0xFF0F766E),
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              icon: Icons.badge_outlined,
                              label: 'Assigned Health Officer',
                              value: officerName,
                              valueColor: isDark ? Colors.white : AppTheme.navyColor,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (inspection != null && inspection.scheduledDate.isNotEmpty) ...[
                              _buildInfoRow(
                                icon: Icons.calendar_today_outlined,
                                label: 'Scheduled Date',
                                value: inspection.scheduledDate,
                                valueColor: const Color(0xFF0284C7),
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
                            ],
                            if ((inspection != null && inspection.issuedDate != null && inspection.issuedDate!.isNotEmpty) ||
                                (restaurant != null && restaurant.fineIssuedDate != null && restaurant.fineIssuedDate!.isNotEmpty)) ...[
                              _buildInfoRow(
                                icon: Icons.event_available_outlined,
                                label: 'Issued Date',
                                value: inspection?.issuedDate ?? (restaurant?.fineIssuedDate ?? '2026-08-25'),
                                valueColor: isDark ? Colors.white70 : Colors.grey.shade700,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
                            ],
                            _buildInfoRow(
                              icon: Icons.timer_outlined,
                              label: 'Compliance Deadline',
                              value: inspection?.dueDate ?? (restaurant?.fineDueDate ?? '7 Days from issuance'),
                              valueColor: const Color(0xFFDC2626),
                              isDark: isDark,
                            ),


                            const Divider(height: 20),

                            Text(
                              'Official Findings & Violation Reasons:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : AppTheme.navyColor,),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200,),
                              ),
                              child: Text(
                                findings,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade800, height: 1.4,),
                              ),
                            ),
                            const SizedBox(height: 12),

                            Text(
                              'Mandatory Directives Flagged:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : AppTheme.navyColor,),
                            ),
                            const SizedBox(height: 6),
                            ...issuesList.map((iss) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(Icons.error_outline_rounded, size: 14, color: Colors.red,),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          iss,
                                          style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87,),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5. PROOF MEDIA & INSPECTION LOGS (3 CATEGORIES: CUSTOMER, OWNER, OFFICER)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF181818) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.perm_media_rounded, size: 18, color: authColor,),
                                  const SizedBox(width: 8),
                                    Expanded(
                                      child:
                                  Text(
                                    'Proof Media & Inspection Logs',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : AppTheme.navyColor,),
                                  ),
                                    ),
                                    const SizedBox(width: 8
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5,),
                                decoration: BoxDecoration(
                                  color: authColor.withValues(alpha: 0.12,),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: authColor.withValues(alpha: 0.25,),),
                                ),
                                child: Text(
                                  '$totalMediaCount Total Photo${totalMediaCount != 1 ? "s" : ""}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: authColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Evidence records categorized across customer report, restaurant improvement, and officer on-site inspection.',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600,),
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
                          ),

                          // CATEGORY 2: Restaurant Owner Evidence
                          _buildCategoryMediaBlock(
                            context: context,
                            categoryTitle: '2. Restaurant Owner Improvement Evidence',
                            categorySubtitle: 'Improvement & cleaning photos submitted by restaurant management.',
                            icon: Icons.storefront_rounded,
                            accentColor: const Color(0xFF0F766E),
                            photos: ownerPhotos,
                            tagPrefix: 'Owner Fix',
                            emptyMessage: isRectificationSubmitted
                                ? 'Owner submitted improvement statement (no additional photos attached).'
                                : 'No owner improvement photos submitted yet. Upload proof via the button below.',
                            extraNotes: rectificationRecord != null && rectificationRecord.notes.isNotEmpty ? rectificationRecord.notes : null,
                            isDark: isDark,
                          ),

                          // CATEGORY 3: Officer Inspection Record Media
                          _buildCategoryMediaBlock(
                            context: context,
                            categoryTitle: '3. Officer Inspection Record Media',
                            categorySubtitle: 'On-site physical inspection evidence logged by ${inspection?.officerName ?? "Health Inspector (KKM)"}.',
                            icon: Icons.policy_rounded,
                            accentColor: const Color(0xFF0284C7),
                            photos: officerPhotos,
                            tagPrefix: 'Officer Audit',
                            emptyMessage: isScheduled
                                ? 'Pending on-site visit scheduled for ${inspection.scheduledDate}. Officer photos will appear here after audit.'
                                : 'No on-site officer inspection photos logged yet.',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 6. GPS LOCATION (LOCKED PREVIEW MAP)
                    Text(
                      'Inspection Pin Map Location',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : AppTheme.navyColor,),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300,),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            IgnorePointer(
                              ignoring: true,
                              child: GoogleMap(
                                style: AppMapTheme.getMapStyle(isDark),
                                onMapCreated: (ctrl) => AppMapTheme.applyTheme(ctrl, isDark),
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(lat, lng),
                                  zoom: 16.0,
                                ),
                                markers: {
                                  Marker(
                                    markerId: MarkerId(formattedNoticeId),
                                    position: LatLng(lat, lng),
                                    infoWindow: InfoWindow(
                                      title: 'Restaurant: $restName',
                                      snippet: address,
                                    ),
                                  ),
                                },
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                mapToolbarEnabled: false,
                                compassEnabled: false,
                                scrollGesturesEnabled: false,
                                zoomGesturesEnabled: false,
                                rotateGesturesEnabled: false,
                                tiltGesturesEnabled: false,
                              ),
                            ),
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7,),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white.withValues(alpha: 0.95,),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200,),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.1,), blurRadius: 4,),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: AppTheme.primaryColor, size: 16,),
                                    const SizedBox(width: 6),
                                    Text(
                                      'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : AppTheme.navyColor,),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 7. MOH COMPOUND PENALTY CARD (Warning / Error Card if Unpaid, Green Card if Settled)
                    if (fineAmt > 0 && isRectificationSubmitted) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isFinePaid
                              ? (isDark ? const Color(0xFF064E3B,).withValues(alpha: 0.3) : const Color(0xFFECFDF5))
                              : (isDark ? const Color(0xFF450A0A,).withValues(alpha: 0.4) : const Color(0xFFFEF2F2)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isFinePaid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            width: 1.8,
                          ),
                          boxShadow: isFinePaid
                              ? null
                              : [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444,).withValues(alpha: 0.15),
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
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isFinePaid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isFinePaid ? Icons.check_rounded : Icons.priority_high_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          isFinePaid ? 'Compound Penalty Settled' : 'Statutory Fine Outstanding',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isFinePaid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'RM ${fineAmt.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: isFinePaid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isFinePaid
                                  ? 'Official clearance confirmed. Penalty fine settled and business active.'
                                  : 'Official fine issued under Food Act 1983 / Food Hygiene Regulations 2009. Please settle this fine via FPX before uploading fix proof.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isFinePaid ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                                height: 1.35,
                              ),
                            ),
                            if (isFinePaid) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F766E,),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 11,),
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),),
                                      ),
                                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 16,),
                                      label: const Text(
                                        'Download PDF Invoice',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,),
                                      ),
                                      onPressed: () {
                                        final invNumber = 'MOH-INV-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                                        PdfInvoiceService.downloadOrPrintInvoice(
                                          invoiceNumber: invNumber,
                                          paymentReference: 'pi_settled_statutory',
                                          chargeId: null,
                                          restaurantName: restName,
                                          ownerName: restaurant?.ownerName ?? 'Premises Licensee',
                                          premiseAddress: address,
                                          statutoryCitation: statutoryCitation,
                                          amountPaid: fineAmt,
                                          settledAt: DateTime.now().toLocal().toString().split('.').first,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF6366F1,),
                                      side: const BorderSide(color: Color(0xFF6366F1), width: 1.2,),
                                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12,),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),),
                                    ),
                                    icon: const Icon(Icons.open_in_browser_rounded, size: 16,),
                                    label: const Text(
                                      'Stripe Receipt',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,),
                                    ),
                                    onPressed: () {
                                      StripePaymentService.openUrl('https://dashboard.stripe.com/test/payments',);
                                    },
                                  ),
                                ],
                              ),
                            ],
                            if (!isFinePaid) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626,),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12,),
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12,),),
                                  ),
                                  onPressed: () {
                                    final targetR = restaurant ??
                                        RestaurantModel(
                                          id: restId,
                                          name: restName,
                                          category: 'Restaurant',
                                          address: address,
                                          latitude: lat,
                                          longitude: lng,
                                          hygieneRiskScore: 70.0,
                                          riskCategory: RiskCategory.high,
                                          imageUrl: '',
                                          lastUpdated: '',
                                          status: RestaurantStatus.approved,
                                          violationCount: 1,
                                          fineAmount: fineAmt,
                                          isFinePaid: false,
                                        );
                                    showMOHPaymentGatewayModal(
                                      context,
                                      restaurant: targetR,
                                      fineAmount: fineAmt,
                                      inspection: inspection,
                                      citation: statutoryCitation,
                                    );
                                  },
                                  icon: const Icon(Icons.payment_rounded, size: 18,),
                                  label: Text(
                                    'Settle Penalty via FPX / Card (RM ${fineAmt.toStringAsFixed(2)})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13,),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // 8. FINAL STATUS & RESOLUTION CERTIFICATE
                    if (isClosed) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16,),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669,).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF059669,).withValues(alpha: 0.3),),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 20,),
                            SizedBox(width: 8),
                            Text(
                              'Completed (Case Closed & Resolved)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.finalReport,
                              arguments: complaint,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14,),
                            side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFF059669), width: 1.2,),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),),
                          ),
                          icon: const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF059669),),
                          label: const Text(
                            'View Official Compliance Certificate',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ),
                    ] else if (canSubmitRectification && complaint != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final submitted = await Navigator.pushNamed(
                              context,
                              AppRoutes.markIssueResolved,
                              arguments: complaint,
                            );
                            if (submitted == true && context.mounted) {
                              await RestaurantStoreService.syncRectificationsFromStorage();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.upload_file_rounded, size: 19),
                          label: Text(
                            'Upload Improvement Evidence ($daysLeft Day${daysLeft == 1 ? '' : 's'} Left)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ] else if (ownerWindowExpired) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          '7-Day Window Expired • Awaiting Health Officer Scheduling',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                        ),
                      ),
                    ] else if (isRectificationSubmitted) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16,),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E,).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0F766E,).withValues(alpha: 0.3),),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.hourglass_top_rounded, color: Color(0xFF0F766E), size: 18,),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Evidence Submitted',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                  ],
                      ),
                ),
              ),
              );
            },
          );
        },
      );
    },
  );
}

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: isDark ? Colors.white54 : Colors.grey.shade500,),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade700,),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: valueColor,),
          ),
        ),
      ],
    );
  }

  Widget _buildNoticeStepProgressTimeline({
    required int currentStep,
    required String stepTitle,
    required String latestNews,
    required bool isDark,
  }) {
    final steps = [
      {'num': 1, 'label': '1. Logged'},
      {'num': 2, 'label': '2. Review'},
      {'num': 3, 'label': '3. Action'},
      {'num': 4, 'label': '4. Resolved'},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline_rounded, size: 14, color: isDark ? Colors.white70 : const Color(0xFF0F766E),),
                  const SizedBox(width: 6),
                  Text(
                    'Step Progress',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor,),
                  ),
                ],
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2,),
                  decoration: BoxDecoration(
                    color: (currentStep == 4 ? const Color(0xFF10B981) : const Color(0xFF0F766E)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Step $currentStep of 4: $stepTitle',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: currentStep == 4 ? const Color(0xFF059669) : const Color(0xFF0F766E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4-Step Animated Smooth Stepper Bar with Balanced Labels
          LayoutBuilder(
            builder: (context, constraints) {
              final double totalWidth = constraints.maxWidth;
              const double nodeSize = 24.0;
              final double slotWidth = totalWidth / 4.0;
              final double halfSlot = slotWidth * 0.5;
              final double trackWidth = totalWidth - slotWidth;
              final double targetFactor = ((currentStep.clamp(1, 4) - 1) / 3.0).clamp(0.0, 1.0);

              return Stack(
                children: [
                  // 1. Inactive Background Track (Starts at Center of Node 1, Ends at Center of Node 4)
                  Positioned(
                    left: halfSlot,
                    right: halfSlot,
                    top: (nodeSize / 2) - 1.5,
                    child: Container(
                      height: 3.0,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),

                  // 2. Animated Active Gradient Fill Track
                  Positioned(
                    left: halfSlot,
                    top: (nodeSize / 2) - 1.5,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeInOutCubic,
                      tween: Tween<double>(begin: 0.0, end: targetFactor),
                      builder: (context, factor, child) {
                        return Container(
                          width: trackWidth * factor,
                          height: 3.0,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F766E), Color(0xFF059669)],
                            ),
                            borderRadius: BorderRadius.circular(1.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF059669,).withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // 3. Milestone Interactive Nodes & Step Labels
                  Row(
                    children: List.generate(4, (index) {
                      final stepNum = index + 1;
                      final isPassed = stepNum < currentStep || (stepNum == 4 && currentStep >= 4);
                      final isCurrent = stepNum == currentStep && currentStep < 4;
                      final label = steps[index]['label'] as String;

                      Color nodeBgColor;
                      Color nodeBorderColor;
                      if (isPassed) {
                        nodeBgColor = const Color(0xFF059669);
                        nodeBorderColor = const Color(0xFF059669);
                      } else if (isCurrent) {
                        nodeBgColor = const Color(0xFF0F766E);
                        nodeBorderColor = const Color(0xFF0F766E);
                      } else {
                        nodeBgColor = isDark ? const Color(0xFF262626) : Colors.white;
                        nodeBorderColor = isDark ? Colors.white24 : const Color(0xFFCBD5E1);
                      }

                      return Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Node Circle
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                              width: nodeSize,
                              height: nodeSize,
                              decoration: BoxDecoration(
                                color: nodeBgColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: nodeBorderColor,
                                  width: isCurrent ? 2.2 : 1.6,
                                ),
                                boxShadow: (isPassed || isCurrent)
                                    ? [
                                        BoxShadow(
                                          color: nodeBgColor.withValues(alpha: 0.3,),
                                          blurRadius: 5,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: isPassed
                                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white,)
                                    : Text(
                                        '$stepNum',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent
                                              ? Colors.white
                                              : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Symmetrically Centered Step Label
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: (isCurrent || isPassed) ? FontWeight.bold : FontWeight.w500,
                                color: (isCurrent || isPassed)
                                    ? (isDark ? Colors.white70 : const Color(0xFF334155))
                                    : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          // Latest News Notice Banner
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222222) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200,),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.campaign_rounded, size: 14, color: Color(0xFF0284C7),),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    latestNews,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.3,),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  categoryTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0C2340),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5,),
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
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600,),
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
                      'Note: $extraNotes',
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
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),),
              ),
              child: Row(
                children: [
                  Icon(Icons.no_photography_outlined, size: 16, color: isDark ? Colors.white38 : Colors.grey.shade400,),
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
                      onTap: () {
                        _showFullImageViewer(
                          context,
                          path,
                          '$categoryTitle • $tagPrefix #${idx + 1}',
                          isDark,
                        );
                      },
                      child: Container(
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: accentColor.withValues(alpha: 0.25),),
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
                              _buildImageWidget(path),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6,),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent,],
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$tagPrefix #${idx + 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold,),
                                      ),
                                      const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14,),
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

  Widget _buildImageWidget(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => Container(
          color: Colors.grey.shade800,
          child: const Center(
            child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.white54,),
          ),
        ),
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
      final f = File(cleanPath);
      if (f.existsSync()) {
        return Image.file(
          f,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => Container(
            color: Colors.grey.shade800,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.white54,),
            ),
          ),
        );
      } else {
        return Container(
          color: Colors.grey.shade800,
          child: const Center(
            child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.white54,),
          ),
        );
      }
    }
  }

  void _showFullImageViewer(BuildContext context, String path, String title, bool isDark,) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24,),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12,),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16),),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF0F766E),),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16),),
                child: SizedBox(
                  height: 360,
                  width: double.infinity,
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: _buildImageWidget(path),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
