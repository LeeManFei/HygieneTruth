import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class ImageHashHelper {
  /// Hash actual decoded-image bytes; an unreadable image is never a clean match.
  static Future<Uint8List> readEvidenceBytes(String path) async {
    const maxBytes = 20 * 1024 * 1024;
    late Uint8List bytes;
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final response = await (await client.getUrl(uri).timeout(const Duration(seconds: 8))).close().timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 || response.contentLength > maxBytes) throw const FormatException('Photo unavailable or too large');
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.timeout(const Duration(seconds: 8))) {
          builder.add(chunk);
          if (builder.length > maxBytes) throw const FormatException('Photo exceeds 20 MB');
        }
        bytes = builder.takeBytes();
      } finally { client.close(force: true); }
    } else {
      final file = File(path.replaceFirst('file://', ''));
      if (await file.length() > maxBytes) throw const FormatException('Photo exceeds 20 MB');
      bytes = await file.readAsBytes();
    }
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32, targetHeight: 32);
    codec.dispose();
    return bytes;
  }

  static Future<String> computeEvidenceHash(String path) async =>
      sha256.convert(await readEvidenceBytes(path)).toString();

  /// Computes a cryptographic SHA-256 hash of an image file or URL string.
  /// If [pathOrUrl] points to a local file, reads file bytes and computes SHA-256 hash.
  /// Otherwise, computes SHA-256 hash of the URL/identifier string.
  static Future<String> computeHash(String pathOrUrl) async {
    final clean = pathOrUrl.trim();
    if (clean.isEmpty) {
      return sha256.convert(utf8.encode('empty_image_${DateTime.now().millisecondsSinceEpoch}')).toString();
    }

    try {
      if (clean.startsWith('/') || clean.contains('\\') || clean.startsWith('file:')) {
        final filePath = clean.replaceFirst('file://', '');
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            return sha256.convert(bytes).toString();
          }
        }
      }
    } catch (_) {}

    // Fallback: deterministic cryptographic hash based on path or URL string
    return sha256.convert(utf8.encode(clean)).toString();
  }

  /// Synchronous version for instant mapping
  static String computeHashSync(String pathOrUrl) {
    final clean = pathOrUrl.trim();
    if (clean.isEmpty) {
      return sha256.convert(utf8.encode('empty_image_${DateTime.now().millisecondsSinceEpoch}')).toString();
    }

    try {
      if (clean.startsWith('/') || clean.contains('\\') || clean.startsWith('file:')) {
        final filePath = clean.replaceFirst('file://', '');
        final file = File(filePath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          if (bytes.isNotEmpty) {
            return sha256.convert(bytes).toString();
          }
        }
      }
    } catch (_) {}

    return sha256.convert(utf8.encode(clean)).toString();
  }
}
