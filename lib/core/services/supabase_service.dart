import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_env.dart';

class SupabaseService {
  static bool isInitialized = false;

  static Future<void> initialize() async {
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: '.env');
      }
    } catch (_) {}

    final activeUrl = AppEnv.supabaseUrl;
    final activeKey = AppEnv.supabaseAnonKey;

    if (activeUrl.isEmpty || activeKey.isEmpty) {
      isInitialized = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: activeUrl,
        // ignore: deprecated_member_use
        anonKey: activeKey,
      );
      isInitialized = true;
    } catch (_) {
      try {
        Supabase.instance.client;
        isInitialized = true;
      } catch (_) {
        isInitialized = false;
      }
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
