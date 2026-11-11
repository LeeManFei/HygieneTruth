import '../../core/widgets/app_search_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/audit_log_model.dart';
import '../../core/models/payment_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/pdf_invoice_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/stripe_payment_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/dual_arc_loader.dart';
import '../../core/widgets/shimmer_skeletons.dart';

class OwnerActionHistoryScreen extends StatefulWidget {
  const OwnerActionHistoryScreen({super.key});

  @override
  State<OwnerActionHistoryScreen> createState() => _OwnerActionHistoryScreenState();
}

class _OwnerActionHistoryScreenState extends State<OwnerActionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = 'All';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<AuditLogModel> _allLogs = [];
  int _displayedCount = 8;
  final int _pageSize = 8;
  String _searchQuery = '';

  final List<String> _categories = [
    'All',
    'Business',
    'Finance',
    'Account',
    'Session',
  ];

  @override
  void initState() {
    super.initState();
    _loadOwnerLogs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150 &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMoreLogs();
    }
  }

  Future<void> _loadOwnerLogs() async {
    setState(() => _isLoading = true);
    final user = CustomerStoreService.currentCustomer;
    final fetched = await AuditLogService.fetchUserLogs(userId: user?.id);

    fetched.removeWhere((l) =>
        l.title.toLowerCase().contains('cross-portal') ||
        l.category.toLowerCase().contains('unauthorized portal') ||
        l.description.toLowerCase().contains('cross-portal') ||
        l.description.toLowerCase().contains('rejected attempting to login'));

    fetched.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {
        _allLogs = fetched;
        _displayedCount = _pageSize;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreLogs() async {
    final filtered = _getFilteredLogs();
    if (_displayedCount >= filtered.length) return;

    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() {
        _displayedCount = (_displayedCount + _pageSize).clamp(0, filtered.length);
        _isLoadingMore = false;
      });
    }
  }

  List<AuditLogModel> _getFilteredLogs() {
    return _allLogs.where((log) {
      final group = _resolveGroup(log.category, log.actionType);

      if (_selectedCategory != 'All' && group != _selectedCategory) {
        return false;
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchTitle = log.title.toLowerCase().contains(query);
        final matchDesc = log.description.toLowerCase().contains(query);
        final matchType = log.actionType.toLowerCase().contains(query);
        return matchTitle || matchDesc || matchType;
      }

      return true;
    }).toList();
  }

  String _resolveGroup(String category, String actionType) {
    final lowAct = actionType.toLowerCase();
    final lowCat = category.toLowerCase();

    if (lowAct.contains('fine') ||
        lowAct.contains('payment') ||
        lowAct.contains('compound') ||
        lowCat.contains('financ') ||
        lowCat.contains('payment')) {
      return 'Finance';
    }
    if (lowAct.contains('rest') ||
        lowAct.contains('outlet') ||
        lowAct.contains('rectification') ||
        lowAct.contains('review') ||
        lowAct.contains('business') ||
        lowCat.contains('business')) {
      return 'Business';
    }
    if (lowAct.contains('login') ||
        lowAct.contains('logout') ||
        lowAct.contains('session') ||
        lowAct.contains('register') ||
        lowCat.contains('session')) {
      return 'Session';
    }
    return 'Account';
  }

  Map<String, dynamic> _getGroupStyle(String category, String actionType) {
    switch (_resolveGroup(category, actionType)) {
      case 'Finance':
        return {
          'icon': Icons.payments_rounded,
          'color': const Color(0xFF059669),
          'tag': 'Finance',
        };
      case 'Business':
        final lowAct = actionType.toLowerCase();
        return {
          'icon': lowAct.contains('rectification')
              ? Icons.fact_check_rounded
              : lowAct.contains('review')
                  ? Icons.rate_review_rounded
                  : lowAct.contains('delete')
                      ? Icons.delete_sweep_rounded
                      : Icons.storefront_rounded,
          'color': const Color(0xFF0F766E),
          'tag': 'Business',
        };
      case 'Session':
        return {
          'icon': Icons.verified_user_rounded,
          'color': const Color(0xFF0284C7),
          'tag': 'Session',
        };
      default:
        return {
          'icon': Icons.person_pin_rounded,
          'color': const Color(0xFF7C3AED),
          'tag': 'Account',
        };
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');

    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return 'Today, $hour:$min';
    } else if (now.year == dt.year && now.month == dt.month && now.day - dt.day == 1) {
      return 'Yesterday, $hour:$min';
    }
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$min';
  }

  String _formatFullTimestamp(DateTime dt) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} at $hour:$min';
  }

  void _showRecordDetailSheet(AuditLogModel log) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = _getGroupStyle(log.category, log.actionType);
    final IconData icon = style['icon'] as IconData;
    final Color color = style['color'] as Color;
    final String tag = style['tag'] as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final bool isFineSettlement = log.actionType.toUpperCase().contains('FINE_SETTLED');
        _FinanceResolution? resolution;
        bool downloadingPdf = false;
        bool resolutionStarted = false;

        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            if (isFineSettlement && !resolutionStarted) {
              resolutionStarted = true;
              _resolveFinanceRecord(log).then((res) {
                if (sheetCtx.mounted) setSheetState(() => resolution = res);
              });
            }

            return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.navyColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  log.description,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                const SizedBox(height: 14),
                _detailRow('Action Type', log.actionType, isDark),
                _detailRow('Recorded For', log.userEmail.isNotEmpty ? log.userEmail : 'Owner Account', isDark),
                _detailRow('Exact Time', _formatFullTimestamp(log.timestamp), isDark),
                if (isFineSettlement) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: resolution == null || downloadingPdf
                          ? null
                          : () async {
                              setSheetState(() => downloadingPdf = true);
                              await _downloadInvoicePdf(resolution!);
                              if (sheetCtx.mounted) setSheetState(() => downloadingPdf = false);
                            },
                      icon: downloadingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(
                        downloadingPdf ? 'Preparing Invoice...' : 'Download HygieneTruth Invoice (PDF)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  if (resolution?.stripeUrl != null && resolution!.stripeUrl!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Color(0xFF635BFF)),
                          foregroundColor: const Color(0xFF635BFF),
                        ),
                        onPressed: () async {
                          final ok = await StripePaymentService.openUrl(resolution!.stripeUrl!);
                          if (!ok && mounted) {
                            HygieneFeedback.showError(context, 'Could not open the Stripe receipt link.');
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Open Stripe Receipt / Invoice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                    ),
                    onPressed: () => Navigator.pop(sheetCtx),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Close Record', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<_FinanceResolution> _resolveFinanceRecord(AuditLogModel log) async {
    final desc = log.description;
    final refMatch = RegExp(r'Ref:\s*(.+?)\s*\(').firstMatch(desc);
    final amtMatch = RegExp(r'RM\s*([\d,]+\.\d{2})').firstMatch(desc);
    final nameMatch = RegExp(r'confirmed for (.+?)\. Ref:').firstMatch(desc);
    final methodMatch = RegExp(r'\(((?:Stripe|FPX|DuitNow)[^)]*)\)').firstMatch(desc);

    final String reference = refMatch?.group(1)?.trim() ?? '';
    final double amount = double.tryParse((amtMatch?.group(1) ?? '').replaceAll(',', '')) ?? 0.0;
    final String restaurantName = nameMatch?.group(1)?.trim() ?? 'Registered Premise';

    final resolution = _FinanceResolution(
      payment: PaymentModel(
        id: 'pay_hist_${log.id}',
        restaurantId: '',
        restaurantName: restaurantName,
        amount: amount,
        paymentMethod: methodMatch?.group(1)?.trim() ?? 'Card Settlement',
        paymentReference: reference,
        statutoryCitation: 'Food Act 1983 - Section 11',
        paidAt: log.timestamp.toIso8601String(),
        createdAt: log.timestamp.toIso8601String(),
      ),
    );

    if (reference.isEmpty) return resolution;

    try {
      final dbPayment = await StripePaymentService.getPaymentByReference(reference).timeout(const Duration(seconds: 5));
      if (dbPayment != null) {
        resolution.payment = dbPayment;
        resolution.stripeUrl = dbPayment.receiptUrl ?? dbPayment.invoiceUrl;
        resolution.chargeId = dbPayment.stripeChargeId;
      }
    } catch (_) {}

    if (reference.startsWith('pi_')) {
      try {
        final details = await StripePaymentService.fetchPaymentDetails(reference).timeout(const Duration(seconds: 6));
        if (details.isNotEmpty) {
          final liveCharge = details['charge_id']?.toString();
          if (liveCharge != null && liveCharge.isNotEmpty) resolution.chargeId = liveCharge;
          final liveReceipt = details['receipt_url']?.toString();
          if (liveReceipt != null &&
              liveReceipt.isNotEmpty &&
              (resolution.stripeUrl == null || resolution.stripeUrl!.trim().isEmpty)) {
            resolution.stripeUrl = liveReceipt;
          }
        }
      } catch (_) {}
    }

    return resolution;
  }

  Future<void> _downloadInvoicePdf(_FinanceResolution resolution) async {
    final payment = resolution.payment;
    try {
      final matches = RestaurantStoreService.restaurantsNotifier.value.where(
        (r) => r.name.toLowerCase() == payment.restaurantName.toLowerCase(),
      );
      final String premiseAddress = matches.isNotEmpty ? matches.first.address : 'Registered Premise, Malaysia';
      await PdfInvoiceService.downloadOrPrintInvoice(
        invoiceNumber: payment.receiptNumber ?? 'MOH-INV-${DateTime.now().millisecondsSinceEpoch}',
        paymentReference: payment.paymentReference,
        chargeId: resolution.chargeId,
        restaurantName: payment.restaurantName,
        ownerName: CustomerStoreService.currentCustomer?.name ?? 'Premises Licensee',
        premiseAddress: premiseAddress,
        statutoryCitation: payment.statutoryCitation ?? 'Food Act 1983 - Section 11',
        amountPaid: payment.amount,
        settledAt: payment.paidAt,
        receiptUrl: payment.receiptUrl,
      );
      if (mounted) {
        HygieneFeedback.showSuccess(
          context,
          'HygieneTruth invoice generated. Use the print dialog to save or share the PDF.',
        );
      }
    } catch (e) {
      if (mounted) {
        HygieneFeedback.showError(context, 'Failed to generate invoice: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = CustomerStoreService.currentCustomer;
    final filteredLogs = _getFilteredLogs();
    final paginatedLogs = filteredLogs.take(_displayedCount).toList();

    final int businessCount = _allLogs.where((l) => _resolveGroup(l.category, l.actionType) == 'Business').length;
    final int financeCount = _allLogs.where((l) => _resolveGroup(l.category, l.actionType) == 'Finance').length;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackgroundColor : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Action History Log',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Records',
            onPressed: _loadOwnerLogs,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const SettingsHistorySkeleton()
            : RefreshIndicator(
              onRefresh: _loadOwnerLogs,
              color: AppTheme.primaryColor,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                            : [const Color(0xFF0C2340), const Color(0xFF0F766E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.history_edu_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? 'Owner Account',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? 'Business activity audit trail',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _headerStat('$businessCount', 'Business'),
                                  const SizedBox(width: 8),
                                  _headerStat('$financeCount', 'Finance'),
                                  const SizedBox(width: 8),
                                  _headerStat('${_allLogs.length}', 'Total'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: AppSearchField(suggestions: _allLogs.map((l) => l.title).toList(),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim();
                          _displayedCount = _pageSize;
                        });
                      },
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search records by keyword or action...',
                        hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat),
                              selected: isSelected,
                              selectedColor: const Color(0xFF0F766E),
                              backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedCategory = val ? cat : 'All';
                                  _displayedCount = _pageSize;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: filteredLogs.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: paginatedLogs.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == paginatedLogs.length) {
                                return _buildLoadingMoreIndicator(isDark);
                              }

                              final log = paginatedLogs[index];
                              final style = _getGroupStyle(log.category, log.actionType);
                              final IconData icon = style['icon'] as IconData;
                              final Color iconColor = style['color'] as Color;
                              final String tag = style['tag'] as String;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _showRecordDetailSheet(log),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: iconColor.withValues(alpha: 0.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(icon, color: iconColor, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        log.title,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                          color: isDark ? Colors.white : AppTheme.navyColor,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: iconColor.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        tag,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: iconColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  log.description,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                                    height: 1.3,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.access_time_rounded,
                                                      size: 12,
                                                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _formatTimestamp(log.timestamp),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Icon(
                                                      Icons.chevron_right_rounded,
                                                      size: 16,
                                                      color: isDark ? Colors.white24 : Colors.grey.shade400,
                                                    ),
                                                  ],
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
                          ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _headerStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DualArcLoader(
            size: 20,
            strokeWidth: 2.2,
            color: isDark ? Colors.tealAccent : const Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading more records...',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                size: 40,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No Action Records Found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Every business action you take such as paying fines, submitting rectification evidence, replying to reviews or managing outlets will be recorded here for tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceResolution {
  PaymentModel payment;
  String? stripeUrl;
  String? chargeId;

  _FinanceResolution({required this.payment});
}
