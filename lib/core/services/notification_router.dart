import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../routes/app_routes.dart';
import '../models/restaurant_model.dart';
import 'restaurant_store_service.dart';
import 'customer_store_service.dart';
import 'notification_service.dart';

class NotificationRouter {
  static String? _pendingPayload;
  static GlobalKey<NavigatorState>? _navigatorKey;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  static GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// Process any pending notification payload when the app finishes launching
  static void processPendingLaunchPayload() {
    if (_pendingPayload != null && _pendingPayload!.isNotEmpty) {
      final payloadToProcess = _pendingPayload;
      _pendingPayload = null;
      Future.delayed(const Duration(milliseconds: 300), () {
        navigateFromPayload(payloadToProcess);
      });
    }
  }

  /// Master router to navigate directly to the target screen based on notification payload
  static void navigateFromPayload(String? payload, {BuildContext? context}) {
    if (payload == null || payload.trim().isEmpty) {
      _navigateToRoute(AppRoutes.notificationCenter, context: context);
      return;
    }

    final nav = _navigatorKey?.currentState ?? (context != null ? Navigator.of(context) : null);
    if (nav == null) {
      if (kDebugMode) {
        print('Navigator not ready yet, saving payload for launch: $payload');
      }
      _pendingPayload = payload;
      return;
    }

    Map<String, dynamic> payloadMap = {};
    String? rawStringPayload = payload.trim();

    try {
      if (payload.startsWith('{') && payload.endsWith('}')) {
        payloadMap = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      }
    } catch (_) {}

    String? notifId = payloadMap['id']?.toString() ?? payloadMap['notification_id']?.toString();
    String? typeStr = payloadMap['type']?.toString();
    String? actionUrl = payloadMap['action_url']?.toString() ??
        payloadMap['actionUrl']?.toString() ??
        (payloadMap.isEmpty ? rawStringPayload : null);
    String? restaurantId = payloadMap['restaurant_id']?.toString() ??
        payloadMap['restaurantId']?.toString() ??
        payloadMap['data']?['restaurant_id']?.toString();
    String? restaurantName = payloadMap['restaurant_name']?.toString() ??
        payloadMap['restaurantName']?.toString() ??
        payloadMap['data']?['restaurant_name']?.toString();
    String? complaintId = payloadMap['complaint_id']?.toString() ??
        payloadMap['complaintId']?.toString() ??
        payloadMap['data']?['complaint_id']?.toString();

    // Mark as read if notification ID is present
    if (notifId != null && notifId.isNotEmpty) {
      final user = CustomerStoreService.currentCustomer;
      NotificationService.markAsRead(notifId, userId: user?.id, userEmail: user?.email);
    }

    // 1. Check for specific Complaint Reference
    if (complaintId == null && actionUrl != null) {
      final compMatch = RegExp(r'#?CMP-([A-Za-z0-9]+)', caseSensitive: false).firstMatch(actionUrl);
      if (compMatch != null) {
        complaintId = compMatch.group(1);
      } else if (actionUrl.startsWith('cmp_') || actionUrl.startsWith('complaint_')) {
        complaintId = actionUrl.replaceFirst('cmp_', '').replaceFirst('complaint_', '');
      }
    }

    if (complaintId != null && complaintId.isNotEmpty) {
      _routeToComplaint(complaintId, context: context);
      return;
    }

    // 2. Check for specific Restaurant Reference
    if (restaurantId == null && actionUrl != null) {
      if (actionUrl.startsWith('outlet_')) {
        restaurantId = actionUrl.replaceFirst('outlet_', '');
      } else if (actionUrl.startsWith('restaurant_')) {
        restaurantId = actionUrl.replaceFirst('restaurant_', '');
      }
    }

    final isReviewType = typeStr != null && typeStr.toLowerCase().contains('review');
    if ((restaurantId != null && restaurantId.isNotEmpty) ||
        (restaurantName != null && restaurantName.isNotEmpty)) {
      _routeToRestaurant(
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        scrollToReviews: isReviewType,
        context: context,
      );
      return;
    }

    // 3. Direct Route Match (e.g. '/notifications', '/map', '/recommendation-home')
    if (actionUrl != null && actionUrl.isNotEmpty) {
      if (actionUrl == AppRoutes.notificationCenter || actionUrl == '/notifications') {
        _navigateToRoute(AppRoutes.notificationCenter, context: context);
        return;
      }
      if (actionUrl == AppRoutes.restaurantMap || actionUrl == '/map') {
        _navigateToRoute(AppRoutes.restaurantMap, context: context);
        return;
      }
      if (actionUrl == AppRoutes.recommendationHome || actionUrl == '/recommendations') {
        _navigateToRoute(AppRoutes.recommendationHome, context: context);
        return;
      }
      if (actionUrl == AppRoutes.complaintHistory || actionUrl == '/complaints') {
        _navigateToRoute(AppRoutes.complaintHistory, context: context);
        return;
      }
      if (actionUrl == AppRoutes.hygieneHeatmap || actionUrl == '/heatmap') {
        _navigateToRoute(AppRoutes.hygieneHeatmap, context: context);
        return;
      }
      if (actionUrl == AppRoutes.ownerDashboard || actionUrl == '/owner-dashboard') {
        _navigateToRoute(AppRoutes.ownerDashboard, context: context);
        return;
      }
    }

    // 4. Fallback based on notification type
    if (typeStr != null) {
      final lowerType = typeStr.toLowerCase();
      if (lowerType.contains('complaint')) {
        _navigateToRoute(AppRoutes.complaintHistory, context: context);
        return;
      }
      if (lowerType.contains('alert') || lowerType.contains('hygiene')) {
        _navigateToRoute(AppRoutes.recommendationHome, context: context);
        return;
      }
      if (lowerType.contains('outlet') || lowerType.contains('restaurant')) {
        _navigateToRoute(AppRoutes.restaurantSearch, context: context);
        return;
      }
    }

    // 5. Default Fallback -> Notification Center
    _navigateToRoute(AppRoutes.notificationCenter, context: context);
  }

  static void _routeToComplaint(String complaintId, {BuildContext? context}) {
    final allComplaints = ComplaintStoreService.complaintsNotifier.value.isNotEmpty
        ? ComplaintStoreService.complaintsNotifier.value
        : RestaurantStoreService.complaintsNotifier.value;

    final cleanTarget = complaintId
        .replaceAll('#', '')
        .replaceAll('CMP-', '')
        .replaceAll('cmp-', '')
        .replaceAll('cmp_', '')
        .trim()
        .toLowerCase();

    final targetComplaint = allComplaints.where((c) {
      final cleanId = c.id
          .replaceAll('#', '')
          .replaceAll('CMP-', '')
          .replaceAll('cmp-', '')
          .replaceAll('cmp_', '')
          .trim()
          .toLowerCase();
      return cleanId == cleanTarget ||
          cleanId.startsWith(cleanTarget) ||
          cleanTarget.startsWith(cleanId) ||
          c.id.toLowerCase() == complaintId.toLowerCase();
    }).firstOrNull;

    if (targetComplaint != null) {
      _navigateToRoute(
        AppRoutes.complaintStatusDetail,
        arguments: targetComplaint,
        context: context,
      );
    } else {
      _navigateToRoute(
        AppRoutes.complaintStatusDetail,
        arguments: complaintId,
        context: context,
      );
    }
  }

  static void _routeToRestaurant({
    String? restaurantId,
    String? restaurantName,
    bool scrollToReviews = false,
    BuildContext? context,
  }) {
    final allRestaurants = RestaurantStoreService.restaurantsNotifier.value;
    RestaurantModel? target;

    if (restaurantId != null && restaurantId.isNotEmpty) {
      target = allRestaurants
          .where((r) => r.id == restaurantId || r.name.toLowerCase() == restaurantId.toLowerCase())
          .firstOrNull;
    }
    if (target == null && restaurantName != null && restaurantName.isNotEmpty) {
      target = allRestaurants
          .where((r) => r.name.toLowerCase() == restaurantName.toLowerCase())
          .firstOrNull;
    }
    if (target == null && allRestaurants.isNotEmpty) {
      target = allRestaurants.first;
    }

    if (target != null) {
      _navigateToRoute(
        AppRoutes.restaurantDetail,
        arguments: {
          'restaurant': target,
          'scrollToReviews': scrollToReviews,
        },
        context: context,
      );
    } else {
      _navigateToRoute(AppRoutes.restaurantSearch, context: context);
    }
  }

  static void _navigateToRoute(String routeName, {Object? arguments, BuildContext? context}) {
    try {
      final nav = _navigatorKey?.currentState ?? (context != null ? Navigator.of(context) : null);
      if (nav != null) {
        nav.pushNamed(routeName, arguments: arguments);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error navigating to route $routeName: $e');
      }
    }
  }
}
