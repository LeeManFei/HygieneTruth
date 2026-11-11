import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audit_log_model.dart';
import '../utils/uuid_helper.dart';
import 'customer_store_service.dart';
import 'supabase_service.dart';

class AuditLogService {
  static const retention = Duration(days: 7);
  static Timer? _cleanupTimer;
  static DateTime get _cutoff => DateTime.now().toUtc().subtract(retention);

  static Future<void> initializeRetention() async {
    await cleanupLocalLogs();
    _cleanupTimer ??= Timer.periodic(const Duration(hours: 1), (_) async {
      try { await cleanupLocalLogs(); } catch (e) { debugPrint('Audit cache cleanup failed: $e'); }
    });
  }

  static Future<void> cleanupLocalLogs() async {
    final cutoff = _cutoff;
    _localLogs.removeWhere((l) => l.timestamp.toUtc().isBefore(cutoff));
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith('audit_logs_cache_'))) {
      final cached = prefs.getStringList(key) ?? [];
      final seen = <String>{};
      final kept = cached.where((raw) {
        try {
          final item = jsonDecode(raw) as Map;
          final date = DateTime.tryParse((item['created_at'] ?? item['timestamp'] ?? '').toString());
          if (date == null || date.toUtc().isBefore(cutoff)) return false;
          final id = item['id']?.toString();
          return seen.add(id == null || id.isEmpty ? raw : id);
        } catch (_) { return false; }
      }).toList();
      if (kept.length != cached.length) await prefs.setStringList(key, kept);
    }
  }

  static bool _isValidUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(str);
  }

  static final List<AuditLogModel> _localLogs = [];

  /// Record a new audit log action and persist to Supabase & SharedPreferences
  static Future<AuditLogModel> logAction({
    required String actionType,
    required String category,
    required String title,
    required String description,
    String? userId,
    String? userEmail,
  }) async {
    await cleanupLocalLogs();
    final String currentUserId = userId ?? CustomerStoreService.currentCustomer?.id ?? SupabaseService.client.auth.currentUser?.id ?? 'own_001';
    final String currentUserEmail = userEmail ?? CustomerStoreService.currentCustomer?.email ?? SupabaseService.client.auth.currentUser?.email ?? 'user@app.com';

    final String id = UuidHelper.generateV4();
    final DateTime now = DateTime.now();

    final log = AuditLogModel(
      id: id,
      userId: currentUserId,
      userEmail: currentUserEmail,
      actionType: actionType,
      category: category,
      title: title,
      description: description,
      timestamp: now,
    );

    // 1. Insert to in-memory list
    _localLogs.insert(0, log);

    final payload = {
      'id': id,
      'user_id': _isValidUuid(currentUserId) ? currentUserId : null,
      'user_email': currentUserEmail,
      'action_type': actionType,
      'category': category,
      'title': title,
      'description': description,
      'created_at': now.toUtc().toIso8601String(),
    };

    // 2. Persist to SharedPreferences local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final String cacheKey = 'audit_logs_cache_$currentUserId';
      final List<String> cachedList = prefs.getStringList(cacheKey) ?? [];
      cachedList.insert(0, jsonEncode(payload));
      if (cachedList.length > 200) cachedList.removeRange(200, cachedList.length);
      await prefs.setStringList(cacheKey, cachedList);

      final List<String> globalCachedList = prefs.getStringList('audit_logs_cache_global') ?? [];
      globalCachedList.insert(0, jsonEncode(payload));
      if (globalCachedList.length > 300) globalCachedList.removeRange(300, globalCachedList.length);
      await prefs.setStringList('audit_logs_cache_global', globalCachedList);
    } catch (e) {
      if (kDebugMode) print('SharedPreferences audit log save error: $e');
    }

    // 4. Persist to Supabase `audit_logs` table
    try {
      final supabase = SupabaseService.client;
      await supabase.from('audit_logs').insert(payload);
    } catch (tableErr) {
      if (kDebugMode) print('Supabase audit_logs table insert error: $tableErr');
    }

    return log;
  }

  /// Retrieve all audit logs across categories from Supabase & SharedPreferences
  static Future<List<AuditLogModel>> fetchAllLogs() async {
    await cleanupLocalLogs();
    final List<AuditLogModel> resultLogs = [];

    // 1. Fetch from Supabase `admin_action_logs` table
    try {
      final supabase = SupabaseService.client;
      final List<dynamic> adminLogs = await supabase
          .from('admin_action_logs')
          .select()
          .gte('created_at', _cutoff.toIso8601String())
          .order('created_at', ascending: false);

      for (var row in adminLogs) {
        if (row is Map<String, dynamic>) {
          final String rawDetails = (row['details'] ?? '').toString();
          String cat = 'Government / Admin';
          String tit = (row['action'] ?? 'Admin Action').toString();
          String desc = rawDetails;
          if (rawDetails.contains('|') && rawDetails.contains(':')) {
            final parts = rawDetails.split('|');
            cat = parts.first.trim();
            final rest = parts.sublist(1).join('|');
            if (rest.contains(':')) {
              tit = rest.split(':').first.trim();
              desc = rest.split(':').sublist(1).join(':').trim();
            }
          }

          final model = AuditLogModel(
            id: row['id']?.toString() ?? '',
            userId: row['admin_id']?.toString() ?? 'admin_001',
            userEmail: 'admin@hygienetruth.com',
            actionType: row['action']?.toString() ?? 'ADMIN_ACTION',
            category: cat,
            title: tit,
            description: desc,
            timestamp: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
          );
          if (!resultLogs.any((x) => x.id == model.id)) {
            resultLogs.add(model);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Supabase admin_action_logs query notice: $e');
    }

    // 2. Fetch from Supabase `audit_logs` table
    try {
      final supabase = SupabaseService.client;
      final List<dynamic> response = await supabase
          .from('audit_logs')
          .select()
          .gte('created_at', _cutoff.toIso8601String())
          .order('created_at', ascending: false);

      for (var row in response) {
        if (row is Map<String, dynamic>) {
          final model = AuditLogModel.fromJson(row);
          if (!resultLogs.any((x) => x.id == model.id)) {
            resultLogs.add(model);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Supabase audit_logs table query: $e');
    }

    // 3. Fetch from Supabase `user_audit_logs` table if present
    try {
      final supabase = SupabaseService.client;
      final List<dynamic> response = await supabase
          .from('user_audit_logs')
          .select()
          .gte('created_at', _cutoff.toIso8601String())
          .order('created_at', ascending: false);

      for (var row in response) {
        if (row is Map<String, dynamic>) {
          final model = AuditLogModel.fromJson(row);
          if (!resultLogs.any((x) => x.id == model.id)) {
            resultLogs.add(model);
          }
        }
      }
    } catch (_) {}

    // 3. Fetch from Supabase `users.settings` across all user records
    try {
      final supabase = SupabaseService.client;
      final List<dynamic> usersResp = await supabase
          .from('users')
          .select('settings');

      for (var row in usersResp) {
        if (row is Map<String, dynamic> && row['settings'] != null && row['settings']['audit_logs'] is List) {
          final List<dynamic> userLogs = row['settings']['audit_logs'];
          for (var item in userLogs) {
            if (item is Map<String, dynamic>) {
              final model = AuditLogModel.fromJson(item);
              if (!resultLogs.any((x) => x.id == model.id)) {
                resultLogs.add(model);
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Supabase fetchAllLogs settings error: $e');
    }

    // 4. Fetch from SharedPreferences global cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> cachedList = prefs.getStringList('audit_logs_cache_global') ?? [];
      for (var str in cachedList) {
        final Map<String, dynamic> map = jsonDecode(str);
        final model = AuditLogModel.fromJson(map);
        if (!resultLogs.any((x) => x.id == model.id)) {
          resultLogs.add(model);
        }
      }
    } catch (_) {}

    // 5. Merge local memory seed logs
    for (var l in _localLogs) {
      if (!resultLogs.any((x) => x.id == l.id)) {
        resultLogs.add(l);
      }
    }

    // Sort by timestamp descending
    resultLogs.removeWhere((l) => l.timestamp.toUtc().isBefore(_cutoff));
    resultLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return resultLogs;
  }

  /// Fetch all government operations and incoming admin assigned complaint logs
  static Future<List<AuditLogModel>> fetchGovernmentAuditLogs() async {
    final List<AuditLogModel> allLogs = await fetchAllLogs();
    final List<AuditLogModel> govLogs = [];

    // Filter relevant government & admin assignment logs
    for (var log in allLogs) {
      final act = log.actionType.toUpperCase();
      final cat = log.category.toUpperCase();
      final title = log.title.toUpperCase();
      final desc = log.description.toUpperCase();

      if (cat.contains('GOV') ||
          cat.contains('INSPECT') ||
          act.contains('INSPECT') ||
          act.contains('ENFORCE') ||
          act.contains('OUTLET_APP') ||
          act.contains('OUTLET_REJ') ||
          act.contains('CASE_') ||
          act.contains('COMPLAINT_') ||
          title.contains('COMPLAINT') ||
          title.contains('INSPECT') ||
          title.contains('ENFORCEMENT') ||
          title.contains('OUTLET') ||
          desc.contains('ASSIGN') ||
          desc.contains('COMPLAINT')) {
        govLogs.add(log);
      }
    }

    govLogs.removeWhere((l) => l.timestamp.toUtc().isBefore(_cutoff));
    govLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return govLogs;
  }

  /// Retrieve paginated audit logs for infinite scrolling

  static Future<List<AuditLogModel>> fetchPaginatedLogs({
    required int page,
    required int pageSize,
    String? category,
  }) async {
    final List<AuditLogModel> allLogs = await fetchAllLogs();

    final filtered = (category == null || category == 'All')
        ? allLogs
        : allLogs.where((l) => l.category.toLowerCase() == category.toLowerCase()).toList();

    final int start = page * pageSize;
    if (start >= filtered.length) return [];
    final int end = (start + pageSize) > filtered.length ? filtered.length : (start + pageSize);
    return filtered.sublist(start, end);
  }

  /// Retrieve audit logs for a specific user ID
  static Future<List<AuditLogModel>> fetchUserLogs({String? userId}) async {
    await cleanupLocalLogs();
    final String currentUserId = userId ?? CustomerStoreService.currentCustomer?.id ?? SupabaseService.client.auth.currentUser?.id ?? 'own_001';
    final String? currentUserEmail = CustomerStoreService.currentCustomer?.email ?? SupabaseService.client.auth.currentUser?.email;

    final List<AuditLogModel> resultLogs = [];

    // 1. Fetch from Supabase `users.settings` for this currentUserId
    if (_isValidUuid(currentUserId)) {
      try {
        final supabase = SupabaseService.client;
        final userResp = await supabase
            .from('users')
            .select('settings')
            .eq('id', currentUserId)
            .maybeSingle();

        if (userResp != null && userResp['settings'] != null && userResp['settings']['audit_logs'] is List) {
          final List<dynamic> userLogs = userResp['settings']['audit_logs'];
          for (var item in userLogs) {
            if (item is Map<String, dynamic>) {
              final model = AuditLogModel.fromJson(item);
              if (!resultLogs.any((x) => x.id == model.id)) {
                resultLogs.add(model);
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('Supabase fetchUserLogs settings error: $e');
      }
    }

    // 2. Fetch from SharedPreferences local user cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> cachedList = prefs.getStringList('audit_logs_cache_$currentUserId') ?? [];
      for (var str in cachedList) {
        final Map<String, dynamic> map = jsonDecode(str);
        final model = AuditLogModel.fromJson(map);
        if (!resultLogs.any((x) => x.id == model.id)) {
          resultLogs.add(model);
        }
      }
    } catch (_) {}

    // 3. Attempt fetching from legacy Supabase table `user_audit_logs`
    if (_isValidUuid(currentUserId)) {
      for (final table in ['audit_logs', 'user_audit_logs']) {
      try {
        final supabase = SupabaseService.client;
        final List<dynamic> response = await supabase
            .from(table)
            .select()
            .eq('user_id', currentUserId)
            .gte('created_at', _cutoff.toIso8601String())
          .order('created_at', ascending: false);

        for (var row in response) {
          if (row is Map<String, dynamic>) {
            final model = AuditLogModel.fromJson(row);
            if (!resultLogs.any((x) => x.id == model.id)) {
              resultLogs.add(model);
            }
          }
        }
      } catch (_) {}
      }
    }

    // 4. Merge with local memory logs for this user ID or email
    for (var l in _localLogs) {
      if (l.userId == currentUserId || (currentUserEmail != null && l.userEmail == currentUserEmail) || l.userId == 'own_001') {
        if (!resultLogs.any((x) => x.id == l.id)) {
          resultLogs.add(l);
        }
      }
    }

    // Filter out cross-portal access blocked logs to maintain zero account/role exposure
    resultLogs.removeWhere((l) =>
        l.title.toLowerCase().contains('cross-portal') ||
        l.category.toLowerCase().contains('unauthorized portal') ||
        l.description.toLowerCase().contains('cross-portal') ||
        l.description.toLowerCase().contains('rejected attempting to login'));

    // Clean up local cache if it contains legacy cross-portal logs
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'audit_logs_cache_$currentUserId';
      final cachedList = prefs.getStringList(key) ?? [];
      final cleanedList = cachedList.where((str) {
        final lower = str.toLowerCase();
        return !lower.contains('cross-portal') && !lower.contains('unauthorized portal');
      }).toList();
      if (cleanedList.length != cachedList.length) {
        await prefs.setStringList(key, cleanedList);
      }
    } catch (_) {}

    // Sort by timestamp descending
    resultLogs.removeWhere((l) => l.timestamp.toUtc().isBefore(_cutoff));
    resultLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return resultLogs;
  }
}
