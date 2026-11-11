import 'package:flutter/material.dart';
import 'shimmer_skeletons.dart';

/// Reusable UserAvatar widget that displays:
/// 1. Google / custom profile image if `avatarUrl` is present and valid.
/// 2. Neutral default user silhouette icon (matching the standard avatar placeholder)
///    for default logins or newly created accounts without a custom picture.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 24,
    this.backgroundColor,
    this.iconColor,
    this.border,
    this.boxShadow,
  });

  bool get _hasValidUrl {
    if (avatarUrl == null) return false;
    final trimmed = avatarUrl!.trim();
    return trimmed.isNotEmpty && (trimmed.startsWith('http://') || trimmed.startsWith('https://'));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = backgroundColor ?? (isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0));
    final defaultIconColor = iconColor ?? (isDark ? const Color(0xFF737373) : const Color(0xFF94A3B8));

    Widget avatarContent;

    if (_hasValidUrl) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: defaultBg,
        child: ClipOval(
          child: Image.network(
            avatarUrl!.trim(),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultIcon(defaultBg, defaultIconColor);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return BaseSkeleton(
                width: radius * 2,
                height: radius * 2,
                borderRadius: radius,
              );
            },
          ),
        ),
      );
    } else {
      avatarContent = _buildDefaultIcon(defaultBg, defaultIconColor);
    }

    if (border != null || boxShadow != null) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          boxShadow: boxShadow,
        ),
        child: avatarContent,
      );
    }

    return avatarContent;
  }

  Widget _buildDefaultIcon(Color bg, Color iconClr) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.35,
        color: iconClr,
      ),
    );
  }
}
