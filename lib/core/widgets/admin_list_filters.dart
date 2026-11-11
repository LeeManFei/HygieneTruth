import 'app_search_field.dart';
import 'package:flutter/material.dart';
import 'government_list_tools.dart';
import '../theme/app_theme.dart';

class AdminListFilters extends StatelessWidget {
  final TextEditingController? search;
  final String hint, guidance, dateLabel, sort, group;
  final int days, count;
  final List<String> sorts, groups;
  final ValueChanged<String> onSort, onGroup;
  final ValueChanged<int> onDays;
  final VoidCallback onSearch;
  const AdminListFilters({super.key, this.search, this.hint = 'Search records...',
    required this.guidance, required this.dateLabel, required this.sort,
    required this.days, required this.count, required this.onSort, required this.onDays,
    this.sorts = const ['Newest first', 'Oldest first'], this.groups = const [],
    this.group = 'All', required this.onGroup, required this.onSearch});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (search != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AppSearchField(controller: search, onChanged: (_) => onSearch(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: search!.text.isEmpty ? null : IconButton(tooltip: 'Clear search',
            icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { search!.clear(); onSearch(); })))),
    if (count == 0 && (search?.text.isNotEmpty == true || days != 0 || group != 'All')) Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, children: [
        const Text('No matching records.'), TextButton(onPressed: () {
          search?.clear(); onSearch(); onDays(0); onGroup('All');
        }, child: const Text('Clear search & filters')),
      ])),
    if (groups.isNotEmpty) Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _categoryRow(context)),
    GovernmentListTools(compact: true, guidance: guidance, dateLabel: dateLabel,
      count: count, days: days, sort: sort, sorts: sorts, onDays: onDays, onSort: onSort),
  ]);
  String _label(String value) => const {
    'active': 'Active', 'pendingVerification': 'Pending verification',
    'suspended': 'Suspended', 'deactivated': 'Deactivated',
  }[value] ?? value;

  Widget _categoryRow(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppTheme.darkTextColor : AppTheme.navyColor;
    final border = dark ? AppTheme.darkBorderColor : AppTheme.borderColor;
    final surface = dark ? AppTheme.darkSurfaceColor : Colors.white;
    const accent = Color(0xFF0F766E);
    final style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink);
    final available = constraints.maxWidth;
    if (available <= 0) return const SizedBox.shrink();
    double textWidth(String label) {
      final painter = TextPainter(text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }
    // Reserve the checkmark even when unselected, so choosing a category does not move the row.
    final widths = groups.map((g) => textWidth(_label(g)) + 60).toList();
    final total = widths.fold<double>(0, (sum, w) => sum + w) + (groups.length - 1) * 8;
    var visible = groups.length;
    final moreWidth = (textWidth('+more') + 36).clamp(0.0, available).toDouble();
    if (total > available) {
      visible = 0;
      var used = 0.0;
      for (final width in widths) {
        if (used + width + 8 + moreWidth > available) break;
        used += width + 8;
        visible++;
      }
    }
    final hidden = groups.skip(visible).toList();
    final hiddenSelected = hidden.contains(group);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      for (var i = 0; i < visible; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        SizedBox(width: widths[i], child: ChoiceChip(
          label: Text(_label(groups[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: group == groups[i], selectedColor: accent, backgroundColor: surface,
          checkmarkColor: Colors.white,
          labelStyle: style.copyWith(color: group == groups[i] ? Colors.white : ink),
          side: BorderSide(color: group == groups[i] ? accent : border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => onGroup(groups[i]),
        )),
      ],
      if (hidden.isNotEmpty) ...[
        if (visible > 0) const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: hiddenSelected ? 'More categories. Selected: ${_label(group)}' : 'More categories',
          onSelected: onGroup, position: PopupMenuPosition.under,
          color: surface, surfaceTintColor: Colors.transparent, elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
          itemBuilder: (_) => hidden.map((g) => PopupMenuItem<String>(value: g,
            child: Row(children: [
              Expanded(child: Text(_label(g), style: style.copyWith(color: group == g ? accent : ink))),
              if (group == g) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18, color: accent)),
            ]))).toList(),
          child: Container(width: moreWidth, constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: hiddenSelected ? accent : surface,
              border: Border.all(color: hiddenSelected ? accent : border), borderRadius: BorderRadius.circular(12)),
            child: Text('+more', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: hiddenSelected ? Colors.white : ink))),
        ),
      ],
    ]);
  });

}
