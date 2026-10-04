/// Validation and normalization helpers for input fields.
class Validators {
  Validators._();

  /// Validates that a user name is not empty after trimming whitespace.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    return null;
  }

  /// Normalizes an Indian phone number according to backend rules:
  /// - Strips all spaces and dashes.
  /// - Strips a leading '+91' or '0'.
  static String normalizePhone(String? value) {
    if (value == null) return '';
    var cleaned = value.trim().replaceAll(' ', '').replaceAll('-', '');
    if (cleaned.startsWith('+91')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }
    return cleaned;
  }

  /// Validates that a phone number, once normalized, contains exactly 10 digits.
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a valid 10-digit phone number';
    }
    final normalized = normalizePhone(value);
    if (normalized.length != 10 || !RegExp(r'^\d{10}$').hasMatch(normalized)) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }
}
