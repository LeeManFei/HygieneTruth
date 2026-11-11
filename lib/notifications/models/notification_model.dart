import 'dart:convert';

enum NotificationType {
  complaint,
  outlet,
  review,
  hygieneAlert,
  system,
}

class AppNotificationModel {
  final String id;
  final String userId;
  final String title;
  final String message;
  final NotificationType type;
  final String? actionUrl;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    this.actionUrl,
    this.data = const {},
    this.isRead = false,
    required this.createdAt,
  });

  AppNotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? message,
    NotificationType? type,
    String? actionUrl,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppNotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      actionUrl: actionUrl ?? this.actionUrl,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AppNotificationModel.fromMap(Map<String, dynamic> map) {
    NotificationType nType = NotificationType.system;
    final String typeStr = (map['type'] ?? 'system').toString().toLowerCase();
    if (typeStr.contains('complaint')) {
      nType = NotificationType.complaint;
    } else if (typeStr.contains('outlet') || typeStr.contains('restaurant')) {
      nType = NotificationType.outlet;
    } else if (typeStr.contains('review')) {
      nType = NotificationType.review;
    } else if (typeStr.contains('alert') || typeStr.contains('hygiene') || typeStr.contains('outbreak')) {
      nType = NotificationType.hygieneAlert;
    }

    Map<String, dynamic> parsedData = {};
    if (map['data'] is Map) {
      parsedData = Map<String, dynamic>.from(map['data'] as Map);
    } else if (map['data'] is String && (map['data'] as String).isNotEmpty) {
      try {
        parsedData = Map<String, dynamic>.from(jsonDecode(map['data'] as String) as Map);
      } catch (_) {}
    }

    DateTime parsedCreated = DateTime.now();
    if (map['created_at'] != null) {
      parsedCreated = DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now();
    } else if (map['timestamp'] != null) {
      parsedCreated = DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now();
    }

    return AppNotificationModel(
      id: map['id']?.toString() ?? 'notif_${DateTime.now().millisecondsSinceEpoch}',
      userId: map['user_id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Notification',
      message: map['message']?.toString() ?? '',
      type: nType,
      actionUrl: map['action_url']?.toString(),
      data: parsedData,
      isRead: map['is_read'] == true || map['is_read'] == 'true' || map['is_read'] == 1,
      createdAt: parsedCreated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type.name,
      'action_url': actionUrl,
      'data': data,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
