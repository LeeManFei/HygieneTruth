import 'package:flutter/material.dart';
import '../../core/services/customer_store_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Emblem Animations
  late Animation<double> _emblemOpacity;
  late Animation<double> _emblemScale;

  // Text "Hygiene Truth" Animations (Appearing Phase)
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _textLetterSpacing;

  // Exit / Disappearing Phase Animations
  late Animation<double> _exitOpacity;
  late Animation<double> _exitScale;

  // Exact Brand Colors sampled from HygieneTruth.png
  static const Color hygieneNavy = Color(0xFF051F4E);
  static const Color truthTeal = Color(0xFF00867D);

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // 1. Emblem Mark Appearance (0% -> 35%)
    _emblemOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.32, curve: Curves.easeOutCubic),
      ),
    );

    _emblemScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.38, curve: Curves.easeOutBack),
      ),
    );

    // 2. Text "Hygiene Truth" Appearing (25% -> 58%)
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.55, curve: Curves.easeOut),
      ),
    );

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.58, curve: Curves.easeOutCubic),
      ),
    );

    _textLetterSpacing = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.60, curve: Curves.easeOut),
      ),
    );

    // 3. Disappearing / Exit Phase (76% -> 98%)
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.76, 0.98, curve: Curves.easeInOut),
      ),
    );

    _exitScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.76, 0.98, curve: Curves.easeInCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToNext();
      }
    });

    _controller.forward();
  }

  Future<void> _navigateToNext() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final nextRoute = await CustomerStoreService.resolveInitialAppRoute();
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, nextRoute);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0C192C) : Colors.white;
    final navTextColor = isDark ? Colors.white : hygieneNavy;
    final tealTextColor = isDark ? const Color(0xFF2DD4BF) : truthTeal;

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _navigateToNext,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final currentExitOpacity = _exitOpacity.value;
            final currentExitScale = _exitScale.value;

            return Opacity(
              opacity: currentExitOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: currentExitScale,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 1. Top Emblem Mark (Scale & Fade In)
                      Opacity(
                        opacity: _emblemOpacity.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: _emblemScale.value,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: truthTeal.withValues(alpha: isDark ? 0.25 : 0.12),
                                  blurRadius: 36,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/hygiene_logo_mark.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 2. Animated Appearing & Disappearing Text: "Hygiene" + "Truth"
                      SlideTransition(
                        position: _textSlide,
                        child: Opacity(
                          opacity: _textOpacity.value.clamp(0.0, 1.0),
                          child: Column(
                            children: [
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Hygiene',
                                      style: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: navTextColor,
                                        letterSpacing: _textLetterSpacing.value,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                    const TextSpan(text: ' '),
                                    TextSpan(
                                      text: 'Truth',
                                      style: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: tealTextColor,
                                        letterSpacing: _textLetterSpacing.value,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Opacity(
                                opacity: (_textOpacity.value * 0.85).clamp(0.0, 1.0),
                                child: Text(
                                  'Food Safety & Risk Intelligence',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 1.1,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
