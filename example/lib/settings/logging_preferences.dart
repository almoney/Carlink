import 'package:shared_preferences/shared_preferences.dart';
import 'package:carlink/log.dart';

/// Manages persistent storage of logging preferences
///
/// Stores user's logging preferences across app sessions using SharedPreferences.
/// Handles log level, enabled state, and user's explicit actions.
class LoggingPreferences {
  static const String _keyLogLevel = 'carlink_log_level';
  static const String _keyLoggingEnabled = 'carlink_logging_enabled';
  static const String _keyUserHasDisabled = 'carlink_user_has_disabled';
  static const String _keyFirstLaunch = 'carlink_first_launch';
  static const String _keyLastUserAction = 'carlink_last_user_action';

  static LoggingPreferences? _instance;
  static LoggingPreferences get instance =>
      _instance ??= LoggingPreferences._();

  LoggingPreferences._();

  SharedPreferences? _prefs;

  /// Initialize the preferences manager
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get the saved log level, defaults to Silent
  Future<LogPreset> getLogLevel() async {
    await initialize();
    final levelIndex = _prefs!.getInt(_keyLogLevel) ?? LogPreset.silent.index;

    // Ensure the index is valid
    if (levelIndex < 0 || levelIndex >= LogPreset.values.length) {
      return LogPreset.silent;
    }

    return LogPreset.values[levelIndex];
  }

  /// Save the user's preferred log level
  Future<void> setLogLevel(LogPreset level) async {
    await initialize();
    await _prefs!.setInt(_keyLogLevel, level.index);
    await _recordUserAction();
  }

  /// Get whether logging is enabled
  Future<bool> isLoggingEnabled() async {
    await initialize();
    return _prefs!.getBool(_keyLoggingEnabled) ?? true; // Default to enabled
  }

  /// Set whether logging is enabled
  Future<void> setLoggingEnabled(bool enabled) async {
    await initialize();
    await _prefs!.setBool(_keyLoggingEnabled, enabled);
    await _recordUserAction();
  }

  /// Get whether user has explicitly disabled logging
  Future<bool> hasUserExplicitlyDisabled() async {
    await initialize();
    return _prefs!.getBool(_keyUserHasDisabled) ?? false;
  }

  /// Set that user has explicitly disabled logging
  Future<void> setUserHasExplicitlyDisabled(bool disabled) async {
    await initialize();
    await _prefs!.setBool(_keyUserHasDisabled, disabled);
    if (disabled) {
      await _recordUserAction();
    }
  }

  /// Check if this is the first app launch
  Future<bool> isFirstLaunch() async {
    await initialize();
    final isFirst = _prefs!.getBool(_keyFirstLaunch) ?? true;

    // Mark as not first launch after checking
    if (isFirst) {
      await _prefs!.setBool(_keyFirstLaunch, false);
    }

    return isFirst;
  }

  /// Get the timestamp of the last user action
  Future<DateTime?> getLastUserAction() async {
    await initialize();
    final timestamp = _prefs!.getInt(_keyLastUserAction);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  /// Record the current time as the last user action
  Future<void> _recordUserAction() async {
    await initialize();
    await _prefs!
        .setInt(_keyLastUserAction, DateTime.now().millisecondsSinceEpoch);
  }

  /// Check if user has made any logging configuration within the last session
  Future<bool> hasRecentUserConfiguration() async {
    final lastAction = await getLastUserAction();
    if (lastAction == null) return false;

    // Consider actions within the last 24 hours as "recent"
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return lastAction.isAfter(cutoff);
  }

  /// Get a summary of current preferences for debugging
  Future<Map<String, dynamic>> getPreferencesSummary() async {
    await initialize();

    return {
      'logLevel': (await getLogLevel()).name,
      'loggingEnabled': await isLoggingEnabled(),
      'userHasDisabled': await hasUserExplicitlyDisabled(),
      'isFirstLaunch': _prefs!.getBool(_keyFirstLaunch) ?? true,
      'lastUserAction': await getLastUserAction(),
      'hasRecentConfig': await hasRecentUserConfiguration(),
    };
  }

  /// Reset all preferences to defaults (for testing)
  Future<void> resetToDefaults() async {
    await initialize();
    await _prefs!.remove(_keyLogLevel);
    await _prefs!.remove(_keyLoggingEnabled);
    await _prefs!.remove(_keyUserHasDisabled);
    await _prefs!.remove(_keyFirstLaunch);
    await _prefs!.remove(_keyLastUserAction);
  }

  /// Apply saved preferences to the logging system
  ///
  /// This method should be called on app startup to restore user's settings
  Future<void> applySavedPreferences() async {
    try {
      final level = await getLogLevel();
      final enabled = await isLoggingEnabled();

      // Apply the saved log level
      setLogPreset(level);

      // Apply the saved logging state if available
      if (!enabled) {
        await setFileLoggingEnabled(false);
      } else {
        await setFileLoggingEnabled(true);
      }

      final summary = await getPreferencesSummary();
      log('Applied saved preferences: $summary', tag: 'LOGGING_PREFS');
    } catch (e) {
      log('Failed to apply saved preferences: $e', tag: 'LOGGING_PREFS');
    }
  }
}
