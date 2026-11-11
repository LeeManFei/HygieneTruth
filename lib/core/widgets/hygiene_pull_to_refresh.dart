import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'customer_refresh_indicator.dart';

/// A premium, ultra-smooth pull-to-refresh component inspired by modern fintech apps (e.g. Atome).
///
/// Features:
/// - Displays the official Hygiene brand logo at the top header during overscroll pull.
/// - Top-to-bottom color sync fill transition animation proportional to pull distance.
/// - Continuous fluid top-to-bottom color wave/pulse while refreshing.
/// - Smooth spring-back / retraction animation when returning back up.
/// - Zero jarring layout shifts with elastic resistance physics.
class HygienePullToRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final bool customerMode;
  final double triggerDistance;
  final double headerHeight;
  final Color? backgroundColor;

  const HygienePullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.customerMode = false,
    this.triggerDistance = 85.0,
    this.headerHeight = 72.0,
    this.backgroundColor,
  });

  @override
  State<HygienePullToRefresh> createState() => _HygienePullToRefreshState();
}

class _HygienePullToRefreshState extends State<HygienePullToRefresh>
    with TickerProviderStateMixin {
  double _pullOffset = 0.0;
  bool _isRefreshing = false;
  bool _hasHapticTriggered = false;

  late AnimationController _collapseAnimCtrl;
  late AnimationController _waveAnimCtrl;
  late AnimationController _pulseAnimCtrl;

  late Animation<double> _collapseAnimation;

  @override
  void initState() {
    super.initState();

    _collapseAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _waveAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _pulseAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.95,
      upperBound: 1.05,
    );
  }

  @override
  void dispose() {
    _collapseAnimCtrl.dispose();
    _waveAnimCtrl.dispose();
    _pulseAnimCtrl.dispose();
    super.dispose();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (_isRefreshing) return;

    if (notification is ScrollUpdateNotification) {
      // User is scrolling/dragging
      if (notification.metrics.extentBefore == 0 && notification.scrollDelta != null) {
        if (notification.scrollDelta! < 0 || _pullOffset > 0) {
          final double newOffset = (_pullOffset - (notification.scrollDelta! * 0.55))
              .clamp(0.0, widget.triggerDistance * 1.6);
          setState(() {
            _pullOffset = newOffset;
          });

          // Trigger subtle haptic feedback when crossing the trigger threshold
          if (_pullOffset >= widget.triggerDistance && !_hasHapticTriggered) {
            _hasHapticTriggered = true;
            HapticFeedback.mediumImpact();
          } else if (_pullOffset < widget.triggerDistance && _hasHapticTriggered) {
            _hasHapticTriggered = false;
          }
        }
      }
    } else if (notification is OverscrollNotification) {
      if (notification.overscroll < 0) {
        final double newOffset = (_pullOffset - (notification.overscroll * 0.55))
            .clamp(0.0, widget.triggerDistance * 1.6);
        setState(() {
          _pullOffset = newOffset;
        });

        if (_pullOffset >= widget.triggerDistance && !_hasHapticTriggered) {
          _hasHapticTriggered = true;
          HapticFeedback.mediumImpact();
        }
      }
    } else if (notification is ScrollEndNotification) {
      _handleDragRelease();
    }
  }

  void _handleDragRelease() {
    if (_isRefreshing) return;

    if (_pullOffset >= widget.triggerDistance) {
      // Trigger Refresh!
      _startRefreshing();
    } else if (_pullOffset > 0) {
      // Snap back up smoothly
      _animateBackTo(0.0);
    }
  }

  void _startRefreshing() {
    setState(() {
      _isRefreshing = true;
      _hasHapticTriggered = false;
    });

    _waveAnimCtrl.repeat();
    _pulseAnimCtrl.repeat(reverse: true);

    // Animate to standard resting header height during active refresh
    _animateBackTo(widget.headerHeight, onComplete: () async {
      try {
        await widget.onRefresh();
      } catch (_) {}

      if (mounted) {
        _endRefreshing();
      }
    });
  }

  void _endRefreshing() {
    _waveAnimCtrl.stop();
    _pulseAnimCtrl.stop();

    // Smooth spring back to top
    _animateBackTo(0.0, durationMs: 400, onComplete: () {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _pullOffset = 0.0;
        });
      }
    });
  }

  void _animateBackTo(double targetOffset, {int durationMs = 320, VoidCallback? onComplete}) {
    _collapseAnimCtrl.duration = Duration(milliseconds: durationMs);
    _collapseAnimation = Tween<double>(
      begin: _pullOffset,
      end: targetOffset,
    ).animate(CurvedAnimation(
      parent: _collapseAnimCtrl,
      curve: Curves.easeOutCubic,
    ))..addListener(() {
        setState(() {
          _pullOffset = _collapseAnimation.value;
        });
      });

    _collapseAnimCtrl.forward(from: 0.0).then((_) {
      if (onComplete != null) {
        onComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.customerMode) return CustomerRefreshIndicator(onRefresh: widget.onRefresh, child: widget.child);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double progress = (_pullOffset / widget.triggerDistance).clamp(0.0, 1.0);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScrollNotification(notification);
        return false;
      },
      child: Stack(
        children: [
          // 1. Top Hygiene Brand Header (Custom Atome-style logo reveal)
          if (_pullOffset > 0.5)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _pullOffset,
              child: Container(
                color: widget.backgroundColor ??
                    (isDark ? AppTheme.darkBackgroundColor : Colors.transparent),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: (progress * 1.2).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.75 + (0.25 * progress),
                    child: _buildAnimatedHygieneLogo(progress, isDark),
                  ),
                ),
              ),
            ),

          // 2. Main Child Content shifted down during pull
          Transform.translate(
            offset: Offset(0, _pullOffset),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  /// Builds the Hygiene Logo with Top-to-Bottom Color Sync Transition Effect
  Widget _buildAnimatedHygieneLogo(double progress, bool isDark) {
    const double logoSize = 46.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_waveAnimCtrl, _pulseAnimCtrl]),
      builder: (context, _) {
        final double pulseScale = _isRefreshing ? _pulseAnimCtrl.value : 1.0;

        return Transform.scale(
          scale: pulseScale,
          child: SizedBox(
            width: logoSize,
            height: logoSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A. Base Layer: Muted Outline / Silhouette (Visible on initial pull)
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    isDark
                        ? Colors.white.withValues(alpha: 0.15 + (0.15 * progress))
                        : const Color(0xFF0D9488).withValues(alpha: 0.18 + (0.15 * progress)),
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/hygiene_logo_mark.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => _buildFallbackVectorLogo(isDark, progress),
                  ),
                ),

                // B. Active Layer: Top-to-Bottom Color Sync Fill / Transition
                ClipRect(
                  clipper: _TopToBottomFillClipper(
                    fillFraction: _isRefreshing ? 1.0 : progress,
                  ),
                  child: _isRefreshing
                      ? _buildShimmeringVibrantLogo(logoSize, isDark)
                      : _buildVibrantLogo(logoSize, isDark),
                ),

                // C. Subtle Circular Glow on full pull
                if (progress >= 0.95 || _isRefreshing)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.18),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Vibrant Full-Color Hygiene Logo
  Widget _buildVibrantLogo(double size, bool isDark) {
    return Image.asset(
      'assets/images/hygiene_logo_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (ctx, err, stack) => _buildFallbackVectorLogo(isDark, 1.0, isVibrant: true),
    );
  }

  /// Shimmering Wave Effect across the Logo while Refreshing
  Widget _buildShimmeringVibrantLogo(double size, bool isDark) {
    final double wavePos = _waveAnimCtrl.value;

    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF0284C7), // Sky Blue
            Color(0xFF0D9488), // Truth Teal
            Color(0xFF10B981), // Emerald
            Color(0xFF80EE98), // Mint
            Color(0xFF0284C7), // Loop back
          ],
          stops: [
            (wavePos - 0.4).clamp(0.0, 1.0),
            (wavePos - 0.2).clamp(0.0, 1.0),
            wavePos.clamp(0.0, 1.0),
            (wavePos + 0.2).clamp(0.0, 1.0),
            (wavePos + 0.4).clamp(0.0, 1.0),
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcATop,
      child: _buildVibrantLogo(size, isDark),
    );
  }

  /// High-definition fallback vector logo in case image asset fails
  Widget _buildFallbackVectorLogo(bool isDark, double progress, {bool isVibrant = false}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isVibrant
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D9488), Color(0xFF10B981), Color(0xFF80EE98)],
              )
            : null,
        color: !isVibrant
            ? (isDark ? Colors.white24 : const Color(0xFF0D9488).withValues(alpha: 0.2))
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.verified_user_rounded,
        size: 26,
        color: isVibrant ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF0D9488)),
      ),
    );
  }
}

/// Custom Clipper for razor-sharp Top-to-Bottom Color Fill
class _TopToBottomFillClipper extends CustomClipper<Rect> {
  final double fillFraction;

  _TopToBottomFillClipper({required this.fillFraction});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      0.0,
      0.0,
      size.width,
      size.height * fillFraction.clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldReclip(_TopToBottomFillClipper oldClipper) {
    return oldClipper.fillFraction != fillFraction;
  }
}
