import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Customer refresh: one awaited reload, a visible branded indicator, and a short cooldown.
class CustomerRefreshIndicator extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;
  final bool enabled;
  const CustomerRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.enabled = true,
  });
  @override
  State<CustomerRefreshIndicator> createState() =>
      _CustomerRefreshIndicatorState();
}

class _CustomerRefreshIndicatorState extends State<CustomerRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  double _pull = 0;
  @override
  void dispose() {
    _logo.dispose();
    super.dispose();
  }

  Future<void>? _pending;
  DateTime? _lastCompleted;
  RefreshIndicatorStatus? _status;
  bool get _coolingDown =>
      _lastCompleted != null &&
      DateTime.now().difference(_lastCompleted!) < const Duration(seconds: 10);
  Future<void> _refresh() {
    if (_pending != null) return _pending!;
    if (_coolingDown) {
      return Future<void>.value();
    }
    return _pending = _reload();
  }

  Future<void> _reload() async {
    final visibleUntil = Future<void>.delayed(
      const Duration(milliseconds: 800),
    );
    try {
      await widget.onRefresh();
      _lastCompleted = DateTime.now();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not refresh. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      await visibleUntil;
      _pending = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        color: widget.color,
        child: widget.child,
      );
    }
    final refreshing =
        _status == RefreshIndicatorStatus.refresh ||
        _status == RefreshIndicatorStatus.snap;
    final height = refreshing
        ? 68.0
        : _status == RefreshIndicatorStatus.drag ||
              _status == RefreshIndicatorStatus.armed
        ? _pull.clamp(0.0, 88.0)
        : 0.0;
    return ClipRect(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notice) {
          if (notice.depth != 0 || refreshing) return false;
          double? next;
          if (notice is ScrollStartNotification && notice.dragDetails != null) {
            next = 0;
          }
          if (notice is OverscrollNotification &&
              notice.dragDetails != null &&
              notice.metrics.extentBefore == 0) {
            next = _pull - notice.overscroll * 0.5;
          }
          if (notice is ScrollUpdateNotification &&
              notice.dragDetails != null &&
              notice.metrics.extentBefore == 0) {
            next = notice.metrics.pixels < notice.metrics.minScrollExtent
                ? (notice.metrics.minScrollExtent - notice.metrics.pixels) * 0.6
                : _pull - (notice.scrollDelta ?? 0) * 0.5;
          }
          if (next != null && mounted) {
            setState(() => _pull = next!.clamp(0.0, 88.0));
          }
          return false;
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: height),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, extent, child) => Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(offset: Offset(0, extent), child: child),
              if (extent > 0.5)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: extent,
                  child: ClipRect(
                    child: OverflowBox(
                      minHeight: 68,
                      maxHeight: 68,
                      alignment: Alignment.bottomCenter,
                      child: Center(
                        child: Semantics(
                          label: refreshing ? 'Refreshing' : 'Pull to refresh',
                          child: AnimatedBuilder(
                            animation: _logo,
                            builder: (context, _) => ShaderMask(
                              blendMode: BlendMode.srcATop,
                              shaderCallback: (bounds) => LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  widget.color ?? AppTheme.primaryColor,
                                  (widget.color ?? AppTheme.primaryColor)
                                      .withValues(alpha: 0.15),
                                ],
                                stops: [
                                  refreshing
                                      ? _logo.value
                                      : (_pull / 88).clamp(0.0, 1.0),
                                  1,
                                ],
                              ).createShader(bounds),
                              child: Image.asset(
                                'assets/images/hygiene_logo_mark.png',
                                width: 38,
                                height: 38,
                                errorBuilder: (_, e, s) => Icon(
                                  Icons.refresh_rounded,
                                  color: widget.color ?? AppTheme.primaryColor,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: (value) {
              if (!mounted) return;
              if (value == RefreshIndicatorStatus.refresh &&
                  !MediaQuery.disableAnimationsOf(context)) {
                _logo.repeat(reverse: true);
              } else if (value == null ||
                  value == RefreshIndicatorStatus.done ||
                  value == RefreshIndicatorStatus.canceled) {
                _logo.stop();
              }
              setState(() => _status = value);
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
