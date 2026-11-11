import 'package:shared_preferences/shared_preferences.dart';

enum PortalType {
  customer,
  owner,
  government,
  admin,
}

class RememberMeService {
  static String _getRememberKey(PortalType portal) {
    switch (portal) {
      case PortalType.owner:
        return 'remember_me_owner';
      case PortalType.government:
        return 'remember_me_government';
      case PortalType.admin:
        return 'remember_me_admin';
      case PortalType.customer:
        return 'remember_me_customer';
    }
  }

  static String _getEmailKey(PortalType portal) {
    switch (portal) {
      case PortalType.owner:
        return 'remembered_email_owner';
      case PortalType.government:
        return 'remembered_email_government';
      case PortalType.admin:
        return 'remembered_email_admin';
      case PortalType.customer:
        return 'remembered_email_customer';
    }
  }

  /// Saves or clears the remembered email based on portal type
  static Future<void> saveRememberedUser({
    required bool rememberMe,
    required String email,
    PortalType portal = PortalType.customer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberKey = _getRememberKey(portal);
      final emailKey = _getEmailKey(portal);

      if (rememberMe && email.trim().isNotEmpty) {
        await prefs.setBool(rememberKey, true);
        await prefs.setString(emailKey, email.trim());
      } else {
        await prefs.setBool(rememberKey, false);
        await prefs.remove(emailKey);
      }
    } catch (_) {}
  }

  /// Retrieves the saved Remember Me preference and email for a specific portal
  static Future<Map<String, dynamic>> getRememberedUser({
    PortalType portal = PortalType.customer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clean up legacy non-namespaced keys if present to prevent cross-portal bleed
      if (prefs.containsKey('remember_me')) await prefs.remove('remember_me');
      if (prefs.containsKey('remembered_email')) await prefs.remove('remembered_email');

      final rememberKey = _getRememberKey(portal);
      final emailKey = _getEmailKey(portal);

      final rememberMe = prefs.getBool(rememberKey) ?? false;
      final email = prefs.getString(emailKey) ?? '';
      return {
        'rememberMe': rememberMe && email.isNotEmpty,
        'email': rememberMe ? email : '',
      };
    } catch (_) {
      return {'rememberMe': false, 'email': ''};
    }
  }

  /// Explicitly clear remembered user credentials for a specific portal
  static Future<void> clearRememberedUser({
    PortalType portal = PortalType.customer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_getRememberKey(portal), false);
      await prefs.remove(_getEmailKey(portal));
    } catch (_) {}
  }
}
