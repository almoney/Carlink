import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'file_log_manager.dart';
import 'logging_lifecycle_manager.dart';

// Export lifecycle manager for easy access
export 'logging_lifecycle_manager.dart';

enum LogLevel { debug, info, warn, error }

final Map<LogLevel, bool> _logLevels = {
  LogLevel.debug: true,
  LogLevel.info: true,
  LogLevel.warn: true,
  LogLevel.error: true,
};

// Global logging control
bool logEnabled = true;

// Debug console control (follows Flutter best practices)
bool _debugConsoleEnabled = true;

// Queue management for non-blocking logging (follows Dart best practices)
final Queue<String> _logQueue = ListQueue<String>();
const int _maxQueueSize = 10000;
Completer<void>? _queueProcessingLock;

// Tag-specific logging control
final Map<String, bool> _tagFilters = <String, bool>{
  'USB': true, // USB device operations
  'USB_RAW': false, // Raw USB messages (excluding video/audio)
  'VIDEO': false, // Video data and processing
  'AUDIO': false, // Audio data and processing
  'H264_RENDERER': true, // H264 video renderer operations
  'PLATFORM': true, // Platform interface layer
  'SERIALIZE': true, // Message serialization
  'COMMAND': true, // Protocol commands
  'TOUCH': true, // Touch events
  'CONFIG': true, // Configuration messages
  'ADAPTR': true, // Adapter driver operations
  'PHONE': true, // Phone detection
  'MEDIA': true, // Media data
  'BOX': true, // Box info
  'FILE_LOG': true, // File logging system
  'LOGS_TAB': true, // Logs tab UI operations
  'LOGGING_PREFS': true, // Logging preferences management
};

// Performance logging presets
enum LogPreset {
  silent, // Only errors
  minimal, // Errors + warnings + critical info
  normal, // Standard operational logging
  debug, // Full debug logging
  performance, // Performance metrics only
  rxMessages, // Raw USB messages (excluding video/audio)
  videoOnly, // Video-related events only (including raw video messages)
  audioOnly, // Audio-related events only (including raw audio messages)
}

/// Extension methods for LogPreset to provide UI display information.
/// Consolidates display logic that was previously duplicated across UI code.
extension LogPresetDisplay on LogPreset {
  /// User-friendly display name for UI components
  String get displayName {
    switch (this) {
      case LogPreset.silent:
        return 'Silent';
      case LogPreset.minimal:
        return 'Minimal';
      case LogPreset.normal:
        return 'Normal';
      case LogPreset.performance:
        return 'Performance';
      case LogPreset.debug:
        return 'Debug';
      case LogPreset.rxMessages:
        return 'Adapter Messages';
      case LogPreset.videoOnly:
        return 'Video Only';
      case LogPreset.audioOnly:
        return 'Audio Only';
    }
  }

  /// Color for UI display components
  Color get color {
    switch (this) {
      case LogPreset.silent:
        return const Color(0xFFE57373); // red[300]
      case LogPreset.minimal:
        return const Color(0xFFFFB74D); // orange[300]
      case LogPreset.normal:
        return const Color(0xFF64B5F6); // blue[300]
      case LogPreset.performance:
        return const Color(0xFFBA68C8); // purple[300]
      case LogPreset.debug:
        return const Color(0xFF4DD0E1); // cyan[300]
      case LogPreset.rxMessages:
        return const Color(0xFF7986CB); // indigo[300]
      case LogPreset.videoOnly:
        return const Color(0xFF81C784); // green[300]
      case LogPreset.audioOnly:
        return const Color(0xFFFFD54F); // amber[300]
    }
  }

  /// Description of what this preset logs
  String get description {
    switch (this) {
      case LogPreset.silent:
        return 'Only errors';
      case LogPreset.minimal:
        return 'Errors + warnings';
      case LogPreset.normal:
        return 'Standard operational logging';
      case LogPreset.performance:
        return 'Performance metrics only';
      case LogPreset.debug:
        return 'Full debug (no raw data dumps)';
      case LogPreset.rxMessages:
        return 'Raw messages (no video/audio)';
      case LogPreset.videoOnly:
        return 'Video events + raw video data';
      case LogPreset.audioOnly:
        return 'Audio events + raw audio data';
    }
  }
}

void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
  if (!logEnabled || _logLevels[level] != true) return;

  // Check tag filter
  if (tag != null && _tagFilters.containsKey(tag) && _tagFilters[tag] != true) {
    return;
  }

  final tagStr = tag != null ? '[$tag] ' : '';
  final now = DateTime.now();
  final timestamp =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
  final formatted = '$timestamp > $tagStr$message';

  // Console output only in debug mode (follows Flutter best practices)
  if (kDebugMode && _debugConsoleEnabled) {
    debugPrint(formatted);
  }
  logListener?.call(formatted);

  // Queue-based non-blocking file logging with size limit
  if (_logQueue.length >= _maxQueueSize) {
    _logQueue.removeFirst(); // Drop oldest message
    if (kDebugMode) {
      debugPrint('[LOG] Queue overflow - dropping oldest message');
    }
  }
  _logQueue.add(formatted);
  _processLogQueue();
}

void logDebug(String message, {String? tag}) =>
    log(message, level: LogLevel.debug, tag: tag);
void logInfo(String message, {String? tag}) =>
    log(message, level: LogLevel.info, tag: tag);
void logWarn(String message, {String? tag}) =>
    log(message, level: LogLevel.warn, tag: tag);
void logError(String message, {String? tag}) =>
    log(message, level: LogLevel.error, tag: tag);

// Queue processing functions (follows Dart ListQueue best practices)

/// Process the log queue in a non-blocking manner
///
/// Uses proper synchronization to prevent race conditions
Future<void> _processLogQueue() async {
  // Check if processing is already in progress
  if (_queueProcessingLock != null) {
    await _queueProcessingLock!.future;
    return;
  }

  if (_logQueue.isEmpty) return;

  // Create lock to prevent concurrent processing
  _queueProcessingLock = Completer<void>();

  try {
    const int batchSize = 10;

    // Process queue in batches for better performance
    while (_logQueue.isNotEmpty) {
      final batch = <String>[];

      // Collect batch of messages
      for (int i = 0; i < batchSize && _logQueue.isNotEmpty; i++) {
        batch.add(_logQueue.removeFirst());
      }

      // Process batch
      for (final message in batch) {
        FileLogManager.instance.logMessage(message);
      }

      // Yield control only between batches
      if (_logQueue.isNotEmpty) {
        await Future.delayed(Duration.zero);
      }
    }
  } catch (e) {
    // Log processing error to debug console if available
    if (kDebugMode && _debugConsoleEnabled) {
      debugPrint('Log queue processing error: $e');
    }
  } finally {
    // Release lock
    final lock = _queueProcessingLock;
    _queueProcessingLock = null;
    lock?.complete();
  }
}

// Level control
void setLogLevel(LogLevel level, bool enabled) {
  _logLevels[level] = enabled;
}

// Tag control
void setTagEnabled(String tag, bool enabled) {
  _tagFilters[tag] = enabled;
}

// Bulk tag control
void setTagsEnabled(List<String> tags, bool enabled) {
  for (final tag in tags) {
    _tagFilters[tag] = enabled;
  }
}

// Check if a tag is enabled
bool isTagEnabled(String tag) {
  return _tagFilters[tag] ?? false;
}

// Preset configurations
void setLogPreset(LogPreset preset) {
  switch (preset) {
    case LogPreset.silent:
      logEnabled = true;
      _logLevels[LogLevel.debug] = false;
      _logLevels[LogLevel.info] = false;
      _logLevels[LogLevel.warn] = false;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => false);
      break;

    case LogPreset.minimal:
      logEnabled = true;
      _logLevels[LogLevel.debug] = false;
      _logLevels[LogLevel.info] = false;
      _logLevels[LogLevel.warn] = true;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => true);
      // Disable noisy tags
      setTagsEnabled(['SERIALIZE', 'TOUCH', 'AUDIO', 'MEDIA'], false);
      break;

    case LogPreset.normal:
      logEnabled = true;
      _logLevels[LogLevel.debug] = false;
      _logLevels[LogLevel.info] = true;
      _logLevels[LogLevel.warn] = true;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => true);
      // Disable very noisy tags
      setTagsEnabled(['SERIALIZE', 'TOUCH', 'MEDIA'], false);
      break;

    case LogPreset.debug:
      logEnabled = true;
      _logLevels.updateAll((key, value) => true);
      _tagFilters.updateAll((key, value) => true);
      // Disable raw data dumps to prevent file bloat (use Video Only, Audio Only, or Adapter Messages for raw data)
      setTagsEnabled(['VIDEO', 'AUDIO', 'USB_RAW'], false);
      break;

    case LogPreset.performance:
      logEnabled = true;
      _logLevels[LogLevel.debug] = false;
      _logLevels[LogLevel.info] = true;
      _logLevels[LogLevel.warn] = true;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => false);
      // Enable only performance-related tags
      setTagsEnabled(['USB', 'ADAPTR', 'PLATFORM'], true);
      break;

    case LogPreset.rxMessages:
      logEnabled = true;
      _logLevels[LogLevel.debug] = true;
      _logLevels[LogLevel.info] = true;
      _logLevels[LogLevel.warn] = true;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => false);
      // Enable only raw message logging with minimal noise
      setTagsEnabled(['USB_RAW', 'USB', 'ADAPTR'], true);
      break;

    case LogPreset.videoOnly:
      logEnabled = true;
      _logLevels[LogLevel.debug] = true;
      _logLevels[LogLevel.info] = true;
      _logLevels[LogLevel.warn] = true;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => false);
      // Enable only video-related logging (including raw video messages)
      setTagsEnabled(['VIDEO', 'USB', 'PLATFORM', 'CONFIG'], true);
      break;

    case LogPreset.audioOnly:
      logEnabled = true;
      _logLevels[LogLevel.debug] = true;
      _logLevels[LogLevel.info] = true;
      _logLevels[LogLevel.warn] = true;
      _logLevels[LogLevel.error] = true;
      _tagFilters.updateAll((key, value) => false);
      // Enable only audio-related logging (including raw audio messages)
      setTagsEnabled(['AUDIO', 'USB', 'PLATFORM', 'CONFIG'], true);
      break;
  }
}

// Quick disable functions for common scenarios
void disableDebugLogs() => setLogLevel(LogLevel.debug, false);
void disablePerformanceLogs() =>
    setTagsEnabled(['USB', 'DONGLE', 'PLATFORM'], false);
void disableProtocolLogs() =>
    setTagsEnabled(['SERIALIZE', 'COMMAND', 'CONFIG'], false);
void disableMediaLogs() => setTagsEnabled(['AUDIO', 'MEDIA', 'TOUCH'], false);

// Global disable
void disableAllLogs() => logEnabled = false;
void enableAllLogs() => logEnabled = true;

// Status reporting
Map<String, dynamic> getLoggingStatus() {
  return {
    'enabled': logEnabled,
    'levels': Map.from(_logLevels),
    'tags': Map.from(_tagFilters),
    'debugConsole': {
      'enabled': _debugConsoleEnabled,
      'active': isConsoleOutputActive,
      'debugMode': kDebugMode,
    },
    'queue': {
      'size': _logQueue.length,
      'maxSize': _maxQueueSize,
      'processing': _queueProcessingLock != null,
      'isEmpty': _logQueue.isEmpty,
    },
  };
}

Function(String)? logListener;

// Debug console control functions (follows Flutter best practices)

/// Enable or disable debug console output
///
/// [enabled] - Whether to enable console output in debug mode
/// Note: Console output is automatically disabled in release builds
void setDebugConsoleEnabled(bool enabled) {
  _debugConsoleEnabled = enabled;
}

/// Get current debug console status
///
/// Returns true if console output is enabled AND app is in debug mode
bool get isDebugConsoleEnabled => kDebugMode && _debugConsoleEnabled;

/// Check if console output would be active
///
/// Returns true only if both debug mode and console output are enabled
bool get isConsoleOutputActive => kDebugMode && _debugConsoleEnabled;

// Queue management functions (follows Dart ListQueue best practices)

/// Force process any remaining items in the log queue
///
/// Useful for ensuring all logs are written before app shutdown
Future<void> flushLogQueue() async {
  await _processLogQueue();
}

/// Get current queue status for monitoring
///
/// Returns queue size and processing state
Map<String, dynamic> getQueueStatus() {
  return {
    'size': _logQueue.length,
    'maxSize': _maxQueueSize,
    'processing': _queueProcessingLock != null,
    'isEmpty': _logQueue.isEmpty,
  };
}

/// Clear the log queue (emergency cleanup)
///
/// Use with caution - this will discard pending log messages
void clearLogQueue() {
  _logQueue.clear();
}

// File logging control functions

/// Initialize the file logging system
///
/// [enabled] - Whether to start with file logging enabled (default: false)
/// [sessionPrefix] - Optional prefix for log file names (default: 'carlink')
/// Returns true if initialization was successful
Future<bool> initializeFileLogging({
  bool enabled = false,
  String? sessionPrefix,
}) async {
  return await FileLogManager.instance.initialize(
    enabled: enabled,
    sessionPrefix: sessionPrefix,
  );
}

/// Enable or disable file logging
///
/// [enabled] - Whether to enable file logging
/// Returns true if the operation was successful
Future<bool> setFileLoggingEnabled(bool enabled) async {
  return await FileLogManager.instance.setEnabled(enabled);
}

/// Get current file logging status and information
Future<Map<String, dynamic>> getFileLoggingStatus() async {
  return await FileLogManager.instance.getStatus();
}

/// Get list of available log files (newest first)
Future<List<String>> getLogFiles() async {
  final files = await FileLogManager.instance.getLogFiles();
  return files.map((f) => f.path).toList();
}

/// Get the path to the current log file (if any)
String? getCurrentLogFilePath() {
  return FileLogManager.instance.getCurrentLogPath();
}

/// Clean up old log files based on retention policy
Future<void> cleanupOldLogFiles() async {
  await FileLogManager.instance.cleanupOldLogs();
}

/// Dispose of file logging resources (call on app shutdown)
Future<void> disposeFileLogging() async {
  await FileLogManager.instance.dispose();
}

/// Initialize the complete logging system with lifecycle management
///
/// [fileLoggingEnabled] - Whether to enable file logging (default: false)
/// [sessionPrefix] - Optional prefix for log file names (default: 'carlink')
/// Returns true if initialization was successful
Future<bool> initializeLoggingSystem({
  bool fileLoggingEnabled = false,
  String? sessionPrefix,
}) async {
  try {
    // Initialize file logging
    final fileResult = await initializeFileLogging(
      enabled: fileLoggingEnabled,
      sessionPrefix: sessionPrefix,
    );

    // Initialize lifecycle management
    LoggingLifecycleManager.instance.initialize();

    logInfo('Logging system initialized', tag: 'SYSTEM');
    logInfo(
      'File logging: ${fileLoggingEnabled ? 'enabled' : 'disabled'}',
      tag: 'SYSTEM',
    );

    return fileResult;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[LOG] Failed to initialize logging system: $e');
    }
    return false;
  }
}

/// Dispose the complete logging system (call on app shutdown)
Future<void> disposeLoggingSystem() async {
  try {
    logInfo('Disposing logging system', tag: 'SYSTEM');

    // Dispose lifecycle manager
    LoggingLifecycleManager.instance.dispose();

    // Dispose file logging
    await disposeFileLogging();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[LOG] Error disposing logging system: $e');
    }
  }
}
