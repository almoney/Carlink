import 'package:flutter/widgets.dart';
import 'log.dart';

/// Manages logging system lifecycle with Flutter app state changes
///
/// This class implements WidgetsBindingObserver to properly handle
/// logging operations during app lifecycle transitions for automotive use.
class LoggingLifecycleManager with WidgetsBindingObserver {
  static LoggingLifecycleManager? _instance;
  static LoggingLifecycleManager get instance =>
      _instance ??= LoggingLifecycleManager._();

  LoggingLifecycleManager._();

  bool _initialized = false;

  /// Initialize the lifecycle manager
  ///
  /// Call this during app startup to register the observer
  void initialize() {
    if (_initialized) return;

    WidgetsBinding.instance.addObserver(this);
    _initialized = true;

    logInfo('Logging lifecycle manager initialized', tag: 'LIFECYCLE');
  }

  /// Dispose the lifecycle manager
  ///
  /// Call this during app shutdown to clean up resources
  void dispose() {
    if (!_initialized) return;

    WidgetsBinding.instance.removeObserver(this);
    _initialized = false;

    logInfo('Logging lifecycle manager disposed', tag: 'LIFECYCLE');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        logInfo('App resumed - logging active', tag: 'LIFECYCLE');
        break;

      case AppLifecycleState.inactive:
        logInfo('App inactive - maintaining logging', tag: 'LIFECYCLE');
        break;

      case AppLifecycleState.paused:
        logInfo('App paused - flushing logs', tag: 'LIFECYCLE');
        // Flush any pending logs before app goes to background
        flushLogQueue();
        break;

      case AppLifecycleState.detached:
        logInfo('App detached - disposing logging', tag: 'LIFECYCLE');
        // Clean shutdown of logging system
        _performCleanShutdown();
        break;

      case AppLifecycleState.hidden:
        logInfo('App hidden - maintaining logging', tag: 'LIFECYCLE');
        break;
    }
  }

  /// Perform clean shutdown of logging system
  Future<void> _performCleanShutdown() async {
    try {
      // Flush any remaining logs
      await flushLogQueue();

      // Dispose file logging resources
      await disposeFileLogging();

      logInfo('Logging system shutdown complete', tag: 'LIFECYCLE');
    } catch (e) {
      // Final error log - avoid recursion by using debugPrint instead of logging system
      debugPrint('[LIFECYCLE] Error during logging shutdown: $e');
    }
  }

  /// Get current lifecycle status
  Map<String, dynamic> getStatus() {
    return {
      'initialized': _initialized,
      'observerRegistered': _initialized,
      'currentState': WidgetsBinding.instance.lifecycleState?.name,
    };
  }
}
