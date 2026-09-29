import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/utils/validators.dart';

/// These mirror `server/src/validators/*`. If the server tightens a rule,
/// this file is where the client learns about it.
void main() {
  group('Validators.email', () {
    test('accepts a normal address', () {
      expect(Validators.email('john.doe@smartqueue.test'), isNull);
    });

    test('rejects an empty value', () {
      expect(Validators.email(''), 'Email is required');
      expect(Validators.email(null), 'Email is required');
    });

    test('rejects an address with no domain dot', () {
      expect(Validators.email('john@localhost'), isNotNull);
    });

    test('rejects an address with no @', () {
      expect(Validators.email('john.smartqueue.test'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('accepts eight characters with a letter and a digit', () {
      expect(Validators.password('Passw0rd'), isNull);
    });

    test('rejects anything shorter than eight', () {
      expect(Validators.password('Pas0'), 'Password must be at least 8 characters');
    });

    test('requires a digit', () {
      expect(Validators.password('Password'), 'Password must contain at least one number');
    });

    test('requires a letter', () {
      expect(Validators.password('12345678'), 'Password must contain at least one letter');
    });

    test('rejects more than 72 characters, matching bcrypt input limits', () {
      expect(Validators.password('a1${'x' * 71}'), 'Password must be at most 72 characters');
    });
  });

  group('Validators.confirmPassword', () {
    test('accepts a match', () {
      expect(Validators.confirmPassword('Passw0rd', 'Passw0rd'), isNull);
    });

    test('rejects a mismatch', () {
      expect(Validators.confirmPassword('Passw0rd', 'Passw0rd!'), 'Passwords do not match');
    });
  });

  group('Validators.phone', () {
    test('accepts an international number', () {
      expect(Validators.phone('+254712345678'), isNull);
    });

    test('accepts a spaced local number', () {
      expect(Validators.phone('0712 345 678'), isNull);
    });

    test('rejects letters', () {
      expect(Validators.phone('not-a-number'), isNotNull);
    });

    test('rejects something too short to dial', () {
      expect(Validators.phone('12345'), isNotNull);
    });
  });

  group('Validators.name', () {
    test('accepts a two-letter name', () {
      expect(Validators.name('Jo', 'First name'), isNull);
    });

    test('rejects a single character', () {
      expect(Validators.name('J', 'First name'), 'First name must be at least 2 characters');
    });

    test('treats whitespace as empty', () {
      expect(Validators.name('   ', 'Last name'), 'Last name is required');
    });
  });

  group('Validators.passwordStrength', () {
    test('scores an empty password zero', () {
      expect(Validators.passwordStrength(''), 0);
    });

    test('rises with length and variety', () {
      final int weak = Validators.passwordStrength('abcd1');
      final int fair = Validators.passwordStrength('abcdefg1');
      final int strong = Validators.passwordStrength('abcdefghijk1!');
      expect(weak, lessThan(fair));
      expect(fair, lessThan(strong));
      expect(strong, 4);
    });

    test('labels every score', () {
      expect(Validators.passwordStrengthLabel(0), '');
      expect(Validators.passwordStrengthLabel(1), 'Weak');
      expect(Validators.passwordStrengthLabel(4), 'Strong');
    });
  });
}
