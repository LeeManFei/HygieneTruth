import 'package:flutter/material.dart';

class DeadlineCountdownBadge extends StatelessWidget {
  final int daysLeft;
  final bool isResolved;

  const DeadlineCountdownBadge({
    super.key,
    required this.daysLeft,
    this.isResolved = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isResolved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Resolved',
          style: TextStyle(
            color: Colors.blue.shade900,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final isOverdue = daysLeft <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOverdue ? Colors.red.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOverdue ? 'Overdue' : '$daysLeft Days',
        style: TextStyle(
          color: isOverdue ? Colors.red.shade900 : Colors.green.shade900,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
