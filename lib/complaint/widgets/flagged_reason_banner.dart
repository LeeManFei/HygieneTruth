import 'package:flutter/material.dart';

class FlaggedReasonBanner extends StatelessWidget {
  final String reason;

  const FlaggedReasonBanner({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: Colors.red.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FLAGGED FOR ADMIN REVIEW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                Text(
                  reason,
                  style: TextStyle(fontSize: 13, color: Colors.red.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
