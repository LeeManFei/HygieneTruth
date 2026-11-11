import 'package:image_picker/image_picker.dart';
import '../services/ocr_scanner_service.dart';

class SSMValidationResult {
  final bool isValid;
  final bool needsReview;
  final double confidenceScore;
  final String message;
  final String? companyName;
  final String? registrationNo;
  final List<String> detectedOcrKeywords;
  final String? extractedText;
  final List<String> sourcesUsed;

  const SSMValidationResult({
    required this.isValid,
    required this.needsReview,
    required this.confidenceScore,
    required this.message,
    this.companyName,
    this.registrationNo,
    this.detectedOcrKeywords = const [],
    this.extractedText,
    this.sourcesUsed = const [],
  });
}

class SSMValidatorHelper {
  /// Validates whether an uploaded image is an authentic SSM certificate using
  /// the multi-layer OCR engine (quality gate + on-device ML Kit + evidence
  /// scoring + optional Gemini Vision fusion).
  ///
  /// Verdicts:
  /// - confidence >= 0.75  -> verified (isValid = true, needsReview = false)
  /// - confidence >= 0.50  -> review   (isValid = true, needsReview = true, flagged for admin)
  /// - confidence <  0.50  -> rejected (isValid = false)
  static Future<SSMValidationResult> validateSSMCertificate(XFile imageFile) async {
    final ocrResult = await OcrScannerService.analyzeDocument(imageFile);

    if (ocrResult.verdict == OcrVerdict.rejected || !ocrResult.isSSMCertificate || !ocrResult.isDocument) {
      return SSMValidationResult(
        isValid: false,
        needsReview: false,
        confidenceScore: ocrResult.confidenceScore,
        message: ocrResult.failureReason ?? 'Document OCR Scan Rejected: Uploaded file is NOT an official SSM Certificate of Incorporation.',
        detectedOcrKeywords: ocrResult.detectedOcrFeatures,
        extractedText: ocrResult.extractedText,
        sourcesUsed: ocrResult.sourcesUsed,
      );
    }

    if (ocrResult.verdict == OcrVerdict.review) {
      return SSMValidationResult(
        isValid: true,
        needsReview: true,
        confidenceScore: ocrResult.confidenceScore,
        message: ocrResult.failureReason ??
            'Possible SSM certificate detected (${(ocrResult.confidenceScore * 100).toStringAsFixed(0)}% confidence). Please confirm the extracted details — submission will be flagged for admin review.',
        companyName: ocrResult.extractedCompanyName,
        registrationNo: ocrResult.extractedRegistrationNo,
        detectedOcrKeywords: ocrResult.detectedOcrFeatures,
        extractedText: ocrResult.extractedText,
        sourcesUsed: ocrResult.sourcesUsed,
      );
    }

    return SSMValidationResult(
      isValid: true,
      needsReview: false,
      confidenceScore: ocrResult.confidenceScore,
      message: 'Official SSM Certificate of Incorporation (Suruhanjaya Syarikat Malaysia / Akta Syarikat 2016) verified via multi-layer OCR engine'
          '${ocrResult.sourcesUsed.isNotEmpty ? ' (${ocrResult.sourcesUsed.join(" + ")})' : ''}.',
      companyName: ocrResult.extractedCompanyName,
      registrationNo: ocrResult.extractedRegistrationNo,
      detectedOcrKeywords: ocrResult.detectedOcrFeatures,
      extractedText: ocrResult.extractedText,
      sourcesUsed: ocrResult.sourcesUsed,
    );
  }
}
