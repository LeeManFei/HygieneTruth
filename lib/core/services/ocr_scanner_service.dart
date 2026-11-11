import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_env.dart';

enum OcrVerdict { verified, review, rejected }

class OcrQualityMetrics {
  final int width;
  final int height;
  final double meanLuminance;
  final double blurScore;
  final bool passesQuality;
  final String? qualityIssue;

  const OcrQualityMetrics({
    required this.width,
    required this.height,
    required this.meanLuminance,
    required this.blurScore,
    required this.passesQuality,
    this.qualityIssue,
  });
}

class OcrScannerResult {
  final bool isDocument;
  final bool isSSMCertificate;
  final double confidenceScore;
  final OcrVerdict verdict;
  final String? failureReason;
  final String? extractedCompanyName;
  final String? extractedRegistrationNo;
  final List<String> detectedOcrFeatures;
  final String? extractedText;
  final OcrQualityMetrics? quality;
  final List<String> sourcesUsed;

  const OcrScannerResult({
    required this.isDocument,
    required this.isSSMCertificate,
    required this.confidenceScore,
    required this.verdict,
    this.failureReason,
    this.extractedCompanyName,
    this.extractedRegistrationNo,
    this.detectedOcrFeatures = const [],
    this.extractedText,
    this.quality,
    this.sourcesUsed = const [],
  });
}

class _EvidenceResult {
  final double keywordScore;
  final String? registrationNo;
  final String? companyName;
  final List<String> matchedKeywords;

  const _EvidenceResult({
    required this.keywordScore,
    this.registrationNo,
    this.companyName,
    this.matchedKeywords = const [],
  });
}

class OcrScannerService {
  static const double _verifyThreshold = 0.75;
  static const double _reviewThreshold = 0.50;

  static const Map<String, double> _keywordWeights = {
    'suruhanjaya syarikat malaysia': 0.30,
    'companies commission of malaysia': 0.25,
    'akta syarikat': 0.12,
    'companies act': 0.12,
    'akta 777': 0.05,
    'sijil pendaftaran': 0.12,
    'certificate of incorporation': 0.12,
    'perakuan pendaftaran': 0.12,
    'registration of businesses': 0.08,
    'akta pendaftaran perniagaan': 0.08,
    'business registration act': 0.08,
    'sdn. bhd': 0.06,
    'sdn bhd': 0.06,
    'sendirian berhad': 0.06,
    'enterprise': 0.04,
    'perniagaan': 0.04,
    'no. pendaftaran': 0.08,
    'registration no': 0.08,
    'no. syarikat': 0.08,
    'company no': 0.06,
    'certified true copy': 0.05,
    'matriks': 0.03,
    'waktu perniagaan': 0.03,
  };

  static final RegExp _regNoNewFormat = RegExp(r'\b(\d{12})\b');
  static final RegExp _regNoLegacyFormat = RegExp(r'\b(\d{6,7})\s*-\s*([A-ZV])\b');

  /// Multi-layer SSM document verification:
  /// Layer 0: image quality gate (resolution / luminance / blur)
  /// Layer 1: on-device ML Kit text recognition (offline, bundled model)
  /// Layer 2: SSM evidence scoring (keywords + registration-number formats + company name)
  /// Layer 3: Gemini Vision cross-verification (fused when API key available)
  /// No fabricated fallbacks: without real evidence the document is rejected.
  static Future<OcrScannerResult> analyzeDocument(XFile xFile) async {
    final List<String> sourcesUsed = [];
    try {
      final Uint8List imageBytes = await xFile.readAsBytes();
      if (imageBytes.isEmpty) {
        return _reject('File Error: Uploaded image file is empty or unreadable.');
      }

      // ---------- LAYER 0: IMAGE QUALITY GATE ----------
      final quality = await _analyzeQuality(imageBytes);
      if (!quality.passesQuality) {
        return OcrScannerResult(
          isDocument: false,
          isSSMCertificate: false,
          confidenceScore: 0.10,
          verdict: OcrVerdict.rejected,
          failureReason: quality.qualityIssue ??
              'Image Quality Gate Rejected: photo is not suitable for document verification.',
          quality: quality,
          sourcesUsed: const ['QUALITY_GATE'],
        );
      }

      double qualityPenalty = 0.0;
      if (quality.blurScore < 35) qualityPenalty += 0.08;
      if (quality.meanLuminance < 60 || quality.meanLuminance > 225) qualityPenalty += 0.08;

      // ---------- LAYER 1: ON-DEVICE ML KIT TEXT RECOGNITION ----------
      String extractedText = '';
      try {
        final inputImage = InputImage.fromFilePath(xFile.path);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final recognized = await textRecognizer.processImage(inputImage);
        extractedText = recognized.text;
        await textRecognizer.close();
        if (extractedText.trim().isNotEmpty) sourcesUsed.add('MLKIT_ONDEVICE');
      } catch (mlkitErr) {
        if (kDebugMode) {
          debugPrint('[OcrScannerService] ML Kit unavailable: $mlkitErr');
        }
      }

      // ---------- LAYER 2: SSM EVIDENCE SCORING ENGINE ----------
      final evidence = _extractEvidence(extractedText);

      double onDeviceConfidence = 0.0;
      if (extractedText.trim().isNotEmpty) {
        onDeviceConfidence =
            (evidence.keywordScore + (evidence.registrationNo != null ? 0.20 : 0.0) + (evidence.companyName != null ? 0.10 : 0.0))
                .clamp(0.0, 0.95);
        onDeviceConfidence = (onDeviceConfidence - qualityPenalty).clamp(0.0, 1.0);
      }

      // ---------- LAYER 3: GEMINI VISION CROSS-VERIFICATION ----------
      double? geminiConfidence;
      String? geminiCompany;
      String? geminiRegNo;
      String? geminiFailure;
      List<String> geminiKeywords = const [];
      bool? geminiValid;
      final String geminiApiKey = AppEnv.geminiApiKey.trim();
      if (geminiApiKey.isNotEmpty) {
        try {
          final gemini = await _callGeminiVision(imageBytes, xFile.name);
          if (gemini != null) {
            geminiValid = gemini['is_valid'] == true;
            geminiConfidence = (gemini['confidence_score'] as num?)?.toDouble();
            geminiCompany = gemini['company_name']?.toString();
            geminiRegNo = gemini['registration_no']?.toString();
            geminiFailure = gemini['failure_reason']?.toString();
            if (gemini['detected_keywords'] is List) {
              geminiKeywords = (gemini['detected_keywords'] as List).map((e) => e.toString()).toList();
            }
            sourcesUsed.add('GEMINI_VISION');
          }
        } catch (visionErr) {
          if (kDebugMode) {
            debugPrint('[OcrScannerService] Gemini Vision note: $visionErr');
          }
        }
      }

      // ---------- FUSION & VERDICT ----------
      double finalConfidence;
      if (geminiConfidence != null && extractedText.trim().isNotEmpty) {
        finalConfidence = (onDeviceConfidence * 0.5) + (geminiConfidence * 0.5);
        if (geminiValid == false && onDeviceConfidence < _verifyThreshold) {
          finalConfidence = finalConfidence * 0.8;
        }
      } else if (geminiConfidence != null) {
        finalConfidence = geminiValid == false ? geminiConfidence * 0.5 : geminiConfidence;
      } else if (extractedText.trim().isNotEmpty) {
        finalConfidence = onDeviceConfidence;
      } else {
        return OcrScannerResult(
          isDocument: false,
          isSSMCertificate: false,
          confidenceScore: 0.05,
          verdict: OcrVerdict.rejected,
          failureReason:
              'OCR Rejected: No readable text could be extracted from this image, and no cloud verification was available. Please upload a clear photo of the SSM certificate.',
          quality: quality,
          sourcesUsed: sourcesUsed,
        );
      }

      final String? company = _preferFilled(geminiCompany, evidence.companyName);
      final String? regNo = _preferFilled(geminiRegNo, evidence.registrationNo);

      final List<String> features = [
        ...evidence.matchedKeywords.map((k) => k.toUpperCase()),
        if (evidence.registrationNo != null) 'SSM_REGISTRATION_FORMAT_VALID',
        if (quality.blurScore >= 35) 'IMAGE_SHARPNESS_OK',
        ...geminiKeywords.map((k) => 'AI: $k'),
      ];

      final OcrVerdict verdict;
      final bool isSSM;
      String? failure;
      if (finalConfidence >= _verifyThreshold && (regNo != null || geminiValid == true)) {
        verdict = OcrVerdict.verified;
        isSSM = true;
      } else if (finalConfidence >= _reviewThreshold && (regNo != null || evidence.keywordScore >= 0.25 || geminiValid == true)) {
        verdict = OcrVerdict.review;
        isSSM = true;
        failure = 'Low-to-medium confidence (${(finalConfidence * 100).toStringAsFixed(0)}%). Please confirm the extracted details below before submitting — this submission will be flagged for admin review.';
      } else {
        verdict = OcrVerdict.rejected;
        isSSM = false;
        failure = geminiFailure ??
            'Document Rejected: No credible SSM certificate evidence detected'
                '${extractedText.trim().isEmpty ? ' (no readable text found in image)' : ' (extracted text did not match official SSM certificate patterns)'}'
                '. Confidence ${(finalConfidence * 100).toStringAsFixed(0)}%.';
      }

      return OcrScannerResult(
        isDocument: isSSM,
        isSSMCertificate: isSSM,
        confidenceScore: finalConfidence.clamp(0.0, 1.0),
        verdict: verdict,
        failureReason: failure,
        extractedCompanyName: company,
        extractedRegistrationNo: regNo,
        detectedOcrFeatures: features,
        extractedText: extractedText.trim().isEmpty ? null : extractedText.trim(),
        quality: quality,
        sourcesUsed: sourcesUsed,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OcrScannerService] error: $e');
      }
      return _reject('Document OCR Error: Internal processing error while analyzing document file ($e).');
    }
  }

  static OcrScannerResult _reject(String reason) {
    return OcrScannerResult(
      isDocument: false,
      isSSMCertificate: false,
      confidenceScore: 0.0,
      verdict: OcrVerdict.rejected,
      failureReason: reason,
    );
  }

  static String? _preferFilled(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty && a.trim().toLowerCase() != 'null') return a.trim();
    if (b != null && b.trim().isNotEmpty && b.trim().toLowerCase() != 'null') return b.trim();
    return null;
  }

  // ---------------- LAYER 0: QUALITY ANALYSIS ----------------

  static Future<OcrQualityMetrics> _analyzeQuality(Uint8List bytes) async {
    ui.Image fullImage;
    try {
      final fullCodec = await ui.instantiateImageCodec(bytes);
      final fullFrame = await fullCodec.getNextFrame();
      fullImage = fullFrame.image;
    } catch (_) {
      return const OcrQualityMetrics(
        width: 0,
        height: 0,
        meanLuminance: 0,
        blurScore: 0,
        passesQuality: false,
        qualityIssue: 'Image Quality Gate Rejected: file is not a readable image.',
      );
    }

    final int origW = fullImage.width;
    final int origH = fullImage.height;
    fullImage.dispose();

    if (origW < 400 || origH < 400) {
      return OcrQualityMetrics(
        width: origW,
        height: origH,
        meanLuminance: 0,
        blurScore: 0,
        passesQuality: false,
        qualityIssue: 'Image Quality Gate Rejected: resolution ${origW}x$origH is too low for document verification (minimum 400px).',
      );
    }

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final w = image.width;
    final h = image.height;
    image.dispose();

    if (byteData == null) {
      return OcrQualityMetrics(
        width: origW,
        height: origH,
        meanLuminance: 0,
        blurScore: 0,
        passesQuality: false,
        qualityIssue: 'Image Quality Gate Rejected: unable to read image pixel data.',
      );
    }

    final pixels = byteData.buffer.asUint8List();
    final gray = List<int>.filled(w * h, 0);
    double lumSum = 0;
    for (int i = 0, p = 0; i < gray.length; i++, p += 4) {
      final g = (pixels[p] * 0.299 + pixels[p + 1] * 0.587 + pixels[p + 2] * 0.114).round();
      gray[i] = g;
      lumSum += g;
    }
    final double meanLuminance = lumSum / gray.length;
    final double blurScore = _laplacianVariance(gray, w, h);

    if (meanLuminance < 35) {
      return OcrQualityMetrics(
        width: origW,
        height: origH,
        meanLuminance: meanLuminance,
        blurScore: blurScore,
        passesQuality: false,
        qualityIssue: 'Image Quality Gate Rejected: photo is too dark (brightness ${(meanLuminance / 255 * 100).toStringAsFixed(0)}%). Retake in better lighting.',
      );
    }
    if (meanLuminance > 240) {
      return OcrQualityMetrics(
        width: origW,
        height: origH,
        meanLuminance: meanLuminance,
        blurScore: blurScore,
        passesQuality: false,
        qualityIssue: 'Image Quality Gate Rejected: photo is overexposed / washed out. Retake without direct glare.',
      );
    }
    if (blurScore < 10) {
      return OcrQualityMetrics(
        width: origW,
        height: origH,
        meanLuminance: meanLuminance,
        blurScore: blurScore,
        passesQuality: false,
        qualityIssue: 'Image Quality Gate Rejected: photo is too blurry to read document text. Hold the camera steady and retake.',
      );
    }

    return OcrQualityMetrics(
      width: origW,
      height: origH,
      meanLuminance: meanLuminance,
      blurScore: blurScore,
      passesQuality: true,
    );
  }

  static double _laplacianVariance(List<int> gray, int w, int h) {
    double sum = 0;
    double sumSq = 0;
    int n = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final int i = y * w + x;
        final double lap = (gray[i - 1] + gray[i + 1] + gray[i - w] + gray[i + w] - 4 * gray[i]).toDouble();
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    if (n == 0) return 0;
    final double mean = sum / n;
    return sumSq / n - mean * mean;
  }

  // ---------------- LAYER 2: EVIDENCE EXTRACTION ----------------

  static _EvidenceResult _extractEvidence(String text) {
    if (text.trim().isEmpty) {
      return const _EvidenceResult(keywordScore: 0);
    }
    final String normalized = text.toLowerCase().replaceAll('\n', ' ');

    double score = 0;
    final List<String> matched = [];
    _keywordWeights.forEach((keyword, weight) {
      if (normalized.contains(keyword)) {
        score += weight;
        matched.add(keyword);
      }
    });
    score = score.clamp(0.0, 0.85);

    String? regNo;
    for (final match in _regNoNewFormat.allMatches(text)) {
      final candidate = match.group(1)!;
      final year = int.tryParse(candidate.substring(0, 4));
      final month = int.tryParse(candidate.substring(4, 6));
      if (year != null && year >= 1900 && year <= DateTime.now().year && month != null && month >= 1 && month <= 12) {
        regNo = candidate;
        break;
      }
    }
    if (regNo == null) {
      final legacy = _regNoLegacyFormat.firstMatch(text);
      if (legacy != null) {
        regNo = '${legacy.group(1)}-${legacy.group(2)!.toUpperCase()}';
      }
    }

    String? company;
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final companyPattern = RegExp(r'(sdn\.?\s*bhd|sendirian\s*berhad|\bbhd\b|enterprise|perniagaan)', caseSensitive: false);
    for (final line in lines) {
      if (companyPattern.hasMatch(line) && line.length >= 4 && !line.toLowerCase().contains('akta')) {
        company = line.length > 60 ? line.substring(0, 60).trim() : line;
        break;
      }
    }
    if (company == null) {
      for (int i = 0; i < lines.length; i++) {
        final lower = lines[i].toLowerCase();
        if ((lower.contains('nama syarikat') || lower.contains('company name')) && i + 1 < lines.length) {
          company = lines[i + 1].length > 60 ? lines[i + 1].substring(0, 60).trim() : lines[i + 1];
          break;
        }
      }
    }

    return _EvidenceResult(
      keywordScore: score,
      registrationNo: regNo,
      companyName: company,
      matchedKeywords: matched,
    );
  }

  // ---------------- LAYER 3: GEMINI VISION ----------------

  static Future<Map<String, dynamic>?> _callGeminiVision(Uint8List imageBytes, String fileName) async {
    final String base64Image = base64Encode(imageBytes);
    final String mimeType = fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${AppEnv.geminiApiKey.trim()}',
    );

    final requestPayload = {
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': mimeType, 'data': base64Image}
            },
            {
              'text': 'You are an official Malaysian SSM Document Auditor with strict OCR capabilities. '
                  'Extract the ACTUAL visible text from this image. '
                  'Determine if this image is an official Malaysian SSM business registration certificate '
                  '(Suruhanjaya Syarikat Malaysia / Companies Commission of Malaysia / Akta Syarikat 2016 / Akta Pendaftaran Perniagaan 1956). '
                  'If it is any other photo (pet, selfie, food, object, meme, screenshot, unrelated document), is_valid must be false with an explicit failure reason. '
                  'Return strict JSON with keys: is_valid (bool), confidence_score (float 0.0-1.0), company_name (string exactly as printed, or null), '
                  'registration_no (string exactly as printed, or null), document_type (string), failure_reason (string or null), '
                  'detected_keywords (array of official keywords actually visible in the image, e.g. "SURUHANJAYA SYARIKAT MALAYSIA", "AKTA SYARIKAT 2016").'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'response_mime_type': 'application/json',
      }
    };

    final client = HttpClient();
    try {
      final request = await client.postUrl(endpoint);
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(requestPayload));
      final response = await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final responseBody = await response.transform(utf8.decoder).join();
      final parsed = jsonDecode(responseBody);
      final candidates = parsed['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;
      final textPart = candidates[0]['content']['parts'][0]['text']?.toString() ?? '';
      final cleaned = textPart.startsWith('```') ? textPart.split('```').firstWhere((s) => s.trim().startsWith('{'), orElse: () => textPart) : textPart;
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
