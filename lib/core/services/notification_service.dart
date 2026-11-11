import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../notifications/models/notification_model.dart';
import '../routes/app_routes.dart';
import '../utils/uuid_helper.dart';
import 'supabase_service.dart';
import 'notification_router.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    final FlutterLocalNotificationsPlugin bgNotifPlugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await bgNotifPlugin.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      'hygienetruth_live_alerts',
      'HygieneTruth Alerts & Updates',
      description: 'High priority alerts for restaurant approvals, owner replies, complaints, and reviews',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final androidImplementation = bgNotifPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(androidChannel);
    }

    final title = message.notification?.title ?? message.data['title'] ?? 'HygieneTruth Alert';
    final body = message.notification?.body ?? message.data['message'] ?? message.data['body'] ?? '';

    final bigTextStyle = BigTextStyleInformation(
      body,
      htmlFormatBigText: false,
      contentTitle: title,
      htmlFormatContentTitle: false,
      summaryText: 'HygieneTruth Alert',
      htmlFormatSummaryText: false,
    );

    final androidDetails = AndroidNotificationDetails(
      'hygienetruth_live_alerts',
      'HygieneTruth Alerts & Updates',
      channelDescription: 'High priority alerts for restaurant approvals, owner replies, complaints, and reviews',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF0F766E),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 250, 150, 250]),
      playSound: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.message,
      styleInformation: bigTextStyle,
      visibility: NotificationVisibility.public,
    );

    if (title.isNotEmpty || body.isNotEmpty) {
      final int notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payloadStr = message.data['action_url'] ??
          message.data['actionUrl'] ??
          jsonEncode(message.data);

      await bgNotifPlugin.show(
        notifId,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: payloadStr,
      );
    }
  } catch (e) {
    if (kDebugMode) {
      print('Background FCM notification error: $e');
    }
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static final List<AppNotificationModel> _notifications = [];
  static final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<List<AppNotificationModel>> notificationsNotifier =
      ValueNotifier<List<AppNotificationModel>>([]);

  static RealtimeChannel? _realtimeChannel;
  static String? _currentSubscribedUserId;
  static String? _fcmToken;

  static String? get fcmToken => _fcmToken;

  /// Initialize Firebase & Local Notification channels & permissions
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Initialize Firebase Core
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      if (kDebugMode) {
        print('Firebase init notice: $e');
      }
    }

    // 2. Initialize Local Notifications Plugin
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );

      await _localNotifPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          if (kDebugMode) {
            print('Notification tapped with payload: ${details.payload}');
          }
          NotificationRouter.navigateFromPayload(details.payload);
        },
      );

      // Check if app was launched directly by tapping a notification
      final launchDetails = await _localNotifPlugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchDetails?.notificationResponse?.payload != null) {
        NotificationRouter.navigateFromPayload(launchDetails!.notificationResponse!.payload);
      }

      if (Platform.isAndroid) {
        final androidImplementation = _localNotifPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          await androidImplementation.createNotificationChannel(
            const AndroidNotificationChannel(
              'hygienetruth_live_alerts',
              'HygieneTruth Alerts & Updates',
              description: 'High priority alerts for restaurant approvals, owner replies, complaints, and reviews',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
              showBadge: true,
            ),
          );
          await androidImplementation.createNotificationChannel(
            const AndroidNotificationChannel(
              'hygienetruth_reminders',
              'HygieneTruth Reminders & Updates',
              description: 'Daily reminders for unread notices and safety reviews',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
              showBadge: true,
            ),
          );
          await androidImplementation.requestNotificationsPermission();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Local notifications init error: $e');
      }
    }

    // 3. Configure FCM Listeners & Request Permission
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _fcmToken = await messaging.getToken();
      if (kDebugMode) {
        print('Device FCM Token: $_fcmToken');
      }

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final title = notification?.title ?? message.data['title'] ?? 'Hygiene Alert';
        final body = notification?.body ?? message.data['message'] ?? '';
        final typeStr = message.data['type'] ?? 'system';

        final notif = AppNotificationModel(
          id: message.messageId ?? 'fcm_${DateTime.now().millisecondsSinceEpoch}',
          userId: _currentSubscribedUserId ?? '',
          title: title,
          message: body,
          type: _parseType(typeStr),
          actionUrl: message.data['action_url'] ?? message.data['actionUrl'],
          data: message.data,
          isRead: false,
          createdAt: DateTime.now(),
        );

        _handleIncomingNotification(notif);
      });

      // App opened from background notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final payload = message.data['action_url'] ??
            message.data['actionUrl'] ??
            jsonEncode(message.data);
        NotificationRouter.navigateFromPayload(payload);
      });

      // App opened from terminated state via FCM notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final payload = initialMessage.data['action_url'] ??
            initialMessage.data['actionUrl'] ??
            jsonEncode(initialMessage.data);
        NotificationRouter.navigateFromPayload(payload);
      }

      // Token refresh listener
      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (_currentSubscribedUserId != null) {
          syncFcmTokenToSupabase(_currentSubscribedUserId!);
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Firebase Messaging setup error: $e');
      }
    }

    _isInitialized = true;
  }

  /// Sync device FCM token to Supabase users and user_devices table
  static Future<void> syncFcmTokenToSupabase(String userId) async {
    if (_fcmToken == null || _fcmToken!.isEmpty || userId.isEmpty) return;
    try {
      final supabase = SupabaseService.client;
      // Update users table
      await supabase.from('users').update({
        'fcm_token': _fcmToken,
        'fcm_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {}

    try {
      final supabase = SupabaseService.client;
      // Upsert into user_devices table
      await supabase.from('user_devices').upsert({
        'user_id': userId,
        'fcm_token': _fcmToken,
        'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web'),
        'last_active': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (_) {}
  }

  /// Start Supabase Realtime live WebSocket listener for this user
  static void startRealtimeListener(String userId) {
    if (_currentSubscribedUserId == userId && _realtimeChannel != null) return;
    _currentSubscribedUserId = userId;

    // Sync FCM Token immediately
    syncFcmTokenToSupabase(userId);

    try {
      final supabase = SupabaseService.client;
      if (_realtimeChannel != null) {
        supabase.removeChannel(_realtimeChannel!);
      }

      _realtimeChannel = supabase
          .channel('user-notifications-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final newRow = payload.newRecord;
              if (newRow.isNotEmpty) {
                final notif = AppNotificationModel.fromMap(newRow);
                _handleIncomingNotification(notif);
              }
            },
          )
          .subscribe();
    } catch (e) {
      if (kDebugMode) {
        print('Error starting Realtime notification listener: $e');
      }
    }
  }

  /// Show heads-up device banner notification with rich expandable text, sound and vibration
  static Future<void> showLocalNotification({
    required String title,
    required String message,
    String? payload,
    int? notificationId,
    String channelId = 'hygienetruth_live_alerts',
    String channelName = 'HygieneTruth Alerts & Updates',
  }) async {
    try {
      await initialize();

      final bigTextStyle = BigTextStyleInformation(
        message,
        htmlFormatBigText: false,
        contentTitle: title,
        htmlFormatContentTitle: false,
        summaryText: 'HygieneTruth Alert',
        htmlFormatSummaryText: false,
      );

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'High priority alerts for restaurant approvals, owner replies, complaints, and reviews',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF0F766E),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 250, 150, 250]),
        playSound: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.message,
        styleInformation: bigTextStyle,
        visibility: NotificationVisibility.public,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notifDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final id = notificationId ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 100000;
      await _localNotifPlugin.show(
        id,
        title,
        message,
        notifDetails,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error showing local notification: $e');
      }
    }
  }

  static void _handleIncomingNotification(AppNotificationModel notif) {
    final existingIdx = _notifications.indexWhere((n) => n.id == notif.id);
    if (existingIdx != -1) {
      _notifications[existingIdx] = notif;
    } else {
      _notifications.insert(0, notif);
      final payloadJson = jsonEncode({
        'id': notif.id,
        'type': notif.type.name,
        'action_url': notif.actionUrl,
        'title': notif.title,
        'message': notif.message,
        'data': notif.data,
      });
      showLocalNotification(
        title: notif.title,
        message: notif.message,
        payload: payloadJson,
      );
    }
    _updateStateAndPersist();
  }

  /// Load user read state from Supabase users.settings and local SharedPreferences
  static Future<Map<String, dynamic>> _loadUserReadState(String? cleanUserId, String? cleanEmail) async {
    final Set<String> readIds = {};
    DateTime? allReadAt;

    // 1. Read from local SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final localKey = 'user_read_ids_${cleanUserId ?? cleanEmail ?? "guest"}';
      final localAllKey = 'user_all_read_at_${cleanUserId ?? cleanEmail ?? "guest"}';

      final savedIds = prefs.getStringList(localKey);
      if (savedIds != null) {
        readIds.addAll(savedIds);
      }

      final savedAllStr = prefs.getString(localAllKey);
      if (savedAllStr != null && savedAllStr.isNotEmpty) {
        allReadAt = DateTime.tryParse(savedAllStr);
      }
    } catch (_) {}

    // 2. Fetch cloud read state from Supabase users table settings column
    if (cleanUserId != null && cleanUserId.isNotEmpty) {
      try {
        final supabase = SupabaseService.client;
        final userRow = await supabase
            .from('users')
            .select('settings')
            .eq('id', cleanUserId)
            .maybeSingle();

        if (userRow != null && userRow['settings'] is Map) {
          final settings = Map<String, dynamic>.from(userRow['settings'] as Map);
          final cloudReadIds = settings['read_notification_ids'];
          if (cloudReadIds is List) {
            for (final id in cloudReadIds) {
              readIds.add(id.toString());
            }
          }
          final cloudAllReadStr = settings['notifications_read_all_at']?.toString();
          if (cloudAllReadStr != null && cloudAllReadStr.isNotEmpty) {
            final cloudDt = DateTime.tryParse(cloudAllReadStr);
            if (cloudDt != null) {
              if (allReadAt == null || cloudDt.isAfter(allReadAt)) {
                allReadAt = cloudDt;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Check audit_logs as backup cloud sync
    try {
      final supabase = SupabaseService.client;
      final logs = await supabase
          .from('audit_logs')
          .select('action_type, description, created_at')
          .or('action_type.eq.READ_NOTIFICATION,action_type.eq.READ_ALL_NOTIFICATIONS')
          .order('created_at', ascending: false)
          .limit(50);

      for (final log in logs) {
        final action = (log['action_type'] ?? '').toString();
        final desc = (log['description'] ?? '').toString();
        if (action == 'READ_NOTIFICATION' && desc.isNotEmpty) {
          readIds.add(desc);
        } else if (action == 'READ_ALL_NOTIFICATIONS') {
          final logDt = DateTime.tryParse(log['created_at']?.toString() ?? '');
          if (logDt != null && (allReadAt == null || logDt.isAfter(allReadAt))) {
            allReadAt = logDt;
          }
        }
      }
    } catch (_) {}

    return {
      'readIds': readIds,
      'allReadAt': allReadAt,
    };
  }

  /// Fetch all notifications for the given user from Supabase and local cache with permanent read status
  static Future<List<AppNotificationModel>> fetchNotifications({
    String? userId,
    String? userEmail,
    String? userRole,
  }) async {
    final List<AppNotificationModel> resultList = [];
    final Set<String> seenIds = {};
    final cleanUserId = userId?.trim();
    final cleanEmail = userEmail?.trim().toLowerCase();

    // Retrieve synchronized read history from cloud & local storage
    final readState = await _loadUserReadState(cleanUserId, cleanEmail);
    final Set<String> readIds = readState['readIds'] as Set<String>;
    final DateTime? allReadAt = readState['allReadAt'] as DateTime?;

    // 1. Try fetching from Supabase public.notifications table
    try {
      final supabase = SupabaseService.client;
      dynamic query = supabase.from('notifications').select().order('created_at', ascending: false);
      if (cleanUserId != null && cleanUserId.isNotEmpty) {
        query = query.eq('user_id', cleanUserId);
      }
      final rows = await query as List<dynamic>;
      for (final r in rows) {
        final map = Map<String, dynamic>.from(r as Map);
        final notif = AppNotificationModel.fromMap(map);
        if (!seenIds.contains(notif.id)) {
          seenIds.add(notif.id);
          final bool isRead = notif.isRead ||
              readIds.contains(notif.id) ||
              (allReadAt != null && notif.createdAt.isBefore(allReadAt.add(const Duration(seconds: 10))));
          resultList.add(notif.copyWith(isRead: isRead));
        }
      }
    } catch (_) {}

    // 2. Try fetching notification records stored in Supabase audit_logs table (reliable backup)
    try {
      final supabase = SupabaseService.client;
      final logs = await supabase
          .from('audit_logs')
          .select()
          .eq('action_type', 'USER_NOTIFICATION')
          .order('created_at', ascending: false)
          .limit(30);
      for (final log in logs) {
        final lUserId = (log['user_id'] ?? '').toString();
        final lEmail = (log['user_email'] ?? '').toString().toLowerCase();
        final desc = (log['description'] ?? '').toString();
        final bool isTarget = (cleanUserId != null && lUserId == cleanUserId) ||
            (cleanEmail != null && lEmail == cleanEmail) ||
            (log['title'] ?? '').toString().toLowerCase().contains('broadcast');

        if (isTarget && desc.startsWith('{') && desc.endsWith('}')) {
          try {
            final parsedMap = Map<String, dynamic>.from(jsonDecode(desc) as Map);
            final notif = AppNotificationModel.fromMap(parsedMap);
            if (!seenIds.contains(notif.id)) {
              seenIds.add(notif.id);
              final bool isRead = notif.isRead ||
                  readIds.contains(notif.id) ||
                  (allReadAt != null && notif.createdAt.isBefore(allReadAt.add(const Duration(seconds: 10))));
              resultList.add(notif.copyWith(isRead: isRead));
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 3. Merge with local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'user_notifications_${cleanUserId ?? "guest"}';
      final localJson = prefs.getString(cacheKey);
      if (localJson != null && localJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(localJson);
        for (final item in decoded) {
          final notif = AppNotificationModel.fromMap(Map<String, dynamic>.from(item as Map));
          if (!seenIds.contains(notif.id)) {
            seenIds.add(notif.id);
            final bool isRead = notif.isRead ||
                readIds.contains(notif.id) ||
                (allReadAt != null && notif.createdAt.isBefore(allReadAt.add(const Duration(seconds: 10))));
            resultList.add(notif.copyWith(isRead: isRead));
          }
        }
      }
    } catch (_) {}

    // 4. Default Seed Notifications based on role if brand new / empty
    if (resultList.isEmpty) {
      final seedList = _getSeedNotifications(cleanUserId ?? 'usr_current', userRole ?? 'customer');
      for (final s in seedList) {
        if (!seenIds.contains(s.id)) {
          seenIds.add(s.id);
          final bool isRead = s.isRead ||
              readIds.contains(s.id) ||
              (allReadAt != null && s.createdAt.isBefore(allReadAt.add(const Duration(seconds: 10))));
          resultList.add(s.copyWith(isRead: isRead));
        }
      }
    }

    // Sort descending by date
    resultList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _notifications.clear();
    _notifications.addAll(resultList);
    _updateStateAndPersist(userId: cleanUserId);

    if (cleanUserId != null && cleanUserId.isNotEmpty) {
      startRealtimeListener(cleanUserId);
    }

    return _notifications;
  }

  /// Mark single notification as read with cloud persistence to Supabase and local cache
  static Future<void> markAsRead(String notificationId, {String? userId, String? userEmail}) async {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx != -1) {
      _notifications[idx] = _notifications[idx].copyWith(isRead: true);
      _updateStateAndPersist(userId: userId);

      final cleanUserId = userId?.trim();
      final cleanEmail = userEmail?.trim().toLowerCase();

      // 1. Save to local SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final localKey = 'user_read_ids_${cleanUserId ?? cleanEmail ?? "guest"}';
        final existingList = prefs.getStringList(localKey) ?? [];
        if (!existingList.contains(notificationId)) {
          existingList.add(notificationId);
          await prefs.setStringList(localKey, existingList);
        }
      } catch (_) {}

      // 2. Update Supabase notifications table
      try {
        final supabase = SupabaseService.client;
        await supabase.from('notifications').update({'is_read': true}).eq('id', notificationId);
      } catch (_) {}

      // 3. Sync to Supabase users.settings JSON
      if (cleanUserId != null && cleanUserId.isNotEmpty) {
        try {
          final supabase = SupabaseService.client;
          final userRow = await supabase
              .from('users')
              .select('settings')
              .eq('id', cleanUserId)
              .maybeSingle();

          final currentSettings = Map<String, dynamic>.from((userRow?['settings'] as Map?) ?? {});
          final List<String> currentReadIds = List<String>.from((currentSettings['read_notification_ids'] as List?) ?? []);
          if (!currentReadIds.contains(notificationId)) {
            currentReadIds.add(notificationId);
            currentSettings['read_notification_ids'] = currentReadIds;
            await supabase.from('users').update({'settings': currentSettings}).eq('id', cleanUserId);
          }
        } catch (_) {}
      }

      // 4. Log to audit_logs as backup cloud record
      try {
        final supabase = SupabaseService.client;
        final resolvedUserId = (cleanUserId != null && cleanUserId.length > 10)
            ? cleanUserId
            : (cleanEmail != null && cleanEmail.isNotEmpty
                ? UuidHelper.deterministic(cleanEmail)
                : UuidHelper.generate());
        await supabase.from('audit_logs').insert({
          'user_id': resolvedUserId,
          'user_email': cleanEmail ?? 'user@hygienetruth.com',
          'action_type': 'READ_NOTIFICATION',
          'category': 'Notification State',
          'title': 'Notification Marked Read',
          'description': notificationId,
        });
      } catch (_) {}
    }
  }

  /// Mark all notifications as read with cloud persistence to Supabase and local cache
  static Future<void> markAllAsRead({String? userId, String? userEmail}) async {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    _updateStateAndPersist(userId: userId);

    final cleanUserId = userId?.trim();
    final cleanEmail = userEmail?.trim().toLowerCase();
    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final allIds = _notifications.map((n) => n.id).toList();

    // 1. Save to local SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final localKey = 'user_read_ids_${cleanUserId ?? cleanEmail ?? "guest"}';
      final localAllKey = 'user_all_read_at_${cleanUserId ?? cleanEmail ?? "guest"}';

      final existingList = prefs.getStringList(localKey) ?? [];
      for (final id in allIds) {
        if (!existingList.contains(id)) {
          existingList.add(id);
        }
      }
      await prefs.setStringList(localKey, existingList);
      await prefs.setString(localAllKey, nowIso);
    } catch (_) {}

    // 2. Update Supabase notifications table
    try {
      final supabase = SupabaseService.client;
      if (cleanUserId != null && cleanUserId.isNotEmpty) {
        await supabase.from('notifications').update({'is_read': true}).eq('user_id', cleanUserId);
      }
    } catch (_) {}

    // 3. Sync to Supabase users.settings JSON
    if (cleanUserId != null && cleanUserId.isNotEmpty) {
      try {
        final supabase = SupabaseService.client;
        final userRow = await supabase
            .from('users')
            .select('settings')
            .eq('id', cleanUserId)
            .maybeSingle();

        final currentSettings = Map<String, dynamic>.from((userRow?['settings'] as Map?) ?? {});
        final List<String> currentReadIds = List<String>.from((currentSettings['read_notification_ids'] as List?) ?? []);
        for (final id in allIds) {
          if (!currentReadIds.contains(id)) {
            currentReadIds.add(id);
          }
        }
        currentSettings['read_notification_ids'] = currentReadIds;
        currentSettings['notifications_read_all_at'] = nowIso;
        await supabase.from('users').update({'settings': currentSettings}).eq('id', cleanUserId);
      } catch (_) {}
    }

      // 4. Log to audit_logs as backup cloud record
      try {
        final supabase = SupabaseService.client;
        final resolvedUserId = (cleanUserId != null && cleanUserId.length > 10)
            ? cleanUserId
            : (cleanEmail != null && cleanEmail.isNotEmpty
                ? UuidHelper.deterministic(cleanEmail)
                : UuidHelper.generate());
        await supabase.from('audit_logs').insert({
          'user_id': resolvedUserId,
          'user_email': cleanEmail ?? 'user@hygienetruth.com',
          'action_type': 'READ_ALL_NOTIFICATIONS',
          'category': 'Notification State',
          'title': 'All Notifications Marked Read',
          'description': nowIso,
        });
      } catch (_) {}
  }

  /// Delete notification
  static Future<void> deleteNotification(String notificationId, {String? userId}) async {
    _notifications.removeWhere((n) => n.id == notificationId);
    _updateStateAndPersist(userId: userId);
    try {
      final supabase = SupabaseService.client;
      await supabase.from('notifications').delete().eq('id', notificationId);
    } catch (_) {}
  }

  /// Clear all notifications
  static Future<void> clearAll({String? userId}) async {
    _notifications.clear();
    _updateStateAndPersist(userId: userId);
    try {
      final supabase = SupabaseService.client;
      if (userId != null && userId.isNotEmpty) {
        await supabase.from('notifications').delete().eq('user_id', userId);
      }
    } catch (_) {}
  }

  /// Send a new notification to a specific user and broadcast via Supabase & Local Notifications
  static Future<bool> sendNotification({
    required String userId,
    required String title,
    required String message,
    NotificationType type = NotificationType.system,
    String? actionUrl,
    Map<String, dynamic>? data,
    String? userEmail,
  }) async {
    final notifId = UuidHelper.generateV4();
    final notif = AppNotificationModel(
      id: notifId,
      userId: userId,
      title: title,
      message: message,
      type: type,
      actionUrl: actionUrl,
      data: data ?? {},
      isRead: false,
      createdAt: DateTime.now().toUtc(),
    );

    if (_currentSubscribedUserId == userId || _currentSubscribedUserId == null) {
      _notifications.insert(0, notif);
      _updateStateAndPersist(userId: userId);
      final payloadJson = jsonEncode({
        'id': notif.id,
        'type': notif.type.name,
        'action_url': actionUrl ?? notif.actionUrl,
        'title': title,
        'message': message,
        'data': data ?? notif.data,
      });
      showLocalNotification(
        title: title,
        message: message,
        payload: payloadJson,
      );
    }

    try {
      final supabase = SupabaseService.client;
      final validUserId = UuidHelper.toDeterministicUuid(userId);
      final userCheck = await supabase.from('users').select('id').eq('id', validUserId).maybeSingle();
      if (userCheck != null) {
        await supabase.from('notifications').upsert({
          'id': notifId,
          'user_id': validUserId,
          'title': title,
          'message': message,
          'type': type.name,
          'action_url': actionUrl,
          'data': data ?? {},
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (_) {}

    try {
      final supabase = SupabaseService.client;
      final validUserId = UuidHelper.toDeterministicUuid(userId);
      await supabase.from('audit_logs').insert({
        'user_id': validUserId,
        'user_email': userEmail ?? 'user@hygienetruth.com',
        'action_type': 'USER_NOTIFICATION',
        'category': 'System Notification',
        'title': title,
        'description': jsonEncode(notif.toMap()),
      });
    } catch (_) {}

    return true;
  }

  static void _updateStateAndPersist({String? userId}) async {
    final unread = _notifications.where((n) => !n.isRead).length;
    unreadCountNotifier.value = unread;
    notificationsNotifier.value = List.from(_notifications);

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'user_notifications_${userId ?? _currentSubscribedUserId ?? "guest"}';
      final encoded = jsonEncode(_notifications.map((n) => n.toMap()).toList());
      await prefs.setString(cacheKey, encoded);
    } catch (_) {}
  }

  static NotificationType _parseType(String typeStr) {
    final s = typeStr.toLowerCase();
    if (s.contains('complaint')) return NotificationType.complaint;
    if (s.contains('outlet') || s.contains('restaurant')) return NotificationType.outlet;
    if (s.contains('review')) return NotificationType.review;
    if (s.contains('alert') || s.contains('hygiene') || s.contains('outbreak')) return NotificationType.hygieneAlert;
    return NotificationType.system;
  }

  /// Check for unread notifications and send a real incoming reminder notification if unread items exist
  static Future<void> checkAndSendUnreadReminder({String? userId, String? userEmail}) async {
    final unreadCount = unreadCountNotifier.value;
    if (unreadCount <= 0) return;

    final unreadItems = _notifications.where((n) => !n.isRead).toList();
    if (unreadItems.isEmpty) return;

    final latest = unreadItems.first;
    String reminderTitle = '👋 Welcome Back to HygieneTruth';
    String reminderBody = 'You have $unreadCount unread hygiene alert${unreadCount > 1 ? "s" : ""} waiting for you. Tap to review now.';

    if (latest.type == NotificationType.review) {
      reminderTitle = '💬 Unread Review Response';
      reminderBody = 'The restaurant owner responded to your review. Tap to view the details.';
    } else if (latest.type == NotificationType.complaint) {
      reminderTitle = '📋 Unread Health Inspection Update';
      reminderBody = 'Your hygiene report status was updated. Tap to see the latest inspection findings.';
    } else if (latest.type == NotificationType.hygieneAlert) {
      reminderTitle = '🛡️ Active Hygiene Alert in Your Area';
      reminderBody = 'Check verified Grade A dining spots and safety notices nearby.';
    }

    final payload = jsonEncode({
      'id': latest.id,
      'type': latest.type.name,
      'action_url': latest.actionUrl ?? AppRoutes.notificationCenter,
      'title': latest.title,
      'message': latest.message,
      'data': latest.data,
    });

    await showLocalNotification(
      title: reminderTitle,
      message: reminderBody,
      payload: payload,
      notificationId: 99999,
      channelId: 'hygienetruth_reminders',
      channelName: 'HygieneTruth Reminders & Updates',
    );
  }

  /// Schedule or trigger an unread reminder when the app goes into background
  static void scheduleUnreadReminderOnAppPaused() {
    final unread = unreadCountNotifier.value;
    if (unread > 0) {
      // Delay slightly so it feels like a real incoming message from the server
      Future.delayed(const Duration(seconds: 4), () {
        checkAndSendUnreadReminder();
      });
    }
  }

  /// Send a realistic social-media style incoming notification simulation
  static Future<void> simulateIncomingSocialNotification({
    required String senderName,
    required String messageContent,
    String? targetRoute,
    Map<String, dynamic>? data,
  }) async {
    final title = '💬 $senderName';
    final payloadJson = jsonEncode({
      'type': 'review',
      'action_url': targetRoute ?? AppRoutes.notificationCenter,
      'title': title,
      'message': messageContent,
      'data': data ?? {},
    });

    await showLocalNotification(
      title: title,
      message: messageContent,
      payload: payloadJson,
      channelId: 'hygienetruth_live_alerts',
      channelName: 'HygieneTruth Alerts & Updates',
    );
  }

  static List<AppNotificationModel> _getSeedNotifications(String userId, String role) {
    final now = DateTime.now();
    return [
      AppNotificationModel(
        id: 'seed_notif_001',
        userId: userId,
        title: '🎉 Welcome to HygieneTruth Portal',
        message: 'Your account is verified and protected. Discover clean dining and track hygiene ratings in real time.',
        type: NotificationType.system,
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      AppNotificationModel(
        id: 'seed_notif_002',
        userId: userId,
        title: '🛡️ Safety Patrol Alert',
        message: 'New hygiene inspection grade A awarded to restaurants in Kuala Lumpur Central.',
        type: NotificationType.hygieneAlert,
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      AppNotificationModel(
        id: 'seed_notif_003',
        userId: userId,
        title: '📋 Review Response Received',
        message: 'Owner of "testing" replied to your recent feedback: "hello"',
        type: NotificationType.review,
        actionUrl: 'outlet_testing',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }
}
