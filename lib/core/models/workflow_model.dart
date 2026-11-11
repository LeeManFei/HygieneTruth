import '../models/user_model.dart';

enum WorkflowStep {
  customerSubmission,        // 1. Customer submits complaint (User)
  adminDuplicationReview,    // 2. Admin duplicate check & manual approval (Admin)
  ownerRectificationPeriod,  // 3. 7-Day owner countdown for evidence submission (Owner / Timer)
  officerInspection,         // 4. Officer review, schedule & conduct on-site inspection (Government)
  adminReportVerification,   // 5. Admin verifies inspection report validity (Admin)
  officerEnforcementAction,  // 6. Officer issues Compliance or Non-Compliance (Government)
  caseClosure,               // 7. Case officially closed & archived (Government)
}

enum WorkflowStepStatus {
  locked,
  active,
  completed,
}

enum WorkflowOverallStatus {
  inProgress,
  completed,
  rejected,
  closedUnpaid,
}

class WorkflowStepState {
  final WorkflowStep step;
  final WorkflowStepStatus status;
  final String? completedBy;
  final DateTime? completedAt;
  final String? remarks;

  const WorkflowStepState({
    required this.step,
    required this.status,
    this.completedBy,
    this.completedAt,
    this.remarks,
  });

  factory WorkflowStepState.fromMap(Map<String, dynamic> map) {
    final stepId = map['step_id']?.toString() ?? '';
    WorkflowStep step;
    switch (stepId) {
      case 'customerSubmission':
        step = WorkflowStep.customerSubmission;
        break;
      case 'adminInitialReview':
      case 'adminDuplicationReview':
        step = WorkflowStep.adminDuplicationReview;
        break;
      case 'ownerRectificationPeriod':
      case 'ownerEvidencePeriod':
        step = WorkflowStep.ownerRectificationPeriod;
        break;
      case 'officerInspection':
        step = WorkflowStep.officerInspection;
        break;
      case 'adminReportVerification':
      case 'adminFinalApproval':
        step = WorkflowStep.adminReportVerification;
        break;
      case 'officerEnforcementAction':
        step = WorkflowStep.officerEnforcementAction;
        break;
      case 'caseClosure':
        step = WorkflowStep.caseClosure;
        break;
      default:
        step = WorkflowStep.customerSubmission;
    }

    return WorkflowStepState(
      step: step,
      status: WorkflowStepStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => WorkflowStepStatus.locked,
      ),
      completedBy: map['completed_by']?.toString(),
      completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'].toString()) : null,
      remarks: map['remarks']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'step_id': step.name,
      'status': status.name,
      'completed_by': completedBy,
      'completed_at': completedAt?.toIso8601String(),
      'remarks': remarks,
    };
  }

  WorkflowStepState copyWith({
    WorkflowStepStatus? status,
    String? completedBy,
    DateTime? completedAt,
    String? remarks,
  }) {
    return WorkflowStepState(
      step: step,
      status: status ?? this.status,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
      remarks: remarks ?? this.remarks,
    );
  }
}

class WorkflowState {
  final String workflowId;
  final String complaintId;
  final WorkflowOverallStatus overallStatus;
  final WorkflowStep currentStep;
  final List<WorkflowStepState> steps;
  final DateTime? rectificationDeadline; // 7-day countdown from admin forwarding
  final DateTime? paymentDeadline;       // 7-day payment window for non-compliance fines
  final bool isScoreLocked;              // Permanent score lock on non-compliance
  final String? enforcementOutcome;      // 'compliance' | 'non_compliance'
  final String? adminRevisionNotes;      // Rejection notes if admin requests inspection modifications
  final DateTime createdAt;
  final DateTime? updatedAt;

  const WorkflowState({
    required this.workflowId,
    required this.complaintId,
    required this.overallStatus,
    required this.currentStep,
    required this.steps,
    this.rectificationDeadline,
    this.paymentDeadline,
    this.isScoreLocked = false,
    this.enforcementOutcome,
    this.adminRevisionNotes,
    required this.createdAt,
    this.updatedAt,
  });

  factory WorkflowState.fromMap(Map<String, dynamic> map, List<Map<String, dynamic>> stepsMap) {
    final steps = stepsMap.map((s) => WorkflowStepState.fromMap(s)).toList();
    final currentStep = steps.firstWhere(
      (s) => s.status != WorkflowStepStatus.completed,
      orElse: () => steps.isNotEmpty ? steps.last : const WorkflowStepState(step: WorkflowStep.customerSubmission, status: WorkflowStepStatus.active),
    ).step;

    return WorkflowState(
      workflowId: map['workflow_id']?.toString() ?? '',
      complaintId: map['complaint_id']?.toString() ?? '',
      overallStatus: WorkflowOverallStatus.values.firstWhere(
        (e) => e.name == map['overall_status'],
        orElse: () => WorkflowOverallStatus.inProgress,
      ),
      currentStep: currentStep,
      steps: steps,
      rectificationDeadline: map['rectification_deadline'] != null
          ? DateTime.tryParse(map['rectification_deadline'].toString())
          : null,
      paymentDeadline: map['payment_deadline'] != null
          ? DateTime.tryParse(map['payment_deadline'].toString())
          : null,
      isScoreLocked: map['is_score_locked'] == true,
      enforcementOutcome: map['enforcement_outcome']?.toString(),
      adminRevisionNotes: map['admin_revision_notes']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workflow_id': workflowId,
      'complaint_id': complaintId,
      'overall_status': overallStatus.name,
      'current_step': currentStep.name,
      'rectification_deadline': rectificationDeadline?.toIso8601String(),
      'payment_deadline': paymentDeadline?.toIso8601String(),
      'is_score_locked': isScoreLocked,
      'enforcement_outcome': enforcementOutcome,
      'admin_revision_notes': adminRevisionNotes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  WorkflowStepState? getStepState(WorkflowStep step) {
    try {
      return steps.firstWhere((s) => s.step == step);
    } catch (_) {
      return null;
    }
  }

  bool isStepCompleted(WorkflowStep step) {
    final state = getStepState(step);
    return state?.status == WorkflowStepStatus.completed;
  }

  bool isStepActive(WorkflowStep step) {
    final state = getStepState(step);
    return state?.status == WorkflowStepStatus.active;
  }

  bool isStepLocked(WorkflowStep step) {
    final state = getStepState(step);
    return state?.status == WorkflowStepStatus.locked;
  }

  List<WorkflowStep> get completedSteps =>
      steps.where((s) => s.status == WorkflowStepStatus.completed).map((s) => s.step).toList();

  List<WorkflowStep> get pendingSteps =>
      steps.where((s) => s.status != WorkflowStepStatus.completed).map((s) => s.step).toList();

  // Convenience Helpers
  bool get isOwnerRectificationActive => isStepActive(WorkflowStep.ownerRectificationPeriod);
  bool get isOfficerReviewPending => isStepActive(WorkflowStep.officerInspection);
  bool get isAdminReportReviewPending => isStepActive(WorkflowStep.adminReportVerification);
  bool get isEnforcementReady => isStepActive(WorkflowStep.officerEnforcementAction);
  bool get isCaseClosureReady => isStepActive(WorkflowStep.caseClosure);
  bool get isPaymentPending =>
      enforcementOutcome == 'non_compliance' &&
      isStepActive(WorkflowStep.caseClosure) == false &&
      overallStatus == WorkflowOverallStatus.inProgress;
}

class WorkflowValidationResult {
  final bool isValid;
  final String? errorMessage;
  final WorkflowStep? currentStep;

  const WorkflowValidationResult({
    required this.isValid,
    this.errorMessage,
    this.currentStep,
  });

  static WorkflowValidationResult valid(WorkflowStep currentStep) =>
      WorkflowValidationResult(isValid: true, currentStep: currentStep);

  static WorkflowValidationResult invalid(String message, WorkflowStep currentStep) =>
      WorkflowValidationResult(isValid: false, errorMessage: message, currentStep: currentStep);
}

extension WorkflowStepExtension on WorkflowStep {
  int get order {
    switch (this) {
      case WorkflowStep.customerSubmission:
        return 1;
      case WorkflowStep.adminDuplicationReview:
        return 2;
      case WorkflowStep.ownerRectificationPeriod:
        return 3;
      case WorkflowStep.officerInspection:
        return 4;
      case WorkflowStep.adminReportVerification:
        return 5;
      case WorkflowStep.officerEnforcementAction:
        return 6;
      case WorkflowStep.caseClosure:
        return 7;
    }
  }

  UserRole get requiredRole {
    switch (this) {
      case WorkflowStep.customerSubmission:
        return UserRole.user;
      case WorkflowStep.adminDuplicationReview:
        return UserRole.admin;
      case WorkflowStep.ownerRectificationPeriod:
        return UserRole.owner;
      case WorkflowStep.officerInspection:
        return UserRole.government;
      case WorkflowStep.adminReportVerification:
        return UserRole.admin;
      case WorkflowStep.officerEnforcementAction:
        return UserRole.government;
      case WorkflowStep.caseClosure:
        return UserRole.government;
    }
  }

  String get displayName {
    switch (this) {
      case WorkflowStep.customerSubmission:
        return 'Customer Submission';
      case WorkflowStep.adminDuplicationReview:
        return 'Admin Duplication Review';
      case WorkflowStep.ownerRectificationPeriod:
        return '7-Day Owner Rectification';
      case WorkflowStep.officerInspection:
        return 'Officer Inspection & Schedule';
      case WorkflowStep.adminReportVerification:
        return 'Admin Report Verification';
      case WorkflowStep.officerEnforcementAction:
        return 'Enforcement Action';
      case WorkflowStep.caseClosure:
        return 'Statutory Case Closure';
    }
  }

  String get shortName {
    switch (this) {
      case WorkflowStep.customerSubmission:
        return 'Submission';
      case WorkflowStep.adminDuplicationReview:
        return 'Admin Review';
      case WorkflowStep.ownerRectificationPeriod:
        return 'Rectification';
      case WorkflowStep.officerInspection:
        return 'Inspection';
      case WorkflowStep.adminReportVerification:
        return 'Report Review';
      case WorkflowStep.officerEnforcementAction:
        return 'Action';
      case WorkflowStep.caseClosure:
        return 'Closure';
    }
  }

  WorkflowStep? get nextStep {
    final values = WorkflowStep.values;
    final index = values.indexOf(this);
    if (index < values.length - 1) {
      return values[index + 1];
    }
    return null;
  }

  List<WorkflowStep> get previousSteps => WorkflowStep.values.where((s) => s.order < order).toList();
}
