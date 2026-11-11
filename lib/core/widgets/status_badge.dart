import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  final bool isOnDark;
  final bool isSolid;
  final bool isOnImage;

  const StatusBadge({
    super.key,
    required this.text,
    required this.backgroundColor,
    this.textColor = Colors.white,
    this.icon,
    this.isOnDark = false,
    this.isSolid = false,
    this.isOnImage = false,
  });

  factory StatusBadge.fromStatus(
    String statusStr, {
    bool isOnDark = false,
    bool isSolid = false,
    bool isOnImage = false,
  }) {
    Color bg = const Color(0xFF64748B);
    Color fg = const Color(0xFF334155);
    Color darkFg = Colors.white;
    IconData? iconData;

    String label = statusStr;

    final normalized = statusStr.toLowerCase().replaceAll('_', '').replaceAll(' ', '');

    switch (normalized) {
      case 'completed':
      case 'resolved':
      case 'approved':
      case 'active':
      case 'compliant':
        label = normalized == 'compliant'
            ? 'Compliant'
            : (normalized == 'completed'
                ? 'Completed'
                : (normalized == 'resolved' ? 'Resolved' : 'Approved'));
        bg = const Color(0xFF10B981);
        fg = const Color(0xFF047857);
        darkFg = const Color(0xFFD1FAE5);
        iconData = Icons.check_circle_outline_rounded;
        break;

      case 'inprogress':
      case 'enforcing':
        label = 'In Progress';
        bg = const Color(0xFFF59E0B);
        fg = const Color(0xFFB45309);
        darkFg = const Color(0xFFFEF3C7);
        iconData = Icons.pending_actions_rounded;
        break;

      case 'investigating':
        label = 'Investigating';
        bg = const Color(0xFF0284C7);
        fg = const Color(0xFF0369A1);
        darkFg = const Color(0xFFE0F2FE);
        iconData = Icons.search_rounded;
        break;

      case 'inspecting':
        label = 'Inspecting';
        bg = const Color(0xFF7C3AED);
        fg = const Color(0xFF6D28D9);
        darkFg = const Color(0xFFEDE9FE);
        iconData = Icons.fact_check_rounded;
        break;

      case 'pendinginspection':
      case 'scheduled':
        label = 'Visit Scheduled';
        bg = const Color(0xFF0284C7);
        fg = const Color(0xFF0369A1);
        darkFg = const Color(0xFFE0F2FE);
        iconData = Icons.calendar_today_rounded;
        break;

      case 'underreview':
        label = 'Under Review';
        bg = const Color(0xFFF59E0B);
        fg = const Color(0xFFB45309);
        darkFg = const Color(0xFFFEF3C7);
        iconData = Icons.rate_review_rounded;
        break;

      case 'submitted':
      case 'pending':
      case 'pendingverification':
        label = normalized.contains('submit') ? 'Submitted' : 'Pending';
        bg = const Color(0xFFF59E0B);
        fg = const Color(0xFFB45309);
        darkFg = const Color(0xFFFEF3C7);
        iconData = Icons.schedule_rounded;
        break;

      case 'closure':
      case 'closurenotice':
        label = 'Closure Notice';
        bg = const Color(0xFFEF4444);
        fg = const Color(0xFFB91C1C);
        darkFg = const Color(0xFFFEE2E2);
        iconData = Icons.block_rounded;
        break;

      case 'fine':
      case 'compoundfine':
        label = 'Compound Fine';
        bg = const Color(0xFFD97706);
        fg = const Color(0xFFB45309);
        darkFg = const Color(0xFFFEF3C7);
        iconData = Icons.payments_rounded;
        break;

      case 'warning':
      case 'form32warning':
        label = 'Warning Notice';
        bg = const Color(0xFF0284C7);
        fg = const Color(0xFF0369A1);
        darkFg = const Color(0xFFE0F2FE);
        iconData = Icons.warning_amber_rounded;
        break;

      case 'rejected':
      case 'deactivated':
      case 'noncompliant':
      case 'suspended':
      case 'dismissed':
        label = normalized.contains('non')
            ? 'Non-Compliant'
            : (normalized.contains('dismiss') ? 'Dismissed' : '${statusStr[0].toUpperCase()}${statusStr.substring(1)}');
        bg = const Color(0xFFEF4444);
        fg = const Color(0xFFB91C1C);
        darkFg = const Color(0xFFFEE2E2);
        iconData = Icons.cancel_outlined;
        break;

      case 'needsrevision':
        label = 'Needs Revision';
        bg = const Color(0xFF8B5CF6);
        fg = const Color(0xFF6D28D9);
        darkFg = const Color(0xFFEDE9FE);
        iconData = Icons.edit_note_rounded;
        break;

      default:
        label = statusStr.isNotEmpty ? '${statusStr[0].toUpperCase()}${statusStr.substring(1)}' : 'Unknown';
        bg = const Color(0xFF64748B);
        fg = const Color(0xFF334155);
        darkFg = Colors.white;
        iconData = Icons.info_outline_rounded;
        break;
    }

    return StatusBadge(
      text: label,
      backgroundColor: bg,
      textColor: isOnDark && !isOnImage ? darkFg : fg,
      icon: iconData,
      isOnDark: isOnDark,
      isSolid: isSolid,
      isOnImage: isOnImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isOnDark || Theme.of(context).brightness == Brightness.dark;

    if (isSolid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final Color displayTextColor = isOnImage ? textColor : isDark
        ? (isOnDark ? textColor : _resolveDarkText(backgroundColor))
        : textColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOnImage ? Color.alphaBlend(backgroundColor.withValues(alpha: 0.10), Colors.white) : backgroundColor.withValues(alpha: isDark ? 0.22 : 0.12),
        border: Border.all(
          color: backgroundColor.withValues(alpha: isDark ? 0.55 : 0.4),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: displayTextColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: displayTextColor,
            ),
          ),
        ],
      ),
    );
  }

  static Color _resolveDarkText(Color baseBg) {
    if (baseBg == const Color(0xFF10B981)) return const Color(0xFF6EE7B7);
    if (baseBg == const Color(0xFFF59E0B) || baseBg == const Color(0xFFD97706)) return const Color(0xFFFDE68A);
    if (baseBg == const Color(0xFF0284C7)) return const Color(0xFF7DD3FC);
    if (baseBg == const Color(0xFF7C3AED) || baseBg == const Color(0xFF8B5CF6)) return const Color(0xFFDDD6FE);
    if (baseBg == const Color(0xFFEF4444)) return const Color(0xFFFCA5A5);
    return Colors.white;
  }
}
