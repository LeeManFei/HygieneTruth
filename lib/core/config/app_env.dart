import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  // App Info
  static String get appEnv => dotenv.env['APP_ENV'] ?? 'development';
  static String get appName => dotenv.env['APP_NAME'] ?? 'Hygiene Portal';
  static String get appVersion => dotenv.env['APP_VERSION'] ?? '1.0.0';

  // Supabase Database & Backend Settings
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Authentication & Security
  static String get authTokenKey => dotenv.env['AUTH_TOKEN_KEY'] ?? 'hygiene_auth_token';
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  static String get googleClientSecret => dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';
  static String get googleClientIdAndroid => dotenv.env['GOOGLE_CLIENT_ID_ANDROID'] ?? '';
  static String get googleClientIdIos => dotenv.env['GOOGLE_CLIENT_ID_IOS'] ?? '';

  // GPS & Location Thresholds
  static String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  static double get defaultLatitude => double.tryParse(dotenv.env['DEFAULT_LATITUDE'] ?? '3.1466') ?? 3.1466;
  static double get defaultLongitude => double.tryParse(dotenv.env['DEFAULT_LONGITUDE'] ?? '101.6958') ?? 101.6958;
  static double get gpsAccuracyThresholdMeters => double.tryParse(dotenv.env['GPS_ACCURACY_THRESHOLD_METERS'] ?? '150.0') ?? 150.0;

  // Storage & Media Bucket Limits
  static String get storageBucketName => dotenv.env['STORAGE_BUCKET_NAME'] ?? 'images';
  static int get maxPhotoUploadSizeMb => int.tryParse(dotenv.env['MAX_PHOTO_UPLOAD_SIZE_MB'] ?? '10') ?? 10;

  // Notifications & Cloud Messaging
  static String get fcmSenderId => dotenv.env['FCM_SENDER_ID'] ?? '';

  // Resend API Key for Email Delivery
  static String get resendApiKey => dotenv.env['RESEND_API_KEY'] ?? '';
  static String get resendFromEmail => dotenv.env['RESEND_FROM_EMAIL'] ?? 'HygieneTruth <noreply@contact.smartsystem.live>';

  // Google Gemini AI Vision
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  // Stripe Payment Gateway Configuration
  static String get stripePublishableKey => dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';
  static String get stripeSecretKey => dotenv.env['STRIPE_SECRET_KEY'] ?? '';
}
