import '../../core/widgets/app_validated_field.dart';
import 'package:flutter/material.dart';
import '../../core/models/user_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/input_validator.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/google_sign_in_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passError;
  String? _confirmPassError;

  bool _obscurePass = true;
  bool _obscureConfirmPass = true;

  bool _isLoading = false;
  bool _isTraditionalLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }



  // --- TRADITIONAL REGISTRATION FLOW ---
  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passController.text;
    final confirmPass = _confirmPassController.text;

    final nameErr = InputValidator.validateName(name, fieldName: 'your name');
    final emailErr = InputValidator.validateEmail(email);
    final passErr = InputValidator.validatePassword(pass);
    final confirmErr = InputValidator.validateConfirmPassword(pass, confirmPass);

    setState(() {
      _nameError = nameErr;
      _emailError = emailErr;
      _passError = passErr;
      _confirmPassError = confirmErr;
    });

    if (nameErr != null || emailErr != null || passErr != null || confirmErr != null) {
      final firstError = nameErr ?? emailErr ?? passErr ?? confirmErr!;
      HygieneFeedback.showWarning(context, firstError);
      return;
    }

    setState(() {
      _isLoading = true;
      _isTraditionalLoading = true;
    });

    final result = await CustomerStoreService.registerCustomer(
      name: name,
      email: email,
      password: pass,
      role: UserRole.user,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isTraditionalLoading = false;
      });

      if (result.success) {
        HygieneFeedback.showSuccess(context, 'Account created successfully!');
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.userDashboard,
          (route) => false,
          arguments: {
            'showProfileSetupDialog': true,
            'isGoogleFlow': false,
          },
        );
      } else {
        HygieneFeedback.showError(context, result.message);
      }
    }
  }

  // --- GOOGLE SIGN UP FLOW ---
  Future<void> _handleGoogleRegistration() async {
    setState(() {
      _isLoading = true;
      _isGoogleLoading = true;
    });

    final result = await CustomerStoreService.signInWithGoogle(isRegistration: true);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isGoogleLoading = false;
      });

      if (result.success && CustomerStoreService.currentCustomer != null) {
        HygieneFeedback.showSuccess(context, result.message);
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.userDashboard,
          (route) => false,
          arguments: {
            'showProfileSetupDialog': true,
            'isGoogleFlow': true,
          },
        );
      } else {
        HygieneFeedback.showError(context, result.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = AppTheme.primaryColor;
    final navyColor = isDark ? Colors.white : AppTheme.navyColor;
    final fullButtonWidth = MediaQuery.of(context).size.width - 48;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Create Account'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
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
              const SizedBox(height: 18),

              // Header Title
              Text(
                'Register Account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: navyColor,
                  letterSpacing: -0.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),

              // Subtitle
              Text(
                'Start monitoring & reporting in seconds',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Full Name
              AppValidatedField(validator: (v) => InputValidator.validateName(v, fieldName: 'your name'), controller: _nameController,
                style: TextStyle(color: isDark ? Colors.white : navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.person_outline_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryColor, width: 1.8),
                  ),
                  errorText: _nameError,
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 16),

              // Email Address
              AppValidatedField(validator: InputValidator.validateEmail, controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: isDark ? Colors.white : navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.email_outlined, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryColor, width: 1.8),
                  ),
                  errorText: _emailError,
                ),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
              ),
              const SizedBox(height: 16),

              // Password
              AppValidatedField(validator: InputValidator.validatePassword, guidance: 'Use at least 8 characters.', controller: _passController,
                obscureText: _obscurePass,
                style: TextStyle(color: isDark ? Colors.white : navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  errorText: _passError,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: isDark ? Colors.white60 : Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePass = !_obscurePass;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryColor, width: 1.8),
                  ),
                ),
                onChanged: (_) {
                  if (_passError != null) setState(() => _passError = null);
                },
              ),
              const SizedBox(height: 16),

              // Confirm Password
              AppValidatedField(revalidateOn: _passController, validator: (v) => InputValidator.validateConfirmPassword(_passController.text, v), controller: _confirmPassController,
                obscureText: _obscureConfirmPass,
                style: TextStyle(color: isDark ? Colors.white : navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.lock_reset_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  errorText: _confirmPassError,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: isDark ? Colors.white60 : Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPass = !_obscureConfirmPass;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryColor, width: 1.8),
                  ),
                ),
                onChanged: (_) {
                  if (_confirmPassError != null) setState(() => _confirmPassError = null);
                },
              ),
              const SizedBox(height: 24),

              // Animated Register Button
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: _isTraditionalLoading ? 54 : fullButtonWidth,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_isTraditionalLoading ? 27 : 12),
                      ),
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isTraditionalLoading
                          ? const SizedBox(
                              key: ValueKey('reg_spinner'),
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Register Account',
                              key: ValueKey('reg_text_row'),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Login Route Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacementNamed(context, AppRoutes.login);
                    },
                    child: const Text(
                      'Log In',
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Divider Line
              Row(
                children: [
                  Expanded(child: Divider(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR REGISTER WITH',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(child: Divider(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 20),

              // Google Registration Button
              GoogleSignInButton(
                text: 'Register with Google',
                isLoading: _isGoogleLoading,
                width: fullButtonWidth,
                onPressed: _isLoading ? null : _handleGoogleRegistration,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
