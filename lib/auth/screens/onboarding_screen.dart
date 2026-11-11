import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/customer_store_service.dart';
import '../widgets/slide_to_act_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int _currentPage = 0;

  late VideoPlayerController _videoController;

  bool _isVideoInitialized = false;

  final List<Map<String, String>> _pages = [
    {
      'type': 'image',
      'image': 'assets/images/HygieneTruth_Onbord.png',
      'badge': 'HYGIENE INTELLIGENCE',
      'title': 'Safe Dining in Your Pocket!',
      'subtitle':
          'Navigate and explore verified clean food spots with real-time hygiene intelligence.',
    },
    {
      'type': 'image',
      'image': 'assets/images/HygieneTruth_Onbord_one.png',
      'badge': 'RISK ANALYTICS',
      'title': 'Real-Time Risk Monitoring',
      'subtitle':
          'AI-driven risk scoring, complaint tracking, and official health inspection records.',
    },
    {
      'type': 'video',
      'video': 'assets/videos/Onbording_HygieneTruth.mp4',
      'badge': 'TOTAL TRANSPARENCY',
      'title': 'Get Started with Hygiene Truth!',
      'subtitle':
          'Empowering customers, restaurant owners, and health officials for cleaner dining.',
    },
  ];

  @override
  void initState() {
    super.initState();

    // ---------------------------------------------------------
    // TRUE FULLSCREEN / EDGE-TO-EDGE
    // ---------------------------------------------------------
    //
    // Allows the onboarding media to render behind:
    //
    // - Android status bar
    // - Android navigation bar
    //
    // The status/navigation bars themselves remain transparent.
    //
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        // STATUS BAR
        statusBarColor: Colors.transparent,

        // White clock / battery / signal icons.
        statusBarIconBrightness: Brightness.light,

        // Used mainly by iOS.
        statusBarBrightness: Brightness.dark,

        // Prevent Android from adding its own contrast background.
        systemStatusBarContrastEnforced: false,

        // NAVIGATION BAR
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,

        // Prevent Android navigation bar contrast scrim.
        systemNavigationBarContrastEnforced: false,
      ),
    );

    _initVideoBackground();
  }

  Future<void> _initVideoBackground() async {
    try {
      _videoController = VideoPlayerController.asset(
        'assets/videos/Onbording_HygieneTruth.mp4',
      );

      await _videoController.initialize();

      await _videoController.setLooping(true);
      await _videoController.setVolume(0.0);

      await _videoController.play();

      if (!mounted) return;

      setState(() {
        _isVideoInitialized = true;
      });
    } catch (e) {
      debugPrint('Onboarding video init fallback notice: $e');

      try {
        // Fallback asset location.
        _videoController = VideoPlayerController.asset(
          'assets/Onbording_HygieneTruth.mp4',
        );

        await _videoController.initialize();

        await _videoController.setLooping(true);
        await _videoController.setVolume(0.0);

        await _videoController.play();

        if (!mounted) return;

        setState(() {
          _isVideoInitialized = true;
        });
      } catch (fallbackError) {
        debugPrint('Onboarding fallback video failed: $fallbackError');
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();

    if (_isVideoInitialized) {
      _videoController.dispose();
    }

    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await CustomerStoreService.setOnboardingCompleted(true);

    final route = await CustomerStoreService.getLastPortalLoginRoute();

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final bool isLastPage = _currentPage == _pages.length - 1;

    // Actual Android/iOS status bar height.
    // Actual Android/iOS status bar height.
    //
    // This is ONLY used for the Skip button.
    // It does NOT push the video down.
    final double statusBarHeight = MediaQuery.paddingOf(context).top;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    const Color primaryColor = Color(0xFF00A88F);

    const Color truthTeal = Color(0xFF00867D);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,

        systemStatusBarContrastEnforced: false,

        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,

        systemNavigationBarContrastEnforced: false,
      ),

      child: Scaffold(
        // -------------------------------------------------------
        // IMPORTANT:
        //
        // Do not wrap the complete body in SafeArea.
        //
        // We want the video/image to cover the ENTIRE display,
        // including behind the status bar.
        // -------------------------------------------------------
        backgroundColor: const Color(0xFF051F4E),

        resizeToAvoidBottomInset: false,

        body: Stack(
          fit: StackFit.expand,
          children: [
            // ===================================================
            // 1. FULLSCREEN PAGE CONTENT
            // ===================================================
            PageView.builder(
              controller: _pageController,

              padEnds: false,

              clipBehavior: Clip.hardEdge,

              physics: const ClampingScrollPhysics(),

              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });

                if (_isVideoInitialized) {
                  if (index == _pages.length - 1) {
                    _videoController.play();
                  }
                }
              },

              itemCount: _pages.length,

              itemBuilder: (context, index) {
                final page = _pages[index];

                final bool isVideo = page['type'] == 'video';

                return SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,

                    clipBehavior: Clip.hardEdge,

                    children: [
                      // =========================================
                      // BACKGROUND MEDIA
                      // =========================================
                      if (isVideo)
                        _buildVideoBackground()
                      else
                        _buildImageBackground(page),

                      // =========================================
                      // CINEMATIC BOTTOM GRADIENT
                      // =========================================
                      //
                      // Notice:
                      //
                      // Top 45% = completely transparent.
                      //
                      // Therefore this does NOT create the
                      // transparent/glass bar you previously saw.
                      //
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,

                                end: Alignment.bottomCenter,

                                colors: [
                                  Colors.transparent,

                                  Colors.transparent,

                                  const Color(
                                    0xFF051F4E,
                                  ).withValues(alpha: 0.72),

                                  const Color(
                                    0xFF051F4E,
                                  ).withValues(alpha: 0.96),
                                ],

                                stops: const [0.0, 0.45, 0.72, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // =========================================
                      // PAGE TITLE / DESCRIPTION
                      // =========================================
                      Positioned(
                        left: 28,
                        right: 28,
                        bottom: bottomInset + 124,

                        child: Column(
                          mainAxisSize: MainAxisSize.min,

                          children: [
                            // -----------------------------------
                            // BADGE
                            // -----------------------------------
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 5.5,
                              ),

                              decoration: BoxDecoration(
                                color: truthTeal.withValues(alpha: 0.35),

                                borderRadius: BorderRadius.circular(20),

                                border: Border.all(
                                  color: const Color(
                                    0xFF2DD4BF,
                                  ).withValues(alpha: 0.6),

                                  width: 1,
                                ),
                              ),

                              child: Text(
                                page['badge']!,

                                style: const TextStyle(
                                  fontSize: 11,

                                  fontWeight: FontWeight.w700,

                                  color: Color(0xFF5EEAD4),

                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // -----------------------------------
                            // TITLE
                            // -----------------------------------
                            Text(
                              page['title']!,

                              textAlign: TextAlign.center,

                              style: const TextStyle(
                                fontSize: 26,

                                fontWeight: FontWeight.w800,

                                color: Colors.white,

                                height: 1.2,

                                letterSpacing: -0.4,

                                shadows: [
                                  Shadow(
                                    color: Colors.black54,

                                    blurRadius: 10,

                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // -----------------------------------
                            // SUBTITLE
                            // -----------------------------------
                            Text(
                              page['subtitle']!,

                              textAlign: TextAlign.center,

                              style: TextStyle(
                                fontSize: 14,

                                color: Colors.white.withValues(alpha: 0.88),

                                height: 1.45,

                                letterSpacing: 0.1,

                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,

                                    blurRadius: 8,

                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ===================================================
            // 2. SKIP BUTTON
            // ===================================================
            //
            // IMPORTANT FIX:
            //
            // There is NO SafeArea wrapping this button anymore.
            //
            // Instead:
            //
            // top = actual status bar height + 12
            //
            // That protects the button while allowing the video
            // itself to remain behind the status bar.
            // ===================================================
            Positioned(
              top: statusBarHeight + 12,
              right: 20,

              child: GestureDetector(
                behavior: HitTestBehavior.opaque,

                onTap: _finishOnboarding,

                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),

                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),

                    borderRadius: BorderRadius.circular(20),

                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),

                      width: 1.2,
                    ),

                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),

                        blurRadius: 10,

                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),

                  child: const Text(
                    'Skip',

                    style: TextStyle(
                      color: Colors.white,

                      fontSize: 13,

                      fontWeight: FontWeight.bold,

                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            // ===================================================
            // 3. PAGE INDICATORS
            // ===================================================
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset + 96,

              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: List.generate(
                  _pages.length,

                  (idx) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),

                    curve: Curves.easeInOut,

                    margin: const EdgeInsets.symmetric(horizontal: 3.5),

                    width: _currentPage == idx ? 24 : 7,

                    height: 7,

                    decoration: BoxDecoration(
                      color: _currentPage == idx
                          ? primaryColor
                          : Colors.white.withValues(alpha: 0.35),

                      borderRadius: BorderRadius.circular(4),

                      boxShadow: _currentPage == idx
                          ? [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.5),

                                blurRadius: 8,

                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),

            // ===================================================
            // 4. BOTTOM ACTION
            // ===================================================
            Positioned(
              left: 24,
              right: 24,
              bottom: bottomInset + 20,

              child: isLastPage
                  // ---------------------------------------------
                  // LAST PAGE
                  // ---------------------------------------------
                  ? SlideToActButton(
                      text: 'Slide to Get Started',

                      icon: Icons.keyboard_double_arrow_right,

                      onSlideComplete: _finishOnboarding,
                    )
                  // ---------------------------------------------
                  // NORMAL PAGE
                  // ---------------------------------------------
                  : ElevatedButton(
                      onPressed: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 350),

                          curve: Curves.easeInOut,
                        );
                      },

                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,

                        foregroundColor: Colors.white,

                        minimumSize: const Size.fromHeight(54),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),

                        elevation: 4,

                        shadowColor: primaryColor.withValues(alpha: 0.5),
                      ),

                      child: const Text(
                        'Next',

                        style: TextStyle(
                          fontSize: 16,

                          fontWeight: FontWeight.bold,

                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // VIDEO BACKGROUND
  // ===========================================================

  Widget _buildVideoBackground() {
    if (_isVideoInitialized && _videoController.value.isInitialized) {
      return Positioned.fill(
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,

            alignment: Alignment.center,

            child: SizedBox(
              width: _videoController.value.size.width,

              height: _videoController.value.size.height,

              child: VideoPlayer(_videoController),
            ),
          ),
        ),
      );
    }

    // ---------------------------------------------------------
    // Video loading fallback.
    // ---------------------------------------------------------

    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,

            colors: [Color(0xFF051F4E), Color(0xFF0C2340), Color(0xFF004D40)],
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // IMAGE BACKGROUND
  // ===========================================================

  Widget _buildImageBackground(Map<String, String> page) {
    final String image = page['image'] ?? '';

    if (image.startsWith('http')) {
      return Positioned.fill(
        child: Image.network(
          image,

          fit: BoxFit.cover,

          alignment: Alignment.center,

          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: const Color(0xFF051F4E),

              alignment: Alignment.center,

              child: const Icon(
                Icons.restaurant,

                size: 80,

                color: Colors.white24,
              ),
            );
          },
        ),
      );
    }

    return Positioned.fill(
      child: Image.asset(image, fit: BoxFit.cover, alignment: Alignment.center),
    );
  }
}
