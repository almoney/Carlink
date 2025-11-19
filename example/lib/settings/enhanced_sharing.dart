import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:carlink/file_log_manager.dart';

/// Enhanced sharing functionality with improved reliability for AAOS
class EnhancedSharing {
  // Timeout configuration constants
  static const Duration _shareTimeout = Duration(seconds: 15);
  static const Duration _shareTimeoutAAOS = Duration(seconds: 20);
  static const Duration _canShareTestTimeout = Duration(milliseconds: 100);
  static const int _maxShareSizeBytes =
      100 * 1024 * 1024; // 100MB warning threshold

  /// Share files with enhanced progress dialog and retry mechanism
  ///
  /// Returns true if the share dialog was successfully opened, false otherwise
  static Future<bool> shareFilesWithProgress({
    required BuildContext context,
    required List<File> files,
    required String operationName,
    String? shareText,
  }) async {
    if (files.isEmpty) {
      throw Exception('No files to share');
    }

    // Perform the share operation directly
    return await _performShare(files, shareText);
  }

  /// Perform the actual share operation with enhanced error handling
  static Future<bool> _performShare(List<File> files, String? shareText) async {
    try {
      // Validate all files before sharing
      await _validateFilesForSharing(files);

      // Create XFiles from File objects
      final xFiles = files.map((file) => XFile(file.path)).toList();

      // Attempt to share with a reasonable timeout using new SharePlus API
      await SharePlus.instance
          .share(
        ShareParams(
          files: xFiles,
          text: shareText ?? 'Carlink Debug Logs (${files.length} files)',
        ),
      )
          .timeout(
        _shareTimeout,
        onTimeout: () {
          throw TimeoutException(
              'Share operation timed out after ${_shareTimeout.inSeconds}s');
        },
      );

      // Note: share_plus doesn't return a boolean success indicator
      // The fact that it completes without throwing means the share dialog opened
      return true;
    } catch (e) {
      // Re-throw with more context
      if (e is TimeoutException) {
        throw Exception('Share dialog failed to open within 15 seconds');
      } else if (e.toString().contains('No Activity found')) {
        throw Exception('No file manager or sharing app available');
      } else {
        throw Exception('Share operation failed: ${e.toString()}');
      }
    }
  }

  /// Validate files before attempting to share
  ///
  /// Performs comprehensive validation including:
  /// - Closing any open file handles from FileLogManager
  /// - Verifying file existence and readability
  /// - Checking file size and content accessibility
  /// - Testing actual file read capability
  static Future<void> _validateFilesForSharing(List<File> files) async {
    // CRITICAL: Close any open log file handles before sharing
    // This prevents file locking issues that cause empty file copies
    final currentLogPath = FileLogManager.instance.getCurrentLogPath();
    if (currentLogPath != null) {
      final isCurrentFileBeingShared =
          files.any((f) => f.path == currentLogPath);
      if (isCurrentFileBeingShared) {
        debugPrint(
            '[SHARE] Closing active log file before sharing: $currentLogPath');
        await FileLogManager.instance.dispose();
        // Give OS time to release file handles (critical on Android)
        await Future.delayed(const Duration(milliseconds: 200));
        // Re-initialize logging to continue after share
        await FileLogManager.instance.initialize(enabled: true);
      }
    }

    // Validate each file with detailed checks
    final validationErrors = <String>[];

    for (final file in files) {
      final fileName = file.path.split('/').last;

      // Check 1: File existence
      if (!await file.exists()) {
        validationErrors.add('File not found: $fileName');
        continue;
      }

      // Check 2: File accessibility - attempt to open handle
      try {
        final handle = await file.open();
        await handle.close();
      } catch (e) {
        validationErrors.add(
            'Cannot access file (may be locked): $fileName - ${e.toString()}');
        continue;
      }

      // Check 3: File size and content readability
      try {
        final length = await file.length();

        // Empty file check
        if (length == 0) {
          validationErrors.add('File is empty (0 bytes): $fileName');
          continue;
        }

        // Large file warning (not an error)
        if (length > _maxShareSizeBytes) {
          debugPrint(
              '[SHARE] Warning: Large file detected (${(length / (1024 * 1024)).toStringAsFixed(1)}MB): $fileName');
        }

        // Check 4: Verify file is actually readable by reading first chunk
        // This catches cases where file exists but content is inaccessible
        final bytesToRead = min(1024, length);
        final bytes = await file.openRead(0, bytesToRead).toList();

        if (bytes.isEmpty) {
          validationErrors.add(
              'File appears readable but content is inaccessible: $fileName');
          continue;
        }

        // Verify we got expected bytes
        final totalBytesRead =
            bytes.fold<int>(0, (sum, chunk) => sum + chunk.length);
        if (totalBytesRead == 0) {
          validationErrors.add('File read returned 0 bytes: $fileName');
          continue;
        }
      } catch (e) {
        validationErrors.add('Cannot read file: $fileName - ${e.toString()}');
        continue;
      }
    }

    // Throw aggregated validation errors
    if (validationErrors.isNotEmpty) {
      throw Exception(
          'File validation failed:\n${validationErrors.join('\n')}');
    }

    debugPrint('[SHARE] All ${files.length} files validated successfully');
  }

  /// Get total size of files in a human-readable format
  static String getFilesTotalSize(List<File> files) {
    try {
      final totalBytes = files.fold<int>(0, (sum, file) {
        try {
          return sum + file.lengthSync();
        } catch (e) {
          return sum; // Skip files that can't be read
        }
      });

      if (totalBytes < 1024) {
        return '${totalBytes}B';
      } else if (totalBytes < 1024 * 1024) {
        return '${(totalBytes / 1024).toStringAsFixed(1)}KB';
      } else {
        return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
      }
    } catch (e) {
      return 'Unknown size';
    }
  }

  /// Check if sharing is likely to work (basic validation)
  static Future<bool> canShare() async {
    try {
      // Try to share test text to validate if share functionality works
      // This won't actually open a dialog but will validate the share capability
      await SharePlus.instance
          .share(
            ShareParams(
              text: 'test',
              subject: 'test',
            ),
          )
          .timeout(_canShareTestTimeout);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Enhanced share operation with better error messages for AAOS
  static Future<ShareResult> shareWithAAOSSupport({
    required List<File> files,
    String? text,
    int maxRetries = 1,
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < maxRetries) {
      attempts++;

      try {
        await _validateFilesForSharing(files);

        final xFiles = files.map((file) => XFile(file.path)).toList();

        await SharePlus.instance
            .share(
              ShareParams(
                files: xFiles,
                text: text,
              ),
            )
            .timeout(
              _shareTimeoutAAOS, // Longer timeout for AAOS
            );

        return ShareResult(
          success: true,
          message: 'Share dialog opened successfully',
          attempts: attempts,
        );
      } catch (e) {
        lastError = Exception('Attempt $attempts failed: ${e.toString()}');

        if (attempts < maxRetries) {
          // Brief delay before retry
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    return ShareResult(
      success: false,
      message: lastError?.toString() ?? 'Unknown error',
      attempts: attempts,
    );
  }
}

/// Result of a share operation
class ShareResult {
  final bool success;
  final String message;
  final int attempts;

  const ShareResult({
    required this.success,
    required this.message,
    required this.attempts,
  });

  @override
  String toString() {
    return 'ShareResult(success: $success, attempts: $attempts, message: $message)';
  }
}
