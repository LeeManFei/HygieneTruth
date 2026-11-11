import '../utils/heatmap_zone.dart';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/complaint_model.dart';
import '../models/restaurant_model.dart';
import '../utils/image_hash_helper.dart';

/// Layer identifiers emitted in [VerificationCheckResult.triggeredLayers].
class DuplicateLayer {
  static const String imageHash = 'IMAGE_HASH';
  static const String activeCase = 'ACTIVE_CASE';
  static const String gpsFence = 'GPS_FENCE';
  static const String spamBurst = 'SPAM_BURST';
  static const String textSimilarity = 'TEXT_SIMILARITY';

  /// Human-readable short labels for UI chips.
  static const Map<String, String> labels = {
    imageHash: 'Photo Hash',
    activeCase: 'Open Case',
    gpsFence: 'GPS Fence',
    spamBurst: 'Burst Spam',
    textSimilarity: 'Text Match',
  };
}

class VerificationCheckResult {
  final bool isFlagged;
  final bool isDuplicate;
  final bool isFakeSuspected;
  final String? flagReason;
  final String? matchedComplaintId;
  final String? matchedImageUrl;
  final double confidenceScore;
  final List<String> riskFactors;
  final String recommendation;

  /// Which detection layers fired, e.g. [DuplicateLayer.imageHash].
  final List<String> triggeredLayers;

  /// Highest token-similarity ratio found by the text layer (0.0 - 1.0).
  final double textSimilarity;

  const VerificationCheckResult({
    required this.isFlagged,
    required this.isDuplicate,
    required this.isFakeSuspected,
    this.flagReason,
    this.matchedComplaintId,
    this.matchedImageUrl,
    required this.confidenceScore,
    required this.riskFactors,
    required this.recommendation,
    this.triggeredLayers = const [],
    this.textSimilarity = 0.0,
  });

  /// Confidence at or above which a duplicate is merged into its master case
  /// automatically (exact byte-level photo collision).
  static const double autoMergeThreshold = 95.0;

  bool get isAutoMergeCandidate =>
      isDuplicate &&
      confidenceScore >= autoMergeThreshold &&
      matchedComplaintId != null;
}

class AiDuplicateAnalysisResult {
  final bool gpsPassed;
  final bool timingPassed;
  final bool scanComplete;
  final String gpsMessage;
  final String timingMessage;
  bool get canApprove => gpsPassed && timingPassed && scanComplete && !isDuplicate;
  final double hexMatchScore; // 0.0 to 100.0 (byte-level hash comparison)
  final double aiSemanticScore; // 0.0 to 100.0 (evidence correlation score)
  final bool isDuplicate;
  final String confidenceLevel; // 'HIGH RISK DUPLICATE', 'MODERATE SIMILARITY', 'UNIQUE ORIGINAL', 'SUSPECTED FAKE'
  final String detectedScene; // Derived from the report's declared category
  final List<String> detectedObjects; // Derived from the report's declared issues
  final List<String> matchedAiFeatures; // Real risk factors / comparison notes
  final String hexHash;
  final String? matchedComplaintId;
  final String? matchedImageUrl;
  final String? matchedUploadedImageUrl;
  final String aiVerdict;

  const AiDuplicateAnalysisResult({
    this.gpsPassed = false, this.timingPassed = false, this.scanComplete = false,
    this.gpsMessage = 'Not checked', this.timingMessage = 'Not checked',
    required this.hexMatchScore,
    required this.aiSemanticScore,
    required this.isDuplicate,
    required this.confidenceLevel,
    required this.detectedScene,
    required this.detectedObjects,
    required this.matchedAiFeatures,
    required this.hexHash,
    this.matchedComplaintId,
    this.matchedImageUrl,
    this.matchedUploadedImageUrl,
    required this.aiVerdict,
  });

  double get overallRiskScore => max(hexMatchScore, aiSemanticScore);
}

class AiDuplicateDetectorService {
  /// Compute Hex SHA-256 Hash of image path or URL.
  /// Local files are hashed from raw bytes; remote URLs fall back to a
  /// deterministic string hash (consistent with complaint_photos.image_hash).
  static String computeHexHash(String input) {
    return ImageHashHelper.computeHashSync(input);
  }

  /// Calculate distance in km between two GPS coordinates using Haversine formula
  static double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  // ---------------------------------------------------------------------------
  // TEXT SIMILARITY (token Jaccard on normalized description + issues)
  // ---------------------------------------------------------------------------

  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be', 'been',
    'at', 'in', 'on', 'of', 'to', 'for', 'with', 'very', 'so', 'it', 'its', 'this',
    'that', 'i', 'we', 'they', 'there', 'here', 'my', 'our', 'their', 'you',
    'saya', 'dan', 'yang', 'di', 'ke', 'ada', 'itu', 'ini', 'kami', 'kita', 'dia',
  };

  static Set<String> _tokenize(String text) {
    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3 && !_stopWords.contains(t))
        .toSet();
  }

  /// Jaccard similarity between two free-text blobs (0.0 - 1.0).
  static double computeTextSimilarity(String textA, String textB) {
    final tokensA = _tokenize(textA);
    final tokensB = _tokenize(textB);
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;
    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  static String _complaintTextBlob(ComplaintModel c) {
    return '${c.description} ${c.issues.join(' ')} ${c.category}';
  }

  static String _shortId(String id) =>
      id.substring(0, min(8, id.length)).toUpperCase();

  /// Run Comprehensive Multi-Layer Verification & Duplicate Analysis Check.
  ///
  /// Layers (in confidence priority order):
  ///  1. IMAGE_HASH      - exact byte/URL collision across ALL photos (99.2)
  ///  2. GPS_FENCE       - submitter >2km from registered venue (92.0)
  ///  3. ACTIVE_CASE     - open case for same venue within 7 days (88.5)

  ///  4. SPAM_BURST      - same user filed >=3 reports within 24h (85.0)
  ///  5. TEXT_SIMILARITY - reworded text overlap >=0.75 same venue/user (80.0)
  static VerificationCheckResult performFullVerificationCheck({
    required ComplaintModel complaint,
    required List<ComplaintModel> existingComplaints,
    List<RestaurantModel>? restaurants,
  }) {
    final List<String> riskFactors = [];
    final List<String> triggeredLayers = [];
    bool isDuplicate = false;
    bool isFake = false;
    String? matchedParentId;
    String? matchedImg;
    double confidenceScore = 0.0;
    double bestTextSimilarity = 0.0;
    String? primaryFlagReason;

    // Pre-compute incoming photo hashes once (ALL photos, not just the first).
    final List<_PhotoFingerprint> incomingPrints = complaint.photoUrls
        .where((p) => p.trim().isNotEmpty)
        .map((p) => _PhotoFingerprint(url: p, hash: computeHexHash(p)))
        .toList();

    // 1. IMAGE HASH & URL DUPLICATE CHECK (multi-photo, multi-target)
    if (incomingPrints.isNotEmpty) {
      outer:
      for (final other in existingComplaints) {
        if (other.id == complaint.id) continue;
        for (final otherUrl in other.photoUrls) {
          if (otherUrl.trim().isEmpty) continue;
          final otherHash = computeHexHash(otherUrl);
          for (final inc in incomingPrints) {
            if (inc.url == otherUrl || inc.hash == otherHash) {
              isDuplicate = true;
              triggeredLayers.add(DuplicateLayer.imageHash);
              matchedParentId ??= other.id;
              matchedImg ??= otherUrl;
              confidenceScore = max(confidenceScore, 99.2);
              riskFactors.add(
                  'Identical SHA-256 photo collision with Report #${_shortId(other.id)}');
              primaryFlagReason ??=
                  'Duplicate Photo Evidence Collision (Matches Report #${_shortId(other.id)})';
              break outer;
            }
          }
        }
      }
    }

    // 2. GPS GEO-FENCING DISTANCE CHECK (> 2.0 km from registered venue location)
    if (restaurants != null && restaurants.isNotEmpty) {
      final matchedRest = restaurants.where((r) =>
          (complaint.restaurantId.isNotEmpty && r.id == complaint.restaurantId) ||
          r.name.toLowerCase() == complaint.restaurantName.toLowerCase()).firstOrNull;

      if (matchedRest != null && matchedRest.latitude != 0 && matchedRest.longitude != 0 &&
          complaint.latitude != 0 && complaint.longitude != 0) {
        final dist = calculateDistanceKm(complaint.latitude, complaint.longitude,
            matchedRest.latitude, matchedRest.longitude);
        if (dist > 2.0) {
          isFake = true;
          triggeredLayers.add(DuplicateLayer.gpsFence);
          confidenceScore = max(confidenceScore, 92.0);
          riskFactors.add(
              'GPS Distance Mismatch: Submitter is ${dist.toStringAsFixed(1)}km away from registered venue GPS');
          primaryFlagReason ??=
              'GPS Geo-Fence Mismatch: Submitter located ${dist.toStringAsFixed(1)}km away from outlet coordinates';
        }
      }
    }

    // 3. VENUE & TIME WINDOW COLLISION (same restaurant, open case within 7 days with overlapping category/issues)
    if (!isDuplicate) {
      for (final other in existingComplaints) {
        if (other.id == complaint.id) continue;
        final bool sameRest =
            (other.restaurantId.isNotEmpty && other.restaurantId == complaint.restaurantId) ||
                (other.restaurantName.toLowerCase().trim() == complaint.restaurantName.toLowerCase().trim());
        final bool isResolved = other.status == ComplaintStatus.resolved;

        // Check if category or issues overlap as well, instead of blindly flagging any report against the same restaurant
        final bool sameCategory = complaint.category.trim().toLowerCase() == other.category.trim().toLowerCase();
        final bool sameUser = complaint.userId.isNotEmpty && other.userId.isNotEmpty && other.userId == complaint.userId;
        final bool hasOverlappingIssues = complaint.issues.any((iss) => other.issues.contains(iss));

        if (sameRest && !isResolved && (sameUser || sameCategory || hasOverlappingIssues)) {
          try {
            final dtComplaint = DateTime.parse(complaint.submittedAt);
            final dtOther = DateTime.parse(other.submittedAt);
            final diffDays = dtComplaint.difference(dtOther).inDays.abs();
            if (diffDays <= 7) {
              // Only flag as duplicate if same user repeating identical category/issues, or identical category with overlapping issues
              if (sameUser && (sameCategory || hasOverlappingIssues)) {
                isDuplicate = true;
                triggeredLayers.add(DuplicateLayer.activeCase);
                matchedParentId ??= other.id;
                matchedImg ??= other.photoUrls.isNotEmpty ? other.photoUrls.first : null;
                confidenceScore = max(confidenceScore, 88.5);
                riskFactors.add(
                    'Active inspection case already open for ${complaint.restaurantName} in "${complaint.category}" (Report #${_shortId(other.id)})');
                primaryFlagReason ??=
                    'Active Case Collision: Report #${_shortId(other.id)} already filed for ${complaint.restaurantName} in ${complaint.category}';
                break;
              } else if (sameCategory && hasOverlappingIssues) {
                isDuplicate = true;
                triggeredLayers.add(DuplicateLayer.activeCase);
                matchedParentId ??= other.id;
                matchedImg ??= other.photoUrls.isNotEmpty ? other.photoUrls.first : null;
                confidenceScore = max(confidenceScore, 85.0);
                riskFactors.add(
                    'Overlapping complaint already open for ${complaint.restaurantName} in "${complaint.category}" (Report #${_shortId(other.id)})');
                primaryFlagReason ??=
                    'Active Investigation in Progress (Report #${_shortId(other.id)} filed within 7 days)';
                break;
              }
            }
          } catch (_) {}
        }
      }
    }


    // 4. REPETITIVE SUBMITTER SPAM CHECK (rate + distinct-venue breadth)
    if (complaint.userId.isNotEmpty) {
      final userRecentReports = existingComplaints.where((c) {
        if (c.id == complaint.id || c.userId != complaint.userId) return false;
        try {
          final d1 = DateTime.parse(complaint.submittedAt);
          final d2 = DateTime.parse(c.submittedAt);
          return d1.difference(d2).inHours.abs() < 24;
        } catch (_) {
          return false;
        }
      }).toList();

      if (userRecentReports.length >= 2) {
        // >=2 priors + current one => 3 reports in 24h
        final distinctVenues = userRecentReports
            .map((c) => c.restaurantName.toLowerCase())
            .toSet()
            .length;
        isFake = true;
        triggeredLayers.add(DuplicateLayer.spamBurst);
        confidenceScore = max(confidenceScore, 85.0);
        riskFactors.add(
            'Rapid-fire rate limit: Submitter filed ${userRecentReports.length + 1} reports in 24 hours${
                distinctVenues > 1 ? ' across $distinctVenues different outlets' : ''}');
        primaryFlagReason ??=
            'Rapid Submissions: ${userRecentReports.length + 1} reports submitted in 24h by same user';
      }
    }

    // 5. TEXT SIMILARITY CHECK (reworded duplicates against same venue or same user)
    if (!isDuplicate) {
      final incomingText = _complaintTextBlob(complaint);
      for (final other in existingComplaints) {
        if (other.id == complaint.id) continue;
        final bool sameVenue =
            (other.restaurantId.isNotEmpty && other.restaurantId == complaint.restaurantId) ||
                (other.restaurantName.toLowerCase() == complaint.restaurantName.toLowerCase());
        final bool sameUser =
            complaint.userId.isNotEmpty && other.userId == complaint.userId;
        if (!sameVenue && !sameUser) continue;
        if (other.status == ComplaintStatus.rejected ||
            other.status == ComplaintStatus.resolved) {
          continue;
        }
        final similarity = computeTextSimilarity(incomingText, _complaintTextBlob(other));
        if (similarity >= 0.75) {
          isDuplicate = true;
          triggeredLayers.add(DuplicateLayer.textSimilarity);
          bestTextSimilarity = max(bestTextSimilarity, similarity);
          matchedParentId ??= other.id;
          matchedImg ??= other.photoUrls.isNotEmpty ? other.photoUrls.first : null;
          confidenceScore = max(confidenceScore, 80.0 + (similarity * 10));
          riskFactors.add(
              'Textual overlap ${(similarity * 100).toStringAsFixed(0)}% with Report #${_shortId(other.id)} (${sameVenue ? 'same venue' : 'same submitter'})');
          primaryFlagReason ??=
              'Reworded Duplicate Suspected: ${(similarity * 100).toStringAsFixed(0)}% narrative overlap with Report #${_shortId(other.id)}';
          break;
        }
      }
    }

    final bool isFlagged = isDuplicate || isFake;
    String recommendation = 'Clean Original: Safe to assign to Health Officer';
    if (isAutoMergeEligible(isDuplicate, confidenceScore, matchedParentId)) {
      recommendation =
          'AUTO-MERGE ELIGIBLE (${confidenceScore.toStringAsFixed(1)}%): identical evidence of an active master case. Merging automatically.';
    } else if (isDuplicate) {
      recommendation =
          'Merge with Master Case #${matchedParentId != null ? _shortId(matchedParentId) : "EXISTING"} to prevent duplicate inspection visits.';
    } else if (isFake) {
      recommendation =
          'Review GPS / User Spam metrics. Dismiss fake report if location is spoofed.';
    }

    return VerificationCheckResult(
      isFlagged: isFlagged,
      isDuplicate: isDuplicate,
      isFakeSuspected: isFake,
      flagReason: primaryFlagReason,
      matchedComplaintId: matchedParentId,
      matchedImageUrl: matchedImg,
      confidenceScore: confidenceScore,
      riskFactors: riskFactors,
      recommendation: recommendation,
      triggeredLayers: triggeredLayers,
      textSimilarity: bestTextSimilarity,
    );
  }

  static bool isAutoMergeEligible(
      bool isDuplicate, double confidence, String? masterId) {
    return isDuplicate &&
        confidence >= VerificationCheckResult.autoMergeThreshold &&
        masterId != null;
  }

  // ---------------------------------------------------------------------------
  // SCAN RECORD PERSISTENCE (local audit of the last automated scan per report)
  // ---------------------------------------------------------------------------

  static Future<void> saveScanRecord(
      String complaintId, VerificationCheckResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final record = {
        'confidence': result.confidenceScore,
        'layers': result.triggeredLayers,
        'matched_id': result.matchedComplaintId,
        'risk_factors': result.riskFactors,
        'recommendation': result.recommendation,
        'scanned_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(
        'complaint_duplicate_scan_$complaintId',
        jsonEncode(record),
      );
      scanRecordCache[complaintId] = record;
    } catch (_) {}
  }

  /// In-memory mirror of persisted scan records for synchronous UI access.
  static final Map<String, Map<String, dynamic>> scanRecordCache = {};

  static const String _scanKeyPrefix = 'complaint_duplicate_scan_';

  /// Loads every persisted scan record into [scanRecordCache] (call once).
  static Future<void> hydrateScanRecordCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_scanKeyPrefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          scanRecordCache[key.substring(_scanKeyPrefix.length)] =
              jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Map<String, dynamic>? getScanRecord(String complaintId) {
    return scanRecordCache[complaintId];
  }

  static String? scanAgeText(Map<String, dynamic>? record) {
    if (record == null) return null;
    try {
      final ts = DateTime.parse(record['scanned_at'] as String);
      final diff = DateTime.now().difference(ts);
      if (diff.inMinutes < 1) return 'Scanned just now';
      if (diff.inMinutes < 60) return 'Scanned ${diff.inMinutes}m ago';
      if (diff.inHours < 24) return 'Scanned ${diff.inHours}h ago';
      return 'Scanned ${diff.inDays}d ago';
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HONEST EVIDENCE ANALYSIS (no fabricated scores or placeholder imagery)
  // ---------------------------------------------------------------------------

  /// Deterministic analysis built strictly from real comparisons:
  ///  - hexMatchScore is 100 only when an actual byte/URL match exists.
  ///  - semantic score reflects the strongest real correlation signal found
  ///    (hash collision > textual overlap > contextual collisions).
  ///  - scene/objects derive from the report's own category & issue list.
  ///  - no placeholder images, no forced verdicts, no artificial latency.
  static Future<AiDuplicateAnalysisResult> analyzeComplaintEvidence({
    required ComplaintModel complaint,
    List<ComplaintModel>? databaseComplaints,
    List<RestaurantModel>? databaseRestaurants,
  }) async {
    final notes = <String>[];
    final submitted = DateTime.tryParse(complaint.submittedAt)?.toUtc();
    final gps = complaint.evidenceContext;
    final lat = (gps['reporter_latitude'] as num?)?.toDouble();
    final lon = (gps['reporter_longitude'] as num?)?.toDouble();
    final accuracy = (gps['accuracy_meters'] as num?)?.toDouble();
    final captured = DateTime.tryParse(gps['location_captured_at']?.toString() ?? '')?.toUtc();
    final venue = (databaseRestaurants ?? []).where((r) => r.id == complaint.restaurantId).firstOrNull;
    bool gpsPassed = false;
    String gpsMessage = 'UNVERIFIED: Reporter GPS or registered outlet is missing; outlet coordinates are not reporter evidence.';
    if (venue != null && lat != null && lon != null && accuracy != null && captured != null && submitted != null) {
      final valid = gps['outlet_registered'] != false && lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180 &&
        venue.latitude.isFinite && venue.longitude.isFinite && venue.latitude.abs() <= 90 && venue.longitude.abs() <= 180 &&
        accuracy.isFinite && accuracy >= 0 && accuracy <= 100 && gps['is_mocked'] == false &&
        submitted.difference(captured).inSeconds.abs() <= 300;
      final radius = HeatmapZone.radiusMeters(venue);
      final distance = valid ? calculateDistanceKm(lat, lon, venue.latitude, venue.longitude) * 1000 : double.infinity;
      gpsPassed = valid && distance + accuracy <= radius;
      gpsMessage = !valid ? 'FLAGGED: GPS is stale, mocked, invalid, less accurate than 100 m, or the outlet is unregistered.' :
        '${gpsPassed ? 'PASSED' : 'FLAGGED'}: ${distance.toStringAsFixed(0)} m from outlet; zone ${radius.toStringAsFixed(0)} m; accuracy +/-${accuracy.toStringAsFixed(0)} m. ${gpsPassed ? 'Inside restaurant heatmap zone.' : 'Outside or uncertain at zone boundary.'}';
    }
    if (!gpsPassed) notes.add(gpsMessage);
    bool complete = databaseComplaints != null && databaseRestaurants != null && complaint.photoUrls.isNotEmpty;
    bool reportSpam = false, photoSpam = false;
    double hexScore = 0, semanticScore = 0;
    String? matchedId, matchedImage, matchedUploaded;
    final hashes = <String, Future<String?>>{};
    Future<String?> hash(String path) => hashes.putIfAbsent(path, () async {
      try { return await ImageHashHelper.computeEvidenceHash(path); }
      catch (_) { complete = false; return null; }
    });
    final incoming = await Future.wait(complaint.photoUrls.map(hash));
    final uploadedPhotosReadable = incoming.isNotEmpty && incoming.every((value) => value != null);
    final knownIncoming = incoming.whereType<String>().toSet();
    if (knownIncoming.length < incoming.whereType<String>().length) {
      photoSpam = true; hexScore = 100;
      notes.add('Same photo attached more than once in this report.');
    }
    if (submitted == null || submitted.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) complete = false;
    for (final other in databaseComplaints ?? <ComplaintModel>[]) {
      if (other.id == complaint.id) continue;
      final date = DateTime.tryParse(other.submittedAt)?.toUtc();
      if (submitted == null || date == null) { complete = false; continue; }
      if (date.isAfter(submitted) || date == submitted && other.id.compareTo(complaint.id) > 0) continue;
      final age = submitted.difference(date);
      if (age > const Duration(days: 7)) continue;
      final sameUser = complaint.userId.isNotEmpty && complaint.userId == other.userId;
      final sameVenue = complaint.restaurantId.isNotEmpty && complaint.restaurantId == other.restaurantId;
      if (sameUser && sameVenue && age <= const Duration(minutes: 10)) reportSpam = true;
      if ((sameUser || sameVenue) && age <= const Duration(days: 7)) {
        final score = computeTextSimilarity("${complaint.description} ${complaint.issues.join(' ')}",
          "${other.description} ${other.issues.join(' ')}") * 100;
        if (score > semanticScore) { semanticScore = score; if (hexScore == 0) { matchedId = other.id; matchedImage = other.photoUrls.firstOrNull; } }
      }
      final otherHashes = await Future.wait(other.photoUrls.map(hash));
      for (var i = 0; i < otherHashes.length; i++) {
        if (otherHashes[i] != null && knownIncoming.contains(otherHashes[i])) {
          hexScore = 100; matchedId = other.id; matchedImage = other.photoUrls[i];
          matchedUploaded = complaint.photoUrls[incoming.indexOf(otherHashes[i])];
          if (age <= const Duration(hours: 24)) photoSpam = true;
        }
      }
    }
    final timingPassed = complete && submitted != null && !reportSpam && !photoSpam;
    final timingMessage = reportSpam || photoSpam
      ? 'FLAGGED: ${photoSpam ? 'Repeated photo evidence within 24 hours or this report. ' : ''}${reportSpam ? 'Same user reported this outlet within 10 minutes.' : ''}'
      : !complete ? (uploadedPhotosReadable ? 'UNVERIFIED: Uploaded photos are readable, but recent comparison records could not be checked.' : 'UNVERIFIED: One or more uploaded photos could not be read.') : submitted == null ? 'UNVERIFIED: Submission timestamp missing.' : 'PASSED: No repeated photo within 24 hours or same-user outlet report within 10 minutes. Uses report receipt times, not camera EXIF.';
    if (!timingPassed) notes.add(timingMessage);
    if (!complete) notes.add('Approval is blocked until missing photos, timestamps or recent comparison data can be checked.');
    notes.add('Comparison window: the seven days preceding this report; older records are excluded.');
    final risk = max(hexScore, semanticScore);
    if (hexScore == 100) notes.add('Layer 1: Identical photo bytes found; exact SHA-256 match takes priority.');
    notes.add('Layer 2: ${semanticScore.toStringAsFixed(1)}% report text overlap; this is not a visual-image probability.');
    return AiDuplicateAnalysisResult(gpsPassed: gpsPassed, timingPassed: timingPassed, scanComplete: complete,
      gpsMessage: gpsMessage, timingMessage: timingMessage,
      hexMatchScore: hexScore, aiSemanticScore: semanticScore, isDuplicate: risk >= 50,
      confidenceLevel: risk >= 80 ? 'RED - FLAGGED' : risk >= 50 ? 'YELLOW - REVIEW' : 'GREEN - LOW MATCH',
      detectedScene: complaint.category, detectedObjects: complaint.issues,
      matchedAiFeatures: notes, hexHash: knownIncoming.firstOrNull ?? 'Unavailable',
      matchedComplaintId: matchedId, matchedImageUrl: matchedImage, matchedUploadedImageUrl: matchedUploaded,
      aiVerdict: risk >= 50 || !gpsPassed || !timingPassed || !complete ? 'Approval blocked: resolve the verification findings.' : 'Checks passed for the loaded comparison records.');
  }

}

class _PhotoFingerprint {
  final String url;
  final String hash;
  const _PhotoFingerprint({required this.url, required this.hash});
}
