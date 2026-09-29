/// Client-side validation that deliberately mirrors the server's zod schemas
/// (`server/src/validators/*`).
///
/// The client validates to give instant feedback; the server validates
/// because it is the only side that can be trusted. When the two disagree the
/// server wins and its message is shown next to the field.
class Validators {
  const Validators._();

  static final RegExp _email = RegExp(r'^[\w.!#$%&*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$');
  static final RegExp _phone = RegExp(r'^\+?[0-9][0-9\s-]{5,}$');
  static final RegExp _hasLetter = RegExp('[A-Za-z]');
  static final RegExp _hasDigit = RegExp('[0-9]');

  static String? required(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    if (text.length > 191) return 'Email is too long';
    if (!_email.hasMatch(text)) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Phone number is required';
    if (text.length < 7) return 'Enter a valid phone number';
    if (text.length > 30) return 'Phone number is too long';
    if (!_phone.hasMatch(text)) return 'Enter a valid phone number';
    return null;
  }

  /// Matches `passwordField` on the server: 8–72 chars, a letter and a digit.
  static String? password(String? value) {
    final String text = value ?? '';
    if (text.isEmpty) return 'Password is required';
    if (text.length < 8) return 'Password must be at least 8 characters';
    if (text.length > 72) return 'Password must be at most 72 characters';
    if (!_hasLetter.hasMatch(text)) return 'Password must contain at least one letter';
    if (!_hasDigit.hasMatch(text)) return 'Password must contain at least one number';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static String? name(String? value, String label) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required';
    if (text.length < 2) return '$label must be at least 2 characters';
    if (text.length > 80) return '$label is too long';
    return null;
  }

  /// 0 = none, 1 = weak, 2 = fair, 3 = good, 4 = strong. Display only.
  static int passwordStrength(String value) {
    if (value.isEmpty) return 0;
    int score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (_hasLetter.hasMatch(value) && _hasDigit.hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score.clamp(0, 4);
  }

  static String passwordStrengthLabel(int score) {
    switch (score) {
      case 0:
        return '';
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }
}
