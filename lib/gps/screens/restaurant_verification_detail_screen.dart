import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/user_banner.dart';

class RestaurantVerificationDetailScreen extends StatefulWidget {
  const RestaurantVerificationDetailScreen({super.key});

  @override
  State<RestaurantVerificationDetailScreen> createState() => _RestaurantVerificationDetailScreenState();
}

class _RestaurantVerificationDetailScreenState extends State<RestaurantVerificationDetailScreen> {
  final _revisionNoteCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isMapLoading = true;
  bool _isSubmitting = false;
  Map<String, dynamic>? _ocrMeta;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ocrMeta == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is RestaurantModel) {
        _loadOcrMetadata(args);
      }
    }
  }

  Future<void> _loadOcrMetadata(RestaurantModel r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('restaurant_ssm_ocr_${r.id}');
      if (mounted && raw != null && raw.isNotEmpty) {
        setState(() => _ocrMeta = jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  String? _firstFilled(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty && a.trim().toLowerCase() != 'null') return a.trim();
    if (b != null && b.trim().isNotEmpty && b.trim().toLowerCase() != 'null') return b.trim();
    return null;
  }

  Widget _ocrMetaRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _revisionNoteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;
    final RestaurantModel? r = args is RestaurantModel ? args : (RestaurantStoreService.restaurantsNotifier.value.isNotEmpty ? RestaurantStoreService.restaurantsNotifier.value.first : null);

    if (r == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Outlet Review'),
        body: const Center(child: Text('No outlet selected for review')),
      );
    }

    final appId = 'APP-${r.id.substring(0, r.id.length > 8 ? 8 : r.id.length).toUpperCase()}';

    return Scaffold(
      appBar: const CustomAppBar(title: 'Outlet Review'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const OutletReviewSkeleton()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero Card Header with Restaurant Image & Banner
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Outlet Image Banner
                        Stack(
                          children: [
                            UserBanner(
                              bannerUrl: r.imageUrl,
                              height: 140,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: StatusBadge.fromStatus(r.status.name),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            appId,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                r.category,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Details Section Header
            Row(
              children: [
                const Icon(Icons.storefront_rounded, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Application Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Location & Information Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded, color: AppTheme.primaryColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(r.address, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.access_time_rounded, color: Color(0xFFD97706), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Operating Hours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(r.operatingHours.isNotEmpty ? r.operatingHours : '10:00 AM - 10:00 PM (Daily)', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Outlet Location Interactive Map Widget Section
            Row(
              children: [
                const Icon(Icons.map_rounded, color: Color(0xFF0284C7), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Map Location',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gps_fixed_rounded, size: 12, color: Color(0xFF0284C7)),
                      const SizedBox(width: 4),
                      Text(
                        '${r.latitude.toStringAsFixed(4)}, ${r.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Embedded Interactive Google Map Container
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    IgnorePointer(
                      ignoring: true,
                      child: GoogleMap(
                        style: AppMapTheme.getMapStyle(isDark),
                        onMapCreated: (ctrl) {
                          AppMapTheme.applyTheme(ctrl, isDark);
                          if (mounted) {
                            setState(() => _isMapLoading = false);
                          }
                        },
                        initialCameraPosition: CameraPosition(
                          target: LatLng(r.latitude, r.longitude),
                          zoom: 15.5,
                        ),
                        markers: {
                          Marker(
                            markerId: MarkerId(r.id),
                            position: LatLng(r.latitude, r.longitude),
                            infoWindow: InfoWindow(
                              title: r.name,
                              snippet: r.address,
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
                    if (_isMapLoading)
                      const BaseSkeleton(
                        width: double.infinity,
                        height: 200,
                        borderRadius: 16,
                      ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFF121212) : Colors.white).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                r.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : AppTheme.navyColor,
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
            ),
            const SizedBox(height: 16),

            // SSM Certificate & AI OCR Evidence Card
            Builder(builder: (ocrCtx) {
              final bool ocrVerified = r.ocrVerified || _ocrMeta?['ocr_verified'] == true;
              final double ocrConf = r.ocrConfidence > 0
                  ? r.ocrConfidence
                  : ((_ocrMeta?['ocr_confidence'] as num?)?.toDouble() ?? 0.0);
              final String? ocrCompany = _firstFilled(r.ocrCompanyName, _ocrMeta?['ocr_company_name']?.toString());
              final String? ocrRegNo = _firstFilled(r.ocrRegistrationNo, _ocrMeta?['ocr_registration_no']?.toString());
              final String? certUrl = _firstFilled(r.ssmCertUrl, _ocrMeta?['ssm_cert_url']?.toString());
              final Color ocrColor = ocrVerified ? const Color(0xFF059669) : (ocrConf >= 0.5 ? const Color(0xFFD97706) : const Color(0xFF64748B));

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.fact_check_rounded, size: 18, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SSM Certificate & AI OCR Evidence',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ocrColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ocrVerified
                                ? 'AI VERIFIED'
                                : (ocrConf >= 0.5 ? 'NEEDS REVIEW' : 'NO OCR DATA'),
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: ocrColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isDark ? Colors.white10 : Colors.grey.shade100,
                            border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: certUrl != null && certUrl.startsWith('http')
                                ? Image.network(
                                    certUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, st) => const Icon(Icons.receipt_long_rounded, size: 32, color: Colors.grey),
                                  )
                                : (certUrl != null && (certUrl.startsWith('/') || certUrl.startsWith('file:'))
                                    ? Image.file(
                                        File(certUrl),
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, st) => const Icon(Icons.receipt_long_rounded, size: 32, color: Colors.grey),
                                      )
                                    : const Icon(Icons.receipt_long_rounded, size: 32, color: Colors.grey)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ocrMetaRow('Company', ocrCompany ?? 'Not extracted', isDark),
                              _ocrMetaRow('SSM Reg No', ocrRegNo ?? 'Not extracted', isDark),
                              _ocrMetaRow(
                                'Confidence',
                                ocrConf > 0 ? '${(ocrConf * 100).toStringAsFixed(0)}%' : 'N/A',
                                isDark,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!ocrVerified && ocrConf < 0.5) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 15),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No credible AI OCR verification is attached to this application. Manually inspect the uploaded certificate before approving.',
                                style: TextStyle(fontSize: 10.5, color: Color(0xFF92400E), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),

            // Revision Note Input Box
            Text(
              'Official Assessment & Notes',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _revisionNoteCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter inspection comments or required revisions...',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade400),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.rate_review_outlined, size: 20),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
              ),
            ),
            const SizedBox(height: 24),

            // Decision Action Buttons
            CustomButton(
              label: 'Approve Outlet',
              icon: Icons.check_circle_rounded,
              backgroundColor: Colors.green.shade700,
              isLoading: _isSubmitting,
              onPressed: () async {
                if (_isSubmitting) return;
                final nav = Navigator.of(context);

                setState(() => _isSubmitting = true);
                final String? ocrRegNo = _firstFilled(r.ocrRegistrationNo, _ocrMeta?['ocr_registration_no']?.toString());
                final String ssmRegNo = ocrRegNo ?? 'SSM-${DateTime.now().year}-${r.id.substring(0, 6).toUpperCase()}-X';
                final notes = _revisionNoteCtrl.text.trim();

                await RestaurantStoreService.updateRestaurantStatus(
                  restaurantId: r.id,
                  status: 'approved',
                  businessRegNo: ssmRegNo,
                  revisionNotes: notes,
                );

                if (!mounted || !context.mounted) return;
                setState(() => _isSubmitting = false);
                HygieneFeedback.showSuccess(
                  context,
                  '${r.name} Approved & Verified! Reg No: $ssmRegNo${ocrRegNo != null ? ' (from AI OCR)' : ''}',
                );
                nav.pop(true);
              },
            ),
            const SizedBox(height: 10),
            CustomButton(
              label: 'Request Revision',
              icon: Icons.edit_note_rounded,
              backgroundColor: Colors.amber.shade800,
              isLoading: _isSubmitting,
              onPressed: () async {
                if (_isSubmitting) return;
                final nav = Navigator.of(context);

                setState(() => _isSubmitting = true);
                final notes = _revisionNoteCtrl.text.trim();

                await RestaurantStoreService.updateRestaurantStatus(
                  restaurantId: r.id,
                  status: 'needsRevision',
                  revisionNotes: notes,
                );

                if (!mounted || !context.mounted) return;
                setState(() => _isSubmitting = false);
                HygieneFeedback.showWarning(context, 'Revision requested for ${r.name}. Notes saved.');
                nav.pop(true);
              },
            ),
            const SizedBox(height: 10),
            CustomButton(
              label: 'Reject Entry',
              icon: Icons.cancel_rounded,
              backgroundColor: Colors.red.shade700,
              isLoading: _isSubmitting,
              onPressed: () async {
                if (_isSubmitting) return;
                final nav = Navigator.of(context);

                setState(() => _isSubmitting = true);
                final notes = _revisionNoteCtrl.text.trim();

                await RestaurantStoreService.updateRestaurantStatus(
                  restaurantId: r.id,
                  status: 'rejected',
                  revisionNotes: notes,
                );

                if (!mounted || !context.mounted) return;
                setState(() => _isSubmitting = false);
                HygieneFeedback.showError(context, 'Application rejected for ${r.name}.');
                nav.pop(true);
              },
            ),
          ],
        ),
      ),
      ),
    );
  }
}
