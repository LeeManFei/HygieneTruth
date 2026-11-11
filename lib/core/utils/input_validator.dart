class InputValidator {
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  /// Validates email address format
  static String? validateEmail(String? email) {
    final clean = email?.trim() ?? '';
    if (clean.isEmpty) {
      return 'Please enter email';
    }
    if (!_emailRegex.hasMatch(clean)) {
      return 'Invalid email (e.g. name@email.com)';
    }
    return null;
  }

  /// Validates password for login (checks empty & minimum length)
  static String? validatePassword(String? password) {
    final clean = password ?? '';
    if (clean.isEmpty) {
      return 'Please enter password';
    }
    if (clean.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  /// Validates required name fields
  static String? validateName(String? name, {String fieldName = 'name'}) {
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) {
      return 'Please enter $fieldName';
    }
    if (clean.length < 2) {
      return 'Must be at least 2 characters';
    }
    return null;
  }

  /// Validates confirmation password
  static String? validateConfirmPassword(String? password, String? confirmPassword) {
    final cleanConfirm = confirmPassword ?? '';
    if (cleanConfirm.isEmpty) {
      return 'Please confirm password';
    }
    if (password != cleanConfirm) {
      return 'Passwords do not match';
    }
    return null;
  }
}
