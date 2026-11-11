import 'package:flutter/material.dart';
import '../../core/models/user_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/input_validator.dart';
import '../../core/widgets/custom_app_bar.dart';

class OwnerRegisterScreen extends StatefulWidget {
  const OwnerRegisterScreen({super.key});

  @override
  State<OwnerRegisterScreen> createState() => _OwnerRegisterScreenState();
}

class _OwnerRegisterScreenState extends State<OwnerRegisterScreen> {
  final _ownerNameController = TextEditingController();
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

  @override
  void dispose() {
    _ownerNameController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  Future<void> _handleOwnerRegistration() async {
    final name = _ownerNameController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passController.text;
    final confirmPass = _confirmPassController.text;

    final nameErr = InputValidator.validateName(name, fieldName: 'businessman name');
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
      String firstError = nameErr ?? emailErr ?? passErr ?? confirmErr!;
      HygieneFeedback.showWarning(context, firstError);
      return;
    }

    setState(() => _isLoading = true);

    final result = await CustomerStoreService.registerCustomer(
      name: name,
      email: email,
      password: pass,
      role: UserRole.owner,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (result.success) {
        CustomerStoreService.updateOwnerRole(UserRole.owner);

        HygieneFeedback.showSuccess(
          context,
          'Business Registration Successful! Welcome, ${result.user?.name ?? name}!',
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.ownerDashboard,
          (route) => false,
        );
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
      appBar: const CustomAppBar(title: 'Business Registration'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Circular soft amber badge matching system theme
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
                'Register Business Account',
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
                'Register your business details to receive official inspection notices & report resolutions',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Businessman / Manager Full Name
              TextField(
                controller: _ownerNameController,
                style: TextStyle(color: navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Businessman / Manager Full Name',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.person_outline_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: ownerColor, width: 1.8),
                  ),
                  errorText: _nameError,
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 16),

              // Business Email Address
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Business Email Address',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.email_outlined, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
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

              // Password
              TextField(
                controller: _passController,
                obscureText: _obscurePass,
                style: TextStyle(color: navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  errorText: _passError,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: isDark ? Colors.white60 : Colors.grey.shade500, size: 20),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: ownerColor, width: 1.8),
                  ),
                ),
                onChanged: (_) {
                  if (_passError != null) setState(() => _passError = null);
                },
              ),
              const SizedBox(height: 16),

              // Confirm Password
              TextField(
                controller: _confirmPassController,
                obscureText: _obscureConfirmPass,
                style: TextStyle(color: navyColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 14),
                  prefixIcon: Icon(Icons.lock_reset_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                  errorText: _confirmPassError,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: isDark ? Colors.white60 : Colors.grey.shade500, size: 20),
                    onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: ownerColor, width: 1.8),
                  ),
                ),
                onChanged: (_) {
                  if (_confirmPassError != null) setState(() => _confirmPassError = null);
                },
              ),
              const SizedBox(height: 24),

              // Register Action Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleOwnerRegistration,
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
                      : const Text('Register Business Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already registered your business?', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.ownerLogin),
                    child: const Text('Log In', style: TextStyle(color: ownerColor, fontWeight: FontWeight.bold, fontSize: 14)),
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
