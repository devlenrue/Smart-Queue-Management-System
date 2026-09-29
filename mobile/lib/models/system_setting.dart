import '../core/utils/json.dart';

/// One row of `system_settings` (§14).
///
/// Values are stored as text on the server — `250` comes back as `"250"` and
/// `false` as `"false"` — so the client keeps them as strings and only
/// interprets them where it needs to (the toggles below).
class SystemSetting {
  const SystemSetting({
    required this.key,
    required this.value,
    this.description,
    this.updatedAt,
  });

  final String key;
  final String value;
  final String? description;
  final String? updatedAt;

  factory SystemSetting.fromJson(Map<String, dynamic> json) {
    return SystemSetting(
      key: Json.asString(json['key']),
      value: Json.asString(json['value']),
      description: Json.asStringOrNull(json['description']),
      updatedAt: Json.asStringOrNull(json['updatedAt']),
    );
  }

  /// `institution_name` → `Institution name`; `display.banner` → `Display
  /// banner`. Keeps the settings screen readable without a hand-maintained
  /// label table that would go stale the moment somebody adds a key.
  String get label {
    final String words = key.replaceAll(RegExp(r'[._]'), ' ').trim();
    if (words.isEmpty) return key;
    return words[0].toUpperCase() + words.substring(1);
  }

  bool get isBoolean => value == 'true' || value == 'false';
  bool get asBool => value == 'true';
  bool get isNumeric => num.tryParse(value) != null;

  SystemSetting copyWith({String? value}) => SystemSetting(
        key: key,
        value: value ?? this.value,
        description: description,
        updatedAt: updatedAt,
      );
}
