import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_user_app/utils/validators.dart';

void main() {
  group('Validators.validateName', () {
    test('returns error when null', () {
      expect(Validators.validateName(null), 'Name is required');
    });

    test('returns error when empty string', () {
      expect(Validators.validateName(''), 'Name is required');
    });

    test('returns error when whitespace only', () {
      expect(Validators.validateName('   '), 'Name is required');
    });

    test('returns null for valid name', () {
      expect(Validators.validateName('Alice'), isNull);
      expect(Validators.validateName('  Alice Nair  '), isNull);
    });
  });

  group('Validators.normalizePhone', () {
    test('returns empty string when null', () {
      expect(Validators.normalizePhone(null), '');
    });

    test('leaves plain 10-digit phone untouched', () {
      expect(Validators.normalizePhone('9876543210'), '9876543210');
    });

    test('strips spaces', () {
      expect(Validators.normalizePhone('98765 43210'), '9876543210');
    });

    test('strips dashes', () {
      expect(Validators.normalizePhone('98765-43210'), '9876543210');
    });

    test('strips leading +91 with spaces', () {
      expect(Validators.normalizePhone('+91 98765 43210'), '9876543210');
    });

    test('strips leading +91 with dashes', () {
      expect(Validators.normalizePhone('+91-98765-43210'), '9876543210');
    });

    test('strips leading 0', () {
      expect(Validators.normalizePhone('09876543210'), '9876543210');
    });

    test('strips leading +91 and 0 combined', () {
      expect(Validators.normalizePhone('+9109876543210'), '9876543210');
    });
  });

  group('Validators.validatePhone', () {
    test('returns error when null or empty', () {
      expect(Validators.validatePhone(null), 'Enter a valid 10-digit phone number');
      expect(Validators.validatePhone(''), 'Enter a valid 10-digit phone number');
      expect(Validators.validatePhone('   '), 'Enter a valid 10-digit phone number');
    });

    test('returns null for valid standard 10-digit phone', () {
      expect(Validators.validatePhone('9876543210'), isNull);
    });

    test('returns null for valid phone with +91 and spaces', () {
      expect(Validators.validatePhone('+91 98765 43210'), isNull);
    });

    test('returns null for valid phone with leading 0', () {
      expect(Validators.validatePhone('09876543210'), isNull);
    });

    test('returns error for short phone numbers', () {
      expect(Validators.validatePhone('123'), 'Enter a valid 10-digit phone number');
      expect(Validators.validatePhone('987654321'), 'Enter a valid 10-digit phone number');
    });

    test('returns error for overly long phone numbers', () {
      expect(Validators.validatePhone('98765432101'), 'Enter a valid 10-digit phone number');
    });

    test('returns error for non-digit characters', () {
      expect(Validators.validatePhone('98765abcde'), 'Enter a valid 10-digit phone number');
      expect(Validators.validatePhone('abcdefghij'), 'Enter a valid 10-digit phone number');
    });
  });
}
