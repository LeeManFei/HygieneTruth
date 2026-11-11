import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'customer_store_service.dart';
import 'supabase_service.dart';

/// Manages the application language/locale and persists selection across local storage & Supabase.
class LanguageManager extends ChangeNotifier {
  Locale _locale = const Locale('en', 'US');

  Locale get locale => _locale;

  // Convenient display names, language codes and country flags
  static const List<Map<String, dynamic>> languages = [
    {'name': 'English (US)', 'code': 'en', 'country': 'US', 'label': '🇺🇸 English (US)'},
    {'name': 'Bahasa Malaysia (BM)', 'code': 'ms', 'country': 'MY', 'label': '🇲🇾 Bahasa Melayu (BM)'},
    {'name': 'Chinese (CN)', 'code': 'zh', 'country': 'CN', 'label': '🇨🇳 中文 (CN)'},
  ];

  LanguageManager() {
    _loadLanguage();
  }

  /// Loads the saved language index from SharedPreferences.
  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final langIndex = prefs.getInt('language_index') ?? 0;

      if (langIndex >= 0 && langIndex < languages.length) {
        final lang = languages[langIndex];
        _locale = Locale(lang['code'].toString(), lang['country'].toString());
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Updates the language and persists choice (Local SharedPreferences + Supabase Database).
  Future<void> setLanguage(int index) async {
    if (index < 0 || index >= languages.length) return;

    final lang = languages[index];
    final newLocale = Locale(lang['code'].toString(), lang['country'].toString());

    if (_locale == newLocale) return;

    _locale = newLocale;
    notifyListeners();

    // 1. Local SharedPreferences Persistence
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('language_index', index);
    } catch (_) {}

    // 2. Supabase Database Persistence
    final userId = CustomerStoreService.currentCustomer?.id ?? SupabaseService.client.auth.currentUser?.id;

    if (userId != null && userId.isNotEmpty) {
      try {
        final supabase = SupabaseService.client;
        await supabase
            .from('users')
            .update({'language': index})
            .eq('id', userId);
      } catch (_) {}
    }
  }

  /// Direct sync from database (called after login/restore)
  void updateLanguageFromDatabase(int index) {
    if (index >= 0 && index < languages.length) {
      final lang = languages[index];
      _locale = Locale(lang['code'].toString(), lang['country'].toString());
      notifyListeners();
    }
  }

  /// Reset to default English (called after logout)
  Future<void> resetToDefault() async {
    _locale = const Locale('en', 'US');
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('language_index');
    } catch (_) {}
  }
}

// Global instance matching mobile_project
final languageManager = LanguageManager();
