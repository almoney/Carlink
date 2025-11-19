import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// File logging manager for Carlink
///
/// Implements secure file logging to private app storage following 2025 Android best practices.
/// Uses path_provider for cross-platform compatibility and app-specific storage isolation.
/// No permissions required - files are stored in encrypted, app-specific internal storage.
class FileLogManager {
  static FileLogManager? _instance;
  static FileLogManager get instance => _instance ??= FileLogManager._();

  FileLogManager._();

  // Configuration constants following 2025 best practices
  static const int _maxLogFileSizeMB = 10; // Maximum log file size for mobile
  static const Duration _maxLogFileAge = Duration(
    days: 7,
  ); // Keep logs for 7 days
  static const Duration _flushInterval = Duration(
    seconds: 3,
  ); // Balance performance/data loss
  static const int _bufferSize = 100; // Lines to buffer before write

  // State management
  bool _initialized = false;
  bool _enabled = false;
  String? _sessionId;
  File? _currentLogFile;
  IOSink? _logSink;
  Timer? _flushTimer;

  // Thread-safe buffer management
  final List<String> _logBuffer = [];
  bool _isWriting = false;

  /// Initialize the file logging system
  ///
  /// [enabled] - Whether to start with file logging enabled (default: false)
  /// [sessionPrefix] - Optional prefix for log file names (default: 'carlink')
  ///
  /// Returns true if initialization was successful
  Future<bool> initialize({bool enabled = false, String? sessionPrefix}) async {
    if (_initialized) {
      debugPrint('[FILE_LOG] Already initialized');
      return true;
    }

    try {
      _sessionId = _generateSessionId(sessionPrefix ?? 'carlink');

      if (enabled) {
        await _setupLogging();
      }

      _initialized = true;
      _enabled = enabled;

      debugPrint(
        '[FILE_LOG] Initialized (enabled: $enabled, session: $_sessionId)',
      );

      if (enabled) {
        await _writeLogEntry(
          '[FILE_LOG] File logging session started: $_sessionId',
        );
      }

      return true;
    } catch (e) {
      debugPrint('[FILE_LOG] Initialization failed: $e');
      _enabled = false;
      return false;
    }
  }

  /// Enable or disable file logging
  ///
  /// [enabled] - Whether to enable file logging
  /// Returns true if the operation was successful
  Future<bool> setEnabled(bool enabled) async {
    if (!_initialized) {
      debugPrint(
        '[FILE_LOG] Not initialized - initializing with enabled=$enabled',
      );
      return await initialize(enabled: enabled);
    }

    if (_enabled == enabled) {
      return true; // No change needed
    }

    try {
      if (enabled) {
        await _setupLogging();
        await _writeLogEntry('[FILE_LOG] File logging enabled');
      } else {
        await _writeLogEntry('[FILE_LOG] File logging disabled');
        await _teardownLogging();
      }

      _enabled = enabled;
      debugPrint('[FILE_LOG] File logging ${enabled ? 'enabled' : 'disabled'}');
      return true;
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to change enabled state: $e');
      return false;
    }
  }

  /// Log a message to file (if enabled)
  ///
  /// [message] - The formatted log message to write
  Future<void> logMessage(String message) async {
    if (!_initialized || !_enabled || message.isEmpty) {
      return;
    }

    try {
      await _writeLogEntry(message);
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to log message: $e');
      // Don't disable logging on individual failures
    }
  }

  /// Get current logging status and file information
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final files = await getLogFiles();
      final currentSize =
          _currentLogFile != null && await _currentLogFile!.exists()
          ? await _currentLogFile!.length()
          : 0;

      final totalSize = files.fold<int>(0, (sum, file) {
        try {
          return sum + file.lengthSync();
        } catch (e) {
          return sum;
        }
      });

      return {
        'enabled': _enabled,
        'initialized': _initialized,
        'sessionId': _sessionId,
        'currentFile': _currentLogFile?.path,
        'currentFileSizeBytes': currentSize,
        'currentFileSizeMB': (currentSize / (1024 * 1024)).toStringAsFixed(2),
        'totalFiles': files.length,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'maxFileSizeMB': _maxLogFileSizeMB,
        'maxFileAgeDays': _maxLogFileAge.inDays,
        'bufferSize': _logBuffer.length,
      };
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to get status: $e');
      return {'enabled': _enabled, 'error': e.toString()};
    }
  }

  /// Get list of available log files (newest first)
  Future<List<File>> getLogFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/logs');

      if (!await logDir.exists()) {
        return [];
      }

      final files = await logDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // Sort by modification time (newest first)
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (e) {
          return 0;
        }
      });

      return files;
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to get log files: $e');
      return [];
    }
  }

  /// Get the path to the current log file
  String? getCurrentLogPath() => _currentLogFile?.path;

  /// Clean up old log files based on retention policy (7 days)
  Future<void> cleanupOldLogs() async {
    try {
      final files = await getLogFiles();
      final cutoffTime = DateTime.now().subtract(_maxLogFileAge);
      final List<File> filesToDelete = [];

      for (final file in files) {
        try {
          final lastModified = await file.lastModified();
          if (lastModified.isBefore(cutoffTime)) {
            filesToDelete.add(file);
          }
        } catch (e) {
          debugPrint('[FILE_LOG] Failed to check file age: ${file.path}: $e');
          // If we can't check the file age, consider it for deletion to be safe
          filesToDelete.add(file);
        }
      }

      if (filesToDelete.isEmpty) {
        return;
      }

      int deletedCount = 0;
      for (final file in filesToDelete) {
        try {
          await file.delete();
          deletedCount++;
          debugPrint(
            '[FILE_LOG] Deleted old log file (age check): ${file.path}',
          );
        } catch (e) {
          debugPrint('[FILE_LOG] Failed to delete old log: ${file.path}: $e');
        }
      }

      if (deletedCount > 0) {
        debugPrint(
          '[FILE_LOG] Cleaned up $deletedCount old log files (older than ${_maxLogFileAge.inDays} days)',
        );
      }
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to cleanup logs: $e');
    }
  }

  /// Dispose of all resources and stop file logging
  Future<void> dispose() async {
    try {
      if (_enabled) {
        await _writeLogEntry('[FILE_LOG] File logging session ended');
      }

      await _teardownLogging();

      _initialized = false;
      _enabled = false;

      debugPrint('[FILE_LOG] Disposed');
    } catch (e) {
      debugPrint('[FILE_LOG] Error during dispose: $e');
    }
  }

  // Private implementation methods

  /// Set up logging infrastructure
  Future<void> _setupLogging() async {
    await _createLogFile();
    _startFlushTimer();
  }

  /// Tear down logging infrastructure
  Future<void> _teardownLogging() async {
    _stopFlushTimer();
    await _flushBuffer();
    await _closeLogFile();
  }

  /// Create a new log file for the current session
  Future<void> _createLogFile() async {
    IOSink? tempSink;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/logs');

      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      _currentLogFile = File('${logDir.path}/$_sessionId.log');
      tempSink = _currentLogFile!.openWrite(mode: FileMode.append);

      // Write session header
      await _writeSessionHeader(tempSink);

      // Successfully created, transfer ownership
      _logSink = tempSink;
      tempSink = null;

      // Cleanup old logs
      await cleanupOldLogs();
    } catch (e) {
      // Close temp sink if creation failed
      await tempSink?.close();
      debugPrint('[FILE_LOG] Failed to create log file: $e');
      rethrow;
    }
  }

  /// Write session header information
  Future<void> _writeSessionHeader(IOSink sink) async {
    try {
      final header =
          '''
=== Carlink Logging Session Started ===
Session ID: $_sessionId
Timestamp: ${DateTime.now().toIso8601String()}
Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Debug Mode: ${kDebugMode ? 'true' : 'false'}
Max File Size: ${_maxLogFileSizeMB}MB
Max File Age: ${_maxLogFileAge.inDays} days
========================================

''';

      sink.write(header);
      await sink.flush();
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to write session header: $e');
      rethrow;
    }
  }

  /// Write a log entry to the buffer
  Future<void> _writeLogEntry(String message) async {
    if (_logSink == null) return;

    // Add to buffer
    _logBuffer.add(message);

    // Flush if buffer is full or on important messages
    if (_logBuffer.length >= _bufferSize ||
        message.contains('[ERROR]') ||
        message.contains('[FILE_LOG]')) {
      await _flushBuffer();
    }

    // Check file size and rotate if needed
    await _checkAndRotateLogFile();
  }

  /// Flush the log buffer to file
  Future<void> _flushBuffer() async {
    if (_logSink == null || _logBuffer.isEmpty || _isWriting) {
      return;
    }

    _isWriting = true;

    try {
      for (final entry in _logBuffer) {
        _logSink!.writeln(entry);
      }
      await _logSink!.flush();
      _logBuffer.clear();
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to flush buffer: $e');
    } finally {
      _isWriting = false;
    }
  }

  /// Check file size and rotate if necessary
  Future<void> _checkAndRotateLogFile() async {
    if (_currentLogFile == null) return;

    try {
      final size = await _currentLogFile!.length();
      if (size > _maxLogFileSizeMB * 1024 * 1024) {
        await _rotateLogFile();
      }
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to check file size: $e');
    }
  }

  /// Rotate to a new log file
  Future<void> _rotateLogFile() async {
    try {
      // Write rotation message to current file
      await _writeLogEntry('[FILE_LOG] Log file rotated due to size limit');
      await _flushBuffer();

      // Close current file
      await _closeLogFile();

      // Create new file with incremented session ID
      _sessionId = _generateSessionId('carlink');
      await _createLogFile();

      debugPrint('[FILE_LOG] Log file rotated to new session: $_sessionId');
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to rotate log file: $e');
    }
  }

  /// Close the current log file
  Future<void> _closeLogFile() async {
    try {
      await _flushBuffer();
      await _logSink?.close();
      _logSink = null;
    } catch (e) {
      debugPrint('[FILE_LOG] Failed to close log file: $e');
    }
  }

  /// Start the periodic flush timer
  void _startFlushTimer() {
    _stopFlushTimer();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushBuffer());
  }

  /// Stop the flush timer
  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Generate a unique session ID
  String _generateSessionId(String prefix) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final millis = now.millisecond.toString().padLeft(3, '0');

    return '${prefix}_${dateStr}_${timeStr}_$millis';
  }
}
