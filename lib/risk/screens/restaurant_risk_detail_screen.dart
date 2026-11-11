import 'package:flutter/material.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../widgets/risk_score_badge.dart';
import '../widgets/risk_score_gauge.dart';

class RestaurantRiskDetailScreen extends StatelessWidget {
  const RestaurantRiskDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;
    final r = args is RestaurantModel ? args : (RestaurantStoreService.restaurantsNotifier.value.isNotEmpty ? RestaurantStoreService.restaurantsNotifier.value.first : null);
    if (r == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
        appBar: const CustomAppBar(title: 'Risk Details'),
        body: Center(
          child: Text('No restaurant selected', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey)),
        ),
      );
    }
    final eval = RestaurantStoreService.getRestaurantRiskEvaluation(r.id, restaurantName: r.name, fallbackRestaurant: r);
    RestaurantStoreService.recordRecentVisit(r);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Risk Details'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  RiskScoreGauge(score: eval.score, size: 90),
                  const SizedBox(height: 12),
                  RiskScoreBadge(category: eval.category),
                  const SizedBox(height: 8),
                  Text(
                    r.name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                  ),
                  const SizedBox(height: 4),
                  Text(r.address, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Evaluation Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        eval.isFromOfficer ? Icons.verified_user_rounded : Icons.star_rate_rounded,
                        color: eval.isFromOfficer
                            ? (eval.category == RiskCategory.high ? const Color(0xFFDC2626) : const Color(0xFF0F766E))
                            : Colors.amber.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          eval.headline,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: isDark ? Colors.white : AppTheme.navyColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    eval.explanation,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Timestamp Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? const Color(0xFF00A88F).withValues(alpha: 0.3) : Colors.teal.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A88F).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.update, color: Color(0xFF00A88F), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Evaluation Basis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.teal.shade900)),
                        const SizedBox(height: 2),
                        Text('${eval.source} • Last Updated ${r.lastUpdated}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.teal.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Risk Factors',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : AppTheme.navyColor),
            ),
            const SizedBox(height: 12),
            Card(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _factorRow(
                      title: 'Assessment Source',
                      value: eval.isFromOfficer ? 'Officer Audit' : 'Customer Feedback',
                      isNegative: eval.category == RiskCategory.high,
                      isDark: isDark,
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    _factorRow(
                      title: 'Compliance Status',
                      value: eval.category == RiskCategory.safe ? 'Clean & Safe' : (eval.category == RiskCategory.moderate ? 'Monitor Required' : 'Action Required'),
                      isNegative: eval.category != RiskCategory.safe,
                      isDark: isDark,
                    ),
                    Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    _factorRow(
                      title: 'Verified Violations',
                      value: '${r.violationCount} Violations',
                      isNegative: r.violationCount > 0,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            CustomButton(
              label: 'Submit Report',
              icon: Icons.report_problem,
              backgroundColor: Colors.red.shade700,
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.submitComplaint,
                  arguments: r,
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _factorRow({required String title, required String value, required bool isNegative, bool isDark = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
          Row(
            children: [
              Icon(
                isNegative ? Icons.warning_amber : Icons.check_circle,
                size: 16,
                color: isNegative ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isNegative ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
