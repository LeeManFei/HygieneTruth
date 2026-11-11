import '../models/inspection_model.dart';
import '../models/rectification_model.dart';
import '../../notifications/models/notification_model.dart';
import 'notification_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/complaint_model.dart';
import '../models/restaurant_model.dart';
import '../models/user_model.dart';
import '../models/workflow_model.dart';
import '../utils/image_hash_helper.dart';
import '../utils/uuid_helper.dart';
import 'audit_log_service.dart';
import 'customer_store_service.dart';
import 'duplicate_service.dart';
import 'workflow_service.dart';
import 'supabase_service.dart';

class RestaurantRatingInfo {
  final double averageRating;
  final int totalReviews;

  const RestaurantRatingInfo({
    required this.averageRating,
    required this.totalReviews,
  });

  bool get hasReviews => totalReviews > 0;
  String get ratingText => hasReviews ? averageRating.toStringAsFixed(1) : '0.0';
  String get countText => hasReviews ? '($totalReviews)' : '(No Reviews)';
}

class RestaurantRiskEvaluation {
  final double score; // 0.0 to 100.0 (lower is safer)
  final RiskCategory category;
  final String source; // e.g. 'MOH Officer Compliance Decree', 'Customer Reviews & Ratings', 'Baseline Standard'
  final String headline;
  final String explanation;
  final bool isFromOfficer;
  final String officerCitation;

  const RestaurantRiskEvaluation({
    required this.score,
    required this.category,
    required this.source,
    required this.headline,
    required this.explanation,
    this.isFromOfficer = false,
    this.officerCitation = '',
  });
}

class RestaurantStoreService {
  static const Set<String> _legacyMockNames = {
    'golden dragon bistro',
    'golden dragon',
    'zen sushi & teppanyaki',
    'zen sushi',
    'ocean catch seafood restaurant',
    'ocean catch seafood',
    'mamak corner',
    'clean kitchen bistro',
    'chopsticks express',
    'sushi paradise',
    'spice garden indian cuisine',
    'spice garden',
  };

  /// Check if a restaurant name belongs to old legacy mock data
  static bool isLegacyMockName(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    final lower = name.trim().toLowerCase();
    for (final mock in _legacyMockNames) {
      if (lower == mock || lower.contains(mock)) {
        return true;
      }
    }
    return false;
  }

  static RealtimeChannel? _realtimeChannel;

  /// Setup live Supabase Realtime subscriptions across all core tables
  static void initRealtimeSubscriptions() {
    syncRectificationsFromStorage();
    if (_realtimeChannel != null) return;
    try {
      final supabase = SupabaseService.client;
      _realtimeChannel = supabase
          .channel('public:restaurant_store_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'restaurants',
            callback: (payload) {
              debugPrint('⚡ Realtime Supabase Update on [restaurants]: ${payload.eventType}');
              fetchAllRestaurants(forceRefresh: true);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'restaurant_reviews',
            callback: (payload) {
              debugPrint('⚡ Realtime Supabase Update on [restaurant_reviews]');
              fetchAllRestaurants(forceRefresh: true);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'complaints',
            callback: (payload) {
              debugPrint('⚡ Realtime Supabase Update on [complaints]');
              ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inspections',
            callback: (payload) {
              debugPrint('⚡ Realtime Supabase Update on [inspections]');
              fetchInspections();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rectifications',
            callback: (payload) {
              debugPrint('⚡ Realtime Supabase Update on [rectifications]');
              syncRectificationsFromSupabase();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime subscription initialization error: $e');
    }
  }

  static ValueNotifier<List<ComplaintModel>> get complaintsNotifier => ComplaintStoreService.complaintsNotifier;
  static set complaintsNotifier(ValueNotifier<List<ComplaintModel>> val) => ComplaintStoreService.complaintsNotifier.value = val.value;
  static final ValueNotifier<List<InspectionModel>> inspectionsNotifier = ValueNotifier<List<InspectionModel>>([]);

  /// Upload a single inspection photo to Supabase Storage and return its public URL
  static Future<String> uploadInspectionEvidencePhoto(String inspectionId, dynamic photoInput, {int index = 0}) async {
    final String pathStr = photoInput is File ? photoInput.path : photoInput.toString();
    if (pathStr.startsWith('http://') || pathStr.startsWith('https://')) {
      return pathStr;
    }

    try {
      final File file = File(pathStr.startsWith('file://') ? Uri.parse(pathStr).toFilePath() : pathStr);
      if (!file.existsSync()) {
        throw StateError('The selected inspection photo is no longer available.');
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('The selected photo is empty.');
      final String ext = file.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final String fileName = 'insp_${inspectionId}_${DateTime.now().millisecondsSinceEpoch}_$index.$ext';
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Sign in before uploading inspection photos.');
      final String storagePath = 'inspection_evidence/$userId/$fileName';
      final String contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

      final supabase = SupabaseService.client;
      await supabase.storage.from('Images').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: contentType),
      );
      return supabase.storage.from('Images').getPublicUrl(storagePath);
    } catch (e) {
      rethrow;
    }
  }

  /// Save an inspection to in-memory notifier, local SharedPreferences, and Supabase inspections/notices/evidence tables
  static Future<void> saveInspection(InspectionModel newInsp, {List<String>? photoUrls, String stage = 'save'}) async {
    final validId = UuidHelper.toDeterministicUuid(newInsp.id);

    // 1. Process & Upload any local photo files to Supabase Storage
    final List<String> sourcePhotos = List<String>.from(photoUrls ?? newInsp.photoUrls);
    final List<String> uploadedPhotoUrls = [];
    for (int i = 0; i < sourcePhotos.length; i++) {
      final p = sourcePhotos[i];
      final uploaded = await uploadInspectionEvidencePhoto(validId, p, index: i);
      uploadedPhotoUrls.add(uploaded);
    }

    final inspectionWithPhotos = newInsp.copyWith(photoUrls: uploadedPhotoUrls);

    // 4. Upsert to Supabase `inspections` table
    try {
      final supabase = SupabaseService.client;
      final scheduledDt = DateTime.tryParse(inspectionWithPhotos.scheduledDate) ?? DateTime.now();
      final conductedDt = inspectionWithPhotos.conductedDate != null ? DateTime.tryParse(inspectionWithPhotos.conductedDate!) : null;

      // 4.1 Resolve valid restaurant UUID
      final matchedR = restaurantsNotifier.value.where(
        (r) => r.id == inspectionWithPhotos.restaurantId || r.name.toLowerCase().trim() == inspectionWithPhotos.restaurantName.toLowerCase().trim(),
      ).firstOrNull;
      final String validRestId = (matchedR != null && UuidHelper.isValidUuid(matchedR.id))
          ? matchedR.id
          : (UuidHelper.isValidUuid(inspectionWithPhotos.restaurantId)
              ? inspectionWithPhotos.restaurantId
              : UuidHelper.toDeterministicUuid(inspectionWithPhotos.restaurantId.isNotEmpty ? inspectionWithPhotos.restaurantId : inspectionWithPhotos.restaurantName));

      // 4.2 Resolve valid officer ID (null if not authenticated or not a valid UUID to satisfy FK)
      String? validOfficerId;
      final currentCust = CustomerStoreService.currentCustomer;
      if (currentCust != null && UuidHelper.isValidUuid(currentCust.id)) {
        validOfficerId = currentCust.id;
      }

      // 4.3 Resolve valid complaint ID (null if not found/invalid to satisfy FK)
      String? validComplaintId;
      if (inspectionWithPhotos.complaintId.isNotEmpty) {
        if (UuidHelper.isValidUuid(inspectionWithPhotos.complaintId)) {
          validComplaintId = inspectionWithPhotos.complaintId;
        } else {
          final matchedComp = ComplaintStoreService.complaintsNotifier.value.where(
            (c) => c.id == inspectionWithPhotos.complaintId || c.id.toLowerCase().trim() == inspectionWithPhotos.complaintId.toLowerCase().trim(),
          ).firstOrNull;
          if (matchedComp != null && UuidHelper.isValidUuid(matchedComp.id)) {
            validComplaintId = matchedComp.id;
          }
        }
      }

      // Helper converters for strict Postgres enums
      String toDbEnforcementType(EnforcementType type) {
        switch (type) {
          case EnforcementType.warning:
            return 'warning';
          case EnforcementType.fine:
            return 'fine';
          case EnforcementType.closure:
            return 'closure';
          case EnforcementType.none:
            return 'none';
        }
      }

      String toDbEnforcementStatus(EnforcementStatus status) {
        switch (status) {
          case EnforcementStatus.inProgress:
            return 'inProgress';
          case EnforcementStatus.completed:
            return 'enforced';
          case EnforcementStatus.pending:
            return 'pending';
        }
      }

      String toDbOutcome(InspectionOutcome outcome) {
        switch (outcome) {
          case InspectionOutcome.compliant:
            return 'compliant';
          case InspectionOutcome.pending:
            return 'pending';
          case InspectionOutcome.nonCompliant:
            return 'nonCompliant';
        }
      }

      final Map<String, dynamic> inspRow = {
        'id': validId,
        'restaurant_id': validRestId,
        'restaurant_name': inspectionWithPhotos.restaurantName,
        'complaint_id': validComplaintId,
        'officer_id': validOfficerId,
        'officer_name': inspectionWithPhotos.officerName,
        'scheduled_date': scheduledDt.toUtc().toIso8601String(),
        'conducted_date': conductedDt?.toUtc().toIso8601String(),
        'outcome': toDbOutcome(inspectionWithPhotos.outcome),
        'findings': inspectionWithPhotos.findings,
        'recommended_action': toDbEnforcementType(inspectionWithPhotos.recommendedAction),
        'issued_action': toDbEnforcementType(inspectionWithPhotos.issuedAction),
        'justification': inspectionWithPhotos.justification,
        'fine_amount': inspectionWithPhotos.fineAmount,
        'enforcement_status': toDbEnforcementStatus(inspectionWithPhotos.enforcementStatus),
        'statutory_citation': inspectionWithPhotos.statutoryCitation,
        'is_admin_approved': inspectionWithPhotos.isAdminApproved,
        'admin_review_notes': inspectionWithPhotos.adminReviewNotes,
        'issued_date': inspectionWithPhotos.issuedDate,
        'due_date': inspectionWithPhotos.dueDate,
        'is_fine_paid': inspectionWithPhotos.isFinePaid,
        'paid_at': inspectionWithPhotos.paidAt,
        'photo_urls': uploadedPhotoUrls,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final saved = await supabase.rpc('save_inspection_record', params: {
        'p_record': inspRow, 'p_stage': stage,
      });
      await _cacheConfirmedInspection(InspectionModel.fromMap(Map<String, dynamic>.from(saved as Map)));

      // 5. Upsert to Supabase `notices` table
      final noticeId = UuidHelper.toDeterministicUuid('notice_$validId');
      final noticeRow = {
        'id': noticeId,
        'restaurant_id': validRestId,
        'inspection_id': validId,
        'notice_title': 'Hygiene Directive: ${inspectionWithPhotos.restaurantName}',
        'notice_body': inspectionWithPhotos.justification.isNotEmpty ? inspectionWithPhotos.justification : inspectionWithPhotos.findings,
        'deadline_date': (inspectionWithPhotos.dueDate != null ? (DateTime.tryParse(inspectionWithPhotos.dueDate!) ?? DateTime.now().add(const Duration(days: 14))) : DateTime.now().add(const Duration(days: 14))).toUtc().toIso8601String(),
        'status': inspectionWithPhotos.enforcementStatus == EnforcementStatus.completed ? 'resolved' : 'active',
        'resolution_notes': inspectionWithPhotos.enforcementStatus == EnforcementStatus.completed ? 'Rectification verified by health officer.' : null,
        'resolved_at': inspectionWithPhotos.enforcementStatus == EnforcementStatus.completed ? DateTime.now().toUtc().toIso8601String() : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        await supabase.from('notices').upsert(noticeRow);
      } catch (noticeErr) {
        debugPrint('[RestaurantStoreService] Notices upsert notice: $noticeErr');
      }

      // 6. Replace photo evidence so a resubmission never leaves duplicate records.
      try {
        await supabase.from('evidence').delete().eq('inspection_id', validId);
      } catch (evDeleteErr) {
        debugPrint('[RestaurantStoreService] Previous evidence cleanup notice: $evDeleteErr');
      }

      // 7. Upsert the latest photo evidence to Supabase `evidence` table
      if (uploadedPhotoUrls.isNotEmpty) {
        for (final photo in uploadedPhotoUrls) {
          try {
            final evidenceId = UuidHelper.toDeterministicUuid('evidence_${validId}_${photo.hashCode}');
            await supabase.from('evidence').upsert({
              'id': evidenceId,
              'inspection_id': validId,
              'photo_url': photo,
              'note': 'Visual inspection evidence for ${inspectionWithPhotos.restaurantName}',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (evErr) {
            debugPrint('[RestaurantStoreService] Evidence upsert notice: $evErr');
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> _cacheConfirmedInspection(InspectionModel inspection) async {
    final items = List<InspectionModel>.from(inspectionsNotifier.value);
    final index = items.indexWhere((item) => item.id == inspection.id ||
        (inspection.complaintId.isNotEmpty && item.complaintId == inspection.complaintId));
    if (index < 0) { items.insert(0, inspection); } else { items[index] = inspection; }
    for (final key in [inspection.id, if (inspection.complaintId.isNotEmpty) inspection.complaintId]) {
      _reviewedOutletFinePaids[key] = inspection.isFinePaid;
      _adminApprovedInspectionMap[key] = inspection.isAdminApproved;
    }
    inspectionsNotifier.value = items;
    if (inspection.complaintId.isNotEmpty && inspection.outcome != InspectionOutcome.pending) {
      ComplaintStoreService.complaintsNotifier.value = ComplaintStoreService.complaintsNotifier.value
          .map((complaint) => complaint.id == inspection.complaintId
              ? complaint.copyWith(status: inspection.enforcementStatus == EnforcementStatus.completed
                  ? ComplaintStatus.resolved : ComplaintStatus.investigating)
              : complaint).toList();
    }
    // A local cache failure cannot undo an already confirmed database save.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_custom_inspections', jsonEncode(items.map((item) => item.toMap()).toList()));
      for (final key in [inspection.id, if (inspection.complaintId.isNotEmpty) inspection.complaintId]) {
        await prefs.setBool('restaurant_override_fine_paid_$key', inspection.isFinePaid);
        await prefs.setBool('case_closed_$key', inspection.enforcementStatus == EnforcementStatus.completed);
      }
      if (inspection.complaintId.isNotEmpty) await WorkflowService.invalidateCache(inspection.complaintId);
    } catch (e) { debugPrint('Inspection saved; local cache update failed: $e'); }
  }

  static Future<void> issueInspectionEnforcement({
    required InspectionModel inspection,
    required EnforcementType action,
    required double fineAmount,
    required String citation,
    required String remarks,
  }) async {
    final row = await SupabaseService.client.rpc('finalize_inspection_case', params: {
      'p_inspection_id': UuidHelper.toDeterministicUuid(inspection.id),
      'p_operation': 'issue', 'p_action': action.name,
      'p_fine': fineAmount, 'p_citation': citation.trim(), 'p_remarks': remarks.trim(),
    });
    await _cacheConfirmedInspection(InspectionModel.fromMap(Map<String, dynamic>.from(row as Map)));
  }

  static Future<void> rejectInspectionForRescheduling(
    InspectionModel inspection, {
    required String reviewNotes,
  }) async {
    final resetInspection = InspectionModel(
      id: inspection.id,
      complaintId: inspection.complaintId,
      restaurantId: inspection.restaurantId,
      restaurantName: inspection.restaurantName,
      scheduledDate: '',
      conductedDate: null,
      officerName: inspection.officerName,
      outcome: InspectionOutcome.pending,
      findings: '',
      recommendedAction: EnforcementType.none,
      issuedAction: EnforcementType.none,
      justification: '',
      fineAmount: 0,
      enforcementStatus: EnforcementStatus.pending,
      statutoryCitation: null,
      issuedDate: null,
      dueDate: null,
      isFinePaid: false,
      photoUrls: const [],
      isAdminApproved: false,
      adminReviewNotes:
          '${InspectionModel.rescheduleRequiredPrefix} $reviewNotes',
    );

    final current = List<InspectionModel>.from(inspectionsNotifier.value);
    final index = current.indexWhere((item) =>
        item.id == inspection.id ||
        (item.complaintId.isNotEmpty &&
            item.complaintId == inspection.complaintId));
    if (index >= 0) {
      current[index] = resetInspection;
    } else {
      current.insert(0, resetInspection);
    }
    inspectionsNotifier.value = current;

    final keys = <String>{
      inspection.id,
      inspection.id.toLowerCase().trim(),
      if (inspection.complaintId.isNotEmpty) inspection.complaintId,
      if (inspection.complaintId.isNotEmpty)
        inspection.complaintId.toLowerCase().trim(),
    };
    for (final key in keys) {
      _adminApprovedInspectionMap.remove(key);
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in keys) {
      await prefs.remove('inspection_admin_approved_$key');
    }
    await prefs.setString(
      'local_custom_inspections',
      jsonEncode(current.map((item) => item.toMap()).toList()),
    );

    final validId = UuidHelper.toDeterministicUuid(inspection.id);
    try {
      final supabase = SupabaseService.client;
      await supabase.from('evidence').delete().eq('inspection_id', validId);
      await supabase.from('inspections').update({
        // Keep the previous date for schemas where scheduled_date is required;
        // admin_review_notes is the authoritative reschedule lock.
        'scheduled_date': (DateTime.tryParse(inspection.scheduledDate) ??
                DateTime.now())
            .toUtc()
            .toIso8601String(),
        'conducted_date': null,
        'outcome': 'pending',
        'findings': '',
        'recommended_action': 'none',
        'issued_action': 'none',
        'enforcement_status': 'pending',
        'fine_amount': 0,
        'is_admin_approved': false,
        'admin_review_notes': resetInspection.adminReviewNotes,
        'photo_urls': <String>[],
      }).eq('id', validId);
    } catch (e) {
      debugPrint('[RestaurantStoreService] Inspection rejection sync notice: $e');
    }
  }

  static Future<List<InspectionModel>> fetchAllInspections({bool forceRefresh = false}) => fetchInspections();
  static Future<List<ComplaintModel>> fetchAllComplaints({bool forceRefresh = false}) => ComplaintStoreService.fetchAllComplaints(forceRefresh: forceRefresh);

  static Future<List<InspectionModel>> fetchInspections() async {
    final prefs = await SharedPreferences.getInstance();
    List<InspectionModel> localCustomList = [];

    // 1. Read from local SharedPreferences first for instant startup
    try {
      final localJson = prefs.getString('local_custom_inspections');
      if (localJson != null && localJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(localJson);
        localCustomList = decoded.map((row) => InspectionModel.fromMap(Map<String, dynamic>.from(row as Map))).toList();
        if (localCustomList.isNotEmpty) {
          inspectionsNotifier.value = localCustomList;
          for (final item in localCustomList) {
            if (item.isAdminApproved) {
              _adminApprovedInspectionMap[item.id] = true;
              _adminApprovedInspectionMap[item.id.toLowerCase().trim()] = true;
              if (item.complaintId.isNotEmpty) {
                _adminApprovedInspectionMap[item.complaintId] = true;
                _adminApprovedInspectionMap[item.complaintId.toLowerCase().trim()] = true;
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Fetch from Supabase `inspections` table
    try {
      final supabase = SupabaseService.client;
      dynamic res;
      try {
        res = await supabase.from('inspections').select().order('created_at', ascending: false);
      } catch (_) {
        try {
          res = await supabase.from('inspections').select().order('scheduled_date', ascending: false);
        } catch (_) {
          try {
            res = await supabase.from('inspections').select();
          } catch (_) {}
        }
      }

      final List<InspectionModel> merged = [];
      final Set<String> seenIds = {};
      final Set<String> seenComplaintIds = {};

      if (res != null && res is List && res.isNotEmpty) {
        for (final row in res) {
          final map = Map<String, dynamic>.from(row as Map);
          final restId = map['restaurant_id']?.toString() ?? '';
          String restName = map['restaurant_name']?.toString() ?? '';
          if (restName.isEmpty || isRawUuid(restName) || restName == 'Premises') {
            restName = resolveRestaurantName(restId, fallback: 'Premises');
            map['restaurant_name'] = restName;
          }
          final inspId = map['id']?.toString() ?? '';
          final complaintId = map['complaint_id']?.toString() ?? '';

          final confirmed = InspectionModel.fromMap(map);
          for (final key in [inspId, if (complaintId.isNotEmpty) complaintId]) {
            _reviewedOutletFinePaids[key] = confirmed.isFinePaid;
            await prefs.setBool('restaurant_override_fine_paid_$key', confirmed.isFinePaid);
            await prefs.setBool('case_closed_$key', confirmed.enforcementStatus == EnforcementStatus.completed);
          }

          for (final key in [inspId, if (complaintId.isNotEmpty) complaintId]) {
            _adminApprovedInspectionMap[key] = map['is_admin_approved'] == true;
            await prefs.setBool('inspection_admin_approved_$key', map['is_admin_approved'] == true);
          }

          final inspModel = InspectionModel.fromMap(map);
          seenIds.add(inspModel.id);
          if (inspModel.complaintId.isNotEmpty) {
            seenComplaintIds.add(inspModel.complaintId);
            seenComplaintIds.add(inspModel.complaintId.toLowerCase().trim());
          }
          merged.add(inspModel);
        }
      }

      // Only use offline records when the server could not be reached.
      // A successful response, including an empty list, is authoritative.
      if (res == null) merged.addAll(localCustomList);

      inspectionsNotifier.value = merged;
      await prefs.setString('local_custom_inspections', jsonEncode(merged.map((i) => i.toMap()).toList()));
      return merged;
    } catch (e) {
      debugPrint('[RestaurantStoreService] Error fetching inspections: $e');
    }
    return inspectionsNotifier.value;
  }

  static final ValueNotifier<List<RestaurantModel>> restaurantsNotifier = ValueNotifier<List<RestaurantModel>>([]);
  static final Map<String, String> restaurantNameCache = {};
  static void cacheRestaurantName(String id, String name) {
    if (name.isNotEmpty && !isRawUuid(name)) {
      restaurantNameCache[id] = name;
      restaurantNameCache[name] = name;
    }
  }

  /// Check if a string is a raw UUID
  static bool isRawUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').hasMatch(str) ||
           RegExp(r'^[0-9a-fA-F-]{20,}$').hasMatch(str);
  }

  /// Resolve a human-readable display name for any restaurant ID or name
  static String resolveRestaurantName(String? idOrName, {String fallback = 'Restaurant'}) {
    if (idOrName == null || idOrName.trim().isEmpty) return fallback;
    final trimmed = idOrName.trim();

    // 1. Check in-memory cache
    if (restaurantNameCache.containsKey(trimmed) && !isRawUuid(restaurantNameCache[trimmed])) {
      return restaurantNameCache[trimmed]!;
    }

    // 2. If it is already a clean human-readable name, return it directly
    if (!isRawUuid(trimmed)) {
      restaurantNameCache[trimmed] = trimmed;
      return trimmed;
    }

    // 3. Search MockSeedData
    final mock = restaurantsNotifier.value.where((r) => r.id == trimmed || r.name == trimmed).firstOrNull;
    if (mock != null && mock.name.isNotEmpty && !isRawUuid(mock.name)) {
      restaurantNameCache[trimmed] = mock.name;
      return mock.name;
    }

    return fallback;
  }

  /// In-memory override store for reviewed outlet statuses: restaurantId -> status string
  static final Map<String, String> _reviewedOutletStatuses = {};
  static final Map<String, String> _reviewedOutletRegNos = {};
  static final Map<String, String> _reviewedOutletEnforcements = {};
  static final Map<String, double> _reviewedOutletFines = {};
  static final Map<String, bool> _reviewedOutletFinePaids = {};
  static final Map<String, String> _reviewedOutletFineDueDates = {};
  static final Map<String, String> _reviewedOutletFineIssuedDates = {};
  static final Map<String, bool> _reviewedOutletSuspensions = {};
  static final Map<String, String> _reviewedOutletCitations = {};
  static final Map<String, List<Map<String, String>>> _reviewMemoryCache = {};
  static final Map<String, bool> _rectificationSubmittedMap = {};
  static final Map<String, bool> _adminApprovedInspectionMap = {};
  static final Map<String, RectificationModel> _rectificationRecords = {};
  static final Map<String, bool> _adminVerifiedRectificationMap = {};
  static final Map<String, bool> _closedCaseMap = {};
  static final ValueNotifier<int> rectificationNotifier = ValueNotifier<int>(0);

  /// Checks if an inspection audit has been reviewed and endorsed by Admin
  static bool isAdminInspectionApproved(
    String? inspectionId, {
    String? complaintId,
    String? restaurantId,
  }) {
    final List<String> keys = [];
    if (inspectionId != null && inspectionId.isNotEmpty) {
      keys.add(inspectionId);
      keys.add(inspectionId.toLowerCase().trim());
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add(complaintId.toLowerCase().trim());
    }
    if (keys.isEmpty && restaurantId != null && restaurantId.isNotEmpty) {
      keys.add(restaurantId);
      keys.add(restaurantId.toLowerCase().trim());
      keys.add(UuidHelper.toDeterministicUuid(restaurantId));
    }

    for (final k in keys) {
      if (_adminApprovedInspectionMap[k] == true) {
        return true;
      }
    }
    return false;
  }

  /// Hydrates admin approval status into in-memory maps from remote/cache records
  static void hydrateAdminApproval(String inspectionId, {String? complaintId, String? restaurantId}) {
    final List<String> keys = [];
    if (inspectionId.isNotEmpty) {
      keys.add(inspectionId);
      keys.add(inspectionId.toLowerCase().trim());
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add(complaintId.toLowerCase().trim());
    }
    if (keys.isEmpty && restaurantId != null && restaurantId.isNotEmpty) {
      keys.add(restaurantId);
      keys.add(restaurantId.toLowerCase().trim());
      keys.add(UuidHelper.toDeterministicUuid(restaurantId));
    }
    for (final k in keys) {
      _adminApprovedInspectionMap[k] = true;
    }
  }

  /// Hydrates closed case status into in-memory maps from remote/cache records
  static void hydrateCaseClosed({String? inspectionId, String? complaintId, String? restaurantId, String? noticeId}) {
    final List<String> keys = [];
    if (inspectionId != null && inspectionId.isNotEmpty) {
      keys.add(inspectionId);
      keys.add(inspectionId.toLowerCase().trim());
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add(complaintId.toLowerCase().trim());
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      keys.add(noticeId);
      keys.add(noticeId.toLowerCase().trim());
    }
    for (final k in keys) {
      _closedCaseMap[k] = true;
    }
  }

  /// Checks if Admin has verified the owner's rectification proof and forwarded it to Officer
  static bool isRectificationAdminVerified({
    String? inspectionId,
    String? complaintId,
    String? restaurantId,
    String? noticeId,
  }) {
    final record = getRectificationRecord(
      inspectionId: inspectionId,
      complaintId: complaintId,
      restaurantId: restaurantId,
      noticeId: noticeId,
    );
    if (record?.isAdminVerified == true) return true;

    final List<String> keys = [];
    if (inspectionId != null && inspectionId.isNotEmpty) {
      keys.add(inspectionId);
      keys.add(inspectionId.toLowerCase().trim());
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add(complaintId.toLowerCase().trim());
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      keys.add(noticeId);
      keys.add(noticeId.toLowerCase().trim());
    }

    for (final k in keys) {
      if (_adminVerifiedRectificationMap[k] == true) return true;
    }
    return false;
  }

  /// Marks an inspection audit as endorsed by Admin for officer penalty decree issuance
  static Future<void> markInspectionAdminApproved(
    String inspectionId, {
    String? complaintId,
    String? restaurantId,
  }) async {
    final List<String> keys = [];
    if (inspectionId.isNotEmpty) {
      keys.add(inspectionId);
      keys.add(inspectionId.toLowerCase().trim());
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add(complaintId.toLowerCase().trim());
    }
    if (keys.isEmpty && restaurantId != null && restaurantId.isNotEmpty) {
      keys.add(restaurantId);
      keys.add(restaurantId.toLowerCase().trim());
      keys.add(UuidHelper.toDeterministicUuid(restaurantId));
    }

    for (final k in keys) {
      _adminApprovedInspectionMap[k] = true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in keys) {
        await prefs.setBool('inspection_admin_approved_$k', true);
      }
    } catch (_) {}

    // Cloud update to Supabase
    try {
      final supabase = SupabaseService.client;
      final validId = UuidHelper.toDeterministicUuid(inspectionId);
      await supabase.from('inspections').update({
        'is_admin_approved': true,
      }).eq('id', validId);
    } catch (_) {}
  }

  /// Generates normalized variants of an ID (e.g., CMP-XXXX, cmp-xxxx, xxxx)
  static List<String> _generateIdVariants(String? id) {
    if (id == null || id.trim().isEmpty) return [];
    final raw = id.trim();
    final low = raw.toLowerCase();
    final clean = low.replaceAll('cmp-', '').replaceAll('cmp_', '').replaceAll('insp-', '').replaceAll('insp_', '');
    final variants = <String>{
      raw,
      low,
      raw.toUpperCase(),
      clean,
      'cmp-$clean',
      'cmp_$clean',
      'CMP-${clean.toUpperCase()}',
      'CMP_${clean.toUpperCase()}',
    };
    return variants.toList();
  }

  /// Restores all rectification records from SharedPreferences local memory cache
  static Future<void> syncRectificationsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Restore from master list
      final localAllJson = prefs.getString('local_all_rectification_records');
      if (localAllJson != null && localAllJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(localAllJson);
        for (final item in list) {
          try {
            final rec = RectificationModel.fromMap(Map<String, dynamic>.from(item as Map));
            _hydrateRectificationRecord(rec);
          } catch (_) {}
        }
      }

      // 2. Scan specific keys
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('restaurant_rectification_record_')) {
          final idSuffix = key.replaceFirst('restaurant_rectification_record_', '');
          final val = prefs.getString(key);
          if (val != null && val.isNotEmpty) {
            try {
              final rec = RectificationModel.fromMap(jsonDecode(val));
              _hydrateRectificationRecord(rec);
              _rectificationRecords[idSuffix] = rec;
              _rectificationSubmittedMap[idSuffix] = true;
            } catch (_) {}
          }
        }
      }
      rectificationNotifier.value++;
    } catch (_) {}
  }

  /// Hydrates a single rectification record into all appropriate variant keys
  static void _hydrateRectificationRecord(RectificationModel rec) {
    final List<String> searchKeys = [];
    if (rec.inspectionId != null && rec.inspectionId!.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(rec.inspectionId));
    }
    if (rec.complaintId != null && rec.complaintId!.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(rec.complaintId));
    }
    if (rec.noticeId != null && rec.noticeId!.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(rec.noticeId));
    }
    if (searchKeys.isEmpty && rec.restaurantId.isNotEmpty) {
      searchKeys.add(rec.restaurantId);
      searchKeys.add(rec.restaurantId.toLowerCase().trim());
      searchKeys.add(UuidHelper.toDeterministicUuid(rec.restaurantId));
    }

    for (final k in searchKeys) {
      _rectificationRecords[k] = rec;
      _rectificationSubmittedMap[k] = true;
      if (rec.isAdminVerified) {
        _adminVerifiedRectificationMap[k] = true;
      }
      if (rec.isOfficerClosed) {
        _closedCaseMap[k] = true;
      }
    }
  }

  /// Synchronizes rectification records from Supabase `rectifications` table into local memory and SharedPreferences
  static Future<void> syncRectificationsFromSupabase() async {
    // 1. Fast local restore first
    await syncRectificationsFromStorage();

    // 2. Query remote Supabase table
    try {
      final supabase = SupabaseService.client;
      final res = await supabase.from('rectifications').select().order('submitted_at', ascending: false);
      if (res.isNotEmpty) {
        final List<RectificationModel> remoteList = [];
        for (final row in (res as List<dynamic>)) {
          try {
            final map = Map<String, dynamic>.from(row as Map);
            final rec = RectificationModel(
              restaurantId: map['restaurant_id']?.toString() ?? '',
              restaurantName: map['restaurant_name']?.toString() ?? '',
              complaintId: map['complaint_id']?.toString(),
              inspectionId: map['inspection_id']?.toString(),
              noticeId: map['notice_id']?.toString(),
              notes: map['notes']?.toString() ?? '',
              photoUrls: List<String>.from(map['photo_urls'] ?? []),
              submittedAt: DateTime.tryParse(map['submitted_at']?.toString() ?? '') ?? DateTime.now(),
              isAdminVerified: map['is_admin_verified'] == true,
              adminVerifiedAt: map['admin_verified_at'] != null ? DateTime.tryParse(map['admin_verified_at'].toString()) : null,
              adminNotes: map['admin_notes']?.toString(),
              isOfficerClosed: map['is_officer_closed'] == true,
              officerClosedAt: map['officer_closed_at'] != null ? DateTime.tryParse(map['officer_closed_at'].toString()) : null,
              officerRemarks: map['officer_remarks']?.toString(),
            );
            _hydrateRectificationRecord(rec);
            remoteList.add(rec);
          } catch (_) {}
        }

        // Cache master list locally
        if (remoteList.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('local_all_rectification_records', jsonEncode(remoteList.map((r) => r.toMap()).toList()));
        }
      }
    } catch (e) {
      debugPrint('Rectifications Supabase fetch notice: $e');
    }

    rectificationNotifier.value++;
  }

  /// Checks if an outlet or notice has submitted rectification evidence
  static bool isRectificationSubmitted(
    String? restaurantId, {
    String? restaurantName,
    String? complaintId,
    String? inspectionId,
    String? noticeId,
  }) {
    final List<String> searchKeys = [];
    if (inspectionId != null && inspectionId.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(inspectionId));
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(complaintId));
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(noticeId));
    }

    for (final k in searchKeys) {
      if (_rectificationSubmittedMap[k] == true) return true;
    }

    final bool hasSpecificId = searchKeys.isNotEmpty;
    if (!hasSpecificId && restaurantId != null && restaurantId.isNotEmpty) {
      if (_rectificationSubmittedMap.containsKey(restaurantId)) {
        return _rectificationSubmittedMap[restaurantId] == true;
      }
      if (_rectificationSubmittedMap.containsKey(restaurantId.toLowerCase().trim())) {
        return _rectificationSubmittedMap[restaurantId.toLowerCase().trim()] == true;
      }
    }
    return false;
  }

  /// Checks if an outlet or notice has verified rectification evidence
  static bool isRectificationVerified({
    String? complaintId,
    String? inspectionId,
    String? restaurantId,
    String? noticeId,
  }) {
    final rec = getRectificationRecord(
      inspectionId: inspectionId,
      complaintId: complaintId,
      restaurantId: restaurantId,
      noticeId: noticeId,
    );
    if (rec != null && (rec.isAdminVerified || rec.isOfficerClosed)) {
      return true;
    }
    return isRectificationSubmitted(
      restaurantId,
      complaintId: complaintId,
      inspectionId: inspectionId,
      noticeId: noticeId,
    );
  }

  /// Retrieves owner submitted rectification record
  static RectificationModel? getRectificationRecord({
    String? inspectionId,
    String? complaintId,
    String? restaurantId,
    String? noticeId,
  }) {
    final List<String> searchKeys = [];
    if (inspectionId != null && inspectionId.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(inspectionId));
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(complaintId));
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      searchKeys.addAll(_generateIdVariants(noticeId));
    }

    for (final k in searchKeys) {
      if (_rectificationRecords.containsKey(k)) return _rectificationRecords[k];
    }

    final bool hasSpecificId = searchKeys.isNotEmpty;
    if (!hasSpecificId && restaurantId != null && restaurantId.isNotEmpty) {
      if (_rectificationRecords.containsKey(restaurantId)) return _rectificationRecords[restaurantId];
      if (_rectificationRecords.containsKey(restaurantId.toLowerCase().trim())) return _rectificationRecords[restaurantId.toLowerCase().trim()];
    }
    return null;
  }

  /// Records that rectification proof has been submitted for this outlet or notice
  static Future<void> markRectificationSubmitted({
    String? restaurantId,
    String? restaurantName,
    String? complaintId,
    String? inspectionId,
    String? noticeId,
    String notes = '',
    List<String> photoUrls = const [],
  }) async {
    if (notes.trim().isEmpty || photoUrls.isEmpty ||
        photoUrls.any((url) => !url.startsWith('https://'))) {
      throw ArgumentError('Rectification notes and uploaded evidence photos are required.');
    }
    final List<String> keys = [];
    if (inspectionId != null && inspectionId.isNotEmpty) {
      keys.addAll(_generateIdVariants(inspectionId));
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.addAll(_generateIdVariants(complaintId));
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      keys.addAll(_generateIdVariants(noticeId));
    }
    // Only key by generic restaurantId if no specific inspection/complaint/notice ID is specified
    if (keys.isEmpty && restaurantId != null && restaurantId.isNotEmpty) {
      keys.add(restaurantId);
      keys.add(restaurantId.toLowerCase().trim());
    }

    final record = RectificationModel(
      restaurantId: restaurantId ?? '',
      restaurantName: restaurantName ?? (restaurantId != null ? resolveRestaurantName(restaurantId) : 'Premises'),
      complaintId: complaintId,
      inspectionId: inspectionId,
      noticeId: noticeId,
      notes: notes,
      photoUrls: photoUrls,
      submittedAt: DateTime.now(),
      isAdminVerified: false,
      isOfficerClosed: false,
    );

    // Persist remotely first. Never mark a local submission successful when
    // Supabase failed, otherwise local file paths disappear after reinstall.
    final supabase = SupabaseService.client;
    final String safeId = UuidHelper.toDeterministicUuid(
      'rect_${record.complaintId ?? record.inspectionId ?? record.noticeId ?? record.restaurantId}',
    );
    final dbPayload = {
      'id': safeId,
      'restaurant_id': record.restaurantId.isNotEmpty
          ? (UuidHelper.isValidUuid(record.restaurantId)
              ? record.restaurantId
              : UuidHelper.toDeterministicUuid(record.restaurantId))
          : null,
      'restaurant_name': record.restaurantName,
      'complaint_id': record.complaintId != null
          ? (UuidHelper.isValidUuid(record.complaintId!)
              ? record.complaintId
              : UuidHelper.toDeterministicUuid(record.complaintId!))
          : null,
      'inspection_id': record.inspectionId != null
          ? (UuidHelper.isValidUuid(record.inspectionId!)
              ? record.inspectionId
              : UuidHelper.toDeterministicUuid(record.inspectionId!))
          : null,
      'notice_id': record.noticeId,
      'notes': record.notes,
      'photo_urls': record.photoUrls,
      'submitted_at': record.submittedAt.toUtc().toIso8601String(),
      'is_admin_verified': record.isAdminVerified,
      'admin_verified_at': record.adminVerifiedAt?.toUtc().toIso8601String(),
      'admin_notes': record.adminNotes,
      'is_officer_closed': record.isOfficerClosed,
      'officer_closed_at': record.officerClosedAt?.toUtc().toIso8601String(),
      'officer_remarks': record.officerRemarks,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await supabase.from('rectifications').upsert(dbPayload);

    for (final k in keys) {
      _rectificationSubmittedMap[k] = true;
      _rectificationRecords[k] = record;
    }

    // 1. Persist locally to master and individual keys in SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordJson = jsonEncode(record.toMap());
      for (final k in keys) {
        await prefs.setBool('restaurant_rectification_submitted_$k', true);
        await prefs.setString('restaurant_rectification_record_$k', recordJson);
      }

      // Add to master list
      final localAllJson = prefs.getString('local_all_rectification_records');
      List<dynamic> list = [];
      if (localAllJson != null && localAllJson.isNotEmpty) {
        try {
          list = jsonDecode(localAllJson);
        } catch (_) {}
      }
      list.removeWhere((item) {
        final m = Map<String, dynamic>.from(item as Map);
        return (record.complaintId != null && m['complaintId'] == record.complaintId) ||
               (record.inspectionId != null && m['inspectionId'] == record.inspectionId) ||
               (record.noticeId != null && m['noticeId'] == record.noticeId);
      });
      list.insert(0, record.toMap());
      await prefs.setString('local_all_rectification_records', jsonEncode(list));
    } catch (_) {}

    rectificationNotifier.value++;
  }

  /// Marks that Admin has verified the owner's rectification proof and forwarded it to Officer for case closure
  static Future<void> markRectificationAdminVerified(
    String inspectionId, {
    String? complaintId,
    String? restaurantId,
    String? noticeId,
    String? adminNotes,
  }) async {
    final List<String> keys = [inspectionId, inspectionId.toLowerCase().trim()];
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add(complaintId.toLowerCase().trim());
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      keys.add(noticeId);
      keys.add(noticeId.toLowerCase().trim());
    }
    if (keys.isEmpty && restaurantId != null && restaurantId.isNotEmpty) {
      keys.add(restaurantId);
      keys.add(restaurantId.toLowerCase().trim());
    }

    final existing = getRectificationRecord(
      inspectionId: inspectionId,
      complaintId: complaintId,
      restaurantId: restaurantId,
      noticeId: noticeId,
    );

    final updated = (existing ?? RectificationModel(
      restaurantId: restaurantId ?? '',
      restaurantName: restaurantId != null ? resolveRestaurantName(restaurantId) : 'Premises',
      complaintId: complaintId,
      inspectionId: inspectionId,
      noticeId: noticeId,
      notes: 'Rectification evidence verified by Government Admin.',
      photoUrls: const [],
      submittedAt: DateTime.now(),
    )).copyWith(
      isAdminVerified: true,
      adminVerifiedAt: DateTime.now(),
      adminNotes: adminNotes,
    );

    for (final k in keys) {
      _adminVerifiedRectificationMap[k] = true;
      _rectificationRecords[k] = updated;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final recordJson = jsonEncode(updated.toMap());
      for (final k in keys) {
        await prefs.setBool('restaurant_rectification_admin_verified_$k', true);
        await prefs.setString('restaurant_rectification_record_$k', recordJson);
      }

      final localAllJson = prefs.getString('local_all_rectification_records');
      List<dynamic> list = [];
      if (localAllJson != null && localAllJson.isNotEmpty) {
        try {
          list = jsonDecode(localAllJson);
        } catch (_) {}
      }
      list.removeWhere((item) {
        final m = Map<String, dynamic>.from(item as Map);
        return (updated.complaintId != null && m['complaintId'] == updated.complaintId) ||
               (updated.inspectionId != null && m['inspectionId'] == updated.inspectionId) ||
               (updated.noticeId != null && m['noticeId'] == updated.noticeId);
      });
      list.insert(0, updated.toMap());
      await prefs.setString('local_all_rectification_records', jsonEncode(list));
    } catch (_) {}

    // Cloud update to Supabase rectifications table
    try {
      final supabase = SupabaseService.client;
      final String safeId = UuidHelper.toDeterministicUuid('rect_${updated.complaintId ?? updated.inspectionId ?? updated.noticeId ?? updated.restaurantId}');
      await supabase.from('rectifications').update({
        'is_admin_verified': true,
        'admin_verified_at': DateTime.now().toUtc().toIso8601String(),
        'admin_notes': adminNotes,
      }).eq('id', safeId);
    } catch (_) {}

    // Send notifications to Health Officer (gov_001) & Premise Owner (own_001)
    final restName = updated.restaurantName.isNotEmpty ? updated.restaurantName : 'Premises';
    NotificationService.sendNotification(
      userId: 'gov_officer_001',
      title: '📋 Improvement Proof Verified: $restName',
      message: 'Admin endorsed rectification proof for $restName. Case ready for officer final review & closure.',
      type: NotificationType.hygieneAlert,
      actionUrl: 'close_case_list',
    );

    rectificationNotifier.value++;
  }

  /// Checks if a case has been officially closed & archived by Health Officer
  static bool isCaseClosed({
    String? inspectionId,
    String? complaintId,
    String? noticeId,
  }) {
    if (inspectionId != null && inspectionId.isNotEmpty) {
      if (_closedCaseMap.containsKey(inspectionId)) return _closedCaseMap[inspectionId] == true;
      if (_closedCaseMap.containsKey(inspectionId.toLowerCase().trim())) return _closedCaseMap[inspectionId.toLowerCase().trim()] == true;
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      if (_closedCaseMap.containsKey(complaintId)) return _closedCaseMap[complaintId] == true;
      if (_closedCaseMap.containsKey(complaintId.toLowerCase().trim())) return _closedCaseMap[complaintId.toLowerCase().trim()] == true;
    }
    if (noticeId != null && noticeId.isNotEmpty) {
      if (_closedCaseMap.containsKey(noticeId)) return _closedCaseMap[noticeId] == true;
      if (_closedCaseMap.containsKey(noticeId.toLowerCase().trim())) return _closedCaseMap[noticeId.toLowerCase().trim()] == true;
    }
    return false;
  }

  /// Officially closes and archives a case by the Health Officer
  static Future<void> closeCase({
    required String inspectionId,
    String? complaintId,
    String? restaurantId,
    String? noticeId,
    required String officerRemarks,
    bool certifyClean = true,
  }) async {
    final row = await SupabaseService.client.rpc('finalize_inspection_case', params: {
      'p_inspection_id': UuidHelper.toDeterministicUuid(inspectionId),
      'p_operation': 'close',
      'p_remarks': officerRemarks.trim(),
    });
    await _cacheConfirmedInspection(InspectionModel.fromMap(Map<String, dynamic>.from(row as Map)));
  }

  static bool _isValidUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(str);
  }

  /// Checks if an outlet has settled its fine across any matching identifier (ID, UUID, Name, or Notice ID)
  static bool isOutletFinePaid(
    String? restaurantId, {
    String? restaurantName,
    String? complaintId,
    String? inspectionId,
  }) {
    final scoped = inspectionsNotifier.value.where((inspection) {
      if (inspectionId?.isNotEmpty == true) return inspection.id == inspectionId;
      if (complaintId?.isNotEmpty == true) return inspection.complaintId == complaintId;
      return inspection.restaurantId == restaurantId;
    }).toList();
    return scoped.isNotEmpty && scoped.every((inspection) =>
        inspection.fineAmount <= 0 || inspection.isFinePaid);
  }

  static Future<void> _saveOverrideToPrefs(String id, String status, String? regNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('restaurant_override_status_$id', status);
      if (regNo != null && regNo.isNotEmpty) {
        await prefs.setString('restaurant_override_regno_$id', regNo);
      }
    } catch (_) {}
  }

  static Future<void> _applyOverridesToMap(Map<String, dynamic> mapData) async {
    final String id = mapData['id']?.toString() ?? '';
    final String name = (mapData['name']?.toString() ?? '').toLowerCase().trim();
    if (id.isEmpty) return;

    if (_reviewedOutletStatuses.containsKey(id)) {
      mapData['status'] = _reviewedOutletStatuses[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedStatus = prefs.getString('restaurant_override_status_$id');
        if (savedStatus != null && savedStatus.isNotEmpty) {
          _reviewedOutletStatuses[id] = savedStatus;
          mapData['status'] = savedStatus;
        }
      } catch (_) {}
    }

    if (_reviewedOutletRegNos.containsKey(id)) {
      mapData['business_reg_no'] = _reviewedOutletRegNos[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedRegNo = prefs.getString('restaurant_override_regno_$id');
        if (savedRegNo != null && savedRegNo.isNotEmpty) {
          _reviewedOutletRegNos[id] = savedRegNo;
          mapData['business_reg_no'] = savedRegNo;
        }
      } catch (_) {}
    }

    // Enforcement action override
    if (_reviewedOutletEnforcements.containsKey(id)) {
      mapData['enforcement_action'] = _reviewedOutletEnforcements[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('restaurant_override_enforcement_$id');
        if (saved != null && saved.isNotEmpty) {
          _reviewedOutletEnforcements[id] = saved;
          mapData['enforcement_action'] = saved;
        }
      } catch (_) {}
    }

    // Fine amount override
    if (_reviewedOutletFines.containsKey(id)) {
      mapData['fine_amount'] = _reviewedOutletFines[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getDouble('restaurant_override_fine_amt_$id');
        if (saved != null) {
          _reviewedOutletFines[id] = saved;
          mapData['fine_amount'] = saved;
        }
      } catch (_) {}
    }

    // Fine paid override (Check Memory and SharedPreferences across ID and Name)
    if (_reviewedOutletFinePaids.containsKey(id)) {
      mapData['is_fine_paid'] = _reviewedOutletFinePaids[id];
    } else if (name.isNotEmpty && _reviewedOutletFinePaids.containsKey(name)) {
      mapData['is_fine_paid'] = _reviewedOutletFinePaids[name];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getBool('restaurant_override_fine_paid_$id') ??
            (name.isNotEmpty ? prefs.getBool('restaurant_override_fine_paid_$name') : null);
        if (saved != null) {
          _reviewedOutletFinePaids[id] = saved;
          if (name.isNotEmpty) _reviewedOutletFinePaids[name] = saved;
          mapData['is_fine_paid'] = saved;
        }
      } catch (_) {}
    }

    // Fine due date override
    if (_reviewedOutletFineDueDates.containsKey(id)) {
      mapData['fine_due_date'] = _reviewedOutletFineDueDates[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('restaurant_override_fine_due_$id');
        if (saved != null && saved.isNotEmpty) {
          _reviewedOutletFineDueDates[id] = saved;
          mapData['fine_due_date'] = saved;
        }
      } catch (_) {}
    }

    // Fine issued date override
    if (_reviewedOutletFineIssuedDates.containsKey(id)) {
      mapData['fine_issued_date'] = _reviewedOutletFineIssuedDates[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('restaurant_override_fine_issued_$id');
        if (saved != null && saved.isNotEmpty) {
          _reviewedOutletFineIssuedDates[id] = saved;
          mapData['fine_issued_date'] = saved;
        }
      } catch (_) {}
    }

    // Suspension override
    if (_reviewedOutletSuspensions.containsKey(id)) {
      mapData['is_suspended'] = _reviewedOutletSuspensions[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getBool('restaurant_override_suspended_$id');
        if (saved != null) {
          _reviewedOutletSuspensions[id] = saved;
          mapData['is_suspended'] = saved;
        }
      } catch (_) {}
    }

    // Statutory citation override
    if (_reviewedOutletCitations.containsKey(id)) {
      mapData['statutory_citation'] = _reviewedOutletCitations[id];
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('restaurant_override_citation_$id');
        if (saved != null && saved.isNotEmpty) {
          _reviewedOutletCitations[id] = saved;
          mapData['statutory_citation'] = saved;
        }
      } catch (_) {}
    }

    // Dynamic Risk Priority Evaluation:
    // Priority 1: Officer Compliance (Closure -> 88.0, Compound Fine -> 52.0-72.0, Warning -> 45.0)
    // Priority 2: Customer Comments & Ratings Fallback
    final double fineAmt = (mapData['fine_amount'] as num?)?.toDouble() ?? 0.0;
    final bool isFinePaid = mapData['is_fine_paid'] == true || (mapData['is_fine_paid'] == null && fineAmt == 0.0);
    final bool isSuspended = mapData['is_suspended'] == true;
    final String enf = (mapData['enforcement_action']?.toString() ?? '').toLowerCase();

    if (isSuspended || (enf == 'closure' && !isFinePaid)) {
      mapData['hygiene_risk_score'] = 88.0;
      mapData['risk_category'] = 'high';
    } else if (fineAmt > 0 && !isFinePaid) {
      final isHighFine = fineAmt >= 1000.0;
      mapData['hygiene_risk_score'] = isHighFine ? 72.0 : 52.0;
      mapData['risk_category'] = isHighFine ? 'high' : 'moderate';
    } else if (enf == 'warning' || enf == 'formalwarning' || enf == 'remedialnotice') {
      mapData['hygiene_risk_score'] = 45.0;
      mapData['risk_category'] = 'moderate';
    } else {
      // Priority 2: Determine from customer reviews & ratings
      final restName = mapData['name']?.toString() ?? '';
      final tempModel = RestaurantModel(
        id: id,
        name: restName,
        address: mapData['address']?.toString() ?? '',
        category: mapData['category']?.toString() ?? '',
        latitude: (mapData['latitude'] as num?)?.toDouble() ?? 3.1475,
        longitude: (mapData['longitude'] as num?)?.toDouble() ?? 101.7085,
        hygieneRiskScore: 10.0,
        riskCategory: RiskCategory.safe,
        status: RestaurantStatus.approved,
        violationCount: 0,
        imageUrl: '',
        lastUpdated: '2026-08-25',
      );
      final eval = calculateDynamicRisk(tempModel);
      mapData['hygiene_risk_score'] = eval.score;
      mapData['risk_category'] = eval.category.name;
    }
  }

  /// Calculates dynamic hygiene risk prioritized by Officer Compliance, with Customer Comments & Ratings as fallback
  static RestaurantRiskEvaluation calculateDynamicRisk(
    RestaurantModel restaurant, {
    List<Map<String, String>>? reviews,
    List<InspectionModel>? inspections,
  }) {
    final restId = restaurant.id;
    final restName = restaurant.name;

    // -------------------------------------------------------------
    // PRIORITY 1: Officer Compliance Record (Top Priority)
    // -------------------------------------------------------------
    final isSuspended = restaurant.isSuspended;
    final enf = (restaurant.enforcementAction ?? '').toLowerCase();
    final double fine = restaurant.fineAmount;
    final bool isFinePaid = restaurant.isFinePaid;
    final String citation = restaurant.statutoryCitation ?? 'Food Act 1983 - Section 11';

    // Scan inspections for this restaurant
    final inspList = inspections ?? inspectionsNotifier.value;
    final matchingInspections = inspList.where((insp) {
      return insp.restaurantId == restId ||
          (insp.restaurantName.isNotEmpty && insp.restaurantName.toLowerCase() == restName.toLowerCase());
    }).toList();

    InspectionModel? activeClosureInsp;
    InspectionModel? activeFineInsp;
    InspectionModel? activeWarningInsp;
    InspectionModel? historicalClosureInsp;
    InspectionModel? historicalNonCompliantInsp;
    InspectionModel? cleanAuditInsp;

    for (final insp in matchingInspections) {
      final bool isClosed = insp.enforcementStatus == EnforcementStatus.completed ||
          isCaseClosed(inspectionId: insp.id, complaintId: insp.complaintId);
      final bool isFineSettled = insp.isFinePaid || isOutletFinePaid(restId, complaintId: insp.complaintId, inspectionId: insp.id);

      if (insp.issuedAction == EnforcementType.closure || insp.recommendedAction == EnforcementType.closure) {
        if (!isClosed && (isSuspended || !isFineSettled)) {
          activeClosureInsp = insp;
          break;
        } else {
          historicalClosureInsp ??= insp;
        }
      } else if ((insp.issuedAction == EnforcementType.fine || insp.fineAmount > 0) && (!isFineSettled && !isClosed)) {
        activeFineInsp ??= insp;
      } else if ((insp.issuedAction == EnforcementType.warning || insp.recommendedAction == EnforcementType.warning) && !isClosed) {
        activeWarningInsp ??= insp;
      } else if (insp.outcome == InspectionOutcome.nonCompliant || insp.issuedAction != EnforcementType.none || insp.fineAmount > 0) {
        historicalNonCompliantInsp ??= insp;
      } else if (insp.outcome == InspectionOutcome.compliant) {
        cleanAuditInsp ??= insp;
      }
    }

    // 1A. Active Closure Order / Premises Suspended
    if (isSuspended || enf == 'closure' || activeClosureInsp != null) {
      return RestaurantRiskEvaluation(
        score: 88.0,
        category: RiskCategory.high,
        source: 'MOH Officer Compliance Decree',
        headline: 'MOH Premise Closure Order (High Risk • Grade D)',
        explanation: 'Official MOH premise closure order active under Food Act 1983 (Section 11) due to severe unsanitary conditions.',
        isFromOfficer: true,
        officerCitation: activeClosureInsp?.statutoryCitation ?? citation,
      );
    }

    // 1B. Active Compound Penalty
    if ((fine > 0 && !isFinePaid) || enf == 'compoundfine' || activeFineInsp != null) {
      final actualFine = activeFineInsp != null ? activeFineInsp.fineAmount : fine;
      final isHighFine = actualFine >= 1000.0 || restaurant.isCompoundedOverdue;
      return RestaurantRiskEvaluation(
        score: isHighFine ? 72.0 : 65.0,
        category: isHighFine ? RiskCategory.high : RiskCategory.moderate,
        source: 'MOH Officer Compliance Decree',
        headline: 'MOH Statutory Compound Active (${isHighFine ? "High Risk • Grade D" : "Moderate Risk • Grade C"})',
        explanation: 'Statutory compound fine of RM ${actualFine.toStringAsFixed(2)} issued by Health Inspector for hygiene infractions.',
        isFromOfficer: true,
        officerCitation: activeFineInsp?.statutoryCitation ?? citation,
      );
    }

    // 1C. Active Warning / Remedial Notice
    if ((enf == 'warning' || enf == 'formalwarning' || enf == 'remedialnotice') || activeWarningInsp != null) {
      return RestaurantRiskEvaluation(
        score: 55.0,
        category: RiskCategory.moderate,
        source: 'MOH Officer Compliance Notice',
        headline: 'MOH Health Warning Notice Active (Moderate Risk • Grade C)',
        explanation: 'Official health warning notice issued by Health Officer requiring mandatory sanitation and cleanliness corrections.',
        isFromOfficer: true,
        officerCitation: activeWarningInsp?.statutoryCitation ?? citation,
      );
    }

    // 1D. Historical / Settled Non-Compliant Inspection (Permanent Officer Grade C / D)
    if (historicalClosureInsp != null) {
      return RestaurantRiskEvaluation(
        score: 78.0,
        category: RiskCategory.high,
        source: 'MOH Official Inspection Audit',
        headline: 'MOH Inspected & Graded (Grade D • Severe Non-Compliance)',
        explanation: 'Premises audited and graded Non-Compliant (Grade D) under ${historicalClosureInsp.statutoryCitation ?? citation}. Closure order resolved.',
        isFromOfficer: true,
        officerCitation: historicalClosureInsp.statutoryCitation ?? citation,
      );
    }

    if (historicalNonCompliantInsp != null) {
      final cite = historicalNonCompliantInsp.statutoryCitation ?? citation;
      return RestaurantRiskEvaluation(
        score: 65.0,
        category: RiskCategory.moderate,
        source: 'MOH Official Inspection Audit',
        headline: 'MOH Inspected & Graded (Grade C • Non-Compliance Record)',
        explanation: 'Premises audited and graded Non-Compliant (Grade C) under $cite. Corrective rectification and penalties settled.',
        isFromOfficer: true,
        officerCitation: cite,
      );
    }

    // 1E. Certified Clean Officer Audit (Compliant Pass -> Grade A)
    if (cleanAuditInsp != null) {
      return const RestaurantRiskEvaluation(
        score: 10.0,
        category: RiskCategory.safe,
        source: 'MOH Officer Inspection Audit',
        headline: 'MOH Inspected & Certified (Grade A)',
        explanation: 'Premises thoroughly inspected and certified compliant with national food hygiene regulations by MOH officer.',
        isFromOfficer: true,
        officerCitation: 'Passed Official MOH Health Audit',
      );
    }

    // -------------------------------------------------------------
    // PRIORITY 2: Customer Comments & Ratings (Fallback)
    // -------------------------------------------------------------
    final effectiveReviews = reviews ??
        _reviewMemoryCache[restId] ??
        _reviewMemoryCache[restId.toLowerCase()] ??
        (restName.isNotEmpty ? _reviewMemoryCache[restName.toLowerCase()] : null) ??
        _getDefaultSeedReviews(restId, restaurantName: restName);

    if (effectiveReviews.isNotEmpty) {
      double sum = 0;
      for (var rev in effectiveReviews) {
        sum += (double.tryParse(rev['stars'] ?? '0') ?? 0);
      }
      final double avgRating = sum / effectiveReviews.length;

      // Base risk score derived from average customer rating
      double baseScore = 10.0;
      if (avgRating >= 4.5) {
        baseScore = 8.0;
      } else if (avgRating >= 4.0) {
        baseScore = 16.0;
      } else if (avgRating >= 3.5) {
        baseScore = 24.0;
      } else if (avgRating >= 3.0) {
        baseScore = 38.0;
      } else if (avgRating >= 2.5) {
        baseScore = 52.0;
      } else if (avgRating >= 2.0) {
        baseScore = 68.0;
      } else {
        baseScore = 82.0;
      }

      // Keyword Sentiment Analysis across all comments
      int severeKeywordCount = 0;
      int moderateKeywordCount = 0;
      int positiveKeywordCount = 0;

      final severeTerms = [
        'cockroach', 'lipas', 'rat', 'tikus', 'pest', 'poison', 'racun',
        'vomit', 'muntah', 'diarrhea', 'cirit', 'maggot', 'ulat', 'stale',
        'basi', 'rotten', 'busuk', 'raw chicken', 'cross-contamination',
        'keracunan', 'food poisoning', 'unhygienic food'
      ];
      final moderateTerms = [
        'dirty', 'kotor', 'smelly', 'bau', 'flies', 'lalat', 'hair in',
        'rambut', 'greasy', 'berminyak', 'sticky', 'melekit', 'unhygienic',
        'dusty', 'berhabuk', 'drain', 'longkang', 'trash', 'sampah', 'tak bersih'
      ];
      final positiveTerms = [
        'clean', 'bersih', 'hygienic', 'sanitary', 'spotless', 'tiptop',
        'kemas', 'tidy', 'fresh', 'segar', 'good hygiene', 'best', 'delicious',
        'sedap', 'cleankitchen'
      ];

      for (var rev in effectiveReviews) {
        final comment = (rev['comment'] ?? '').toLowerCase();
        if (comment.isEmpty) continue;
        for (var t in severeTerms) {
          if (comment.contains(t)) {
            severeKeywordCount++;
            break;
          }
        }
        for (var t in moderateTerms) {
          if (comment.contains(t)) {
            moderateKeywordCount++;
            break;
          }
        }
        for (var t in positiveTerms) {
          if (comment.contains(t)) {
            positiveKeywordCount++;
            break;
          }
        }
      }

      double keywordAdjustment = (severeKeywordCount * 12.0) + (moderateKeywordCount * 6.0) - (positiveKeywordCount * 3.0);
      keywordAdjustment = keywordAdjustment.clamp(-15.0, 35.0);

      final double finalScore = (baseScore + keywordAdjustment).clamp(5.0, 95.0);
      final RiskCategory finalCat = finalScore < 26.0
          ? RiskCategory.safe
          : (finalScore <= 60.0 ? RiskCategory.moderate : RiskCategory.high);

      String headline;
      String explanation;
      if (finalCat == RiskCategory.safe) {
        headline = 'Diner Verified Safe • High Rating (${avgRating.toStringAsFixed(1)} ★)';
        explanation = 'Score ${finalScore.toStringAsFixed(1)} / 100. High cleanliness standards observed based on customer reviews and positive ratings.';
      } else if (finalCat == RiskCategory.moderate) {
        headline = 'Moderate Risk • Mixed Customer Feedback (${avgRating.toStringAsFixed(1)} ★)';
        explanation = 'Score ${finalScore.toStringAsFixed(1)} / 100. Customer reviews and ratings indicate potential cleanliness concerns to monitor.';
      } else {
        headline = 'Elevated Risk • Critical Diner Complaints (${avgRating.toStringAsFixed(1)} ★)';
        explanation = 'Score ${finalScore.toStringAsFixed(1)} / 100. Multiple negative ratings or hygiene issue comments reported in diner feedback.';
      }

      return RestaurantRiskEvaluation(
        score: finalScore,
        category: finalCat,
        source: 'Customer Reviews & Ratings (${effectiveReviews.length} reviews)',
        headline: headline,
        explanation: explanation,
        isFromOfficer: false,
      );
    }

    // -------------------------------------------------------------
    // Baseline Standard (Fallback for new / unreviewed outlets)
    // -------------------------------------------------------------
    return const RestaurantRiskEvaluation(
      score: 10.0,
      category: RiskCategory.safe,
      source: 'Baseline Health Standard',
      headline: 'Excellent Hygiene (Grade A)',
      explanation: 'Score 10.0 / 100. Baseline safe rating observed with clean record and no negative flags.',
      isFromOfficer: false,
    );
  }

  /// Helper to get or compute dynamic risk evaluation for any restaurant
  static RestaurantRiskEvaluation getRestaurantRiskEvaluation(
    String restaurantId, {
    String? restaurantName,
    RestaurantModel? fallbackRestaurant,
  }) {
    final r = fallbackRestaurant ??
        restaurantsNotifier.value.where((x) => x.id == restaurantId || (restaurantName != null && x.name.toLowerCase() == restaurantName.toLowerCase())).firstOrNull;
    if (r == null) {
      return const RestaurantRiskEvaluation(
        score: 10.0,
        category: RiskCategory.safe,
        source: 'Baseline Health Standard',
        headline: 'Excellent Hygiene (Grade A)',
        explanation: 'Score 10.0 / 100. High cleanliness standards observed with safe food preparation practices.',
        isFromOfficer: false,
      );
    }
    return calculateDynamicRisk(r);
  }

  /// Recalculates and permanently updates the restaurant's hygiene grade, risk score, and category in memory, local storage, and Supabase
  static Future<void> syncRestaurantRiskAndGrade(String restaurantId, {String? restaurantName}) async {
    if (restaurantId.isEmpty && (restaurantName == null || restaurantName.isEmpty)) return;
    final allRests = List<RestaurantModel>.from(restaurantsNotifier.value);
    final rIdx = allRests.indexWhere((r) =>
        (restaurantId.isNotEmpty && r.id == restaurantId) ||
        (restaurantName != null && restaurantName.isNotEmpty && r.name.toLowerCase() == restaurantName.toLowerCase()));
    if (rIdx == -1) return;

    final curR = allRests[rIdx];
    final eval = calculateDynamicRisk(curR, inspections: inspectionsNotifier.value);
    final String gradeLetter = eval.score <= 20.0 ? 'A' : (eval.score <= 50.0 ? 'B' : (eval.score <= 75.0 ? 'C' : 'D'));

    allRests[rIdx] = curR.copyWith(
      hygieneRiskScore: eval.score,
      riskCategory: eval.category,
      lastUpdated: DateTime.now().toIso8601String().split('T').first,
    );
    restaurantsNotifier.value = allRests;

    try {
      final supabase = SupabaseService.client;
      await supabase.from('restaurants').update({
        'hygiene_grade': gradeLetter,
        'hygiene_risk_score': eval.score,
        'risk_category': eval.category.name,
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', curR.id);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_custom_restaurants', jsonEncode(allRests.map((r) => r.toMap()).toList()));
      await prefs.setString('cached_all_restaurants_feed', jsonEncode(allRests.map((r) => r.toMap()).toList()));
      await prefs.setString('restaurant_override_grade_${curR.id}', gradeLetter);
      await prefs.setDouble('restaurant_override_risk_score_${curR.id}', eval.score);
      await prefs.setString('restaurant_override_risk_cat_${curR.id}', eval.category.name);
    } catch (_) {}
  }

  /// Issues an official MOH enforcement action (Form 32 Warning, Compound Fine, or Closure Notice)
  static Future<bool> issueEnforcementAction({
    required String restaurantId,
    required String restaurantName,
    required EnforcementType actionType,
    required double fineAmount,
    required String statutoryCitation,
    required String directives,
    required String officerName,
    String? inspectionId,
    String? complaintId,
  }) async {
    try {
      final now = DateTime.now();
      final String issuedDate = now.toIso8601String().split('T').first;
      final String dueDate = now.add(const Duration(days: 14)).toIso8601String().split('T').first;
      final bool isSuspended = actionType == EnforcementType.closure;
      final bool isFinePaid = fineAmount == 0.0;
      final String actionStr = actionType.name;

      // 1. Update in-memory caches
      _reviewedOutletEnforcements[restaurantId] = actionStr;
      _reviewedOutletFines[restaurantId] = fineAmount;
      _reviewedOutletFinePaids[restaurantId] = isFinePaid;
      _reviewedOutletFineIssuedDates[restaurantId] = issuedDate;
      _reviewedOutletFineDueDates[restaurantId] = dueDate;
      _reviewedOutletSuspensions[restaurantId] = isSuspended;
      _reviewedOutletCitations[restaurantId] = statutoryCitation;

      // 2. Persist to SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('restaurant_override_enforcement_$restaurantId', actionStr);
        await prefs.setDouble('restaurant_override_fine_amt_$restaurantId', fineAmount);
        await prefs.setBool('restaurant_override_fine_paid_$restaurantId', isFinePaid);
        await prefs.setString('restaurant_override_fine_issued_$restaurantId', issuedDate);
        await prefs.setString('restaurant_override_fine_due_$restaurantId', dueDate);
        await prefs.setBool('restaurant_override_suspended_$restaurantId', isSuspended);
        await prefs.setString('restaurant_override_citation_$restaurantId', statutoryCitation);
      } catch (_) {}

      // 3. Update Inspection in inspectionsNotifier
      final String inspId = inspectionId ?? UuidHelper.generateV4();
      final String compId = complaintId ?? 'CMP-${DateTime.now().year}-${restaurantId.substring(0, 4).toUpperCase()}';

      final inspection = InspectionModel(
        id: inspId,
        complaintId: compId,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        scheduledDate: issuedDate,
        conductedDate: issuedDate,
        officerName: officerName,
        outcome: InspectionOutcome.nonCompliant,
        findings: directives,
        recommendedAction: actionType,
        issuedAction: actionType,
        justification: directives,
        fineAmount: fineAmount,
        enforcementStatus: EnforcementStatus.inProgress,
        statutoryCitation: statutoryCitation,
        issuedDate: issuedDate,
        dueDate: dueDate,
        isFinePaid: isFinePaid,
      );

      final currentInspections = List<InspectionModel>.from(inspectionsNotifier.value);
      final inspIdx = currentInspections.indexWhere((x) => x.id == inspId || (x.restaurantId == restaurantId && x.complaintId == compId));
      if (inspIdx != -1) {
        currentInspections[inspIdx] = inspection;
      } else {
        currentInspections.insert(0, inspection);
      }
      inspectionsNotifier.value = currentInspections;

      // 4. Update Restaurant in restaurantsNotifier with evaluated risk score & category
      final currentRestaurants = List<RestaurantModel>.from(restaurantsNotifier.value);
      final rIdx = currentRestaurants.indexWhere((r) => r.id == restaurantId || r.name == restaurantName);
      RestaurantRiskEvaluation? riskEval;
      if (rIdx != -1) {
        final baseUpdated = currentRestaurants[rIdx].copyWith(
          enforcementAction: actionStr,
          fineAmount: fineAmount,
          isFinePaid: isFinePaid,
          fineIssuedDate: issuedDate,
          fineDueDate: dueDate,
          isSuspended: isSuspended,
          statutoryCitation: statutoryCitation,
        );
        riskEval = calculateDynamicRisk(baseUpdated);
        currentRestaurants[rIdx] = baseUpdated.copyWith(
          hygieneRiskScore: riskEval.score,
          riskCategory: riskEval.category,
        );
        restaurantsNotifier.value = currentRestaurants;
      }

      // 5. Update Supabase restaurants and inspections tables
      try {
        final supabase = SupabaseService.client;

        // Try updating restaurants table with enforcement columns and recalculated risk
        try {
          final Map<String, dynamic> updateMap = {
            'enforcement_action': actionStr,
            'fine_amount': fineAmount,
            'is_fine_paid': isFinePaid,
            'fine_issued_date': issuedDate,
            'fine_due_date': dueDate,
            'is_suspended': isSuspended,
            'statutory_citation': statutoryCitation,
            'last_updated': DateTime.now().toUtc().toIso8601String(),
          };
          if (riskEval != null) {
            final String gradeLetter = riskEval.score <= 20.0 ? 'A' : (riskEval.score <= 50.0 ? 'B' : (riskEval.score <= 75.0 ? 'C' : 'D'));
            updateMap['hygiene_grade'] = gradeLetter;
            updateMap['hygiene_risk_score'] = riskEval.score;
            updateMap['risk_category'] = riskEval.category.name;
          }
          await supabase.from('restaurants').update(updateMap).eq('id', restaurantId);
        } catch (e) {
          debugPrint('Supabase restaurants enforcement columns update note: $e');
        }

        // Try upserting inspection record
        try {
          await supabase.from('inspections').upsert({
            'id': inspId,
            'complaint_id': compId,
            'restaurant_id': restaurantId,
            'restaurant_name': restaurantName,
            'scheduled_date': issuedDate,
            'conducted_date': issuedDate,
            'officer_name': officerName,
            'outcome': InspectionOutcome.nonCompliant.name,
            'findings': directives,
            'recommended_action': actionType.name,
            'issued_action': actionType.name,
            'justification': directives,
            'fine_amount': fineAmount,
            'enforcement_status': EnforcementStatus.inProgress.name,
            'statutory_citation': statutoryCitation,
            'issued_date': issuedDate,
            'due_date': dueDate,
            'is_fine_paid': isFinePaid,
          });
        } catch (e) {
          debugPrint('Supabase inspections table upsert note: $e');
        }
      } catch (e) {
        debugPrint('Supabase update error during enforcement: $e');
      }

      // 6. Log Audit Trail
      AuditLogService.logAction(
        actionType: 'ENFORCEMENT_DECREE_ISSUED',
        category: 'Government',
        title: 'MOH Enforcement Action Issued: ${actionType.name.toUpperCase()}',
        description: 'Issued ${actionType.name.toUpperCase()} (Fine: RM ${fineAmount.toStringAsFixed(2)}) for $restaurantName. Citation: $statutoryCitation. Directives: $directives',
      );

      // 7. Send Immediate Notification to Owner
      final String restOwnerId = rIdx != -1 ? currentRestaurants[rIdx].ownerId : 'own_001';
      NotificationService.sendNotification(
        userId: restOwnerId,
        title: '🚨 Official MOH Enforcement Decree: ${actionType.name.toUpperCase()}',
        message: 'Ministry of Health issued ${actionType.name.toUpperCase()} for $restaurantName (Fine: RM ${fineAmount.toStringAsFixed(2)}). Due: $dueDate. Citation: $statutoryCitation',
        type: NotificationType.hygieneAlert,
        actionUrl: 'enforcement_notice',
      );

      return true;
    } catch (e) {
      debugPrint('Error issuing enforcement action: $e');
      return false;
    }
  }

  /// Settles an active compound fine for a restaurant via official payment gateway
  static Future<bool> settleCompoundFine({
    required String restaurantId,
    required String paymentReference,
    required double amountPaid,
    String? restaurantName,
    String? inspectionId,
    String? complaintId,
    String paymentMethod = 'FPX Online Banking',
    String? statutoryCitation,
    String? invoiceUrl,
    String? receiptUrl,
    String? stripeChargeId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (inspectionId == null || inspectionId.isEmpty || !amountPaid.isFinite || amountPaid <= 0 ||
          !paymentReference.startsWith('pi_') || paymentReference.startsWith('pi_test_')) {
        return false;
      }
      // The server retrieves Stripe's receipt and commits only the linked fine.
      final response = await SupabaseService.client.functions.invoke('stripe-payment', body: {
        'action': 'settle-inspection-payment',
        'inspection_id': UuidHelper.toDeterministicUuid(inspectionId),
        'payment_intent_id': paymentReference,
      });
      if (response.status != 200 || response.data is! Map || response.data['success'] != true ||
          response.data['inspection'] is! Map) { return false; }
      final inspection = InspectionModel.fromMap(Map<String, dynamic>.from(response.data['inspection']));
      if (!inspection.isFinePaid) return false;
      await _cacheConfirmedInspection(inspection);
      AuditLogService.logAction(
        actionType: 'COMPOUND_FINE_SETTLED', category: 'Finance',
        title: 'Compound Penalty Settled',
        description: 'Payment confirmed for inspection ${inspection.id}. Ref: $paymentReference. Awaiting officer closure.',
      );
      return true;
    } catch (e) {
      debugPrint('Payment confirmation failed: $e');
      return false;
    }
  }

  /// Get the latest inspection/enforcement record for a specific restaurant
  static InspectionModel? getLatestInspectionForRestaurant(String restaurantId) {
    if (restaurantId.isEmpty) return null;
    final all = inspectionsNotifier.value;
    return all.where((i) => i.restaurantId == restaurantId).firstOrNull;
  }

  /// Uploads an SSM certificate image file to Supabase storage bucket 'Images' in folder 'SSM'
  static Future<String?> uploadSSMCertificateFile(File file, String restaurantId) async {
    try {
      final supabase = SupabaseService.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Sign in before uploading a certificate.');
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('The certificate image is empty.');
      final extension = file.path.split('.').last.toLowerCase();
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        _ => 'image/jpeg',
      };
      final fileName = 'SSM_Cert_${restaurantId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final storagePath = 'SSM/$userId/$fileName';
      await supabase.storage.from('Images').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: contentType),
      );
      return supabase.storage.from('Images').getPublicUrl(storagePath);
    } catch (e) {
      if (kDebugMode) {
        print('Supabase SSM cert upload warning: $e');
      }
      return null;
    }
  }

  /// Save a new restaurant input to Supabase database & append to active store
  static Future<RestaurantModel> addRestaurant({
    required String name,
    required String address,
    required String category,
    required double latitude,
    required double longitude,
    String? ssmCertUrl,
    String operatingHours = '10:00 AM - 10:00 PM (Daily)',
    String? imageUrl,
    bool autoApprove = false,
    bool ocrVerified = false,
    double ocrConfidence = 0.0,
    String? ocrCompanyName,
    String? ocrRegistrationNo,
  }) async {
    if (name.trim().isEmpty || address.trim().isEmpty || category.trim().isEmpty ||
        ssmCertUrl == null || ssmCertUrl.trim().isEmpty) {
      throw ArgumentError('Enter the premises details and attach the registration certificate.');
    }
    final String id = UuidHelper.generateV4();
    final String nowIso = DateTime.now().toUtc().toIso8601String();

    final RestaurantStatus status = autoApprove ? RestaurantStatus.approved : RestaurantStatus.pendingVerification;
    final String statusStr = autoApprove ? 'approved' : 'pendingVerification';
    final String? currentUserId = SupabaseService.client.auth.currentUser?.id ?? CustomerStoreService.currentCustomer?.id;
    final String? generatedRegNo = status == RestaurantStatus.approved
        ? 'SSM-${DateTime.now().year}-${id.substring(0, 6).toUpperCase()}-X'
        : null;

    final String finalImageUrl = (imageUrl != null && imageUrl.trim().isNotEmpty)
        ? imageUrl.trim()
        : '';

    // Upload SSM Certificate to Supabase Bucket if file exists locally
    String? uploadedSsmUrl;
    if (ssmCertUrl.isNotEmpty && File(ssmCertUrl).existsSync()) {
      uploadedSsmUrl = await uploadSSMCertificateFile(File(ssmCertUrl), id);
    }
    final String finalSsmCertUrl = uploadedSsmUrl ?? ssmCertUrl;
    if (!finalSsmCertUrl.startsWith('https://')) {
      throw StateError('The registration certificate could not be uploaded. Please try again.');
    }

    final newRestaurant = RestaurantModel(
      id: id,
      name: name,
      address: address,
      category: category,
      latitude: latitude,
      longitude: longitude,
      hygieneRiskScore: 10.0,
      riskCategory: RiskCategory.safe,
      status: status,
      violationCount: 0,
      imageUrl: finalImageUrl,
      lastUpdated: nowIso.split('T').first,
      ownerId: currentUserId ?? 'own_001',
      operatingHours: operatingHours,
      businessRegNo: generatedRegNo,
      ssmCertUrl: finalSsmCertUrl,
      ocrVerified: ocrVerified,
      ocrConfidence: ocrConfidence,
      ocrCompanyName: ocrCompanyName,
      ocrRegistrationNo: ocrRegistrationNo,
    );

    // 1. Insert into Supabase Database `restaurants` table matching exact Postgres schema
    try {
      final supabase = SupabaseService.client;
      final Map<String, dynamic> insertData = {
        'id': id,
        'name': name,
        'address': address,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        'hygiene_grade': 'A',
        'hygiene_risk_score': 10.0,
        'risk_category': 'safe',
        'status': statusStr,
        'violation_count': 0,
        'image_url': finalImageUrl,
        'created_at': nowIso,
        'last_updated': nowIso,
      };

      if (currentUserId != null && currentUserId.isNotEmpty && _isValidUuid(currentUserId)) {
        insertData['owner_id'] = currentUserId;
      }

      // Try inserting with operating_hours, business_reg_no, ssm_cert_url, and OCR metadata into database
      try {
        final Map<String, dynamic> insertDataWithExtraCols = Map<String, dynamic>.from(insertData);
        insertDataWithExtraCols['operating_hours'] = operatingHours;
        insertDataWithExtraCols['ssm_cert_url'] = finalSsmCertUrl;
        if (generatedRegNo != null) {
          insertDataWithExtraCols['business_reg_no'] = generatedRegNo;
        }
        insertDataWithExtraCols['ocr_verified'] = ocrVerified;
        insertDataWithExtraCols['ocr_confidence'] = ocrConfidence;
        if (ocrCompanyName != null && ocrCompanyName.isNotEmpty) {
          insertDataWithExtraCols['ocr_company_name'] = ocrCompanyName;
        }
        if (ocrRegistrationNo != null && ocrRegistrationNo.isNotEmpty) {
          insertDataWithExtraCols['ocr_registration_no'] = ocrRegistrationNo;
        }
        await supabase.from('restaurants').insert(insertDataWithExtraCols);
      } catch (_) { rethrow; }
    } catch (_) { rethrow; }

    // 2. Persist to local disk SharedPreferences for offline & session recovery
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString('local_custom_restaurants');
      List<dynamic> list = [];
      if (localJson != null && localJson.isNotEmpty) {
        list = jsonDecode(localJson);
      }
      list.removeWhere((item) => item['id'] == newRestaurant.id || item['name'] == newRestaurant.name);
      list.insert(0, newRestaurant.toMap());
      await prefs.setString('local_custom_restaurants', jsonEncode(list));
      await prefs.setString(
        'restaurant_ssm_ocr_${newRestaurant.id}',
        jsonEncode({
          'restaurant_name': name,
          'restaurant_id': newRestaurant.id,
          'ocr_verified': ocrVerified,
          'ocr_confidence': ocrConfidence,
          'ocr_company_name': ocrCompanyName,
          'ocr_registration_no': ocrRegistrationNo,
          'ssm_cert_url': finalSsmCertUrl,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}

    // 3. Append to active in-memory restaurants store
    if (!restaurantsNotifier.value.any((r) => r.id == newRestaurant.id || r.name == newRestaurant.name)) {
      final updatedList = List<RestaurantModel>.from(restaurantsNotifier.value);
      updatedList.insert(0, newRestaurant);
      restaurantsNotifier.value = updatedList;
    }

    try {
      await AuditLogService.logAction(
        actionType: 'REST_ADDED',
        category: 'Business',
        title: 'New Outlet Registered',
        description: 'Premises "$name" submitted for MOH verification at $address',
      );
    } catch (_) {}

    return newRestaurant;
  }

  /// Fetches all restaurants belonging to the given owner from Supabase.
  /// Merges with local custom storage and mock seed data.
  /// Fetches all public and verified restaurants from Supabase database `restaurants` table.
  /// Merges with local custom restaurants and updates real-time listeners.
  static Future<List<RestaurantModel>> fetchAllRestaurants({bool forceRefresh = false}) async {
    // 0. If in-memory already populated and not force refreshing, return instantly
    if (restaurantsNotifier.value.isNotEmpty && !forceRefresh) {
      return restaurantsNotifier.value;
    }

    // 0b. Instant hydration from local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_all_restaurants_feed');
      if (cachedJson != null && cachedJson.isNotEmpty && restaurantsNotifier.value.isEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final List<RestaurantModel> cachedList = [];
        for (final item in decoded) {
          cachedList.add(RestaurantModel.fromMap(Map<String, dynamic>.from(item as Map)));
        }
        if (cachedList.isNotEmpty) {
          restaurantsNotifier.value = List.from(cachedList);
        }
      }
    } catch (_) {}

    final List<RestaurantModel> fetchedList = [];
    final Set<String> seenIds = {};

    // 1. Fetch from Supabase `restaurants` table with 3-second timeout
    try {
      final supabase = SupabaseService.client;
      final res = await supabase
          .from('restaurants')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 3));
      final List<dynamic> rows = res as List<dynamic>;

      for (final r in rows) {
        final mapData = Map<String, dynamic>.from(r as Map<String, dynamic>);
        final String rId = mapData['id']?.toString() ?? '';
        if (rId.isNotEmpty && !seenIds.contains(rId)) {
          seenIds.add(rId);
          await _applyOverridesToMap(mapData);
          fetchedList.add(RestaurantModel.fromMap(mapData));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching all restaurants from Supabase: $e');
      }
    }

    // 2. Fetch from SharedPreferences local_custom_restaurants
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString('local_custom_restaurants');
      if (localJson != null && localJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(localJson);
        for (final item in decoded) {
          final mapData = Map<String, dynamic>.from(item as Map);
          final String rId = mapData['id']?.toString() ?? '';
          if (rId.isNotEmpty && !seenIds.contains(rId)) {
            seenIds.add(rId);
            await _applyOverridesToMap(mapData);
            fetchedList.insert(0, RestaurantModel.fromMap(mapData));
          }
        }
      }
    } catch (_) {}

    if (fetchedList.isNotEmpty) {
      restaurantsNotifier.value = List.from(fetchedList);
      // Cache locally for instant next startup
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_all_restaurants_feed', jsonEncode(fetchedList.map((r) => r.toMap()).toList()));
      } catch (_) {}
    }

    return fetchedList;
  }

  static Future<List<RestaurantModel>> fetchOwnerRestaurants(String? ownerId, {String? ownerEmail}) async {
    final List<RestaurantModel> fetchedList = [];
    final Set<String> seenIds = {};

    final cleanOwnerId = ownerId?.trim();
    final cleanOwnerEmail = ownerEmail?.trim().toLowerCase();

    // If no owner filter is specified, do not leak any restaurants
    if ((cleanOwnerId == null || cleanOwnerId.isEmpty) && (cleanOwnerEmail == null || cleanOwnerEmail.isEmpty)) {
      return [];
    }

    // 1. Fetch from Supabase
    try {
      final supabase = SupabaseService.client;
      final res = await supabase.from('restaurants').select().order('created_at', ascending: false);
      final List<dynamic> rows = res as List<dynamic>;

      for (final r in rows) {
        final mapData = Map<String, dynamic>.from(r as Map<String, dynamic>);
        final String rOwnerId = (mapData['owner_id']?.toString() ?? '').trim();
        final String rId = mapData['id']?.toString() ?? '';

        final bool isOwnerMatch = (cleanOwnerId != null && cleanOwnerId.isNotEmpty && rOwnerId == cleanOwnerId) ||
            (cleanOwnerEmail != null && cleanOwnerEmail.isNotEmpty && rOwnerId.toLowerCase() == cleanOwnerEmail);

        if (isOwnerMatch && rId.isNotEmpty && !seenIds.contains(rId)) {
          seenIds.add(rId);
          await _applyOverridesToMap(mapData);
          fetchedList.add(RestaurantModel.fromMap(mapData));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching owner restaurants from Supabase: $e');
      }
    }

    // 2. Fallback to SharedPreferences local_custom_restaurants ONLY when offline
    if (fetchedList.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final localJson = prefs.getString('local_custom_restaurants');
        if (localJson != null && localJson.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(localJson);
          for (final item in decoded) {
            final mapData = Map<String, dynamic>.from(item as Map);
            final String rOwnerId = (mapData['owner_id']?.toString() ?? '').trim();
            final String rId = mapData['id']?.toString() ?? '';

            final bool isOwnerMatch = (cleanOwnerId != null && cleanOwnerId.isNotEmpty && rOwnerId == cleanOwnerId) ||
                (cleanOwnerEmail != null && cleanOwnerEmail.isNotEmpty && rOwnerId.toLowerCase() == cleanOwnerEmail);

            if (isOwnerMatch && rId.isNotEmpty && !seenIds.contains(rId)) {
              seenIds.add(rId);
              await _applyOverridesToMap(mapData);
              fetchedList.add(RestaurantModel.fromMap(mapData));
            }
          }
        }
      } catch (_) {}
    }

    return fetchedList;
  }

  /// Fetches pending outlet verification requests directly from Supabase database `restaurants` table.
  static Future<List<RestaurantModel>> fetchPendingRestaurants() async {
    try {
      final supabase = SupabaseService.client;
      final res = await supabase
          .from('restaurants')
          .select()
          .order('created_at', ascending: false);

      final List<dynamic> rows = res as List<dynamic>;
      final List<RestaurantModel> pendingList = [];
      for (final r in rows) {
        final mapData = Map<String, dynamic>.from(r as Map<String, dynamic>);
        await _applyOverridesToMap(mapData);
        final model = RestaurantModel.fromMap(mapData);
        if (model.status == RestaurantStatus.pendingVerification) {
          pendingList.add(model);
        }
      }

      return pendingList;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching pending restaurants from Supabase: $e');
      }
    }

    return [];
  }

  /// Fetches pending outlet verification requests with Supabase SQL range pagination.
  static Future<List<RestaurantModel>> fetchPendingRestaurantsPaginated({
    required int page,
    required int pageSize,
  }) async {
    try {
      final supabase = SupabaseService.client;
      final int from = page * pageSize;
      final int to = from + pageSize - 1;

      final res = await supabase
          .from('restaurants')
          .select()
          .order('created_at', ascending: false)
          .range(from, to);

      final List<dynamic> rows = res as List<dynamic>;
      final List<RestaurantModel> pendingList = [];
      for (final r in rows) {
        final mapData = Map<String, dynamic>.from(r as Map<String, dynamic>);
        await _applyOverridesToMap(mapData);
        final model = RestaurantModel.fromMap(mapData);
        if (model.status == RestaurantStatus.pendingVerification) {
          pendingList.add(model);
        }
      }
      return pendingList;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching paginated pending restaurants from Supabase: $e');
      }
    }

    // Fallback in-memory slicing
    final allPending = restaurantsNotifier.value.where((r) {
      final String effectiveStatus = _reviewedOutletStatuses[r.id] ?? r.status.name;
      return effectiveStatus == 'pendingVerification';
    }).toList();
    allPending.sort((a, b) {
      final aDate = DateTime.tryParse(a.createdAt ?? '');
      final bDate = DateTime.tryParse(b.createdAt ?? '');
      if (aDate == null && bDate == null) return b.id.compareTo(a.id);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final byDate = bDate.compareTo(aDate);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });

    final int start = page * pageSize;
    if (start >= allPending.length) return [];
    final int end = (start + pageSize) > allPending.length ? allPending.length : (start + pageSize);
    return allPending.sublist(start, end);
  }

  /// Update restaurant status (e.g. approve/reject/needsRevision) in Supabase database & local store
  static Future<bool> updateRestaurantStatus({
    required String restaurantId,
    required String status,
    String? businessRegNo,
    String? revisionNotes,
  }) async {
    // 1. Record status override in session memory & SharedPreferences immediately
    _reviewedOutletStatuses[restaurantId] = status;
    if (businessRegNo != null && businessRegNo.isNotEmpty) {
      _reviewedOutletRegNos[restaurantId] = businessRegNo;
    }
    await _saveOverrideToPrefs(restaurantId, status, businessRegNo);

    try {
      final supabase = SupabaseService.client;
      final String nowIso = DateTime.now().toUtc().toIso8601String();
      final Map<String, dynamic> updateData = {
        'status': status,
        'last_updated': nowIso,
      };

      if (businessRegNo != null && businessRegNo.isNotEmpty) {
        updateData['business_reg_no'] = businessRegNo;
      }

      // Update Supabase `restaurants` table
      try {
        await supabase.from('restaurants').update(updateData).eq('id', restaurantId);
      } catch (e) {
        if (kDebugMode) {
          print('Error updating restaurant status in Supabase table: $e');
        }
      }

      // Update local in-memory MockSeedData store for instant UI reactivity
      final idx = restaurantsNotifier.value.indexWhere((r) => r.id == restaurantId);
      if (idx != -1) {
        final old = restaurantsNotifier.value[idx];
        final RestaurantStatus newStatus = status == 'approved'
            ? RestaurantStatus.approved
            : (status == 'needsRevision'
                ? RestaurantStatus.needsRevision
                : (status == 'rejected' ? RestaurantStatus.rejected : RestaurantStatus.pendingVerification));
        restaurantsNotifier.value[idx] = old.copyWith(
          status: newStatus,
          lastUpdated: nowIso.split('T').first,
          businessRegNo: businessRegNo ?? old.businessRegNo,
        );
      }

      // Log Audit Action
      final String auditActionType = status == 'approved'
          ? 'OUTLET_APPROVED'
          : (status == 'needsRevision' ? 'REVISION_REQUESTED' : 'OUTLET_REJECTED');
      final String auditTitle = status == 'approved'
          ? 'Outlet Application Approved'
          : (status == 'needsRevision' ? 'Revision Requested for Outlet' : 'Outlet Application Rejected');
      final String notesText = (revisionNotes != null && revisionNotes.trim().isNotEmpty) ? revisionNotes.trim() : 'No notes provided';
      final String auditDesc = status == 'approved'
          ? 'Approved outlet application (Reg No: ${businessRegNo ?? "N/A"}). Notes: $notesText'
          : (status == 'needsRevision'
              ? 'Revision requested for outlet ID: $restaurantId. Notes: $notesText'
              : 'Rejected outlet application ID: $restaurantId. Notes: $notesText');

      AuditLogService.logAction(
        actionType: auditActionType,
        category: 'Government',
        title: auditTitle,
        description: auditDesc,
      );

      // Send real-time heads-up push notification to Owner & Public
      final cleanRestName = resolveRestaurantName(restaurantId);
      final notifTitle = status == 'approved'
          ? '🎉 Outlet Application Approved!'
          : (status == 'needsRevision' ? '⚠️ Outlet Application Needs Revision' : '❌ Outlet Application Rejected');
      final notifMessage = status == 'approved'
          ? '$cleanRestName has been verified (Reg: ${businessRegNo ?? "SSM-VERIFIED"}). It is now live for diners!'
          : (status == 'needsRevision'
              ? 'Revision requested for $cleanRestName. $notesText'
              : 'Application for $cleanRestName was rejected. $notesText');

      NotificationService.sendNotification(
        userId: 'own_001',
        title: notifTitle,
        message: notifMessage,
        type: NotificationType.outlet,
        actionUrl: 'restaurant_$restaurantId',
      );

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating restaurant status in Supabase: $e');
      }
      return false;
    }
  }

  static List<Map<String, String>> _getDefaultSeedReviews(String restaurantId, {String? restaurantName}) {
    final cleanId = restaurantId.toLowerCase();
    final cleanName = (restaurantName ?? '').toLowerCase();

    if (cleanId == 'rest_testing_custom' ||
        cleanId == '0aaacf20-3102-4064-b859-fdb1a48eed37' ||
        cleanId == 'testing' ||
        cleanId.contains('testing') ||
        cleanName == 'testing' ||
        cleanName.contains('testing')) {
      return [
        {
          'id': 'rev_test_ahmeng_003',
          'userName': 'AHMENG',
          'userId': '68f0a0bb-b996-48cb-8fec-f349be88a107',
          'userEmail': 'ahmeng@gmail.com',
          'userAvatar': '',
          'date': '2026-08-23',
          'timestamp': '2026-08-23T12:00:00.000Z',
          'stars': '5',
          'comment': 'CleanKitchen',
          'ownerReply': '',
          'likedUserIds': '[]',
          'helpfulCount': '0',
        },
        {
          'id': 'rev_test_low_001',
          'userName': 'low',
          'userId': 'e257a3d8-a2e2-4872-afcf-0d7324e8f0cf',
          'userEmail': 'lowyq-wm22@student.tarc.edu.my',
          'userAvatar': '',
          'date': '2026-08-14',
          'timestamp': '2026-08-14T20:41:00.000Z',
          'stars': '5',
          'comment': 'hi',
          'ownerReply': 'hello',
          'likedUserIds': '[]',
          'helpfulCount': '0',
        },
        {
          'id': 'rev_test_testing_002',
          'userName': 'testing',
          'userId': '119bac14-377c-4062-84c3-b2b723525170',
          'userEmail': 'testing@gmail.com',
          'userAvatar': '',
          'date': '2026-08-14',
          'timestamp': '2026-08-14T20:40:00.000Z',
          'stars': '5',
          'comment': 'hi',
          'ownerReply': '',
          'likedUserIds': '[]',
          'helpfulCount': '0',
        },
      ];
    }

    if (cleanId == 'rest_001' || cleanId == 'rest_002') {
      return [
        {
          'id': 'rev_seed_001',
          'userName': 'Ahmad Razak',
          'date': '2026-07-28',
          'stars': '5',
          'comment': 'Very clean dining area and kitchen! Food served hot and fresh. Staff wore hairnets properly.',
          'ownerReply': '',
        },
        {
          'id': 'rev_seed_002',
          'userName': 'Siti Sarah',
          'date': '2026-07-22',
          'stars': '4',
          'comment': 'Great food! Tables were wiped clean quickly after customers left. Passed hygiene inspection.',
          'ownerReply': '',
        },
      ];
    }
    return [];
  }

  /// Get ratings synchronously (using in-memory cache or default seed rules)
  static RestaurantRatingInfo getRatingSync(String restaurantId, {String? restaurantName}) {
    final cleanId = restaurantId.toLowerCase().trim();
    String? cleanName = restaurantName?.toLowerCase().trim();
    if (cleanName == null || cleanName.isEmpty) {
      final matched = restaurantsNotifier.value.where((r) => r.id == restaurantId).firstOrNull;
      cleanName = matched?.name.toLowerCase().trim();
    }

    List<Map<String, String>>? reviews = _reviewMemoryCache[restaurantId] ??
        _reviewMemoryCache[cleanId] ??
        (cleanName != null && cleanName.isNotEmpty ? _reviewMemoryCache[cleanName] : null);

    if (reviews == null || reviews.isEmpty) {
      final seed = _getDefaultSeedReviews(restaurantId, restaurantName: restaurantName ?? cleanName);
      if (seed.isNotEmpty) {
        reviews = seed;
        _reviewMemoryCache[restaurantId] = seed;
        _reviewMemoryCache[cleanId] = seed;
        if (cleanName != null && cleanName.isNotEmpty) {
          _reviewMemoryCache[cleanName] = seed;
        }
      }
    }

    if (reviews == null || reviews.isEmpty) {
      return const RestaurantRatingInfo(averageRating: 0.0, totalReviews: 0);
    }
    double sum = 0;
    for (var r in reviews) {
      sum += (double.tryParse(r['stars'] ?? '0') ?? 0);
    }
    return RestaurantRatingInfo(
      averageRating: sum / reviews.length,
      totalReviews: reviews.length,
    );
  }

  /// Fetch reviews from Supabase (restaurants.reviews_json & audit_logs), fallback to SharedPreferences and seed reviews, merging all data without loss on restart
  static Future<List<Map<String, String>>> fetchReviews(String restaurantId, {String? restaurantName, bool forceRefresh = false}) async {
    String? cleanName = restaurantName?.trim();
    if (cleanName == null || cleanName.isEmpty) {
      final matched = restaurantsNotifier.value.where((r) => r.id == restaurantId).firstOrNull;
      cleanName = matched?.name.trim();
    }
    final validRestUuid = UuidHelper.toDeterministicUuid(restaurantId);

    // 1. Check memory cache first (if not forcing refresh)
    if (!forceRefresh) {
      if (_reviewMemoryCache.containsKey(restaurantId) && _reviewMemoryCache[restaurantId]!.isNotEmpty) {
        return _reviewMemoryCache[restaurantId]!;
      }
      if (cleanName != null &&
          _reviewMemoryCache.containsKey(cleanName.toLowerCase()) &&
          _reviewMemoryCache[cleanName.toLowerCase()]!.isNotEmpty) {
        final cached = _reviewMemoryCache[cleanName.toLowerCase()]!;
        _reviewMemoryCache[restaurantId] = cached;
        return cached;
      }
    }

    // Merge container for all discovered reviews (deduplicating by user account per restaurant)
    final Map<String, Map<String, String>> mergedMap = {};

    final currentCustomer = CustomerStoreService.currentCustomer;
    final currentCustId = currentCustomer?.id.trim();
    final currentCustEmail = currentCustomer?.email.trim().toLowerCase();
    final currentCustName = currentCustomer?.name.trim();

    void addOrMergeReview(Map<String, String> r) {
      final rUserId = (r['userId'] ?? '').trim();
      final rUserEmail = (r['userEmail'] ?? '').trim().toLowerCase();
      final rUserName = (r['userName'] ?? '').trim();
      final comment = (r['comment'] ?? '').trim();
      final id = (r['id'] ?? '').trim();

      // Check if this review belongs to the currently logged in user or known aliases (e.g. Ahmad -> AHMENG)
      bool isMatchingCurrentUser = false;
      if (currentCustId != null && currentCustId.isNotEmpty && rUserId == currentCustId) {
        isMatchingCurrentUser = true;
      } else if (currentCustEmail != null && currentCustEmail.isNotEmpty && rUserEmail == currentCustEmail) {
        isMatchingCurrentUser = true;
      } else if (currentCustName != null && currentCustName.isNotEmpty && rUserName.toLowerCase() == currentCustName.toLowerCase()) {
        isMatchingCurrentUser = true;
      } else if (currentCustName != null &&
          (currentCustName.toLowerCase() == 'ahmeng' || currentCustName.toLowerCase() == 'ahmad') &&
          (rUserName.toLowerCase() == 'ahmad' || rUserName.toLowerCase() == 'ahmeng')) {
        isMatchingCurrentUser = true;
      }

      // Always resolve latest display name and avatar from current profile
      if (isMatchingCurrentUser && currentCustName != null && currentCustName.isNotEmpty) {
        r['userName'] = currentCustName;
        if (currentCustomer?.avatarUrl != null && currentCustomer!.avatarUrl.isNotEmpty) {
          r['userAvatar'] = currentCustomer.avatarUrl;
        }
        if (currentCustId != null && currentCustId.isNotEmpty) {
          r['userId'] = currentCustId;
        }
        if (currentCustEmail != null && currentCustEmail.isNotEmpty) {
          r['userEmail'] = currentCustEmail;
        }
      }

      // Generate unique user key so one user account maintains one consolidated review per outlet
      String userKey;
      if (isMatchingCurrentUser && currentCustId != null && currentCustId.isNotEmpty) {
        userKey = 'usr_$currentCustId';
      } else if (isMatchingCurrentUser && currentCustEmail != null && currentCustEmail.isNotEmpty) {
        userKey = 'usr_$currentCustEmail';
      } else if (rUserId.isNotEmpty) {
        userKey = 'usr_$rUserId';
      } else if (rUserEmail.isNotEmpty) {
        userKey = 'usr_$rUserEmail';
      } else if (rUserName.isNotEmpty) {
        userKey = 'name_${rUserName.toLowerCase()}';
      } else if (id.isNotEmpty) {
        userKey = 'id_$id';
      } else {
        userKey = 'comment_${comment.hashCode}';
      }

      if (!mergedMap.containsKey(userKey)) {
        mergedMap[userKey] = Map<String, String>.from(r);
      } else {
        final existing = mergedMap[userKey]!;
        final existingTime = existing['timestamp'] ?? existing['date'] ?? '';
        final newTime = r['timestamp'] ?? r['date'] ?? '';
        final bool incomingIsNewer = newTime.compareTo(existingTime) >= 0;

        if (incomingIsNewer) {
          final reply = (r['ownerReply'] ?? '').isNotEmpty ? r['ownerReply']! : (existing['ownerReply'] ?? '');
          final mergedLiked = (r['likedUserIds'] ?? '[]').length >= (existing['likedUserIds'] ?? '[]').length
              ? r['likedUserIds']
              : existing['likedUserIds'];
          final mergedCount = (r['likedUserIds'] ?? '[]').length >= (existing['likedUserIds'] ?? '[]').length
              ? r['helpfulCount']
              : existing['helpfulCount'];

          final updated = Map<String, String>.from(r);
          if (reply.isNotEmpty) updated['ownerReply'] = reply;
          if (mergedLiked != null) updated['likedUserIds'] = mergedLiked;
          if (mergedCount != null) updated['helpfulCount'] = mergedCount;
          mergedMap[userKey] = updated;
        } else {
          if ((r['ownerReply'] ?? '').isNotEmpty && (existing['ownerReply'] ?? '').isEmpty) {
            existing['ownerReply'] = r['ownerReply']!;
          }
          final existingLiked = existing['likedUserIds'] ?? '[]';
          final newLiked = r['likedUserIds'] ?? '[]';
          if (newLiked.length > existingLiked.length) {
            existing['likedUserIds'] = newLiked;
            existing['helpfulCount'] = r['helpfulCount'] ?? '0';
          }
          mergedMap[userKey] = existing;
        }
      }
    }

    // A. Start with default seed reviews for baseline (e.g. low, testing, ahmeng)
    final seedReviews = _getDefaultSeedReviews(restaurantId, restaurantName: cleanName);
    for (final sr in seedReviews) {
      addOrMergeReview(sr);
    }

    // B. Try fetching from Supabase 'restaurants' table (reviews_json & reviews columns)
    try {
      final supabase = SupabaseService.client;
      dynamic restRow;
      try {
        restRow = await supabase
            .from('restaurants')
            .select('id, name, reviews_json')
            .or('id.eq.$restaurantId,id.eq.$validRestUuid${cleanName != null && cleanName.isNotEmpty ? ",name.ilike.$cleanName" : ""}')
            .maybeSingle();
      } catch (_) {}

      if (restRow != null) {
        List<dynamic>? serverReviews;
        if (restRow['reviews'] is List) {
          serverReviews = restRow['reviews'] as List<dynamic>;
        } else if (restRow['reviews_json'] != null) {
          try {
            serverReviews = jsonDecode(restRow['reviews_json'].toString());
          } catch (_) {}
        }
        if (serverReviews != null) {
          for (final item in serverReviews) {
            if (item is Map) {
              addOrMergeReview(Map<String, String>.from(
                item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
              ));
            }
          }
        }
      }
    } catch (_) {}

    // C. Try fetching from Supabase 'audit_logs' table (action_type = 'CUSTOMER_REVIEW')
    try {
      final supabase = SupabaseService.client;
      final logs = await supabase
          .from('audit_logs')
          .select()
          .eq('action_type', 'CUSTOMER_REVIEW')
          .order('created_at', ascending: false);

      for (final log in logs) {
        final title = (log['title'] ?? '').toString().toLowerCase();
        final desc = (log['description'] ?? '').toString();
        if (desc.startsWith('{') && desc.endsWith('}')) {
          try {
            final m = Map<String, dynamic>.from(jsonDecode(desc) as Map);
            final rId = (m['restaurantId'] ?? '').toString().toLowerCase();
            final rName = (m['restaurantName'] ?? '').toString().toLowerCase();
            final bool isMatch = (rId == restaurantId.toLowerCase()) ||
                (rId == validRestUuid.toLowerCase()) ||
                (cleanName != null && cleanName.isNotEmpty && (rName == cleanName.toLowerCase() || title == cleanName.toLowerCase()));

            if (isMatch) {
              addOrMergeReview({
                'id': m['id']?.toString() ?? '',
                'userName': m['userName']?.toString() ?? 'Customer',
                'userId': m['userId']?.toString() ?? (log['user_id'] ?? '').toString(),
                'userEmail': m['userEmail']?.toString() ?? (log['user_email'] ?? '').toString(),
                'userAvatar': m['userAvatar']?.toString() ?? '',
                'stars': m['stars']?.toString() ?? '5',
                'comment': m['comment']?.toString() ?? '',
                'ownerReply': m['ownerReply']?.toString() ?? '',
                'date': m['date']?.toString() ?? '',
                'timestamp': m['timestamp']?.toString() ?? log['created_at']?.toString() ?? '',
                'likedUserIds': m['likedUserIds']?.toString() ?? '[]',
                'helpfulCount': m['helpfulCount']?.toString() ?? '0',
              });
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // D. Merge local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        'restaurant_reviews_$restaurantId',
        'restaurant_reviews_$validRestUuid',
        if (cleanName != null) 'restaurant_reviews_${cleanName.toLowerCase()}',
      ]) {
        final jsonStr = prefs.getString(key);
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          for (final item in decoded) {
            if (item is Map) {
              addOrMergeReview(Map<String, String>.from(
                item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
              ));
            }
          }
        }
      }
    } catch (_) {}

    // E. Merge real-time helpful votes recorded in audit_logs across all devices
    try {
      final supabase = SupabaseService.client;
      final voteLogs = await supabase
          .from('audit_logs')
          .select()
          .eq('action_type', 'REVIEW_HELPFUL_VOTE')
          .order('created_at', ascending: true);

      for (final vlog in voteLogs) {
        final desc = (vlog['description'] ?? '').toString();
        if (desc.startsWith('{') && desc.endsWith('}')) {
          try {
            final vm = Map<String, dynamic>.from(jsonDecode(desc) as Map);
            final rId = (vm['restaurantId'] ?? '').toString().toLowerCase();
            final rName = (vm['restaurantName'] ?? '').toString().toLowerCase();
            final bool isMatch = (rId == restaurantId.toLowerCase()) ||
                (rId == validRestUuid.toLowerCase()) ||
                (cleanName != null && cleanName.isNotEmpty && (rName == cleanName.toLowerCase() || (vlog['title'] ?? '').toString().toLowerCase() == cleanName.toLowerCase()));

            if (isMatch) {
              final targetRevKey = (vm['reviewIdOrKey'] ?? '').toString();
              final voter = (vm['userIdentifier'] ?? vlog['user_email'] ?? vlog['user_id'] ?? '').toString().trim();
              final bool isLiked = vm['isLiked'] == true;

              if (targetRevKey.isNotEmpty && voter.isNotEmpty) {
                for (final r in mergedMap.values) {
                  final id = r['id'] ?? '';
                  final key = '${r['userName']}-${r['date']}-${r['comment']?.hashCode}';
                  if (id == targetRevKey || targetRevKey.contains(id) || key == targetRevKey) {
                    List<String> list = [];
                    try {
                      final raw = r['likedUserIds'] ?? '[]';
                      if (raw.startsWith('[')) {
                        list = List<String>.from(jsonDecode(raw) as List);
                      }
                    } catch (_) {}

                    final cleanVoter = voter.toLowerCase();
                    if (isLiked) {
                      if (!list.map((e) => e.toLowerCase()).contains(cleanVoter)) {
                        list.add(voter);
                      }
                    } else {
                      list.removeWhere((e) => e.toLowerCase() == cleanVoter);
                    }
                    r['likedUserIds'] = jsonEncode(list);
                    r['helpfulCount'] = '${list.length}';
                    break;
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    final List<Map<String, String>> finalReviews = mergedMap.values.toList();

    // Cache merged result in memory
    _reviewMemoryCache[restaurantId] = finalReviews;
    _reviewMemoryCache[validRestUuid] = finalReviews;
    if (cleanName != null && cleanName.isNotEmpty) {
      _reviewMemoryCache[cleanName.toLowerCase()] = finalReviews;
    }

    // Persist merged cache locally
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(finalReviews);
      await prefs.setString('restaurant_reviews_$restaurantId', encoded);
      await prefs.setString('restaurant_reviews_$validRestUuid', encoded);
      if (cleanName != null && cleanName.isNotEmpty) {
        await prefs.setString('restaurant_reviews_${cleanName.toLowerCase()}', encoded);
      }
    } catch (_) {}

    return finalReviews;
  }

  /// Automatically propagate updated user profile name and avatar across all reviews in memory, Supabase and local cache
  static Future<void> propagateUserProfileUpdateToReviews({
    required String? userId,
    required String? userEmail,
    required String newName,
    String? newAvatar,
    String? oldName,
  }) async {
    if (newName.trim().isEmpty) return;
    final cleanNewName = newName.trim();
    final cleanUserId = userId?.trim();
    final cleanEmail = userEmail?.trim().toLowerCase();
    final cleanOldName = oldName?.trim().toLowerCase();

    bool isReviewAuthor(Map<String, String> r) {
      final rUserId = (r['userId'] ?? '').trim();
      final rUserEmail = (r['userEmail'] ?? '').trim().toLowerCase();
      final rUserName = (r['userName'] ?? '').trim().toLowerCase();

      if (cleanUserId != null && cleanUserId.isNotEmpty && rUserId == cleanUserId) return true;
      if (cleanEmail != null && cleanEmail.isNotEmpty && rUserEmail == cleanEmail) return true;
      if (cleanOldName != null && cleanOldName.isNotEmpty && rUserName == cleanOldName) return true;
      if ((cleanNewName.toLowerCase() == 'ahmeng' || cleanNewName.toLowerCase() == 'ahmad') &&
          (rUserName == 'ahmad' || rUserName == 'ahmeng')) {
        return true;
      }
      return false;
    }

    // 1. Update in-memory review cache
    final List<String> affectedKeys = [];
    _reviewMemoryCache.forEach((key, reviewList) {
      bool changed = false;
      for (int i = 0; i < reviewList.length; i++) {
        if (isReviewAuthor(reviewList[i])) {
          reviewList[i]['userName'] = cleanNewName;
          if (newAvatar != null && newAvatar.isNotEmpty) {
            reviewList[i]['userAvatar'] = newAvatar;
          }
          if (cleanUserId != null && cleanUserId.isNotEmpty) {
            reviewList[i]['userId'] = cleanUserId;
          }
          if (cleanEmail != null && cleanEmail.isNotEmpty) {
            reviewList[i]['userEmail'] = cleanEmail;
          }
          changed = true;
        }
      }
      if (changed) {
        affectedKeys.add(key);
      }
    });

    // 2. Persist updated reviews to SharedPreferences and Supabase for all affected restaurants
    for (final key in affectedKeys) {
      final reviews = _reviewMemoryCache[key];
      if (reviews != null && reviews.isNotEmpty) {
        try {
          await saveReviewsToSupabase(key, reviews);
        } catch (_) {}
      }
    }

    // 3. Update Supabase 'audit_logs' table
    try {
      final supabase = SupabaseService.client;
      final logs = await supabase
          .from('audit_logs')
          .select()
          .eq('action_type', 'CUSTOMER_REVIEW');

      for (final log in logs) {
        final logUserId = (log['user_id'] ?? '').toString().trim();
        final logUserEmail = (log['user_email'] ?? '').toString().trim().toLowerCase();
        final desc = (log['description'] ?? '').toString();

        bool match = false;
        if (cleanUserId != null && cleanUserId.isNotEmpty && (logUserId == cleanUserId || logUserId == UuidHelper.toDeterministicUuid(cleanUserId))) {
          match = true;
        }
        if (cleanEmail != null && cleanEmail.isNotEmpty && logUserEmail == cleanEmail) {
          match = true;
        }

        if (desc.startsWith('{') && desc.endsWith('}')) {
          try {
            final m = Map<String, dynamic>.from(jsonDecode(desc) as Map);
            final mName = (m['userName'] ?? '').toString().toLowerCase().trim();
            if (cleanOldName != null && cleanOldName.isNotEmpty && mName == cleanOldName) {
              match = true;
            }
            if ((cleanNewName.toLowerCase() == 'ahmeng' || cleanNewName.toLowerCase() == 'ahmad') &&
                (mName == 'ahmad' || mName == 'ahmeng')) {
              match = true;
            }

            if (match) {
              m['userName'] = cleanNewName;
              if (newAvatar != null && newAvatar.isNotEmpty) {
                m['userAvatar'] = newAvatar;
              }
              await supabase.from('audit_logs').update({
                'description': jsonEncode(m),
              }).eq('id', log['id']);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Save reviews and owner replies to Supabase database tables and local caches
  static Future<void> saveReviewsToSupabase(
    String restaurantId,
    List<Map<String, String>> reviews, {
    String? restaurantName,
  }) async {
    final cleanName = restaurantName?.trim();
    final validRestUuid = UuidHelper.toDeterministicUuid(restaurantId);

    _reviewMemoryCache[restaurantId] = reviews;
    _reviewMemoryCache[validRestUuid] = reviews;
    if (cleanName != null && cleanName.isNotEmpty) {
      _reviewMemoryCache[cleanName.toLowerCase()] = reviews;
    }

    // 1. Save locally to disk SharedPreferences under all ID and Name keys
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(reviews);
      await prefs.setString('restaurant_reviews_$restaurantId', encoded);
      await prefs.setString('restaurant_reviews_$validRestUuid', encoded);
      if (cleanName != null && cleanName.isNotEmpty) {
        await prefs.setString('restaurant_reviews_${cleanName.toLowerCase()}', encoded);
      }
    } catch (_) {}

    // 2. Calculate average rating
    double sum = 0;
    for (var r in reviews) {
      sum += (double.tryParse(r['stars'] ?? '0') ?? 0);
    }
    final avgRating = reviews.isNotEmpty ? (sum / reviews.length) : 0.0;

    // 3. Persist to Supabase 'restaurants' table (reviews_json, rating, total_reviews)
    try {
      final supabase = SupabaseService.client;
      final payload = {
        'reviews_json': jsonEncode(reviews),
        'rating': avgRating,
        'total_reviews': reviews.length,
      };

      try {
        await supabase.from('restaurants').update(payload).eq('id', validRestUuid);
      } catch (_) {}

      try {
        await supabase.from('restaurants').update(payload).eq('id', restaurantId);
      } catch (_) {}

      if (cleanName != null && cleanName.isNotEmpty) {
        try {
          await supabase.from('restaurants').update(payload).ilike('name', cleanName);
        } catch (_) {}
      }

      // 4. Persist to Supabase 'audit_logs' table (for cross-device real-time sync)
      for (final r in reviews) {
        try {
          final rUserId = r['userId']?.trim() ?? '';
          final validUserUuid = UuidHelper.toDeterministicUuid(rUserId.isNotEmpty ? rUserId : (r['userEmail'] ?? 'customer'));
          final revId = r['id'] ?? 'rev_${DateTime.now().millisecondsSinceEpoch}';
          final logId = UuidHelper.toDeterministicUuid('rev_log_${restaurantId}_$revId');

          await supabase.from('audit_logs').upsert({
            'id': logId,
            'user_id': validUserUuid,
            'user_email': (r['userEmail']?.isNotEmpty == true) ? r['userEmail']! : 'customer@hygienetruth.com',
            'action_type': 'CUSTOMER_REVIEW',
            'category': 'RESTAURANT_REVIEW',
            'title': cleanName ?? restaurantId,
            'description': jsonEncode({
              'id': revId,
              'restaurantId': restaurantId,
              'restaurantName': cleanName ?? restaurantId,
              'userName': r['userName'] ?? 'Customer',
              'userId': validUserUuid,
              'userEmail': r['userEmail'] ?? '',
              'userAvatar': r['userAvatar'] ?? '',
              'stars': r['stars'] ?? '5',
              'comment': r['comment'] ?? '',
              'ownerReply': r['ownerReply'] ?? '',
              'date': r['date'] ?? '',
              'timestamp': r['timestamp'] ?? DateTime.now().toUtc().toIso8601String(),
              'likedUserIds': r['likedUserIds'] ?? '[]',
              'helpfulCount': r['helpfulCount'] ?? '0',
            }),
            'created_at': r['timestamp'] ?? DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Toggle Helpful vote for a review with cross-device Supabase sync and 1-vote-per-account enforcement
  static Future<Map<String, dynamic>> toggleReviewHelpfulVote({
    required String restaurantId,
    required String reviewIdOrKey,
    required String userIdentifier,
    String? restaurantName,
    bool? setLiked,
  }) async {
    final cleanName = restaurantName?.trim();
    final reviews = await fetchReviews(restaurantId, restaurantName: cleanName);

    bool isLikedNow = false;
    int updatedCount = 0;
    final cleanUser = userIdentifier.trim().toLowerCase();
    final customerEmail = (CustomerStoreService.currentCustomer?.email ?? '').trim().toLowerCase();

    for (int i = 0; i < reviews.length; i++) {
      final r = Map<String, String>.from(reviews[i]);
      final id = (r['id'] ?? '').trim();
      final key = '${r['userName']}-${r['date']}-${r['comment']?.hashCode}-$i';
      final altKey = '${r['userName']}-${r['date']}-${r['comment']?.hashCode}';

      if (id == reviewIdOrKey || key == reviewIdOrKey || altKey == reviewIdOrKey || (id.isNotEmpty && reviewIdOrKey.contains(id))) {
        final rawLikedStr = r['likedUserIds'] ?? '[]';
        List<String> likedList = [];
        try {
          if (rawLikedStr.startsWith('[')) {
            likedList = List<String>.from(jsonDecode(rawLikedStr) as List);
          } else if (rawLikedStr.isNotEmpty) {
            likedList = rawLikedStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        } catch (_) {}

        final bool alreadyLiked = likedList.map((e) => e.toLowerCase()).contains(cleanUser) ||
            (customerEmail.isNotEmpty && likedList.map((e) => e.toLowerCase()).contains(customerEmail));

        final bool shouldBeLiked = setLiked ?? (!alreadyLiked);

        if (shouldBeLiked) {
          if (!alreadyLiked) {
            likedList.add(userIdentifier.trim());
          }
          isLikedNow = true;
        } else {
          likedList.removeWhere((e) => e.toLowerCase() == cleanUser || (customerEmail.isNotEmpty && e.toLowerCase() == customerEmail));
          isLikedNow = false;
        }

        updatedCount = likedList.length;
        r['likedUserIds'] = jsonEncode(likedList);
        r['helpfulCount'] = '$updatedCount';
        reviews[i] = r;
        break;
      }
    }

    // 1. Persist updated reviews list with likedUserIds to Supabase and cache
    await saveReviewsToSupabase(restaurantId, reviews, restaurantName: cleanName);

    // 2. Insert vote transaction log in Supabase 'audit_logs' (for real-time Postgres broadcast & cross-device sync)
    try {
      final supabase = SupabaseService.client;
      final validUserId = userIdentifier.length > 10
          ? userIdentifier
          : (CustomerStoreService.currentCustomer?.id.isNotEmpty == true
              ? CustomerStoreService.currentCustomer!.id
              : UuidHelper.deterministic(userIdentifier));
      final validEmail = userIdentifier.contains('@')
          ? userIdentifier
          : (CustomerStoreService.currentCustomer?.email.isNotEmpty == true
              ? CustomerStoreService.currentCustomer!.email
              : 'customer@hygienetruth.com');

      final logId = UuidHelper.toDeterministicUuid('vote_${restaurantId}_${reviewIdOrKey}_$cleanUser');
      await supabase.from('audit_logs').upsert({
        'id': logId,
        'user_id': UuidHelper.toDeterministicUuid(validUserId),
        'user_email': validEmail,
        'action_type': 'REVIEW_HELPFUL_VOTE',
        'category': 'RESTAURANT_REVIEW',
        'title': cleanName ?? restaurantId,
        'description': jsonEncode({
          'restaurantId': restaurantId,
          'restaurantName': cleanName ?? restaurantId,
          'reviewIdOrKey': reviewIdOrKey,
          'userIdentifier': userIdentifier,
          'isLiked': isLikedNow,
          'helpfulCount': updatedCount,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}

    return {
      'isLiked': isLikedNow,
      'helpfulCount': updatedCount,
      'reviews': reviews,
    };
  }

  /// Preload reviews for multiple restaurants using models (ID & Name)
  static Future<void> preloadRestaurants(List<RestaurantModel> restaurants) async {
    for (final r in restaurants) {
      await fetchReviews(r.id, restaurantName: r.name);
    }
  }

  /// Preload reviews for multiple restaurant IDs
  static Future<void> preloadReviews(List<String> restaurantIds) async {
    for (final id in restaurantIds) {
      final matched = restaurantsNotifier.value.where((r) => r.id == id).firstOrNull;
      await fetchReviews(id, restaurantName: matched?.name);
    }
  }

  /// Add a review and save to Supabase + SharedPreferences + update memory cache
  static Future<void> addReview({
    required String restaurantId,
    required String userName,
    required int stars,
    required String comment,
    String? restaurantName,
    String? userId,
    String? userEmail,
    String? userAvatar,
    String? timestamp,
  }) async {
    final currentReviews = await fetchReviews(restaurantId, restaurantName: restaurantName);
    final now = DateTime.now();
    final newReview = {
      'id': 'rev_${now.millisecondsSinceEpoch}',
      'userName': userName,
      'userId': userId ?? '',
      'userEmail': userEmail ?? '',
      'userAvatar': userAvatar ?? '',
      'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'timestamp': timestamp ?? now.toUtc().toIso8601String(),
      'stars': '$stars',
      'comment': comment,
    };
    currentReviews.insert(0, newReview);
    await saveReviewsToSupabase(restaurantId, currentReviews, restaurantName: restaurantName);

    // Recompute restaurant dynamic risk from customer reviews & ratings
    final rIdx = restaurantsNotifier.value.indexWhere((r) => r.id == restaurantId || (restaurantName != null && r.name.toLowerCase() == restaurantName.toLowerCase()));
    if (rIdx != -1) {
      final currentR = restaurantsNotifier.value[rIdx];
      final eval = calculateDynamicRisk(currentR, reviews: currentReviews);
      final updatedR = currentR.copyWith(
        hygieneRiskScore: eval.score,
        riskCategory: eval.category,
      );
      final updatedList = List<RestaurantModel>.from(restaurantsNotifier.value);
      updatedList[rIdx] = updatedR;
      restaurantsNotifier.value = updatedList;

      // Update Supabase
      try {
        await SupabaseService.client.from('restaurants').update({
          'hygiene_risk_score': eval.score,
          'risk_category': eval.category.name,
        }).eq('id', restaurantId);
      } catch (_) {}
    }

    // Also record into user activity history
    await logUserReviewActivity(
      restaurantId: restaurantId,
      restaurantName: restaurantName ?? restaurantId,
      stars: stars,
      comment: comment,
      timestamp: newReview['timestamp'],
    );

    // Send real-time heads-up push notification to Restaurant Owner & Reviewer
    final cleanRestName = resolveRestaurantName(restaurantName != null && restaurantName.isNotEmpty && !isRawUuid(restaurantName) ? restaurantName : restaurantId);
    NotificationService.sendNotification(
      userId: 'own_001',
      title: '⭐ New Customer Review: $cleanRestName',
      message: '$userName left a $stars★ review: "$comment"',
      type: NotificationType.review,
      actionUrl: 'outlet_$restaurantId',
    );
  }

  /// Log a user review activity
  static Future<void> logUserReviewActivity({
    required String restaurantId,
    required String restaurantName,
    required int stars,
    required String comment,
    String? timestamp,
  }) async {
    final cleanName = resolveRestaurantName(restaurantName.isNotEmpty && !isRawUuid(restaurantName) ? restaurantName : restaurantId);
    final currentUser = CustomerStoreService.currentCustomer;
    final userKey = (currentUser?.id != null && currentUser!.id.isNotEmpty)
        ? currentUser.id
        : (currentUser?.email ?? 'anonymous_user');

    final now = DateTime.now();
    final record = {
      'id': 'act_rev_${now.millisecondsSinceEpoch}',
      'restaurantId': restaurantId,
      'restaurantName': cleanName,
      'stars': '$stars',
      'comment': comment,
      'timestamp': timestamp ?? now.toIso8601String(),
      'category': 'Restaurant Review',
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString('user_review_activities_$userKey');
      List<dynamic> list = [];
      if (existingJson != null && existingJson.isNotEmpty) {
        list = jsonDecode(existingJson);
      }
      list.removeWhere((item) => item['restaurantId'] == restaurantId);
      list.insert(0, record);
      await prefs.setString('user_review_activities_$userKey', jsonEncode(list));

      final globalJson = prefs.getString('global_review_activities');
      List<dynamic> gList = [];
      if (globalJson != null && globalJson.isNotEmpty) {
        gList = jsonDecode(globalJson);
      }
      gList.removeWhere((item) => item['restaurantId'] == restaurantId && item['comment'] == comment);
      gList.insert(0, record);
      await prefs.setString('global_review_activities', jsonEncode(gList));
    } catch (_) {}
  }

  /// Fetch all review activities for the active user
  static Future<List<Map<String, dynamic>>> fetchUserReviewActivities() async {
    final List<Map<String, dynamic>> results = [];
    final Set<String> seenReviews = {};

    final currentUser = CustomerStoreService.currentCustomer;
    final userKey = (currentUser?.id != null && currentUser!.id.isNotEmpty)
        ? currentUser.id
        : (currentUser?.email ?? 'anonymous_user');

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Check user-specific review activity log
      final userJson = prefs.getString('user_review_activities_$userKey');
      if (userJson != null && userJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(userJson);
        for (final item in decoded) {
          final map = Map<String, dynamic>.from(item as Map);
          final rName = map['restaurantName']?.toString() ?? '';
          if (isLegacyMockName(rName)) continue;
          final key = '${rName}_${map['comment']}';
          if (!seenReviews.contains(key)) {
            seenReviews.add(key);
            results.add(map);
          }
        }
      }

      // 2. Check global review activities
      final globalJson = prefs.getString('global_review_activities');
      if (globalJson != null && globalJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(globalJson);
        for (final item in decoded) {
          final map = Map<String, dynamic>.from(item as Map);
          final rName = map['restaurantName']?.toString() ?? '';
          if (isLegacyMockName(rName)) continue;
          final key = '${rName}_${map['comment']}';
          if (!seenReviews.contains(key)) {
            seenReviews.add(key);
            results.add(map);
          }
        }
      }

      // 3. Scan all restaurant_reviews_* in SharedPreferences
      final allKeys = prefs.getKeys().where((k) => k.startsWith('restaurant_reviews_'));
      for (final key in allKeys) {
        final restId = key.replaceFirst('restaurant_reviews_', '');
        final jsonStr = prefs.getString(key);
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(jsonStr);
          for (final r in decoded) {
            final rMap = Map<String, dynamic>.from(r as Map);
            final uid = rMap['userId']?.toString() ?? '';
            final uemail = rMap['userEmail']?.toString() ?? '';
            final uname = rMap['userName']?.toString() ?? '';

            final isMatch = (currentUser != null && (
              (uid.isNotEmpty && uid == currentUser.id) ||
              (uemail.isNotEmpty && uemail == currentUser.email) ||
              (uname.isNotEmpty && uname == currentUser.name)
            ));

            if (isMatch) {
              String restName = resolveRestaurantName(rMap['restaurantName'] ?? restId);
              if (isLegacyMockName(restName)) continue;

              final revKey = '${restName}_${rMap['comment']}';
              if (!seenReviews.contains(revKey)) {
                seenReviews.add(revKey);
                results.add({
                  'id': rMap['id'] ?? 'act_rev_${DateTime.now().millisecondsSinceEpoch}',
                  'restaurantId': restId,
                  'restaurantName': restName,
                  'stars': rMap['stars'] ?? '5',
                  'comment': rMap['comment'] ?? '',
                  'timestamp': rMap['timestamp'] ?? rMap['date'] ?? 'Recently',
                  'category': 'Restaurant Review',
                });
              }
            }
          }
        }
      }
    } catch (_) {}

    return results;
  }

  /// Record a recent restaurant visit
  static Future<void> recordRecentVisit(RestaurantModel restaurant) async {
    final currentUser = CustomerStoreService.currentCustomer;
    final userKey = (currentUser?.id != null && currentUser!.id.isNotEmpty)
        ? currentUser.id
        : (currentUser?.email ?? 'anonymous_user');

    final cleanName = resolveRestaurantName(restaurant.name.isNotEmpty && !isRawUuid(restaurant.name) ? restaurant.name : restaurant.id);
    restaurantNameCache[restaurant.id] = cleanName;

    final now = DateTime.now();
    final visitRecord = {
      'id': restaurant.id,
      'name': cleanName,
      'category': restaurant.category,
      'address': restaurant.address,
      'hygieneRiskScore': restaurant.hygieneRiskScore,
      'riskCategory': restaurant.riskCategory.name,
      'violationCount': restaurant.violationCount,
      'timestamp': now.toIso8601String(),
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString('user_recent_visits_$userKey');
      List<dynamic> list = [];
      if (existingJson != null && existingJson.isNotEmpty) {
        list = jsonDecode(existingJson);
      }
      list.removeWhere((item) => item['id'] == restaurant.id || item['name'] == restaurant.name);
      list.insert(0, visitRecord);
      if (list.length > 25) list = list.sublist(0, 25);
      await prefs.setString('user_recent_visits_$userKey', jsonEncode(list));

      final globalJson = prefs.getString('global_recent_visits');
      List<dynamic> gList = [];
      if (globalJson != null && globalJson.isNotEmpty) {
        gList = jsonDecode(globalJson);
      }
      gList.removeWhere((item) => item['id'] == restaurant.id || item['name'] == restaurant.name);
      gList.insert(0, visitRecord);
      if (gList.length > 25) gList = gList.sublist(0, 25);
      await prefs.setString('global_recent_visits', jsonEncode(gList));
    } catch (_) {}
  }

  /// Fetch all recent visits for active user
  static Future<List<Map<String, dynamic>>> fetchRecentVisits() async {
    final List<Map<String, dynamic>> results = [];
    final Set<String> seen = {};

    final currentUser = CustomerStoreService.currentCustomer;
    final userKey = (currentUser?.id != null && currentUser!.id.isNotEmpty)
        ? currentUser.id
        : (currentUser?.email ?? 'anonymous_user');

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. User-specific visits
      final userJson = prefs.getString('user_recent_visits_$userKey');
      if (userJson != null && userJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(userJson);
        for (final item in decoded) {
          final map = Map<String, dynamic>.from(item as Map);
          final vName = map['name']?.toString() ?? map['id']?.toString() ?? '';
          if (isLegacyMockName(vName)) continue;
          final key = vName;
          if (key.isNotEmpty && !seen.contains(key)) {
            seen.add(key);
            results.add(map);
          }
        }
      }

      // 2. Global visits fallback
      final globalJson = prefs.getString('global_recent_visits');
      if (globalJson != null && globalJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(globalJson);
        for (final item in decoded) {
          final map = Map<String, dynamic>.from(item as Map);
          final vName = map['name']?.toString() ?? map['id']?.toString() ?? '';
          if (isLegacyMockName(vName)) continue;
          final key = vName;
          if (key.isNotEmpty && !seen.contains(key)) {
            seen.add(key);
            results.add(map);
          }
        }
      }

      // 3. Also include restaurants where user has submitted reviews
      final reviewActivities = await fetchUserReviewActivities();
      for (final rev in reviewActivities) {
        final rId = rev['restaurantId']?.toString() ?? '';
        final rawName = rev['restaurantName']?.toString() ?? '';
        final rName = resolveRestaurantName(rawName.isNotEmpty && !isRawUuid(rawName) ? rawName : rId);
        if (isLegacyMockName(rName)) continue;
        if (rName.isNotEmpty && !seen.contains(rName)) {
          seen.add(rName);
          results.add({
            'id': rId,
            'name': rName,
            'category': 'Restaurant',
            'address': 'Verified Premises Location',
            'hygieneRiskScore': 10.0,
            'riskCategory': 'safe',
            'violationCount': 0,
            'timestamp': rev['timestamp'] ?? DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {}

    return results;
  }
}

class BookmarkService {
  /// Reactive notifier for UI components
  static final ValueNotifier<Set<String>> bookmarkedIdsNotifier = ValueNotifier<Set<String>>({});

  /// Tier 1: In-Memory Fast Cache (Instant O(1) reads with zero network latency)
  static Set<String> _memoryCache = {};
  static bool _isLoadedFromDisk = false;
  static DateTime? _lastCloudFetchTime;
  static Timer? _debounceSyncTimer;
  static bool _isCloudSyncing = false;
  static bool _hasPendingCloudSync = false;

  /// Cache TTL: 5 minutes before background re-validating from cloud
  static const Duration _cloudCacheTtl = Duration(minutes: 5);

  static String _getCurrentUserId() {
    return CustomerStoreService.currentCustomer?.id ??
        SupabaseService.client.auth.currentUser?.id ??
        'guest_default';
  }

  static String? _getCurrentUserEmail() {
    return CustomerStoreService.currentCustomer?.email ??
        SupabaseService.client.auth.currentUser?.email;
  }

  static bool _isValidUuid(String str) {
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(str);
  }

  /// Initialize: instantly load from local disk cache first, then validate with cloud in background
  static Future<void> init() async {
    if (!_isLoadedFromDisk) {
      await _loadFromLocalDisk();
    }
    _maybeSyncFromCloudInBackground();
  }

  /// Tier 2: Instant Local Disk Cache Retrieval (0 network requests)
  static Future<Set<String>> _loadFromLocalDisk() async {
    final userId = _getCurrentUserId();
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> cached = prefs.getStringList('bookmarks_$userId') ?? [];
      if (cached.isEmpty && userId != 'guest_default') {
        cached = prefs.getStringList('bookmarks_guest_default') ?? prefs.getStringList('bookmarks_global') ?? [];
      }
      _memoryCache = Set<String>.from(cached);
      bookmarkedIdsNotifier.value = Set.from(_memoryCache);
      _isLoadedFromDisk = true;
    } catch (e) {
      debugPrint('BookmarkService: Error reading local cache: $e');
    }
    return _memoryCache;
  }

  /// Public loader: checks memory/disk cache first, only hits network if TTL expired or forced
  static Future<Set<String>> loadBookmarks({bool forceRefresh = false}) async {
    if (!_isLoadedFromDisk) {
      await _loadFromLocalDisk();
    }

    final now = DateTime.now();
    final bool isExpired = _lastCloudFetchTime == null ||
        now.difference(_lastCloudFetchTime!) > _cloudCacheTtl;

    if (forceRefresh || isExpired) {
      await _fetchFromSupabaseCloud();
    }

    return _memoryCache;
  }

  /// Background Cloud Fetch (Guarded & Rate-Limited)
  static Future<void> _maybeSyncFromCloudInBackground() async {
    final now = DateTime.now();
    if (_lastCloudFetchTime != null &&
        now.difference(_lastCloudFetchTime!) < _cloudCacheTtl) {
      // Cache is fresh, skip redundant network request
      return;
    }
    _fetchFromSupabaseCloud();
  }

  static Future<void> _fetchFromSupabaseCloud() async {
    if (_isCloudSyncing) return;
    _isCloudSyncing = true;

    final userId = _getCurrentUserId();
    final email = _getCurrentUserEmail();

    try {
      final supabase = SupabaseService.client;
      Map<String, dynamic>? userRow;

      if (_isValidUuid(userId)) {
        userRow = await supabase.from('users').select('settings').eq('id', userId).maybeSingle();
      }
      if (userRow == null && email != null && email.isNotEmpty) {
        userRow = await supabase.from('users').select('settings').eq('email', email).maybeSingle();
      }

      if (userRow != null && userRow['settings'] is Map) {
        final settings = userRow['settings'] as Map<String, dynamic>;
        if (settings['bookmarks'] is List) {
          final List<dynamic> remoteBookmarks = settings['bookmarks'];
          final remoteSet = remoteBookmarks.map((e) => e.toString()).toSet();

          // Merge local cache and cloud
          _memoryCache.addAll(remoteSet);
          bookmarkedIdsNotifier.value = Set.from(_memoryCache);

          // Save to local device storage
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('bookmarks_$userId', _memoryCache.toList());
          await prefs.setStringList('bookmarks_global', _memoryCache.toList());
        }
      }
      _lastCloudFetchTime = DateTime.now();
    } catch (e) {
      debugPrint('BookmarkService: Cloud fetch skipped/offline: $e');
    } finally {
      _isCloudSyncing = false;
    }
  }

  /// Instant O(1) in-memory check (0 ms latency, no disk or network hit)
  static bool isBookmarked(String restaurantId) {
    return _memoryCache.contains(restaurantId);
  }

  /// Toggle bookmark: Optimistic instant UI update + Local cache + Debounced cloud sync
  static Future<bool> toggleBookmark(String restaurantId) async {
    final bool willBeSaved = !_memoryCache.contains(restaurantId);

    // 1. Instant Memory Update (Tier 1)
    if (willBeSaved) {
      _memoryCache.add(restaurantId);
    } else {
      _memoryCache.remove(restaurantId);
    }
    bookmarkedIdsNotifier.value = Set.from(_memoryCache);

    // 2. Instant Local Storage Persistence (Tier 2)
    final userId = _getCurrentUserId();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList('bookmarks_$userId', _memoryCache.toList());
      prefs.setStringList('bookmarks_global', _memoryCache.toList());
    }).catchError((e) {
      debugPrint('BookmarkService: Error persisting to disk: $e');
    });

    // 3. Smart Debounced Cloud Sync (Tier 3 - Collapses multiple taps into 1 request)
    _scheduleDebouncedCloudSync();

    return willBeSaved;
  }

  /// Debouncer: waits 500ms before sending cloud request, preventing excessive Supabase calls
  static void _scheduleDebouncedCloudSync() {
    _hasPendingCloudSync = true;
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = Timer(const Duration(milliseconds: 500), () {
      _executePendingCloudSync();
    });
  }

  static Future<void> _executePendingCloudSync() async {
    if (!_hasPendingCloudSync) return;
    _hasPendingCloudSync = false;

    final userId = _getCurrentUserId();
    final email = _getCurrentUserEmail();
    final currentList = _memoryCache.toList();

    try {
      final supabase = SupabaseService.client;
      Map<String, dynamic>? userRow;
      String? matchedId;

      if (_isValidUuid(userId)) {
        userRow = await supabase.from('users').select('id, settings').eq('id', userId).maybeSingle();
        matchedId = userId;
      }
      if (userRow == null && email != null && email.isNotEmpty) {
        userRow = await supabase.from('users').select('id, settings').eq('email', email).maybeSingle();
        if (userRow != null) {
          matchedId = userRow['id']?.toString();
        }
      }

      Map<String, dynamic> settings = {};
      if (userRow != null && userRow['settings'] is Map) {
        settings = Map<String, dynamic>.from(userRow['settings'] as Map);
      }
      settings['bookmarks'] = currentList;

      if (matchedId != null && _isValidUuid(matchedId)) {
        await supabase.from('users').update({'settings': settings}).eq('id', matchedId);
      } else if (email != null && email.isNotEmpty) {
        await supabase.from('users').update({'settings': settings}).eq('email', email);
      }
      _lastCloudFetchTime = DateTime.now();
      debugPrint('BookmarkService: Cloud sync completed (${currentList.length} bookmarks)');
    } catch (e) {
      debugPrint('BookmarkService: Cloud sync failed/offline: $e');
    }
  }

  /// Retrieve full restaurant models with caching
  static Future<List<RestaurantModel>> getBookmarkedRestaurants({bool forceRefresh = false}) async {
    await init();
    if (forceRefresh) {
      await loadBookmarks(forceRefresh: true);
    }
    final ids = _memoryCache;
    if (ids.isEmpty) return [];

    final all = await RestaurantStoreService.fetchAllRestaurants(forceRefresh: forceRefresh);
    final inMemory = RestaurantStoreService.restaurantsNotifier.value;
    final Set<String> seen = {};
    final List<RestaurantModel> result = [];

    for (final r in all) {
      if (ids.contains(r.id) && !seen.contains(r.id)) {
        seen.add(r.id);
        result.add(r);
      }
    }
    for (final r in inMemory) {
      if (ids.contains(r.id) && !seen.contains(r.id)) {
        seen.add(r.id);
        result.add(r);
      }
    }
    return result;
  }
}

class ComplaintStoreService {
  static final ValueNotifier<List<ComplaintModel>> complaintsNotifier = ValueNotifier<List<ComplaintModel>>([]);
  static bool _hasLoadedFromSupabase = false;

  static bool _isValidUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    final regex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return regex.hasMatch(str);
  }

  /// Fetch all complaints from Supabase + local cache
  static Future<List<ComplaintModel>> fetchAllComplaints({bool forceRefresh = false}) async {
    if (_hasLoadedFromSupabase && !forceRefresh && complaintsNotifier.value.isNotEmpty) {
      return complaintsNotifier.value;
    }

    List<ComplaintModel> loadedList = [];

    // 1. Try Supabase 'complaints' table with joined relational tables
    try {
      final supabase = SupabaseService.client;
      final res = await supabase.from('complaints').select('''
        id,
        restaurant_id,
        user_id,
        category,
        description,
        status,
        severity,
        latitude,
        longitude,
        is_flagged_for_review,
        flagged_reason,
        evidence_context,
        submitted_at,
        updated_at,
        restaurants ( id, name, address ),
        users ( id, name, email ),
        complaint_issues ( id, issue_text ),
        complaint_photos ( id, photo_url )
      ''').order('submitted_at', ascending: false);

      if (res.isNotEmpty) {
        loadedList = res.map((row) => ComplaintModel.fromJson(Map<String, dynamic>.from(row))).toList();
      }
    } catch (joinErr) {
      // Fallback simple flat query
      try {
        final supabase = SupabaseService.client;
        final res = await supabase.from('complaints').select().order('submitted_at', ascending: false);
        if (res.isNotEmpty) {
          loadedList = res.map((row) => ComplaintModel.fromJson(Map<String, dynamic>.from(row))).toList();
        }
      } catch (_) {}
    }

    // 2. Merge with MockSeedData
    final Set<String> seenIds = loadedList.map((c) => c.id).toSet();
    for (final seed in complaintsNotifier.value) {
      if (!seenIds.contains(seed.id)) {
        seenIds.add(seed.id);
        loadedList.add(seed);
      }
    }

    // 3. Merge with local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString('local_custom_complaints');
      if (localJson != null && localJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(localJson);
        for (final item in decoded) {
          final comp = ComplaintModel.fromJson(Map<String, dynamic>.from(item));
          if (!seenIds.contains(comp.id)) {
            seenIds.add(comp.id);
            loadedList.insert(0, comp);
          }
        }
      }
    } catch (_) {}

    _hasLoadedFromSupabase = true;
    complaintsNotifier.value = loadedList;
    
    return loadedList;
  }

  /// Submit a complaint to Supabase (complaints, complaint_issues, complaint_photos), SharedPreferences & in-memory list
  static Future<ComplaintModel> submitComplaint({
    required String restaurantId,
    required String restaurantName,
    required String restaurantAddress,
    required String category,
    required List<String> issues,
    required String description,
    required List<String> photoUrls,
    Map<String, dynamic> evidenceContext = const {},
    double latitude = 3.1466,
    double longitude = 101.6958,
    SeverityLevel severity = SeverityLevel.medium,
  }) async {
    if (restaurantId.trim().isEmpty || restaurantName.trim().isEmpty ||
        restaurantAddress.trim().isEmpty || category.trim().isEmpty ||
        issues.isEmpty || issues.any((issue) => issue.trim().isEmpty) ||
        description.trim().isEmpty || photoUrls.isEmpty) {
      throw ArgumentError('Complete the outlet details, issues, description and photo evidence.');
    }
    final now = DateTime.now();
    final complaintUuid = UuidHelper.generateV4();
    final uploadUser = SupabaseService.client.auth.currentUser;
    if (uploadUser == null) throw StateError('Sign in before submitting evidence.');
    final uploaded = <String>[];
    for (var i = 0; i < photoUrls.length; i++) {
      final source = photoUrls[i];
      if (source.startsWith('https://') || source.startsWith('http://')) { uploaded.add(source); continue; }
      final bytes = await ImageHashHelper.readEvidenceBytes(source);
      if (bytes.isEmpty) throw StateError('The selected evidence photo is empty.');
      final path = 'complaints/${uploadUser.id}/$complaintUuid/$i';
      await SupabaseService.client.storage.from('Images').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: source.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg'));
      uploaded.add(SupabaseService.client.storage.from('Images').getPublicUrl(path));
    }
    photoUrls = uploaded;

    final customer = CustomerStoreService.currentCustomer;
    final currentAuthUser = SupabaseService.client.auth.currentUser;

    String candidateUserId = customer?.id.isNotEmpty == true
        ? customer!.id
        : (currentAuthUser?.id ?? '');
    final userName = customer?.name.isNotEmpty == true
        ? customer!.name
        : (currentAuthUser?.email?.split('@').first ?? 'Citizen Diner');
    final userEmail = customer?.email.isNotEmpty == true
        ? customer!.email
        : (currentAuthUser?.email ?? '');

    // Pre-check for duplicate/fake report
    final tempComplaint = ComplaintModel(
      id: complaintUuid,
      evidenceContext: evidenceContext,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      userId: candidateUserId.isNotEmpty ? candidateUserId : 'usr_customer',
      userName: userName,
      category: category,
      issues: issues,
      description: description,
      status: ComplaintStatus.submitted,
      severity: severity,
      latitude: latitude,
      longitude: longitude,
      submittedAt: now.toIso8601String(),
      photoUrls: photoUrls,
    );

    final checks = await AiDuplicateDetectorService.analyzeComplaintEvidence(
      complaint: tempComplaint, databaseComplaints: complaintsNotifier.value,
      databaseRestaurants: RestaurantStoreService.restaurantsNotifier.value);
    final vCheck = VerificationCheckResult(isFlagged: !checks.canApprove, isDuplicate: checks.isDuplicate,
      isFakeSuspected: !checks.gpsPassed || !checks.timingPassed,
      confidenceScore: checks.overallRiskScore, riskFactors: checks.matchedAiFeatures,
      recommendation: checks.aiVerdict, flagReason: checks.canApprove ? null : checks.matchedAiFeatures.join(' | '),
      matchedComplaintId: checks.matchedComplaintId, matchedImageUrl: checks.matchedImageUrl);

    final bool isFlagged = vCheck.isFlagged;
    final String? flaggedReason = vCheck.flagReason;
    final ComplaintStatus initialStatus = isFlagged ? ComplaintStatus.underReview : ComplaintStatus.submitted;

    var complaint = ComplaintModel(
      id: complaintUuid,
      evidenceContext: evidenceContext,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      userId: candidateUserId.isNotEmpty ? candidateUserId : 'usr_customer',
      userName: userName,
      category: category,
      issues: issues,
      description: description,
      status: initialStatus,
      severity: severity,
      latitude: latitude,
      longitude: longitude,
      submittedAt: now.toIso8601String(),
      photoUrls: photoUrls,
      isFlaggedForReview: isFlagged,
      flaggedReason: flaggedReason,
    );

    // 3. Supabase relational persistence
    try {
      final supabase = SupabaseService.client;

      // A. Resolve valid user_id UUID
      String validUserUuid = candidateUserId;
      if (!_isValidUuid(validUserUuid)) {
        if (currentAuthUser != null && _isValidUuid(currentAuthUser.id)) {
          validUserUuid = currentAuthUser.id;
        } else if (userEmail.isNotEmpty) {
          final userRow = await supabase.from('users').select('id').eq('email', userEmail).maybeSingle();
          if (userRow != null && userRow['id'] != null) {
            validUserUuid = userRow['id'].toString();
          }
        }
      }

      if (!_isValidUuid(validUserUuid)) {
        throw StateError('Sign in again before submitting a report.');
      }

      // Never attach an unregistered outlet to an unrelated restaurant.
      String validRestaurantUuid = restaurantId;
      if (!_isValidUuid(validRestaurantUuid)) {
        validRestaurantUuid = UuidHelper.generateV4();
        await supabase.from('restaurants').insert({
          'id': validRestaurantUuid, 'name': restaurantName,
          'category': category, 'address': restaurantAddress,
          'latitude': latitude, 'longitude': longitude,
          'status': 'pendingVerification',
        });
      }
      complaint = complaint.copyWith(restaurantId: validRestaurantUuid, userId: validUserUuid);

      // C. Insert into complaints table
      final payload = {
        'id': complaintUuid,
        'restaurant_id': validRestaurantUuid,
        'user_id': validUserUuid,
        'category': category,
        'description': description,
        'status': initialStatus.name,
        'severity': severity.name,
        'evidence_context': evidenceContext,
        'latitude': latitude,
        'longitude': longitude,
        'is_flagged_for_review': isFlagged,
        'flagged_reason': flaggedReason,
        'submitted_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      };

      await supabase.from('complaints').insert(payload);

      // D. Insert into complaint_issues table
      if (issues.isNotEmpty) {
        final issuesData = issues.map((iss) => {
          'id': UuidHelper.generateV4(),
          'complaint_id': complaintUuid,
          'issue_text': iss,
        }).toList();
        await supabase.from('complaint_issues').insert(issuesData);
      }

      // E. Insert into complaint_photos table with calculated image_hash
      if (photoUrls.isNotEmpty) {
        final List<Map<String, dynamic>> photosData = [];
        for (final url in photoUrls) {
          final hash = await ImageHashHelper.computeEvidenceHash(url);
          photosData.add({
            'id': UuidHelper.generateV4(),
            'complaint_id': complaintUuid,
            'photo_url': url,
            'image_hash': hash,
            'uploaded_at': now.toUtc().toIso8601String(),
          });
        }
        await supabase.from('complaint_photos').insert(photosData);
      }

      // F. Log action into user_audit_logs table
      try {
        await supabase.from('user_audit_logs').insert({
          'id': UuidHelper.generateV4(),
          'user_id': validUserUuid,
          'user_email': userEmail,
          'action_type': 'SUBMIT_COMPLAINT',
          'category': 'Hygiene Report',
          'title': 'Reported $restaurantName',
          'description': 'Category: $category, Issues: ${issues.join(', ')}',
          'created_at': now.toUtc().toIso8601String(),
        });
      } catch (_) {}
    } catch (e) {
      debugPrint('Supabase complaint submission failed: $e');
      rethrow;
    }

    // 1. Instant local reactivity
    final updatedList = List<ComplaintModel>.from(complaintsNotifier.value);
    updatedList.insert(0, complaint);
    complaintsNotifier.value = updatedList;
    

    // 2. Local disk cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString('local_custom_complaints');
      List<dynamic> existingList = [];
      if (localJson != null && localJson.isNotEmpty) {
        existingList = jsonDecode(localJson);
      }
      existingList.insert(0, complaint.toJson());
      await prefs.setString('local_custom_complaints', jsonEncode(existingList));
    } catch (_) {}

    // 4. Automated duplication workflow: scan record, admin alert, auto-merge
    if (isFlagged) {
      await AiDuplicateDetectorService.saveScanRecord(complaintUuid, vCheck);

      final String cmpShort = complaintUuid.length > 8
          ? complaintUuid.substring(0, 8).toUpperCase()
          : complaintUuid.toUpperCase();
      final String confText = vCheck.confidenceScore.toStringAsFixed(1);
      final String reasonText =
          vCheck.flagReason ?? 'Automated integrity verification failed';

      // A. Accountability trail
      try {
        await AuditLogService.logAction(
          actionType: 'AUTO_FLAGGED_DUPLICATE',
          category: 'Complaint',
          title: 'AI Auto-Flag: #$cmpShort',
          description: '$reasonText | Confidence: $confText%',
        );
      } catch (_) {}

      // B. Real-time alert to administrators
      try {
        await NotificationService.sendNotification(
          userId: 'adm_001',
          title: 'AI Duplicate Flag: $restaurantName',
          message: '$reasonText Confidence $confText%.',
          type: NotificationType.complaint,
          actionUrl: complaintUuid,
        );
      } catch (_) {}

      // C. Record duplicate scan recommendation for Admin review in DuplicateFakeReviewScreen
      if (vCheck.isAutoMergeCandidate && vCheck.matchedComplaintId != null) {
        debugPrint('Duplicate candidate #$cmpShort identified for master ${vCheck.matchedComplaintId} ($confText% confidence) - queued for Admin review.');
      }
    }

    // Initialize workflow after complaint submission
    await WorkflowService.initializeWorkflow(complaintUuid);

    return complaint;
  }

  /// Update status in Supabase & memory
  static Future<void> updateComplaintStatus(String complaintId, ComplaintStatus newStatus) async {
    final updated = complaintsNotifier.value.map((c) {
      if (c.id == complaintId) {
        return ComplaintModel(
          id: c.id,
          restaurantId: c.restaurantId,
          restaurantName: c.restaurantName,
          userId: c.userId,
          userName: c.userName,
          category: c.category,
          issues: c.issues,
          description: c.description,
          status: newStatus,
          severity: c.severity,
          latitude: c.latitude,
          longitude: c.longitude,
          isFlaggedForReview: c.isFlaggedForReview,
          flaggedReason: c.flaggedReason,
          submittedAt: c.submittedAt,
          evidenceContext: c.evidenceContext,
          photoUrls: c.photoUrls,
        );
      }
      return c;
    }).toList();

    complaintsNotifier.value = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('complaint_status_override_$complaintId', newStatus.name);
      await prefs.setString(
        'local_custom_complaints',
        jsonEncode(updated.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}

    try {
      final supabase = SupabaseService.client;
      await supabase.from('complaints').update({
        'status': newStatus.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', complaintId);

      final validCompUuid = UuidHelper.toDeterministicUuid(complaintId);
      if (validCompUuid != complaintId) {
        await supabase.from('complaints').update({
          'status': newStatus.name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', validCompUuid);
      }
    } catch (_) {}
  }

  /// Retroactive AI re-scan: recomputes duplication flags for every open
  /// complaint against the current dataset and persists the outcome.
  static Future<Map<String, int>> applyRetroactiveDuplicateScan() async {
    final all = List<ComplaintModel>.from(complaintsNotifier.value);
    final updatedList = List<ComplaintModel>.from(all);
    final List<Map<String, dynamic>> cloudUpdates = [];
    int scanned = 0;
    int newlyFlagged = 0;
    int cleared = 0;

    for (int i = 0; i < updatedList.length; i++) {
      final c = updatedList[i];
      if (c.status == ComplaintStatus.rejected ||
          c.status == ComplaintStatus.resolved) {
        continue;
      }

      final checks = await scanComplaintEvidence(c.id);
      final result = VerificationCheckResult(isFlagged: !checks.canApprove, isDuplicate: checks.isDuplicate,
        isFakeSuspected: !checks.gpsPassed || !checks.timingPassed,
        confidenceScore: checks.overallRiskScore, riskFactors: checks.matchedAiFeatures,
        recommendation: checks.aiVerdict, flagReason: checks.canApprove ? null : checks.matchedAiFeatures.join(' | '),
        matchedComplaintId: checks.matchedComplaintId, matchedImageUrl: checks.matchedImageUrl);
      scanned++;
      await AiDuplicateDetectorService.saveScanRecord(c.id, result);

      if (result.isFlagged && !c.isFlaggedForReview) {
        updatedList[i] = c.copyWith(
          isFlaggedForReview: true,
          flaggedReason: result.flagReason,
        );
        cloudUpdates.add({
          'id': c.id,
          'flagged': true,
          'reason': result.flagReason,
        });
        newlyFlagged++;
      } else if (!result.isFlagged &&
          c.isFlaggedForReview &&
          c.status == ComplaintStatus.submitted) {
        // Self-heal stale false positives that were never adjudicated.
        updatedList[i] = ComplaintModel(
          id: c.id,
          restaurantId: c.restaurantId,
          restaurantName: c.restaurantName,
          userId: c.userId,
          userName: c.userName,
          category: c.category,
          issues: c.issues,
          description: c.description,
          status: c.status,
          severity: c.severity,
          latitude: c.latitude,
          longitude: c.longitude,
          isFlaggedForReview: false,
          flaggedReason: null,
          submittedAt: c.submittedAt,
          evidenceContext: c.evidenceContext,
          photoUrls: c.photoUrls,
        );
        cloudUpdates.add({
          'id': c.id,
          'flagged': false,
          'reason': null,
        });
        cleared++;
      }
    }

    if (newlyFlagged > 0 || cleared > 0) {
      complaintsNotifier.value = updatedList;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'local_custom_complaints',
          jsonEncode(updatedList.map((c) => c.toJson()).toList()),
        );
      } catch (_) {}
      try {
        final supabase = SupabaseService.client;
        for (final u in cloudUpdates) {
          try {
            await supabase.from('complaints').update({
              'is_flagged_for_review': u['flagged'] as bool,
              'flagged_reason': u['reason'],
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', u['id'] as String);
          } catch (_) {}
        }
      } catch (_) {}
    }

    return {
      'scanned': scanned,
      'flagged': newlyFlagged,
      'cleared': cleared,
    };
  }

  /// Admin assigns a complaint to a Government Health Officer for field investigation
  static Future<bool> assignOfficerToComplaint({
    required String complaintId,
    required String officerName,
    String? officerId,
    String? directives,
  }) async {
    // Validate workflow: this completes the adminDuplicationReview step
    await _validateWorkflowForAction(complaintId, WorkflowStep.adminDuplicationReview, UserRole.admin);

    if (!(await scanComplaintEvidence(complaintId)).canApprove) {
      throw StateError('Evidence verification is flagged or incomplete. Open Verify Evidence for details.');
    }

    final currentList = List<ComplaintModel>.from(complaintsNotifier.value);
    final idx = currentList.indexWhere((c) => c.id == complaintId);
    ComplaintModel? targetComplaint;

    if (idx != -1) {
      final c = currentList[idx];
      targetComplaint = ComplaintModel(
        id: c.id,
        restaurantId: c.restaurantId,
        restaurantName: c.restaurantName,
        userId: c.userId,
        userName: c.userName,
        category: c.category,
        issues: c.issues,
        description: c.description,
        status: ComplaintStatus.investigating,
        severity: c.severity,
        latitude: c.latitude,
        longitude: c.longitude,
        isFlaggedForReview: false,
        flaggedReason: c.flaggedReason,
        submittedAt: c.submittedAt,
        evidenceContext: c.evidenceContext,
        photoUrls: c.photoUrls,
      );
      currentList[idx] = targetComplaint;
      complaintsNotifier.value = currentList;
    }

    final restName = targetComplaint?.restaurantName ?? 'Premises';
    final severityStr = targetComplaint?.severity.name.toUpperCase() ?? 'MEDIUM';

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('complaint_assigned_officer_$complaintId', officerName);
      await prefs.setString('complaint_status_override_$complaintId', ComplaintStatus.investigating.name);
    } catch (_) {}

    // Update Supabase
    try {
      final supabase = SupabaseService.client;
      await supabase.from('complaints').update({
        'status': 'investigating',
        'is_flagged_for_review': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', complaintId);
    } catch (_) {}

    // Log in Audit Trail
    AuditLogService.logAction(
      actionType: 'ADMIN_ASSIGNED_OFFICER',
      category: 'Enforcement',
      title: 'Case Assigned to $officerName',
      description: 'Admin assigned report for $restName to $officerName for statutory inspection. Priority: $severityStr.${directives != null && directives.isNotEmpty ? " Note: $directives" : ""}',
    );

    // Send push notification to Government Health Officer
    NotificationService.sendNotification(
      userId: officerId ?? 'gov_officer_001',
      title: '🚨 New Field Case Assigned: $restName',
      message: 'Admin assigned a $severityStr priority hygiene report for $restName to you for on-site inspection.',
      type: NotificationType.hygieneAlert,
      actionUrl: 'verified_complaints_list',
    );

    // Complete workflow step: adminDuplicationReview -> start 7-day owner countdown
    await WorkflowService.forwardCaseAfterAdminReview(
      complaintId: complaintId,
      adminId: CustomerStoreService.currentCustomer?.id ?? 'admin',
      remarks: 'Officer assigned: $officerName',
    );

    return true;
  }

  // Workflow validation helper
  static Future<void> _validateWorkflowForAction(String complaintId, WorkflowStep requiredStep, UserRole userRole) async {
    final result = await WorkflowService.canPerformStep(
      complaintId: complaintId,
      requestedStep: requiredStep,
      userRole: userRole,
    );
    if (!result.isValid) {
      debugPrint('Workflow validation notice: ${result.errorMessage}');
    }
  }

  /// Admin verifies genuine evidence or overrides flag
  /// Read a complete, fresh comparison set; errors never fall back to clean cache results.
  static Future<AiDuplicateAnalysisResult> scanComplaintEvidence(String complaintId) async {
    final all = <ComplaintModel>[];
    for (var offset = 0; ; offset += 100) {
      final rows = await SupabaseService.client.from('complaints').select('*, restaurants(id,name), users(id,name), complaint_issues(issue_text), complaint_photos(photo_url)').order('id').range(offset, offset + 99);
      all.addAll(rows.map((r) => ComplaintModel.fromJson(r)));
      if (rows.length < 100) break;
    }
    final current = all.where((c) => c.id == complaintId).firstOrNull;
    if (current == null) throw StateError('Report is unavailable in Supabase.');
    final rows = await SupabaseService.client.from('restaurants').select().eq('id', current.restaurantId);
    final venues = rows.map((r) => RestaurantModel.fromMap(r)).toList();
    return AiDuplicateDetectorService.analyzeComplaintEvidence(complaint: current, databaseComplaints: all, databaseRestaurants: venues);
  }

  static Future<bool> verifyComplaintEvidence({
    required String complaintId,
    required bool isGenuine,
    String? remarks,
  }) async {
    // Validate workflow: this is the adminDuplicationReview step
    await _validateWorkflowForAction(complaintId, WorkflowStep.adminDuplicationReview, UserRole.admin);

    if (isGenuine) {
      final check = await scanComplaintEvidence(complaintId);
      if (!check.canApprove) return false;
    }
    final persisted = await SupabaseService.client.from('complaints').update({
      'status': isGenuine ? 'underReview' : 'rejected', 'is_flagged_for_review': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', complaintId).select('id');
    if (persisted.isEmpty) throw StateError('Verification could not be saved.');

    final currentList = List<ComplaintModel>.from(complaintsNotifier.value);
    final idx = currentList.indexWhere((c) => c.id == complaintId);
    if (idx != -1) {
      final c = currentList[idx];
      currentList[idx] = ComplaintModel(
        id: c.id,
        restaurantId: c.restaurantId,
        restaurantName: c.restaurantName,
        userId: c.userId,
        userName: c.userName,
        category: c.category,
        issues: c.issues,
        description: c.description,
        status: isGenuine ? ComplaintStatus.underReview : ComplaintStatus.rejected,
        severity: c.severity,
        latitude: c.latitude,
        longitude: c.longitude,
        isFlaggedForReview: false,
        flaggedReason: isGenuine ? null : (remarks ?? 'Evidence Rejected'),
        submittedAt: c.submittedAt,
        evidenceContext: c.evidenceContext,
        photoUrls: c.photoUrls,
      );
      complaintsNotifier.value = currentList;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'complaint_status_override_$complaintId',
        isGenuine ? ComplaintStatus.underReview.name : ComplaintStatus.rejected.name,
      );
    } catch (_) {}

    AuditLogService.logAction(
      actionType: isGenuine ? 'EVIDENCE_VERIFIED' : 'EVIDENCE_REJECTED',
      category: 'Admin Verification',
      title: isGenuine ? 'Evidence Verified Genuine' : 'Report Rejected by Admin',
      description: 'Admin verified complaint #$complaintId evidence. Status: ${isGenuine ? "Under Review" : "Rejected"}.',
    );

    // Complete workflow step
    if (isGenuine) {
      await WorkflowService.forwardCaseAfterAdminReview(
        complaintId: complaintId,
        adminId: CustomerStoreService.currentCustomer?.id ?? 'admin',
        remarks: 'Evidence verified as genuine',
      );
    } else {
      await WorkflowService.rejectWorkflow(
        complaintId: complaintId,
        rejectedBy: CustomerStoreService.currentCustomer?.id ?? 'admin',
        reason: remarks ?? 'Evidence Rejected',
      );
    }

    return true;
  }

  /// Admin merges a duplicate complaint into an existing master complaint
  static Future<bool> mergeComplaints({
    required String duplicateComplaintId,
    required String masterComplaintId,
    String? adminRemarks,
  }) async {
    final currentList = List<ComplaintModel>.from(complaintsNotifier.value);
    final dupIdx = currentList.indexWhere((c) => c.id == duplicateComplaintId);
    final masterIdx = currentList.indexWhere((c) => c.id == masterComplaintId);

    if (dupIdx == -1 || masterIdx == -1) return false;

    final dup = currentList[dupIdx];
    final master = currentList[masterIdx];

    // Combine photos and issues without duplicates
    final Set<String> mergedPhotos = {...master.photoUrls, ...dup.photoUrls};
    final Set<String> mergedIssues = {...master.issues, ...dup.issues};
    final masterShort = master.id.length > 8 ? master.id.substring(0, 8).toUpperCase() : master.id.toUpperCase();
    final dupShort = dup.id.length > 8 ? dup.id.substring(0, 8).toUpperCase() : dup.id.toUpperCase();

    // 1. Update master complaint with consolidated evidence
    final updatedMaster = ComplaintModel(
      id: master.id,
      restaurantId: master.restaurantId,
      restaurantName: master.restaurantName,
      userId: master.userId,
      userName: master.userName,
      category: master.category,
      issues: mergedIssues.toList(),
      description: '${master.description}\n\n[Consolidated Evidence from Duplicate Report #$dupShort]: ${dup.description}',
      status: master.status,
      severity: master.severity,
      latitude: master.latitude,
      longitude: master.longitude,
      isFlaggedForReview: false,
      flaggedReason: master.flaggedReason,
      submittedAt: master.submittedAt,
      photoUrls: mergedPhotos.toList(),
    );

    // 2. Mark duplicate as resolved (merged into master) so officers do not receive a duplicate task
    final updatedDup = ComplaintModel(
      id: dup.id,
      restaurantId: dup.restaurantId,
      restaurantName: dup.restaurantName,
      userId: dup.userId,
      userName: dup.userName,
      category: dup.category,
      issues: dup.issues,
      description: dup.description,
      status: ComplaintStatus.resolved,
      severity: dup.severity,
      latitude: dup.latitude,
      longitude: dup.longitude,
      isFlaggedForReview: false,
      flaggedReason: 'Merged into Master Case #$masterShort${adminRemarks != null ? " - $adminRemarks" : ""}',
      submittedAt: dup.submittedAt,
      evidenceContext: dup.evidenceContext,
      photoUrls: dup.photoUrls,
    );

    currentList[masterIdx] = updatedMaster;
    currentList[dupIdx] = updatedDup;
    complaintsNotifier.value = currentList;

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('complaint_status_override_$duplicateComplaintId', ComplaintStatus.resolved.name);
      await prefs.setString(
        'local_custom_complaints',
        jsonEncode(currentList.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}

    // Update Supabase
    try {
      final supabase = SupabaseService.client;
      await supabase.from('complaints').update({
        'status': 'resolved',
        'is_flagged_for_review': false,
        'flagged_reason': 'Merged into Master Case #$masterShort',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', duplicateComplaintId);

      await supabase.from('complaints').update({
        'description': updatedMaster.description,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', masterComplaintId);
    } catch (_) {}

    // Audit Log
    AuditLogService.logAction(
      actionType: 'COMPLAINT_MERGED',
      category: 'Verification',
      title: 'Duplicate Report #$dupShort Merged',
      description: 'Admin merged duplicate report #$dupShort into Master Case #$masterShort for ${master.restaurantName}. Combined ${dup.photoUrls.length} photos and ${dup.issues.length} issues.',
    );

    // Notify Submitter
    NotificationService.sendNotification(
      userId: dup.userId,
      title: '📋 Report Updated: Merged with Master Investigation',
      message: 'Your report for ${dup.restaurantName} has been combined with active Master Case #$masterShort. Health officers are investigating.',
      type: NotificationType.complaint,
      actionUrl: 'complaint_history',
    );

    return true;
  }

  /// Admin rejects and dismisses a fake/spam report
  static Future<bool> rejectComplaint({
    required String complaintId,
    required String reason,
  }) async {
    // Validate workflow: this completes the adminDuplicationReview step
    await _validateWorkflowForAction(complaintId, WorkflowStep.adminDuplicationReview, UserRole.admin);

    final currentList = List<ComplaintModel>.from(complaintsNotifier.value);
    final idx = currentList.indexWhere((c) => c.id == complaintId);
    if (idx == -1) return false;

    final target = currentList[idx];
    final shortId = target.id.length > 8 ? target.id.substring(0, 8).toUpperCase() : target.id.toUpperCase();

    final updatedTarget = ComplaintModel(
      id: target.id,
      restaurantId: target.restaurantId,
      restaurantName: target.restaurantName,
      userId: target.userId,
      userName: target.userName,
      category: target.category,
      issues: target.issues,
      description: target.description,
      status: ComplaintStatus.rejected,
      severity: target.severity,
      latitude: target.latitude,
      longitude: target.longitude,
      isFlaggedForReview: false,
      flaggedReason: 'Rejected as Fake / Spam: $reason',
      submittedAt: target.submittedAt,
      evidenceContext: target.evidenceContext,
      photoUrls: target.photoUrls,
    );

    currentList[idx] = updatedTarget;
    complaintsNotifier.value = currentList;

    // Persist
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('complaint_status_override_$complaintId', ComplaintStatus.rejected.name);
      await prefs.setString(
        'local_custom_complaints',
        jsonEncode(currentList.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}

    try {
      final supabase = SupabaseService.client;
      await supabase.from('complaints').update({
        'status': 'rejected',
        'is_flagged_for_review': false,
        'flagged_reason': 'Rejected: $reason',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', complaintId);
    } catch (_) {}

    AuditLogService.logAction(
      actionType: 'COMPLAINT_REJECTED',
      category: 'Fraud Prevention',
      title: 'Fake / Spam Report #$shortId Dismissed',
      description: 'Admin dismissed report for ${target.restaurantName}. Reason: $reason. Report excluded from officer dispatch.',
    );

    NotificationService.sendNotification(
      userId: target.userId,
      title: '⚠️ Report Status: Dismissed',
      message: 'Your report #$shortId could not be verified ($reason).',
      type: NotificationType.complaint,
      actionUrl: 'complaint_history',
    );

    return true;
  }

  /// Admin verifies a flagged report as genuine and assigns it
  static Future<bool> verifyAndApproveComplaint({
    required String complaintId,
    String? officerName,
  }) async {
    // Validate workflow: this completes the adminDuplicationReview step
    await _validateWorkflowForAction(complaintId, WorkflowStep.adminDuplicationReview, UserRole.admin);

    if (!(await scanComplaintEvidence(complaintId)).canApprove) {
      throw StateError('Evidence verification is flagged or incomplete. Open Verify Evidence for details.');
    }

    final currentList = List<ComplaintModel>.from(complaintsNotifier.value);
    final idx = currentList.indexWhere((c) => c.id == complaintId);
    if (idx == -1) return false;

    final target = currentList[idx];
    final shortId = target.id.length > 8 ? target.id.substring(0, 8).toUpperCase() : target.id.toUpperCase();

    final updatedTarget = ComplaintModel(
      id: target.id,
      restaurantId: target.restaurantId,
      restaurantName: target.restaurantName,
      userId: target.userId,
      userName: target.userName,
      category: target.category,
      issues: target.issues,
      description: target.description,
      status: ComplaintStatus.investigating,
      severity: target.severity,
      latitude: target.latitude,
      longitude: target.longitude,
      isFlaggedForReview: false,
      flaggedReason: 'Verified Genuine by Admin',
      submittedAt: target.submittedAt,
      evidenceContext: target.evidenceContext,
      photoUrls: target.photoUrls,
    );

    currentList[idx] = updatedTarget;
    complaintsNotifier.value = currentList;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('complaint_status_override_$complaintId', ComplaintStatus.investigating.name);
      await prefs.setString(
        'local_custom_complaints',
        jsonEncode(currentList.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}

    try {
      final supabase = SupabaseService.client;
      await supabase.from('complaints').update({
        'status': 'investigating',
        'is_flagged_for_review': false,
        'flagged_reason': 'Verified Genuine by Admin',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', complaintId);
    } catch (_) {}

    AuditLogService.logAction(
      actionType: 'COMPLAINT_VERIFIED',
      category: 'Verification',
      title: 'Report #$shortId Verified as Genuine',
      description: 'Admin verified evidence for ${target.restaurantName}. Assigned to ${officerName ?? "Health Officer Pipeline"}.',
    );

    // Forward workflow step: adminDuplicationReview -> 7-day owner rectification
    await WorkflowService.forwardCaseAfterAdminReview(
      complaintId: complaintId,
      adminId: CustomerStoreService.currentCustomer?.id ?? 'admin',
      remarks: 'Verified genuine and assigned officer: ${officerName ?? "Pipeline"}',
    );

    return true;
  }








}
