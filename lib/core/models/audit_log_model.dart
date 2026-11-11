import 'package:flutter/material.dart';

class AuditLogModel {
  final String id;
  final String userId;
  final String userEmail;
  final String actionType; // e.g. LOGIN, LOGOUT, NAME_CHANGE, PASSWORD_CHANGE, PROFILE_UPDATE
  final String category;   // e.g. 'Session Activity', 'Account Modification', 'General Activity'
  final String title;
  final String description;
  final DateTime timestamp;

  AuditLogModel({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.actionType,
    required this.category,
    required this.title,
    required this.description,
    required this.timestamp,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userEmail: json['user_email']?.toString() ?? json['userEmail']?.toString() ?? '',
      actionType: json['action_type']?.toString() ?? json['actionType']?.toString() ?? 'GENERAL',
      category: json['category']?.toString() ?? 'Account Modification',
      title: json['title']?.toString() ?? 'Account Activity',
      description: json['description']?.toString() ?? '',
      timestamp: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : (json['timestamp'] != null ? DateTime.parse(json['timestamp'].toString()) : DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_email': userEmail,
      'action_type': actionType,
      'category': category,
      'title': title,
      'description': description,
      'created_at': timestamp.toIso8601String(),
    };
  }

  IconData get icon {
    switch (actionType.toUpperCase()) {
      case 'CUSTOMER_REGISTER':
      case 'USER_REGISTER':
        return Icons.person_add_alt_1_rounded;
      case 'BUSINESSMAN_REGISTER':
        return Icons.storefront_rounded;
      case 'GOVERNMENT_INSPECTION':
      case 'GOVERNMENT_REVIEW':
        return Icons.fact_check_rounded;
      case 'OUTLET_APPROVED':
        return Icons.verified_rounded;
      case 'OUTLET_REJECTED':
        return Icons.remove_circle_outline_rounded;
      case 'ADMIN_USER_EDIT':
      case 'ADMIN_ROLE_CHANGE':
      case 'ADMIN_PROFILE_EDIT':
        return Icons.admin_panel_settings_rounded;
      case 'LOGIN':
        return Icons.login_rounded;
      case 'LOGOUT':
        return Icons.logout_rounded;
      case 'PASSWORD_CHANGE':
        return Icons.lock_reset_rounded;
      default:
        return Icons.history_edu_rounded;
    }
  }

  Color get iconColor {
    switch (category.toLowerCase()) {
      case 'customer':
        return const Color(0xFF0F766E);
      case 'businessman':
        return const Color(0xFF0284C7);
      case 'government':
        return const Color(0xFFD97706);
      case 'admin':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF7C3AED);
    }
  }
}
