import 'package:flutter/material.dart';
import '../services/user_settings_service.dart';

class ThemeManager extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _activeUserId = 'guest_default';

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  String get activeUserId => _activeUserId;

  ThemeManager() {
    resetToSystemTheme();
  }

  /// Resets theme to clean system default (used for pre-login, Login/Register screens, and logout)
  void resetToSystemTheme() {
    _activeUserId = 'guest_default';
    if (_themeMode != ThemeMode.system) {
      _themeMode = ThemeMode.system;
      notifyListeners();
    }
  }

  /// Loads the theme mode saved for a specific user ID (from SharedPreferences + Supabase cloud sync)
  Future<void> loadThemeForUser(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty || cleanId == 'guest_default') {
      resetToSystemTheme();
      return;
    }

    _activeUserId = cleanId;
    final settings = await UserSettingsService.loadUserSettings(cleanId);
    _themeMode = settings.themeMode;
    notifyListeners();
  }

  /// Saves theme mode to active user profile (Local SharedPreferences + Supabase Database)
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    if (_activeUserId.isNotEmpty && _activeUserId != 'guest_default') {
      await UserSettingsService.saveThemeMode(_activeUserId, mode);
    }
  }
}

// Global instance
final themeManager = ThemeManager();
