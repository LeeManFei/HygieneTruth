class AppRoutes {
  // Onboarding, Splash & Auth
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String splashRoleSelect = '/role-select';
  static const String login = '/login';
  static const String register = '/register';
  static const String ownerLogin = '/owner-login';
  static const String ownerRegister = '/owner-register';
  static const String adminGovLogin = '/admin-gov-login';
  static const String resetPassword = '/reset-password';
  static const String profile = '/profile';
  static const String editProfile = '/edit-profile';
  static const String settings = '/settings';
  static const String activityHistory = '/activity-history';
  static const String userSettingsHistory = '/user-settings-history';
  static const String manageUserAccounts = '/admin/manage-user-accounts';
  static const String accountDetail = '/admin/account-detail';

  // Navigation Shells
  static const String userDashboard = '/user-dashboard';
  static const String adminDashboard = '/admin-dashboard';
  static const String governmentDashboard = '/government-dashboard';
  static const String ownerDashboard = '/owner-dashboard';

  // GPS & Restaurant Info
  static const String restaurantSearch = '/restaurant-search';
  static const String restaurantList = '/restaurant-list';
  static const String restaurantDetail = '/restaurant-detail';
  static const String restaurantMap = '/restaurant-map';
  static const String savedRestaurants = '/saved-restaurants';
  static const String wishlist = '/saved-restaurants';
  static const String addRestaurant = '/add-restaurant';
  static const String restaurantVerificationQueue = '/admin/restaurant-verification-queue';
  static const String restaurantVerificationDetail = '/admin/restaurant-verification-detail';

  // Hygiene Complaint Reporting
  static const String submitComplaint = '/submit-complaint';
  static const String complaintHistory = '/complaint-history';
  static const String complaintStatusDetail = '/complaint-status-detail';

  // Complaint Verification & Administration (Admin)
  static const String allComplaints = '/admin/all-complaints';
  static const String complaintReviewDetail = '/admin/complaint-review-detail';
  static const String verifyEvidence = '/admin/verify-evidence';
  static const String duplicateFakeReview = '/admin/duplicate-fake-review';
  static const String restaurantValidationQueue = '/admin/restaurant-validation-queue';
  static const String inspectionReportReview = '/admin/inspection-report-review';
  static const String adminActionLog = '/admin/action-log';

  // Inspection & Enforcement (Government / PIC)
  static const String verifiedComplaintsList = '/gov/verified-complaints-list';
  static const String governmentAuditLog = '/gov/audit-log';
  static const String complaintFullDetail = '/gov/complaint-full-detail';
  static const String scheduleInspection = '/gov/schedule-inspection';
  static const String conductInspection = '/gov/conduct-inspection';
  static const String issueEnforcement = '/gov/issue-enforcement';
  static const String issueEnforcementDetail = '/gov/issue-enforcement-detail';
  static const String enforcementHistory = '/gov/enforcement-history';
  static const String closeCase = '/gov/close-case';
  static const String closeCaseDetail = '/gov/close-case-detail';

  // Risk Score Analysis & Smart Recommendation (Module 6)
  static const String recommendationHome = '/recommendation-home';
  static const String hygieneHeatmap = '/hygiene-heatmap';
  static const String restaurantRiskDetail = '/restaurant-risk-detail';
  static const String riskRankingList = '/risk-ranking-list';

  // Restaurant Owner Portal Module
  static const String noticeDetail = '/owner/notice-detail';
  static const String markIssueResolved = '/owner/mark-issue-resolved';
  static const String finalReport = '/owner/final-report';
  static const String ownerActionHistory = '/owner/action-history';

  // Notifications Module
  static const String notificationCenter = '/notifications';
}
