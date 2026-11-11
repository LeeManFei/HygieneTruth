import 'app_select_field.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/country_location_data.dart';
import '../services/customer_store_service.dart';
import '../theme/app_theme.dart';
import '../utils/hygiene_feedback.dart';

enum PasswordDialogStep {
  options,
  customPassword,
  passwordReveal,
  skipWarning,
}

class ProfileSetupFocusDialog {
  /// Displays a Strong Focus Backdrop Dialog overlaying the Home Page
  static void show(BuildContext context, {bool isGoogleFlow = false}) {
    String? selectedGender;
    String? selectedCountry;
    String? selectedState;

    final customGenderCtrl = TextEditingController();
    final customCountryCtrl = TextEditingController();
    final customStateCtrl = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Profile Setup Focus',
      barrierColor: Colors.black.withValues(alpha: 0.65), // Strong Darkened Backdrop Focus
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value,
          child: child,
        );
      },
      pageBuilder: (ctx, anim1, anim2) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final inputBg = isDark ? const Color(0xFF282828) : const Color(0xFFF8FAFC);
        final titleColor = isDark ? Colors.white : AppTheme.navyColor;
        final textColor = isDark ? Colors.white : AppTheme.navyColor;
        final borderColor = isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1);

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 20,
            backgroundColor: cardBg,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                final customer = CustomerStoreService.currentCustomer;

                return Padding(
                  padding: const EdgeInsets.all(22.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Icon & Title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.person_pin_outlined, color: AppTheme.primaryColor, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer != null ? 'Welcome, ${customer.name}!' : 'Personal Details (Optional)',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
                                  ),
                                  Text(
                                    'Select gender, country, and state or set it later',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 1. GENDER DROPDOWN
                        Text('Gender', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: titleColor)),
                        const SizedBox(height: 6),
                        AppSelectField<String>(
                          initialValue: selectedGender,
                          dropdownColor: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'Select Gender',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.normal),
                            filled: true,
                            fillColor: inputBg,
                            prefixIcon: Icon(Icons.wc_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor, width: 1.2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor, width: 1.2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                            ),
                          ),
                          items: ['Male', 'Female', 'Other']
                              .map((g) => DropdownMenuItem(
                                    value: g,
                                    child: Text(
                                      g,
                                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14.5),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) => setDialogState(() => selectedGender = val),
                        ),
                        if (selectedGender == 'Other') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: customGenderCtrl,
                            style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: 'Enter your gender...',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                              filled: true,
                              fillColor: inputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor, width: 1.2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor, width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 2. COUNTRY DROPDOWN
                        Text('Country / Region', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: titleColor)),
                        const SizedBox(height: 6),
                        AppSelectField<String>(
                          initialValue: selectedCountry,
                          dropdownColor: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'Select Country',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.normal),
                            filled: true,
                            fillColor: inputBg,
                            prefixIcon: Icon(Icons.public_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor, width: 1.2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor, width: 1.2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                            ),
                          ),
                          items: CountryLocationData.countryList
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14.5),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedCountry = val;
                              final validStates = CountryLocationData.getStatesForCountry(val);
                              if (selectedState != null && !validStates.contains(selectedState)) {
                                selectedState = null;
                              }
                            });
                          },
                        ),
                        if (selectedCountry == 'Other') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: customCountryCtrl,
                            style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: 'Enter country name...',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                              filled: true,
                              fillColor: inputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor, width: 1.2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor, width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 3. STATE DROPDOWN
                        Text('State / City', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: titleColor)),
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            final currentStates = CountryLocationData.getStatesForCountry(selectedCountry);
                            final validInitial = (selectedState != null && currentStates.contains(selectedState)) ? selectedState : null;

                            return AppSelectField<String>(
                              key: ValueKey('state_dd_${selectedCountry ?? "none"}'),
                              initialValue: validInitial,
                              dropdownColor: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: selectedCountry == null ? 'Select Country First' : 'Select State / City',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.normal),
                                filled: true,
                                fillColor: inputBg,
                                prefixIcon: Icon(Icons.location_city_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderColor, width: 1.2),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderColor, width: 1.2),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                                ),
                              ),
                              items: currentStates
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(
                                          s,
                                          style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14.5),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) => setDialogState(() => selectedState = val),
                            );
                          },
                        ),
                        if (selectedState == 'Other') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: customStateCtrl,
                            style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: 'Enter state or city name...',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                              filled: true,
                              fillColor: inputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor, width: 1.2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor, width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ACTION BUTTONS
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final finalGender = selectedGender == 'Other' ? customGenderCtrl.text.trim() : selectedGender;
                            final finalCountry = selectedCountry == 'Other' ? customCountryCtrl.text.trim() : selectedCountry;
                            final finalState = selectedState == 'Other' ? customStateCtrl.text.trim() : selectedState;

                            Navigator.pop(ctx);
                            final current = CustomerStoreService.currentCustomer;
                            if (current != null) {
                              await CustomerStoreService.updateCustomerProfile(
                                name: current.name,
                                gender: finalGender,
                                country: finalCountry,
                                state: finalState,
                              );
                            }
                            if (isGoogleFlow && context.mounted) {
                              _showPasswordSecurityDialog(context);
                            }
                          },
                          child: const Text('Save & Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: borderColor, width: 1.2),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (isGoogleFlow && context.mounted) {
                              _showPasswordSecurityDialog(context);
                            }
                          },
                          child: Text('Set It Later', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Step 2: Unified Interactive Password Security Dialog
  /// Uses an internal state machine (options -> customPassword / passwordReveal / skipWarning)
  /// so that transitions are 100% reliable without route navigation race conditions.
  static void _showPasswordSecurityDialog(BuildContext context) {
    final customer = CustomerStoreService.currentCustomer;
    final userEmail = customer?.email ?? '';

    PasswordDialogStep currentStep = PasswordDialogStep.options;
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isGeneratedVisible = true;
    String generatedPassword = '';
    String? customError;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                elevation: 20,
                backgroundColor: cardBg,
                insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: SingleChildScrollView(
                      key: ValueKey(currentStep),
                      child: _buildDialogContent(
                        currentStep: currentStep,
                        dialogContext: dialogContext,
                        setDialogState: setDialogState,
                        userEmail: userEmail,
                        passwordCtrl: passwordCtrl,
                        confirmCtrl: confirmCtrl,
                        obscurePassword: obscurePassword,
                        onTogglePasswordObscure: () => setDialogState(() => obscurePassword = !obscurePassword),
                        obscureConfirm: obscureConfirm,
                        onToggleConfirmObscure: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        isGeneratedVisible: isGeneratedVisible,
                        onToggleGeneratedVisible: () => setDialogState(() => isGeneratedVisible = !isGeneratedVisible),
                        generatedPassword: generatedPassword,
                        customError: customError,
                        isSaving: isSaving,
                        isDark: isDark,
                        onGoToStep: (step) => setDialogState(() {
                          currentStep = step;
                          customError = null;
                        }),
                        onGeneratePassword: () async {
                          setDialogState(() => isSaving = true);
                          final tempPass = CustomerStoreService.generateSecurePassword();
                          final res = await CustomerStoreService.setInitialPassword(
                            newPassword: tempPass,
                            email: userEmail,
                          );
                          if (dialogContext.mounted) {
                            if (res.success) {
                              setDialogState(() {
                                isSaving = false;
                                generatedPassword = tempPass;
                                currentStep = PasswordDialogStep.passwordReveal;
                              });
                            } else {
                              setDialogState(() => isSaving = false);
                              HygieneFeedback.showError(dialogContext, res.message);
                            }
                          }
                        },
                        onSaveCustomPassword: () async {
                          final pass = passwordCtrl.text;
                          final confirm = confirmCtrl.text;
                          if (pass.length < 6) {
                            setDialogState(() => customError = 'Password must be at least 6 characters.');
                            return;
                          }
                          if (pass != confirm) {
                            setDialogState(() => customError = 'Passwords do not match.');
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                            customError = null;
                          });
                          final res = await CustomerStoreService.setInitialPassword(
                            newPassword: pass,
                            email: userEmail,
                          );
                          if (dialogContext.mounted) {
                            if (res.success) {
                              Navigator.pop(dialogContext);
                              HygieneFeedback.showSuccess(
                                dialogContext,
                                'Password configured successfully! You can now sign in with email & password.',
                              );
                            } else {
                              setDialogState(() {
                                isSaving = false;
                                customError = res.message;
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildDialogContent({
    required PasswordDialogStep currentStep,
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required String userEmail,
    required TextEditingController passwordCtrl,
    required TextEditingController confirmCtrl,
    required bool obscurePassword,
    required VoidCallback onTogglePasswordObscure,
    required bool obscureConfirm,
    required VoidCallback onToggleConfirmObscure,
    required bool isGeneratedVisible,
    required VoidCallback onToggleGeneratedVisible,
    required String generatedPassword,
    required String? customError,
    required bool isSaving,
    required bool isDark,
    required void Function(PasswordDialogStep) onGoToStep,
    required Future<void> Function() onGeneratePassword,
    required Future<void> Function() onSaveCustomPassword,
  }) {
    final titleColor = isDark ? Colors.white : AppTheme.navyColor;
    final textColor = isDark ? Colors.white : AppTheme.navyColor;
    final inputBg = isDark ? const Color(0xFF282828) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1);

    switch (currentStep) {
      // 1. STEP OPTIONS (Main Menu)
      case PasswordDialogStep.options:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.25) : const Color(0xFFCCFBF1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security_rounded,
                  size: 38,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Protect Your Account',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Would you like to set a password so you can sign in directly with your email on any device, or auto-generate a secure password?',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                fontSize: 13.5,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Option 1: Set Custom Password
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.password_rounded, size: 20),
              label: const Text(
                'Set My Own Password',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
              onPressed: () => onGoToStep(PasswordDialogStep.customPassword),
            ),
            const SizedBox(height: 10),

            // Option 2: Generate Random Password
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppTheme.primaryColor, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
                  : const Icon(Icons.auto_awesome_rounded, size: 20, color: AppTheme.primaryColor),
              label: Text(
                isSaving ? 'Securing Account...' : 'Generate Secure Password',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: AppTheme.primaryColor,
                ),
              ),
              onPressed: isSaving ? null : () => onGeneratePassword(),
            ),
            const SizedBox(height: 12),

            // Option 3: Skip for now
            TextButton(
              onPressed: () => onGoToStep(PasswordDialogStep.skipWarning),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                foregroundColor: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
              child: const Text(
                'Skip for Now',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ),
          ],
        );

      // 2. STEP CUSTOM PASSWORD (Inputs)
      case PasswordDialogStep.customPassword:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create Password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Set a password with at least 6 characters for $userEmail',
              style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            // Password Field
            TextField(
              controller: passwordCtrl,
              obscureText: obscurePassword,
              style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'New Password (min 6 chars)',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                suffixIcon: IconButton(
                  icon: Icon(obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  onPressed: onTogglePasswordObscure,
                ),
                filled: true,
                fillColor: inputBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 1.2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 1.2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8)),
              ),
            ),
            const SizedBox(height: 12),

            // Confirm Password Field
            TextField(
              controller: confirmCtrl,
              obscureText: obscureConfirm,
              style: TextStyle(color: textColor, fontSize: 14.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Confirm Password',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500),
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                suffixIcon: IconButton(
                  icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  onPressed: onToggleConfirmObscure,
                ),
                filled: true,
                fillColor: inputBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 1.2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 1.2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8)),
              ),
            ),

            if (customError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.15) : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.4) : Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: isDark ? const Color(0xFFFCA5A5) : Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        customError,
                        style: TextStyle(color: isDark ? const Color(0xFFFCA5A5) : Colors.red, fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: borderColor),
                    ),
                    onPressed: isSaving ? null : () => onGoToStep(PasswordDialogStep.options),
                    child: Text('Back', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSaving ? null : () => onSaveCustomPassword(),
                    child: isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Password', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        );

      // 3. STEP PASSWORD REVEAL (Generated)
      case PasswordDialogStep.passwordReveal:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF059669).withValues(alpha: 0.25) : const Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, size: 36, color: Color(0xFF059669)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Account Secured!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: titleColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'A secure temporary password has been created for your account ($userEmail). You can copy it now or change it later in Profile Settings.',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 13, height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Password Reveal Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_rounded, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isGeneratedVisible ? generatedPassword : '●●●●●●●●●●',
                      style: TextStyle(
                        fontSize: isGeneratedVisible ? 16 : 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: isGeneratedVisible ? 1.2 : 3.0,
                        color: textColor,
                        fontFamily: isGeneratedVisible ? 'monospace' : null,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(isGeneratedVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: isDark ? Colors.white60 : Colors.grey.shade700),
                    onPressed: onToggleGeneratedVisible,
                    tooltip: isGeneratedVisible ? 'Hide' : 'Show',
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20, color: AppTheme.primaryColor),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: generatedPassword));
                      HygieneFeedback.showSuccess(dialogContext, 'Password copied to clipboard!');
                    },
                    tooltip: 'Copy to Clipboard',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                HygieneFeedback.showSuccess(dialogContext, 'Account setup completed successfully!');
              },
              child: const Text('Got It, Continue to Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        );

      // 4. STEP SKIP WARNING (Notice)
      case PasswordDialogStep.skipWarning:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFFD97706).withValues(alpha: 0.25) : const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 36, color: Color(0xFFD97706)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Password Setup Notice',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: titleColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Without a password, you can only log in using Google Sign-In on supported devices. You will not be able to log in with your email & password until you set one in Settings > Account Security.\n\nDo you want to proceed?',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 13.5, height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => onGoToStep(PasswordDialogStep.options),
              child: const Text('Set Password Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: borderColor, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                HygieneFeedback.showSuccess(dialogContext, 'Profile setup completed. You can add a password anytime in Settings.');
              },
              child: Text('Proceed Without Password', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontWeight: FontWeight.w600)),
            ),
          ],
        );
    }
  }
}
