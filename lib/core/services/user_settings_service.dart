import 'audit_log_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class UserSettings {
  final ThemeMode themeMode;
  final bool enablePushNotifications;
  final bool hygieneRiskAlerts;
  final bool complaintStatusAlerts;
  final bool inspectionUpdates;
  final String selectedLanguage;

  const UserSettings({
    this.themeMode = ThemeMode.system,
    this.enablePushNotifications = true,
    this.hygieneRiskAlerts = true,
    this.complaintStatusAlerts = true,
    this.inspectionUpdates = true,
    this.selectedLanguage = 'English',
  });

  UserSettings copyWith({
    ThemeMode? themeMode,
    bool? enablePushNotifications,
    bool? hygieneRiskAlerts,
    bool? complaintStatusAlerts,
    bool? inspectionUpdates,
    String? selectedLanguage,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      enablePushNotifications: enablePushNotifications ?? this.enablePushNotifications,
      hygieneRiskAlerts: hygieneRiskAlerts ?? this.hygieneRiskAlerts,
      complaintStatusAlerts: complaintStatusAlerts ?? this.complaintStatusAlerts,
      inspectionUpdates: inspectionUpdates ?? this.inspectionUpdates,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
    );
  }
}

class UserSettingsService {
  static String _getKey(String userId, String key) {
    final cleanId = userId.trim().isEmpty ? 'guest_default' : userId.trim();
    return 'user_setting_${cleanId}_$key';
  }

  /// Loads user settings from SharedPreferences and syncs with Supabase if logging in on a new device
  static Future<UserSettings> loadUserSettings(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty || cleanId == 'guest_default') {
      // Outside UI (Pre-login / Logout) always displays clean System Theme
      return const UserSettings(themeMode: ThemeMode.system);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Attempt reading local SharedPreferences
      int? themeIndex = prefs.getInt(_getKey(cleanId, 'theme_mode'));
      bool? push = prefs.getBool(_getKey(cleanId, 'enable_push'));
      bool? risk = prefs.getBool(_getKey(cleanId, 'risk_alerts'));
      bool? complaint = prefs.getBool(_getKey(cleanId, 'complaint_alerts'));
      bool? inspection = prefs.getBool(_getKey(cleanId, 'inspection_updates'));
      String? lang = prefs.getString(_getKey(cleanId, 'language'));

      // 2. If missing locally, fetch cloud settings from Supabase users table
      if (themeIndex == null) {
        try {
          final supabase = SupabaseService.client;
          final Map<String, dynamic>? userRow = await supabase
              .from('users')
              .select('theme_mode, settings')
              .eq('id', cleanId)
              .maybeSingle();

          if (userRow != null) {
            final String remoteTheme = userRow['theme_mode']?.toString() ?? 'system';
            if (remoteTheme == 'light') {
              themeIndex = 0;
            } else if (remoteTheme == 'dark') {
              themeIndex = 2;
            } else {
              themeIndex = 1;
            }

            await prefs.setInt(_getKey(cleanId, 'theme_mode'), themeIndex);

            final Map<String, dynamic>? remoteSettings = userRow['settings'] as Map<String, dynamic>?;
            if (remoteSettings != null) {
              push = remoteSettings['enable_push'] as bool?;
              risk = remoteSettings['risk_alerts'] as bool?;
              complaint = remoteSettings['complaint_alerts'] as bool?;
              inspection = remoteSettings['inspection_updates'] as bool?;
              lang = remoteSettings['language']?.toString();

              if (push != null) await prefs.setBool(_getKey(cleanId, 'enable_push'), push);
              if (risk != null) await prefs.setBool(_getKey(cleanId, 'risk_alerts'), risk);
              if (complaint != null) await prefs.setBool(_getKey(cleanId, 'complaint_alerts'), complaint);
              if (inspection != null) await prefs.setBool(_getKey(cleanId, 'inspection_updates'), inspection);
              if (lang != null) await prefs.setString(_getKey(cleanId, 'language'), lang);
            }
          }
        } catch (_) {}
      }

      themeIndex ??= 1;
      ThemeMode mode = ThemeMode.system;
      if (themeIndex == 0) mode = ThemeMode.light;
      if (themeIndex == 2) mode = ThemeMode.dark;

      return UserSettings(
        themeMode: mode,
        enablePushNotifications: push ?? true,
        hygieneRiskAlerts: risk ?? true,
        complaintStatusAlerts: complaint ?? true,
        inspectionUpdates: inspection ?? true,
        selectedLanguage: lang ?? 'English',
      );
    } catch (_) {
      return const UserSettings();
    }
  }

  /// Persists theme mode locally in SharedPreferences AND remote Supabase database
  static Future<void> saveThemeMode(String userId, ThemeMode mode) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty || cleanId == 'guest_default') return;

    try {
      final prefs = await SharedPreferences.getInstance();
      int index = 1;
      String modeStr = 'system';
      if (mode == ThemeMode.light) {
        index = 0;
        modeStr = 'light';
      }
      if (mode == ThemeMode.dark) {
        index = 2;
        modeStr = 'dark';
      }
      await prefs.setInt(_getKey(cleanId, 'theme_mode'), index);

      // Sync to Supabase users table
      try {
        await SupabaseService.client.from('users').update({
          'theme_mode': modeStr,
        }).eq('id', cleanId);
      } catch (_) {}

      AuditLogService.logAction(
        actionType: 'THEME_CHANGE',
        category: 'Preferences',
        title: 'App Theme Changed',
        description: 'Switched display theme to ${modeStr.toUpperCase()} mode',
        userId: cleanId,
      );
    } catch (_) {}
  }

  /// Persists toggle setting locally AND remote Supabase database
  static Future<void> saveBool(String userId, String key, bool value) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty || cleanId == 'guest_default') return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_getKey(cleanId, key), value);

      // Sync to Supabase user settings JSON
      try {
        final currentSettings = (await loadUserSettings(cleanId));
        final settingsMap = {
          'enable_push': key == 'enable_push' ? value : currentSettings.enablePushNotifications,
          'risk_alerts': key == 'risk_alerts' ? value : currentSettings.hygieneRiskAlerts,
          'complaint_alerts': key == 'complaint_alerts' ? value : currentSettings.complaintStatusAlerts,
          'inspection_updates': key == 'inspection_updates' ? value : currentSettings.inspectionUpdates,
          'language': currentSettings.selectedLanguage,
        };

        await SupabaseService.client.from('users').update({
          'settings': settingsMap,
        }).eq('id', cleanId);
      } catch (_) {}

      final String readableKey = key == 'enable_push'
          ? 'Push Notifications'
          : (key == 'risk_alerts'
              ? 'Hygiene Risk Alerts'
              : (key == 'complaint_alerts' ? 'Complaint Status Alerts' : 'Inspection Updates'));
      AuditLogService.logAction(
        actionType: 'NOTIFICATION_TOGGLE',
        category: 'Notifications',
        title: '$readableKey ${value ? "Enabled" : "Disabled"}',
        description: '${value ? "Activated" : "Deactivated"} preference for $readableKey',
        userId: cleanId,
      );
    } catch (_) {}
  }

  /// Persists string setting locally AND remote Supabase database
  static Future<void> saveString(String userId, String key, String value) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty || cleanId == 'guest_default') return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_getKey(cleanId, key), value);

      try {
        final currentSettings = (await loadUserSettings(cleanId));
        final settingsMap = {
          'enable_push': currentSettings.enablePushNotifications,
          'risk_alerts': currentSettings.hygieneRiskAlerts,
          'complaint_alerts': currentSettings.complaintStatusAlerts,
          'inspection_updates': currentSettings.inspectionUpdates,
          'language': key == 'language' ? value : currentSettings.selectedLanguage,
        };

        await SupabaseService.client.from('users').update({
          'settings': settingsMap,
        }).eq('id', cleanId);
      } catch (_) {}

      if (key == 'language') {
        AuditLogService.logAction(
          actionType: 'LANGUAGE_CHANGE',
          category: 'Preferences',
          title: 'Language Updated',
          description: 'Changed application language to $value',
          userId: cleanId,
        );
      }
    } catch (_) {}
  }
}
