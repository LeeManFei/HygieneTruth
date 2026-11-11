import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Each item reflects its own evidence; paying a fine does not complete review.
class OwnerComplianceChecklist extends StatelessWidget {
  final bool submitted,
      reviewed,
      closed,
      hasFine,
      paid,
      canSubmit,
      scheduled,
      expired;
  const OwnerComplianceChecklist({
    super.key,
    required this.submitted,
    required this.reviewed,
    required this.closed,
    required this.hasFine,
    required this.paid,
    required this.canSubmit,
    this.scheduled = false,
    this.expired = false,
  });

  List<({String title, String status, bool done})> get steps => [
    (
      title: 'Rectification photos',
      status: submitted
          ? 'Submitted'
          : closed
          ? 'Completed through authority closure'
          : canSubmit
          ? 'Action needed: upload your photos'
          : scheduled
          ? 'Awaiting scheduled inspection'
          : expired
          ? 'Submission window ended; officer review pending'
          : 'Check the notice requirements',
      done: submitted || closed,
    ),
    (
      title: 'Evidence review',
      status: reviewed
          ? 'Approved'
          : closed
          ? 'Completed through authority closure'
          : submitted
          ? 'Awaiting authority review'
          : 'Waiting for evidence',
      done: reviewed || closed,
    ),
    (
      title: 'Outstanding payment',
      status: !hasFine
          ? 'Not required — no fine currently recorded'
          : paid
          ? 'Paid'
          : 'Action needed: settle the issued fine',
      done: !hasFine || paid,
    ),
    (
      title: 'Case closure',
      status: closed
          ? 'Closed by authority'
          : reviewed && (!hasFine || paid)
          ? 'Awaiting final authority closure'
          : 'Pending remaining requirements',
      done: closed,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkSurfaceColor : const Color(0xFFF3FAF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppTheme.darkBorderColor : const Color(0xFFD5E7E5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compliance checklist',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : AppTheme.navyColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Evidence, payment and closure are tracked separately.',
            style: TextStyle(
              fontSize: 12,
              color: dark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: step.done
                        ? accent
                        : (dark ? Colors.white54 : const Color(0xFF64748B)),
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: dark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          step.status,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: dark
                                ? Colors.white70
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
