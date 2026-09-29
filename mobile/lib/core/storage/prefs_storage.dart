import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Non-secret preferences: theme mode and polling interval.
///
/// Kept apart from [SecureStorage] so it is obvious at a glance which values
/// are sensitive and which are merely convenient.
class PrefsStorage {
  PrefsStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStorage> create() async {
    return PrefsStorage(await SharedPreferences.getInstance());
  }

  ThemeMode readThemeMode() {
    switch (_prefs.getString(AppConstants.themeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> writeThemeMode(ThemeMode mode) {
    return _prefs.setString(AppConstants.themeModeKey, mode.name);
  }

  /// Clamped, because a 1-second poll would hammer the server and a 5-minute
  /// one would make the ticket screen look broken.
  Duration readPollInterval() {
    final int seconds = _prefs.getInt(AppConstants.pollSecondsKey) ??
        AppConstants.ticketPollInterval.inSeconds;
    return Duration(seconds: seconds.clamp(3, 60));
  }

  Future<void> writePollInterval(Duration interval) {
    return _prefs.setInt(AppConstants.pollSecondsKey, interval.inSeconds.clamp(3, 60));
  }
}
