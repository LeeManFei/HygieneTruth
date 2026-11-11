import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GovernmentRecordDate {
  static String format(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) return 'Not recorded';
    final local = date.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = '${local.day} ${months[local.month - 1]} ${local.year}';
    if (raw!.length == 10) return '$day (time not recorded)';
    return '$day, ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static bool matches(String? raw, int days, {DateTime? now}) {
    if (days == 0) return true;
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return false;
    final today = (now ?? DateTime.now()).toLocal();
    final start = DateTime(today.year, today.month, today.day - days + 1);
    final end = DateTime(today.year, today.month, today.day + 1);
    return !date.isBefore(start) && date.isBefore(end);
  }

  static int compare(String? a, String? b, bool oldest) {
    final da = DateTime.tryParse(a ?? '');
    final db = DateTime.tryParse(b ?? '');
    if (da == null) return db == null ? 0 : 1;
    if (db == null) return -1;
    return oldest ? da.compareTo(db) : db.compareTo(da);
  }
}

class GovernmentListTools extends StatelessWidget {
  final bool compact;
  final String guidance;
  final String dateLabel;
  final int count;
  final int days;
  final String sort;
  final List<String> sorts;
  final ValueChanged<int> onDays;
  final ValueChanged<String> onSort;
  const GovernmentListTools({super.key, this.compact = false, required this.guidance, required this.dateLabel,
    required this.count, required this.days, required this.sort, required this.sorts,
    required this.onDays, required this.onSort});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppTheme.darkTextColor : AppTheme.navyColor;
    final muted = dark ? AppTheme.darkSubtitleColor : AppTheme.subtitleColor;
    final accent = dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
    final border = dark ? AppTheme.darkBorderColor : AppTheme.borderColor;
    final dateText = days == 0 ? 'All dates' : days == 1 ? 'Today' : 'Last $days days';

    Widget control(IconData icon, String label, String value, bool active) => Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.06) : (dark ? AppTheme.darkSurfaceColor : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? accent.withValues(alpha: 0.4) : border),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w600)),
        ])),
        Icon(Icons.expand_more_rounded, size: 18, color: muted),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!compact) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: dark ? 0.1 : 0.045),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.15)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.assistant_direction_outlined, size: 19, color: accent),
            const SizedBox(width: 10),
            Expanded(child: Text(guidance, style: TextStyle(fontSize: 11.5, height: 1.45, color: dark ? AppTheme.darkTextColor : const Color(0xFF475569)))),
          ]),
        ),
        if (!compact) const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(12) > 18;
          final menuWidth = stacked ? constraints.maxWidth : (constraints.maxWidth - 10) / 2;

          PopupMenuItem<T> option<T>(T value, String label, bool selected) => PopupMenuItem<T>(
            value: value,
            padding: EdgeInsets.zero,
            child: Semantics(
              selected: selected,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: dark ? 0.14 : 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Expanded(child: Text(label, style: TextStyle(
                    fontSize: 12, height: 1.4,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? accent : ink,
                  ))),
                  const SizedBox(width: 6),
                  SizedBox(width: 16, child: selected ? Icon(Icons.check_rounded, size: 16, color: accent) : null),
                ]),
              ),
            ),
          );

          Widget menu<T>({required String tooltip, required ValueChanged<T> onSelected,
            required List<PopupMenuEntry<T>> Function(BuildContext) items, required Widget child}) => PopupMenuButton<T>(
            tooltip: tooltip, onSelected: onSelected,
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            constraints: BoxConstraints.tightFor(width: menuWidth),
            color: dark ? AppTheme.darkSurfaceColor : Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: dark ? 0.3 : 0.12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
            clipBehavior: Clip.antiAlias,
            menuPadding: const EdgeInsets.all(6),
            itemBuilder: items,
            child: child,
          );
          final controls = [
            menu<String>(
              tooltip: 'Change record order', onSelected: onSort,
              items: (_) => sorts.map((s) => option(s, s, s == sort)).toList(),
              child: control(Icons.sort_rounded, 'Sort by', sort, false),
            ),
            menu<int>(
              tooltip: 'Filter by $dateLabel date', onSelected: onDays,
              items: (_) => [0, 1, 7, 30].map((d) => option(d,
                d == 0 ? 'All dates' : d == 1 ? 'Today' : 'Last $d days', d == days)).toList(),
              child: control(Icons.calendar_month_outlined, '$dateLabel date', dateText, days != 0),
            ),
          ];
          return stacked
            ? Column(children: [controls[0], const SizedBox(height: 8), controls[1]])
            : Row(children: [Expanded(child: controls[0]), const SizedBox(width: 10), Expanded(child: controls[1])]);
        }),
        const SizedBox(height: 12),
        Row(children: [
          if (compact) Padding(padding: const EdgeInsets.only(right: 6), child: Tooltip(message: guidance, child: Icon(Icons.info_outline_rounded, size: 15, color: muted))),
          Text('Records', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: border)),
        ]),
      ]),
    );
  }
}
