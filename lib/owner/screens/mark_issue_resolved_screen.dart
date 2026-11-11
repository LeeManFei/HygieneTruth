import '../../core/widgets/app_validated_field.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_env.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/workflow_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/utils/uuid_helper.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../notifications/models/notification_model.dart';

class MarkIssueResolvedScreen extends StatefulWidget {
  const MarkIssueResolvedScreen({super.key});

  @override
  State<MarkIssueResolvedScreen> createState() => _MarkIssueResolvedScreenState();
}

class _MarkIssueResolvedScreenState extends State<MarkIssueResolvedScreen> {
  final TextEditingController _notesController = TextEditingController();
  final List<XFile> _evidenceFiles = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _notesController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _isFormValid =>
      _notesController.text.trim().isNotEmpty && _evidenceFiles.isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked != null) {
        setState(() {
          _evidenceFiles.add(picked);
        });
      }
    } catch (e) {
      if (mounted) {
        HygieneFeedback.showError(context, 'Failed to select file: $e');
      }
    }
  }

  Future<void> _submitResolution(ComplaintModel c) async {
    final notes = _notesController.text.trim();

    // Validation 1: Notes check
    if (notes.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please enter details of the corrective actions taken.');
      return;
    }

    // Validation 2: Photo evidence check
    if (_evidenceFiles.isEmpty) {
      HygieneFeedback.showWarning(context, 'Please attach at least 1 photo showing the corrected hygiene standard.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final supabase = SupabaseService.client;

      // 1. Upload owner rectification evidence to Supabase Storage
      final List<String> uploadedOwnerPhotos = [];
      final storageBucket = AppEnv.storageBucketName;
      for (int i = 0; i < _evidenceFiles.length; i++) {
        final file = File(_evidenceFiles[i].path);
        if (!file.existsSync()) {
          throw Exception('Selected evidence file is no longer available. Please select it again.');
        }

        final bytes = await file.readAsBytes();
        final ext = file.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        final fileName = 'owner_${c.restaurantId}_${DateTime.now().microsecondsSinceEpoch}_$i.$ext';
        final storagePath = 'owner_rectifications/$fileName';
        final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

        await supabase.storage.from(storageBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
        uploadedOwnerPhotos.add(
          supabase.storage.from(storageBucket).getPublicUrl(storagePath),
        );
      }

      if (uploadedOwnerPhotos.length != _evidenceFiles.length) {
        throw Exception('Not all evidence photos were uploaded to Supabase. Please try again.');
      }

      // Find associated inspection for foreign key compliance
      final matchingInspections = RestaurantStoreService.inspectionsNotifier.value
          .where((i) =>
              i.complaintId.isNotEmpty &&
              i.complaintId.toLowerCase().trim() == c.id.toLowerCase().trim())
          .toList();
      matchingInspections.sort(CaseOrdering.inspections);
      final insp = matchingInspections.firstOrNull;
      final inspId = insp != null ? (UuidHelper.isValidUuid(insp.id) ? insp.id : UuidHelper.toDeterministicUuid(insp.id)) : null;

      // 2. Record the owner's submission without closing the notice
      if (inspId != null) {
        try {
          await supabase.from('notices').update({
            'status': 'owner_evidence_submitted',
            'resolution_notes': notes,
          }).eq('inspection_id', inspId);
        } catch (dbErr) {
          debugPrint('[MarkIssueResolvedScreen] Notice update notice: $dbErr');
        }
      }

      // 3. Insert owner proof records into evidence table tagged with owner origin
      if (inspId != null) {
        for (final photo in uploadedOwnerPhotos) {
          try {
            final evidenceId = UuidHelper.toDeterministicUuid('owner_evidence_${c.id}_${photo.hashCode}');
            await supabase.from('evidence').upsert({
              'id': evidenceId,
              'inspection_id': inspId,
              'photo_url': photo,
              'note': '[OWNER PROOF OF FIX]: $notes',
              'created_at': nowIso,
            });
          } catch (evErr) {
            debugPrint('[MarkIssueResolvedScreen] Evidence upsert notice: $evErr');
          }
        }
      }

      // 4. Keep enforcement status unchanged until an officer completes review
      try {
        await supabase.from('restaurants').update({
          'last_updated': nowIso,
        }).eq('id', c.restaurantId);
      } catch (_) {}

      // 5. Update local state & record rectification submission
      await RestaurantStoreService.markRectificationSubmitted(
        restaurantId: c.restaurantId,
        restaurantName: c.restaurantName,
        complaintId: c.id,
        inspectionId: insp?.id,
        noticeId: c.id,
        notes: notes,
        photoUrls: uploadedOwnerPhotos,
      );

      final rIdx = RestaurantStoreService.restaurantsNotifier.value.indexWhere(
        (r) => r.id == c.restaurantId || r.name.toLowerCase() == c.restaurantName.toLowerCase(),
      );
      if (rIdx != -1) {
        final currentR = RestaurantStoreService.restaurantsNotifier.value[rIdx];
        final updatedList = List<RestaurantModel>.from(RestaurantStoreService.restaurantsNotifier.value);
        updatedList[rIdx] = currentR.copyWith(
          lastUpdated: nowIso,
        );
        RestaurantStoreService.restaurantsNotifier.value = updatedList;
      }

      // Update complaintsNotifier & persist status in SharedPreferences + Supabase
      await ComplaintStoreService.updateComplaintStatus(c.id, ComplaintStatus.investigating);

      try {
        await WorkflowService.submitOwnerEvidence(
          complaintId: c.id,
          ownerId: CustomerStoreService.currentCustomer?.id ?? 'owner',
          remarks: notes,
        );
      } catch (workflowError) {
        debugPrint('[MarkIssueResolvedScreen] Workflow update notice: $workflowError');
      }

      // Notify the officer queue that the case is ready for manual scheduling
      NotificationService.sendNotification(
        userId: 'gov_officer_001',
        title: '📋 Owner Evidence Ready for Inspection',
        message: 'The owner of ${c.restaurantName} submitted corrective-action evidence. The case is ready for manual inspection scheduling.',
        type: NotificationType.hygieneAlert,
        actionUrl: 'verified_complaints_list',
      );

      NotificationService.sendNotification(
        userId: 'own_001',
        title: '📤 Evidence Submitted',
        message: 'Your improvement evidence for ${c.restaurantName} was submitted. A Health Officer can now review and schedule the case.',
        type: NotificationType.system,
        actionUrl: 'owner_dashboard',
      );

      // 6. Audit log action
      try {
        await AuditLogService.logAction(
          actionType: 'RECTIFICATION_SUBMITTED',
          category: 'Business',
          title: 'Rectification Evidence Submitted',
          description: 'Owner submitted proof for ${c.restaurantName} (Notice ${c.id}) with ${_evidenceFiles.length} photo(s).',
        );
      } catch (_) {}

      if (mounted) {
        HygieneFeedback.showSuccess(context, 'Evidence uploaded to Supabase and submitted for officer review!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        HygieneFeedback.showError(context, 'Submission failed: $e');
      }
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
        appBar: const CustomAppBar(title: 'Submit Proof'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.task_alt, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No notice available to resolve.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Upload Evidence & Resolve'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
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
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.verified_rounded, color: Color(0xFF0F766E), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.restaurantName,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.navyColor,
                              ),
                            ),
                            Text(
                              'Notice: ${c.id}',
                              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Text(
                    'Upload proof that cleanliness directives have been rectified.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Corrective Action Notes
            Row(
              children: [
                Text(
                  'Corrective Action Taken',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.navyColor,
                  ),
                ),
                const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            AppValidatedField(validator: (v) => (v?.trim().isEmpty ?? true) ? 'Describe the corrective work you completed.' : null, controller: _notesController,
              maxLines: 3,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'e.g. Deep cleaning completed, pest control service done.',
                hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.grey.shade400),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Evidence Photos Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Proof of Fix / Photos',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                      ),
                    ),
                    const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(
                  '${_evidenceFiles.length} photo${_evidenceFiles.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _evidenceFiles.isNotEmpty ? const Color(0xFF059669) : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Evidence Grid & Add Buttons
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._evidenceFiles.map((file) {
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(file.path),
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 3,
                        right: 3,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _evidenceFiles.remove(file);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(3),
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
                }),
                // Add Photo from Gallery Button
                InkWell(
                  onTap: () => _pickImage(ImageSource.gallery),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.12 : 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.35)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF0F766E), size: 22),
                        SizedBox(height: 4),
                        Text('Gallery', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                      ],
                    ),
                  ),
                ),
                // Add Photo from Camera Button
                InkWell(
                  onTap: () => _pickImage(ImageSource.camera),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded, color: isDark ? Colors.white70 : Colors.grey.shade700, size: 22),
                        const SizedBox(height: 4),
                        Text('Camera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF0F766E), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Photos are verified by health officers during case audits.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            CustomButton(
              label: _isSubmitting ? 'Submitting...' : 'Submit',
              icon: Icons.check_circle_rounded,
              backgroundColor: const Color(0xFF0F766E),
              isLoading: _isSubmitting,
              onPressed: (_isFormValid && !_isSubmitting) ? () => _submitResolution(c!) : null,
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
