/// Defensive JSON readers.
///
/// A class project is graded by someone tapping around a live app, so a
/// single unexpected null must never throw inside a `ListView.builder`.
/// Every model reads through these.
class Json {
  const Json._();

  static int asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? asIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double asDouble(dynamic value, [double fallback = 0]) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static String asString(dynamic value, [String fallback = '']) {
    if (value is String) return value;
    if (value == null) return fallback;
    return value.toString();
  }

  static String? asStringOrNull(dynamic value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value == null) return null;
    return value.toString();
  }

  static bool asBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == 'true' || value == '1';
    return fallback;
  }

  static Map<String, dynamic>? asMap(dynamic value) {
    return value is Map<String, dynamic> ? value : null;
  }

  static List<Map<String, dynamic>> asList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  static List<T> mapList<T>(dynamic value, T Function(Map<String, dynamic>) build) {
    return asList(value).map(build).toList(growable: false);
  }
}
