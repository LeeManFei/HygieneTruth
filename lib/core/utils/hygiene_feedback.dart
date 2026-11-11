import 'dart:async';
import 'package:flutter/material.dart';

enum FeedbackType {
  success,
  error,
  warning,
}

/// Standardized, theme-aware, anti-spam color-coded feedback utility for HygieneTruth
/// 🟢 Success: Emerald Green (#059669)
/// 🔴 Error: Crimson Red (#DC2626)
/// 🟡 Warning / Required Input: Amber/Yellow (#D97706)
class HygieneFeedback {
  // Anti-spam debounce trackers
  static String? _lastMessageKey;
  static int _lastTriggerTimestamp = 0;
  static Timer? _debounceRefreshTimer;
  static const int _spamThresholdMs = 700; // Rapid click window

  /// Displays a floating Success snackbar (Green)
  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _showFeedback(
      context,
      type: FeedbackType.success,
      message: message,
      title: title ?? 'Success',
      duration: duration,
      action: action,
    );
  }

  /// Displays a floating Error snackbar (Red)
  static void showError(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    _showFeedback(
      context,
      type: FeedbackType.error,
      message: message,
      title: title ?? 'Error Occurred',
      duration: duration,
      action: action,
    );
  }

  /// Displays a floating Warning / Requirement snackbar (Yellow/Amber)
  static void showWarning(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _showFeedback(
      context,
      type: FeedbackType.warning,
      message: message,
      title: title ?? 'Attention Required',
      duration: duration,
      action: action,
    );
  }

  /// Internal dispatcher with anti-spam debouncing and Light/Dark theme sync
  static void _showFeedback(
    BuildContext context, {
    required FeedbackType type,
    required String message,
    required String title,
    required Duration duration,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final String messageKey = '${type.name}::$title::$message';
    final int now = DateTime.now().millisecondsSinceEpoch;
    final bool isSpamming = _lastMessageKey == messageKey && (now - _lastTriggerTimestamp) < _spamThresholdMs;

    _lastMessageKey = messageKey;
    _lastTriggerTimestamp = now;

    // If the user is spamming the exact same prompt, do not re-queue or jerkily animate out and in.
    // We clear any pending backlog and refresh/extend the current view.
    if (isSpamming) {
      _debounceRefreshTimer?.cancel();
      _debounceRefreshTimer = Timer(const Duration(milliseconds: 400), () {
        _lastMessageKey = null;
      });
      return;
    }

    _debounceRefreshTimer?.cancel();
    _debounceRefreshTimer = Timer(duration + const Duration(milliseconds: 500), () {
      _lastMessageKey = null;
    });

    // Clear all pending queued SnackBars to prevent stacking/spam build-up
    messenger.clearSnackBars();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme Color Tokens
    final Color primaryAccentColor;
    final Color iconBgColor;
    final Color iconColor;
    final Color cardBgColor;
    final Color borderColor;
    final Color titleColor;
    final Color messageColor;
    final IconData iconData;

    switch (type) {
      case FeedbackType.success:
        primaryAccentColor = const Color(0xFF059669); // Emerald Green
        iconData = Icons.check_circle_rounded;
        if (isDark) {
          cardBgColor = const Color(0xFF1E1E1E);
          borderColor = const Color(0xFF059669).withValues(alpha: 0.45);
          iconBgColor = const Color(0xFF059669).withValues(alpha: 0.2);
          iconColor = const Color(0xFF34D399);
          titleColor = Colors.white;
          messageColor = const Color(0xFFD1D5DB);
        } else {
          cardBgColor = Colors.white;
          borderColor = const Color(0xFF10B981);
          iconBgColor = const Color(0xFFECFDF5);
          iconColor = const Color(0xFF059669);
          titleColor = const Color(0xFF0C2340);
          messageColor = const Color(0xFF334155);
        }
        break;

      case FeedbackType.error:
        primaryAccentColor = const Color(0xFFDC2626); // Crimson Red
        iconData = Icons.error_outline_rounded;
        if (isDark) {
          cardBgColor = const Color(0xFF1E1E1E);
          borderColor = const Color(0xFFDC2626).withValues(alpha: 0.45);
          iconBgColor = const Color(0xFFDC2626).withValues(alpha: 0.2);
          iconColor = const Color(0xFFF87171);
          titleColor = Colors.white;
          messageColor = const Color(0xFFD1D5DB);
        } else {
          cardBgColor = Colors.white;
          borderColor = const Color(0xFFEF4444);
          iconBgColor = const Color(0xFFFEF2F2);
          iconColor = const Color(0xFFDC2626);
          titleColor = const Color(0xFF0C2340);
          messageColor = const Color(0xFF334155);
        }
        break;

      case FeedbackType.warning:
        primaryAccentColor = const Color(0xFFD97706); // Amber Yellow
        iconData = Icons.warning_amber_rounded;
        if (isDark) {
          cardBgColor = const Color(0xFF1E1E1E);
          borderColor = const Color(0xFFD97706).withValues(alpha: 0.45);
          iconBgColor = const Color(0xFFD97706).withValues(alpha: 0.2);
          iconColor = const Color(0xFFFBBF24);
          titleColor = Colors.white;
          messageColor = const Color(0xFFD1D5DB);
        } else {
          cardBgColor = Colors.white;
          borderColor = const Color(0xFFF59E0B);
          iconBgColor = const Color(0xFFFFFBEB);
          iconColor = const Color(0xFFD97706);
          titleColor = const Color(0xFF0C2340);
          messageColor = const Color(0xFF334155);
        }
        break;
    }

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        padding: EdgeInsets.zero,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: duration,
        action: action,
        content: Container(
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Left accent color indicator stripe
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: Container(color: primaryAccentColor),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: iconBgColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(iconData, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: titleColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message,
                              style: TextStyle(
                                color: messageColor,
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }
}
