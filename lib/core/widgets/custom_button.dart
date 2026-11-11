import 'package:flutter/material.dart';
import 'dual_arc_loader.dart';

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isOutlined;
  final bool isLoading;
  final double width;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.isOutlined = false,
    this.isLoading = false,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDisabled = onPressed == null && !isLoading;
    final defaultDisabledBg = isDark ? const Color(0xFF333333) : const Color(0xFF9E9E9E);
    final effectiveBg = backgroundColor ?? (isDisabled ? defaultDisabledBg : Theme.of(context).primaryColor);
    final effectiveTextColor = textColor ?? Colors.white;

    final style = isOutlined
        ? OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            side: BorderSide(
              color: isDisabled
                  ? (isDark ? Colors.white24 : Colors.grey.shade400)
                  : (backgroundColor ?? Theme.of(context).primaryColor),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: effectiveBg,
            disabledBackgroundColor: backgroundColor ?? defaultDisabledBg,
            disabledForegroundColor: Colors.white,
            foregroundColor: effectiveTextColor,
            elevation: isDisabled ? 0 : 2,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          );

    final child = isLoading
        ? DualArcLoader(
            size: 20,
            strokeWidth: 2.2,
            color: isOutlined ? (backgroundColor ?? Theme.of(context).primaryColor) : effectiveTextColor,
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: isOutlined
                      ? (isDisabled ? (isDark ? Colors.white38 : Colors.grey) : (backgroundColor ?? Theme.of(context).primaryColor))
                      : effectiveTextColor,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: isOutlined
                        ? (isDisabled ? (isDark ? Colors.white38 : Colors.grey) : (backgroundColor ?? Theme.of(context).primaryColor))
                        : effectiveTextColor,
                  ),
                ),
              ),
            ],
          );

    return SizedBox(
      width: width,
      child: isOutlined
          ? OutlinedButton(onPressed: isLoading ? null : onPressed, style: style, child: child)
          : ElevatedButton(onPressed: isLoading ? null : onPressed, style: style, child: child),
    );
  }
}
