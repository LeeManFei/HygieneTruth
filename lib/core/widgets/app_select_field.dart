import 'package:flutter/material.dart';

/// Uses the same dropdown interaction for every list size.
class AppSelectField<T> extends StatefulWidget {
  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final Widget? icon, hint, disabledHint;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;
  final double? menuMaxHeight;
  final int elevation;
  final bool isExpanded;
  final DropdownButtonBuilder? selectedItemBuilder;
  const AppSelectField({
    super.key,
    this.initialValue,
    this.items,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.style,
    this.icon,
    this.hint,
    this.disabledHint,
    this.dropdownColor,
    this.borderRadius,
    this.menuMaxHeight,
    this.elevation = 4,
    this.isExpanded = true,
    this.selectedItemBuilder,
  });
  @override
  State<AppSelectField<T>> createState() => _AppSelectFieldState<T>();
}

class _AppSelectFieldState<T> extends State<AppSelectField<T>> {
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey(widget.initialValue),
      initialValue: widget.initialValue,
      items: widget.items?.map((item) {
        final child = item.child;
        return DropdownMenuItem<T>(
          value: item.value,
          enabled: item.enabled,
          onTap: item.onTap,
          alignment: item.alignment,
          child: child is Text && child.data != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(child.data!, style: child.style, softWrap: true),
                )
              : child,
        );
      }).toList(),
      onChanged: widget.onChanged,
      decoration: widget.decoration,
      isExpanded: widget.isExpanded,
      style: widget.style,
      icon: widget.icon,
      hint: widget.hint,
      disabledHint: widget.disabledHint,
      dropdownColor: widget.dropdownColor,
      borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
      elevation: widget.elevation,
      menuMaxHeight: widget.menuMaxHeight ?? 360,
      itemHeight: null,
      selectedItemBuilder:
          widget.selectedItemBuilder ??
          (context) => (widget.items ?? []).map((item) {
            final child = item.child;
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: child is Text && child.data != null
                  ? Text(
                      child.data!,
                      style: child.style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : child,
            );
          }).toList(),
    );
  }
}
