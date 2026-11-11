import 'package:flutter/material.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/remember_me_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/input_validator.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../auth/widgets/portal_switch_modal.dart';

class OwnerLoginScreen extends StatefulWidget {
  const OwnerLoginScreen({super.key});

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final data = await RememberMeService.getRememberedUser(portal: PortalType.owner);
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

  Future<void> _handleOwnerLogin() async {
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

    setState(() => _isLoading = true);

    await RememberMeService.saveRememberedUser(
      rememberMe: _rememberMe,
      email: email,
      portal: PortalType.owner,
    );

    final result = await CustomerStoreService.loginCustomer(
      email: email,
      password: password,
      rememberMe: _rememberMe,
      portal: PortalType.owner,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (result.success) {
        HygieneFeedback.showSuccess(context, 'Welcome to Businessman Portal!');
        Navigator.pushReplacementNamed(context, AppRoutes.ownerDashboard);
      } else {
        HygieneFeedback.showError(context, result.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const ownerColor = Color(0xFFD97706);
    final navyColor = isDark ? Colors.white : const Color(0xFF0C2340);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: CustomAppBar(
        title: 'Business Portal Login',
        showBackButton: Navigator.canPop(context),
        actions: const [
          PortalSwitchButton(
            currentPortal: 'Businessman',
            buttonColor: Color(0xFFD97706),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 20),
              Text(
                'Businessman Portal',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: navyColor,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Manage hygiene inspection compliance, notices & reports',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Email Input Field matching reference screenshot
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Business Email',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.business_center_outlined, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
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
                    borderSide: const BorderSide(color: ownerColor, width: 1.8),
                  ),
                  errorText: _emailError,
                ),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
              ),
              const SizedBox(height: 16),

              // Password Input Field matching reference screenshot
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: TextStyle(color: navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
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
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                    borderSide: const BorderSide(color: ownerColor, width: 1.8),
                  ),
                ),
                onChanged: (_) {
                  if (_passwordError != null) setState(() => _passwordError = null);
                },
              ),
              const SizedBox(height: 10),

              // Remember me Checkbox
              Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: ownerColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) => setState(() => _rememberMe = val ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remember me',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Log In to Business Portal Full-width Action Button matching reference design
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleOwnerLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ownerColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Text(
                          'Log In to Business Portal',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Footer: Need a Business Account? Register Business
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Need a Business Account?',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.ownerRegister),
                    child: const Text(
                      'Register Business',
                      style: TextStyle(
                        color: ownerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
