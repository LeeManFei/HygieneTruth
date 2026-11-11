import '../../core/widgets/app_select_field.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../notifications/models/notification_model.dart';

class IssueEnforcementScreen extends StatefulWidget {
  final InspectionModel? inspection;
  const IssueEnforcementScreen({super.key, this.inspection});

  @override
  State<IssueEnforcementScreen> createState() => _IssueEnforcementScreenState();
}

class _IssueEnforcementScreenState extends State<IssueEnforcementScreen> {
  EnforcementType _selectedAction = EnforcementType.warning;
  final TextEditingController _fineCtrl = TextEditingController();
  final TextEditingController _justificationCtrl = TextEditingController();
  String _selectedLawClause = 'Food Hygiene Reg 2009 - Reg 34 (Pest Infestation)';
  bool _isSubmitting = false;
  bool _hasInitialized = false;

  final List<String> _lawClauses = [
    'Food Act 1983 - Section 11 (Unsanitary Conditions Closure)',
    'Food Hygiene Reg 2009 - Reg 34 (Pest Infestation)',
    'Food Act 1983 - Section 13 (Contaminated Food Selling)',
    'Food Hygiene Reg 2009 - Reg 11 (Medical Health & PPE Violation)',
  ];

  final List<int> _finePresets = [250, 500, 1000, 2500, 5000];

  @override
  void dispose() {
    _fineCtrl.dispose();
    _justificationCtrl.dispose();
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

  void _initFields(InspectionModel insp) {
    if (_hasInitialized) return;
    _hasInitialized = true;

    _selectedAction = insp.issuedAction != EnforcementType.none
        ? insp.issuedAction
        : (insp.recommendedAction != EnforcementType.none ? insp.recommendedAction : EnforcementType.warning);

    if (insp.fineAmount > 0) {
      _fineCtrl.text = insp.fineAmount.toInt().toString();
    } else {
      _fineCtrl.text = '';
    }

    if (insp.findings.isNotEmpty) {
      _justificationCtrl.text = insp.findings;
    } else if (insp.justification.isNotEmpty) {
      _justificationCtrl.text = insp.justification;
    } else {
      _justificationCtrl.text = '';
    }

    if (insp.statutoryCitation != null && _lawClauses.contains(insp.statutoryCitation)) {
      _selectedLawClause = insp.statutoryCitation!;
    } else {
      _selectedLawClause = _lawClauses.first;
    }
  }

  void _showPhotoPreviewDialog(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Colors.black,
                  constraints: const BoxConstraints(maxHeight: 500),
                  child: InteractiveViewer(
                    child: _buildEvidenceImage(path, fit: BoxFit.contain),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEvidenceImage(String path, {BoxFit fit = BoxFit.cover}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (ctx, err, stack) => Container(
          color: Colors.grey.shade300,
          child: const Center(child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey)),
        ),
      );
    } else {
      final f = File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
      if (f.existsSync()) {
        return Image.file(
          f,
          fit: fit,
          errorBuilder: (ctx, err, stack) => Container(
            color: Colors.grey.shade300,
            child: const Center(child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey)),
          ),
        );
      }
      return Container(
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    InspectionModel? insp = widget.inspection;
    if (insp == null && args is InspectionModel) {
      insp = args;
    } else if (insp == null && RestaurantStoreService.inspectionsNotifier.value.isNotEmpty) {
      insp = RestaurantStoreService.inspectionsNotifier.value.first;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (insp == null) {
      if (RestaurantStoreService.inspectionsNotifier.value.isEmpty) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
          appBar: const CustomAppBar(title: 'Issue Action'),
          body: const CaseDetailsSkeleton(),
        );
      }
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
        appBar: const CustomAppBar(title: 'Issue Action'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.assignment_late_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No Inspection Selected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

    final InspectionModel targetInsp = insp;
    _initFields(targetInsp);

    // Look up linked complaint and restaurant details
    final complaint = ComplaintStoreService.complaintsNotifier.value
        .where((c) => c.id == insp!.complaintId || (insp.complaintId.isNotEmpty && c.id.toLowerCase() == insp.complaintId.toLowerCase()))
        .firstOrNull;

    final restaurant = RestaurantStoreService.restaurantsNotifier.value
        .where((r) => r.id == insp!.restaurantId || r.name.toLowerCase() == insp.restaurantName.toLowerCase())
        .firstOrNull;

    final formattedId = _formatCaseId(insp.complaintId.isNotEmpty ? insp.complaintId : insp.id);
    final restName = RestaurantStoreService.resolveRestaurantName(insp.restaurantName, fallback: insp.restaurantName);
    final isNonCompliant = insp.outcome == InspectionOutcome.nonCompliant;

    // Collect all available evidence photos (Priority 1: Health Officer on-site inspection photos)
    final List<String> evidencePhotos = [];
    if (insp.photoUrls.isNotEmpty) {
      evidencePhotos.addAll(insp.photoUrls.where((p) => p.trim().isNotEmpty));
    } else if (complaint != null && complaint.photoUrls.isNotEmpty) {
      evidencePhotos.addAll(complaint.photoUrls.where((p) => p.trim().isNotEmpty));
    }

    // Violations list
    final List<String> observedViolations = [];
    if (complaint != null && complaint.issues.isNotEmpty) {
      observedViolations.addAll(complaint.issues);
    } else {
      observedViolations.addAll(['Food Storage Temp', 'Active Pest Presence', 'Staff Hygiene & PPE']);
    }

    final bool isAlreadyIssued = insp.issuedDate?.isNotEmpty == true ||
        insp.enforcementStatus == EnforcementStatus.completed;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(title: isAlreadyIssued ? 'View Action Notice' : 'Issue Action'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP CASE CONTEXT BANNER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                      : [const Color(0xFF0C2340), const Color(0xFF991B1B)],
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
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formattedId,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isAlreadyIssued ? const Color(0xFF10B981).withValues(alpha: 0.8) : Colors.red.shade900.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isAlreadyIssued ? const Color(0xFF10B981) : Colors.red.shade400),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isAlreadyIssued ? Icons.verified_rounded : Icons.gavel_rounded, color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              isAlreadyIssued ? 'Action Issued & Active' : 'Action Notice',
                              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
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
                    'Violation: ${insp.findings.isNotEmpty ? insp.findings : "Pest Infestation & Critical Contamination Risk"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. PREVIOUS COMPLIANCE & PHYSICAL VISIT EVIDENCE SUMMARY
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.fact_check_rounded, size: 16, color: Color(0xFF0F766E)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Inspection Findings & Evidence',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0C2340),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatDate(insp.conductedDate ?? insp.scheduledDate),
                        style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Score & Outcome Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669)).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669)).withValues(alpha: 0.3),
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
                              isNonCompliant ? 'Non-Compliant' : 'Compliant',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: (restaurant?.riskCategory == RiskCategory.high
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFD97706))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Score: ${restaurant?.hygieneRiskScore.toInt() ?? (isNonCompliant ? 45 : 88)} / 100 (Grade ${isNonCompliant ? "C" : "A"})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isNonCompliant ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Observed Violations Tags
                  Text(
                    'Observed Violations:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: observedViolations.map((v) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.close_rounded, size: 11, color: Color(0xFFDC2626)),
                            const SizedBox(width: 4),
                            Text(
                              v,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Official Inspector Findings Text
                  Text(
                    'Inspector Official Description:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      insp.findings.isNotEmpty
                          ? insp.findings
                          : (complaint?.description.isNotEmpty == true
                              ? complaint!.description
                              : 'Inspection findings recorded.'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Photographic Evidence Gallery
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Attached Photo Evidence (${evidencePhotos.length}):',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                      ),
                      Text(
                        'Tap photo to zoom',
                        style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: evidencePhotos.length,
                      itemBuilder: (context, idx) {
                        final photo = evidencePhotos[idx];
                        return GestureDetector(
                          onTap: () => _showPhotoPreviewDialog(context, photo),
                          child: Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: _buildEvidenceImage(photo),
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.zoom_in, color: Colors.white, size: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. ACTION TYPE SELECTION CARDS
            Text(
              isAlreadyIssued ? 'Issued Enforcement Action Type (Official)' : 'Enforcement Action Type *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0C2340),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildActionTypeTile(
                    type: EnforcementType.closure,
                    title: 'Closure Notice',
                    subtitle: '7-Day Shutdown',
                    icon: Icons.block_rounded,
                    color: const Color(0xFFDC2626),
                    isSelected: _selectedAction == EnforcementType.closure,
                    isEnabled: !isAlreadyIssued,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionTypeTile(
                    type: EnforcementType.fine,
                    title: 'Compound Fine',
                    subtitle: 'Monetary Penalty',
                    icon: Icons.payments_rounded,
                    color: const Color(0xFFD97706),
                    isSelected: _selectedAction == EnforcementType.fine,
                    isEnabled: !isAlreadyIssued,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionTypeTile(
                    type: EnforcementType.warning,
                    title: 'Form 32 Warning',
                    subtitle: '7-Day Remediation',
                    icon: Icons.warning_amber_rounded,
                    color: const Color(0xFF0284C7),
                    isSelected: _selectedAction == EnforcementType.warning,
                    isEnabled: !isAlreadyIssued,
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 5. FINE AMOUNT SECTION (FOR FINES AND CLOSURES)
            if (_selectedAction == EnforcementType.fine || _selectedAction == EnforcementType.closure) ...[
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
                      'Compound Penalty Amount (MYR)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0C2340),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _fineCtrl,
                      readOnly: isAlreadyIssued,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: 'RM ',
                        prefixStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F766E),
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    if (!isAlreadyIssued) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: _finePresets.map((amount) {
                          return ActionChip(
                            label: Text('RM $amount'),
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: _fineCtrl.text == amount.toString() ? Colors.white : const Color(0xFF0F766E),
                            ),
                            backgroundColor: _fineCtrl.text == amount.toString()
                                ? const Color(0xFF0F766E)
                                : (isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9)),
                            onPressed: () {
                              setState(() => _fineCtrl.text = amount.toString());
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 6. LEGAL STATUTORY CLAUSE
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
                    'Statutory Legal Citation *',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppSelectField<String>(
                    initialValue: _selectedLawClause,
                    isExpanded: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 12.5),
                    dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                    ),
                    items: _lawClauses.map((clause) {
                      return DropdownMenuItem(value: clause, child: Text(clause));
                    }).toList(),
                    onChanged: isAlreadyIssued
                        ? null
                        : (val) {
                            if (val != null) setState(() => _selectedLawClause = val);
                          },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 7. OFFICER JUSTIFICATION & DIRECTIVES
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
                    'Enforcement Directives & Orders *',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _justificationCtrl,
                    readOnly: isAlreadyIssued,
                    maxLines: 3,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Specify mandatory rectification orders, fine due date, or closure conditions...',
                      hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 8. ISSUE ACTION BUTTON (LOCKED IF ALREADY ISSUED TO PREVENT UNFAIR MODIFICATION)
            if (isAlreadyIssued) ...[
              CustomButton(
                label: 'Action Notice Already Issued (Locked)',
                icon: Icons.lock_rounded,
                backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E),
                textColor: Colors.white,
                onPressed: null,
              ),
            ] else ...[
              CustomButton(
                label: 'Issue Official Enforcement Decree',
                icon: Icons.gavel_rounded,
                backgroundColor: const Color(0xFFDC2626),
                isLoading: _isSubmitting,
                onPressed: () => _handleIssueEnforcement(targetInsp, restName),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _handleIssueEnforcement(InspectionModel targetInsp, String restName) async {
    if (_isSubmitting) return;

    final justText = _justificationCtrl.text.trim();
    final fineAmt = _selectedAction == EnforcementType.warning
        ? 0.0 : double.tryParse(_fineCtrl.text.trim());

    // Validation 1: Enforcement directives / justification
    if (justText.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please enter enforcement directives and legal justification.');
      return;
    }

    // Validation 2: Compound fine amount check
    if (fineAmt == null || !fineAmt.isFinite || fineAmt < 0 ||
        (_selectedAction == EnforcementType.fine && fineAmt <= 0)) {
      HygieneFeedback.showWarning(context, 'Please specify a compound fine amount greater than RM 0.00.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await RestaurantStoreService.issueInspectionEnforcement(
        inspection: targetInsp, action: _selectedAction,
        fineAmount: fineAmt, citation: _selectedLawClause, remarks: justText,
      );

      // Log audit action
      AuditLogService.logAction(
        actionType: 'ENFORCEMENT_ISSUED',
        category: 'Government',
        title: 'Enforcement Action Issued',
        description: 'Issued ${_selectedAction.name.toUpperCase()} (Fine: RM ${fineAmt.toStringAsFixed(2)}) for $restName. $_selectedLawClause',
      );

      // 1. Notify Restaurant Owner
      NotificationService.sendNotification(
        userId: 'own_001',
        title: '🚨 Official Action Notice Issued: ${_selectedAction.name.toUpperCase()}',
        message: 'Ministry of Health issued ${_selectedAction.name.toUpperCase()} (Fine: RM ${fineAmt.toStringAsFixed(2)}) for $restName. Law: $_selectedLawClause. Settle fine & submit improvement proof.',
        type: NotificationType.hygieneAlert,
        actionUrl: 'enforcement_notice',
      );

      // 2. Notify Admin
      NotificationService.sendNotification(
        userId: 'adm_001',
        title: '📢 Action Notice Issued by Officer: $restName',
        message: 'Health Officer ${targetInsp.officerName} has officially issued ${_selectedAction.name.toUpperCase()} (Fine: RM ${fineAmt.toStringAsFixed(2)}) for $restName.',
        type: NotificationType.system,
        actionUrl: 'enforcement_history',
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showSuccess(context, 'Official enforcement notice issued for $restName!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showError(context, 'Failed to issue enforcement notice: $e');
    }
  }

  Widget _buildActionTypeTile({
    required EnforcementType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    bool isEnabled = true,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: isEnabled
          ? () => setState(() {
                _selectedAction = type;
                if (type == EnforcementType.closure) {
                  _fineCtrl.text = '2500';
                  _selectedLawClause = 'Food Act 1983 - Section 11 (Unsanitary Conditions Closure)';
                } else if (type == EnforcementType.fine) {
                  _fineCtrl.text = '1000';
                  _selectedLawClause = 'Food Hygiene Reg 2009 - Reg 34 (Pest Infestation)';
                } else {
                  _fineCtrl.text = '0';
                  _selectedLawClause = 'Food Hygiene Reg 2009 - Reg 34 (Pest Infestation)';
                }
              })
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF0C2340)),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 9.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
