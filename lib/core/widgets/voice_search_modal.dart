import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';

class VoiceSearchModal extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onResult;
  final stt.SpeechToText? speechToText;
  final List<String>? suggestions;

  const VoiceSearchModal({
    super.key,
    this.initialText = '',
    required this.onResult,
    this.speechToText,
    this.suggestions,
  });

  static Future<String?> show({
    required BuildContext context,
    String initialText = '',
    required ValueChanged<String> onResult,
    stt.SpeechToText? speechToText,
    List<String>? suggestions,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => VoiceSearchModal(
        initialText: initialText,
        onResult: onResult,
        speechToText: speechToText,
        suggestions: suggestions,
      ),
    );
  }

  @override
  State<VoiceSearchModal> createState() => _VoiceSearchModalState();
}

class _VoiceSearchModalState extends State<VoiceSearchModal>
    with TickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isSpeechAvailable = false;
  String _recognizedText = '';
  double _soundLevel = 0.0;
  double? _noiseFloor;
  Timer? _voiceRelease;
  bool _starting = false;
  bool _closing = false;
  bool _voiceDetected = false;
  String? _speechError;
  String _lastHeard = '';

  void _endListening() {
    if (!mounted) return;
    _voiceRelease?.cancel();
    _rippleController.stop();
    _soundBarController.stop();
    setState(() { _isListening = false; _soundLevel = 0; _voiceDetected = false; });
  }

  void _markSpeech() {
    _voiceRelease?.cancel();
    _voiceDetected = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _rippleController.repeat();
      _soundBarController.repeat(reverse: true);
    }
    _voiceRelease = Timer(const Duration(milliseconds: 900), () {
      _rippleController.stop();
      _soundBarController.stop();
      if (mounted) setState(() { _voiceDetected = false; _soundLevel = 0; });
    });
  }

  void _onLevel(double level) {
    if (!mounted || !_isListening || !level.isFinite) return;
    _noiseFloor ??= level;
    // Learn ambient levels only outside recognised speech; never gate transcription.
    if (!_voiceDetected) _noiseFloor = _noiseFloor! * 0.9 + level * 0.1;
    final target = _voiceDetected ? ((level - _noiseFloor! - 2) / 10).clamp(0.0, 1.0) : 0.0;
    setState(() => _soundLevel += (target - _soundLevel) * 0.35);
  }

  late AnimationController _rippleController;
  late AnimationController _soundBarController;

  final List<String> _defaultSuggestions = [
    'Golden Dragon',
    'Halal Bistro',
    'Dim Sum',
    'Noodles',
    'Mamak',
    'Café',
    'Bakery',
  ];

  @override
  void initState() {
    super.initState();
    _recognizedText = widget.initialText;
    _speech = widget.speechToText ?? stt.SpeechToText();

    // Ripple wave animation for mic button
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Sound bar equalizer oscillation
    _soundBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _initAndStartListening();
  }

  Future<void> _initAndStartListening() async {
    try {
      // Rebind callbacks when this shared recognizer is reopened.
      _speech.statusListener = (status) {
        if (status == 'done' || status == 'notListening') _endListening();
      };
      _speech.errorListener = (_) {
        if (mounted) setState(() => _speechError = 'Could not hear that. Tap the mic to retry.');
        _endListening();
      };
      _isSpeechAvailable = await _speech.initialize(
        onStatus: _speech.statusListener, onError: _speech.errorListener);
      if (!mounted) return;
      if (_isSpeechAvailable) {
        await _startListening();
      } else {
        setState(() => _speechError = 'Microphone unavailable. You can use text search.');
      }
    } catch (_) {
      if (mounted) setState(() => _speechError = 'Microphone unavailable. You can use text search.');
      _endListening();
    }
  }

  Future<void> _startListening() async {
    if (!_isSpeechAvailable || _starting || _closing || !mounted) return;
    _starting = true;
    _noiseFloor = null;
    _voiceDetected = false;
    _soundLevel = 0;
    _speechError = null;
    _lastHeard = '';
    try {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          if (mounted && !_closing) {
            if (result.recognizedWords.trim().isEmpty) return;
            if (result.recognizedWords != _lastHeard) _markSpeech();
            _lastHeard = result.recognizedWords;
            setState(() {
              _recognizedText = result.recognizedWords;
            });
            widget.onResult(result.recognizedWords);
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              _closing = true;
              HapticFeedback.mediumImpact();
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && Navigator.canPop(context)) {
                  Navigator.pop(context, result.recognizedWords);
                }
              });
            }
          }
        },
        onSoundLevelChange: _onLevel,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.search,
          cancelOnError: true,
          partialResults: true,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _speechError = 'Could not start listening. Tap the mic to retry.');
      _endListening();
    } finally { _starting = false; }
  }

  void _toggleListening() {
    HapticFeedback.lightImpact();
    if (_isListening) {
      _speech.stop();
      _endListening();
    } else {
      _initAndStartListening();
    }
  }

  void _applySuggestion(String text) {
    _closing = true;
    HapticFeedback.mediumImpact();
    setState(() {
      _recognizedText = text;
      _isListening = false;
    });
    _speech.stop();
    widget.onResult(text);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context, text);
      }
    });
  }

  void _finishSearch() {
    _closing = true;
    HapticFeedback.selectionClick();
    _speech.stop();
    widget.onResult(_recognizedText);
    if (Navigator.canPop(context)) {
      Navigator.pop(context, _recognizedText);
    }
  }

  @override
  void dispose() {
    _closing = true;
    _voiceRelease?.cancel();
    _speech.cancel();
    _speech.statusListener = null;
    _speech.errorListener = null;
    _rippleController.dispose();
    _soundBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suggestions = widget.suggestions ?? _defaultSuggestions;

    return SafeArea(
      top: false,
      bottom: true,
      child: SingleChildScrollView(child: Container(
        decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row with Title and Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFF0D9488),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(
                    'Voice Food Search',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.navyColor,
                    ),
                  )),
                ],
              )),
              IconButton(
                onPressed: () {
                  _speech.stop();
                  Navigator.pop(context);
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status Badge Pill
          AnimatedContainer(
            height: 48,
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _isListening
                  ? (isDark ? const Color(0xFF0F766E).withValues(alpha: 0.3) : const Color(0xFFCCFBF1))
                  : (isDark ? const Color(0xFF334155).withValues(alpha: 0.3) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isListening
                    ? const Color(0xFF14B8A6)
                    : (isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isListening) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(
                    'Listening for Outlets & Cuisine...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                    ),
                  )),
                ] else ...[
                  Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 14,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(
                    _speechError ?? 'Paused • Tap Mic to Speak',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  )),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Wave Ripple Mic Button & Sound Equalizer Area
          SizedBox(
            height: 150,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Concentric Animated Ripple Waves
                if (_isListening && _voiceDetected && _soundLevel > 0.03)
                  AnimatedBuilder(
                    animation: _rippleController,
                    builder: (context, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: List.generate(3, (index) {
                          final double waveProgress = (_rippleController.value + (index * 0.33)) % 1.0;
                          final double size = 70.0 + (waveProgress * 75.0);
                          final double opacity = (1.0 - waveProgress).clamp(0.0, 0.45);

                          return Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF14B8A6).withValues(alpha: opacity * 0.3),
                              border: Border.all(
                                color: const Color(0xFF14B8A6).withValues(alpha: opacity),
                                width: 1.5,
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),

                // Center Glowing Microphone Button
                GestureDetector(
                  onTap: _toggleListening,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [const Color(0xFF0D9488), const Color(0xFF0F766E)]
                            : [const Color(0xFF64748B), const Color(0xFF475569)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? const Color(0xFF0D9488) : Colors.black)
                              .withValues(alpha: _isListening ? 0.45 : 0.2),
                          blurRadius: _isListening ? 18 : 8,
                          spreadRadius: _isListening ? 3 : 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Reserve space so waveform changes never move the sheet.
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AnimatedBuilder(
              animation: _soundBarController,
              builder: (context, _) {
                final double animValue = _soundBarController.value;
                final double baseLevel = _isListening ? _soundLevel : 0.0;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(7, (i) {
                    final double phase = (i * 0.45);
                    final double wave = math.sin((animValue * math.pi * 2) + phase).abs();
                    final double height = 6.0 + (baseLevel * wave * 26.0);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: 4.5,
                      height: height,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isListening
                              ? [const Color(0xFF2DD4BF), const Color(0xFF0F766E)]
                              : [Colors.grey.shade400, Colors.grey.shade500],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Fixed transcript space keeps the mic anchored as words arrive.
          Container(
            height: 96,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _recognizedText.isNotEmpty
                    ? const Color(0xFF0D9488).withValues(alpha: 0.5)
                    : (isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
                width: _recognizedText.isNotEmpty ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Text(
                  _recognizedText.isEmpty
                      ? 'Speak outlet name (e.g. Golden Dragon)'
                      : _recognizedText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _recognizedText.isEmpty ? 13.5 : 16,
                    fontWeight: _recognizedText.isEmpty ? FontWeight.w500 : FontWeight.bold,
                    color: _recognizedText.isEmpty
                        ? (isDark ? Colors.white38 : Colors.grey.shade500)
                        : (isDark ? const Color(0xFF5EEAD4) : AppTheme.navyColor),
                    height: 1.35,
                  ),
                ),
                if (_recognizedText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF0D9488)),
                      const SizedBox(width: 4),
                      Text(
                        'Detected speech input',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Quick Suggestion Chips
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'QUICK SUGGESTIONS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: suggestions.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => _applySuggestion(s),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 13,
                            color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            s,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : AppTheme.navyColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 18),

          // Action Buttons: Done / Search and Cancel
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _speech.stop();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _finishSearch,
                  icon: const Icon(Icons.search_rounded, size: 18, color: Colors.white),
                  label: Text(
                    _recognizedText.isNotEmpty ? 'Search "$_recognizedText"' : 'Done',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    backgroundColor: const Color(0xFF0D9488),
                    elevation: 3,
                    shadowColor: const Color(0xFF0D9488).withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      )),
    );
  }
}
