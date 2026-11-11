import 'package:flutter/material.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/language_manager.dart';
import '../../core/services/user_settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_manager.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/translations.dart';
import '../../core/widgets/custom_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Push Notification Settings Toggles
  bool _enablePushNotifications = true;
  bool _hygieneRiskAlerts = true;
  bool _inspectionUpdates = true;
  bool _complaintStatusAlerts = true;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final user = CustomerStoreService.currentCustomer;
    final userId = user?.id ?? 'guest_default';
    final settings = await UserSettingsService.loadUserSettings(userId);
    if (mounted) {
      setState(() {
        _enablePushNotifications = settings.enablePushNotifications;
        _hygieneRiskAlerts = settings.hygieneRiskAlerts;
        _complaintStatusAlerts = settings.complaintStatusAlerts;
        _inspectionUpdates = settings.inspectionUpdates;
      });
    }
  }

  void _saveSettingBool(String key, bool val) {
    final user = CustomerStoreService.currentCustomer;
    final userId = user?.id ?? 'guest_default';
    UserSettingsService.saveBool(userId, key, val);
  }

  Future<void> _showChangePasswordDialog() async {
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
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
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
                    // Gradient Top Header Banner
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
                                  hasExistingPassword ? t('change_password') : 'Set Account Password',
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
                          // 1. Current Password (ONLY required if password has already been configured)
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
                                  child: Text(t('cancel'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                      HygieneFeedback.showWarning(context, 'Please enter your current password');
                                      return;
                                    }

                                    if (newPass.length < 6) {
                                      HygieneFeedback.showWarning(context, 'Password must be at least 6 characters!');
                                      return;
                                    }

                                    if (newPass != confirmPass) {
                                      HygieneFeedback.showWarning(context, 'Passwords do not match!');
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
                                    } else {
                                      HygieneFeedback.showError(context, result.message);
                                    }
                                  },
                                  child: isSaving
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : Text(
                                          hasExistingPassword ? t('update') : 'Save Password',
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

  void _showLanguageSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('choose_language'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                ),
                const SizedBox(height: 16),
                ...List.generate(LanguageManager.languages.length, (index) {
                  final lang = LanguageManager.languages[index];
                  final isSelected = languageManager.locale.languageCode == lang['code'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor.withValues(alpha: isDark ? 0.2 : 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryColor : (isDark ? const Color(0xFF333333) : Colors.grey.shade300),
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        lang['label'].toString(),
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                      onTap: () {
                        languageManager.setLanguage(index);
                        Navigator.pop(context);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Settings'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. ACCOUNT & SECURITY SECTION
            _buildSectionHeader('ACCOUNT & PROFILE'),
            _buildSettingCard([
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_outline, color: Colors.blue),
                ),
                title: const Text('Edit Profile Details', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Name, email, phone number', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_outline, color: Colors.indigo),
                ),
                title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Update login credentials', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _showChangePasswordDialog,
              ),
            ]),

            const SizedBox(height: 24),

            // 2. PUSH NOTIFICATIONS SECTION
            _buildSectionHeader('PUSH NOTIFICATIONS'),
            _buildSettingCard([
              SwitchListTile(
                activeThumbColor: AppTheme.primaryColor,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
                ),
                title: const Text('Enable Push Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Receive real-time alerts and updates', style: TextStyle(fontSize: 12)),
                value: _enablePushNotifications,
                onChanged: (val) {
                  setState(() {
                    _enablePushNotifications = val;
                  });
                  _saveSettingBool('enable_push', val);
                },
              ),
              if (_enablePushNotifications) ...[
                const Divider(height: 1),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryColor,
                  title: const Text('Hygiene Risk Alerts', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('High risk changes near your location', style: TextStyle(fontSize: 12)),
                  value: _hygieneRiskAlerts,
                  onChanged: (val) {
                    setState(() => _hygieneRiskAlerts = val);
                    _saveSettingBool('risk_alerts', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryColor,
                  title: const Text('Complaint Status Updates', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Official inspection and ticket progress', style: TextStyle(fontSize: 12)),
                  value: _complaintStatusAlerts,
                  onChanged: (val) {
                    setState(() => _complaintStatusAlerts = val);
                    _saveSettingBool('complaint_alerts', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryColor,
                  title: const Text('Inspection Notice Updates', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Enforcement notices and resolution reports', style: TextStyle(fontSize: 12)),
                  value: _inspectionUpdates,
                  onChanged: (val) {
                    setState(() => _inspectionUpdates = val);
                    _saveSettingBool('inspection_updates', val);
                  },
                ),
              ],
            ]),

            const SizedBox(height: 24),

            // 3. NEW CONTAINER SECTION FOR THEME SETTINGS
            _buildSectionHeader('APPEARANCE & THEME SETTINGS'),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF3C3C3C)
                      : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Select App Theme Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Segmented Theme Mode Selector (Light, System, Dark)
                  ListenableBuilder(
                    listenable: themeManager,
                    builder: (context, _) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF181818) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            _buildThemeOption(ThemeMode.light, 'Light', Icons.light_mode_outlined),
                            _buildThemeOption(ThemeMode.system, 'System', Icons.brightness_auto_outlined),
                            _buildThemeOption(ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 4. LANGUAGE & PREFERENCES SECTION
            _buildSectionHeader(t('preferences')),
            _buildSettingCard([
              ListenableBuilder(
                listenable: languageManager,
                builder: (context, _) {
                  final currentLang = LanguageManager.languages.firstWhere(
                    (l) => l['code'] == languageManager.locale.languageCode,
                    orElse: () => LanguageManager.languages.first,
                  );

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.language, color: Colors.green),
                    ),
                    title: Text(t('language'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(currentLang['label'].toString(), style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: _showLanguageSelector,
                  );
                },
              ),
            ]),

            const SizedBox(height: 32),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: isDark ? const Color(0xFF9CA3AF) : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF3C3C3C) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildThemeOption(ThemeMode mode, String label, IconData icon) {
    final bool isSelected = themeManager.themeMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const Color activeColor = AppTheme.primaryColor;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          themeManager.setThemeMode(mode);
          HygieneFeedback.showSuccess(
            context,
            '$label Theme applied successfully!',
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF252526) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: activeColor.withValues(alpha: 0.5), width: 1.2)
                : Border.all(color: Colors.transparent),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? activeColor : (isDark ? const Color(0xFF9CA3AF) : Colors.grey.shade600),
                size: 20,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? activeColor : (isDark ? const Color(0xFF9CA3AF) : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
