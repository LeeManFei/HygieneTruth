import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/uuid_helper.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/custom_button.dart';
import '../../notifications/models/notification_model.dart';

class ScheduleInspectionScreen extends StatefulWidget {
  const ScheduleInspectionScreen({super.key});

  @override
  State<ScheduleInspectionScreen> createState() => _ScheduleInspectionScreenState();
}

class _ScheduleInspectionScreenState extends State<ScheduleInspectionScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 30);
  String _selectedInspectionType = 'On-site Hygiene Audit';
  bool _isSubmitting = false;
  final TextEditingController _notesCtrl = TextEditingController();

  final List<String> _inspectionTypes = [
    'On-site Hygiene Audit',
    'Pest Re-inspection',
    'Sample Swab Test',
    'Notice Follow-up',
  ];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime _visitDateTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  void _selectVisit(DateTime date, TimeOfDay time) {
    if (!mounted) return;
    if (!_visitDateTime(date, time).isAfter(DateTime.now())) {
      HygieneFeedback.showWarning(context, 'Choose a visit date and time in the future. For today, choose a later time.');
      return;
    }
    setState(() { _selectedDate = date; _selectedTime = time; });
  }

  String _formatCaseId(String rawId) {
    if (rawId.startsWith('CMP-') || rawId.startsWith('cmp_')) {
      return rawId.toUpperCase();
    }
    final short = rawId.length > 8 ? rawId.substring(0, 8) : rawId;
    return 'CMP-${short.toUpperCase()}';
  }

  String _formatDateDisplay(DateTime dt) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  void _applyQuickPreset(int daysFromNow, int hour, int minute) {
    setState(() {
      _selectedDate = DateTime.now().add(Duration(days: daysFromNow));
      _selectedTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    ComplaintModel? c;
    if (args is ComplaintModel) {
      c = args;
    } else if (RestaurantStoreService.complaintsNotifier.value.isNotEmpty) {
      c = RestaurantStoreService.complaintsNotifier.value.first;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (c == null) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Schedule Visit'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No complaint available to schedule an inspection.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    final formattedId = _formatCaseId(c.id);
    final restName = RestaurantStoreService.resolveRestaurantName(c.restaurantName, fallback: c.restaurantName);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Schedule Visit'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. HERO CASE OVERVIEW CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                      : [const Color(0xFF0C2340), const Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          formattedId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.priority_high_rounded, color: Color(0xFFFDE68A), size: 12),
                            SizedBox(width: 4),
                            Text(
                              'Priority Visit',
                              style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.report_problem_outlined, size: 13, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        'Issue: ${c.category}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (RestaurantStoreService.inspectionsNotifier.value.any((i) =>
                ((i.restaurantId.isNotEmpty && i.restaurantId == (c?.restaurantId ?? '')) ||
                    i.restaurantName.toLowerCase() == restName.toLowerCase()) &&
                i.enforcementStatus != EnforcementStatus.completed)) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Active Investigation in Progress: An inspection audit is already active for $restName. Ensure you coordinate with your team to avoid duplicate physical visits.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 2. INSPECTION TYPE SELECTOR
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.assignment_outlined, color: Color(0xFF0F766E), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Inspection Mission Type',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _inspectionTypes.map((type) {
                      final isSelected = (_selectedInspectionType == type);
                      return ChoiceChip(
                        label: Text(type),
                        selected: isSelected,
                        selectedColor: const Color(0xFF0F766E),
                        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _selectedInspectionType = type);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. DATE & TIME SELECTION CARDS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF0284C7), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Visit Date & Time',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Date Row Card
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (picked != null) _selectVisit(picked, _selectedTime);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_rounded, color: Color(0xFF0F766E), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Scheduled Date', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDateDisplay(_selectedDate),
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0C2340)),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 60)),
                              );
                              if (picked != null) _selectVisit(picked, _selectedTime);
                            },
                            child: const Text('Change Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Time Row Card
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) _selectVisit(_selectedDate, picked);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_filled_rounded, color: Color(0xFF0284C7), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Inspection Time', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedTime.format(context),
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0C2340)),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _selectedTime,
                              );
                              if (picked != null) _selectVisit(_selectedDate, picked);
                            },
                            child: const Text('Change Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Quick Schedule Presets Row
                  Row(
                    children: [
                      _buildPresetButton('Tomorrow 10:00 AM', () => _applyQuickPreset(1, 10, 0), isDark),
                      const SizedBox(width: 8),
                      _buildPresetButton('Tomorrow 2:30 PM', () => _applyQuickPreset(1, 14, 30), isDark),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. OFFICER DIRECTIVES & NOTES BOX
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.edit_note_rounded, color: Color(0xFF7C3AED), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Officer Directives & Focus Areas',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0C2340),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enter specific checklist instructions for visiting officers...',
                      hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const SizedBox(height: 24),

            // 5. CONFIRM VISIT ACTION BUTTON
            CustomButton(
              label: 'Confirm & Schedule Visit',
              icon: Icons.event_available_rounded,
              backgroundColor: const Color(0xFF0F766E),
              isLoading: _isSubmitting,
              onPressed: () => _handleSchedule(c, restName),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _handleSchedule(ComplaintModel? c, String restName) async {
    if (_isSubmitting) return;

    final scheduledAt = _visitDateTime(_selectedDate, _selectedTime);
    if (!scheduledAt.isAfter(DateTime.now())) {
      HygieneFeedback.showWarning(context, 'Choose a visit date and time in the future.');
      return;
    }

    // Validation 2: Ensure outlet name is valid
    if (restName.trim().isEmpty) {
      HygieneFeedback.showWarning(context, 'Premise name is required before scheduling.');
      return;
    }

    setState(() => _isSubmitting = true);

    final String scheduledStr = '${_formatDateDisplay(_selectedDate)} at ${_selectedTime.format(context)}';

    try {
      // 1. Create and register InspectionModel in inspectionsNotifier & Supabase
      final existingInspection = c == null
          ? null
          : RestaurantStoreService.inspectionsNotifier.value
              .where((item) => item.complaintId == c.id)
              .firstOrNull;
      final inspectionId = existingInspection?.id ?? UuidHelper.generateV4();
      final newInsp = InspectionModel(
        id: inspectionId,
        complaintId: c?.id ?? '',
        restaurantId: c?.restaurantId ?? '',
        restaurantName: restName,
        scheduledDate: scheduledAt.toUtc().toIso8601String(),
        conductedDate: null,
        officerName: 'Health Inspector (KKM)',
        outcome: InspectionOutcome.pending,
        findings: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : 'Scheduled official hygiene inspection: $_selectedInspectionType on $scheduledStr',
        recommendedAction: EnforcementType.none,
        issuedAction: EnforcementType.none,
        justification: 'Official hygiene audit scheduled for $scheduledStr.',
        fineAmount: 0.0,
        statutoryCitation: 'Food Act 1983 - Section 10',
        enforcementStatus: EnforcementStatus.pending,
        isAdminApproved: false,
        issuedDate: null,
        dueDate: null,
        isFinePaid: false,
      );

      await RestaurantStoreService.saveInspection(newInsp);

      // 2. Update complaint status in ComplaintStoreService
      if (c != null) {
        await ComplaintStoreService.updateComplaintStatus(c.id, ComplaintStatus.pendingInspection);
      }

      // 3. Log audit action & sync officer route
      AuditLogService.logAction(
        actionType: 'INSPECTION_SCHEDULED',
        category: 'Government',
        title: 'Health Inspection Visit Scheduled',
        description: 'Scheduled $_selectedInspectionType for $restName ($scheduledStr). Notes: ${_notesCtrl.text.trim()}',
      );

      // 4. Automatically dispatch notification to premise owner
      NotificationService.sendNotification(
        userId: 'own_001',
        title: '📅 Scheduled Health Inspection Notice',
        message: 'MOH Health Inspector has scheduled a $_selectedInspectionType on $scheduledStr for $restName.',
        type: NotificationType.outlet,
        actionUrl: c != null ? 'case_${c.id}' : 'notice',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showSuccess(context, 'Inspection scheduled for $restName on $scheduledStr!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      HygieneFeedback.showError(context, 'Failed to schedule inspection: $e');
    }
  }

  Widget _buildPresetButton(String label, VoidCallback onTap, bool isDark) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
