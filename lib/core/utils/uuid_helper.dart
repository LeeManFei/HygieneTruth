import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class UuidHelper {
  static final Random _random = Random.secure();

  /// Check if a string is already a valid UUID
  static bool isValidUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(str);
  }

  /// Generates a valid RFC-4122 Version 4 UUID string
  static String generateV4() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version to 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to IETF RFC 4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final String hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Converts any string (like "rest_001", "usr_current", "testing") into a deterministic RFC-4122 UUID
  static String toDeterministicUuid(String input) {
    final trimmed = input.trim();
    if (isValidUuid(trimmed)) return trimmed;
    if (trimmed.isEmpty) return generateV4();

    final digest = md5.convert(utf8.encode(trimmed.toLowerCase()));
    final List<int> bytes = List<int>.from(digest.bytes);

    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Set version to 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Set variant to IETF RFC 4122

    final String hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Convenience aliases
  static String deterministic(String input) => toDeterministicUuid(input);
  static String generate() => generateV4();
}
