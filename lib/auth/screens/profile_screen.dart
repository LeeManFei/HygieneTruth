import '../../core/widgets/customer_refresh_indicator.dart';
import 'package:flutter/material.dart';
import '../../core/models/user_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/translations.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/google_sign_in_button.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/user_banner.dart';
import '../widgets/role_badge.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoadingSession = true;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    if (CustomerStoreService.currentCustomer != null) {
      _isLoadingSession = false;
    }
    _loadUserSession();
  }

  Future<void> _loadUserSession() async {
    await CustomerStoreService.fetchActiveUserSession();
    final hasPass = await CustomerStoreService.hasPasswordConfigured();
    if (mounted) {
      setState(() {
        _hasPassword = hasPass;
        _isLoadingSession = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = CustomerStoreService.currentCustomer;
    final userName = customer?.name ?? 'Guest User';
    final userEmail = customer?.email ?? 'Not Signed In';
    final avatarUrl = customer?.avatarUrl ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppTheme.navyColor;
    final subtitleTextColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);

        return Scaffold(
          appBar: CustomAppBar(
            title: t('Profile'),
            showBackButton: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Profile',
                onPressed: () async {
                  await Navigator.pushNamed(context, AppRoutes.editProfile);
                  _loadUserSession();
                },
              ),
              IconButton(
                icon: const Icon(Icons.history_toggle_off),
                tooltip: 'Settings & Security Log',
                onPressed: () => Navigator.pushNamed(context, AppRoutes.userSettingsHistory),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: t('settings'),
                onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: true,
            child: _isLoadingSession
                ? const ProfileSkeleton()
                : CustomerRefreshIndicator(enabled: CustomerStoreService.currentCustomer?.role == UserRole.user,
                    onRefresh: _loadUserSession,
                    color: AppTheme.primaryColor,
                    child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. TOP BANNER UI BEHIND PROFILE AVATAR FRAME
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.topCenter,
                          children: [
                            // Custom Cover / Gradient Banner
                            UserBanner(
                              bannerUrl: customer?.bannerUrl,
                              height: 140,
                            ),

                      // Overlapping Profile Avatar Frame Icon with Gold Ring Accent
                      Positioned(
                        top: 85,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              UserAvatar(
                                avatarUrl: avatarUrl,
                                radius: 46,
                              ),
                              // Online Status Indicator Dot
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(2.5),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981), // Active Online Green Dot
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 55),

                  // User Info Header Block
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      children: [
                        Text(
                          userName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userEmail,
                          style: TextStyle(
                            color: subtitleTextColor,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        RoleBadge(role: customer?.role ?? UserRole.user),
                        const SizedBox(height: 24),

                        // Section 1: Personal Details
                        Text(
                          'Personal Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 8),

                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildDetailRow(
                                  context,
                                  Icons.person_outline,
                                  'Full Name',
                                  userName,
                                  textColor,
                                  subtitleTextColor,
                                  onTap: () async {
                                    await Navigator.pushNamed(context, AppRoutes.editProfile);
                                    _loadUserSession();
                                  },
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.email_outlined,
                                  'Email Address',
                                  userEmail,
                                  textColor,
                                  subtitleTextColor,
                                ),
                                const Divider(height: 20),
                                InkWell(
                                  onTap: () {
                                    final isGoogleLinked = CustomerStoreService.isGoogleLinked();
                                    final googleEmail = CustomerStoreService.getGoogleLinkedEmail();
                                    _showLinkedConnectionBottomSheet(context, isGoogleLinked, googleEmail.isNotEmpty ? googleEmail : userEmail);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.link, color: AppTheme.primaryColor, size: 22),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Linked Connection',
                                                style: TextStyle(fontSize: 12, color: subtitleTextColor),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Text(
                                                    CustomerStoreService.isGoogleLinked() ? 'Google Account Linked' : 'Not Linked',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: CustomerStoreService.isGoogleLinked() ? Colors.green.shade700 : textColor,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  if (CustomerStoreService.isGoogleLinked())
                                                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.lock_outline_rounded,
                                  'Account Password',
                                  _hasPassword ? 'Password Configured (Tap to change)' : 'Not Set (Tap to set password)',
                                  textColor,
                                  subtitleTextColor,
                                  valueColor: _hasPassword
                                      ? (isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E))
                                      : (isDark ? const Color(0xFFFDBA74) : const Color(0xFFD97706)),
                                  onTap: () => _showPasswordSecurityDialog(),
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.phone_outlined,
                                  'Phone Number',
                                  customer?.phone ?? 'Not set (Tap edit to set)',
                                  textColor,
                                  subtitleTextColor,
                                  onTap: () async {
                                    await Navigator.pushNamed(context, AppRoutes.editProfile);
                                    _loadUserSession();
                                  },
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.wc_outlined,
                                  'Gender',
                                  customer?.gender ?? 'Not set (Tap edit to set)',
                                  textColor,
                                  subtitleTextColor,
                                  onTap: () async {
                                    await Navigator.pushNamed(context, AppRoutes.editProfile);
                                    _loadUserSession();
                                  },
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.public_outlined,
                                  'Country / Region',
                                  customer?.country ?? 'Not set (Tap edit to set)',
                                  textColor,
                                  subtitleTextColor,
                                  onTap: () async {
                                    await Navigator.pushNamed(context, AppRoutes.editProfile);
                                    _loadUserSession();
                                  },
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.location_city_outlined,
                                  'State / City',
                                  customer?.state ?? 'Not set (Tap edit to set)',
                                  textColor,
                                  subtitleTextColor,
                                  onTap: () async {
                                    await Navigator.pushNamed(context, AppRoutes.editProfile);
                                    _loadUserSession();
                                  },
                                ),
                                const Divider(height: 20),
                                _buildDetailRow(
                                  context,
                                  Icons.calendar_today_outlined,
                                  'Member Since',
                                  _formatMemberSinceDate(customer?.joinedDate),
                                  textColor,
                                  subtitleTextColor,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        );
  }

  String _formatMemberSinceDate(String? rawDate) {
    if (rawDate != null && rawDate.trim().isNotEmpty && rawDate != 'Recently Joined') {
      if (rawDate.contains('-') && rawDate.length >= 10) {
        final dt = DateTime.tryParse(rawDate);
        if (dt != null) {
          final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
        }
      }
      return rawDate;
    }
    final nowMsia = DateTime.now().toUtc().add(const Duration(hours: 8));
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${nowMsia.day} ${months[nowMsia.month - 1]} ${nowMsia.year}';
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color textColor,
    Color subtitleTextColor, {
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final isClickable = (onTap != null);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: subtitleTextColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: valueColor ??
                          (value.contains('Not set') ? Colors.grey.shade500 : textColor),
                    ),
                  ),
                ],
              ),
            ),
            if (isClickable)
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showLinkedConnectionBottomSheet(BuildContext context, bool initialIsLinked, String initialEmail) {
    bool isLinked = initialIsLinked;
    String linkedEmail = initialEmail;
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Icon(Icons.link, color: AppTheme.primaryColor, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Linked Connection Status',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Google Connection Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isLinked ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isLinked ? const Color(0xFF86EFAC) : Colors.grey.shade300,
                          width: isLinked ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const GoogleGLogoWidget(size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Google Account',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isLinked ? Colors.green.shade100 : Colors.grey.shade200,
                                      ),
                                      child: Text(
                                        isLinked ? 'Linked' : 'Not Linked',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isLinked ? Colors.green.shade800 : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isLinked ? linkedEmail : 'No Google account connected',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isLinked ? FontWeight.w500 : FontWeight.normal,
                                    color: isLinked ? Colors.green.shade900 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isLinked
                          ? '✓ Your Google account ($linkedEmail) is successfully bound to this profile for fast 1-tap authentication.'
                          : 'ℹ️ Connect your Google account to enable instant 1-tap sign-in and sync across your devices.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                    ),
                    const SizedBox(height: 20),

                    // Primary Action: Link / Unlink Button
                    if (!isLinked)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                          ),
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  setModalState(() => isProcessing = true);
                                  final result = await CustomerStoreService.linkGoogleAccount();

                                  if (!mounted || !modalContext.mounted) return;

                                  if (result.success) {
                                    final newEmail = CustomerStoreService.getGoogleLinkedEmail();
                                    setModalState(() {
                                      isLinked = true;
                                      linkedEmail = newEmail;
                                      isProcessing = false;
                                    });
                                    if (mounted) setState(() {});
                                    HygieneFeedback.showSuccess(modalContext, result.message);
                                  } else {
                                    setModalState(() => isProcessing = false);
                                    HygieneFeedback.showError(modalContext, result.message);
                                  }
                                },
                          icon: isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const GoogleGLogoWidget(size: 16),
                                ),
                          label: Text(
                            isProcessing ? 'Connecting to Google...' : 'Link Google Account',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  final confirm = await showDialog<bool>(
                                    context: modalContext,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('Unlink Google Account?'),
                                      content: const Text(
                                        'Are you sure you want to disconnect this Google account? You will still be able to log in with your email and password.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dCtx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                                          onPressed: () => Navigator.pop(dCtx, true),
                                          child: const Text('Unlink', style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (!mounted || !modalContext.mounted) return;

                                  if (confirm == true) {
                                    setModalState(() => isProcessing = true);
                                    final result = await CustomerStoreService.unlinkGoogleAccount();

                                    if (!mounted || !modalContext.mounted) return;

                                    if (result.success) {
                                      setModalState(() {
                                        isLinked = false;
                                        linkedEmail = '';
                                        isProcessing = false;
                                      });
                                      if (mounted) setState(() {});
                                      HygieneFeedback.showSuccess(modalContext, result.message);
                                    } else {
                                      setModalState(() => isProcessing = false);
                                    }
                                  }
                                },
                          icon: isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                                )
                              : const Icon(Icons.link_off_rounded, size: 20),
                          label: Text(
                            isProcessing ? 'Unlinking...' : 'Unlink Google Account',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Close Button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPasswordSecurityDialog() async {
    final bool hasExistingPassword = await CustomerStoreService.hasPasswordConfigured();
    if (!mounted) return;

    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (sbCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
          final newPass = newPasswordController.text;

          // Password Strength Calculation
          int strengthScore = 0;
          if (newPass.length >= 6) strengthScore++;
          if (newPass.length >= 8) strengthScore++;
          if (RegExp(r'[A-Z]').hasMatch(newPass)) strengthScore++;
          if (RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]').hasMatch(newPass)) strengthScore++;

          String strengthLabel = 'Weak Password';
          Color strengthColor = Colors.red;
          if (strengthScore >= 3) {
            strengthLabel = 'Strong Password';
            strengthColor = const Color(0xFF0F766E);
          } else if (strengthScore == 2) {
            strengthLabel = 'Medium Strength';
            strengthColor = Colors.orange;
          }

          return Dialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF121212), const Color(0xFF0F766E)]
                              : [const Color(0xFF0C2340), const Color(0xFF0F766E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(hasExistingPassword ? Icons.lock_reset_rounded : Icons.password_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasExistingPassword ? 'Change Password' : 'Set Account Password',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasExistingPassword
                                      ? 'Update your login security credentials'
                                      : 'Create a password for direct email login access',
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                    ),

                    // Form Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Current Password (Only if already set)
                          if (hasExistingPassword) ...[
                            TextField(
                              controller: oldPasswordController,
                              obscureText: obscureOld,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                labelText: 'Current Password *',
                                prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFF0284C7)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                                suffixIcon: IconButton(
                                  icon: Icon(obscureOld ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                                  onPressed: () => setDialogState(() => obscureOld = !obscureOld),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 2. New Password
                          TextField(
                            controller: newPasswordController,
                            obscureText: obscureNew,
                            onChanged: (_) => setDialogState(() {}),
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              labelText: hasExistingPassword ? 'New Password *' : 'Create Password *',
                              hintText: 'Enter at least 6 characters',
                              prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primaryColor),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                              suffixIcon: IconButton(
                                icon: Icon(obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                                onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                              ),
                            ),
                          ),

                          // Live Password Strength Bar
                          if (newPass.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: (strengthScore / 4).clamp(0.1, 1.0),
                                      color: strengthColor,
                                      backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  strengthLabel,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: strengthColor),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),

                          // 3. Confirm New Password
                          TextField(
                            controller: confirmPasswordController,
                            obscureText: obscureConfirm,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              labelText: 'Confirm Password *',
                              hintText: 'Re-enter your password',
                              prefixIcon: const Icon(Icons.check_circle_rounded, color: Color(0xFF0F766E)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                              suffixIcon: IconButton(
                                icon: Icon(obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                                onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Action Buttons Row
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () => Navigator.pop(dialogCtx),
                                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: isSaving ? null : () async {
                                    final nav = Navigator.of(dialogCtx);
                                    final oldPass = oldPasswordController.text;
                                    final newPass = newPasswordController.text;
                                    final confirmPass = confirmPasswordController.text;

                                    if (hasExistingPassword && oldPass.isEmpty) {
                                      HygieneFeedback.showWarning(dialogCtx, 'Please enter your current password');
                                      return;
                                    }

                                    if (newPass.length < 6) {
                                      HygieneFeedback.showWarning(dialogCtx, 'Password must be at least 6 characters!');
                                      return;
                                    }

                                    if (newPass != confirmPass) {
                                      HygieneFeedback.showWarning(dialogCtx, 'Passwords do not match!');
                                      return;
                                    }

                                    setDialogState(() => isSaving = true);

                                    final CustomerAuthResult result;
                                    if (hasExistingPassword) {
                                      result = await CustomerStoreService.changePassword(
                                        oldPassword: oldPass,
                                        newPassword: newPass,
                                      );
                                    } else {
                                      result = await CustomerStoreService.setInitialPassword(
                                        newPassword: newPass,
                                      );
                                    }

                                    setDialogState(() => isSaving = false);
                                    if (!mounted) return;

                                    if (result.success) {
                                      nav.pop();
                                      HygieneFeedback.showSuccess(
                                        context,
                                        hasExistingPassword
                                            ? 'Password changed successfully!'
                                            : 'Password set successfully! You can now log in with your email and password.',
                                      );
                                      _loadUserSession();
                                    } else {
                                      HygieneFeedback.showError(context, result.message);
                                    }
                                  },
                                  child: isSaving
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : Text(
                                          hasExistingPassword ? 'Update Password' : 'Save Password',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
