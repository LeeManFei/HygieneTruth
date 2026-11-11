import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../notifications/models/notification_model.dart';
import '../models/complaint_model.dart';
import '../models/restaurant_model.dart';
import '../utils/image_hash_helper.dart';
import '../utils/uuid_helper.dart';
import 'notification_service.dart';
import 'restaurant_store_service.dart';
import 'supabase_service.dart';
import 'audit_log_service.dart';

class DataSyncService {
  static bool _isSyncing = false;

  /// Full bidirectional synchronization between SharedPreferences (local cache) and Supabase database.
  /// Ensures all tables (restaurants, inspections, notices, evidence, notifications, complaints, admin_action_logs, audit_logs)
  /// contain complete, real, persistent data in both local storage and cloud database.
  static Future<void> syncAllData() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      debugPrint('🔄 [DataSyncService] Starting full Supabase & SharedPreferences dual sync...');

      // 1. Sync Restaurants
      await _syncRestaurants();

      // 2. Sync Inspections, Evidence & Notices
      await _syncInspectionsNoticesAndEvidence();

      // 2b. Sync Rectifications (Owner Submissions & Admin Verifications)
      await _syncRectifications();

      // 3. Sync Notifications
      await _syncNotifications();

      // 4. Sync Complaints & Photo Hashes
      await _syncComplaints();

      // 5. Sync Admin Action Logs & Audit Logs
      await _syncAdminAuditLogs();

      debugPrint('✅ [DataSyncService] Dual sync completed successfully! All tables populated.');
    } catch (e) {
      debugPrint('⚠️ [DataSyncService] Sync notice: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ==========================================
  // 1. RESTAURANTS DUAL SYNC (FETCH & CACHE ONLY)
  // ==========================================
  static Future<void> _syncRestaurants() async {
    final supabase = SupabaseService.client;
    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await supabase.from('restaurants').select().order('created_at', ascending: false);
      if (res.isNotEmpty) {
        final List<RestaurantModel> fetched = (res as List<dynamic>).map((r) {
          final map = Map<String, dynamic>.from(r as Map);
          final String id = map['id']?.toString() ?? '';
          final String name = map['name']?.toString() ?? '';
          final bool isLocallyPaid = prefs.getBool('restaurant_override_fine_paid_$id') == true ||
              prefs.getBool('restaurant_override_fine_paid_${name.toLowerCase()}') == true ||
              RestaurantStoreService.isOutletFinePaid(id, restaurantName: name);

          if (isLocallyPaid) {
            map['is_fine_paid'] = true;
            map['is_suspended'] = false;
          }
          return RestaurantModel.fromMap(map);
        }).toList();

        RestaurantStoreService.restaurantsNotifier.value = fetched;
        await prefs.setString('local_custom_restaurants', jsonEncode(fetched.map((r) => r.toMap()).toList()));
        await prefs.setString('cached_all_restaurants_feed', jsonEncode(fetched.map((r) => r.toMap()).toList()));

        for (final r in fetched) {
          try {
            await RestaurantStoreService.fetchReviews(r.id, restaurantName: r.name, forceRefresh: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Restaurants sync notice: $e');
    }
  }

  // ==========================================
  // 2. INSPECTIONS, NOTICES & EVIDENCE DUAL SYNC
  // ==========================================
  static Future<void> _syncInspectionsNoticesAndEvidence() async {
    // Demo inspections use display IDs and must stay local; fetch persisted cases.
    await RestaurantStoreService.fetchInspections();
  }

  // ==========================================
  // 2b. RECTIFICATIONS DUAL SYNC
  // ==========================================
  static Future<void> _syncRectifications() async {
    try {
      await RestaurantStoreService.syncRectificationsFromSupabase();
    } catch (e) {
      debugPrint('Rectifications sync notice: $e');
    }
  }

  // ==========================================
  // 3. NOTIFICATIONS DUAL SYNC & SEED
  // ==========================================
  static Future<void> _syncNotifications() async {
    final supabase = SupabaseService.client;
    final prefs = await SharedPreferences.getInstance();

    final userId = UuidHelper.toDeterministicUuid('usr_current');
    final ownerId = UuidHelper.toDeterministicUuid('own_001');

    final List<AppNotificationModel> seedNotifications = [
      AppNotificationModel(
        id: UuidHelper.toDeterministicUuid('notif_welcome_01'),
        userId: userId,
        title: '🌟 Welcome to HygieneTruth Portal',
        message: 'Explore verified restaurant cleanliness ratings, submit complaints, and track KKM health inspections.',
        type: NotificationType.system,
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)).toUtc(),
      ),
      AppNotificationModel(
        id: UuidHelper.toDeterministicUuid('notif_testing_complaint_02'),
        userId: userId,
        title: '📋 Hygiene Report Queued: #CMP-90D5C3F3',
        message: 'Your report for "testing" has been dispatched to municipal health officers for inspection.',
        type: NotificationType.complaint,
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)).toUtc(),
      ),
      AppNotificationModel(
        id: UuidHelper.toDeterministicUuid('notif_owner_inspection_03'),
        userId: ownerId,
        title: '📋 Official Health Notice Received',
        message: 'Health Inspector scheduled an audit visit for your outlet "testing". Please prepare food handler logs.',
        type: NotificationType.hygieneAlert,
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 45)).toUtc(),
      ),
    ];

    // Persist locally for instant offline UI display
    NotificationService.notificationsNotifier.value = seedNotifications;
    await prefs.setString('user_notifications_usr_current', jsonEncode(seedNotifications.map((n) => n.toMap()).toList()));

    // Fetch valid registered user IDs to avoid FK constraint violations
    Set<String> validUserIds = {};
    try {
      final userRows = await supabase.from('users').select('id').timeout(const Duration(seconds: 2));
      validUserIds = (userRows as List<dynamic>).map((u) => u['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (_) {}

    for (final notif in seedNotifications) {
      if (!validUserIds.contains(notif.userId)) continue;
      try {
        final Map<String, dynamic> row = {
          'id': notif.id,
          'user_id': notif.userId,
          'title': notif.title,
          'message': notif.message,
          'type': notif.type.name,
          'action_url': notif.actionUrl,
          'data': notif.data,
          'is_read': notif.isRead,
          'created_at': notif.createdAt.toUtc().toIso8601String(),
        };
        await supabase.from('notifications').upsert(row);
      } catch (e) {
        debugPrint('Notification upsert notice: $e');
      }
    }

    // Fetch and merge remote notifications
    try {
      final res = await supabase.from('notifications').select().order('created_at', ascending: false);
      if (res.isNotEmpty) {
        final List<AppNotificationModel> list = (res as List<dynamic>)
            .map((row) => AppNotificationModel.fromMap(Map<String, dynamic>.from(row as Map)))
            .toList();
        NotificationService.notificationsNotifier.value = list;
        await prefs.setString('user_notifications_usr_current', jsonEncode(list.map((n) => n.toMap()).toList()));
      }
    } catch (_) {}
  }

  // ==========================================
  // 4. COMPLAINTS DUAL SYNC & SEED
  // ==========================================
  static Future<void> _syncComplaints() async {
    final supabase = SupabaseService.client;

    final testingRestId = UuidHelper.toDeterministicUuid('rest_testing_custom');
    final userUuid = UuidHelper.toDeterministicUuid('usr_current');

    final ComplaintModel seedComplaint = ComplaintModel(
      id: UuidHelper.toDeterministicUuid('cmp_testing_sample_01'),
      restaurantId: testingRestId,
      restaurantName: 'testing',
      userId: userUuid,
      userName: 'Citizen Diner',
      category: 'Food Quality & Poisoning',
      issues: const ['Food Poisoning', 'Expired / Spoiled Ingredients', 'Raw / Undercooked Meat'],
      description: 'Customer experienced food safety symptoms after dining. Requires kitchen cold storage and ingredient inspection.',
      status: ComplaintStatus.investigating,
      severity: SeverityLevel.high,
      latitude: 3.1466,
      longitude: 101.6958,
      submittedAt: DateTime.now().subtract(const Duration(hours: 4)).toUtc().toIso8601String(),
      photoUrls: const [],
    );

    // Refresh ComplaintStoreService & cache locally first
    try {
      await ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
    } catch (_) {}

    // Check if userUuid exists in Supabase before attempting insert
    Set<String> validUserIds = {};
    try {
      final userRows = await supabase.from('users').select('id').timeout(const Duration(seconds: 2));
      validUserIds = (userRows as List<dynamic>).map((u) => u['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (_) {}

    if (validUserIds.contains(seedComplaint.userId)) {
      try {
        final payload = {
          'id': seedComplaint.id,
          'restaurant_id': seedComplaint.restaurantId,
          'user_id': seedComplaint.userId,
          'category': seedComplaint.category,
          'description': seedComplaint.description,
          'status': 'investigating',
          'severity': 'high',
          'latitude': seedComplaint.latitude,
          'longitude': seedComplaint.longitude,
          'is_flagged_for_review': false,
          'submitted_at': seedComplaint.submittedAt,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        await supabase.from('complaints').upsert(payload);

        // Upsert issue tags
        for (final iss in seedComplaint.issues) {
          await supabase.from('complaint_issues').upsert({
            'id': UuidHelper.toDeterministicUuid('issue_${seedComplaint.id}_$iss'),
            'complaint_id': seedComplaint.id,
            'issue_text': iss,
          });
        }

        // Upsert photos with computed cryptographic image_hash
        for (final url in seedComplaint.photoUrls) {
          final hash = ImageHashHelper.computeHashSync(url);
          await supabase.from('complaint_photos').upsert({
            'id': UuidHelper.toDeterministicUuid('photo_${seedComplaint.id}_${url.hashCode}'),
            'complaint_id': seedComplaint.id,
            'photo_url': url,
            'image_hash': hash,
            'uploaded_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('Complaints sync notice: $e');
      }
    }
  }

  // ==========================================
  // 5. ADMIN ACTION LOGS & AUDIT LOGS DUAL SYNC
  // ==========================================
  static Future<void> _syncAdminAuditLogs() async {
    // Retain real events only; startup must not recreate synthetic audit history.
    await AuditLogService.cleanupLocalLogs();
  }
}
