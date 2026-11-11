import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'shimmer_skeletons.dart';

/// Reusable UserBanner widget that displays:
/// 1. Custom uploaded image (network URL, local file, or base64 data URI)
/// 2. Or the rich aesthetic default dark gradient banner with ambient circles
class UserBanner extends StatelessWidget {
  final String? bannerUrl;
  final double height;
  final BorderRadius? borderRadius;
  final Widget? overlay;
  final Widget? child;

  const UserBanner({
    super.key,
    required this.bannerUrl,
    this.height = 140,
    this.borderRadius,
    this.overlay,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;

    final url = bannerUrl?.trim() ?? '';

    if (url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        content = Image.network(
          url,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildDefaultBanner(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildDefaultBanner(isLoading: true);
          },
        );
      } else if (url.startsWith('data:image') || url.length > 200 && !url.contains('/')) {
        try {
          final cleanBase64 = url.contains(',') ? url.split(',').last : url;
          final bytes = base64Decode(cleanBase64);
          content = Image.memory(
            bytes,
            width: double.infinity,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildDefaultBanner(),
          );
        } catch (_) {
          content = _buildDefaultBanner();
        }
      } else {
        // Local file path
        try {
          final file = File(url);
          if (file.existsSync()) {
            content = Image.file(
              file,
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildDefaultBanner(),
            );
          } else {
            content = _buildDefaultBanner();
          }
        } catch (_) {
          content = _buildDefaultBanner();
        }
      }
    } else {
      content = _buildDefaultBanner();
    }

    Widget bannerWithOverlay = Stack(
      children: [
        Positioned.fill(child: content),
        // Subtle dark gradient overlay to ensure contrast and premium feel
        if (url.isNotEmpty)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ?overlay,
        ?child,
      ],
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: bannerWithOverlay,
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: bannerWithOverlay,
    );
  }

  Widget _buildDefaultBanner({bool isLoading = false}) {
    if (isLoading) {
      return BaseSkeleton(
        width: double.infinity,
        height: height,
        borderRadius: borderRadius?.topLeft.x ?? 0,
      );
    }

    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0C2340),
            Color(0xFF0F766E),
          ],
          stops: [0.0, 0.4, 0.75, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Subtle decorative floating circles
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 10,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
