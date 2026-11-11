enum ComplaintStatus {
  submitted,
  underReview,
  investigating,
  inspecting,
  pendingInspection,
  resolved,
  rejected,
}

enum SeverityLevel { low, medium, high }

class ComplaintModel {
  final Map<String, dynamic> evidenceContext;
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String userId;
  final String userName;
  final String category;
  final List<String> issues;
  final String description;
  final ComplaintStatus status;
  final SeverityLevel severity;
  final double latitude;
  final double longitude;
  final bool isFlaggedForReview;
  final String? flaggedReason;
  final String submittedAt;
  final List<String> photoUrls;

  const ComplaintModel({
    this.evidenceContext = const {},
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.userId,
    required this.userName,
    required this.category,
    required this.issues,
    required this.description,
    required this.status,
    required this.severity,
    required this.latitude,
    required this.longitude,
    this.isFlaggedForReview = false,
    this.flaggedReason,
    required this.submittedAt,
    required this.photoUrls,
  });

  factory ComplaintModel.fromJson(Map<String, dynamic> json) {
    ComplaintStatus parsedStatus = ComplaintStatus.submitted;
    final statusStr = (json['status'] ?? '').toString().toLowerCase();
    if (statusStr == 'underreview' || statusStr == 'under_review') {
      parsedStatus = ComplaintStatus.underReview;
    } else if (statusStr == 'investigating') {
      parsedStatus = ComplaintStatus.investigating;
    } else if (statusStr == 'inspecting') {
      parsedStatus = ComplaintStatus.inspecting;
    } else if (statusStr == 'pendinginspection' || statusStr == 'pending_inspection') {
      parsedStatus = ComplaintStatus.pendingInspection;
    } else if (statusStr == 'resolved') {
      parsedStatus = ComplaintStatus.resolved;
    } else if (statusStr == 'rejected') {
      parsedStatus = ComplaintStatus.rejected;
    }

    SeverityLevel parsedSeverity = SeverityLevel.medium;
    final sevStr = (json['severity'] ?? '').toString().toLowerCase();
    if (sevStr == 'high') {
      parsedSeverity = SeverityLevel.high;
    } else if (sevStr == 'low') {
      parsedSeverity = SeverityLevel.low;
    }

    List<String> parsedIssues = [];
    if (json['complaint_issues'] is List) {
      for (final item in json['complaint_issues']) {
        if (item is Map && item['issue_text'] != null) {
          parsedIssues.add(item['issue_text'].toString());
        } else if (item != null) {
          parsedIssues.add(item.toString());
        }
      }
    } else if (json['issues'] is List) {
      parsedIssues = (json['issues'] as List).map((e) => e.toString()).toList();
    }

    List<String> parsedPhotos = [];
    if (json['complaint_photos'] is List) {
      for (final item in json['complaint_photos']) {
        if (item is Map && item['photo_url'] != null) {
          parsedPhotos.add(item['photo_url'].toString());
        } else if (item != null) {
          parsedPhotos.add(item.toString());
        }
      }
    } else if (json['photo_urls'] is List) {
      parsedPhotos = (json['photo_urls'] as List).map((e) => e.toString()).toList();
    } else if (json['photos'] is List) {
      parsedPhotos = (json['photos'] as List).map((e) => e.toString()).toList();
    }

    String rName = 'Outlet';
    if (json['restaurants'] is Map && json['restaurants']['name'] != null) {
      rName = json['restaurants']['name'].toString();
    } else if (json['restaurant_name'] != null) {
      rName = json['restaurant_name'].toString();
    } else if (json['restaurantName'] != null) {
      rName = json['restaurantName'].toString();
    }

    String uName = 'Citizen Diner';
    if (json['users'] is Map && json['users']['name'] != null) {
      uName = json['users']['name'].toString();
    } else if (json['user_name'] != null) {
      uName = json['user_name'].toString();
    } else if (json['userName'] != null) {
      uName = json['userName'].toString();
    }

    return ComplaintModel(
      evidenceContext: Map<String, dynamic>.from(json['evidence_context'] is Map ? json['evidence_context'] : const {}),
      id: json['id']?.toString() ?? '',
      restaurantId: json['restaurant_id']?.toString() ?? json['restaurantId']?.toString() ?? '',
      restaurantName: rName,
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: uName,
      category: json['category']?.toString() ?? 'Hygiene Issue',
      issues: parsedIssues,
      description: json['description']?.toString() ?? '',
      status: parsedStatus,
      severity: parsedSeverity,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 3.1466,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 101.6958,
      isFlaggedForReview: json['is_flagged_for_review'] == true || json['isFlaggedForReview'] == true,
      flaggedReason: json['flagged_reason']?.toString() ?? json['flaggedReason']?.toString(),
      submittedAt: json['submitted_at']?.toString() ?? json['submittedAt']?.toString() ?? json['created_at']?.toString() ?? '',
      photoUrls: parsedPhotos,
    );
  }

  factory ComplaintModel.fromMap(Map<String, dynamic> map) => ComplaintModel.fromJson(map);

  Map<String, dynamic> toMap() => toJson();

  ComplaintModel copyWith({
    Map<String, dynamic>? evidenceContext,
    String? id,
    String? restaurantId,
    String? restaurantName,
    String? userId,
    String? userName,
    String? category,
    List<String>? issues,
    String? description,
    ComplaintStatus? status,
    SeverityLevel? severity,
    double? latitude,
    double? longitude,
    bool? isFlaggedForReview,
    String? flaggedReason,
    String? submittedAt,
    List<String>? photoUrls,
  }) {
    return ComplaintModel(
      evidenceContext: evidenceContext ?? this.evidenceContext,
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      category: category ?? this.category,
      issues: issues ?? this.issues,
      description: description ?? this.description,
      status: status ?? this.status,
      severity: severity ?? this.severity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isFlaggedForReview: isFlaggedForReview ?? this.isFlaggedForReview,
      flaggedReason: flaggedReason ?? this.flaggedReason,
      submittedAt: submittedAt ?? this.submittedAt,
      photoUrls: photoUrls ?? this.photoUrls,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'evidence_context': evidenceContext,
      'id': id,
      'restaurant_id': restaurantId,
      'restaurant_name': restaurantName,
      'user_id': userId,
      'user_name': userName,
      'category': category,
      'issues': issues,
      'description': description,
      'status': status.name,
      'severity': severity.name,
      'latitude': latitude,
      'longitude': longitude,
      'is_flagged_for_review': isFlaggedForReview,
      'flagged_reason': flaggedReason,
      'submitted_at': submittedAt,
      'photo_urls': photoUrls,
    };
  }
}
