import '../../core/widgets/app_search_field.dart';
import '../../core/widgets/app_select_field.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/services/duplicate_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/custom_app_bar.dart';

class DuplicateFakeReviewScreen extends StatefulWidget {
  const DuplicateFakeReviewScreen({super.key});

  @override
  State<DuplicateFakeReviewScreen> createState() => _DuplicateFakeReviewScreenState();
}

class _DuplicateFakeReviewScreenState extends State<DuplicateFakeReviewScreen> {
  int _selectedFilterIdx = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, VerificationCheckResult> _verificationCache = {};
  bool _isRescanning = false;

  final List<String> _filters = [
    'All Flagged',
    'Image Collisions',
    'GPS Mismatches',
    'Venue Collisions',
    'Text Matches',
  ];

  @override
  void initState() {
    super.initState();
    _hydrateScanCache();
  }

  Future<void> _hydrateScanCache() async {
    await AiDuplicateDetectorService.hydrateScanRecordCache();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runRetroactiveScan() async {
    if (_isRescanning) return;
    setState(() => _isRescanning = true);
    try {
      _verificationCache.clear();
      final summary = await ComplaintStoreService.applyRetroactiveDuplicateScan();
      if (mounted) {
        setState(() {});
        HygieneFeedback.showSuccess(
          context,
          'AI Re-Scan complete: ${summary['scanned']} reports checked • ${summary['flagged']} newly flagged • ${summary['cleared']} cleared',
        );
      }
    } catch (_) {
      if (mounted) {
        HygieneFeedback.showError(context, 'Re-scan failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isRescanning = false);
    }
  }

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_') || rawId.startsWith('CMP_')) {
      return rawId.toUpperCase().replaceAll('_', '-');
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  String? _shortCaseId(String? rawId) {
    if (rawId == null) return null;
    return rawId.length > 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
  }

  VerificationCheckResult _getVerificationResult(ComplaintModel c, List<ComplaintModel> allComplaints, List<RestaurantModel> allRestaurants) {
    if (_verificationCache.containsKey(c.id)) {
      return _verificationCache[c.id]!;
    }
    final res = AiDuplicateDetectorService.performFullVerificationCheck(
      complaint: c,
      existingComplaints: allComplaints,
      restaurants: allRestaurants,
    );
    _verificationCache[c.id] = res;
    return res;
  }

  Widget _buildEvidenceImage(String path, {BoxFit fit = BoxFit.cover, double height = 120}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        height: height,
        width: double.infinity,
        fit: fit,
        errorBuilder: (ctx, err, stack) => _buildMissingImageBox(height),
      );
    } else {
      final f = File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
      if (f.existsSync()) {
        return Image.file(
          f,
          height: height,
          width: double.infinity,
          fit: fit,
          errorBuilder: (ctx, err, stack) => _buildMissingImageBox(height),
        );
      }
      return _buildMissingImageBox(height);
    }
  }

  Widget _buildMissingImageBox(double height) {
    return Container(
      height: height,
      width: double.infinity,
      color: Colors.grey.shade300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.broken_image_rounded, size: 24, color: Colors.grey),
            SizedBox(height: 4),
            Text('No reference photo', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showMergeDialog(BuildContext context, ComplaintModel dup, String? defaultMasterId) {
    final allComplaints = ComplaintStoreService.complaintsNotifier.value;
    final candidateMasters = allComplaints.where((c) =>
      c.id != dup.id &&
      (c.restaurantId == dup.restaurantId || c.restaurantName.toLowerCase() == dup.restaurantName.toLowerCase()) &&
      c.status != ComplaintStatus.rejected
    ).toList();

    String selectedMasterId = defaultMasterId ?? (candidateMasters.isNotEmpty ? candidateMasters.first.id : (allComplaints.isNotEmpty ? allComplaints.first.id : ''));
    final TextEditingController remarksCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.merge_type_rounded, color: Color(0xFF0F766E), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Merge Duplicate Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Merging duplicate report ${_formatCaseId(dup.id)} will append its photos and evidence into the master investigation case, preventing duplicate visits by health officers.',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    const Text('Select Target Master Case *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    AppSelectField<String>(
                      initialValue: selectedMasterId.isNotEmpty ? selectedMasterId : null,
                      isExpanded: true,
                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white : Colors.black87),
                      dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: candidateMasters.isNotEmpty
                          ? candidateMasters.map((m) {
                              return DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                  '${_formatCaseId(m.id)} - ${m.restaurantName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList()
                          : allComplaints.map((m) {
                              return DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                  '${_formatCaseId(m.id)} - ${m.restaurantName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedMasterId = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Admin Consolidation Remarks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarksCtrl,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'e.g. Duplicate photo matching existing pest report',
                        hintStyle: TextStyle(fontSize: 11.5, color: isDark ? Colors.white38 : Colors.grey),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: selectedMasterId.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await ComplaintStoreService.mergeComplaints(
                            duplicateComplaintId: dup.id,
                            masterComplaintId: selectedMasterId,
                            adminRemarks: remarksCtrl.text.trim(),
                          );
                          _verificationCache.remove(dup.id);
                          if (context.mounted) {
                            HygieneFeedback.showSuccess(
                              context,
                              'Merged ${_formatCaseId(dup.id)} into Master Case!',
                            );
                          }
                        },
                  child: const Text('Confirm Merge'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRejectDialog(BuildContext context, ComplaintModel c) {
    String selectedReason = 'Suspected fake / spoofed GPS location';
    final List<String> reasons = [
      'Suspected fake / spoofed GPS location',
      'Stolen / re-uploaded stock photo from web',
      'Malicious spam / repetitive submitter',
      'Non-existent premise / invalid report',
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.block_rounded, color: Color(0xFFDC2626), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Reject & Dismiss Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dismissing report ${_formatCaseId(c.id)} will reject the submission and exclude it completely from health officer queues.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  const Text('Select Rejection Reason *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  AppSelectField<String>(
                    initialValue: selectedReason,
                    isExpanded: true,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                    dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedReason = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ComplaintStoreService.rejectComplaint(
                      complaintId: c.id,
                      reason: selectedReason,
                    );
                    _verificationCache.remove(c.id);
                    if (context.mounted) {
                      HygieneFeedback.showWarning(
                        context,
                        'Report ${_formatCaseId(c.id)} dismissed and rejected.',
                      );
                    }
                  },
                  child: const Text('Reject Report'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Duplicate & Fake Verification Hub',
        actions: [
          IconButton(
            tooltip: 'Re-run AI scan on all open reports',
            onPressed: _isRescanning ? null : _runRetroactiveScan,
            icon: _isRescanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.radar_rounded, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ValueListenableBuilder<List<ComplaintModel>>(
          valueListenable: ComplaintStoreService.complaintsNotifier,
        builder: (context, allComplaints, _) {
          final allRestaurants = RestaurantStoreService.restaurantsNotifier.value;

          // Identify all complaints that are flagged or underReview or have verification alerts
          final List<Map<String, dynamic>> flaggedEntries = [];

          for (final c in allComplaints) {
            final vResult = _getVerificationResult(c, allComplaints, allRestaurants);
            final bool isFlagged = c.isFlaggedForReview || vResult.isFlagged || c.status == ComplaintStatus.underReview;
            if (isFlagged && c.status != ComplaintStatus.rejected && c.status != ComplaintStatus.resolved) {
              flaggedEntries.add({
                'complaint': c,
                'result': vResult,
              });
            }
          }

          final query = _searchCtrl.text.trim().toLowerCase();

          final filteredEntries = flaggedEntries.where((entry) {
            final ComplaintModel c = entry['complaint'];
            final VerificationCheckResult res = entry['result'];

            if (query.isNotEmpty) {
              final rName = c.restaurantName.toLowerCase();
              final cId = _formatCaseId(c.id).toLowerCase();
              if (!rName.contains(query) && !cId.contains(query)) return false;
            }

            if (_selectedFilterIdx == 1) {
              // Image collisions
              return res.matchedImageUrl != null ||
                  (res.triggeredLayers.contains(DuplicateLayer.imageHash)) ||
                  (c.flaggedReason?.toLowerCase().contains('photo') ?? false);
            } else if (_selectedFilterIdx == 2) {
              // GPS Mismatches
              return res.isFakeSuspected || (c.flaggedReason?.toLowerCase().contains('gps') ?? false);
            } else if (_selectedFilterIdx == 3) {
              // Venue / active collisions
              return res.isDuplicate;
            } else if (_selectedFilterIdx == 4) {
              // Text similarity duplicates
              return res.triggeredLayers.contains(DuplicateLayer.textSimilarity) ||
                  res.textSimilarity > 0;
            }
            return true;
          }).toList();
          filteredEntries.sort((a, b) => CaseOrdering.complaints(
                a['complaint'] as ComplaintModel,
                b['complaint'] as ComplaintModel,
              ));

          final int totalFlaggedCount = flaggedEntries.length;
          final int imageMatchesCount = flaggedEntries
              .where((e) =>
                  ((e['result'] as VerificationCheckResult).matchedImageUrl != null) ||
                  ((e['result'] as VerificationCheckResult).triggeredLayers.contains(DuplicateLayer.imageHash)))
              .length;
          final int gpsMismatchesCount = flaggedEntries.where((e) => (e['result'] as VerificationCheckResult).isFakeSuspected).length;
          final int textMatchesCount = flaggedEntries
              .where((e) => (e['result'] as VerificationCheckResult).triggeredLayers.contains(DuplicateLayer.textSimilarity))
              .length;
          final int autoMergeEligibleCount = flaggedEntries.where((e) => (e['result'] as VerificationCheckResult).isAutoMergeCandidate).length;

          return Column(
            children: [
              // 1. TOP KPI SUMMARY
              Container(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Flagged Reports',
                            count: '$totalFlaggedCount',
                            color: const Color(0xFFDC2626),
                            icon: Icons.warning_amber_rounded,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Image Matches',
                            count: '$imageMatchesCount',
                            color: const Color(0xFFD97706),
                            icon: Icons.image_search_rounded,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'GPS Mismatch',
                            count: '$gpsMismatchesCount',
                            color: const Color(0xFF0284C7),
                            icon: Icons.wrong_location_rounded,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Text Match',
                            count: '$textMatchesCount',
                            color: const Color(0xFF7C3AED),
                            icon: Icons.notes_rounded,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    if (autoMergeEligibleCount > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: isDark ? 0.2 : 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF059669)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$autoMergeEligibleCount report(s) at \u2265${VerificationCheckResult.autoMergeThreshold.toStringAsFixed(0)}% confidence are auto-merged on arrival',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.greenAccent : const Color(0xFF065F46),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Search Bar
                    AppSearchField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search flagged reports by outlet or ID...',
                        hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
                        prefixIcon: Icon(Icons.search_rounded, size: 18, color: isDark ? Colors.white54 : Colors.grey.shade500),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setState(() => _searchCtrl.clear()),
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. FILTER CHIPS
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  itemBuilder: (context, idx) {
                    final isSelected = _selectedFilterIdx == idx;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          _filters[idx],
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFF0F766E),
                        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        side: BorderSide(color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
                        onSelected: (val) {
                          if (val) setState(() => _selectedFilterIdx = idx);
                        },
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // 3. FLAGGED REPORT COMPARISON CARDS
              Expanded(
                child: filteredEntries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.verified_user_rounded, size: 48, color: Color(0xFF059669)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'All Reports Clean & Verified 🎉',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0C2340),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No duplicate or fake reports are pending verification.',
                              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredEntries.length,
                        itemBuilder: (context, idx) {
                          final entry = filteredEntries[idx];
                          final ComplaintModel c = entry['complaint'];
                          final VerificationCheckResult res = entry['result'];
                          return _buildComparisonReviewCard(c, res, isDark);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String count,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(count, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : const Color(0xFF475569)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= VerificationCheckResult.autoMergeThreshold) return const Color(0xFFDC2626);
    if (confidence >= 85) return const Color(0xFFD97706);
    return const Color(0xFF059669);
  }

  Widget _buildComparisonReviewCard(ComplaintModel dup, VerificationCheckResult res, bool isDark) {
    final formattedId = _formatCaseId(dup.id);
    final restName = RestaurantStoreService.resolveRestaurantName(dup.restaurantName, fallback: dup.restaurantName);
    final isDup = res.isDuplicate;
    final isFake = res.isFakeSuspected;

    final Color headerColor = isDup ? const Color(0xFFD97706) : (isFake ? const Color(0xFFDC2626) : const Color(0xFF0284C7));
    final String badgeLabel = isDup ? 'DUPLICATE REPORT DETECTED' : (isFake ? 'SUSPECTED FAKE REPORT' : 'PENDING REVIEW');

    // Auto-merge eligibility vs actual master-case state.
    bool autoMergeBlocked = false;
    final String? matchedId = res.matchedComplaintId;
    if (res.isAutoMergeCandidate && matchedId != null) {
      final master = ComplaintStoreService.complaintsNotifier.value
          .where((m) => m.id == matchedId)
          .firstOrNull;
      autoMergeBlocked = master == null ||
          master.status == ComplaintStatus.rejected ||
          master.status == ComplaintStatus.resolved;
    }

    final scanRecord = AiDuplicateDetectorService.getScanRecord(dup.id);
    final scanAge = AiDuplicateDetectorService.scanAgeText(scanRecord);
    final confidenceColor = _confidenceColor(res.confidenceScore);

    final String? uploadedPhoto = dup.photoUrls.isNotEmpty ? dup.photoUrls.first : null;
    final String? matchedPhoto = res.matchedImageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: headerColor.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: headerColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isDup ? Icons.copy_rounded : Icons.warning_amber_rounded, size: 12, color: headerColor),
                      const SizedBox(width: 4),
                      Text(badgeLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: headerColor)),
                    ],
                  ),
                ),
                Text(
                  formattedId,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Confidence + triggered detection layers row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: confidenceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: confidenceColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed_rounded, size: 12, color: confidenceColor),
                      const SizedBox(width: 3),
                      Text(
                        '${res.confidenceScore.toStringAsFixed(1)}% Confidence',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: confidenceColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ...res.triggeredLayers.map((layer) => Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white12 : const Color(0xFF0C2340)).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          DuplicateLayer.labels[layer] ?? layer,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    )),
                const Spacer(),
                if (scanAge != null)
                  Text(
                    scanAge,
                    style: TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic, color: isDark ? Colors.white38 : Colors.grey.shade500),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Premise Name & Submitter
            Text(restName, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0C2340))),
            const SizedBox(height: 2),
            Text(
              'Submitter: ${dup.userName} • Category: ${dup.category}',
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
            ),
            const SizedBox(height: 10),

            // Risk & AI Reason Box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161616) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      Text('Verification Analysis:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    res.flagReason ?? (dup.flaggedReason ?? 'Evidence requires admin verification.'),
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            if (autoMergeBlocked) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50.withValues(alpha: isDark ? 0.15 : 1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.link_off_rounded, size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto-Merge Blocked \u2014 master case #${_shortCaseId(matchedId)} is already closed. Manual review required.',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Side-by-Side Evidence Comparison
            if (uploadedPhoto != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Incoming Citizen Photo:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _buildEvidenceImage(uploadedPhoto),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matchedId != null ? 'Original Report #${matchedId.substring(0, 8).toUpperCase()}:' : 'Reference Match:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF475569)),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: matchedPhoto != null
                              ? _buildEvidenceImage(matchedPhoto)
                              : _buildMissingImageBox(120),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Action Buttons Row (Merge, Reject, Verify)
            Row(
              children: [
                if (isDup)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showMergeDialog(context, dup, matchedId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.merge_type_rounded, size: 14),
                      label: const Text('Merge Case', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.pushNamed(context, '/admin/verify-evidence', arguments: dup);
                        if (mounted) setState(() => _verificationCache.remove(dup.id));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 14),
                      label: const Text('Verify Evidence', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(context, dup),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.block_rounded, size: 14),
                    label: const Text('Reject Fake', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
