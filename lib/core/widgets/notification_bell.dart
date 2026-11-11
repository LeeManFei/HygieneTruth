import 'dart:math';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/customer_store_service.dart';
import '../theme/app_theme.dart';
import '../../notifications/screens/notification_center_screen.dart';

class NotificationBell extends StatefulWidget {
  final VoidCallback? onPressed;
  final Color? iconColor;

  const NotificationBell({
    super.key,
    this.onPressed,
    this.iconColor,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11), // 8s still + 3s shake cycle
    );

    WidgetsBinding.instance.addObserver(this);

    // Start animation if unread notifications exist
    if (NotificationService.unreadCountNotifier.value > 0) {
      _shakeController.repeat();
    }

    NotificationService.unreadCountNotifier.addListener(_onUnreadCountChanged);
  }

  void _onUnreadCountChanged() {
    if (mounted) {
      final unread = NotificationService.unreadCountNotifier.value;
      if (unread > 0) {
        if (!_shakeController.isAnimating) {
          _shakeController.repeat();
        }
      } else {
        if (_shakeController.isAnimating) {
          _shakeController.stop();
          _shakeController.reset();
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final user = CustomerStoreService.currentCustomer;
      NotificationService.fetchNotifications(
        userId: user?.id,
        userEmail: user?.email,
        userRole: user?.role.name,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.unreadCountNotifier.removeListener(_onUnreadCountChanged);
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconColor = widget.iconColor ??
        Theme.of(context).appBarTheme.iconTheme?.color ??
        (isDark ? Colors.white : AppTheme.navyColor);

    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.unreadCountNotifier,
      builder: (context, unreadCount, _) {
        return AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            // Oscillation animation logic: 8s still, 3s shake (60fps smooth trigonometric wave)
            double angle = 0;
            if (unreadCount > 0) {
              const double stillRatio = 8 / 11;
              if (_shakeController.value > stillRatio) {
                double shakeT = (_shakeController.value - stillRatio) / (1 - stillRatio);
                angle = sin(shakeT * pi * 8) * 0.35;
              }
            }

            return Transform.rotate(
              angle: angle,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      unreadCount > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: unreadCount > 0
                          ? const Color(0xFFF59E0B)
                          : effectiveIconColor,
                    ),
                    tooltip: 'Notifications',
                    onPressed: widget.onPressed ??
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationCenterScreen(),
                            ),
                          );
                        },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
