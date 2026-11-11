import 'core/services/customer_store_service.dart';
import 'core/services/restaurant_store_service.dart';
import 'auth/screens/user_settings_history_screen.dart';
import 'package:flutter/material.dart';
import 'core/services/language_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_manager.dart';
import 'core/routes/app_routes.dart';
import 'core/models/user_model.dart';
import 'core/widgets/role_dashboard_scaffold.dart';

// Authentication & Onboarding Module (auth)
import 'auth/screens/splash_screen.dart';
import 'auth/screens/onboarding_screen.dart';
import 'auth/screens/login_screen.dart';
import 'auth/screens/register_screen.dart';
import 'auth/screens/admin_gov_login_screen.dart';
import 'auth/screens/reset_password_screen.dart';
import 'auth/screens/profile_screen.dart';
import 'auth/screens/edit_profile_screen.dart';
import 'auth/screens/settings_screen.dart';
import 'auth/screens/activity_history_screen.dart';
import 'auth/screens/manage_user_accounts_screen.dart';
import 'auth/screens/account_detail_screen.dart';

import 'owner/screens/owner_login_screen.dart';
import 'owner/screens/owner_register_screen.dart';

// GPS & Restaurant Info Module (gps)
import 'gps/screens/restaurant_search_screen.dart';
import 'gps/screens/restaurant_list_screen.dart';
import 'gps/screens/restaurant_detail_screen.dart';
import 'gps/screens/restaurant_map_screen.dart';
import 'gps/screens/add_restaurant_screen.dart';
import 'gps/screens/restaurant_verification_queue_screen.dart';
import 'gps/screens/restaurant_verification_detail_screen.dart';

// Hygiene Complaint Reporting Module (report)
import 'report/screens/submit_complaint_screen.dart';
import 'report/screens/complaint_history_screen.dart';
import 'report/screens/complaint_status_detail_screen.dart';

// Complaint Verification & Administration Module (complaint)
import 'complaint/screens/all_complaints_screen.dart';
import 'complaint/screens/complaint_review_detail_screen.dart';
import 'complaint/screens/verify_evidence_screen.dart';
import 'complaint/screens/duplicate_fake_review_screen.dart';
import 'complaint/screens/restaurant_validation_queue_screen.dart';
import 'complaint/screens/inspection_report_review_screen.dart';
import 'complaint/screens/admin_action_log_screen.dart';

// Inspection & Enforcement Module (inspect)
import 'inspect/screens/verified_complaints_list_screen.dart';
import 'inspect/screens/government_audit_log_screen.dart';
import 'inspect/screens/complaint_full_detail_screen.dart';
import 'inspect/screens/schedule_inspection_screen.dart';
import 'inspect/screens/conduct_inspection_screen.dart';
import 'inspect/screens/issue_action_list_screen.dart';
import 'inspect/screens/issue_enforcement_screen.dart';
import 'inspect/screens/enforcement_history_screen.dart';
import 'inspect/screens/close_case_list_screen.dart';
import 'inspect/screens/close_case_screen.dart';

// Risk Score Analysis & Smart Recommendation Module (risk)
import 'risk/screens/recommendation_home_screen.dart';
import 'risk/screens/hygiene_heatmap_screen.dart';
import 'risk/screens/restaurant_risk_detail_screen.dart';
import 'risk/screens/risk_ranking_list_screen.dart';

// Restaurant Owner Portal Module (owner)
import 'owner/screens/notice_detail_screen.dart';
import 'owner/screens/mark_issue_resolved_screen.dart';
import 'owner/screens/final_report_screen.dart';
import 'owner/screens/owner_action_history_screen.dart';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'core/config/app_env.dart';
import 'core/services/data_sync_service.dart';
import 'core/services/audit_log_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/notification_router.dart';
import 'notifications/screens/notification_center_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await AuditLogService.initializeRetention(); } catch (e) { debugPrint('Audit retention initialization failed: $e'); }
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('dotenv.load error: $e');
  }

  try {
    Stripe.publishableKey =
        dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? AppEnv.stripePublishableKey;
    Stripe.urlScheme = 'flutterstripe';
    await Stripe.instance.applySettings();
  } catch (e) {
    debugPrint('Stripe init error: $e');
  }

  try {
    await SupabaseService.initialize();
    RestaurantStoreService.initRealtimeSubscriptions();
    // Run full dual synchronization to populate Supabase tables & cache locally in SharedPreferences
    await DataSyncService.syncAllData();
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }

  try {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  } catch (_) {}

  runApp(const RestaurantHygieneApp());
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class RestaurantHygieneApp extends StatefulWidget {
  const RestaurantHygieneApp({super.key});

  @override
  State<RestaurantHygieneApp> createState() => _RestaurantHygieneAppState();
}

class _RestaurantHygieneAppState extends State<RestaurantHygieneApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationRouter.setNavigatorKey(appNavigatorKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationRouter.processPendingLaunchPayload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CustomerStoreService.checkInactivityTimeout(
        navigatorKey: appNavigatorKey,
      );
      final user = CustomerStoreService.currentCustomer;
      if (user != null) {
        NotificationService.fetchNotifications(
          userId: user.id,
          userEmail: user.email,
          userRole: user.role.name,
        );
        NotificationRouter.processPendingLaunchPayload();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      CustomerStoreService.updateLastActive();
      NotificationService.scheduleUnreadReminderOnAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeManager, languageManager]),
      builder: (context, _) {
        return ScaffoldMessenger(
          child: MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Restaurant Hygiene Monitoring System',
            debugShowCheckedModeBanner: false,
            locale: languageManager.locale,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeManager.themeMode,
            themeAnimationDuration: const Duration(milliseconds: 400),
            themeAnimationCurve: Curves.easeInOutCubic,
            builder: (context, child) {
              return child ?? const SizedBox.shrink();
            },
            initialRoute: AppRoutes.splash,
            routes: {
              // Onboarding, Splash & Auth
              AppRoutes.splash: (context) => const SplashScreen(),
              AppRoutes.onboarding: (context) => const OnboardingScreen(),
              AppRoutes.splashRoleSelect: (context) => const LoginScreen(),
              AppRoutes.login: (context) => const LoginScreen(),
              AppRoutes.register: (context) => const RegisterScreen(),
              AppRoutes.ownerLogin: (context) => const OwnerLoginScreen(),
              AppRoutes.ownerRegister: (context) => const OwnerRegisterScreen(),
              AppRoutes.adminGovLogin: (context) => const AdminGovLoginScreen(),
              AppRoutes.resetPassword: (context) => const ResetPasswordScreen(),
              AppRoutes.profile: (context) => const ProfileScreen(),
              AppRoutes.editProfile: (context) => const EditProfileScreen(),
              AppRoutes.settings: (context) => const SettingsScreen(),
              AppRoutes.activityHistory: (context) =>
                  const ActivityHistoryScreen(),
              AppRoutes.userSettingsHistory: (context) =>
                  const UserSettingsHistoryScreen(),
              AppRoutes.manageUserAccounts: (context) =>
                  const ManageUserAccountsScreen(),
              AppRoutes.accountDetail: (context) => const AccountDetailScreen(),

              // Role Dashboards
              AppRoutes.userDashboard: (context) =>
                  const RoleDashboardScaffold(initialRole: UserRole.user),
              AppRoutes.adminDashboard: (context) =>
                  const RoleDashboardScaffold(initialRole: UserRole.admin),
              AppRoutes.governmentDashboard: (context) =>
                  const RoleDashboardScaffold(initialRole: UserRole.government),
              AppRoutes.ownerDashboard: (context) =>
                  const RoleDashboardScaffold(initialRole: UserRole.owner),

              // GPS & Restaurant Info
              AppRoutes.restaurantSearch: (context) =>
                  const RestaurantSearchScreen(),
              AppRoutes.restaurantList: (context) =>
                  const RestaurantListScreen(),
              AppRoutes.restaurantDetail: (context) =>
                  const RestaurantDetailScreen(),
              AppRoutes.restaurantMap: (context) => const RestaurantMapScreen(),
              AppRoutes.savedRestaurants: (context) =>
                  const SavedRestaurantsScreen(),
              AppRoutes.addRestaurant: (context) => const AddRestaurantScreen(),
              AppRoutes.restaurantVerificationQueue: (context) =>
                  const RestaurantVerificationQueueScreen(),
              AppRoutes.restaurantVerificationDetail: (context) =>
                  const RestaurantVerificationDetailScreen(),

              // Hygiene Complaint Reporting
              AppRoutes.submitComplaint: (context) =>
                  const SubmitComplaintScreen(),
              AppRoutes.complaintHistory: (context) =>
                  const ComplaintHistoryScreen(),
              AppRoutes.complaintStatusDetail: (context) =>
                  const ComplaintStatusDetailScreen(),

              // Complaint Verification & Administration
              AppRoutes.allComplaints: (context) => const AllComplaintsScreen(),
              AppRoutes.complaintReviewDetail: (context) =>
                  const ComplaintReviewDetailScreen(),
              AppRoutes.verifyEvidence: (context) =>
                  const VerifyEvidenceScreen(),
              AppRoutes.duplicateFakeReview: (context) =>
                  const DuplicateFakeReviewScreen(),
              AppRoutes.restaurantValidationQueue: (context) =>
                  const RestaurantValidationQueueScreen(),
              AppRoutes.inspectionReportReview: (context) =>
                  const InspectionReportReviewScreen(),
              AppRoutes.adminActionLog: (context) =>
                  const AdminActionLogScreen(),

              // Inspection & Enforcement
              AppRoutes.verifiedComplaintsList: (context) =>
                  const VerifiedComplaintsListScreen(),
              AppRoutes.governmentAuditLog: (context) =>
                  const GovernmentAuditLogScreen(),
              AppRoutes.complaintFullDetail: (context) =>
                  const ComplaintFullDetailScreen(),
              AppRoutes.scheduleInspection: (context) =>
                  const ScheduleInspectionScreen(),
              AppRoutes.conductInspection: (context) =>
                  const ConductInspectionScreen(),
              AppRoutes.issueEnforcement: (context) =>
                  const IssueActionListScreen(),
              AppRoutes.issueEnforcementDetail: (context) =>
                  const IssueEnforcementScreen(),
              AppRoutes.enforcementHistory: (context) =>
                  const EnforcementHistoryScreen(),
              AppRoutes.closeCase: (context) => const CloseCaseListScreen(),
              AppRoutes.closeCaseDetail: (context) => const CloseCaseScreen(),

              // Risk Score Analysis & Smart Recommendation
              AppRoutes.recommendationHome: (context) =>
                  const RecommendationHomeScreen(),
              AppRoutes.hygieneHeatmap: (context) =>
                  const HygieneHeatmapScreen(),
              AppRoutes.restaurantRiskDetail: (context) =>
                  const RestaurantRiskDetailScreen(),
              AppRoutes.riskRankingList: (context) =>
                  const RiskRankingListScreen(),

              // Restaurant Owner Portal
              AppRoutes.noticeDetail: (context) => const NoticeDetailScreen(),
              AppRoutes.markIssueResolved: (context) =>
                  const MarkIssueResolvedScreen(),
              AppRoutes.finalReport: (context) => const FinalReportScreen(),
              AppRoutes.ownerActionHistory: (context) =>
                  const OwnerActionHistoryScreen(),

              // Notification Center
              AppRoutes.notificationCenter: (context) =>
                  const NotificationCenterScreen(),
            },
          ),
        );
      },
    );
  }
}
