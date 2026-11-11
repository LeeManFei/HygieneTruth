import 'package:flutter/material.dart';
import '../../core/models/restaurant_model.dart';

class RiskScoreBadge extends StatelessWidget {
  final RiskCategory category;

  const RiskScoreBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    IconData icon;

    switch (category) {
      case RiskCategory.safe:
        bg = const Color(0xFF10B981);
        label = 'SAFE';
        icon = Icons.verified_user_outlined;
        break;
      case RiskCategory.moderate:
        bg = const Color(0xFFF59E0B);
        label = 'MODERATE';
        icon = Icons.warning_amber_outlined;
        break;
      case RiskCategory.high:
        bg = const Color(0xFFEF4444);
        label = 'HIGH RISK';
        icon = Icons.report_problem_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
