class RectificationModel {
  final String restaurantId;
  final String restaurantName;
  final String? complaintId;
  final String? inspectionId;
  final String? noticeId;
  final String notes;
  final List<String> photoUrls;
  final DateTime submittedAt;
  final bool isAdminVerified;
  final DateTime? adminVerifiedAt;
  final String? adminNotes;
  final bool isOfficerClosed;
  final DateTime? officerClosedAt;
  final String? officerRemarks;

  const RectificationModel({
    required this.restaurantId,
    required this.restaurantName,
    this.complaintId,
    this.inspectionId,
    this.noticeId,
    required this.notes,
    required this.photoUrls,
    required this.submittedAt,
    this.isAdminVerified = false,
    this.adminVerifiedAt,
    this.adminNotes,
    this.isOfficerClosed = false,
    this.officerClosedAt,
    this.officerRemarks,
  });

  Map<String, dynamic> toMap() {
    return {
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'complaintId': complaintId,
      'inspectionId': inspectionId,
      'noticeId': noticeId,
      'notes': notes,
      'photoUrls': photoUrls,
      'submittedAt': submittedAt.toIso8601String(),
      'isAdminVerified': isAdminVerified,
      'adminVerifiedAt': adminVerifiedAt?.toIso8601String(),
      'adminNotes': adminNotes,
      'isOfficerClosed': isOfficerClosed,
      'officerClosedAt': officerClosedAt?.toIso8601String(),
      'officerRemarks': officerRemarks,
    };
  }

  factory RectificationModel.fromMap(Map<String, dynamic> map) {
    return RectificationModel(
      restaurantId: map['restaurantId']?.toString() ?? '',
      restaurantName: map['restaurantName']?.toString() ?? '',
      complaintId: map['complaintId']?.toString(),
      inspectionId: map['inspectionId']?.toString(),
      noticeId: map['noticeId']?.toString(),
      notes: map['notes']?.toString() ?? '',
      photoUrls: List<String>.from(map['photoUrls'] ?? []),
      submittedAt: DateTime.tryParse(map['submittedAt']?.toString() ?? '') ?? DateTime.now(),
      isAdminVerified: map['isAdminVerified'] == true,
      adminVerifiedAt: map['adminVerifiedAt'] != null ? DateTime.tryParse(map['adminVerifiedAt'].toString()) : null,
      adminNotes: map['adminNotes']?.toString(),
      isOfficerClosed: map['isOfficerClosed'] == true,
      officerClosedAt: map['officerClosedAt'] != null ? DateTime.tryParse(map['officerClosedAt'].toString()) : null,
      officerRemarks: map['officerRemarks']?.toString(),
    );
  }

  RectificationModel copyWith({
    String? notes,
    List<String>? photoUrls,
    bool? isAdminVerified,
    DateTime? adminVerifiedAt,
    String? adminNotes,
    bool? isOfficerClosed,
    DateTime? officerClosedAt,
    String? officerRemarks,
  }) {
    return RectificationModel(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      complaintId: complaintId,
      inspectionId: inspectionId,
      noticeId: noticeId,
      notes: notes ?? this.notes,
      photoUrls: photoUrls ?? this.photoUrls,
      submittedAt: submittedAt,
      isAdminVerified: isAdminVerified ?? this.isAdminVerified,
      adminVerifiedAt: adminVerifiedAt ?? this.adminVerifiedAt,
      adminNotes: adminNotes ?? this.adminNotes,
      isOfficerClosed: isOfficerClosed ?? this.isOfficerClosed,
      officerClosedAt: officerClosedAt ?? this.officerClosedAt,
      officerRemarks: officerRemarks ?? this.officerRemarks,
    );
  }
}
