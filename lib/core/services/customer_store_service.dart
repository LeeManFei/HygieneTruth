import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../routes/app_routes.dart';
import '../theme/theme_manager.dart';
import '../utils/hygiene_feedback.dart';
import '../utils/uuid_helper.dart';
import 'audit_log_service.dart';
import 'language_manager.dart';
import 'remember_me_service.dart';
import 'restaurant_store_service.dart';
import 'supabase_service.dart';

class CustomerAuthResult {
  final bool success;
  final String message;
  final UserModel? user;
  final bool isAccountNotFound;

  const CustomerAuthResult({
    required this.success,
    required this.message,
    this.user,
    this.isAccountNotFound = false,
  });
}

class CustomerStoreService {
  static const String _kOnboardingCompletedKey = 'onboarding_completed';
  static const String _kUserSessionJsonKey = 'user_session_json';
  static const String _kUserSessionLastActiveKey = 'user_session_last_active';
  static const String _kUserLastPortalKey = 'user_last_portal';
  static const int maxInactivityDurationMs =
      3 * 60 * 60 * 1000; // 3 hours (10,800,000 ms)

  /// Incremented whenever a user logs in, restores a session, or logs out
  static int sessionGeneration = 0;

  /// Returns true if the user has completed or skipped the onboarding flow
  static Future<bool> isOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kOnboardingCompletedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets the onboarding completion flag in persistent local storage
  static Future<void> setOnboardingCompleted(bool completed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboardingCompletedKey, completed);
    } catch (_) {}
  }

  /// Helper to convert portal string or role to standard portal login route
  static String getPortalLoginRoute([String? portalStr]) {
    final p = portalStr?.toLowerCase().trim();
    if (p == 'owner' || p == 'businessman') {
      return AppRoutes.ownerLogin;
    } else if (p == 'admin' || p == 'government' || p == 'officer') {
      return AppRoutes.adminGovLogin;
    }
    return AppRoutes.login;
  }

  /// Retrieves the saved last portal login route
  static Future<String> getLastPortalLoginRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPortal = prefs.getString(_kUserLastPortalKey) ?? 'customer';
      return getPortalLoginRoute(lastPortal);
    } catch (_) {
      return AppRoutes.login;
    }
  }

  /// Resolves the role dashboard route
  static String getRoleDashboardRoute(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return AppRoutes.adminDashboard;
      case UserRole.government:
        return AppRoutes.governmentDashboard;
      case UserRole.owner:
        return AppRoutes.ownerDashboard;
      case UserRole.user:
        return AppRoutes.userDashboard;
    }
  }

  /// Saves active user session to in-memory memory and persistent local storage
  static Future<void> saveSession(UserModel user, {PortalType? portal}) async {
    sessionGeneration++;
    _currentCustomer = user;
    final String portalStr = portal != null
        ? portal.name
        : (user.role == UserRole.owner
              ? 'owner'
              : (user.role == UserRole.admin
                    ? 'admin'
                    : (user.role == UserRole.government
                          ? 'government'
                          : 'customer')));

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserSessionJsonKey, jsonEncode(user.toMap()));
      await prefs.setInt(
        _kUserSessionLastActiveKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setString(_kUserLastPortalKey, portalStr);
    } catch (_) {}
  }

  /// Updates last active timestamp in persistent local memory
  static Future<void> updateLastActive() async {
    if (_currentCustomer == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kUserSessionLastActiveKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Resolves the initial route on app launch (handling Onboarding, Session Persistence, and Inactivity Timeout)
  static Future<String> resolveInitialAppRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Check if Onboarding was completed
      final bool onboardingDone =
          prefs.getBool(_kOnboardingCompletedKey) ?? false;
      if (!onboardingDone) {
        return AppRoutes.onboarding;
      }

      // 2. Check Session & 3-Hour Inactivity Timeout
      final String? sessionJson = prefs.getString(_kUserSessionJsonKey);
      final int? lastActive = prefs.getInt(_kUserSessionLastActiveKey);
      final String lastPortal =
          prefs.getString(_kUserLastPortalKey) ?? 'customer';

      if (sessionJson != null && sessionJson.isNotEmpty && lastActive != null) {
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int elapsed = now - lastActive;

        if (elapsed <= maxInactivityDurationMs) {
          // Session is VALID! Restore into memory
          try {
            final Map<String, dynamic> userMap = jsonDecode(sessionJson);
            final restoredUser = UserModel.fromMap(userMap);
            final authUser = SupabaseService.client.auth.currentUser;
            if (authUser == null || authUser.id != restoredUser.id) {
              await prefs.remove(_kUserSessionJsonKey);
              await prefs.remove(_kUserSessionLastActiveKey);
              _currentCustomer = null;
              return getPortalLoginRoute(lastPortal);
            }

            final verifiedProfile = await SupabaseService.client
                .from('users')
                .select('id, role, status')
                .eq('id', authUser.id)
                .maybeSingle();
            final verifiedStatus = verifiedProfile?['status']
                ?.toString()
                .toLowerCase();
            final verifiedRole = verifiedProfile?['role']
                ?.toString()
                .toLowerCase();
            final restoredRole = restoredUser.role.name.toLowerCase();
            final roleMatches =
                verifiedRole == restoredRole ||
                (verifiedRole == 'customer' && restoredRole == 'user') ||
                (verifiedRole == 'businessman' && restoredRole == 'owner') ||
                (verifiedRole == 'officer' && restoredRole == 'government');
            if (verifiedProfile == null ||
                verifiedStatus != 'active' ||
                !roleMatches) {
              await SupabaseService.client.auth.signOut();
              await prefs.remove(_kUserSessionJsonKey);
              await prefs.remove(_kUserSessionLastActiveKey);
              _currentCustomer = null;
              return getPortalLoginRoute(lastPortal);
            }
            _currentCustomer = restoredUser;
            sessionGeneration++;

            // Refresh last active timestamp
            await prefs.setInt(_kUserSessionLastActiveKey, now);

            // Load user customized theme
            await themeManager.loadThemeForUser(restoredUser.id);

            // Return dashboard route for restored role
            return getRoleDashboardRoute(restoredUser.role);
          } catch (_) {}
        } else {
          // Expired due to 3 hours inactivity! Clear active session but preserve last portal
          await prefs.remove(_kUserSessionJsonKey);
          await prefs.remove(_kUserSessionLastActiveKey);
          _currentCustomer = null;
        }
      }

      // 3. Fallback to last logged-in portal login screen
      return getPortalLoginRoute(lastPortal);
    } catch (_) {
      return AppRoutes.login;
    }
  }

  /// Validates session timeout when app resumes from background
  static Future<bool> checkInactivityTimeout({
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    if (_currentCustomer == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? lastActive = prefs.getInt(_kUserSessionLastActiveKey);
      if (lastActive != null) {
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int elapsed = now - lastActive;

        if (elapsed > maxInactivityDurationMs) {
          final destination = await logout();
          if (navigatorKey?.currentState != null) {
            navigatorKey!.currentState!.pushNamedAndRemoveUntil(
              destination,
              (route) => false,
            );
            final ctx = navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              HygieneFeedback.showWarning(
                ctx,
                'Session expired after 3 hours of inactivity. Please log in again.',
              );
            }
          }
          return true; // Timed out
        } else {
          // Still active, refresh timestamp
          await prefs.setInt(_kUserSessionLastActiveKey, now);
        }
      }
    } catch (_) {}
    return false;
  }

  static List<UserModel> getAllRegisteredCustomers() {
    return _registeredCustomers.entries
        .map(
          (e) => UserModel(
            id: e.key,
            name: e.key.split('@').first,
            email: e.key,
            phone: '',
            role: e.value['role'] == 'businessman'
                ? UserRole.owner
                : UserRole.user,
            status: AccountStatus.active,
            avatarUrl: '',
          ),
        )
        .toList();
  }

  static UserModel? _currentCustomer;

  static UserModel? get currentCustomer => _currentCustomer;

  static final Map<String, Map<String, String>> _registeredCustomers = {};

  /// Fetches real user profile for the current active Supabase Auth session or current customer
  static Future<UserModel?> fetchActiveUserSession() async {
    try {
      final supabase = SupabaseService.client;
      final sessionUser = supabase.auth.currentUser;

      String? targetUserId = sessionUser?.id ?? _currentCustomer?.id;
      String? targetUserEmail = sessionUser?.email ?? _currentCustomer?.email;

      if (targetUserId == null &&
          (targetUserEmail == null || targetUserEmail.isEmpty)) {
        return _currentCustomer;
      }

      // Query real user row from public.users table in Supabase
      Map<String, dynamic>? data;
      if (targetUserId != null && targetUserId.isNotEmpty) {
        try {
          data = await supabase
              .from('users')
              .select()
              .eq('id', targetUserId)
              .maybeSingle();
        } catch (_) {}
      }

      if (data == null &&
          targetUserEmail != null &&
          targetUserEmail.isNotEmpty) {
        try {
          data = await supabase
              .from('users')
              .select()
              .eq('email', targetUserEmail.trim().toLowerCase())
              .maybeSingle();
        } catch (_) {}
      }

      final String finalId =
          data?['id']?.toString() ?? targetUserId ?? UuidHelper.generateV4();
      final String finalEmail =
          data?['email']?.toString() ?? targetUserEmail ?? '';

      String name =
          sessionUser?.userMetadata?['name'] as String? ??
          (finalEmail.isNotEmpty ? finalEmail.split('@').first : 'User');
      String? phone;
      String? gender;
      String? country;
      String? state;
      String avatarUrl = '';
      UserRole userRole = _currentCustomer?.role ?? UserRole.user;

      if (data != null) {
        name = data['name']?.toString() ?? name;
        phone = data['phone']?.toString();
        gender = data['gender']?.toString();
        country = data['country']?.toString();
        state = data['state']?.toString();
        if (data['avatar_url'] != null &&
            data['avatar_url'].toString().trim().isNotEmpty) {
          avatarUrl = data['avatar_url'].toString().trim();
        }
        if (data['role'] != null) {
          final r = data['role'].toString().toLowerCase();
          userRole = (r == 'businessman' || r == 'owner')
              ? UserRole.owner
              : (r == 'admin'
                    ? UserRole.admin
                    : (r == 'government'
                          ? UserRole.government
                          : UserRole.user));
        }
        if (data['language'] != null) {
          final langIdx = int.tryParse(data['language'].toString());
          if (langIdx != null) {
            languageManager.updateLanguageFromDatabase(langIdx);
          }
        }
        if (data['settings'] is Map) {
          final settings = data['settings'] as Map<String, dynamic>;
          if (settings['google_linked'] is Map) {
            _cachedGoogleLinkedEmail = settings['google_linked']['email']
                ?.toString();
          } else if (settings['google_email'] != null) {
            _cachedGoogleLinkedEmail = settings['google_email']?.toString();
          }
        }
      }

      String? bannerUrl;
      if (data != null) {
        if (data['banner_url'] != null &&
            data['banner_url'].toString().trim().isNotEmpty) {
          bannerUrl = data['banner_url'].toString().trim();
        } else if (data['settings'] is Map &&
            (data['settings'] as Map)['banner_url'] != null) {
          bannerUrl = (data['settings'] as Map)['banner_url']
              ?.toString()
              .trim();
        }
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        _cachedGoogleLinkedEmail ??=
            prefs.getString('google_linked_email_$finalId') ??
            prefs.getString('google_linked_email_$finalEmail');
        bannerUrl ??=
            prefs.getString('user_banner_url_$finalId') ??
            prefs.getString('user_banner_url_$finalEmail');
      } catch (_) {}

      String? joinedDate;
      final rawCreated =
          data?['created_at']?.toString() ??
          sessionUser?.createdAt ??
          _currentCustomer?.joinedDate;
      if (rawCreated != null && rawCreated.isNotEmpty) {
        final dt = DateTime.tryParse(rawCreated);
        if (dt != null) {
          final DateTime msiaDt = dt.toUtc().add(const Duration(hours: 8));
          joinedDate =
              '${msiaDt.day} ${_monthName(msiaDt.month)} ${msiaDt.year}';
        }
      }

      if (joinedDate == null || joinedDate.isEmpty) {
        final nowMsia = DateTime.now().toUtc().add(const Duration(hours: 8));
        joinedDate =
            '${nowMsia.day} ${_monthName(nowMsia.month)} ${nowMsia.year}';
      }

      _currentCustomer = UserModel(
        id: finalId,
        name: name,
        email: finalEmail,
        phone: phone,
        role: userRole,
        status: AccountStatus.active,
        avatarUrl: avatarUrl,
        bannerUrl: bannerUrl,
        gender: gender,
        country: country,
        state: state,
        joinedDate: joinedDate,
      );

      themeManager.loadThemeForUser(finalId);

      return _currentCustomer;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching active Supabase session user profile: $e');
      }
      return _currentCustomer;
    }
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  static String? _cachedGoogleLinkedEmail;

  /// Checks if current Supabase session or user profile is linked to a Google auth provider
  static bool isGoogleLinked() {
    if (_cachedGoogleLinkedEmail != null &&
        _cachedGoogleLinkedEmail!.trim().isNotEmpty) {
      return true;
    }
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      final provider = user.appMetadata['provider']?.toString();
      if (provider == 'google') return true;
      final identities = user.identities;
      if (identities != null) {
        return identities.any((id) => id.provider.toLowerCase() == 'google');
      }
    }
    return false;
  }

  /// Returns linked Google account email address if available
  static String getGoogleLinkedEmail() {
    if (_cachedGoogleLinkedEmail != null &&
        _cachedGoogleLinkedEmail!.trim().isNotEmpty) {
      return _cachedGoogleLinkedEmail!;
    }
    final user = SupabaseService.client.auth.currentUser;
    if (user != null && isGoogleLinked()) {
      return user.email ?? '';
    }
    return '';
  }

  /// Links / binds a Google account to the currently logged in profile
  static Future<CustomerAuthResult> linkGoogleAccount() async {
    try {
      final supabase = SupabaseService.client;
      String? envClientId;
      try {
        if (dotenv.isInitialized) {
          envClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
        }
      } catch (_) {}
      final String webClientId =
          envClientId ??
          '927326709623-332ted8aosmjf5efmbq3if09ur98vtl5.apps.googleusercontent.com';

      // 1. Initialize Native Google Sign-In SDK
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        scopes: ['email', 'profile'],
      );

      // Clear any stale cached session to prevent reauth issues
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return const CustomerAuthResult(
          success: false,
          message: 'Google link operation was cancelled.',
        );
      }

      final String gEmail = googleUser.email;
      final String gName = googleUser.displayName ?? gEmail.split('@').first;
      final String? gAvatar = googleUser.photoUrl;

      final currentCust = _currentCustomer;
      final authUser = supabase.auth.currentUser;
      final String? userId = currentCust?.id ?? authUser?.id;
      final String? userEmail = currentCust?.email ?? authUser?.email;

      if (authUser == null ||
          currentCust == null ||
          authUser.id != currentCust.id) {
        return const CustomerAuthResult(
          success: false,
          message:
              'Please sign in with your email and password again before linking Google.',
        );
      }
      if (gEmail.trim().toLowerCase() !=
          currentCust.email.trim().toLowerCase()) {
        await googleSignIn.signOut();
        return const CustomerAuthResult(
          success: false,
          message:
              'Please choose the Google account with the same email as your profile.',
        );
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        return const CustomerAuthResult(
          success: false,
          message: 'Google account verification failed. Please try again.',
        );
      }
      final linked = await supabase.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );
      if (linked.user?.id != currentCust.id) {
        throw const AuthException(
          'Linked identity does not match the signed-in profile.',
        );
      }

      // 3. Persist binding to Supabase users table settings column
      if (userId != null || (userEmail != null && userEmail.isNotEmpty)) {
        try {
          Map<String, dynamic>? userRow;
          if (userId != null && userId.isNotEmpty) {
            userRow = await supabase
                .from('users')
                .select('id, settings')
                .eq('id', userId)
                .maybeSingle();
          }
          if (userRow == null && userEmail != null && userEmail.isNotEmpty) {
            userRow = await supabase
                .from('users')
                .select('id, settings')
                .eq('email', userEmail)
                .maybeSingle();
          }

          Map<String, dynamic> settings = {};
          if (userRow != null && userRow['settings'] is Map) {
            settings = Map<String, dynamic>.from(userRow['settings'] as Map);
          }

          settings['google_linked'] = {
            'email': gEmail,
            'name': gName,
            'avatar': gAvatar,
            'linked_at': DateTime.now().toUtc().toIso8601String(),
          };
          settings['google_email'] = gEmail;

          final String targetId = userRow?['id']?.toString() ?? userId ?? '';
          if (targetId.isNotEmpty) {
            await supabase
                .from('users')
                .update({'settings': settings})
                .eq('id', targetId);
          } else if (userEmail != null && userEmail.isNotEmpty) {
            await supabase
                .from('users')
                .update({'settings': settings})
                .eq('email', userEmail);
          }
          debugPrint(
            'CustomerStoreService: Google account ($gEmail) linked in Supabase users.settings!',
          );
        } catch (dbErr) {
          debugPrint('Error updating google_linked in Supabase: $dbErr');
        }
      }

      // 4. Save to local device storage
      _cachedGoogleLinkedEmail = gEmail;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (userId != null) {
          await prefs.setString('google_linked_email_$userId', gEmail);
        }
        if (userEmail != null) {
          await prefs.setString('google_linked_email_$userEmail', gEmail);
        }
      } catch (_) {}

      // 5. Audit Log
      AuditLogService.logAction(
        actionType: 'GOOGLE_ACCOUNT_LINKED',
        category: 'Security',
        title: 'Google Account Linked',
        description: 'Successfully bound Google account ($gEmail) to profile',
        userId: userId ?? '',
        userEmail: userEmail ?? gEmail,
      );

      return CustomerAuthResult(
        success: true,
        message:
            'Google account ($gEmail) successfully linked to your profile!',
      );
    } catch (e) {
      debugPrint('Error in linkGoogleAccount: $e');
      return const CustomerAuthResult(
        success: false,
        message:
            'Google account could not be linked. Please verify the account and try again.',
      );
    }
  }

  /// Unlinks Google account from current profile
  static Future<CustomerAuthResult> unlinkGoogleAccount() async {
    try {
      final supabase = SupabaseService.client;
      final currentCust = _currentCustomer;
      final String? userId = currentCust?.id ?? supabase.auth.currentUser?.id;
      final String? userEmail =
          currentCust?.email ?? supabase.auth.currentUser?.email;

      if (userId != null || (userEmail != null && userEmail.isNotEmpty)) {
        try {
          Map<String, dynamic>? userRow;
          if (userId != null && userId.isNotEmpty) {
            userRow = await supabase
                .from('users')
                .select('id, settings')
                .eq('id', userId)
                .maybeSingle();
          }
          if (userRow == null && userEmail != null && userEmail.isNotEmpty) {
            userRow = await supabase
                .from('users')
                .select('id, settings')
                .eq('email', userEmail)
                .maybeSingle();
          }

          if (userRow != null && userRow['settings'] is Map) {
            final settings = Map<String, dynamic>.from(
              userRow['settings'] as Map,
            );
            settings.remove('google_linked');
            settings.remove('google_email');
            final String targetId = userRow['id']?.toString() ?? userId ?? '';
            if (targetId.isNotEmpty) {
              await supabase
                  .from('users')
                  .update({'settings': settings})
                  .eq('id', targetId);
            }
          }
        } catch (_) {}
      }

      _cachedGoogleLinkedEmail = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (userId != null) await prefs.remove('google_linked_email_$userId');
        if (userEmail != null) {
          await prefs.remove('google_linked_email_$userEmail');
        }
      } catch (_) {}

      AuditLogService.logAction(
        actionType: 'GOOGLE_ACCOUNT_UNLINKED',
        category: 'Security',
        title: 'Google Account Unlinked',
        description: 'Unlinked Google account connection from profile',
        userId: userId ?? '',
        userEmail: userEmail ?? '',
      );

      return const CustomerAuthResult(
        success: true,
        message: 'Google account unlinked successfully.',
      );
    } catch (e) {
      return CustomerAuthResult(
        success: false,
        message: 'Failed to unlink Google account: $e',
      );
    }
  }

  /// Updates user profile details in Supabase database and active session
  static Future<bool> updateCustomerProfile({
    required String name,
    String? email,
    String? phone,
    String? gender,
    String? country,
    String? state,
    String? avatarUrl,
    String? bannerUrl,
  }) async {
    try {
      final supabase = SupabaseService.client;
      final sessionUser = supabase.auth.currentUser;
      final targetId = sessionUser?.id ?? _currentCustomer?.id;
      final targetEmail = _currentCustomer?.email ?? email;

      final Map<String, dynamic> updateData = {
        'name': name.trim(),
        'phone': phone?.trim(),
        'gender': gender,
        'country': country,
        'state': state,
      };
      if (email != null && email.trim().isNotEmpty) {
        updateData['email'] = email.trim().toLowerCase();
      }
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        updateData['avatar_url'] = avatarUrl;
      }
      if (bannerUrl != null) {
        updateData['banner_url'] = bannerUrl;
      }

      bool updated = false;
      if (targetId != null && targetId.isNotEmpty) {
        try {
          final res = await supabase
              .from('users')
              .update(updateData)
              .eq('id', targetId)
              .select();
          if (res.isNotEmpty) {
            updated = true;
          }
        } catch (_) {
          // If banner_url column does not exist on Supabase table schema, save to settings JSON column
          try {
            final fallbackData = Map<String, dynamic>.from(updateData)
              ..remove('banner_url');
            if (bannerUrl != null) {
              fallbackData['settings'] = {'banner_url': bannerUrl};
            }
            final res = await supabase
                .from('users')
                .update(fallbackData)
                .eq('id', targetId)
                .select();
            if (res.isNotEmpty) {
              updated = true;
            }
          } catch (_) {}
        }
      }

      if (!updated && targetEmail != null && targetEmail.isNotEmpty) {
        try {
          await supabase
              .from('users')
              .update(updateData)
              .eq('email', targetEmail.trim().toLowerCase());
          updated = true;
        } catch (_) {
          try {
            final fallbackData = Map<String, dynamic>.from(updateData)
              ..remove('banner_url');
            if (bannerUrl != null) {
              fallbackData['settings'] = {'banner_url': bannerUrl};
            }
            await supabase
                .from('users')
                .update(fallbackData)
                .eq('email', targetEmail.trim().toLowerCase());
            updated = true;
          } catch (_) {}
        }
      }

      if (bannerUrl != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (targetId != null) {
            await prefs.setString('user_banner_url_$targetId', bannerUrl);
          }
          if (targetEmail != null) {
            await prefs.setString('user_banner_url_$targetEmail', bannerUrl);
          }
        } catch (_) {}
      }

      final oldName = _currentCustomer?.name;
      bool nameChanged =
          (_currentCustomer != null && _currentCustomer!.name != name.trim());
      if (_currentCustomer != null) {
        _currentCustomer = _currentCustomer!.copyWith(
          name: name.trim(),
          email: (email != null && email.trim().isNotEmpty)
              ? email.trim().toLowerCase()
              : _currentCustomer!.email,
          phone: phone?.trim(),
          avatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty)
              ? avatarUrl
              : _currentCustomer!.avatarUrl,
          bannerUrl: bannerUrl ?? _currentCustomer!.bannerUrl,
          gender: gender,
          country: country,
          state: state,
        );
      }

      // Propagate updated name & avatar across all reviews authored by this user
      try {
        await RestaurantStoreService.propagateUserProfileUpdateToReviews(
          userId: targetId,
          userEmail: targetEmail,
          newName: name.trim(),
          newAvatar: avatarUrl ?? _currentCustomer?.avatarUrl,
          oldName: oldName,
        );
      } catch (_) {}

      if (nameChanged) {
        AuditLogService.logAction(
          actionType: 'NAME_CHANGE',
          category: 'Account Modification',
          title: 'User Name Changed',
          description: 'Updated account full name to "${name.trim()}"',
        );
      } else {
        AuditLogService.logAction(
          actionType: 'PROFILE_UPDATED',
          category: 'Account Modification',
          title: 'Profile Details Updated',
          description:
              'User updated profile contact, regional details & banner',
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating customer profile: $e');
      }
      return false;
    }
  }

  static Future<CustomerAuthResult> registerCustomer({
    required String name,
    required String email,
    required String password,
    UserRole role = UserRole.user,
    String? gender,
    String? country,
    String? state,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();

    // 1. Strict Input Validation
    if (cleanName.isEmpty || cleanEmail.isEmpty || password.isEmpty) {
      return const CustomerAuthResult(
        success: false,
        message: 'Please fill in all required fields.',
      );
    }

    if (cleanName.length < 2) {
      return const CustomerAuthResult(
        success: false,
        message: 'Name must be at least 2 characters long.',
      );
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(cleanEmail)) {
      return const CustomerAuthResult(
        success: false,
        message: 'Please enter a valid email address.',
      );
    }

    if (password.length < 6) {
      return const CustomerAuthResult(
        success: false,
        message: 'Password must be at least 6 characters long.',
      );
    }

    final supabase = SupabaseService.client;

    // 2. Strict Duplicate Email Verification Check in Database & Local Store
    Map<String, dynamic>? existingDbUser;
    try {
      existingDbUser = await supabase
          .from('users')
          .select('id, email, name, role')
          .ilike('email', cleanEmail)
          .maybeSingle();
    } catch (e) {
      if (kDebugMode) {
        print('Error checking existing user in Supabase: $e');
      }
    }

    if (existingDbUser != null ||
        _registeredCustomers.containsKey(cleanEmail)) {
      return const CustomerAuthResult(
        success: false,
        message:
            'This email address is already registered. Please log in or use a different email.',
      );
    }

    final String roleStr = role == UserRole.owner
        ? 'businessman'
        : (role == UserRole.admin
              ? 'admin'
              : (role == UserRole.government ? 'government' : 'customer'));

    // Hash password with BCrypt (logRounds: 6 matching $2a$06$ format)
    final String hashedPassword = BCrypt.hashpw(
      password,
      BCrypt.gensalt(logRounds: 6),
    );

    // 3. Supabase Auth Registration
    String? userId;
    try {
      final res = await supabase.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'name': cleanName, 'role': roleStr},
      );
      userId = res.user?.id;
    } on AuthException catch (authErr) {
      final msg = authErr.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('already exists') ||
          msg.contains('user already') ||
          authErr.statusCode == '422' ||
          authErr.statusCode == '400') {
        return const CustomerAuthResult(
          success: false,
          message:
              'This email address is already registered. Please log in or use a different email.',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Supabase auth.signUp info: $e');
      }
    }

    userId ??= UuidHelper.generateV4();
    final nowUtc = DateTime.now().toUtc();
    final nowMsia = nowUtc.add(const Duration(hours: 8));
    final String formattedJoinedDate =
        '${nowMsia.day} ${_monthName(nowMsia.month)} ${nowMsia.year}';

    final Map<String, dynamic> userPayload = {
      'id': userId,
      'name': cleanName,
      'email': cleanEmail,
      'user_password': hashedPassword,
      'role': roleStr,
      'status': 'active',
    };

    if (gender != null && gender.trim().isNotEmpty) {
      userPayload['gender'] = gender.trim();
    }
    if (country != null && country.trim().isNotEmpty) {
      userPayload['country'] = country.trim();
    }
    if (state != null && state.trim().isNotEmpty) {
      userPayload['state'] = state.trim();
    }

    // 4. Strictly persist and enforce role into public.users table
    try {
      await supabase.from('users').upsert(userPayload, onConflict: 'email');
    } catch (e) {
      try {
        await supabase
            .from('users')
            .update({
              'name': cleanName,
              'user_password': hashedPassword,
              'role': roleStr,
              'status': 'active',
              if (gender != null && gender.trim().isNotEmpty)
                'gender': gender.trim(),
              if (country != null && country.trim().isNotEmpty)
                'country': country.trim(),
              if (state != null && state.trim().isNotEmpty)
                'state': state.trim(),
            })
            .eq('email', cleanEmail);
      } catch (err) {
        if (kDebugMode) {
          print('Error persisting user to Supabase users table: $err');
        }
      }
    }

    _registeredCustomers[cleanEmail] = {
      'id': userId,
      'name': name.trim(),
      'email': cleanEmail,
      'password': password,
      'role': roleStr,
    };

    _currentCustomer = UserModel(
      id: userId,
      name: name.trim(),
      email: cleanEmail,
      phone: null,
      role: role,
      status: AccountStatus.active,
      avatarUrl: '',
      gender: gender?.trim(),
      country: country?.trim(),
      state: state?.trim(),
      joinedDate: formattedJoinedDate,
    );

    final PortalType targetPortal = role == UserRole.owner
        ? PortalType.owner
        : (role == UserRole.government
              ? PortalType.government
              : (role == UserRole.admin
                    ? PortalType.admin
                    : PortalType.customer));

    await RememberMeService.saveRememberedUser(
      rememberMe: true,
      email: cleanEmail,
      portal: targetPortal,
    );

    await saveSession(_currentCustomer!, portal: targetPortal);

    await themeManager.loadThemeForUser(_currentCustomer!.id);

    final String auditCategory = role == UserRole.owner
        ? 'Businessman'
        : (role == UserRole.government
              ? 'Government'
              : (role == UserRole.admin ? 'Admin' : 'Customer'));
    final String auditActionType = role == UserRole.owner
        ? 'BUSINESSMAN_REGISTER'
        : (role == UserRole.government
              ? 'GOVERNMENT_REGISTER'
              : (role == UserRole.admin
                    ? 'ADMIN_REGISTER'
                    : 'CUSTOMER_REGISTER'));
    final String auditTitle = role == UserRole.owner
        ? 'Businessman Registration'
        : (role == UserRole.government
              ? 'Government Registration'
              : (role == UserRole.admin
                    ? 'Admin Registration'
                    : 'User Registration'));

    AuditLogService.logAction(
      actionType: auditActionType,
      category: auditCategory,
      title: auditTitle,
      description: 'New $auditCategory account registered ($cleanEmail)',
      userId: userId,
      userEmail: cleanEmail,
    );

    return CustomerAuthResult(
      success: true,
      message:
          'Registration successful! Account created as ${roleStr.toUpperCase()}.',
      user: _currentCustomer,
    );
  }

  static void updatePasswordLocally(String newPassword) {
    if (_currentCustomer != null) {
      final email = _currentCustomer!.email.toLowerCase();
      if (_registeredCustomers.containsKey(email)) {
        _registeredCustomers[email]!['password'] = newPassword;
      }
    }
  }

  /// Checks whether the user has an active password configured in database or local store
  static Future<bool> hasPasswordConfigured([String? email]) async {
    final cleanEmail = (email ?? _currentCustomer?.email)?.trim().toLowerCase();
    if (cleanEmail == null || cleanEmail.isEmpty) return false;

    // 1. Check in-memory store
    if (_registeredCustomers.containsKey(cleanEmail)) {
      final localPass =
          _registeredCustomers[cleanEmail]?['password']?.toString() ?? '';
      if (localPass.isNotEmpty) return true;
    }

    // 2. Check Supabase users table
    try {
      final supabase = SupabaseService.client;
      final dbUser = await supabase
          .from('users')
          .select('user_password, password')
          .ilike('email', cleanEmail)
          .maybeSingle();

      if (dbUser != null) {
        final pass1 = dbUser['user_password']?.toString() ?? '';
        final pass2 = dbUser['password']?.toString() ?? '';
        if (pass1.trim().isNotEmpty || pass2.trim().isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  static Future<CustomerAuthResult> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = _currentCustomer;
    if (user == null) {
      return const CustomerAuthResult(
        success: false,
        message: 'No active login session found. Please log in again.',
      );
    }

    final cleanEmail = user.email.trim().toLowerCase();
    final supabase = SupabaseService.client;

    // 1. Verify old password against Supabase `users` table or local store
    Map<String, dynamic>? dbUser;
    try {
      dbUser = await supabase
          .from('users')
          .select()
          .ilike('email', cleanEmail)
          .maybeSingle();
    } catch (e) {
      debugPrint('Error verifying current password: $e');
    }

    bool oldPasswordValid = false;
    if (dbUser != null) {
      final storedPassword = dbUser['user_password']?.toString() ?? '';
      if (storedPassword.startsWith(r'$2a$') ||
          storedPassword.startsWith(r'$2b$') ||
          storedPassword.startsWith(r'$2y$')) {
        try {
          oldPasswordValid = BCrypt.checkpw(oldPassword, storedPassword);
        } catch (_) {}
      } else {
        oldPasswordValid = (storedPassword == oldPassword);
      }
    } else if (_registeredCustomers.containsKey(cleanEmail)) {
      final localPass = _registeredCustomers[cleanEmail]?['password'] ?? '';
      oldPasswordValid = (localPass == oldPassword);
    }

    if (!oldPasswordValid) {
      return const CustomerAuthResult(
        success: false,
        message: 'Current password is incorrect.',
      );
    }

    // 2. Hash new password with BCrypt
    final String hashedPassword = BCrypt.hashpw(
      newPassword,
      BCrypt.gensalt(logRounds: 6),
    );

    // 3. Update Supabase `users` table
    try {
      await supabase
          .from('users')
          .update({
            'user_password': hashedPassword,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .ilike('email', cleanEmail);
    } catch (e) {
      debugPrint('Error updating password in Supabase: $e');
    }

    // 4. Update Supabase Auth user if active session exists
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (_) {}

    // 5. Update local in-memory store
    _registeredCustomers[cleanEmail] = {
      'password': newPassword,
      'role': user.role.name,
    };

    AuditLogService.logAction(
      actionType: 'PASSWORD_CHANGE',
      category: 'Account Modification',
      title: 'Password Changed',
      description: 'Account login password updated successfully',
      userId: user.id,
      userEmail: cleanEmail,
    );

    return const CustomerAuthResult(
      success: true,
      message: 'Password changed successfully!',
    );
  }

  /// Generates a random 10-character alphanumeric secure password
  static String generateSecurePassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%*';
    final random = Random();
    return List.generate(
      10,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Sets or generates an initial password for a user (e.g. during Google onboarding or account setup)
  static Future<CustomerAuthResult> setInitialPassword({
    required String newPassword,
    String? email,
  }) async {
    final targetEmail = (email ?? _currentCustomer?.email)
        ?.trim()
        .toLowerCase();
    if (targetEmail == null || targetEmail.isEmpty) {
      return const CustomerAuthResult(
        success: false,
        message: 'No active user email found to set password.',
      );
    }

    if (newPassword.length < 6) {
      return const CustomerAuthResult(
        success: false,
        message: 'Password must be at least 6 characters long.',
      );
    }

    final supabase = SupabaseService.client;
    final String hashedPassword = BCrypt.hashpw(
      newPassword,
      BCrypt.gensalt(logRounds: 6),
    );

    // 1. Update Supabase users table with BCrypt hashed password
    try {
      await supabase
          .from('users')
          .update({
            'user_password': hashedPassword,
            'password': hashedPassword,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .ilike('email', targetEmail);
    } catch (e) {
      debugPrint(
        'CustomerStoreService: Supabase user_password update error: $e',
      );
    }

    // 2. Sync password with Supabase Auth so traditional email/password login works
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (_) {}

    // 3. Update in-memory cache
    _registeredCustomers[targetEmail] = {
      'password': newPassword,
      'role': _currentCustomer?.role.name ?? 'customer',
    };

    AuditLogService.logAction(
      actionType: 'PASSWORD_SET',
      category: 'Account Security',
      title: 'Account Password Configured',
      description: 'User configured password for direct login access',
      userId: _currentCustomer?.id ?? '',
      userEmail: targetEmail,
    );

    return const CustomerAuthResult(
      success: true,
      message: 'Account password configured successfully!',
    );
  }

  static Future<CustomerAuthResult> loginCustomer({
    required String email,
    required String password,
    bool rememberMe = false,
    PortalType portal = PortalType.customer,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty || password.isEmpty) {
      return const CustomerAuthResult(
        success: false,
        message: 'Please enter your email and password.',
      );
    }

    final supabase = SupabaseService.client;

    // 1. Check public.users table for user password (BCrypt hash matching)
    Map<String, dynamic>? dbUser;
    try {
      dbUser = await supabase
          .from('users')
          .select()
          .eq('email', cleanEmail)
          .maybeSingle();
    } catch (e) {
      if (kDebugMode) {
        print('Supabase DB fetch info: $e');
      }
    }

    if (dbUser != null) {
      final storedPassword = dbUser['user_password']?.toString() ?? '';
      bool passwordMatches = false;

      if (storedPassword.startsWith(r'$2a$') ||
          storedPassword.startsWith(r'$2b$') ||
          storedPassword.startsWith(r'$2y$')) {
        try {
          passwordMatches = BCrypt.checkpw(password, storedPassword);
        } catch (_) {}
      } else {
        // Legacy plaintext migration fallback: verify and immediately auto-upgrade to cryptographic BCrypt hash in Supabase
        passwordMatches = (storedPassword == password);
        if (passwordMatches) {
          try {
            final upgradedHash = BCrypt.hashpw(
              password,
              BCrypt.gensalt(logRounds: 6),
            );
            supabase
                .from('users')
                .update({'user_password': upgradedHash})
                .eq('email', cleanEmail)
                .catchError((_) {});
          } catch (_) {}
        }
      }

      if (passwordMatches) {
        // Stored password match confirmed!
        final String rawDbRole = (dbUser['role']?.toString() ?? 'customer')
            .toLowerCase()
            .trim();

        // STRICT ROLE-BASED ACCESS CONTROL (RBAC) ENFORCEMENT
        bool isRoleAuthorized = false;

        switch (portal) {
          case PortalType.customer:
            isRoleAuthorized = (rawDbRole == 'customer' || rawDbRole == 'user');
            break;

          case PortalType.owner:
            isRoleAuthorized =
                (rawDbRole == 'businessman' ||
                rawDbRole == 'owner' ||
                rawDbRole == 'business');
            // Graceful auto-repair: If user registered via Business portal previously but role was saved as customer, upgrade role to businessman
            if (!isRoleAuthorized &&
                (rawDbRole == 'customer' || rawDbRole == 'user')) {
              isRoleAuthorized = true;
              try {
                supabase
                    .from('users')
                    .update({'role': 'businessman'})
                    .eq('email', cleanEmail)
                    .catchError((_) {});
              } catch (_) {}
            }
            break;

          case PortalType.government:
            isRoleAuthorized =
                (rawDbRole == 'government' ||
                rawDbRole == 'inspector' ||
                rawDbRole == 'officer');
            break;

          case PortalType.admin:
            isRoleAuthorized =
                (rawDbRole == 'admin' || rawDbRole == 'administrator');
            break;
        }

        if (!isRoleAuthorized) {
          // Generic secure response preventing role and account enumeration (no audit log to avoid exposing role details)
          return const CustomerAuthResult(
            success: false,
            message:
                'No account was found with these credentials. Please try again.',
          );
        }

        final String userId =
            dbUser['id']?.toString() ?? UuidHelper.generateV4();
        final UserRole finalUserRole =
            (rawDbRole == 'businessman' || rawDbRole == 'owner')
            ? UserRole.owner
            : (rawDbRole == 'admin'
                  ? UserRole.admin
                  : (rawDbRole == 'government'
                        ? UserRole.government
                        : UserRole.user));

        try {
          final authResult = await supabase.auth.signInWithPassword(
            email: cleanEmail,
            password: password,
          );
          if (authResult.user == null || authResult.user!.id != userId) {
            await supabase.auth.signOut();
            return const CustomerAuthResult(
              success: false,
              message: 'Account verification failed. Please contact support.',
            );
          }
        } catch (_) {
          return const CustomerAuthResult(
            success: false,
            message:
                'Account verification failed. Please verify your email and password.',
          );
        }

        String? joinedDate;
        final rawCreated = dbUser['created_at']?.toString();
        if (rawCreated != null && rawCreated.isNotEmpty) {
          final dt = DateTime.tryParse(rawCreated);
          if (dt != null) {
            final DateTime msiaDt = dt.toUtc().add(const Duration(hours: 8));
            joinedDate =
                '${msiaDt.day} ${_monthName(msiaDt.month)} ${msiaDt.year}';
          }
        }

        String? bannerUrl;
        if (dbUser['banner_url'] != null &&
            dbUser['banner_url'].toString().trim().isNotEmpty) {
          bannerUrl = dbUser['banner_url'].toString().trim();
        } else if (dbUser['settings'] is Map &&
            (dbUser['settings'] as Map)['banner_url'] != null) {
          bannerUrl = (dbUser['settings'] as Map)['banner_url']
              ?.toString()
              .trim();
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          bannerUrl ??=
              prefs.getString('user_banner_url_$userId') ??
              prefs.getString('user_banner_url_$cleanEmail');
        } catch (_) {}

        _currentCustomer = UserModel(
          id: userId,
          name: dbUser['name']?.toString() ?? cleanEmail.split('@').first,
          email: cleanEmail,
          phone: dbUser['phone']?.toString(),
          role: finalUserRole,
          status: AccountStatus.active,
          avatarUrl: dbUser['avatar_url']?.toString() ?? '',
          bannerUrl: bannerUrl,
          gender: dbUser['gender']?.toString(),
          country: dbUser['country']?.toString(),
          state: dbUser['state']?.toString(),
          joinedDate: joinedDate,
        );

        // Keep registeredCustomers store updated
        _registeredCustomers[cleanEmail] = {
          'password': password,
          'role': rawDbRole,
        };

        // Run background non-blocking tasks asynchronously for instant UI transition
        unawaited(() async {
          try {
            await AuditLogService.logAction(
              actionType: 'LOGIN',
              category: 'Session Activity',
              title: 'User Login Session',
              description:
                  'Logged into account session successfully as ${finalUserRole.name}',
              userId: userId,
              userEmail: cleanEmail,
            );
          } catch (_) {}
          try {
            await themeManager.loadThemeForUser(_currentCustomer!.id);
          } catch (_) {}
        }());

        await RememberMeService.saveRememberedUser(
          rememberMe: rememberMe,
          email: cleanEmail,
          portal: portal,
        );

        await saveSession(_currentCustomer!, portal: portal);

        return CustomerAuthResult(
          success: true,
          message: 'Login successful!',
          user: _currentCustomer,
        );
      } else {
        // Password does not match DB hash -> Invalid Credentials!
        return const CustomerAuthResult(
          success: false,
          message:
              'No account was found with these credentials. Please try again.',
        );
      }
    }

    // 2. Fallback to local registered customers store if offline or no DB row
    if (_registeredCustomers.containsKey(cleanEmail)) {
      final regData = _registeredCustomers[cleanEmail]!;
      final storedPass = regData['password'] ?? '';
      final storedRole = (regData['role'] ?? 'customer')
          .toString()
          .toLowerCase();

      if (storedPass == password) {
        // RBAC validation in fallback mode
        bool isRoleAuthorized = false;
        switch (portal) {
          case PortalType.customer:
            isRoleAuthorized =
                (storedRole == 'customer' || storedRole == 'user');
            break;
          case PortalType.owner:
            isRoleAuthorized =
                (storedRole == 'businessman' || storedRole == 'owner');
            break;
          case PortalType.government:
            isRoleAuthorized =
                (storedRole == 'government' || storedRole == 'inspector');
            break;
          case PortalType.admin:
            isRoleAuthorized =
                (storedRole == 'admin' || storedRole == 'administrator');
            break;
        }

        if (!isRoleAuthorized) {
          return const CustomerAuthResult(
            success: false,
            message:
                'No account was found with these credentials. Please try again.',
          );
        }

        final UserRole role =
            (storedRole == 'businessman' || storedRole == 'owner')
            ? UserRole.owner
            : (storedRole == 'admin'
                  ? UserRole.admin
                  : (storedRole == 'government'
                        ? UserRole.government
                        : UserRole.user));

        _currentCustomer = UserModel(
          id: UuidHelper.generateV4(),
          name: cleanEmail.split('@').first,
          email: cleanEmail,
          role: role,
          status: AccountStatus.active,
          avatarUrl: '',
        );

        await RememberMeService.saveRememberedUser(
          rememberMe: rememberMe,
          email: cleanEmail,
          portal: portal,
        );

        await themeManager.loadThemeForUser(_currentCustomer!.id);

        return CustomerAuthResult(
          success: true,
          message: 'Login successful!',
          user: _currentCustomer,
        );
      }
    }

    return const CustomerAuthResult(
      success: false,
      message: 'No account was found with these credentials. Please try again.',
    );
  }

  /// Triggers Native Google Sign-In Account Selector & authenticates with Supabase via ID Token
  /// [isRegistration]: If false (Login page), checks if user exists in Supabase. If not found, aborts login and returns isAccountNotFound: true.
  /// If true (Register page), creates a new user record in Supabase.
  static Future<CustomerAuthResult> signInWithGoogle({
    bool isRegistration = false,
  }) async {
    try {
      final supabase = SupabaseService.client;
      String? envClientId;
      try {
        if (dotenv.isInitialized) {
          envClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
        }
      } catch (_) {}
      final String webClientId =
          envClientId ??
          '927326709623-332ted8aosmjf5efmbq3if09ur98vtl5.apps.googleusercontent.com';

      // 1. Initialize Google Sign-In with serverClientId matching mobile_project
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        scopes: ['email', 'profile'],
      );

      // Clear any stale cached Google credentials
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      // 2. Trigger native Google Sign-In account selector
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return const CustomerAuthResult(
          success: false,
          message: 'Google Sign-In was cancelled.',
        );
      }

      // 3. Obtain authentication ID Token & Access Token from native Google SDK
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        return const CustomerAuthResult(
          success: false,
          message: 'Failed to retrieve Google ID token.',
        );
      }

      final String gEmail = googleUser.email.trim().toLowerCase();
      final String gName = googleUser.displayName ?? gEmail.split('@').first;
      final String gAvatar = googleUser.photoUrl ?? '';

      // Authenticate first so the profile check is protected by RLS.
      final AuthResponse authRes = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final sessionUser = authRes.user ?? supabase.auth.currentUser;
      if (sessionUser == null ||
          sessionUser.email?.trim().toLowerCase() != gEmail) {
        await supabase.auth.signOut();
        _currentCustomer = null;
        return const CustomerAuthResult(
          success: false,
          message: 'Google account verification failed. Please try again.',
        );
      }
      final String userId = sessionUser.id;
      Map<String, dynamic>? existingUserPre;
      try {
        existingUserPre = await supabase
            .from('users')
            .select()
            .eq('id', userId)
            .maybeSingle();
      } catch (e) {
        if (kDebugMode) {
          print('Error verifying Google user profile: $e');
        }
        await supabase.auth.signOut();
        _currentCustomer = null;
        return const CustomerAuthResult(
          success: false,
          message: 'Unable to verify this account securely. Please try again.',
        );
      }

      if (!isRegistration && existingUserPre == null) {
        await supabase.auth.signOut();
        _currentCustomer = null;
        return CustomerAuthResult(
          success: false,
          isAccountNotFound: true,
          message:
              'No verified account found for $gEmail. Please register first.',
        );
      }
      final nowUtc = DateTime.now().toUtc();
      final nowMsia = nowUtc.add(const Duration(hours: 8));
      final String formattedJoinedDate =
          '${nowMsia.day} ${_monthName(nowMsia.month)} ${nowMsia.year}';
      final String createdIso = nowUtc.toIso8601String();

      // CASE B: REGISTER FLOW (isRegistration == true) & NO RECORD -> CREATE NEW USER
      if (existingUserPre == null) {
        try {
          final createdUser = await supabase
              .from('users')
              .upsert({
                'id': userId,
                'name': gName,
                'email': gEmail,
                'role': 'customer',
                'status': 'active',
                'created_at': createdIso,
                'settings': {
                  'google_linked': {'email': gEmail, 'linked_at': createdIso},
                  'google_email': gEmail,
                },
              }, onConflict: 'email')
              .select('id, email')
              .maybeSingle();
          if (createdUser == null || createdUser['id']?.toString() != userId) {
            throw const AuthException('Google profile could not be verified.');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error upserting new Google user: $e');
          }
          await supabase.auth.signOut();
          _currentCustomer = null;
          return const CustomerAuthResult(
            success: false,
            message:
                'Google registration could not be completed securely. No account access was granted.',
          );
        }

        _currentCustomer = UserModel(
          id: userId,
          name: gName,
          email: gEmail,
          phone: null,
          role: UserRole.user,
          status: AccountStatus.active,
          avatarUrl: gAvatar,
          joinedDate: formattedJoinedDate,
        );

        await RememberMeService.saveRememberedUser(
          rememberMe: true,
          email: gEmail,
          portal: PortalType.customer,
        );

        await themeManager.loadThemeForUser(_currentCustomer!.id);
        await saveSession(_currentCustomer!, portal: PortalType.customer);

        AuditLogService.logAction(
          actionType: 'REGISTER',
          category: 'Authentication',
          title: 'Google Account Registered',
          description: 'New customer account created via Google Sign-In',
          userId: userId,
          userEmail: gEmail,
        );

        return CustomerAuthResult(
          success: true,
          message: 'Google Registration successful! Welcome, $gName',
          user: _currentCustomer,
        );
      }

      // CASE C: EXISTING USER FOUND (Login or Register)
      final existingUserId = existingUserPre['id']?.toString();
      if (existingUserId == null || existingUserId != userId) {
        await supabase.auth.signOut();
        _currentCustomer = null;
        return const CustomerAuthResult(
          success: false,
          message:
              'This email is already registered. Sign in with your email and password, then link and verify Google from Settings.',
        );
      }

      final statusStr =
          existingUserPre['status']?.toString().toLowerCase() ?? 'active';
      if (statusStr == 'suspended' ||
          statusStr == 'banned' ||
          statusStr == 'inactive') {
        try {
          await supabase.auth.signOut();
        } catch (_) {}
        _currentCustomer = null;
        return CustomerAuthResult(
          success: false,
          message:
              'Your account is currently $statusStr. Please contact support.',
        );
      }

      final roleStr =
          existingUserPre['role']?.toString().toLowerCase() ?? 'customer';
      UserRole mappedRole = UserRole.user;
      if (roleStr == 'admin') {
        mappedRole = UserRole.admin;
      } else if (roleStr == 'officer' || roleStr == 'government') {
        mappedRole = UserRole.government;
      } else if (roleStr == 'businessman' || roleStr == 'owner') {
        mappedRole = UserRole.owner;
      }

      _currentCustomer = UserModel(
        id: existingUserPre['id']?.toString() ?? userId,
        name: existingUserPre['name']?.toString() ?? gName,
        email: gEmail,
        phone: existingUserPre['phone']?.toString(),
        role: mappedRole,
        status: AccountStatus.active,
        avatarUrl: existingUserPre['avatar_url']?.toString() ?? gAvatar,
        gender: existingUserPre['gender']?.toString(),
        country: existingUserPre['country']?.toString(),
        state: existingUserPre['state']?.toString(),
        joinedDate: formattedJoinedDate,
      );

      await RememberMeService.saveRememberedUser(
        rememberMe: true,
        email: gEmail,
        portal: mappedRole == UserRole.owner
            ? PortalType.owner
            : PortalType.customer,
      );

      await saveSession(
        _currentCustomer!,
        portal: mappedRole == UserRole.owner
            ? PortalType.owner
            : PortalType.customer,
      );

      await themeManager.loadThemeForUser(_currentCustomer!.id);

      AuditLogService.logAction(
        actionType: 'LOGIN',
        category: 'Authentication',
        title: 'Google Sign-In Successful',
        description: 'Customer logged in with Google authentication',
        userId: _currentCustomer!.id,
        userEmail: gEmail,
      );

      return CustomerAuthResult(
        success: true,
        message: 'Welcome back, ${_currentCustomer!.name}!',
        user: _currentCustomer,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In error: $e');
      }

      final errStr = e.toString().toLowerCase();
      try {
        await SupabaseService.client.auth.signOut();
      } catch (_) {}
      _currentCustomer = null;
      if (errStr.contains('canceled_by_user') ||
          errStr.contains('user_canceled') ||
          errStr.contains('canceled') ||
          errStr.contains('cancelled')) {
        return const CustomerAuthResult(
          success: false,
          message: 'Google Sign-In was cancelled.',
        );
      }

      if (errStr.contains('10') ||
          errStr.contains('developer') ||
          errStr.contains('sign_in_failed')) {
        return const CustomerAuthResult(
          success: false,
          message:
              'Google Sign-In configuration mismatch (SHA-1 fingerprint). Please check Cloud Console credentials.',
        );
      }

      if (errStr.contains('500') ||
          errStr.contains('identity') ||
          errStr.contains('already exists') ||
          errStr.contains('already registered')) {
        return const CustomerAuthResult(
          success: false,
          message:
              'This email is already registered. Sign in with your email and password, then link and verify Google from Settings.',
        );
      }

      return const CustomerAuthResult(
        success: false,
        message: 'Google Sign-In could not be completed. Please try again.',
      );
    }
  }

  static Future<String> logout({BuildContext? context}) async {
    sessionGeneration++;
    String destinationRoute = AppRoutes.login;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPortal =
          prefs.getString(_kUserLastPortalKey) ??
          (_currentCustomer?.role == UserRole.owner
              ? 'owner'
              : (_currentCustomer?.role == UserRole.admin
                    ? 'admin'
                    : (_currentCustomer?.role == UserRole.government
                          ? 'government'
                          : 'customer')));

      destinationRoute = getPortalLoginRoute(lastPortal);

      // Keep last portal in SharedPreferences so sign out always stays at the last portal
      await prefs.setString(_kUserLastPortalKey, lastPortal);
      await prefs.remove(_kUserSessionJsonKey);
      await prefs.remove(_kUserSessionLastActiveKey);
    } catch (_) {}

    if (_currentCustomer != null) {
      AuditLogService.logAction(
        actionType: 'LOGOUT',
        category: 'Session Activity',
        title: 'User Logout Session',
        description: 'Logged out of account session',
        userId: _currentCustomer!.id,
        userEmail: _currentCustomer!.email,
      );
    }

    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {}

    _currentCustomer = null;
    themeManager.resetToSystemTheme();

    if (context != null && context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        destinationRoute,
        (route) => false,
      );
    }

    return destinationRoute;
  }

  /// Override active role for switching between Customer, Owner, Admin & Government Official
  static void updateOwnerRole(UserRole newRole) {
    if (_currentCustomer != null) {
      _currentCustomer = UserModel(
        id: _currentCustomer!.id,
        name: _currentCustomer!.name,
        email: _currentCustomer!.email,
        phone: _currentCustomer!.phone,
        role: newRole,
        status: _currentCustomer!.status,
        avatarUrl: _currentCustomer!.avatarUrl,
        gender: _currentCustomer!.gender,
        country: _currentCustomer!.country,
        state: _currentCustomer!.state,
        joinedDate: _currentCustomer!.joinedDate,
      );

      saveSession(_currentCustomer!);

      final roleStr = newRole == UserRole.owner
          ? 'businessman'
          : (newRole == UserRole.admin
                ? 'admin'
                : (newRole == UserRole.government ? 'government' : 'customer'));

      try {
        final supabase = SupabaseService.client;
        supabase
            .from('users')
            .update({'role': roleStr})
            .eq('email', _currentCustomer!.email.toLowerCase())
            .catchError((_) {});
      } catch (_) {}
    }
  }

  /// Fetches all user accounts directly from Supabase 'users' database table
  static Future<List<UserModel>> fetchAllRealUsers() async {
    try {
      final supabase = SupabaseService.client;
      final res = await supabase
          .from('users')
          .select()
          .order('created_at', ascending: false);
      final List<dynamic> rows = res as List<dynamic>;

      if (rows.isNotEmpty) {
        final List<UserModel> realUsers = [];
        for (final row in rows) {
          realUsers.add(UserModel.fromMap(row as Map<String, dynamic>));
        }

        // Ensure current active customer is included if missing
        if (_currentCustomer != null &&
            !realUsers.any(
              (u) =>
                  u.id == _currentCustomer!.id ||
                  u.email == _currentCustomer!.email,
            )) {
          realUsers.insert(0, _currentCustomer!);
        }

        return realUsers;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching real users from Supabase: $e');
      }
    }

    if (_currentCustomer != null) {
      return [_currentCustomer!];
    }
    return _registeredCustomers.entries
        .map(
          (e) => UserModel(
            id: e.key,
            name: e.key.split('@').first,
            email: e.key,
            phone: '',
            role: e.value['role'] == 'businessman'
                ? UserRole.owner
                : UserRole.user,
            status: AccountStatus.active,
            avatarUrl: '',
          ),
        )
        .toList();
  }

  /// Fetches paginated user accounts directly from Supabase 'users' database table using range(from, to)
  static Future<({List<UserModel> users, bool hasMore})> fetchUsersPaginated({
    required int page,
    required int pageSize,
  }) async {
    try {
      final supabase = SupabaseService.client;
      final int from = page * pageSize;
      final int to = from + pageSize - 1;

      final res = await supabase
          .from('users')
          .select()
          .order('created_at', ascending: false)
          .range(from, to);

      final List<dynamic> rows = res as List<dynamic>;
      final List<UserModel> paginatedUsers = [];
      for (final row in rows) {
        paginatedUsers.add(UserModel.fromMap(row as Map<String, dynamic>));
      }

      final bool hasMore = paginatedUsers.length == pageSize;
      return (users: paginatedUsers, hasMore: hasMore);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching paginated users from Supabase: $e');
      }
      return (users: <UserModel>[], hasMore: false);
    }
  }

  /// Processes and uploads a user custom banner photo, persisting to Supabase storage or Base64 Data URI
  static Future<String> uploadBannerImage(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final supabase = SupabaseService.client;
      final fileName =
          'banner_${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';

      try {
        await supabase.storage
            .from('banners')
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        final publicUrl = supabase.storage
            .from('banners')
            .getPublicUrl(fileName);
        if (publicUrl.isNotEmpty) {
          return publicUrl;
        }
      } catch (_) {
        try {
          await supabase.storage
              .from('avatars')
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          final publicUrl = supabase.storage
              .from('avatars')
              .getPublicUrl(fileName);
          if (publicUrl.isNotEmpty) {
            return publicUrl;
          }
        } catch (_) {}
      }

      // Safe resilient fallback: store as high-quality base64 Data URI directly in Supabase user row
      final base64String = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      if (kDebugMode) {
        print('Error processing banner image: $e');
      }
      return imageFile.path;
    }
  }

  /// Fetches real government health officers and inspectors from Supabase 'users' table
  static Future<List<UserModel>> fetchGovernmentOfficers() async {
    try {
      final supabase = SupabaseService.client;
      final res = await supabase
          .from('users')
          .select()
          .or('role.eq.government,role.eq.officer,role.eq.inspector')
          .order('name', ascending: true);

      final List<dynamic> rows = res as List<dynamic>;
      final List<UserModel> officers = [];
      for (final row in rows) {
        officers.add(UserModel.fromMap(row as Map<String, dynamic>));
      }
      if (officers.isNotEmpty) {
        return officers;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching government officers from Supabase: $e');
      }
    }
    // Safe fallback if network error
    return const [
      UserModel(
        id: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
        name: 'Government Health Officer',
        email: 'government@gmail.com',
        phone: '+60 12-345 6789',
        role: UserRole.government,
        status: AccountStatus.active,
        avatarUrl: '',
      ),
    ];
  }
}
