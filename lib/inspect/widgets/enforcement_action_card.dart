import 'package:flutter/material.dart';
import '../../core/models/inspection_model.dart';
import '../../core/widgets/status_badge.dart';

class EnforcementActionCard extends StatelessWidget {
  final InspectionModel inspection;
  final VoidCallback? onTap;

  const EnforcementActionCard({
    super.key,
    required this.inspection,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color cardColor;
    switch (inspection.issuedAction) {
      case EnforcementType.closure:
        cardColor = Colors.red.shade50;
        break;
      case EnforcementType.fine:
        cardColor = Colors.amber.shade50;
        break;
      case EnforcementType.warning:
        cardColor = Colors.blue.shade50;
        break;
      case EnforcementType.none:
        cardColor = Colors.grey.shade50;
        break;
    }

    return Card(
      color: cardColor,
      child: ListTile(
        onTap: onTap,
        title: Text(inspection.restaurantName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Action: ${inspection.issuedAction.name.toUpperCase()} • Status: ${inspection.enforcementStatus.name}'),
            if (inspection.fineAmount > 0)
              Text('Fine: RM ${inspection.fineAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            Text('Officer: ${inspection.officerName}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: StatusBadge.fromStatus(inspection.enforcementStatus.name),
      ),
    );
  }
}
