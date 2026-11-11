import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ResendEmailService {
  // In-memory store for active password reset tokens: email -> {token, expiry}
  static final Map<String, Map<String, dynamic>> _activeTokens = {};

  static const String defaultResendApiKey = 're_123456789_placeholder';

  static String get apiKey {
    try {
      if (dotenv.isInitialized) {
        final envKey = dotenv.env['RESEND_API_KEY'];
        if (envKey != null && envKey.isNotEmpty) return envKey;
      }
    } catch (_) {}
    return const String.fromEnvironment('RESEND_API_KEY', defaultValue: defaultResendApiKey);
  }

  /// Generate a 6-digit numeric reset token for a specific email address
  static String generateResetToken(String email) {
    final cleanEmail = email.trim().toLowerCase();
    final String token = (Random().nextInt(900000) + 100000).toString();
    
    _activeTokens[cleanEmail] = {
      'token': token,
      'expiry': DateTime.now().add(const Duration(minutes: 15)),
    };

    return token;
  }

  /// Verify if token matches and is not expired
  static bool verifyResetToken(String email, String inputToken) {
    final cleanEmail = email.trim().toLowerCase();
    final data = _activeTokens[cleanEmail];
    if (data == null) return false;

    final String token = data['token'] as String;
    final DateTime expiry = data['expiry'] as DateTime;

    if (DateTime.now().isAfter(expiry)) {
      _activeTokens.remove(cleanEmail);
      return false;
    }

    return token.trim() == inputToken.trim();
  }

  /// Clear token after successful reset
  static void invalidateToken(String email) {
    _activeTokens.remove(email.trim().toLowerCase());
  }

  static String get fromEmail {
    try {
      if (dotenv.isInitialized) {
        final envFrom = dotenv.env['RESEND_FROM_EMAIL'];
        if (envFrom != null && envFrom.isNotEmpty) return envFrom;
      }
    } catch (_) {}
    return 'HygieneTruth <noreply@contact.smartsystem.live>';
  }

  /// Sends a Password Reset Token email via Resend API
  static Future<bool> sendPasswordResetEmail({
    required String recipientEmail,
    required String resetToken,
    String? userName,
  }) async {
    final String activeKey = apiKey;
    final String cleanEmail = recipientEmail.trim().toLowerCase();
    final String name = userName ?? cleanEmail.split('@').first;

    final String htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; background-color: #f4f7f6; margin: 0; padding: 0; }
    .container { max-width: 580px; margin: 30px auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #0F766E, #0F172A); padding: 30px; text-align: center; color: #ffffff; }
    .header h1 { margin: 0; font-size: 24px; letter-spacing: 0.5px; }
    .content { padding: 32px; color: #334155; line-height: 1.6; }
    .token-box { background: #F1F5F9; border: 2px dashed #0F766E; border-radius: 12px; padding: 20px; text-align: center; margin: 24px 0; }
    .token-code { font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #0F766E; margin: 0; }
    .footer { background: #F8FAFC; padding: 20px; text-align: center; font-size: 12px; color: #94A3B8; border-top: 1px solid #E2E8F0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔐 Password Reset Request</h1>
    </div>
    <div class="content">
      <p>Hello <strong>$name</strong>,</p>
      <p>We received a request to reset your account password for (<strong>$cleanEmail</strong>).</p>
      <p>Please use the 6-digit verification code below to authorize your password reset:</p>
      
      <div class="token-box">
        <p style="margin: 0 0 6px 0; font-size: 12px; color: #64748B; text-transform: uppercase; font-weight: bold;">Your Reset Code</p>
        <div class="token-code">$resetToken</div>
      </div>
      
      <p style="font-size: 13px; color: #64748B;">This verification code is valid for <strong>15 minutes</strong>. If you did not request a password reset, please ignore this email.</p>
    </div>
    <div class="footer">
      &copy; 2026 Food Hygiene & Safety Inspection System.
    </div>
  </div>
</body>
</html>
''';

    final Map<String, dynamic> body = {
      'from': fromEmail,
      'to': [cleanEmail],
      'subject': 'Your Password Reset Verification Code: $resetToken',
      'html': htmlContent,
    };

    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('https://api.resend.com/emails'));
      request.headers.set('Authorization', 'Bearer $activeKey');
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (kDebugMode) {
        print('Resend API response status: ${response.statusCode}');
        print('Resend API response body: $responseBody');
      }

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      if (kDebugMode) {
        print('Resend API Send Exception: $e');
      }
      return false;
    }
  }
}
