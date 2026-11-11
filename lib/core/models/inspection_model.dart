enum InspectionOutcome { pending, compliant, nonCompliant }

enum EnforcementType { warning, fine, closure, none }

enum EnforcementStatus { pending, inProgress, completed }

class InspectionModel {
  static const String rescheduleRequiredPrefix = 'RESCHEDULE_REQUIRED:';
  final String id;
  final String complaintId;
  final String restaurantId;
  final String restaurantName;
  final String scheduledDate;
  final String? conductedDate;
  final String officerName;
  final InspectionOutcome outcome;
  final String findings;
  final EnforcementType recommendedAction;
  final EnforcementType issuedAction;
  final String justification;
  final double fineAmount;
  final EnforcementStatus enforcementStatus;
  final String? statutoryCitation;
  final String? issuedDate;
  final String? dueDate;
  final bool isFinePaid;
  final String? paidAt;
  final List<String> photoUrls;
  final bool isAdminApproved;
  final String? adminReviewNotes;

  bool get requiresReschedule =>
      adminReviewNotes?.startsWith(rescheduleRequiredPrefix) == true;

  const InspectionModel({
    required this.id,
    required this.complaintId,
    required this.restaurantId,
    required this.restaurantName,
    required this.scheduledDate,
    this.conductedDate,
    required this.officerName,
    required this.outcome,
    required this.findings,
    required this.recommendedAction,
    required this.issuedAction,
    required this.justification,
    required this.fineAmount,
    required this.enforcementStatus,
    this.statutoryCitation,
    this.issuedDate,
    this.dueDate,
    this.isFinePaid = false,
    this.paidAt,
    this.photoUrls = const [],
    this.isAdminApproved = false,
    this.adminReviewNotes,
  });

  factory InspectionModel.fromMap(Map<String, dynamic> map) {
    final double fineAmt = (map['fine_amount'] as num?)?.toDouble() ??
        (map['fineAmount'] as num?)?.toDouble() ??
        0.0;
    final paidAt = DateTime.tryParse((map['paid_at'] ?? map['paidAt'] ?? '').toString());
    final issuedAt = DateTime.tryParse((map['issued_date'] ?? map['issuedDate'] ?? '').toString());
    final bool finePaid = (map['is_fine_paid'] == true || map['isFinePaid'] == true) &&
        (fineAmt <= 0 || (paidAt != null && (issuedAt == null || !paidAt.isBefore(issuedAt))));

    List<String> parsedPhotos = [];
    if (map['photo_urls'] is List && (map['photo_urls'] as List).isNotEmpty) {
      parsedPhotos = (map['photo_urls'] as List).map((e) => e.toString()).toList();
    } else if (map['evidence_photos'] is List) {
      for (final item in map['evidence_photos']) {
        if (item is Map && item['photo_url'] != null) {
          parsedPhotos.add(item['photo_url'].toString());
        } else if (item != null) {
          parsedPhotos.add(item.toString());
        }
      }
    } else if (map['photo_urls'] is List) {
      parsedPhotos = (map['photo_urls'] as List).map((e) => e.toString()).toList();
    } else if (map['photos'] is List) {
      parsedPhotos = (map['photos'] as List).map((e) => e.toString()).toList();
    } else if (map['photoUrls'] is List) {
      parsedPhotos = (map['photoUrls'] as List).map((e) => e.toString()).toList();
    }

    final bool adminApproved = map['is_admin_approved'] == true ||
        map['isAdminApproved'] == true ||
        (map['enforcement_status'] == 'enforced' || map['enforcement_status'] == 'completed' || map['enforcementStatus'] == 'completed') ||
        (map['issued_date'] != null && map['issued_date'].toString().isNotEmpty && map['issued_date'] != 'null');

    return InspectionModel(
      id: map['id']?.toString() ?? '',
      complaintId: map['complaint_id']?.toString() ?? map['complaintId']?.toString() ?? '',
      restaurantId: map['restaurant_id']?.toString() ?? map['restaurantId']?.toString() ?? '',
      restaurantName: map['restaurant_name']?.toString() ?? map['restaurantName']?.toString() ?? 'Premises',
      scheduledDate: map['scheduled_date']?.toString() ?? map['scheduledDate']?.toString() ?? '',
      conductedDate: map['conducted_date']?.toString() ?? map['conductedDate']?.toString(),
      officerName: map['officer_name']?.toString() ?? map['officerName']?.toString() ?? 'Health Officer',
      outcome: InspectionOutcome.values.firstWhere(
        (e) => e.name.toLowerCase() == (map['outcome'] ?? '').toString().toLowerCase(),
        orElse: () => InspectionOutcome.pending,
      ),
      findings: map['findings']?.toString() ?? '',
      recommendedAction: EnforcementType.values.firstWhere(
        (e) => e.name.toLowerCase() == (map['recommended_action'] ?? map['recommendedAction'] ?? '').toString().toLowerCase(),
        orElse: () => EnforcementType.warning,
      ),
      issuedAction: EnforcementType.values.firstWhere(
        (e) => e.name.toLowerCase() == (map['issued_action'] ?? map['issuedAction'] ?? '').toString().toLowerCase(),
        orElse: () => EnforcementType.warning,
      ),
      justification: map['justification']?.toString() ?? '',
      fineAmount: fineAmt,
      enforcementStatus: map['enforcement_status'] == 'enforced'
          ? EnforcementStatus.completed
          : EnforcementStatus.values.firstWhere(
        (e) => e.name.toLowerCase() == (map['enforcement_status'] ?? map['enforcementStatus'] ?? '').toString().toLowerCase(),
        orElse: () => EnforcementStatus.pending,
      ),
      statutoryCitation: map['statutory_citation']?.toString() ?? map['statutoryCitation']?.toString(),
      issuedDate: map['issued_date']?.toString() ?? map['issuedDate']?.toString(),
      dueDate: map['due_date']?.toString() ?? map['dueDate']?.toString(),
      isFinePaid: finePaid,
      paidAt: map['paid_at']?.toString() ?? map['paidAt']?.toString(),
      photoUrls: parsedPhotos,
      isAdminApproved: adminApproved,
      adminReviewNotes: map['admin_review_notes']?.toString() ?? map['adminReviewNotes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'complaint_id': complaintId,
      'restaurant_id': restaurantId,
      'restaurant_name': restaurantName,
      'scheduled_date': scheduledDate,
      'conducted_date': conductedDate,
      'officer_name': officerName,
      'outcome': outcome.name,
      'findings': findings,
      'recommended_action': recommendedAction.name,
      'issued_action': issuedAction.name,
      'justification': justification,
      'fine_amount': fineAmount,
      'enforcement_status': enforcementStatus.name,
      'statutory_citation': statutoryCitation,
      'issued_date': issuedDate,
      'due_date': dueDate,
      'is_fine_paid': isFinePaid,
      'paid_at': paidAt,
      'photo_urls': photoUrls,
      'is_admin_approved': isAdminApproved,
      'admin_review_notes': adminReviewNotes,
    };
  }

  InspectionModel copyWith({
    String? id,
    String? complaintId,
    String? restaurantId,
    String? restaurantName,
    String? scheduledDate,
    String? conductedDate,
    String? officerName,
    InspectionOutcome? outcome,
    String? findings,
    EnforcementType? recommendedAction,
    EnforcementType? issuedAction,
    String? justification,
    double? fineAmount,
    EnforcementStatus? enforcementStatus,
    String? statutoryCitation,
    String? issuedDate,
    String? dueDate,
    bool? isFinePaid,
    String? paidAt,
    List<String>? photoUrls,
    bool? isAdminApproved,
    String? adminReviewNotes,
  }) {
    return InspectionModel(
      id: id ?? this.id,
      complaintId: complaintId ?? this.complaintId,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      conductedDate: conductedDate ?? this.conductedDate,
      officerName: officerName ?? this.officerName,
      outcome: outcome ?? this.outcome,
      findings: findings ?? this.findings,
      recommendedAction: recommendedAction ?? this.recommendedAction,
      issuedAction: issuedAction ?? this.issuedAction,
      justification: justification ?? this.justification,
      fineAmount: fineAmount ?? this.fineAmount,
      enforcementStatus: enforcementStatus ?? this.enforcementStatus,
      statutoryCitation: statutoryCitation ?? this.statutoryCitation,
      issuedDate: issuedDate ?? this.issuedDate,
      dueDate: dueDate ?? this.dueDate,
      isFinePaid: isFinePaid ?? this.isFinePaid,
      paidAt: paidAt ?? this.paidAt,
      photoUrls: photoUrls ?? this.photoUrls,
      isAdminApproved: isAdminApproved ?? this.isAdminApproved,
      adminReviewNotes: adminReviewNotes ?? this.adminReviewNotes,
    );
  }
}
