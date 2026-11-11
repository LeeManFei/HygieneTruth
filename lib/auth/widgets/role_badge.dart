import 'package:flutter/material.dart';
import '../../core/models/user_model.dart';

class RoleBadge extends StatelessWidget {
  final UserRole role;

  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (role) {
      case UserRole.user:
        bg = const Color(0xFF0284C7);
        fg = isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
        label = 'Customer';
        icon = Icons.person;
        break;
      case UserRole.admin:
        bg = const Color(0xFF8B5CF6);
        fg = isDark ? const Color(0xFFDDD6FE) : const Color(0xFF6D28D9);
        label = 'Admin';
        icon = Icons.admin_panel_settings;
        break;
      case UserRole.government:
        bg = const Color(0xFF0F766E);
        fg = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
        label = 'Government';
        icon = Icons.security;
        break;
      case UserRole.owner:
        bg = const Color(0xFFD97706);
        fg = isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
        label = 'Businessman';
        icon = Icons.storefront;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: isDark ? 0.22 : 0.12),
        border: Border.all(color: bg.withValues(alpha: isDark ? 0.55 : 0.4), width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
