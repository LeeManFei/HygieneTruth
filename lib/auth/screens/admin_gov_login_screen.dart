import '../../core/widgets/app_validated_field.dart';
import '../../core/services/remember_me_service.dart';
import 'package:flutter/material.dart';
import '../../core/models/user_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../widgets/portal_switch_modal.dart';

class AdminGovLoginScreen extends StatefulWidget {
  const AdminGovLoginScreen({super.key});

  @override
  State<AdminGovLoginScreen> createState() => _AdminGovLoginScreenState();
}

class _AdminGovLoginScreenState extends State<AdminGovLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Selected Official Role Portal Mode (Government or Admin)
  UserRole _selectedPortalRole = UserRole.government;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleOfficialLogin() async {
    if (_isLoading) return;
    final selectedRole = _selectedPortalRole;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      HygieneFeedback.showWarning(
        context,
        'Please enter your official email and password.',
      );
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      HygieneFeedback.showWarning(
        context,
        'Please enter a valid email address.',
      );
      return;
    }

    setState(() => _isLoading = true);

    FocusScope.of(context).unfocus();
    final portalType = selectedRole == UserRole.admin
        ? PortalType.admin
        : PortalType.government;

    try {
    final result = await CustomerStoreService.loginCustomer(
      email: email,
      password: password,
      portal: portalType,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (result.success) {
        final targetRoute = selectedRole == UserRole.admin
            ? AppRoutes.adminDashboard
            : AppRoutes.governmentDashboard;

        HygieneFeedback.showSuccess(
          context,
          selectedRole == UserRole.admin
              ? 'Administrator Access Granted'
              : 'Government Official Portal Access Granted',
        );
        Navigator.pushReplacementNamed(context, targetRoute);
      } else {
        HygieneFeedback.showError(context, result.message);
      }
    }
    } catch (_) {
      if (mounted) HygieneFeedback.showError(context, 'Sign-in could not finish. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isAdmin = _selectedPortalRole == UserRole.admin;
    final primaryColor = isAdmin ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)) : (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF00897B));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(
        title: 'Official Staff Portal',
        showBackButton: true,
        actions: [
          PortalSwitchButton(currentPortal: 'Official'),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
              // Top App Logo Image
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/HygieneTruth.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            Text(
              isAdmin ? 'System Administrator Portal' : 'Government Official Portal',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isAdmin
                  ? 'Review complaint tickets, verify restaurant submissions & log admin actions'
                  : 'Conduct inspections, issue enforcement notices & close compliance cases',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Role Segmented Switch (Government vs Admin)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading ? null : () => setState(() => _selectedPortalRole = UserRole.government),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !isAdmin ? (isDark ? const Color(0xFF00897B) : const Color(0xFF00897B)) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Government Official',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: !isAdmin ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading ? null : () => setState(() => _selectedPortalRole = UserRole.admin),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isAdmin ? (isDark ? const Color(0xFF0284C7) : const Color(0xFF0284C7)) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Administrator',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isAdmin ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            AppValidatedField(validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter your staff email address.' : null, controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14.5),
              decoration: InputDecoration(
                helperText: ' ',
                labelText: 'Official Staff ID / Email',
                labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                prefixIcon: Icon(Icons.badge_outlined, color: isDark ? Colors.white60 : Colors.grey.shade600),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            AppValidatedField(validator: (v) => (v?.isEmpty ?? true) ? 'Enter your staff password.' : null, controller: _passwordController,
              obscureText: _obscurePassword,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14.5),
              decoration: InputDecoration(
                helperText: ' ',
                labelText: 'Password',
                labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                prefixIcon: Icon(Icons.lock_outline, color: isDark ? Colors.white60 : Colors.grey.shade600),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: isDark ? Colors.white60 : Colors.grey,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleOfficialLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isAdmin ? 'Log In as Administrator' : 'Log In as Government Official',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
