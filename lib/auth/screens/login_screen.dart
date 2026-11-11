import '../../core/widgets/app_validated_field.dart';
import 'package:flutter/material.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/remember_me_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/input_validator.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/google_sign_in_button.dart';
import '../widgets/portal_switch_modal.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;

  bool _obscurePassword = true;
  bool _rememberMe = false; // State for Remember Me Checkbox
  bool _isLoading = false;
  bool _isTraditionalLoading = false;
  bool _isGoogleLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final data = await RememberMeService.getRememberedUser(portal: PortalType.customer);
    if (mounted) {
      setState(() {
        final bool isRemembered = data['rememberMe'] == true;
        _rememberMe = isRemembered;
        _emailController.text = isRemembered ? (data['email'] ?? '') : '';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _isGoogleLoading = true;
    });

    final result = await CustomerStoreService.signInWithGoogle(isRegistration: false);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isGoogleLoading = false;
      });

      if (result.success) {
        HygieneFeedback.showSuccess(context, result.message);
        if (CustomerStoreService.currentCustomer != null) {
          Navigator.pushReplacementNamed(context, AppRoutes.userDashboard);
        }
      } else {
        if (result.isAccountNotFound) {
          HygieneFeedback.showWarning(context, result.message);
          // Redirect user to registration page
          Navigator.pushNamed(context, AppRoutes.register);
        } else {
          HygieneFeedback.showError(context, result.message);
        }
      }
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailErr = InputValidator.validateEmail(email);
    final passErr = InputValidator.validatePassword(password);

    setState(() {
      _emailError = emailErr;
      _passwordError = passErr;
    });

    if (emailErr != null || passErr != null) {
      String msg;
      if (email.isEmpty && password.isEmpty) {
        msg = 'Please enter email and password';
      } else if (emailErr != null) {
        msg = emailErr;
      } else {
        msg = passErr!;
      }
      HygieneFeedback.showWarning(context, msg);
      return;
    }

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final targetRoute = args?['targetRoute'] as String? ?? AppRoutes.userDashboard;

    setState(() {
      _isLoading = true;
      _isTraditionalLoading = true;
    });

    await RememberMeService.saveRememberedUser(
      rememberMe: _rememberMe,
      email: email,
      portal: PortalType.customer,
    );

    // Authenticate with Supabase & CustomerStoreService
    final result = await CustomerStoreService.loginCustomer(
      email: email,
      password: password,
      rememberMe: _rememberMe,
      portal: PortalType.customer,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isTraditionalLoading = false;
      });

      if (result.success) {
        HygieneFeedback.showSuccess(context, result.message);
        Navigator.pushReplacementNamed(context, targetRoute);
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
      appBar: CustomAppBar(
        title: 'Log In',
        showBackButton: Navigator.canPop(context),
        actions: const [
          PortalSwitchButton(currentPortal: 'Customer'),
        ],
      ),
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
                'Hygiene Portal',
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
                'Sign in to track hygiene updates & reports',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Email Field matching system theme
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

              // Password Field with Visibility Toggle
              AppValidatedField(validator: InputValidator.validatePassword, controller: _passwordController,
                obscureText: _obscurePassword,
                style: TextStyle(color: isDark ? Colors.white : navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  errorText: _passwordError,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: isDark ? Colors.white60 : Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
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
                  if (_passwordError != null) setState(() => _passwordError = null);
                },
              ),
              const SizedBox(height: 6),

              // Remember Me Checkbox on Far Left & Forgot Password Link on Far Right
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _rememberMe = !_rememberMe;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            activeColor: primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              setState(() {
                                _rememberMe = val ?? false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Remember me',
                          style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white70 : Colors.grey.shade700, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.resetPassword);
                    },
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Log In Button Styled strictly in System Primary Teal
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: _isTraditionalLoading ? 54 : fullButtonWidth,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
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
                              key: ValueKey('login_spinner'),
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : SingleChildScrollView(
                              key: const ValueKey('login_text_row'),
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.login, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Log In',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Register Account Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have an account?", style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.register);
                    },
                    child: const Text(
                      'Register',
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
                      'OR CONTINUING WITH',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(child: Divider(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 20),

              // Google Sign-In Button
              GoogleSignInButton(
                text: 'Sign in with Google',
                isLoading: _isGoogleLoading,
                width: fullButtonWidth,
                onPressed: _isLoading ? null : _handleGoogleSignIn,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
