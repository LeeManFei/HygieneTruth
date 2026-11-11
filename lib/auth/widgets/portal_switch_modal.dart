import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/circular_reveal_route.dart';
import '../../owner/screens/owner_login_screen.dart';
import '../screens/admin_gov_login_screen.dart';
import '../screens/login_screen.dart';

void showPortalSwitchModal(
  BuildContext context, {
  required String currentPortal,
  Offset? switchButtonPosition,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final screenSize = MediaQuery.of(context).size;
  final Offset revealCenter = switchButtonPosition ?? Offset(screenSize.width - 50, 56);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (modalCtx) {
      return SafeArea(
        top: false,
        bottom: true,
        child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle indicator
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

            // Modal Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF0F766E), size: 22,),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Switch Login Portal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select your role to access the specific dashboard',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(modalCtx),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Option 1: Customer Portal
            _buildPortalOption(
              context: context,
              modalCtx: modalCtx,
              title: 'Customer',
              subtitle: 'Report hygiene issues & track public restaurant hygiene scores',
              icon: Icons.person_rounded,
              color: const Color(0xFF00A86B),
              isCurrent: currentPortal.toLowerCase() == 'customer',
              targetPageBuilder: () => const LoginScreen(),
              revealCenter: revealCenter,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            // Option 2: Businessman (Business)
            _buildPortalOption(
              context: context,
              modalCtx: modalCtx,
              title: 'Businessman (Business)',
              subtitle: 'Restaurant owners, managers & compliance officers',
              icon: Icons.storefront_rounded,
              color: const Color(0xFFD97706),
              isCurrent: currentPortal.toLowerCase() == 'owner' || currentPortal.toLowerCase() == 'businessman',
              targetPageBuilder: () => const OwnerLoginScreen(),
              revealCenter: revealCenter,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            // Option 3: Official Staff (Admin / Gov)
            _buildPortalOption(
              context: context,
              modalCtx: modalCtx,
              title: 'Official Staff (Admin / Gov)',
              subtitle: 'MOH health enforcement, PKD inspectors & audit admin',
              icon: Icons.admin_panel_settings_rounded,
              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
              isCurrent: currentPortal.toLowerCase() == 'admin' || currentPortal.toLowerCase() == 'gov' || currentPortal.toLowerCase() == 'official',
              targetPageBuilder: () => const AdminGovLoginScreen(),
              revealCenter: revealCenter,
              isDark: isDark,
            ),
          ],
        ),
      ),
      );
    },
  );
}

Widget _buildPortalOption({
  required BuildContext context,
  required BuildContext modalCtx,
  required String title,
  required String subtitle,
  required IconData icon,
  required Color color,
  required bool isCurrent,
  required Widget Function() targetPageBuilder,
  required Offset revealCenter,
  required bool isDark,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () {
        Navigator.pop(modalCtx);
        if (!isCurrent) {
          CircularRevealPageRoute.pushReplacement(
            context,
            targetPageBuilder(),
            centerOffset: revealCenter,
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent
              ? color.withValues(alpha: isDark ? 0.2 : 0.12)
              : (isDark ? const Color(0xFF262626) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent ? color : (isDark ? Colors.white12 : Colors.grey.shade200),
            width: isCurrent ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child:
                      Text(
                        title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2,),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'CURRENT',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isCurrent ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
              color: isCurrent ? color : (isDark ? Colors.white38 : Colors.grey.shade400),
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class PortalSwitchButton extends StatefulWidget {
  final String currentPortal;
  final Color? buttonColor;

  const PortalSwitchButton({
    super.key,
    required this.currentPortal,
    this.buttonColor,
  });

  @override
  State<PortalSwitchButton> createState() => _PortalSwitchButtonState();
}

class _PortalSwitchButtonState extends State<PortalSwitchButton> {
  final GlobalKey _buttonKey = GlobalKey();

  Color _resolvePortalColor(bool isDark) {
    if (widget.buttonColor != null) {
      if (isDark) {
        if (widget.buttonColor == const Color(0xFF0C2340) ||
            widget.buttonColor == const Color(0xFF0F766E)) {
          return const Color(0xFF2DD4BF);
        }
        return widget.buttonColor!;
      }
      return widget.buttonColor!;
    }
    final portal = widget.currentPortal.toLowerCase();
    if (portal == 'businessman' || portal == 'owner') {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    } else if (portal == 'admin' || portal == 'gov' || portal == 'official') {
      return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    }
    return isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = _resolvePortalColor(isDark);

    return Padding(
      padding: const EdgeInsets.only(right: 12.0, top: 10, bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: _buttonKey,
          onTap: () {
            Offset? buttonOffset;
            final RenderBox? renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              buttonOffset = renderBox.localToGlobal(renderBox.size.center(Offset.zero),);
            }
            showPortalSwitchModal(
              context,
              currentPortal: widget.currentPortal,
              switchButtonPosition: buttonOffset,
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282828) : accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? accentColor.withValues(alpha: 0.6) : accentColor.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded, size: 15, color: accentColor),
                const SizedBox(width: 5),
                Text(
                  'Switch',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: accentColor,),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
