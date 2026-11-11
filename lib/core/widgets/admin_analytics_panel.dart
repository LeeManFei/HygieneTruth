import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Counts only dated reports received inside the selected local calendar period.
class AdminReportAnalytics {
  final DateTime start, end;
  final List<int> arrivals;
  final Map<String, int> statuses = {}, categories = {};
  int total = 0, flagged = 0, missingDates = 0;
  AdminReportAnalytics(List<Map<String, dynamic>> rows, int days, DateTime now)
    : start = DateTime(now.year, now.month, now.day - days + 1),
      end = now,
      arrivals = List.filled(days == 7 ? 7 : 6, 0) {
    final bucketDays = days == 7 ? 1 : days ~/ 6;
    for (final row in rows) {
      final date = DateTime.tryParse('${row['submitted_at'] ?? ''}')?.toLocal();
      if (date == null) {
        missingDates++;
        continue;
      }
      if (date.isBefore(start) || date.isAfter(end)) continue;
      total++;
      if (row['is_flagged_for_review'] == true) flagged++;
      final status = '${row['status'] ?? 'Unknown'}';
      statuses.update(status, (n) => n + 1, ifAbsent: () => 1);
      final raw = '${row['category'] ?? ''}'.trim();
      final category = raw.isEmpty ? 'Uncategorised' : raw;
      categories.update(category, (n) => n + 1, ifAbsent: () => 1);
      final localDay = DateTime.utc(date.year, date.month, date.day);
      final firstDay = DateTime.utc(start.year, start.month, start.day);
      final index = localDay.difference(firstDay).inDays ~/ bucketDays;
      arrivals[index.clamp(0, arrivals.length - 1)]++;
    }
  }
  int get open => statuses.entries
      .where((e) => !['resolved', 'rejected'].contains(e.key))
      .fold(0, (n, e) => n + e.value);
}

class AdminAnalyticsPanel extends StatefulWidget {
  final List<Map<String, dynamic>> reports;
  final DateTime updatedAt;
  final VoidCallback onOpenReports;
  const AdminAnalyticsPanel({
    super.key,
    required this.reports,
    required this.updatedAt,
    required this.onOpenReports,
  });
  @override
  State<AdminAnalyticsPanel> createState() => _AdminAnalyticsPanelState();
}

class _AdminAnalyticsPanelState extends State<AdminAnalyticsPanel> {
  int _days = 30;
  String _date(DateTime d) => '${d.day}/${d.month}';
  String _rangeDate(DateTime d) =>
      '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  static const _labels = {
    'submitted': 'Submitted',
    'underReview': 'Under review',
    'investigating': 'Investigating',
    'pendingInspection': 'Visit pending',
    'resolved': 'Resolved',
    'rejected': 'Rejected',
  };
  static const _colors = [
    AppTheme.primaryColor,
    Color(0xFF0284C7),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    AppTheme.safeColor,
    AppTheme.highRiskColor,
  ];
  Color _statusColor(String value) => switch (value) {
    'resolved' => AppTheme.safeColor,
    'rejected' => AppTheme.highRiskColor,
    'submitted' => const Color(0xFFF59E0B),
    'underReview' => AppTheme.primaryColor,
    'pendingInspection' => const Color(0xFF8B5CF6),
    _ => const Color(0xFF0284C7),
  };
  @override
  Widget build(BuildContext context) {
    final data = AdminReportAnalytics(widget.reports, _days, widget.updatedAt);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? AppTheme.darkSubtitleColor : AppTheme.subtitleColor;
    Widget section(String title, String subtitle, Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppTheme.darkBorderColor : AppTheme.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
    Widget distribution(Map<String, int> values, {bool status = false}) {
      final entries = values.entries.toList()
        ..sort(
          (a, b) => b.value == a.value
              ? a.key.compareTo(b.key)
              : b.value.compareTo(a.value),
        );
      if (status) {
        final order = [
          'submitted',
          'underReview',
          'pendingInspection',
          'investigating',
          'resolved',
          'rejected',
        ];
        entries.sort(
          (a, b) => (order.contains(a.key) ? order.indexOf(a.key) : 99)
              .compareTo(order.contains(b.key) ? order.indexOf(b.key) : 99),
        );
      }
      final shown = status ? entries : entries.take(5).toList();
      if (!status && entries.length > 5) {
        shown.add(
          MapEntry(
            'Other categories',
            entries.skip(5).fold(0, (n, e) => n + e.value),
          ),
        );
      }
      return Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          status
                              ? _labels[shown[i].key] ?? shown[i].key
                              : shown[i].key,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${shown[i].value} · ${(shown[i].value * 100 / data.total).round()}%',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    label:
                        '${shown[i].key}: ${shown[i].value} of ${data.total} reports',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 9,
                        value: shown[i].value / data.total,
                        backgroundColor: _colors[i % _colors.length].withValues(
                          alpha: .10,
                        ),
                        color: status
                            ? _statusColor(shown[i].key)
                            : _colors[i % _colors.length],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final maxCount = math.max(1, data.arrivals.reduce(math.max));
    final bucketDays = _days == 7 ? 1 : _days ~/ 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Report overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Received ${_rangeDate(data.start)} – ${_rangeDate(data.end)} · Updated ${widget.updatedAt.hour.toString().padLeft(2, '0')}:${widget.updatedAt.minute.toString().padLeft(2, '0')}',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final days in [7, 30, 90])
              ChoiceChip(
                label: Text('$days days'),
                selected: days == _days,
                onSelected: (_) => setState(() => _days = days),
                selectedColor: AppTheme.primaryColor,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: days == _days ? Colors.white : null,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final entry in {
              'Received': data.total,
              'Still open': data.open,
              'Flagged': data.flagged,
            }.entries)
              Semantics(
                label: '${entry.key}: ${entry.value}',
                child: Chip(
                  label: Text(
                    '${entry.key}  ${entry.value}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  side: BorderSide.none,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: .08),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (data.total == 0)
          section(
            'No reports in this period',
            'Choose a longer period or open the reports list.',
            TextButton.icon(
              onPressed: widget.onOpenReports,
              icon: const Icon(Icons.inbox_outlined),
              label: const Text('Open reports'),
            ),
          )
        else ...[
          section(
            'Incoming requests',
            '${bucketDays == 1 ? 'Daily arrivals' : 'Arrivals per $bucketDays days'} · Numbers above bars are report counts.',
            Column(
              children: [
                SizedBox(
                  height: 148,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < data.arrivals.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Tooltip(
                              message:
                                  '${_date(data.start.add(Duration(days: i * bucketDays)))}: ${data.arrivals[i]} reports',
                              child: Semantics(
                                label:
                                    'From ${_date(data.start.add(Duration(days: i * bucketDays)))}: ${data.arrivals[i]} reports',
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${data.arrivals[i]}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 100 * data.arrivals[i] / maxCount,
                                      constraints: const BoxConstraints(
                                        maxWidth: 34,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: i == data.arrivals.length - 1
                                              ? 1
                                              : .65,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < data.arrivals.length; i++)
                      Expanded(
                        child: Text(
                          _date(data.start.add(Duration(days: i * bucketDays))),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          section(
            'Request progress',
            'Current status of reports received in this period.',
            distribution(data.statuses, status: true),
          ),
          section(
            'Most reported issues',
            'Categories share the same report total; smaller categories are grouped.',
            distribution(data.categories),
          ),
        ],
        if (data.missingDates > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${data.missingDates} reports have no valid date and are excluded from these charts.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
      ],
    );
  }
}
