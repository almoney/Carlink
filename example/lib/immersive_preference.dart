import 'package:shared_preferences/shared_preferences.dart';
import 'package:carlink/log.dart';

// Manages the immersive mode preference for the Carlink app.
//
// Overview:
// Controls display behavior when projecting to GM AAOS infotainment systems.
// Determines whether the app takes full-screen control (immersive) or defers
// to the Android Automotive OS for display area management (non-immersive).
//
// Display Modes:
// - Immersive (true): Fullscreen with hidden system UI bars. App controls
//   entire display surface. Useful for maximum projection area.
//
// - Non-Immersive (false, default): AAOS manages display bounds, status bars,
//   and navigation areas. Recommended for proper GM infotainment integration.
//
// Usage:
// Setting changes persist across app sessions but require restart to apply.
// Users toggle this via Settings UI when projection display issues occur or
// when full-screen projection is desired.
//
// Technical Details:
// - Storage: SharedPreferences (key: 'immersive_mode_enabled')
// - Default: false (AAOS-managed for compatibility)
// - Target: Android API 32+ (GM AAOS RPO: IOK)
// - Restart required: Changes affect MainActivity window flags at launch
//
class ImmersivePreference {
  static const String _key = 'immersive_mode_enabled';

  static ImmersivePreference? _instance;
  static ImmersivePreference get instance =>
      _instance ??= ImmersivePreference._();

  ImmersivePreference._();

  SharedPreferences? _prefs;

  /// Initialize the preferences manager
  Future<void> initialize() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      logError('Failed to initialize: $e', tag: 'ImmersivePreference');
    }
  }

  /// Returns whether immersive fullscreen mode is enabled.
  /// Returns false by default, allowing AAOS to manage app scaling.
  Future<bool> isEnabled() async {
    await initialize();
    if (_prefs == null) {
      return false;
    }
    return _prefs!.getBool(_key) ?? false;
  }

  /// Sets the immersive mode preference.
  /// Note: App restart required for changes to take effect.
  Future<void> setEnabled(bool enabled) async {
    await initialize();
    if (_prefs == null) {
      throw Exception('SharedPreferences not initialized');
    }
    await _prefs!.setBool(_key, enabled);
  }
}
