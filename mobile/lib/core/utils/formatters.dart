import 'package:intl/intl.dart';

/// Every date, duration and greeting the UI renders.
class Formatters {
  const Formatters._();

  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _fullDate = DateFormat('EEEE, d MMMM y');
  static final DateFormat _monthYear = DateFormat('MMMM y');
  static final DateFormat _dateTime = DateFormat('d MMM y, h:mm a');

  /// The server sends UTC ISO-8601; the UI shows local time.
  static DateTime? parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

  static String time(DateTime? value) => value == null ? '—' : _time.format(value);
  static String dayMonth(DateTime? value) => value == null ? '—' : _dayMonth.format(value);
  static String fullDate(DateTime? value) => value == null ? '—' : _fullDate.format(value);
  static String monthYear(DateTime value) => _monthYear.format(value);
  static String dateTime(DateTime? value) => value == null ? '—' : _dateTime.format(value);

  static String timeFromIso(String? iso) => time(parse(iso));
  static String dateTimeFromIso(String? iso) => dateTime(parse(iso));

  /// "just now" · "3 min ago" · "2 h ago" · "Tue" · "14 Mar"
  static String relative(DateTime? value, {DateTime? now}) {
    if (value == null) return '—';
    final DateTime reference = now ?? DateTime.now();
    final Duration difference = reference.difference(value);

    if (difference.isNegative) return 'just now';
    if (difference.inSeconds < 45) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) {
      final int hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    if (difference.inDays == 1) return 'yesterday';
    if (difference.inDays < 7) return DateFormat('EEEE').format(value);
    return _dayMonth.format(value);
  }

  static String relativeFromIso(String? iso, {DateTime? now}) => relative(parse(iso), now: now);

  /// "—" · "about 4 minutes" · "about 1 hour 20 minutes"
  static String waitEstimate(int? minutes) {
    if (minutes == null) return '—';
    if (minutes <= 0) return 'You are next';
    if (minutes < 60) return 'about $minutes ${minutes == 1 ? 'minute' : 'minutes'}';

    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    final String hourPart = '$hours ${hours == 1 ? 'hour' : 'hours'}';
    if (rest == 0) return 'about $hourPart';
    return 'about $hourPart $rest ${rest == 1 ? 'minute' : 'minutes'}';
  }

  /// Compact form for stat tiles: "4 min", "1 h 20 m".
  static String duration(int? minutes) {
    if (minutes == null) return '—';
    if (minutes < 60) return '$minutes min';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest m';
  }

  /// "Good morning" / "Good afternoon" / "Good evening"
  static String greeting({DateTime? now}) {
    final int hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// "5 people" but "1 person".
  static String people(int count) => '$count ${count == 1 ? 'person' : 'people'}';

  /// 1 → "1st", 2 → "2nd", 11 → "11th"
  static String ordinal(int value) {
    if (value <= 0) return '$value';
    if (value % 100 >= 11 && value % 100 <= 13) return '${value}th';
    switch (value % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }

  static String initials(String firstName, String lastName) {
    final String a = firstName.isNotEmpty ? firstName[0] : '';
    final String b = lastName.isNotEmpty ? lastName[0] : '';
    final String result = '$a$b'.toUpperCase();
    return result.isEmpty ? '?' : result;
  }
}
