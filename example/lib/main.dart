// Dart entry point for the Carlink app
//
// Initializes console and file logging systems, manages app lifecycle for proper
// resource cleanup, and launches the main UI.
//

import 'package:carlink/log.dart';
import 'package:carlink/console_log_listener.dart';
import 'package:carlink_example/main_page.dart';
import 'package:carlink_example/settings/logging_preferences.dart';
import 'package:carlink_example/immersive_preference.dart';
import 'package:carlink_example/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize console logging system
  await ConsoleLogListener.initialize();

  // Initialize logging preferences system
  await LoggingPreferences.instance.initialize();

  // Initialize file logging system and apply saved preferences
  await initializeFileLogging(enabled: false, sessionPrefix: 'carlink');

  // Apply saved user preferences for logging
  await LoggingPreferences.instance.applySavedPreferences();

  ConsoleLogListener.logMessage("Starting Flutter application session");
  ConsoleLogListener.logMessage("---");
  ConsoleLogListener.logMessage("Console logging ENABLED",
      tag: 'CONSOLE_LOGGER');
  logInfo("Logging preferences loaded and applied", tag: 'FILE_LOG');

  // Initialize immersive mode based on user preference BEFORE runApp
  // This ensures the viewport is correctly sized before the first build
  final isImmersiveEnabled = await ImmersivePreference.instance.isEnabled();
  if (isImmersiveEnabled) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    logInfo('[IMMERSIVE] Enabled fullscreen immersive mode', tag: 'MAIN');
  } else {
    logInfo('[IMMERSIVE] Non-immersive mode - AAOS managing system UI',
        tag: 'MAIN');
  }

  // Wait 2 seconds for AAOS and immersive mode to fully stabilize
  // This ensures:
  // - Immersive mode animation completes (300ms)
  // - MediaQuery receives updated window metrics
  // - AAOS system services initialize (1000ms)
  // - App lifecycle reaches stable 'resumed' state
  // - USB permission dialog won't auto-dismiss during adapter initialization
  logInfo('[STARTUP] Waiting 2 seconds for system stabilization...',
      tag: 'MAIN');
  await Future.delayed(const Duration(milliseconds: 2000));
  logInfo('[STARTUP] System stabilized, launching app UI', tag: 'MAIN');

  // Request microphone permission on first launch
  await _requestMicrophonePermissionOnFirstLaunch();

  runApp(const MainApp());
}

const String _kMicPermissionRequestedKey = 'mic_permission_requested';

/// Request microphone permission on first launch only.
/// Uses SharedPreferences to track whether we've already asked.
Future<void> _requestMicrophonePermissionOnFirstLaunch() async {
  final prefs = await SharedPreferences.getInstance();
  final alreadyRequested = prefs.getBool(_kMicPermissionRequestedKey) ?? false;

  if (alreadyRequested) {
    logInfo('[PERMISSION] Microphone permission already requested previously',
        tag: 'MAIN');
    return;
  }

  logInfo('[PERMISSION] First launch - requesting microphone permission',
      tag: 'MAIN');

  final status = await Permission.microphone.request();
  await prefs.setBool(_kMicPermissionRequestedKey, true);

  logInfo('[PERMISSION] Microphone permission result: $status', tag: 'MAIN');
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Dispose file logging resources
    disposeFileLogging();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is being terminated, ensure file logging is properly closed
      disposeFileLogging();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: const MainPage(),
      );
}
