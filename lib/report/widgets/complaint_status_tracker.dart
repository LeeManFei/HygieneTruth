import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/theme/app_theme.dart';

class ComplaintStatusTracker extends StatefulWidget {
  final ComplaintStatus status;
  final ComplaintModel? complaint;
  final InspectionModel? inspection;

  const ComplaintStatusTracker({
    super.key,
    required this.status,
    this.complaint,
    this.inspection,
  });

  @override
  State<ComplaintStatusTracker> createState() => _ComplaintStatusTrackerState();
}

class _ComplaintStatusTrackerState extends State<ComplaintStatusTracker> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  int? _selectedStepIndex;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  int _getStatusStepIndex(ComplaintStatus s, InspectionModel? inspection, ComplaintModel? complaint) {
    // 1. Resolved / Completed / Closed (Step 5 / Index 4)
    if (s == ComplaintStatus.resolved || s == ComplaintStatus.rejected) {
      return 4;
    }
    if (inspection != null) {
      if (inspection.enforcementStatus == EnforcementStatus.completed ||
          inspection.outcome == InspectionOutcome.compliant) {
        return 4;
      }
    }

    // 2. Inspecting / Action Issued / Scheduled (Step 4 / Index 3)
    if (s == ComplaintStatus.inspecting || s == ComplaintStatus.pendingInspection) {
      return 3;
    }
    if (inspection != null) {
      if (inspection.issuedAction != EnforcementType.none ||
          inspection.outcome == InspectionOutcome.nonCompliant ||
          inspection.enforcementStatus == EnforcementStatus.inProgress ||
          inspection.conductedDate != null ||
          (inspection.scheduledDate.isNotEmpty && inspection.scheduledDate != 'TBD')) {
        return 3;
      }
    }

    // 3. Investigating / Officer Assigned (Step 3 / Index 2)
    if (s == ComplaintStatus.investigating) {
      return 2;
    }
    if (inspection != null && inspection.officerName.isNotEmpty) {
      return 2;
    }

    // 4. Under Review by Admin (Step 2 / Index 1)
    if (s == ComplaintStatus.underReview || complaint?.isFlaggedForReview == true) {
      return 1;
    }

    // 5. Default Submitted (Step 1 / Index 0)
    return 0;
  }

  List<Map<String, dynamic>> _getStepMeta(InspectionModel? inspection, ComplaintModel? complaint) {
    final officerName = inspection?.officerName.isNotEmpty == true ? inspection!.officerName : 'Assigned Health Officer';
    final scheduledDate = inspection?.scheduledDate.isNotEmpty == true ? inspection!.scheduledDate : null;

    final String inspectDetail;
    if (inspection != null && inspection.issuedAction != EnforcementType.none) {
      inspectDetail = 'Official statutory inspection conducted. Enforcement action issued: ${inspection.issuedAction.name.toUpperCase()}. Compliance directives served to premises.';
    } else if (scheduledDate != null) {
      inspectDetail = 'On-site physical inspection scheduled for $scheduledDate. Field officer $officerName will conduct statutory hygiene audit.';
    } else {
      inspectDetail = 'Enforcement team will conduct physical inspection, food sampling, and statutory hygiene scoring.';
    }

    final String resolvedDetail;
    if (inspection != null && (inspection.enforcementStatus == EnforcementStatus.completed || inspection.outcome == InspectionOutcome.compliant)) {
      resolvedDetail = 'Full compliance verified and enforcement case officially closed and archived by Health Inspector (KKM).';
    } else {
      resolvedDetail = 'Official directive or rectification notice has been concluded and verified by authorities.';
    }

    return [
      {
        'title': 'Report Submitted',
        'short': 'Submitted',
        'icon': Icons.assignment_turned_in_rounded,
        'desc': 'Report received & registered in system.',
        'detail': 'Your report has been received and registered with health authorities for review.',
      },
      {
        'title': 'Under Review',
        'short': 'Review',
        'icon': Icons.manage_search_rounded,
        'desc': 'Audited by System Administrator.',
        'detail': 'Health authorities reviewed submitted evidence and cross-checked hygiene logs.',
      },
      {
        'title': 'Investigating',
        'short': 'Investigate',
        'icon': Icons.travel_explore_rounded,
        'desc': 'Assigned to $officerName.',
        'detail': '$officerName has been assigned to investigate the premises and prepare compliance directives.',
      },
      {
        'title': 'Inspection',
        'short': 'Inspect',
        'icon': Icons.fact_check_rounded,
        'desc': scheduledDate != null ? 'On-site audit scheduled for $scheduledDate.' : 'On-site physical audit in progress.',
        'detail': inspectDetail,
      },
      {
        'title': 'Resolved',
        'short': 'Resolved',
        'icon': Icons.task_alt_rounded,
        'desc': 'Action completed & compliance enforced.',
        'detail': resolvedDetail,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeIndex = _getStatusStepIndex(widget.status, widget.inspection, widget.complaint);
    final isRejected = widget.status == ComplaintStatus.rejected;
    final isResolved = activeIndex == 4 && !isRejected;

    final stepMeta = _getStepMeta(widget.inspection, widget.complaint);
    final inspectedIndex = _selectedStepIndex ?? activeIndex;
    final activeMeta = stepMeta[inspectedIndex.clamp(0, 4)];

    final progressFactor = (activeIndex / 4.0).clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.timeline_rounded,
                        color: Color(0xFF0F766E),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Complaint Progress Tracking',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: isRejected
                      ? const Color(0xFFFEE2E2)
                      : (isResolved ? const Color(0xFFD1FAE5) : const Color(0xFFE0F2FE)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isRejected ? Colors.red.shade300 : (isResolved ? Colors.green.shade300 : const Color(0xFFBAE6FD)),
                  ),
                ),
                child: Text(
                  isRejected ? 'REJECTED' : 'STEP ${activeIndex + 1}/5',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: isRejected
                        ? const Color(0xFFDC2626)
                        : (isResolved ? const Color(0xFF059669) : const Color(0xFF0284C7)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Animated Step Tracker Node Bar
          LayoutBuilder(
            builder: (ctx, constraints) {
              final totalWidth = constraints.maxWidth;
              const nodeSize = 34.0;
              final usableTrackWidth = totalWidth - nodeSize;

              return Column(
                children: [
                  // Stack with background track, animated active fill, and milestone nodes
                  SizedBox(
                    height: nodeSize + 8,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Background Inactive Track
                        Positioned(
                          left: nodeSize / 2,
                          right: nodeSize / 2,
                          top: (nodeSize / 2) + 2,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Animated Filled Active Track
                        Positioned(
                          left: nodeSize / 2,
                          top: (nodeSize / 2) + 2,
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            tween: Tween<double>(begin: 0.0, end: progressFactor),
                            builder: (context, val, child) {
                              return Container(
                                width: usableTrackWidth * val,
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isRejected
                                        ? [const Color(0xFF0F766E), const Color(0xFFEF4444)]
                                        : (isResolved
                                            ? [const Color(0xFF0F766E), const Color(0xFF10B981)]
                                            : [const Color(0xFF0F766E), const Color(0xFF0284C7)]),
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Milestone Interactive Nodes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(5, (index) {
                            final isPassed = index < activeIndex;
                            final isCurrent = index == activeIndex;
                            final isSelected = inspectedIndex == index;

                            final IconData nodeIcon;
                            if (index == 4 && isRejected) {
                              nodeIcon = Icons.close_rounded;
                            } else if (isPassed) {
                              nodeIcon = Icons.check_rounded;
                            } else {
                              nodeIcon = stepMeta[index]['icon'] as IconData;
                            }

                            final Color nodeColor;
                            if (index == 4 && isRejected && isCurrent) {
                              nodeColor = const Color(0xFFDC2626);
                            } else if (isPassed) {
                              nodeColor = const Color(0xFF10B981);
                            } else if (isCurrent) {
                              nodeColor = isResolved ? const Color(0xFF10B981) : const Color(0xFF0F766E);
                            } else {
                              nodeColor = isDark ? Colors.grey.shade700 : const Color(0xFFCBD5E1);
                            }

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedStepIndex = index;
                                });
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (context, child) {
                                      final scale = isCurrent ? _pulseAnimation.value : 1.0;
                                      return Transform.scale(
                                        scale: scale,
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          width: nodeSize,
                                          height: nodeSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: (isPassed || isCurrent)
                                                ? nodeColor
                                                : (isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9)),
                                            border: Border.all(
                                              color: isSelected
                                                  ? (isDark ? Colors.white : AppTheme.navyColor)
                                                  : (isCurrent
                                                      ? Colors.white
                                                      : (isPassed ? nodeColor : (isDark ? Colors.white24 : Colors.grey.shade300))),
                                              width: isCurrent || isSelected ? 2.5 : 1.5,
                                            ),
                                            boxShadow: isCurrent
                                                ? [
                                                    BoxShadow(
                                                      color: nodeColor.withValues(alpha: 0.4),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                  ]
                                                : (isSelected
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.black.withValues(alpha: 0.15),
                                                          blurRadius: 6,
                                                        ),
                                                      ]
                                                    : null),
                                          ),
                                          child: Icon(
                                            nodeIcon,
                                            size: 16,
                                            color: (isPassed || isCurrent)
                                                ? Colors.white
                                                : (isDark ? Colors.white38 : Colors.grey.shade500),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Node Labels Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (index) {
                      final isPassed = index < activeIndex;
                      final isCurrent = index == activeIndex;
                      final isSelected = inspectedIndex == index;

                      final String label = (index == 4 && isRejected)
                          ? 'Rejected'
                          : (stepMeta[index]['short'] as String);

                      return SizedBox(
                        width: (totalWidth / 5.2).clamp(48.0, 70.0),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: isCurrent || isSelected ? FontWeight.bold : (isPassed ? FontWeight.w600 : FontWeight.w500),
                            color: isCurrent
                                ? (isResolved
                                    ? const Color(0xFF10B981)
                                    : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F766E)))
                                : (isSelected
                                    ? (isDark ? Colors.white : AppTheme.navyColor)
                                    : (isPassed
                                        ? (isDark ? Colors.white70 : const Color(0xFF334155))
                                        : (isDark ? Colors.white38 : Colors.grey.shade400))),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // Interactive Step Detail Callout Card
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isResolved
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    activeMeta['icon'] as IconData,
                    size: 16,
                    color: isResolved ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              activeMeta['title'] as String,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.navyColor,
                              ),
                            ),
                          ),
                          if (inspectedIndex == activeIndex) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: (isResolved ? const Color(0xFF10B981) : const Color(0xFF0F766E))
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isResolved ? 'CASE RESOLVED' : 'CURRENT STAGE',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: isResolved ? const Color(0xFF10B981) : const Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        activeMeta['detail'] as String,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
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
      ),
    );
  }
}
