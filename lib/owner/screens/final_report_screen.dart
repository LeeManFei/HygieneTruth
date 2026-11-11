import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/services/pdf_invoice_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';

class FinalReportScreen extends StatelessWidget {
  const FinalReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;
    ComplaintModel? c;
    if (args is ComplaintModel) {
      c = args;
    } else if (RestaurantStoreService.complaintsNotifier.value.isNotEmpty) {
      c = RestaurantStoreService.complaintsNotifier.value.last;
    }

    if (c == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Compliance Report'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_outlined, size: 52, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No compliance report available.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    final String noticeId = c.id.startsWith('CMP-') || c.id.startsWith('cmp_')
        ? c.id.toUpperCase().replaceAll('_', '-')
        : 'CMP-${c.id.length > 8 ? c.id.substring(0, 8).toUpperCase() : c.id.toUpperCase()}';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Compliance & Resolution Report'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Official MOH Verified Certificate Card
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18181B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF059669).withValues(alpha: isDark ? 0.08 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Top Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'MINISTRY OF HEALTH MALAYSIA',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                                ),
                                Text(
                                  'Statutory Case Resolution Certificate',
                                  style: TextStyle(fontSize: 10.5, color: Color(0xFFCCFBF1)),
                                ),
                              ],
                            )),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'CLEARED',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Certificate Body
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(Icons.verified_rounded, size: 56, color: Color(0xFF059669)),
                        const SizedBox(height: 10),
                        Text(
                          c.restaurantName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Notice Reference: $noticeId',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 14),

                        // Green Status Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'CASE RESOLVED & COMPLIANCE RESTORED',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669), letterSpacing: 0.3),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 28),

                        // Details Breakdown
                        _reportRow('Inspection Outcome', 'Compliant (Verified by MOH)', isDark),
                        const SizedBox(height: 8),
                        _reportRow('Enforcement Action', 'Rectification Approved', isDark),
                        const SizedBox(height: 8),
                        _reportRow('Statutory Fine Penalty', 'Settled (RM 0.00 Outstanding)', isDark, isHighlight: true),
                        const SizedBox(height: 8),
                        _reportRow('Report Submitted', DateTime.tryParse(c.submittedAt) == null ? 'Not recorded' : '${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(c.submittedAt).toLocal())}, ${TimeOfDay.fromDateTime(DateTime.parse(c.submittedAt).toLocal()).format(context)}', isDark),
                        const SizedBox(height: 8),
                        _reportRow('Premise Legal Status', 'Grade A Operational Compliance', isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text(
                  'Download Resolution Certificate (PDF)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  final invNumber = 'MOH-RES-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                  PdfInvoiceService.downloadOrPrintInvoice(
                    invoiceNumber: invNumber,
                    paymentReference: 'case_resolved_certified',
                    chargeId: null,
                    restaurantName: c!.restaurantName,
                    ownerName: 'Premises Licensee',
                    premiseAddress: 'Verified Registered Location',
                    statutoryCitation: 'Food Act 1983 - Section 11 Compliance Clearance',
                    amountPaid: 0.0,
                    settledAt: DateTime.now().toLocal().toString().split('.').first,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : AppTheme.navyColor,
                  side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Return to Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _reportRow(String key, String val, bool isDark, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(key, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
        Flexible(
          child: Text(
            val,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isHighlight
                  ? const Color(0xFF059669)
                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
