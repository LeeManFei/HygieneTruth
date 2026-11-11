import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workflow_model.dart';
import '../models/user_model.dart';
import '../utils/uuid_helper.dart';
import 'supabase_service.dart';

class WorkflowService {
  static const String _workflowTable = 'workflow_states';
  static const String _workflowStepsTable = 'workflow_steps';
  static const String _localCachePrefix = 'workflow_state_';
  
  static final Map<String, WorkflowState> _localCache = {};
  static final StreamController<WorkflowState> _stateController = StreamController<WorkflowState>.broadcast();
  
  static Stream<WorkflowState> get stateStream => _stateController.stream;

  static WorkflowState? getCachedWorkflow(String complaintId) =>
      _localCache[complaintId];

  static Future<void> invalidateCache(String complaintId) async {
    _localCache.remove(complaintId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_localCachePrefix$complaintId');
    final workflow = await loadWorkflow(complaintId);
    if (workflow != null) _notifyStateChange(workflow);
  }

  /// Initialize 7-step workflow when a customer submits a complaint
  static Future<WorkflowState> initializeWorkflow(String complaintId) async {
    final workflowId = UuidHelper.generateV4();
    final now = DateTime.now().toUtc();
    
    final steps = [
      WorkflowStepState(step: WorkflowStep.customerSubmission, status: WorkflowStepStatus.completed, completedAt: now),
      WorkflowStepState(step: WorkflowStep.adminDuplicationReview, status: WorkflowStepStatus.active),
      WorkflowStepState(step: WorkflowStep.ownerRectificationPeriod, status: WorkflowStepStatus.locked),
      WorkflowStepState(step: WorkflowStep.officerInspection, status: WorkflowStepStatus.locked),
      WorkflowStepState(step: WorkflowStep.adminReportVerification, status: WorkflowStepStatus.locked),
      WorkflowStepState(step: WorkflowStep.officerEnforcementAction, status: WorkflowStepStatus.locked),
      WorkflowStepState(step: WorkflowStep.caseClosure, status: WorkflowStepStatus.locked),
    ];
    
    final workflow = WorkflowState(
      workflowId: workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.inProgress,
      currentStep: WorkflowStep.adminDuplicationReview,
      steps: steps,
      createdAt: now,
    );
    
    await _persistWorkflow(workflow);
    _notifyStateChange(workflow);
    return workflow;
  }

  /// Load workflow state for a complaint
  static Future<WorkflowState?> loadWorkflow(String complaintId) async {
    if (_localCache.containsKey(complaintId)) {
      return _localCache[complaintId];
    }
    
    // Try SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('$_localCachePrefix$complaintId');
      if (cached != null) {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        final stepsMap = (map['steps'] as List).cast<Map<String, dynamic>>();
        final workflow = WorkflowState.fromMap(map, stepsMap);
        _localCache[complaintId] = workflow;
        return workflow;
      }
    } catch (_) {}
    
    // Try Supabase
    try {
      final supabase = SupabaseService.client;
      final workflowRes = await supabase
          .from(_workflowTable)
          .select()
          .eq('complaint_id', complaintId)
          .maybeSingle();
      
      if (workflowRes != null) {
        final stepsRes = await supabase
            .from(_workflowStepsTable)
            .select()
            .eq('workflow_id', workflowRes['workflow_id'])
            .order('step_order');
        
        final workflow = WorkflowState.fromMap(
          Map<String, dynamic>.from(workflowRes),
          (stepsRes as List).map((s) => Map<String, dynamic>.from(s)).toList(),
        );
        
        _localCache[complaintId] = workflow;
        await _cacheLocally(workflow);
        return workflow;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WorkflowService] Load from Supabase error: $e');
      }
    }
    
    return null;
  }

  /// Step 2 -> 3: Admin approves genuine report and forwards case (starts 7-day owner countdown)
  static Future<WorkflowState> forwardCaseAfterAdminReview({
    required String complaintId,
    required String adminId,
    String? remarks,
  }) async {
    var workflow = await loadWorkflow(complaintId);
    workflow ??= await initializeWorkflow(complaintId);

    final now = DateTime.now().toUtc();
    final deadline = now.add(const Duration(days: 7));

    final updatedSteps = workflow.steps.map((s) {
      if (s.step == WorkflowStep.adminDuplicationReview) {
        return s.copyWith(
          status: WorkflowStepStatus.completed,
          completedBy: adminId,
          completedAt: now,
          remarks: remarks ?? 'Verified non-duplicate and forwarded to restaurant owner',
        );
      }
      if (s.step == WorkflowStep.ownerRectificationPeriod) {
        return s.copyWith(status: WorkflowStepStatus.active);
      }
      return s;
    }).toList();

    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.inProgress,
      currentStep: WorkflowStep.ownerRectificationPeriod,
      steps: updatedSteps,
      rectificationDeadline: deadline,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Step 3 -> 4 (Trigger A): Owner submits evidence before 7 days end -> unlocks Officer review
  static Future<WorkflowState> submitOwnerEvidence({
    required String complaintId,
    required String ownerId,
    String? remarks,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();
    final updatedSteps = workflow.steps.map((s) {
      if (s.step == WorkflowStep.ownerRectificationPeriod) {
        return s.copyWith(
          status: WorkflowStepStatus.completed,
          completedBy: ownerId,
          completedAt: now,
          remarks: remarks ?? 'Owner submitted rectification proof',
        );
      }
      if (s.step == WorkflowStep.officerInspection) {
        return s.copyWith(status: WorkflowStepStatus.active);
      }
      return s;
    }).toList();

    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.inProgress,
      currentStep: WorkflowStep.officerInspection,
      steps: updatedSteps,
      rectificationDeadline: workflow.rectificationDeadline,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Step 3 -> 4 (Trigger B): 7-Day owner rectification expires -> unlocks Officer review
  static Future<WorkflowState> expireOwnerRectification({
    required String complaintId,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();
    final updatedSteps = workflow.steps.map((s) {
      if (s.step == WorkflowStep.ownerRectificationPeriod) {
        return s.copyWith(
          status: WorkflowStepStatus.completed,
          completedBy: 'SystemTimer',
          completedAt: now,
          remarks: '7-day rectification period elapsed',
        );
      }
      if (s.step == WorkflowStep.officerInspection) {
        return s.copyWith(status: WorkflowStepStatus.active);
      }
      return s;
    }).toList();

    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.inProgress,
      currentStep: WorkflowStep.officerInspection,
      steps: updatedSteps,
      rectificationDeadline: workflow.rectificationDeadline,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Step 4 -> 5: Officer submits physical inspection record -> moves to Admin verification
  static Future<WorkflowState> submitOfficerInspectionReport({
    required String complaintId,
    required String officerName,
    String? remarks,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();
    final updatedSteps = workflow.steps.map((s) {
      if (s.step == WorkflowStep.officerInspection) {
        return s.copyWith(
          status: WorkflowStepStatus.completed,
          completedBy: officerName,
          completedAt: now,
          remarks: remarks ?? 'Inspection completed on-site',
        );
      }
      if (s.step == WorkflowStep.adminReportVerification) {
        return s.copyWith(status: WorkflowStepStatus.active);
      }
      return s;
    }).toList();

    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.inProgress,
      currentStep: WorkflowStep.adminReportVerification,
      steps: updatedSteps,
      rectificationDeadline: workflow.rectificationDeadline,
      adminRevisionNotes: null, // clear previous revision notes
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Step 5 -> 6 (If Valid) OR Step 5 -> 4 (If Invalid / Incomplete)
  static Future<WorkflowState> verifyAdminInspectionReport({
    required String complaintId,
    required String adminId,
    required bool isValid,
    String? revisionNotes,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();

    if (isValid) {
      // Valid -> Advance to Step 6 (Unlock Officer Enforcement Action)
      final updatedSteps = workflow.steps.map((s) {
        if (s.step == WorkflowStep.adminReportVerification) {
          return s.copyWith(
            status: WorkflowStepStatus.completed,
            completedBy: adminId,
            completedAt: now,
            remarks: 'Inspection report verified and approved by admin',
          );
        }
        if (s.step == WorkflowStep.officerEnforcementAction) {
          return s.copyWith(status: WorkflowStepStatus.active);
        }
        return s;
      }).toList();

      final updated = WorkflowState(
        workflowId: workflow.workflowId,
        complaintId: complaintId,
        overallStatus: WorkflowOverallStatus.inProgress,
        currentStep: WorkflowStep.officerEnforcementAction,
        steps: updatedSteps,
        rectificationDeadline: workflow.rectificationDeadline,
        adminRevisionNotes: null,
        createdAt: workflow.createdAt,
        updatedAt: now,
      );

      await _persistWorkflow(updated);
      _notifyStateChange(updated);
      return updated;
    } else {
      // Invalid -> Revert Step 4 to active with revision request
      final updatedSteps = workflow.steps.map((s) {
        if (s.step == WorkflowStep.officerInspection) {
          return s.copyWith(
            status: WorkflowStepStatus.active,
            completedAt: null,
            remarks: 'Modifications required: ${revisionNotes ?? "Please update inspection report"}',
          );
        }
        if (s.step == WorkflowStep.adminReportVerification) {
          return s.copyWith(status: WorkflowStepStatus.locked);
        }
        return s;
      }).toList();

      final updated = WorkflowState(
        workflowId: workflow.workflowId,
        complaintId: complaintId,
        overallStatus: WorkflowOverallStatus.inProgress,
        currentStep: WorkflowStep.officerInspection,
        steps: updatedSteps,
        rectificationDeadline: workflow.rectificationDeadline,
        adminRevisionNotes: revisionNotes,
        createdAt: workflow.createdAt,
        updatedAt: now,
      );

      await _persistWorkflow(updated);
      _notifyStateChange(updated);
      return updated;
    }
  }

  /// Step 6: Officer Issues Action (Compliance vs Non-Compliance)
  static Future<WorkflowState> issueOfficerEnforcementAction({
    required String complaintId,
    required String officerName,
    required bool isCompliance,
    double? penaltyAmount,
    String? remarks,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();

    if (isCompliance) {
      // Compliance: Directly unlocks Step 7 (Case Closure)
      final updatedSteps = workflow.steps.map((s) {
        if (s.step == WorkflowStep.officerEnforcementAction) {
          return s.copyWith(
            status: WorkflowStepStatus.completed,
            completedBy: officerName,
            completedAt: now,
            remarks: remarks ?? 'Certificate of Compliance Issued',
          );
        }
        if (s.step == WorkflowStep.caseClosure) {
          return s.copyWith(status: WorkflowStepStatus.active);
        }
        return s;
      }).toList();

      final updated = WorkflowState(
        workflowId: workflow.workflowId,
        complaintId: complaintId,
        overallStatus: WorkflowOverallStatus.inProgress,
        currentStep: WorkflowStep.caseClosure,
        steps: updatedSteps,
        enforcementOutcome: 'compliance',
        isScoreLocked: false,
        createdAt: workflow.createdAt,
        updatedAt: now,
      );

      await _persistWorkflow(updated);
      _notifyStateChange(updated);
      return updated;
    } else {
      // Non-Compliance: Demerit score LOCKED, 7-day payment timer starts
      final paymentDeadline = now.add(const Duration(days: 7));
      final updatedSteps = workflow.steps.map((s) {
        if (s.step == WorkflowStep.officerEnforcementAction) {
          return s.copyWith(
            status: WorkflowStepStatus.completed,
            completedBy: officerName,
            completedAt: now,
            remarks: remarks ?? 'Notice of Non-Compliance Issued (RM ${(penaltyAmount ?? 250).toStringAsFixed(2)})',
          );
        }
        return s;
      }).toList();

      final updated = WorkflowState(
        workflowId: workflow.workflowId,
        complaintId: complaintId,
        overallStatus: WorkflowOverallStatus.inProgress,
        currentStep: WorkflowStep.caseClosure,
        steps: updatedSteps,
        enforcementOutcome: 'non_compliance',
        isScoreLocked: true, // Demerit score permanently locked!
        paymentDeadline: paymentDeadline,
        createdAt: workflow.createdAt,
        updatedAt: now,
      );

      await _persistWorkflow(updated);
      _notifyStateChange(updated);
      return updated;
    }
  }

  /// Step 6 (Non-Compliance Sub-path): Owner settles penalty fine -> unlocks Step 7 (Case Closure)
  static Future<WorkflowState> recordPenaltyPayment({
    required String complaintId,
    required String paymentRef,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();
    final updatedSteps = workflow.steps.map((s) {
      if (s.step == WorkflowStep.caseClosure) {
        return s.copyWith(status: WorkflowStepStatus.active);
      }
      return s;
    }).toList();

    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.inProgress,
      currentStep: WorkflowStep.caseClosure,
      steps: updatedSteps,
      enforcementOutcome: workflow.enforcementOutcome,
      isScoreLocked: true, // score remains locked even after payment!
      paymentDeadline: workflow.paymentDeadline,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Step 7: Officer closes case -> overallStatus = completed (Resolved)
  static Future<WorkflowState> closeWorkflowCase({
    required String complaintId,
    required String officerName,
    String? remarks,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();
    final updatedSteps = workflow.steps.map((s) {
      if (s.step == WorkflowStep.caseClosure) {
        return s.copyWith(
          status: WorkflowStepStatus.completed,
          completedBy: officerName,
          completedAt: now,
          remarks: remarks ?? 'Case officially closed and archived',
        );
      }
      return s;
    }).toList();

    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.completed,
      currentStep: WorkflowStep.caseClosure,
      steps: updatedSteps,
      enforcementOutcome: workflow.enforcementOutcome,
      isScoreLocked: workflow.isScoreLocked,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Overdue penalty auto-closure after 7 days
  static Future<WorkflowState> autoCloseOverduePenalty({
    required String complaintId,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) throw Exception('Workflow not found');

    final now = DateTime.now().toUtc();
    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: complaintId,
      overallStatus: WorkflowOverallStatus.closedUnpaid,
      currentStep: WorkflowStep.caseClosure,
      steps: workflow.steps,
      enforcementOutcome: workflow.enforcementOutcome,
      isScoreLocked: true,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );

    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Mark workflow as rejected (e.g. Admin rejects fake complaint)
  static Future<WorkflowState?> rejectWorkflow({
    required String complaintId,
    required String rejectedBy,
    String? reason,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) return null;
    
    final now = DateTime.now().toUtc();
    final updated = WorkflowState(
      workflowId: workflow.workflowId,
      complaintId: workflow.complaintId,
      overallStatus: WorkflowOverallStatus.rejected,
      currentStep: workflow.currentStep,
      steps: workflow.steps,
      createdAt: workflow.createdAt,
      updatedAt: now,
    );
    
    await _persistWorkflow(updated);
    _notifyStateChange(updated);
    return updated;
  }

  /// Validate if a step can be performed by the current user role
  static Future<WorkflowValidationResult> canPerformStep({
    required String complaintId,
    required WorkflowStep requestedStep,
    required UserRole userRole,
  }) async {
    final workflow = await loadWorkflow(complaintId);
    if (workflow == null) {
      return WorkflowValidationResult.invalid(
        'Workflow not found for this complaint',
        WorkflowStep.customerSubmission,
      );
    }
    
    if (workflow.overallStatus == WorkflowOverallStatus.completed) {
      return WorkflowValidationResult.invalid(
        'This workflow has already been completed',
        workflow.currentStep,
      );
    }
    
    if (workflow.overallStatus == WorkflowOverallStatus.rejected) {
      return WorkflowValidationResult.invalid(
        'This workflow has been rejected',
        workflow.currentStep,
      );
    }
    
    if (requestedStep != workflow.currentStep) {
      if (requestedStep.order < workflow.currentStep.order) {
        return WorkflowValidationResult.invalid(
          'This step has already been completed',
          workflow.currentStep,
        );
      }
      return WorkflowValidationResult.invalid(
        'Please complete the previous step first. Current step: ${workflow.currentStep.displayName}',
        workflow.currentStep,
      );
    }
    
    if (userRole != requestedStep.requiredRole) {
      return WorkflowValidationResult.invalid(
        'You are not authorized to perform this step. Required role: ${requestedStep.requiredRole.name}',
        workflow.currentStep,
      );
    }
    
    return WorkflowValidationResult.valid(workflow.currentStep);
  }

  static Future<void> _persistWorkflow(WorkflowState workflow) async {
    _localCache[workflow.complaintId] = workflow;
    await _cacheLocally(workflow);
    
    try {
      final supabase = SupabaseService.client;
      
      await supabase.from(_workflowTable).upsert({
        'workflow_id': workflow.workflowId,
        'complaint_id': workflow.complaintId,
        'overall_status': workflow.overallStatus.name,
        'current_step': workflow.currentStep.name,
        'rectification_deadline': workflow.rectificationDeadline?.toIso8601String(),
        'payment_deadline': workflow.paymentDeadline?.toIso8601String(),
        'is_score_locked': workflow.isScoreLocked,
        'enforcement_outcome': workflow.enforcementOutcome,
        'admin_revision_notes': workflow.adminRevisionNotes,
        'created_at': workflow.createdAt.toIso8601String(),
        'updated_at': workflow.updatedAt?.toIso8601String(),
      }, onConflict: 'complaint_id');
      
      for (int i = 0; i < workflow.steps.length; i++) {
        final step = workflow.steps[i];
        final stepMap = step.toMap();
        stepMap['workflow_id'] = workflow.workflowId;
        stepMap['step_order'] = i + 1;
        stepMap['required_role'] = step.step.requiredRole.name;
        
        await supabase.from(_workflowStepsTable).upsert(
          stepMap,
          onConflict: 'workflow_id,step_id',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WorkflowService] Supabase persist error: $e');
      }
    }
  }

  static Future<void> _cacheLocally(WorkflowState workflow) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = workflow.toMap();
      map['steps'] = workflow.steps.map((s) => s.toMap()).toList();
      await prefs.setString('$_localCachePrefix${workflow.complaintId}', jsonEncode(map));
    } catch (_) {}
  }

  static void _notifyStateChange(WorkflowState workflow) {
    if (!_stateController.isClosed) {
      _stateController.add(workflow);
    }
  }

  static void dispose() {
    _stateController.close();
  }
}
