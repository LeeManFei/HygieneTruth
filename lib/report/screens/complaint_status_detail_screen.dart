import '../../core/widgets/customer_refresh_indicator.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/shimmer_skeletons.dart';

import '../widgets/complaint_status_tracker.dart';

class ComplaintStatusDetailScreen extends StatefulWidget {
  const ComplaintStatusDetailScreen({super.key});

  @override
  State<ComplaintStatusDetailScreen> createState() => _ComplaintStatusDetailScreenState();
}

class _ComplaintStatusDetailScreenState extends State<ComplaintStatusDetailScreen> {
  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    await Future.wait([
      RestaurantStoreService.fetchAllComplaints(forceRefresh: true),
      RestaurantStoreService.fetchAllInspections(forceRefresh: true),
    ]);
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return 'Recent';
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      final msiaDt = dt.toUtc().add(const Duration(hours: 8));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour12 = msiaDt.hour == 0 ? 12 : (msiaDt.hour > 12 ? msiaDt.hour - 12 : msiaDt.hour);
      final ampm = msiaDt.hour >= 12 ? 'PM' : 'AM';
      final minute = msiaDt.minute.toString().padLeft(2, '0');
      return '${msiaDt.day} ${months[msiaDt.month - 1]} ${msiaDt.year}, $hour12:$minute $ampm';
    }
    return raw;
  }

  ComplaintModel? _findMatchingComplaint(
    List<ComplaintModel> list,
    String targetId,
    ComplaintModel? initial,
  ) {
    if (targetId.isNotEmpty) {
      final cleanTarget = targetId
          .replaceAll('#', '')
          .replaceAll('CMP-', '')
          .replaceAll('cmp-', '')
          .replaceAll('cmp_', '')
          .trim()
          .toLowerCase();

      final match = list.where((c) {
        final cleanC = c.id
            .replaceAll('#', '')
            .replaceAll('CMP-', '')
            .replaceAll('cmp-', '')
            .replaceAll('cmp_', '')
            .trim()
            .toLowerCase();

        return cleanC == cleanTarget ||
            cleanC.startsWith(cleanTarget) ||
            cleanTarget.startsWith(cleanC) ||
            (initial != null && c.id == initial.id);
      }).firstOrNull;

      if (match != null) return match;
    }

    if (initial != null) {
      final match = list.where((c) {
        return c.id.toLowerCase() == initial.id.toLowerCase() ||
            c.id == initial.id;
      }).firstOrNull;

      if (match != null) return match;
      return initial;
    }

    return list.isNotEmpty ? list.first : null;
  }

  InspectionModel? _findMatchingInspection(
    List<InspectionModel> list,
    ComplaintModel complaint,
  ) {
    final cleanCompId = complaint.id
        .replaceAll('#', '')
        .replaceAll('CMP-', '')
        .replaceAll('cmp-', '')
        .replaceAll('cmp_', '')
        .trim()
        .toLowerCase();

    return list.where((i) {
      if (i.complaintId.isNotEmpty) {
        final cleanInspCompId = i.complaintId
            .replaceAll('#', '')
            .replaceAll('CMP-', '')
            .replaceAll('cmp-', '')
            .replaceAll('cmp_', '')
            .trim()
            .toLowerCase();

        if (cleanInspCompId == cleanCompId ||
            cleanInspCompId.startsWith(cleanCompId) ||
            cleanCompId.startsWith(cleanInspCompId)) {
          return true;
        }
      }

      return false;
    }).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;

    String targetId = '';
    ComplaintModel? initialComplaint;
    if (args is ComplaintModel) {
      initialComplaint = args;
      targetId = args.id;
    } else if (args is String) {
      targetId = args;
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Report Status'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomerRefreshIndicator(
          onRefresh: _refreshData,
        child: ValueListenableBuilder<List<ComplaintModel>>(
          valueListenable: RestaurantStoreService.complaintsNotifier,
          builder: (context, complaintsList, _) {
            final complaint = _findMatchingComplaint(complaintsList, targetId, initialComplaint);

            if (complaint == null) {
              if (complaintsList.isEmpty) {
                return const CaseDetailsSkeleton();
              }
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.report_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No complaint status available.',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ValueListenableBuilder<List<InspectionModel>>(
              valueListenable: RestaurantStoreService.inspectionsNotifier,
              builder: (context, inspectionsList, _) {
                final inspection = _findMatchingInspection(inspectionsList, complaint);
                final bool isCaseResolved = complaint.status == ComplaintStatus.resolved ||
                    (inspection != null &&
                        (inspection.enforcementStatus == EnforcementStatus.completed ||
                            inspection.outcome == InspectionOutcome.compliant));

                final displayStatusName = isCaseResolved ? 'resolved' : complaint.status.name;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Enhanced Animated Live Step Progress Tracker
                      ComplaintStatusTracker(
                        status: isCaseResolved ? ComplaintStatus.resolved : complaint.status,
                        complaint: complaint,
                        inspection: inspection,
                      ),
                      const SizedBox(height: 14),

                      // 2. Incident Summary & Verification Card
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Header Row with Report ID and Status Badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Report ID: ${complaint.id}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: isDark ? Colors.white : AppTheme.navyColor,
                                            letterSpacing: -0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Official Public Health Report',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusBadge.fromStatus(displayStatusName),
                                ],
                              ),
                              Divider(height: 24, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),

                              // Restaurant Premises
                              _buildDetailRow(
                                icon: Icons.storefront_rounded,
                                iconColor: const Color(0xFF0F766E),
                                title: complaint.restaurantName,
                                subtitle: 'Category: ${complaint.category}',
                                isDark: isDark,
                              ),
                              const SizedBox(height: 16),

                              // Issues Tagged
                              _buildDetailRow(
                                icon: Icons.warning_amber_rounded,
                                iconColor: const Color(0xFFD97706),
                                title: 'Issues Identified',
                                subtitle: complaint.issues.isNotEmpty
                                    ? complaint.issues.join(' • ')
                                    : 'Standard Hygiene Violation',
                                isDark: isDark,
                              ),
                              const SizedBox(height: 16),

                              // Description
                              _buildDetailRow(
                                icon: Icons.notes_rounded,
                                iconColor: const Color(0xFF0284C7),
                                title: 'Description',
                                subtitle: complaint.description.isNotEmpty
                                    ? complaint.description
                                    : 'No detailed description provided.',
                                isDark: isDark,
                              ),
                              const SizedBox(height: 16),

                              // Timestamp
                              _buildDetailRow(
                                icon: Icons.schedule_rounded,
                                iconColor: const Color(0xFF8B5CF6),
                                title: 'Submitted Date & Time',
                                subtitle: _formatTimestamp(complaint.submittedAt),
                                isDark: isDark,
                              ),

                              // Assigned Officer (If scheduled / investigating / resolved)
                              if (inspection != null && inspection.officerName.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _buildDetailRow(
                                  icon: Icons.badge_rounded,
                                  iconColor: const Color(0xFF0F766E),
                                  title: 'Assigned Health Officer',
                                  subtitle: 'Officer ${inspection.officerName} (Field Inspector)',
                                  isDark: isDark,
                                ),
                              ],

                              // Enforcement Action Details (If issued)
                              if (inspection != null &&
                                  inspection.issuedAction != EnforcementType.none) ...[
                                const SizedBox(height: 16),
                                _buildDetailRow(
                                  icon: Icons.gavel_rounded,
                                  iconColor: isCaseResolved ? const Color(0xFF10B981) : const Color(0xFFDC2626),
                                  title: isCaseResolved ? 'Enforcement Concluded' : 'Enforcement Directive',
                                  subtitle: isCaseResolved
                                      ? '${inspection.issuedAction.name.toUpperCase()} (Resolved & Archived)'
                                      : '${inspection.issuedAction.name.toUpperCase()} (Due: ${inspection.dueDate ?? "Immediate"})',
                                  isDark: isDark,
                                ),
                              ],

                              // Evidence Photos Section
                              if (complaint.photoUrls.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Text(
                                  'Attached Evidence (${complaint.photoUrls.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: isDark ? Colors.white : AppTheme.navyColor,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 90,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: complaint.photoUrls.length,
                                    itemBuilder: (ctx, i) {
                                      final path = complaint.photoUrls[i];
                                      return Container(
                                        width: 90,
                                        height: 90,
                                        margin: const EdgeInsets.only(right: 10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(11),
                                          child: path.startsWith('http')
                                              ? Image.network(
                                                  path,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
                                                )
                                              : (File(path).existsSync()
                                                  ? Image.file(
                                                      File(path),
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
                                                    )
                                                  : _buildPlaceholder()),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 28),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: isDark ? Colors.white : AppTheme.navyColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
