import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/app_select_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/services/pdf_invoice_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/stripe_payment_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';

void showMOHPaymentGatewayModal(
  BuildContext context, {
  required RestaurantModel restaurant,
  required double fineAmount,
  InspectionModel? inspection,
  String? citation,
  VoidCallback? onPaymentSuccess,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      return MOHPaymentGatewaySheet(
        restaurant: restaurant,
        fineAmount: fineAmount,
        inspection: inspection,
        citation: citation,
        onPaymentSuccess: onPaymentSuccess,
      );
    },
  );
}

class MOHPaymentGatewaySheet extends StatefulWidget {
  final RestaurantModel restaurant;
  final double fineAmount;
  final InspectionModel? inspection;
  final String? citation;
  final VoidCallback? onPaymentSuccess;

  const MOHPaymentGatewaySheet({
    super.key,
    required this.restaurant,
    required this.fineAmount,
    this.inspection,
    this.citation,
    this.onPaymentSuccess,
  });

  @override
  State<MOHPaymentGatewaySheet> createState() => _MOHPaymentGatewaySheetState();
}

class _MOHPaymentGatewaySheetState extends State<MOHPaymentGatewaySheet> {
  String _paymentMethod = 'Card'; // 'Card' (Official Stripe PaymentSheet), 'FPX Online', 'DuitNow'
  String _selectedBank = 'Maybank2u';
  bool _isProcessing = false;
  bool _isSuccess = false;
  String _settledRef = '';
  String _receiptTime = '';
  StripeInvoiceDetail? _testInvoice;
  String? _stripeReceiptUrl;
  String? _stripeChargeId;

  final List<Map<String, String>> _fpxBanks = [
    {'name': 'Maybank2u', 'code': 'MBB'},
    {'name': 'CIMB Clicks', 'code': 'CIMB'},
    {'name': 'Public Bank', 'code': 'PBB'},
    {'name': 'RHB Now', 'code': 'RHB'},
    {'name': 'Hong Leong Connect', 'code': 'HLB'},
    {'name': 'AmBank', 'code': 'AMMB'},
    {'name': 'Bank Islam', 'code': 'BIMB'},
  ];

  String _formatAmount(double amt) {
    final parts = amt.toStringAsFixed(2).split('.');
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formattedInt = parts[0].replaceAllMapped(reg, (Match m) => '${m[1]},');
    return 'RM $formattedInt.${parts[1]}';
  }

  Future<void> _handlePayment() async {
    if (_isProcessing || _isSuccess) return;
    if (widget.inspection == null) {
      HygieneFeedback.showWarning(context, 'Open payment from the specific action notice.');
      return;
    }
    if (_paymentMethod != 'Card') {
      HygieneFeedback.showWarning(context, 'This payment method is not connected yet. Please use the secure card payment option.');
      return;
    }
    setState(() => _isProcessing = true);
    try {

    final String generatedCitation = widget.citation ??
        widget.restaurant.statutoryCitation ??
        widget.inspection?.statutoryCitation ??
        'Food Act 1983 - Section 11 (Unsanitary Conditions)';

    String paymentRef = '';
    String? chargeId;
    String? receiptUrl;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final pendingKey = 'pending_fine_payment_${widget.inspection!.id}';
    final pendingReference = prefs.getString(pendingKey);
    if (pendingReference != null) {
      paymentRef = pendingReference;
    } else if (_paymentMethod == 'Card') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      // Prompt Stripe Official Native Payment Sheet UI
      final stripeResult = await StripePaymentService.presentOfficialPaymentSheet(
        inspectionId: widget.inspection!.id,
        amountInMYR: widget.fineAmount,
        restaurantId: widget.restaurant.id,
        restaurantName: widget.restaurant.name,
        citation: generatedCitation,
        isDark: isDark,
        ownerName: widget.restaurant.ownerName,
      );

      if (!stripeResult.success) {
        if (mounted) {
          setState(() => _isProcessing = false);
          if (stripeResult.status != 'cancelled') {
            HygieneFeedback.showError(
              context,
              stripeResult.errorMessage ?? 'Payment was cancelled or failed.',
            );
          }
        }
        return;
      }

      paymentRef = stripeResult.paymentIntentId!;
      await prefs.setString(pendingKey, paymentRef);
      chargeId = stripeResult.chargeId;
      receiptUrl = stripeResult.receiptUrl;

      // Generate / Fetch Test Invoice from Stripe
      try {
        _testInvoice = await StripePaymentService.createOrFetchTestInvoice(
          amountInMYR: widget.fineAmount,
          restaurantId: widget.restaurant.id,
          restaurantName: widget.restaurant.name,
          citation: generatedCitation,
        );
      } catch (_) {}
    } else {
      setState(() => _isProcessing = false);
      return;
    }

    _stripeChargeId = chargeId;
    _stripeReceiptUrl = receiptUrl;

    final bool settled = await RestaurantStoreService.settleCompoundFine(
      restaurantId: widget.restaurant.id,
      restaurantName: widget.restaurant.name,
      inspectionId: widget.inspection?.id,
      complaintId: widget.inspection?.complaintId,
      paymentReference: paymentRef,
      amountPaid: widget.fineAmount,
      paymentMethod: _paymentMethod == 'FPX Online'
          ? 'FPX ($_selectedBank)'
          : (_paymentMethod == 'Card' ? 'Stripe Card ($paymentRef)' : 'DuitNow QR'),
      statutoryCitation: generatedCitation,
      invoiceUrl: _testInvoice?.hostedInvoiceUrl,
      receiptUrl: receiptUrl,
      stripeChargeId: chargeId,
      metadata: {
        'stripe_payment_intent_id': paymentRef,
        'fpx_bank': _paymentMethod == 'FPX Online' ? _selectedBank : null,
        'invoice_id': _testInvoice?.id,
        'invoice_number': _testInvoice?.number,
      },
    );

    if (settled) {
      await prefs.remove(pendingKey);
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isSuccess = true;
          _settledRef = paymentRef;
          _receiptTime = DateTime.now().toLocal().toString().split('.').first;
        });
        HygieneFeedback.showSuccess(context, 'MOH Compound fine successfully settled!');
      }
      widget.onPaymentSuccess?.call();
    } else {
      if (mounted) {
        setState(() => _isProcessing = false);
        HygieneFeedback.showError(context, 'Your payment confirmation is pending. Try again to check the same payment; you will not be charged again.');
      }
    }    } catch (e) {
      if (mounted) HygieneFeedback.showError(context, 'Payment confirmation is unavailable. Please check your connection.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String citation = widget.citation ??
        widget.restaurant.statutoryCitation ??
        widget.inspection?.statutoryCitation ??
        'Food Act 1983 - Section 11 (Unsanitary Conditions)';

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isSuccess
              ? _buildSuccessReceiptView(isDark)
              : _buildPaymentFormView(isDark, citation),
        ),
      ),
    );
  }

  Widget _buildPaymentFormView(bool isDark, String citation) {
    final formattedPenalty = _formatAmount(widget.fineAmount);

    return SingleChildScrollView(
      key: const ValueKey('PaymentFormView'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Government Seal
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_balance_rounded, color: Color(0xFF0F766E), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MOH Statutory Fine Gateway',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ministry of Health Malaysia (KKM) / DBKL',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: isDark ? Colors.white54 : Colors.grey.shade500,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 22),

          // Penalty Breakdown Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Premises Name:', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                    Flexible(
                      child: Text(
                        widget.restaurant.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Statutory Citation:', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                    Flexible(
                      child: Text(
                        citation,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Due Date:', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                    Text(
                      widget.restaurant.fineDueDate ?? '7-Day Statutory Term',

                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Penalty to Settle:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                      ),
                    ),
                    Text(
                      formattedPenalty,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Payment Channel Selector
          Text(
            'Select Payment Method',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.navyColor,
            ),
          ),
          const SizedBox(height: 10),

          // 3 Consistent Payment Method Cards
          Row(
            children: [
              Expanded(
                child: _buildPaymentMethodCard(
                  method: 'FPX Online',
                  icon: Icons.account_balance_rounded,
                  label: 'FPX (Unavailable)',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPaymentMethodCard(
                  method: 'Card',
                  icon: Icons.credit_card_rounded,
                  label: 'Card',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPaymentMethodCard(
                  method: 'DuitNow',
                  icon: Icons.qr_code_2_rounded,
                  label: 'DuitNow (Unavailable)',
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Dynamic Payment Sub-Views
          if (_paymentMethod == 'FPX Online') _buildFPXSelector(isDark),
          if (_paymentMethod == 'Card') _buildStripeCardFields(isDark),
          if (_paymentMethod == 'DuitNow') _buildDuitNowQR(isDark),

          const SizedBox(height: 18),

          // Security Notice
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _paymentMethod == 'Card'
                      ? 'Stripe PCI-DSS Level 1 certified SSL 256-bit encrypted government settlement.'
                      : '256-bit encrypted government settlement gateway. Clearance is applied in real-time.',
                  style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Pay Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              onPressed: _isProcessing ? null : _handlePayment,
              child: _isProcessing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(
                          _paymentMethod == 'Card'
                              ? 'Launching Official Stripe Checkout...'
                              : 'Processing Settlement...',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : Text(
                      'Confirm & Pay $formattedPenalty',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard({
    required String method,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final bool isSelected = _paymentMethod == method;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: method == 'Card' && !_isProcessing
            ? () => setState(() => _paymentMethod = method)
            : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0F766E)
                : (isDark ? const Color(0xFF161616) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0F766E)
                  : (isDark ? Colors.white12 : Colors.grey.shade300),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppTheme.navyColor),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : (isDark ? Colors.white : AppTheme.navyColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFPXSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Malaysian FPX Bank:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppTheme.navyColor,
          ),
        ),
        const SizedBox(height: 6),
        AppSelectField<String>(
          initialValue: _selectedBank,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.account_balance_rounded, color: Color(0xFF0F766E)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          items: _fpxBanks.map((b) {
            return DropdownMenuItem(
              value: b['name'],
              child: Text('${b["name"]} (${b["code"]})', style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedBank = val);
          },
        ),
      ],
    );
  }

  Widget _buildStripeCardFields(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'STRIPE',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Official Stripe Native Checkout',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.navyColor,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.verified_user_rounded, size: 18, color: Color(0xFF0F766E)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.credit_card_rounded, color: Color(0xFF6366F1), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure Card & Digital Wallet',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Accepts Visa, Mastercard, AMEX, Apple Pay & Google Pay',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_rounded, size: 14, color: isDark ? Colors.indigo.shade300 : const Color(0xFF4F46E5)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Tapping Confirm will launch Stripe\'s official PaymentSheet UI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.indigo.shade300 : const Color(0xFF4F46E5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDuitNowQR(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFED1C24).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFED1C24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('DuitNow QR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              const Text('National QR Standard', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Icon(Icons.qr_code_2_rounded, size: 110, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Scan with any Malaysian Banking / eWallet App', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSuccessReceiptView(bool isDark) {
    final formattedPaid = _formatAmount(widget.fineAmount);

    return SingleChildScrollView(
      key: const ValueKey('SuccessReceiptView'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 48),
          ),
          const SizedBox(height: 14),
          Text(
            'Statutory Penalty Settled',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.navyColor,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Official MOH Legal Clearance Confirmed',
            style: TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),

          // Official Receipt Details Box
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161616) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.25), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: isDark ? 0.05 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildReceiptRow('Premises', widget.restaurant.name, isDark),
                const SizedBox(height: 10),
                _buildReceiptRow('Amount Paid', formattedPaid, isDark, isHighlighted: true),
                const SizedBox(height: 10),
                _buildReceiptRow('Payment Method', _paymentMethod == 'Card' ? 'Stripe Card Gateway' : (_paymentMethod == 'FPX Online' ? 'FPX ($_selectedBank)' : 'DuitNow QR'), isDark),
                const SizedBox(height: 10),
                _buildReceiptRow('Gateway Ref ID', _settledRef, isDark),
                const SizedBox(height: 10),
                _buildReceiptRow('Timestamp', _receiptTime, isDark),
                const Divider(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 18),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'STATUS: PREMISE RESTORATION UNLOCKED',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669), letterSpacing: 0.4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Download PDF Invoice Button
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
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
              label: const Text(
                'Download Official PDF Invoice',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              onPressed: () {
                final invNumber = _testInvoice?.number ??
                    'MOH-INV-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                final String citation = widget.citation ??
                    widget.restaurant.statutoryCitation ??
                    widget.inspection?.statutoryCitation ??
                    'Food Act 1983 - Section 11';
                PdfInvoiceService.downloadOrPrintInvoice(
                  invoiceNumber: invNumber,
                  paymentReference: _settledRef,
                  chargeId: _stripeChargeId,
                  restaurantName: widget.restaurant.name,
                  ownerName: widget.restaurant.ownerName,
                  premiseAddress: widget.restaurant.address,
                  statutoryCitation: citation,
                  amountPaid: widget.fineAmount,
                  settledAt: _receiptTime.isNotEmpty
                      ? _receiptTime
                      : DateTime.now().toLocal().toString().split('.').first,
                  receiptUrl: _stripeReceiptUrl,
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Open Built-in Stripe Hosted Receipt / Invoice (if available)
          if ((_stripeReceiptUrl != null && _stripeReceiptUrl!.isNotEmpty) ||
              (_testInvoice?.hostedInvoiceUrl != null && _testInvoice!.hostedInvoiceUrl!.isNotEmpty) ||
              (_testInvoice?.invoicePdf != null && _testInvoice!.invoicePdf!.isNotEmpty)) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1), width: 1.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text(
                  'Open Official Stripe Receipt & PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  final url = _stripeReceiptUrl ??
                      _testInvoice?.invoicePdf ??
                      _testInvoice?.hostedInvoiceUrl ??
                      '';
                  if (url.isNotEmpty) {
                    StripePaymentService.openUrl(url);
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
          ],

          // View Invoice / Receipt Breakdown Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                foregroundColor: isDark ? Colors.white : AppTheme.navyColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text(
                'View Itemized Breakdown & Seal',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: () => _showInvoiceDialog(context, isDark),
            ),
          ),
          const SizedBox(height: 8),

          // Done Button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.white60 : Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done & Return to Notice Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  void _showInvoiceDialog(BuildContext context, bool isDark) {
    final formattedAmt = _formatAmount(widget.fineAmount);
    final invNumber = _testInvoice?.number ?? 'MOH-INV-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final String citation = widget.citation ??
        widget.restaurant.statutoryCitation ??
        widget.inspection?.statutoryCitation ??
        'Food Act 1983 - Section 11';

    showDialog(
      context: context,
      builder: (dlgCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          contentPadding: EdgeInsets.zero,
          content: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Premium Government Header Banner
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 22),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'STATUTORY INVOICE',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: 0.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'MINISTRY OF HEALTH MALAYSIA',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.4),
                          ),
                          const Text(
                            'Food Safety and Quality Statutory Enforcement',
                            style: TextStyle(fontSize: 11, color: Color(0xFFCCFBF1)),
                          ),
                        ],
                      ),
                    ),

                    // Content Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Invoice Metadata Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Invoice No:', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                    InkWell(
                                      onTap: () {
                                        final url = _testInvoice?.invoicePdf ?? _testInvoice?.hostedInvoiceUrl;
                                        if (url != null && url.isNotEmpty) {
                                          StripePaymentService.openUrl(url);
                                        }
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            invNumber,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0F766E),
                                              decoration: (_testInvoice?.hostedInvoiceUrl != null) ? TextDecoration.underline : TextDecoration.none,
                                            ),
                                          ),
                                          if (_testInvoice?.hostedInvoiceUrl != null) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF0F766E)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Payment Ref:', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                    Flexible(
                                      child: Text(_settledRef, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                                if (_stripeChargeId != null && _stripeChargeId!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Transaction ID:', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(_stripeChargeId!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)), overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_stripeReceiptUrl != null && _stripeReceiptUrl!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Official Receipt:', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: InkWell(
                                          onTap: () => StripePaymentService.openUrl(_stripeReceiptUrl!),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Flexible(
                                                child: Text(
                                                  'View Stripe Receipt',
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669), decoration: TextDecoration.underline),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(width: 4),
                                              Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF059669)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Issued To:', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(widget.restaurant.name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Itemized Breakdown Table
                          Text('Itemized Settlement Breakdown', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('1. Statutory Fine Penalty', style: TextStyle(fontSize: 11.5)),
                                      Text(formattedAmt, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: const [
                                      Text('2. MOH Digital Filing Fee', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                                      Text('RM 0.00 (Waived)', style: TextStyle(fontSize: 11.5, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: const [
                                      Text('3. SST (0%)', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                                      Text('RM 0.00', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.2 : 0.08),
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Total Settled:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                      Text(formattedAmt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Legal Clearance Stamp
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 15),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Payment Status: OFFICIALLY CLEARED & RECORDED',
                                    style: TextStyle(fontSize: 9.8, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // PDF Download & Share Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F766E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 2,
                                  ),
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                                  label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  onPressed: () {
                                    PdfInvoiceService.downloadOrPrintInvoice(
                                      invoiceNumber: invNumber,
                                      paymentReference: _settledRef,
                                      chargeId: _stripeChargeId,
                                      restaurantName: widget.restaurant.name,
                                      ownerName: widget.restaurant.ownerName,
                                      premiseAddress: widget.restaurant.address,
                                      statutoryCitation: citation,
                                      amountPaid: widget.fineAmount,
                                      settledAt: _receiptTime.isNotEmpty
                                          ? _receiptTime
                                          : DateTime.now().toLocal().toString().split('.').first,
                                      receiptUrl: _stripeReceiptUrl,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                  side: const BorderSide(color: Color(0xFF0F766E), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.share_rounded, size: 18, color: Color(0xFF0F766E)),
                                label: const Text('Share', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontSize: 12.5)),
                                onPressed: () {
                                  PdfInvoiceService.shareInvoicePdf(
                                    invoiceNumber: invNumber,
                                    paymentReference: _settledRef,
                                    chargeId: _stripeChargeId,
                                    restaurantName: widget.restaurant.name,
                                    ownerName: widget.restaurant.ownerName,
                                    premiseAddress: widget.restaurant.address,
                                    statutoryCitation: citation,
                                    amountPaid: widget.fineAmount,
                                    settledAt: _receiptTime.isNotEmpty
                                        ? _receiptTime
                                        : DateTime.now().toLocal().toString().split('.').first,
                                    receiptUrl: _stripeReceiptUrl,
                                  );
                                },
                              ),
                            ],
                          ),
                          if ((_stripeReceiptUrl != null && _stripeReceiptUrl!.isNotEmpty) ||
                              (_testInvoice?.hostedInvoiceUrl != null && _testInvoice!.hostedInvoiceUrl!.isNotEmpty) ||
                              (_testInvoice?.invoicePdf != null && _testInvoice!.invoicePdf!.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.open_in_browser_rounded, size: 16, color: Color(0xFF6366F1)),
                                label: const Text(
                                  'Open Official Stripe Receipt & PDF',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1), fontSize: 12),
                                ),
                                onPressed: () {
                                  final url = _stripeReceiptUrl ??
                                      _testInvoice?.invoicePdf ??
                                      _testInvoice?.hostedInvoiceUrl ??
                                      '';
                                  if (url.isNotEmpty) {
                                    StripePaymentService.openUrl(url);
                                  }
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: isDark ? Colors.white60 : Colors.grey.shade700,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => Navigator.pop(dlgCtx),
                              child: const Text('Close Invoice', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptRow(String label, String value, bool isDark, {bool isHighlighted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isHighlighted
                  ? const Color(0xFF059669)
                  : (isDark ? Colors.white : AppTheme.navyColor),
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
