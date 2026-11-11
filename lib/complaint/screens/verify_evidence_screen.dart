import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/services/duplicate_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';

class VerifyEvidenceScreen extends StatefulWidget {
  const VerifyEvidenceScreen({super.key});

  @override
  State<VerifyEvidenceScreen> createState() => _VerifyEvidenceScreenState();
}

class _VerifyEvidenceScreenState extends State<VerifyEvidenceScreen> {
  AiDuplicateAnalysisResult? _aiResult;
  bool _isAiScanning = false;
  String? _scanError;
  bool _isProcessing = false;
  ComplaintModel? _complaint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_complaint == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is ComplaintModel) {
        _complaint = args;
      } else if (RestaurantStoreService.complaintsNotifier.value.isNotEmpty) {
        final flagged = RestaurantStoreService.complaintsNotifier.value
            .where((item) => item.isFlaggedForReview)
            .toList();
        _complaint = flagged.isNotEmpty
            ? flagged.first
            : RestaurantStoreService.complaintsNotifier.value.first;
      }
      _runAiDuplicateScan();
    }
  }

  Future<void> _runAiDuplicateScan() async {
    if (_complaint == null || _isAiScanning || _isProcessing) return;
    setState(() { _isAiScanning = true; _aiResult = null; _scanError = null; });
    try {
      final result = await ComplaintStoreService.scanComplaintEvidence(_complaint!.id);
      if (mounted) setState(() => _aiResult = result);
    } catch (e) {
      if (mounted) setState(() => _scanError = 'Verification unavailable. Check connection and re-scan.');
    } finally {
      if (mounted) setState(() => _isAiScanning = false);
    }
  }

  Color _scoreColor(double score) => score >= 80 ? Colors.red.shade700 : score >= 50 ? Colors.orange.shade800 : Colors.green.shade700;

  Widget _checkCard(String title, String message, IconData icon, Color color) => Card(
    elevation: 0, color: color.withValues(alpha: 0.07),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: 0.3))),
    child: ListTile(leading: Icon(icon, color: color), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(message, style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : color))));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _complaint;

    if (c == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Verify'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No reports available for verification.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    final bool canApprove = !_isAiScanning && !_isProcessing && _scanError == null && _aiResult?.canApprove == true;
    final bool isDuplicateFlagged = _aiResult?.isDuplicate ?? true;
    final risk = _aiResult?.overallRiskScore ?? 0;
    final statusMessage = _scanError ?? (_isAiScanning ? 'Checking live report data and photo bytes...' : 'Not checked');
    final String? uploadedPhotoUrl = _aiResult?.matchedUploadedImageUrl ?? ((c.photoUrls.isNotEmpty) ? c.photoUrls.first : null);
    final String? matchedDatabasePhotoUrl =
        isDuplicateFlagged ? _aiResult?.matchedImageUrl : null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Verify'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. REPORT OVERVIEW HEADER CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C2340), Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C2340).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c.id,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: (c.isFlaggedForReview
                              ? Colors.amber.shade700
                              : Colors.green.shade600),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          canApprove ? 'CHECKS PASSED' : 'NEEDS VERIFICATION',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    c.restaurantName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Issues: ${c.issues.join(", ")}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. EVIDENCE VERIFICATION CHECKS
            const Text(
              'Evidence Verification Checks',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navyColor),
            ),
            const SizedBox(height: 10),

            _checkCard('1. Reporter Heatmap Zone', _aiResult?.gpsMessage ?? statusMessage,
              Icons.location_on_outlined, _aiResult == null ? Colors.orange.shade800 : _aiResult!.gpsPassed ? Colors.green.shade700 : Colors.red.shade700),
            _checkCard('2. Photo / Report Spam Timing', _aiResult?.timingMessage ?? statusMessage,
              Icons.access_time_rounded, _aiResult == null ? Colors.orange.shade800 : _aiResult!.timingPassed ? Colors.green.shade700 : Colors.red.shade700),
            _checkCard('3. Automated Verification Risk', _aiResult == null ? statusMessage :
              '${_aiResult!.confidenceLevel}: ${risk.toStringAsFixed(1)}% maximum layer score. Red >=80%, yellow >=50%, green <50%. ${_aiResult!.canApprove ? 'Checks passed.' : 'FLAGGED / INCOMPLETE - approval disabled.'}',
              Icons.rule_rounded, _aiResult == null ? Colors.orange.shade800 : risk < 50 && !_aiResult!.canApprove ? Colors.red.shade700 : _scoreColor(risk)),
            const SizedBox(height: 16),

            // 3. DUAL-LAYER AI DUPLICATE DETECTOR & PHOTO COMPARISON
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
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
                  // Title + Status Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A88F).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.auto_awesome_rounded,
                                  color: Color(0xFF00A88F), size: 18),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Hash & Correlation Duplicate Detector',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppTheme.navyColor,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDuplicateFlagged
                              ? Colors.orange.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDuplicateFlagged
                                ? Colors.orange.shade300
                                : Colors.green.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isDuplicateFlagged
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 14,
                              color: isDuplicateFlagged
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isDuplicateFlagged
                                  ? (_aiResult == null ? 'Not verified' : 'Flagged match')
                                  : 'Below match threshold',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDuplicateFlagged
                                    ? Colors.orange.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dual Detection Layers Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        // Layer 1: Byte-Level Hash Check
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.tag_rounded,
                                  size: 14, color: Colors.blue),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: Text(
                              'Layer 1: Exact Photo Bytes:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            )),
                            const SizedBox(width: 8),
                            Text(
                              _aiResult != null
                                  ? '${_aiResult!.hexMatchScore.toStringAsFixed(1)}% Match'
                                  : 'Calculating...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _scoreColor(_aiResult?.hexMatchScore ?? 0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Layer 2: Evidence Correlation Check
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.psychology_outlined,
                                  size: 14, color: Colors.purple),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: Text(
                              'Layer 2: Report Text:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            )),
                            const SizedBox(width: 8),
                            Text(
                              _aiResult != null
                                  ? '${_aiResult!.aiSemanticScore.toStringAsFixed(1)}% Similarity'
                                  : 'Scanning...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _scoreColor(_aiResult?.aiSemanticScore ?? 0),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // AI Analysis Details & Feature Vector Insights
                  if (_aiResult != null &&
                      _aiResult!.matchedAiFeatures.isNotEmpty) ...[
                    Text(
                      'Detection Insights:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppTheme.darkSubtitleColor
                            : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._aiResult!.matchedAiFeatures.map(
                      (feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 3.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? AppTheme.darkSubtitleColor
                                      : Colors.grey.shade700,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Rescan Action Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        'Hash: ${_aiResult?.hexHash ?? "N/A"}',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontFamily: 'monospace'),
                      )),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isAiScanning || _isProcessing ? null : _runAiDuplicateScan,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _isAiScanning
                                  ? const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: AppTheme.primaryColor),
                                    )
                                  : const Icon(Icons.refresh_rounded,
                                      size: 12, color: AppTheme.primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                _isAiScanning ? 'Scanning...' : 'Re-scan',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Side-by-Side Photo Comparison
                  Text(
                    'Photo Comparison',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? AppTheme.darkTextColor : AppTheme.navyColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Uploaded Photo Container
                      Expanded(
                        child: _buildEvidenceImageThumbnail(
                          context: context,
                          imageUrl: uploadedPhotoUrl,
                          title: 'Uploaded Photo',
                          emptyLabel: 'No Image',
                          emptySublabel: 'No photo attached',
                          emptyIcon: Icons.no_photography_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Database Comparison Photo Container
                      Expanded(
                        child: _buildEvidenceImageThumbnail(
                          context: context,
                          imageUrl: matchedDatabasePhotoUrl,
                          title: isDuplicateFlagged
                              ? 'Matched Reference Photo'
                              : 'Reference Comparison',
                          emptyLabel: 'No Image',
                          emptySublabel: isDuplicateFlagged
                              ? 'No reference photo'
                              : 'Clean original image',
                          emptyIcon: Icons.image_not_supported_outlined,
                          emptyIconColor: isDuplicateFlagged
                              ? Colors.orange.shade400
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. ACTION BUTTONS
            Builder(builder: (context) {
              final bool isAlreadyApproved =
                  c.status != ComplaintStatus.submitted &&
                      c.status != ComplaintStatus.rejected &&
                      !c.isFlaggedForReview;
              final bool isAlreadyRejected =
                  c.status == ComplaintStatus.rejected;
              final bool isActionCompleted =
                  isAlreadyApproved || isAlreadyRejected;

              if (isActionCompleted) {
                return CustomButton(
                  label: isAlreadyApproved
                      ? 'Report Verified & Approved • 7-Day Rectification Active'
                      : 'Report Rejected • Duplicate / Invalid Evidence',
                  icon: isAlreadyApproved
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  backgroundColor:
                      isDark ? Colors.white12 : Colors.grey.shade400,
                  onPressed: null,
                );
              } else {
                return Column(
                  children: [
                    CustomButton(
                      label: 'Approve & Pass',
                      icon: Icons.check_circle_rounded,
                      backgroundColor: canApprove ? const Color(0xFF059669) : Colors.grey.shade500,
                      isLoading: _isProcessing,
                      onPressed: !canApprove
                          ? null
                          : () async {
                              setState(() => _isProcessing = true);
                              try {
                                final approved = await ComplaintStoreService.verifyComplaintEvidence(complaintId: c.id, isGenuine: true);
                                if (!mounted || !context.mounted) return;
                                if (!approved) { HygieneFeedback.showWarning(context, 'Approval blocked by current verification findings. Re-scan the evidence.'); return; }
                                HygieneFeedback.showSuccess(context, 'Report approved after verification.');
                                Navigator.of(context).pop();
                              } catch (e) {
                                if (mounted && context.mounted) HygieneFeedback.showError(context, 'Approval was not completed. Refresh and retry.');
                              } finally {
                                if (mounted) setState(() => _isProcessing = false);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    CustomButton(
                      label: 'Confirm Duplicate / Reject',
                      icon: Icons.cancel_rounded,
                      backgroundColor: const Color(0xFFDC2626),
                      isLoading: _isProcessing,
                      onPressed: _isProcessing
                          ? null
                          : () async {
                              setState(() => _isProcessing = true);
                              final nav = Navigator.of(context);
                              await ComplaintStoreService.verifyComplaintEvidence(
                                complaintId: c.id,
                                isGenuine: false,
                                remarks: 'Rejected: Duplicate / False Report',
                              );
                              if (!mounted || !context.mounted) return;
                              setState(() {
                                _isProcessing = false;
                                _complaint = RestaurantStoreService
                                        .complaintsNotifier.value
                                        .where((item) => item.id == c.id)
                                        .firstOrNull ??
                                    c;
                              });
                              HygieneFeedback.showError(
                                context,
                                'Report ${c.id} rejected due to duplicate/invalid proof.',
                              );
                              nav.pop();
                            },
                    ),
                  ],
                );
              }
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildEvidenceImageThumbnail({
    required BuildContext context,
    required String? imageUrl,
    required String title,
    required String emptyLabel,
    required String emptySublabel,
    required IconData emptyIcon,
    Color? emptyIconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: isDark ? AppTheme.darkTextColor : const Color(0xFF0F766E),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 135,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasImage
                  ? const Color(0xFF00A88F).withValues(alpha: 0.5)
                  : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
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
            child: hasImage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImageWidget(imageUrl),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              _showFullImageDialog(context, imageUrl, title),
                        ),
                      ),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          emptyIcon,
                          size: 32,
                          color: emptyIconColor ??
                              (isDark ? Colors.white38 : Colors.grey.shade400),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          emptyLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          emptySublabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageWidget(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primaryColor),
            ),
          );
        },
        errorBuilder: (ctx, error, stackTrace) => _buildFallbackIcon(),
      );
    } else if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (ctx, error, stackTrace) => _buildFallbackIcon(),
      );
    } else {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (ctx, error, stackTrace) => _buildFallbackIcon(),
        );
      } else {
        return _buildFallbackIcon();
      }
    }
  }

  Widget _buildFallbackIcon() {
    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 28),
      ),
    );
  }

  void _showFullImageDialog(
      BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: AppTheme.navyColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Container(
                color: Colors.black,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: _buildImageWidget(imageUrl),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
