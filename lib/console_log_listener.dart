import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Console-only logging listener for Carlink
///
/// This class provides console logging functionality without any file I/O operations.
/// All log messages are output to the console for debugging and monitoring purposes.
class ConsoleLogListener {
  static bool _initialized = false;
  static String? _sessionId;

  /// Initialize console logging
  ///
  /// Sets up the logging system with a unique session identifier
  /// for tracking log sessions in the console output.
  static Future<void> initialize() async {
    if (_initialized) return;

    _sessionId = _generateSessionId();
    _initialized = true;

    // Log initialization message to console
    _logToConsole('[CONSOLE_LOGGER] Console logging initialized');
    _logToConsole('[CONSOLE_LOGGER] Session: $_sessionId');
    _logToConsole('[CONSOLE_LOGGER] Output: Console only');
  }

  /// Log a message to console with timestamp and formatting
  ///
  /// [message] - The message to log
  /// [tag] - Optional tag for categorizing messages (defaults to 'CARLINK')
  static void logMessage(String message, {String tag = 'CARLINK'}) {
    if (!_initialized) {
      initialize();
    }

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final formattedMessage = '$timestamp > [$tag] $message';

    _logToConsole(formattedMessage);
  }

  /// Internal method to output messages to console
  static void _logToConsole(String message) {
    // Use developer.log for better console output in debug mode
    if (kDebugMode) {
      developer.log(message);
      // Also use debugPrint for compatibility with different logging systems
      debugPrint(message);
    }
  }

  /// Generate a unique session identifier
  static String _generateSessionId() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
  }

  /// Get current session information for debugging
  static Map<String, dynamic> getSessionInfo() {
    return {
      'initialized': _initialized,
      'sessionId': _sessionId,
      'outputMode': 'console-only',
    };
  }

  /// Reset the logging system (useful for testing)
  static void reset() {
    _initialized = false;
    _sessionId = null;
  }
}
