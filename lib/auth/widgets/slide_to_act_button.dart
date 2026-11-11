import 'package:flutter/material.dart';

class SlideToActButton extends StatefulWidget {
  final String text;
  final VoidCallback onSlideComplete;
  final IconData icon;

  const SlideToActButton({
    super.key,
    required this.text,
    required this.onSlideComplete,
    this.icon = Icons.keyboard_double_arrow_right,
  });

  @override
  State<SlideToActButton> createState() => _SlideToActButtonState();
}

class _SlideToActButtonState extends State<SlideToActButton>
    with TickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _submitted = false;

  late AnimationController _shimmerController;
  late AnimationController _idleController;
  late Animation<double> _idleNudgeAnimation;
  late AnimationController _snapController;

  @override
  void initState() {
    super.initState();
    // Shimmer Text Animation Controller
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // Subtle Idle Nudge Animation Controller
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _idleNudgeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 7.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 7.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 40,
      ),
    ]).animate(_idleController);

    // Smooth Reverse Snapback Animation Controller (prevents teleporting on release)
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _idleController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  void _animateReverseSnapback() {
    final startPos = _dragPosition;
    final Animation<double> snapAnim = Tween<double>(begin: startPos, end: 0.0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );

    void listener() {
      if (mounted) {
        setState(() {
          _dragPosition = snapAnim.value;
        });
      }
    }

    _snapController.reset();
    _snapController.addListener(listener);
    _snapController.forward(from: 0.0).then((_) {
      _snapController.removeListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        const thumbWidth = 46.0;
        const padding = 6.0;
        final maxDrag = trackWidth - thumbWidth - (padding * 2);
        final dragPercent = (maxDrag > 0) ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return AnimatedBuilder(
          animation: Listenable.merge([_idleController, _snapController]),
          builder: (context, child) {
            // Idle nudge offset is active only when thumb is resting at left edge
            final idleOffset = (_dragPosition == 0.0 && !_submitted && !_snapController.isAnimating)
                ? _idleNudgeAnimation.value
                : 0.0;
            final currentLeft = padding + _dragPosition + idleOffset;

            return Container(
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF0C2340).withValues(alpha: 0.85), // Deep Navy from logo
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF00A88F).withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Smooth Gradient Tail Animation Behind Thumb matching logo colors
                  if (_dragPosition > 0 || idleOffset > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: (padding + _dragPosition + idleOffset + (thumbWidth / 2) + 8).clamp(0.0, trackWidth),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF0C2340), // Deep Navy logo primary
                              Color(0xFF00A88F), // Vibrant Teal logo secondary
                              Color(0xFF80EE98), // Mint Sparkle logo accent
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),

                  // Center Label Text with Shimmer Shinning Effect Left-to-Right
                  Center(
                    child: Opacity(
                      opacity: (1.0 - (dragPercent * 1.5)).clamp(0.0, 1.0),
                      child: AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          final shimmerVal = _shimmerController.value;
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              final width = bounds.width;
                              final dx = shimmerVal * (width * 2) - width;
                              return LinearGradient(
                                colors: const [
                                  Colors.white70,
                                  Colors.white,
                                  Color(0xFF80EE98), // Luminous Mint shimmer shine
                                  Colors.white,
                                  Colors.white70,
                                ],
                                stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                                begin: Alignment(-1.0 + (shimmerVal * 3), 0.0),
                                end: Alignment(0.0 + (shimmerVal * 3), 0.0),
                              ).createShader(Rect.fromLTWH(dx, 0, width, bounds.height));
                            },
                            blendMode: BlendMode.srcIn,
                            child: Text(
                              widget.text,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Draggable Logo-Themed Thumb Button with Smooth Reverse Animation
                  Positioned(
                    left: currentLeft,
                    top: padding,
                    bottom: padding,
                    child: GestureDetector(
                      onHorizontalDragStart: (details) {
                        if (_snapController.isAnimating) {
                          _snapController.stop();
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_submitted) return;
                        setState(() {
                          _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
                        });
                      },
                      onHorizontalDragEnd: (details) {
                        if (_submitted) return;
                        if (_dragPosition > maxDrag * 0.75) {
                          // Complete slide action!
                          setState(() {
                            _dragPosition = maxDrag;
                            _submitted = true;
                          });
                          widget.onSlideComplete();
                        } else {
                          // Smooth reverse animation back to start position (no teleporting!)
                          _animateReverseSnapback();
                        }
                      },
                      // Explicitly empty onTap to PREVENT user from clicking/tapping
                      onTap: () {},
                      child: Container(
                        width: thumbWidth,
                        height: thumbWidth,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF00A88F), // Vibrant Teal
                              Color(0xFF80EE98), // Mint Accent
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            widget.icon,
                            color: const Color(0xFF0C2340), // Deep Navy arrow icon
                            size: 24,
                          ),
                        ),
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
