import '../../core/widgets/app_validated_field.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/uuid_helper.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../notifications/models/notification_model.dart';

class ConductInspectionScreen extends StatefulWidget {
  const ConductInspectionScreen({super.key});

  @override
  State<ConductInspectionScreen> createState() => _ConductInspectionScreenState();
}

class _ConductInspectionScreenState extends State<ConductInspectionScreen> {
  final ImagePicker _picker = ImagePicker();
  InspectionOutcome _outcome = InspectionOutcome.compliant;
  double _hygieneScore = 85.0;
  bool _isSubmitting = false;

  final TextEditingController _findingsCtrl = TextEditingController();

  final List<String> _commonViolations = [
    'Food Storage Temp',
    'Active Pest Presence',
    'Cross-contamination',
    'Staff Hygiene & PPE',
    'Grease Trap Overflow',
    'Expired Ingredients',
  ];

  final Set<String> _selectedViolations = <String>{};

  final List<String> _evidencePhotos = [];

  bool _submitted = false;

  Future<void> _pickEvidencePhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked != null) {
        setState(() {
          _evidencePhotos.add(picked.path);
        });
        if (mounted) {
          HygieneFeedback.showSuccess(context, 'On-site photo evidence added!');
        }
      }
    } catch (e) {
      if (mounted) {
        HygieneFeedback.showError(context, 'Failed to capture or load photo: $e');
      }
    }
  }

  void _showPhotoSourceBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attach Inspection Photo Evidence',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0C2340),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Capture live premise violation proof or upload photos from your device gallery.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickEvidencePhoto(ImageSource.camera);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_rounded, size: 36, color: Color(0xFF0F766E)),
                              SizedBox(height: 10),
                              Text(
                                'Take Photo',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Live Camera',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickEvidencePhoto(ImageSource.gallery);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_rounded, size: 36, color: Color(0xFF0284C7)),
                              SizedBox(height: 10),
                              Text(
                                'Upload Gallery',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Phone Photos',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
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
  }

  @override
  void dispose() {
    _findingsCtrl.dispose();
    super.dispose();
  }

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_')) {
      return rawId.toUpperCase();
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  Widget _buildEvidenceThumbnail(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(path, height: 75, width: 75, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 28, color: Colors.grey));
    } else {
      final f = File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
      if (f.existsSync()) {
        return Image.file(f, height: 75, width: 75, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 28, color: Colors.grey));
      }
      return Container(
        height: 75,
        width: 75,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image_outlined, size: 28, color: Colors.grey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    ComplaintModel? c;
    if (args is ComplaintModel) {
      c = args;
    } else if (RestaurantStoreService.complaintsNotifier.value.isNotEmpty) {
      c = RestaurantStoreService.complaintsNotifier.value.first;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedId = c != null ? _formatCaseId(c.id) : 'CMP-ACTIVE';
    final restName = c != null
        ? RestaurantStoreService.resolveRestaurantName(c.restaurantName, fallback: c.restaurantName)
        : 'Premise Inspection';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || _submitted) return;
        final String? targetId = c?.id;
        if (targetId == null) return;
        final fresh = RestaurantStoreService.complaintsNotifier.value.where((x) => x.id == targetId).firstOrNull;
        if (fresh != null && fresh.status == ComplaintStatus.inspecting) {
          ComplaintStoreService.updateComplaintStatus(fresh.id, ComplaintStatus.investigating);
        }
      },
      child: Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Record Visit'),
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
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formattedId,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 14),
                          SizedBox(width: 4),
                          Text('Official Inspection', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    restName,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reported: ${c?.category ?? "Food Hygiene Violation"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. VISUAL OUTCOME CARDS SELECTOR
            Text(
              'Inspection Final Outcome *',
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
                  child: _buildOutcomeCard(
                    outcome: InspectionOutcome.compliant,
                    title: 'Compliant',
                    subtitle: 'Passes Grade A/B',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF059669),
                    isSelected: _outcome == InspectionOutcome.compliant,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOutcomeCard(
                    outcome: InspectionOutcome.nonCompliant,
                    title: 'Non-Compliant',
                    subtitle: 'Violations Found',
                    icon: Icons.warning_rounded,
                    color: const Color(0xFFDC2626),
                    isSelected: _outcome == InspectionOutcome.nonCompliant,
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 3. HYGIENE SCORE RATING SLIDER
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
                      Flexible(
                        child: Text(
                          'Assigned Hygiene Score',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0C2340),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: _hygieneScore >= 80
                              ? Colors.green.shade50
                              : (_hygieneScore >= 60 ? Colors.orange.shade50 : Colors.red.shade50),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _hygieneScore >= 80
                                ? Colors.green.shade300
                                : (_hygieneScore >= 60 ? Colors.orange.shade300 : Colors.red.shade300),
                          ),
                        ),
                        child: Text(
                          '${_hygieneScore.toInt()} / 100 • ${_hygieneScore >= 80 ? "Grade A" : (_hygieneScore >= 60 ? "Grade B" : "Grade C")}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _hygieneScore >= 80
                                ? Colors.green.shade800
                                : (_hygieneScore >= 60 ? Colors.orange.shade800 : Colors.red.shade800),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_hygieneScore < 60) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Below Passing Threshold (Action Required)',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.red.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _hygieneScore >= 80 ? const Color(0xFF059669) : (_hygieneScore >= 60 ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
                      thumbColor: const Color(0xFF0F766E),
                      overlayColor: const Color(0xFF0F766E).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _hygieneScore,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${_hygieneScore.toInt()}',
                      onChanged: (val) => setState(() => _hygieneScore = val),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. VIOLATIONS DETECTED QUICK CHIPS
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
                    'Observed Violations Checklist',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _commonViolations.map((item) {
                      final isSelected = _selectedViolations.contains(item);
                      return FilterChip(
                        label: Text(item),
                        selected: isSelected,
                        selectedColor: const Color(0xFFDC2626).withValues(alpha: 0.15),
                        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9),
                        checkmarkColor: const Color(0xFFDC2626),
                        labelStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFFDC2626) : (isDark ? Colors.white70 : const Color(0xFF475569)),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFFDC2626) : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedViolations.add(item);
                            } else {
                              _selectedViolations.remove(item);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 5. DETAILED FINDINGS TEXT FIELD
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
                    'Inspector Official Findings *',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0C2340),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppValidatedField(validator: (v) => (v?.trim().isEmpty ?? true) ? 'Describe your on-site findings before submitting.' : null, controller: _findingsCtrl,
                    maxLines: 3,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Record detailed findings, cross-contamination risks, and corrective orders...',
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
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 6. PHOTO EVIDENCE ATTACHMENTS
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
                      Text(
                        'Attached Photo Evidence (${_evidencePhotos.length})',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showPhotoSourceBottomSheet,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                        label: const Text('Add Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_evidencePhotos.isEmpty)
                    InkWell(
                      onTap: _showPhotoSourceBottomSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 85,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF141414) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_rounded, size: 24, color: Color(0xFF0F766E)),
                            const SizedBox(height: 6),
                            Text(
                              'Tap to take photo or select from gallery',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : const Color(0xFF0F766E),
                              ),
                            ),
                            Text(
                              'Attach evidence of storage, pests, or sanitation',
                              style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _evidencePhotos.length + 1,
                        itemBuilder: (ctx, idx) {
                          if (idx == _evidencePhotos.length) {
                            return Container(
                              width: 75,
                              margin: const EdgeInsets.only(right: 10),
                              child: InkWell(
                                onTap: _showPhotoSourceBottomSheet,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3)),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo_rounded, size: 20, color: Color(0xFF0F766E)),
                                      SizedBox(height: 4),
                                      Text(
                                        'Add',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          return Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: _buildEvidenceThumbnail(_evidencePhotos[idx]),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 12,
                                child: GestureDetector(
                                  onTap: () => setState(() => _evidencePhotos.removeAt(idx)),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 7. SUBMIT ACTION BUTTON
            CustomButton(
              label: 'Submit Inspection Report',
              icon: Icons.send_rounded,
              backgroundColor: const Color(0xFF0F766E),
              isLoading: _isSubmitting,
              onPressed: () => _handleSubmitInspection(c, restName),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Future<void> _handleSubmitInspection(ComplaintModel? c, String restName) async {
    if (_isSubmitting) return;

    final findings = _findingsCtrl.text.trim();

    // Validation 1: Findings note required
    if (findings.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please enter official inspection findings.');
      return;
    }

    // Validation 2: If Non-Compliant, require at least 1 violation selected
    if (_outcome == InspectionOutcome.nonCompliant && _selectedViolations.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please select at least 1 observed violation for non-compliant audit.');
      return;
    }

    if (c == null || c.restaurantId.isEmpty || _evidencePhotos.isEmpty) {
      HygieneFeedback.showWarning(context, 'Select the case and attach at least one on-site inspection photo.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 2. Create and register InspectionModel in inspectionsNotifier
      final existingInspection = RestaurantStoreService.inspectionsNotifier.value
              .where((item) => item.complaintId == c.id)
              .firstOrNull;
      final newInsp = InspectionModel(
        id: existingInspection?.id ?? UuidHelper.generateV4(),
        complaintId: c.id,
        restaurantId: c.restaurantId,
        restaurantName: restName,
        scheduledDate: existingInspection?.scheduledDate.isNotEmpty == true
            ? existingInspection!.scheduledDate
            : DateTime.now().toUtc().toIso8601String(),
        conductedDate: DateTime.now().toUtc().toIso8601String(),
        officerName: 'Health Inspector (KKM)',
        outcome: _outcome,
        findings: findings,
        recommendedAction: EnforcementType.none,
        issuedAction: EnforcementType.none,
        justification: _outcome == InspectionOutcome.compliant
            ? 'Official hygiene inspection conducted. Outcome: COMPLIANT PASS.'
            : 'Official hygiene inspection conducted. Violations recorded: ${_selectedViolations.join(", ")}',
        fineAmount: 0.0,
        statutoryCitation: null,
        enforcementStatus: EnforcementStatus.pending,
        issuedDate: null,
        dueDate: null,
        isAdminApproved: false,
      );

      await RestaurantStoreService.saveInspection(newInsp, photoUrls: _evidencePhotos, stage: 'submit');
      _submitted = true;

      // Update restaurant's inspected grade in memory, local storage & Supabase
      await RestaurantStoreService.syncRestaurantRiskAndGrade(c.restaurantId, restaurantName: restName);

      // Log audit action
      AuditLogService.logAction(
        actionType: 'INSPECTION_SUBMITTED_FOR_ADMIN_VERIFICATION',
        category: 'Government',
        title: 'Health Inspection Report Submitted to Admin',
        description: 'Officer submitted audit report for $restName (Outcome: ${_outcome.name.toUpperCase()}). Forwarded to Admin for review.',
      );

      // Notify Admin
      NotificationService.sendNotification(
        userId: 'adm_001',
        title: '📋 Inspection Report Awaiting Admin Review: $restName',
        message: 'Health Officer recorded visit with outcome: ${_outcome.name.toUpperCase()}. Please review and approve report before officer issues action & notice.',
        type: NotificationType.system,
        actionUrl: 'admin_review',
      );

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showSuccess(context, 'Inspection report submitted to Admin for verification!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showError(context, 'Failed to submit inspection report: $e');
    }
  }

  Widget _buildOutcomeCard({
    required InspectionOutcome outcome,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _outcome = outcome;
          if (outcome == InspectionOutcome.compliant) {
            _hygieneScore = 88.0;
            _selectedViolations.clear();
          } else {
            _hygieneScore = 45.0;
            _selectedViolations.clear();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? color.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF0C2340)),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
