import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/rectification_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/status_badge.dart';

class ComplaintFullDetailScreen extends StatefulWidget {
  const ComplaintFullDetailScreen({super.key});

  @override
  State<ComplaintFullDetailScreen> createState() => _ComplaintFullDetailScreenState();
}

class _ComplaintFullDetailScreenState extends State<ComplaintFullDetailScreen> {
  bool _isMapLoading = true;

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_')) {
      return rawId.toUpperCase();
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
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

  Widget _buildEvidenceImage(String path, {double height = 200, double width = double.infinity, BoxFit fit = BoxFit.cover}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            width: width,
            color: Colors.grey.shade100,
            child: const Center(
              child: DualArcLoader(size: 24, strokeWidth: 2, color: AppTheme.primaryColor),
            ),
          );
        },
        errorBuilder: (ctx, error, stackTrace) => _buildFallbackEvidencePlaceholder(height, width),
      );
    } else if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (ctx, error, stackTrace) => _buildFallbackEvidencePlaceholder(height, width),
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
          width: width,
          fit: fit,
          errorBuilder: (ctx, error, stackTrace) => _buildFallbackEvidencePlaceholder(height, width),
        );
      } else {
        return _buildFallbackEvidencePlaceholder(height, width);
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
          Icon(Icons.photo_library_outlined, size: 36, color: Color(0xFF94A3B8)),
          SizedBox(height: 6),
          Text(
            'Verified Evidence Photo',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
          ),
          SizedBox(height: 2),
          Text(
            'Attached during hygiene complaint submission',
            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
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

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    ComplaintModel? c;
    if (args is ComplaintModel) {
      c = ComplaintStoreService.complaintsNotifier.value.where((x) => x.id == args.id).firstOrNull ?? args;
    } else if (ComplaintStoreService.complaintsNotifier.value.isNotEmpty) {
      c = ComplaintStoreService.complaintsNotifier.value.first;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (c == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Case Details'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No complaint details available.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    final complaint = c;
    final formattedId = _formatCaseId(complaint.id);
    final restName = RestaurantStoreService.resolveRestaurantName(complaint.restaurantName, fallback: complaint.restaurantName);
    final allInspections = RestaurantStoreService.inspectionsNotifier.value;
    final matchingInspections = allInspections.where((insp) {
      final isDirectComp = insp.id == complaint.id ||
          insp.complaintId == complaint.id ||
          (insp.complaintId.isNotEmpty &&
              insp.complaintId.toLowerCase().trim() ==
                  complaint.id.toLowerCase().trim());
      return isDirectComp;
    }).toList();
    matchingInspections.sort(CaseOrdering.inspections);

    final linkedInsp = matchingInspections.firstOrNull;
    final closedInspection =
        linkedInsp?.enforcementStatus == EnforcementStatus.completed
            ? linkedInsp
            : null;
    final bool isCaseClosed =
        linkedInsp?.enforcementStatus == EnforcementStatus.completed ||
        complaint.status == ComplaintStatus.resolved;

    // 1. Customer Complaint Media
    final List<String> customerPhotos = complaint.photoUrls.where((p) => p.trim().isNotEmpty).toList();

    // 2. Restaurant Owner Rectification Evidence
    final RectificationModel? rectificationRecord = RestaurantStoreService.getRectificationRecord(
      complaintId: complaint.id,
      inspectionId: linkedInsp?.id,
      restaurantId: complaint.restaurantId,
    );
    final List<String> ownerPhotos = (rectificationRecord != null && rectificationRecord.photoUrls.isNotEmpty)
        ? rectificationRecord.photoUrls.where((p) => p.trim().isNotEmpty).toList()
        : [];

    // 3. Officer Inspection Record Media
    final List<String> officerPhotos = (linkedInsp != null && linkedInsp.photoUrls.isNotEmpty)
        ? linkedInsp.photoUrls.where((p) => p.trim().isNotEmpty).toList()
        : [];

    final int totalMediaCount = customerPhotos.length + ownerPhotos.length + officerPhotos.length;

    // Check if visit is already scheduled
    final bool isScheduled = !((linkedInsp?.requiresReschedule) ?? false) &&
        ((linkedInsp != null && linkedInsp.scheduledDate.isNotEmpty && linkedInsp.outcome == InspectionOutcome.pending) ||
        complaint.status == ComplaintStatus.pendingInspection ||
        complaint.status == ComplaintStatus.inspecting);

    // Check if on-site visit was conducted
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

    final bool isDecreePending = isVisitConducted &&
        isAdminApproved &&
        ((linkedInsp.issuedDate == null || linkedInsp.issuedDate!.isEmpty || linkedInsp.issuedDate == 'null') &&
            linkedInsp.issuedAction == EnforcementType.none);

    // Check if owner has submitted improvement evidence
    final bool isOwnerEvidenceSubmitted = RestaurantStoreService.isRectificationSubmitted(
      complaint.restaurantId,
      complaintId: complaint.id,
      inspectionId: linkedInsp?.id,
    );

    // Compute remaining days in 7-day statutory rectification window
    int daysPassed = 0;
    int daysRemaining = 7;
    try {
      final subDt = DateTime.parse(complaint.submittedAt);
      final now = DateTime.now();
      daysPassed = now.difference(subDt).inDays;
      daysRemaining = (7 - daysPassed).clamp(0, 7);
    } catch (_) {}

    final bool is7DaysExpired = daysPassed >= 7;
    final bool canScheduleVisit = isOwnerEvidenceSubmitted || is7DaysExpired;


    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Case Details'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP CASE ID & STATUS BANNER CARD
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      StatusBadge.fromStatus(isCaseClosed ? 'Resolved' : c.status.name, isOnDark: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.category_outlined, size: 12, color: Colors.white.withValues(alpha: 0.9)),
                            const SizedBox(width: 4),
                            Text(
                              c.category,
                              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatTimestamp(c.submittedAt),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. DETAILED DESCRIPTION CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
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
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.description_outlined, color: Color(0xFF0F766E), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Complaint Description',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      c.description.isNotEmpty ? c.description : 'No additional description provided.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isDark ? Colors.white70 : const Color(0xFF282828),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. PROOF MEDIA & INSPECTION LOGS (3 CATEGORIES: CUSTOMER, OWNER, OFFICER)
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
                    caseId: formattedId,
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
                        : 'No owner rectification photos submitted yet ($daysRemaining days remaining in window).',
                    extraNotes: rectificationRecord?.notes.isNotEmpty == true ? rectificationRecord!.notes : null,
                    isDark: isDark,
                    caseId: formattedId,
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
                    emptyMessage: isScheduled
                        ? 'Pending on-site visit scheduled for ${linkedInsp?.scheduledDate}. Photos will appear after audit.'
                        : 'No on-site officer inspection photos logged yet.',
                    isDark: isDark,
                    caseId: formattedId,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. ATTACHED GPS LOCATION MAP CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.location_on_rounded, color: Color(0xFF0284C7), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Attached GPS Location',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Embedded Google Map Preview (Non-interactive Static View)
                  Container(
                    height: 170,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          IgnorePointer(
                            ignoring: true,
                            child: GoogleMap(
                              style: AppMapTheme.getMapStyle(isDark),
                              initialCameraPosition: CameraPosition(
                                target: LatLng(c.latitude, c.longitude),
                                zoom: 15.5,
                              ),
                              markers: {
                                Marker(
                                  markerId: MarkerId(c.id),
                                  position: LatLng(c.latitude, c.longitude),
                                  infoWindow: InfoWindow(
                                    title: restName,
                                    snippet: 'Reported GPS coordinates for ${c.category}',
                                  ),
                                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                                ),
                              },
                              onMapCreated: (ctrl) {
                                AppMapTheme.applyTheme(ctrl, isDark);
                                if (mounted) setState(() => _isMapLoading = false);
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
                          if (_isMapLoading)
                            Container(
                              color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                              child: const Center(
                                child: DualArcLoader(size: 24, strokeWidth: 2, color: AppTheme.primaryColor),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 11),
                                  SizedBox(width: 4),
                                  Text(
                                    'GPS Preview',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
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

            const SizedBox(height: 24),

            // 5. INSPECTOR ACTION BUTTONS (DYNAMICALLY ADAPTED BASED ON PROGRESSION STAGE)
            if (isCaseClosed) ...[
              // STAGE 5: CASE STATUTORILY CLOSED & ARCHIVED
              CustomButton(
                label: 'View Case Closure & Action History',
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
                  icon: Icon(Icons.gavel_rounded, size: 18, color: isDark ? Colors.white70 : const Color(0xFF0F766E)),
                  label: Text(
                    'All Enforcement Decrees Archive',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F766E),
                    ),
                  ),
                ),
              ),
            ] else if (isVisitConducted) ...[
              // STAGE 3 & 4: VISIT CONDUCTED ON-SITE
              if (!isAdminApproved) ...[
                // STAGE 3: Visit recorded, awaiting Admin review & endorsement
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.rate_review_rounded, color: Color(0xFF4F46E5), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Inspection Report Filed • Awaiting Admin Approval',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Color(0xFF3730A3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Field inspection recorded on ${linkedInsp.conductedDate ?? "Today"}. Findings have been forwarded to Government Admin for approval.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                CustomButton(
                  label: 'Inspection Report Under Review',
                  icon: Icons.hourglass_top_rounded,
                  backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                  onPressed: () {
                    HygieneFeedback.showWarning(
                      context,
                      'This inspection report is currently under review by Government Admin.',
                    );
                  },
                ),
              ] else if (isDecreePending) ...[
                // STAGE 4: Admin Approved, Ready for Officer to Issue Action/Notice
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF022C22) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Approval Verified • Ready to Issue Action',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Color(0xFF065F46),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Government Admin has verified and approved the inspection report. Please proceed to issue the official penalty or notice.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF047857),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                CustomButton(
                  label: 'Issue Action & Notice',
                  icon: Icons.gavel_rounded,
                  backgroundColor: const Color(0xFFDC2626),
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.issueEnforcementDetail,
                      arguments: linkedInsp,
                    );
                  },
                ),
              ] else ...[
                // STAGE 4.5: Action Active
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.gavel_rounded, color: Color(0xFF0F766E), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enforcement Action Active: ${linkedInsp.issuedAction.name.toUpperCase()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isDark ? Colors.white : const Color(0xFF0C2340),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Action issued on ${linkedInsp.issuedDate ?? "Recent Date"}. Fine: RM ${linkedInsp.fineAmount.toStringAsFixed(2)}. Case will qualify for closure once fine is settled & restaurant improvement verified.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (ctx) {
                    final bool isFinePaid = linkedInsp.fineAmount <= 0 ||
                        (RestaurantStoreService.isOutletFinePaid(
                              linkedInsp.restaurantId,
                              restaurantName: linkedInsp.restaurantName,
                              complaintId: linkedInsp.complaintId,
                              inspectionId: linkedInsp.id,
                            ) ||
                            (linkedInsp.isFinePaid && linkedInsp.enforcementStatus == EnforcementStatus.completed));

                    if (!isFinePaid) {
                      return CustomButton(
                        label: 'Close Case Details (Fine Payment Pending)',
                        icon: Icons.lock_clock_rounded,
                        backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                        textColor: Colors.white,
                        onPressed: () {
                          showDialog(
                            context: ctx,
                            builder: (dCtx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Row(
                                children: [
                                  Icon(Icons.lock_clock_rounded, color: Color(0xFFD97706), size: 22),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Fine Payment Pending', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                                ],
                              ),
                              content: Text(
                                'The premise owner has not settled the compound fine of RM ${linkedInsp.fineAmount.toStringAsFixed(2)} yet. Case closure details will unlock once the payment is completed and improvement proof is verified.',
                                style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87, height: 1.35),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dCtx),
                                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }

                    return CustomButton(
                      label: 'View Enforcement & Case Details',
                      icon: Icons.assignment_outlined,
                      backgroundColor: const Color(0xFF0F766E),
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.closeCaseDetail,
                          arguments: linkedInsp,
                        );
                      },
                    );
                  },
                ),
              ],
            ] else if (!isScheduled) ...[
              // STAGE 1: VISIT NOT SCHEDULED YET -> SHOW 7-DAY RECTIFICATION STATUS & SCHEDULE VISIT
              if (!canScheduleVisit) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A1B00) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.amber.shade700 : const Color(0xFFFDE68A),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '7-Day Owner Fix Window Active',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Waiting for restaurant owner to submit improvement evidence ($daysRemaining days remaining) or until the 7-day period expires before scheduling an inspection visit.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.amber.shade200 : const Color(0xFF78350F),
                                height: 1.35,
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
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF063327) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isOwnerEvidenceSubmitted ? Icons.check_circle_rounded : Icons.timer_off_rounded,
                        color: const Color(0xFF059669),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOwnerEvidenceSubmitted
                                  ? 'Owner Rectification Proof Submitted'
                                  : '7-Day Rectification Period Concluded',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Color(0xFF065F46),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOwnerEvidenceSubmitted
                                  ? 'The restaurant owner has submitted improvement evidence. You may now schedule the statutory on-site inspection visit.'
                                  : 'The 7-day rectification period has concluded without owner proof. You may now schedule the statutory on-site inspection visit.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF047857),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              CustomButton(
                label: canScheduleVisit ? 'Schedule Visit' : 'Schedule Visit (Waiting for Owner / 7 Days)',
                icon: canScheduleVisit ? Icons.edit_calendar_rounded : Icons.hourglass_top_rounded,
                backgroundColor: canScheduleVisit ? const Color(0xFF00A88F) : (isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E)),
                onPressed: () {
                  if (!canScheduleVisit) {
                    HygieneFeedback.showWarning(
                      context,
                      'Statutory wait active: Please wait for restaurant owner evidence or until the 7-day rectification period ends ($daysRemaining days remaining).',
                    );
                    return;
                  }
                  Navigator.pushNamed(
                    context,
                    AppRoutes.scheduleInspection,
                    arguments: c,
                  );
                },
              ),
            ] else ...[
              // STAGE 2: VISIT IS SCHEDULED -> SHOW SCHEDULED CARD & UNLOCK RECORD VISIT
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0A2E2B) : const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF0F766E) : const Color(0xFF99F6E4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.event_available_rounded, color: Color(0xFF0F766E), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Statutory Field Inspection Scheduled',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: Color(0xFF115E59),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Inspection appointment set for ${linkedInsp?.scheduledDate ?? "Upcoming Date"} with ${linkedInsp?.officerName.isNotEmpty == true ? linkedInsp!.officerName : "Health Officer"}. Please proceed to record the inspection findings.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF99F6E4) : const Color(0xFF0F766E),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              CustomButton(
                label: 'Record Visit',
                icon: Icons.assignment_turned_in_rounded,
                backgroundColor: const Color(0xFF0F766E),
                onPressed: () {
                  ComplaintStoreService.updateComplaintStatus(c!.id, ComplaintStatus.inspecting);
                  Navigator.pushNamed(
                    context,
                    AppRoutes.conductInspection,
                    arguments: c,
                  );
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.scheduleInspection,
                      arguments: c,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFF00A88F), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(Icons.edit_calendar_outlined, size: 18, color: isDark ? Colors.white70 : const Color(0xFF00A88F)),
                  label: Text(
                    'Change Scheduled Date',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF00A88F),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
