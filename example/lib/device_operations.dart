import 'package:carlink/carlink.dart';
import 'package:carlink/carlink_platform_interface.dart';
import 'package:carlink/log.dart';
import 'package:flutter/material.dart';

/// Shared device operation utilities for MainPage and Settings.
///
/// Provides centralized device control operations with consistent error handling,
/// state management, and user feedback across the application.
class DeviceOperations {
  /// Prevents concurrent operations from being executed
  static bool _isProcessing = false;

  /// Gets the current processing state
  static bool get isProcessing => _isProcessing;

  /// Restarts the USB device connection with proper state management.
  ///
  /// This is the primary device reset operation used throughout the app.
  /// Prevents concurrent operations and provides consistent error handling.
  ///
  /// [initiatedFrom] - Optional string to identify where the reset was triggered from
  /// (e.g., "Main Page", "Settings Control Tab")
  ///
  /// Returns true if the operation completed successfully, false otherwise.
  static Future<bool> restartConnection({
    required BuildContext context,
    required Carlink? carlink,
    String? successMessage,
    bool showSuccessSnackbar = true,
    String? initiatedFrom,
  }) async {
    // Prevent concurrent operations
    if (_isProcessing) {
      log('[DEVICE_OPS] Reset already in progress, ignoring request');
      return false;
    }

    if (carlink == null) {
      log('[DEVICE_OPS] Cannot reset: Carlink instance is null');
      _showSnackbar(
        context,
        'Cannot reset: Device not initialized',
        isError: true,
      );
      return false;
    }

    _isProcessing = true;
    final source = initiatedFrom ?? 'Unknown';
    log('[DEVICE_OPS] USER INITIATED DEVICE RESET (Source: $source)');

    try {
      await carlink.restart();

      log('[DEVICE_OPS] Device reset completed successfully');

      if (showSuccessSnackbar && context.mounted) {
        _showSnackbar(
          context,
          successMessage ?? 'Device reset completed successfully',
          isError: false,
        );
      }

      return true;
    } catch (e) {
      log('[DEVICE_OPS] Device reset failed: $e');

      if (context.mounted) {
        _showSnackbar(
          context,
          'Device reset failed: $e',
          isError: true,
        );
      }

      return false;
    } finally {
      // Always release the processing lock
      _isProcessing = false;
    }
  }

  /// Shows a snackbar message with consistent styling
  static void _showSnackbar(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : null,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  /// Resets the H.264 video decoder/renderer.
  ///
  /// This operation resets the MediaCodec decoder without disconnecting the USB device.
  /// Useful for recovering from video decoding errors or codec issues.
  ///
  /// [initiatedFrom] - Optional string to identify where the reset was triggered from
  ///
  /// Returns true if the operation completed successfully, false otherwise.
  static Future<bool> resetH264Renderer({
    required BuildContext context,
    String? initiatedFrom,
  }) async {
    // Import required for platform interface
    final CarlinkPlatform platform = CarlinkPlatform.instance;

    final source = initiatedFrom ?? 'Unknown';
    log('[DEVICE_OPS] USER INITIATED H264 RENDERER RESET (Source: $source)');

    try {
      await platform.resetH264Renderer();
      log('[DEVICE_OPS] H264 renderer reset completed successfully');

      if (context.mounted) {
        _showSnackbar(
          context,
          'Video decoder reset completed successfully',
          isError: false,
        );
      }

      return true;
    } catch (e) {
      log('[DEVICE_OPS] H264 renderer reset failed: $e');

      if (context.mounted) {
        _showSnackbar(
          context,
          'Video decoder reset failed: $e',
          isError: true,
        );
      }

      return false;
    }
  }

  /// Resets the processing state (use with caution, primarily for testing)
  @visibleForTesting
  static void resetState() {
    _isProcessing = false;
  }
}
