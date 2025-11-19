import 'package:flutter/services.dart';

import '../../carlink_platform_interface.dart';
import '../../usb.dart';
import '../../log.dart';

class UsbManagerWrapper {
  static Future<List<UsbDeviceWrapper>> lookupForUsbDevice(
    List<Map<int, int>> vendorIdProductIdList,
  ) async {
    logDebug(
      'USB device lookup starting with ${vendorIdProductIdList.length} target VID/PID pairs',
      tag: 'USB',
    );

    final stopwatch = Stopwatch()..start();
    var devices = await CarlinkPlatform.instance.getDeviceList();
    stopwatch.stop();

    logInfo(
      'Found ${devices.length} USB devices in ${stopwatch.elapsedMilliseconds}ms',
      tag: 'USB',
    );

    var filtered = devices.where(
      (device) => vendorIdProductIdList
          .where(
            (pair) =>
                device.vendorId == pair.entries.first.key &&
                device.productId == pair.entries.first.value,
          )
          .isNotEmpty,
    );

    logDebug('Filtered to ${filtered.length} matching devices', tag: 'USB');
    for (var device in filtered) {
      logDebug(
        '  - VID:0x${device.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${device.productId.toRadixString(16).padLeft(4, '0')} ID:${device.identifier}',
        tag: 'USB',
      );
    }

    var wrapped = filtered.map((e) => UsbDeviceWrapper(e)).toList();
    logInfo(
      'USB device lookup completed: ${wrapped.length} CPC200-CCPA devices found',
      tag: 'USB',
    );

    return wrapped;
  }
}

class UsbDeviceWrapper {
  bool _isOpened = false;
  bool get isOpened => _isOpened;

  final UsbDevice _usbDevice;

  UsbEndpoint? _endpointIn;
  UsbEndpoint? _endpointOut;

  // Performance tracking
  int _readOperations = 0;
  int _writeOperations = 0;
  int _readBytes = 0;
  int _writeBytes = 0;
  int _readErrors = 0;
  int _writeErrors = 0;
  DateTime? _openTime;

  UsbDeviceWrapper(this._usbDevice) {
    logDebug(
      'UsbDeviceWrapper created for VID:0x${_usbDevice.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${_usbDevice.productId.toRadixString(16).padLeft(4, '0')}',
      tag: 'USB',
    );
  }

  Future<void> open() async {
    logInfo(
      'Opening USB device VID:0x${_usbDevice.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${_usbDevice.productId.toRadixString(16).padLeft(4, '0')}',
      tag: 'USB',
    );
    final stopwatch = Stopwatch()..start();

    try {
      // Check if we already have permission before requesting
      logDebug('Checking USB permission status...', tag: 'USB');
      final hasPermission = await CarlinkPlatform.instance.hasPermission(
        _usbDevice,
      );

      if (!hasPermission) {
        logInfo(
          'USB permission not granted for VID:0x${_usbDevice.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${_usbDevice.productId.toRadixString(16).padLeft(4, '0')}, requesting from user...',
          tag: 'USB',
        );
        await CarlinkPlatform.instance.requestPermission(_usbDevice);
        logDebug('Permission request completed', tag: 'USB');
      } else {
        logInfo(
          'USB permission already granted for VID:0x${_usbDevice.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${_usbDevice.productId.toRadixString(16).padLeft(4, '0')}, skipping dialog',
          tag: 'USB',
        );
      }

      logDebug('Opening USB device...', tag: 'USB');
      await CarlinkPlatform.instance.openDevice(_usbDevice);

      logDebug('Getting device configuration...', tag: 'USB');
      var conf = await CarlinkPlatform.instance.getConfiguration(0);

      logDebug(
        'Setting device configuration with ${conf.interfaces.length} interfaces',
        tag: 'USB',
      );
      await CarlinkPlatform.instance.setConfiguration(conf);

      var interface = conf.interfaces.first;
      logDebug(
        'Claiming interface with ${interface.endpoints.length} endpoints',
        tag: 'USB',
      );
      await CarlinkPlatform.instance.claimInterface(interface);

      _endpointIn = interface.endpoints.firstWhere(
        (e) => e.direction == UsbEndpoint.DIRECTION_IN,
      );

      _endpointOut = interface.endpoints.firstWhere(
        (e) => e.direction == UsbEndpoint.DIRECTION_OUT,
      );

      logDebug(
        'Configured endpoints: IN=${_endpointIn?.endpointAddress.toRadixString(16)} OUT=${_endpointOut?.endpointAddress.toRadixString(16)}',
        tag: 'USB',
      );

      _isOpened = true;
      _openTime = DateTime.now();
      stopwatch.stop();

      logInfo(
        'USB device opened successfully in ${stopwatch.elapsedMilliseconds}ms',
        tag: 'USB',
      );
      _logPerformanceStats();
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to open USB device after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'USB',
      );
      rethrow;
    }
  }

  Future<void> close() async {
    logInfo('Closing USB device', tag: 'USB');
    final stopwatch = Stopwatch()..start();

    try {
      await CarlinkPlatform.instance.closeDevice();
      _isOpened = false;
      stopwatch.stop();

      final sessionDuration = _openTime != null
          ? DateTime.now().difference(_openTime!).inSeconds
          : 0;
      logInfo(
        'USB device closed successfully in ${stopwatch.elapsedMilliseconds}ms (session: ${sessionDuration}s)',
        tag: 'USB',
      );
      _logPerformanceStats();

      // Reset stats for next session
      _resetStats();
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to close USB device after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'USB',
      );
      rethrow;
    }
  }

  Future<void> reset() async {
    logWarn('Resetting USB device', tag: 'USB');
    final stopwatch = Stopwatch()..start();

    try {
      await CarlinkPlatform.instance.resetDevice();
      stopwatch.stop();
      logInfo(
        'USB device reset completed in ${stopwatch.elapsedMilliseconds}ms',
        tag: 'USB',
      );
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to reset USB device after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'USB',
      );
      rethrow;
    }
  }

  Future<void> startReadingLoop({
    required Function(int, Uint8List?) onMessage,
    required Function(String) onError,
    int timeout = 10000,
  }) {
    if (!isOpened) throw "UsbDevice not opened";
    if (_endpointIn == null) throw "UsbDevice endpointIn is null";

    logInfo('Starting USB reading loop with ${timeout}ms timeout', tag: 'USB');

    return CarlinkPlatform.instance.startReadingLoop(
      _endpointIn!,
      timeout,
      onMessage: (type, data) {
        _readOperations++;
        if (data != null) _readBytes += data.length;
        logDebug(
          'Read loop message: type=$type size=${data?.length ?? 0}',
          tag: 'USB',
        );
        onMessage(type, data);
      },
      onError: (error) {
        _readErrors++;
        logError('Read loop error: $error', tag: 'USB');
        onError(error);
      },
    );
  }

  Future<void> stopReadingLoop() {
    logInfo('Stopping USB reading loop', tag: 'USB');
    return CarlinkPlatform.instance.stopReadingLoop();
  }

  Future<Uint8List> read(
    int maxLength, {
    int timeout = 10000,
    bool isVideoData = false,
    int retryCount = 3,
  }) async {
    if (!isOpened) throw StateError("UsbDevice not opened");
    if (_endpointIn == null) throw StateError("UsbDevice endpointIn is null");

    // Validate input parameters
    if (maxLength <= 0) throw ArgumentError("maxLength must be positive");
    if (timeout <= 0) throw ArgumentError("timeout must be positive");
    if (retryCount < 0) throw ArgumentError("retryCount must be non-negative");

    final stopwatch = Stopwatch()..start();
    logDebug(
      'USB read: maxLen=$maxLength timeout=${timeout}ms video=$isVideoData retries=$retryCount',
      tag: 'USB',
    );

    Exception? lastException;

    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        final result = await CarlinkPlatform.instance.bulkTransferIn(
          _endpointIn!,
          maxLength,
          _calculateTimeout(timeout, attempt),
          isVideoData: isVideoData,
        );

        _readOperations++;
        _readBytes += result.length;
        stopwatch.stop();

        if (attempt > 0) {
          logInfo(
            'USB read succeeded on attempt ${attempt + 1}: ${result.length} bytes in ${stopwatch.elapsedMilliseconds}ms',
            tag: 'USB',
          );
        } else {
          logDebug(
            'USB read: ${result.length} bytes in ${stopwatch.elapsedMilliseconds}ms',
            tag: 'USB',
          );
        }

        return result;
      } on PlatformException catch (e) {
        lastException = e;
        _readErrors++;

        // Check for unrecoverable errors
        if (e.code == "IllegalState" && e.message?.contains("null") == true) {
          stopwatch.stop();
          logError(
            'USB device connection lost after ${stopwatch.elapsedMilliseconds}ms: ${e.message}',
            tag: 'USB',
          );
          throw StateError("USB device connection lost: ${e.message}");
        }

        // If this is the last attempt, throw the exception
        if (attempt == retryCount) break;

        logWarn(
          'USB read attempt ${attempt + 1} failed: ${e.code} - ${e.message}',
          tag: 'USB',
        );

        // Exponential backoff for retries
        final delayMs = 100 * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
      } catch (e) {
        lastException = e as Exception;
        _readErrors++;
        if (attempt == retryCount) break;

        logWarn('USB read attempt ${attempt + 1} failed: $e', tag: 'USB');
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
    }

    stopwatch.stop();
    logError(
      'USB read failed after ${retryCount + 1} attempts in ${stopwatch.elapsedMilliseconds}ms: $lastException',
      tag: 'USB',
    );
    throw lastException ?? Exception("Unknown USB read error");
  }

  Future<int> write(
    Uint8List data, {
    int timeout = 10000,
    int retryCount = 3,
  }) async {
    if (!isOpened) throw StateError("UsbDevice not opened");
    if (_endpointOut == null) throw StateError("UsbDevice endpointOut is null");

    // Validate input parameters
    if (data.isEmpty) throw ArgumentError("data cannot be empty");
    if (timeout <= 0) throw ArgumentError("timeout must be positive");
    if (retryCount < 0) throw ArgumentError("retryCount must be non-negative");

    final stopwatch = Stopwatch()..start();
    logDebug(
      'USB write: ${data.length} bytes timeout=${timeout}ms retries=$retryCount',
      tag: 'USB',
    );

    Exception? lastException;

    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        final result = await CarlinkPlatform.instance.bulkTransferOut(
          _endpointOut!,
          data,
          _calculateTimeout(timeout, attempt),
        );

        _writeOperations++;
        _writeBytes += result;
        stopwatch.stop();

        if (attempt > 0) {
          logInfo(
            'USB write succeeded on attempt ${attempt + 1}: $result bytes in ${stopwatch.elapsedMilliseconds}ms',
            tag: 'USB',
          );
        } else {
          logDebug(
            'USB write: $result bytes in ${stopwatch.elapsedMilliseconds}ms',
            tag: 'USB',
          );
        }

        return result;
      } on PlatformException catch (e) {
        lastException = e;
        _writeErrors++;

        // Check for unrecoverable errors
        if (e.code == "IllegalState" && e.message?.contains("null") == true) {
          stopwatch.stop();
          logError(
            'USB device connection lost during write after ${stopwatch.elapsedMilliseconds}ms: ${e.message}',
            tag: 'USB',
          );
          throw StateError("USB device connection lost: ${e.message}");
        }
        if (e.code == "USBWriteError" &&
            e.message?.contains("actualLength=-1") == true) {
          stopwatch.stop();
          logError(
            'USB device disconnected during write after ${stopwatch.elapsedMilliseconds}ms',
            tag: 'USB',
          );
          throw StateError("USB device disconnected during write");
        }

        // If this is the last attempt, throw the exception
        if (attempt == retryCount) break;

        logWarn(
          'USB write attempt ${attempt + 1} failed: ${e.code} - ${e.message}',
          tag: 'USB',
        );

        // Exponential backoff for retries
        final delayMs = 100 * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
      } catch (e) {
        lastException = e as Exception;
        _writeErrors++;
        if (attempt == retryCount) break;

        logWarn('USB write attempt ${attempt + 1} failed: $e', tag: 'USB');
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
    }

    stopwatch.stop();
    logError(
      'USB write failed after ${retryCount + 1} attempts in ${stopwatch.elapsedMilliseconds}ms: $lastException',
      tag: 'USB',
    );
    throw lastException ?? Exception("Unknown USB write error");
  }

  // Calculate timeout with exponential backoff
  int _calculateTimeout(int baseTimeout, int attempt) {
    return baseTimeout + (baseTimeout * attempt ~/ 2);
  }

  // Performance tracking methods
  void _logPerformanceStats() {
    final sessionDuration = _openTime != null
        ? DateTime.now().difference(_openTime!).inSeconds
        : 0;
    final readThroughput = sessionDuration > 0
        ? (_readBytes / sessionDuration / 1024).toStringAsFixed(1)
        : '0.0';
    final writeThroughput = sessionDuration > 0
        ? (_writeBytes / sessionDuration / 1024).toStringAsFixed(1)
        : '0.0';
    final readSuccessRate = _readOperations + _readErrors > 0
        ? (_readOperations / (_readOperations + _readErrors) * 100)
              .toStringAsFixed(1)
        : '100.0';
    final writeSuccessRate = _writeOperations + _writeErrors > 0
        ? (_writeOperations / (_writeOperations + _writeErrors) * 100)
              .toStringAsFixed(1)
        : '100.0';

    logInfo(
      'USB Performance: R:${_readOperations}ops/${(_readBytes / 1024).toStringAsFixed(1)}KB/${readThroughput}KB/s ($readSuccessRate%) W:${_writeOperations}ops/${(_writeBytes / 1024).toStringAsFixed(1)}KB/${writeThroughput}KB/s ($writeSuccessRate%)',
      tag: 'USB',
    );
  }

  void _resetStats() {
    _readOperations = 0;
    _writeOperations = 0;
    _readBytes = 0;
    _writeBytes = 0;
    _readErrors = 0;
    _writeErrors = 0;
    _openTime = null;
  }

  // Public performance getters for monitoring
  Map<String, dynamic> getPerformanceStats() {
    final sessionDuration = _openTime != null
        ? DateTime.now().difference(_openTime!).inSeconds
        : 0;
    return {
      'sessionDurationSeconds': sessionDuration,
      'readOperations': _readOperations,
      'writeOperations': _writeOperations,
      'readBytes': _readBytes,
      'writeBytes': _writeBytes,
      'readErrors': _readErrors,
      'writeErrors': _writeErrors,
      'readThroughputKBps': sessionDuration > 0
          ? _readBytes / sessionDuration / 1024
          : 0.0,
      'writeThroughputKBps': sessionDuration > 0
          ? _writeBytes / sessionDuration / 1024
          : 0.0,
      'readSuccessRate': _readOperations + _readErrors > 0
          ? _readOperations / (_readOperations + _readErrors)
          : 1.0,
      'writeSuccessRate': _writeOperations + _writeErrors > 0
          ? _writeOperations / (_writeOperations + _writeErrors)
          : 1.0,
    };
  }
}
