import 'package:flutter_test/flutter_test.dart';
import 'package:smartqueue/core/utils/formatters.dart';

void main() {
  group('waitEstimate', () {
    test('tells the next person they are next rather than "0 minutes"', () {
      expect(Formatters.waitEstimate(0), 'You are next');
    });

    test('uses the singular for one minute', () {
      expect(Formatters.waitEstimate(1), 'about 1 minute');
    });

    test('reads minutes under an hour', () {
      expect(Formatters.waitEstimate(25), 'about 25 minutes');
    });

    test('splits into hours and minutes past sixty', () {
      expect(Formatters.waitEstimate(80), 'about 1 hour 20 minutes');
      expect(Formatters.waitEstimate(120), 'about 2 hours');
    });

    test('shows a dash when the server sent nothing', () {
      expect(Formatters.waitEstimate(null), '—');
    });
  });

  group('duration', () {
    test('is compact for tiles', () {
      expect(Formatters.duration(7), '7 min');
      expect(Formatters.duration(60), '1 h');
      expect(Formatters.duration(95), '1 h 35 m');
    });
  });

  group('ordinal', () {
    test('handles the irregular ones', () {
      expect(Formatters.ordinal(1), '1st');
      expect(Formatters.ordinal(2), '2nd');
      expect(Formatters.ordinal(3), '3rd');
      expect(Formatters.ordinal(4), '4th');
    });

    test('handles the teens, which are all "th"', () {
      expect(Formatters.ordinal(11), '11th');
      expect(Formatters.ordinal(12), '12th');
      expect(Formatters.ordinal(13), '13th');
    });

    test('handles larger numbers', () {
      expect(Formatters.ordinal(21), '21st');
      expect(Formatters.ordinal(112), '112th');
    });
  });

  group('relative', () {
    final DateTime now = DateTime(2026, 9, 29, 12, 0);

    test('collapses the last minute to "just now"', () {
      expect(Formatters.relative(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    });

    test('counts minutes', () {
      expect(Formatters.relative(now.subtract(const Duration(minutes: 7)), now: now), '7 min ago');
    });

    test('counts hours', () {
      expect(Formatters.relative(now.subtract(const Duration(hours: 3)), now: now), '3 hours ago');
      expect(Formatters.relative(now.subtract(const Duration(hours: 1)), now: now), '1 hour ago');
    });

    test('says yesterday', () {
      expect(Formatters.relative(now.subtract(const Duration(days: 1)), now: now), 'yesterday');
    });

    test('shows a dash for null', () {
      expect(Formatters.relative(null, now: now), '—');
    });
  });

  group('people', () {
    test('uses the singular for one', () {
      expect(Formatters.people(1), '1 person');
      expect(Formatters.people(0), '0 people');
      expect(Formatters.people(4), '4 people');
    });
  });

  group('initials', () {
    test('takes the first letter of each name', () {
      expect(Formatters.initials('John', 'Doe'), 'JD');
    });

    test('never returns an empty string', () {
      expect(Formatters.initials('', ''), '?');
    });
  });

  group('greeting', () {
    test('changes across the day', () {
      expect(Formatters.greeting(now: DateTime(2026, 9, 29, 8)), 'Good morning');
      expect(Formatters.greeting(now: DateTime(2026, 9, 29, 14)), 'Good afternoon');
      expect(Formatters.greeting(now: DateTime(2026, 9, 29, 20)), 'Good evening');
    });
  });
}
