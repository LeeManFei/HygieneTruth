import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextStyle? style;
  final List<String> suggestions;
  final bool autofocus;
  const AppSearchField({
    super.key,
    this.controller,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.style,
    this.suggestions = const [],
    this.autofocus = false,
  });
  @override
  State<AppSearchField> createState() => _AppSearchFieldState();

  static int distance(String a, String b) {
    var previous = List.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitute = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final insert = current[j - 1] + 1, delete = previous[j] + 1;
        current[j] = [
          substitute,
          insert,
          delete,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous.last;
  }
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _owned = TextEditingController();
  TextEditingController get _controller => widget.controller ?? _owned;
  final _focus = FocusNode();
  final _recent = <String>[];
  int _selections = 0;
  @override
  void dispose() {
    _owned.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _remember(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return;
    _recent.remove(clean);
    _recent.insert(0, clean);
    if (_recent.length > 5) _recent.removeLast();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final box = context.findRenderObject();
      final media = MediaQuery.of(context);
      final top = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero).dy
          : 0.0;
      final below = media.size.height - media.viewInsets.bottom - top - 60;
      final opensUp = below < 260 && top > below;
      final popupHeight = (opensUp ? top - media.padding.top - 16 : below - 8)
          .clamp(80.0, 260.0);
      return RawAutocomplete<String>(
        textEditingController: _controller,
        focusNode: _focus,
        optionsViewOpenDirection: opensUp
            ? OptionsViewOpenDirection.up
            : OptionsViewOpenDirection.down,
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          final source = {
            ..._recent,
            ...widget.suggestions.where((s) => s.trim().isNotEmpty),
          };
          final exact = source
              .where((s) => s.toLowerCase().contains(q))
              .take(5)
              .toList();
          if (exact.isNotEmpty ||
              q.length < 5 ||
              q.length > 40 ||
              RegExp(r'[0-9@]').hasMatch(q)) {
            return exact;
          }
          return source
              .where(
                (s) => s
                    .toLowerCase()
                    .split(RegExp(r'\s+'))
                    .any(
                      (word) =>
                          (word.length - q.length).abs() <= 2 &&
                          AppSearchField.distance(q, word) <=
                              (q.length >= 7 ? 2 : 1),
                    ),
              )
              .take(5);
        },
        onSelected: (value) {
          _selections++;
          _remember(value);
          widget.onChanged?.call(value);
          widget.onSubmitted?.call(value);
          setState(() {});
        },
        fieldViewBuilder: (context, controller, focus, submit) => TextField(
          controller: controller,
          focusNode: focus,
          autofocus: widget.autofocus,
          style: widget.style,
          textInputAction: TextInputAction.search,
          decoration: widget.decoration.copyWith(
            suffixIcon:
                widget.decoration.suffixIcon ??
                (controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          controller.clear();
                          widget.onChanged?.call('');
                          setState(() {});
                        },
                      )),
          ),
          onChanged: (value) {
            widget.onChanged?.call(value);
            setState(() {});
          },
          onSubmitted: (value) {
            final before = _selections;
            submit();
            if (before == _selections) {
              _remember(value);
              widget.onSubmitted?.call(value);
            }
          },
        ),
        optionsViewBuilder: (context, choose, options) {
          final rows = options.toList();
          final q = _controller.text.trim().toLowerCase();
          final similar =
              q.isNotEmpty && rows.any((s) => !s.toLowerCase().contains(q));
          return Align(
            alignment: opensUp ? Alignment.bottomLeft : Alignment.topLeft,
            child: Material(
              elevation: 4,
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: bounds.maxWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: popupHeight),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Text(
                          similar
                              ? 'Similar names · choose to search'
                              : q.isEmpty
                              ? 'Recent searches & suggestions'
                              : 'Suggestions',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      for (var i = 0; i < rows.length; i++)
                        Builder(
                          builder: (context) {
                            final index = rows[i].toLowerCase().indexOf(q);
                            return ListTile(
                              dense: true,
                              selected:
                                  AutocompleteHighlightedOption.of(context) ==
                                  i,
                              selectedTileColor: AppTheme.primaryColor
                                  .withValues(alpha: .1),
                              title: index < 0 || q.isEmpty
                                  ? Text(rows[i])
                                  : Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: rows[i].substring(0, index),
                                          ),
                                          TextSpan(
                                            text: rows[i].substring(
                                              index,
                                              index + q.length,
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                          TextSpan(
                                            text: rows[i].substring(
                                              index + q.length,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              onTap: () => choose(rows[i]),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
