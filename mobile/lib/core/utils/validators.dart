/// Input validators matching backend Zod schemas.
library;

/// Each returns null if valid, or an error message string for TextFormField.

class Validators {
  const Validators._();

  /// Matches backend: z.string().email()
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
  );

  /// Matches backend: z.string().regex(/^[a-zA-Z0-9_]+$/)
  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');

  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Backend: z.string().email('Invalid email address')
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(value.trim())) return 'Invalid email address';
    return null;
  }

  /// Backend: z.string().min(8).regex(/[A-Z]/).regex(/[a-z]/).regex(/[0-9]/)
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Must contain an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'Must contain a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Must contain a number';
    return null;
  }

  /// Returns 0.0-1.0 password strength for visual indicator.
  static double passwordStrength(String value) {
    if (value.isEmpty) return 0;
    double score = 0;
    if (value.length >= 8) score += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(value)) score += 0.25;
    if (RegExp(r'[a-z]').hasMatch(value)) score += 0.25;
    if (RegExp(r'[0-9]').hasMatch(value)) score += 0.15;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) score += 0.10;
    return score.clamp(0.0, 1.0);
  }

  /// Backend: z.string().min(3).max(20).regex(/^[a-zA-Z0-9_]+$/)
  static String? username(String? value) {
    if (value == null || value.trim().isEmpty) return 'Username is required';
    final v = value.trim();
    if (v.length < 3) return 'Must be at least 3 characters';
    if (v.length > 20) return 'Must be at most 20 characters';
    if (!_usernameRegex.hasMatch(v)) return 'Only letters, numbers, and underscores';
    return null;
  }

  /// Backend: z.string().min(1).max(50)
  static String? displayName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Display name is required';
    if (value.trim().length > 50) return 'Must be at most 50 characters';
    return null;
  }

  static String? maxLength(String? value, int max, [String fieldName = 'Field']) {
    if (value != null && value.length > max) {
      return '$fieldName must be at most $max characters';
    }
    return null;
  }

  static String? url(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return 'Invalid URL';
    return null;
  }
}
