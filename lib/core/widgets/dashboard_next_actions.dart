import 'package:flutter/material.dart';
import '../services/customer_store_service.dart';
import '../theme/app_theme.dart';

class DashboardNextAction {
  final String title, detail;
  final Future<void> Function() onOpen;
  const DashboardNextAction({
    required this.title,
    required this.detail,
    required this.onOpen,
  });
}

/// Navigation only: destination screens retain their existing workflow checks.
class DashboardNextActions extends StatefulWidget {
  final List<DashboardNextAction> actions;
  final String emptyMessage;
  final String? sessionKey;
  final VoidCallback? onDismiss;

  const DashboardNextActions({
    super.key,
    required this.actions,
    this.emptyMessage = 'No pending actions in the loaded records.',
    this.sessionKey,
    this.onDismiss,
  });

  /// Set of action cards dismissed during the current login session.
  static final ValueNotifier<Set<String>> dismissedKeysNotifier =
      ValueNotifier<Set<String>>(<String>{});

  /// Tracks the session generation from CustomerStoreService.
  static int _lastObservedSessionGeneration = -1;

  /// Tracks the current user ID for the active session.
  static String? _lastObservedUserId;

  /// Check whether a card is currently dismissed for this session.
  static bool isDismissed([String key = 'default']) =>
      dismissedKeysNotifier.value.contains(key);

  /// Dismisses a card for the active login session.
  static void dismiss([String key = 'default']) {
    final updated = Set<String>.from(dismissedKeysNotifier.value)..add(key);
    dismissedKeysNotifier.value = updated;
  }

  /// Resets the session dismissal state so cards reappear on next login.
  static void resetSession() {
    _lastObservedSessionGeneration = CustomerStoreService.sessionGeneration;
    _lastObservedUserId = CustomerStoreService.currentCustomer?.id;
    if (dismissedKeysNotifier.value.isNotEmpty) {
      dismissedKeysNotifier.value = <String>{};
    }
  }

  @override
  State<DashboardNextActions> createState() => _DashboardNextActionsState();
}

class _DashboardNextActionsState extends State<DashboardNextActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _sizeAnimation;
  int? _opening;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );

    _sizeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.15, 1.0, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (_isDismissing) return;
    setState(() => _isDismissing = true);

    _animController.reverse().then((_) {
      if (mounted) {
        final key = widget.sessionKey ?? 'default';
        DashboardNextActions.dismiss(key);
        widget.onDismiss?.call();
      }
    });
  }

  Future<void> _open(int index) async {
    if (_opening != null || _isDismissing) return;
    setState(() => _opening = index);
    try {
      await widget.actions[index].onOpen();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'This record could not be opened. Please refresh and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detect session changes (login, logout, account switch)
    final currentGen = CustomerStoreService.sessionGeneration;
    final currentUserId = CustomerStoreService.currentCustomer?.id;
    if (DashboardNextActions._lastObservedSessionGeneration != currentGen ||
        DashboardNextActions._lastObservedUserId != currentUserId) {
      DashboardNextActions._lastObservedSessionGeneration = currentGen;
      DashboardNextActions._lastObservedUserId = currentUserId;
      if (DashboardNextActions.dismissedKeysNotifier.value.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DashboardNextActions.dismissedKeysNotifier.value = <String>{};
        });
      }
    }

    final effectiveKey = widget.sessionKey ?? 'default';

    return ValueListenableBuilder<Set<String>>(
      valueListenable: DashboardNextActions.dismissedKeysNotifier,
      builder: (context, dismissedKeys, _) {
        final bool isKeyDismissed = dismissedKeys.contains(effectiveKey);

        if (isKeyDismissed && !_isDismissing) {
          return const SizedBox.shrink();
        }

        if (!isKeyDismissed && !_isDismissing && _animController.value != 1.0) {
          _animController.value = 1.0;
        }

        final dark = Theme.of(context).brightness == Brightness.dark;
        final accent = dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);

        final cardContent = Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dark ? AppTheme.darkSurfaceColor : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: dark ? AppTheme.darkBorderColor : const Color(0xFFD5E7E5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Your next action',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white : AppTheme.navyColor,
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: InkWell(
                      onTap: _isDismissing ? null : _handleDismiss,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: dark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (widget.actions.isEmpty)
                Text(
                  widget.emptyMessage,
                  style: TextStyle(
                    color: dark ? Colors.white70 : const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              for (var i = 0; i < widget.actions.length && i < 3; i++) ...[
                if (i > 0)
                  Divider(color: dark ? Colors.white12 : const Color(0xFFE2E8F0)),
                InkWell(
                  onTap: _opening == null && !_isDismissing ? () => _open(i) : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.actions[i].title,
                                style: TextStyle(
                                  color: dark ? Colors.white : AppTheme.navyColor,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.actions[i].detail,
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
                        const SizedBox(width: 8),
                        if (_opening == i)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        else
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                            color: accent,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

        return SizeTransition(
          sizeFactor: _sizeAnimation,
          axisAlignment: -1.0,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: cardContent,
          ),
        );
      },
    );
  }
}
