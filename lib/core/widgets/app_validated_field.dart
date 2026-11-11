import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Checks the existing field rule after focus leaves; submission remains owned by the screen.
class AppValidatedField extends StatefulWidget {
  final TextEditingController controller;
  final String? Function(String?) validator;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final bool obscureText, enabled;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final String? guidance;
  final Listenable? revalidateOn;
  const AppValidatedField({
    super.key,
    required this.controller,
    required this.validator,
    this.decoration = const InputDecoration(),
    this.style,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.onChanged,
    this.guidance,
    this.revalidateOn,
  });
  @override
  State<AppValidatedField> createState() => _AppValidatedFieldState();
}

class _AppValidatedFieldState extends State<AppValidatedField> {
  final _focus = FocusNode();
  bool _touched = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    widget.revalidateOn?.addListener(_recheck);
  }

  void _recheck() {
    if (mounted && _touched) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AppValidatedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revalidateOn != widget.revalidateOn) {
      oldWidget.revalidateOn?.removeListener(_recheck);
      widget.revalidateOn?.addListener(_recheck);
    }
  }

  void _focusChanged() {
    if (!_focus.hasFocus && mounted) setState(() => _touched = true);
  }

  @override
  void dispose() {
    widget.revalidateOn?.removeListener(_recheck);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localError = _touched
        ? widget.validator(widget.controller.text)
        : null;
    final error = widget.decoration.errorText ?? localError;
    final checked =
        _touched && error == null && widget.controller.text.isNotEmpty;
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      style: widget.style,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      onChanged: (value) {
        widget.onChanged?.call(value);
        setState(() {});
      },
      decoration: widget.decoration.copyWith(
        errorText: error,
        errorMaxLines: 3,
        helperText: checked
            ? 'Format checked'
            : widget.decoration.helperText ?? widget.guidance,
        helperMaxLines: 3,
        helperStyle: checked
            ? const TextStyle(color: AppTheme.safeColor, fontSize: 12)
            : widget.decoration.helperStyle,
        suffixIcon:
            widget.decoration.suffixIcon ??
            (checked
                ? const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.safeColor,
                    size: 20,
                  )
                : null),
      ),
    );
  }
}
