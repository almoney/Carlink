import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'carlink_platform_interface.dart';
import 'usb.dart';
import 'log.dart';

/// An implementation of [CarlinkPlatform] that uses method channels.
class MethodChannelCarlink extends CarlinkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('carlink');

  Function(String)? _logHandler;
  Function(int, Uint8List?)? _readingLoopMessageHandler;
  Function(String)? _readingLoopErrorHandler;

  // Media control callbacks from AAOS/steering wheel
  Function()? _mediaControlPlayHandler;
  Function()? _mediaControlPauseHandler;
  Function()? _mediaControlStopHandler;
  Function()? _mediaControlNextHandler;
  Function()? _mediaControlPreviousHandler;

  MethodChannelCarlink() {
    logDebug('MethodChannelCarlink initialized', tag: 'PLATFORM');

    methodChannel.setMethodCallHandler((call) async {
      logDebug('Method call received: ${call.method}', tag: 'PLATFORM');

      if (call.method == "onLogMessage") {
        _logHandler?.call(call.arguments);
      } else if (call.method == "onReadingLoopMessage") {
        final type = call.arguments["type"];
        final data = Uint8List.fromList(call.arguments["data"]);

        logDebug(
          'Reading loop message: type=$type size=${data.length}',
          tag: 'PLATFORM',
        );

        if (_readingLoopMessageHandler != null) {
          _readingLoopMessageHandler!(type, data);
        }
      } else if (call.method == "onReadingLoopError") {
        logError('Reading loop error: ${call.arguments}', tag: 'PLATFORM');
        _readingLoopErrorHandler?.call(call.arguments);
      } else if (call.method == "onMediaControlPlay") {
        logDebug('Media control: PLAY', tag: 'MEDIA_SESSION');
        _mediaControlPlayHandler?.call();
      } else if (call.method == "onMediaControlPause") {
        logDebug('Media control: PAUSE', tag: 'MEDIA_SESSION');
        _mediaControlPauseHandler?.call();
      } else if (call.method == "onMediaControlStop") {
        logDebug('Media control: STOP', tag: 'MEDIA_SESSION');
        _mediaControlStopHandler?.call();
      } else if (call.method == "onMediaControlNext") {
        logDebug('Media control: NEXT', tag: 'MEDIA_SESSION');
        _mediaControlNextHandler?.call();
      } else if (call.method == "onMediaControlPrevious") {
        logDebug('Media control: PREVIOUS', tag: 'MEDIA_SESSION');
        _mediaControlPreviousHandler?.call();
      } else {
        logWarn('Unknown method call: ${call.method}', tag: 'PLATFORM');
      }
    });
  }

  void setLogHandler(Function(String)? logHandler) {
    _logHandler = logHandler;
  }

  /// Set handlers for media control events from AAOS/steering wheel.
  void setMediaControlHandlers({
    Function()? onPlay,
    Function()? onPause,
    Function()? onStop,
    Function()? onNext,
    Function()? onPrevious,
  }) {
    _mediaControlPlayHandler = onPlay;
    _mediaControlPauseHandler = onPause;
    _mediaControlStopHandler = onStop;
    _mediaControlNextHandler = onNext;
    _mediaControlPreviousHandler = onPrevious;
  }

  @override
  Future<void> startReadingLoop(
    UsbEndpoint endpoint,
    int timeout, {
    required Function(int, Uint8List?) onMessage,
    required Function(String) onError,
  }) async {
    assert(
      endpoint.direction == UsbEndpoint.DIRECTION_IN,
      'Endpoint\'s direction should be in',
    );

    logInfo(
      'Starting reading loop: endpoint=0x${endpoint.endpointAddress.toRadixString(16)} timeout=${timeout}ms',
      tag: 'PLATFORM',
    );

    _readingLoopMessageHandler = onMessage;
    _readingLoopErrorHandler = onError;

    try {
      return await methodChannel.invokeMethod('startReadingLoop', {
        'endpoint': endpoint.toMap(),
        'timeout': timeout,
      });
    } catch (e) {
      logError('Failed to start reading loop: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<void> stopReadingLoop() async {
    logInfo('Stopping reading loop', tag: 'PLATFORM');
    try {
      await methodChannel.invokeMethod<int>('stopReadingLoop');
      logDebug('Reading loop stopped successfully', tag: 'PLATFORM');
    } catch (e) {
      logError('Failed to stop reading loop: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getDisplayMetrics() async {
    logDebug('Getting display metrics', tag: 'PLATFORM');
    try {
      final metrics = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getDisplayMetrics',
      );
      final result = metrics!.cast<String, dynamic>();
      logDebug(
        'Display metrics: ${result['widthPixels']}x${result['heightPixels']} density=${result['density']}',
        tag: 'PLATFORM',
      );
      return result;
    } catch (e) {
      logError('Failed to get display metrics: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getWindowBounds() async {
    logDebug('Getting window bounds', tag: 'PLATFORM');
    try {
      final bounds = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getWindowBounds',
      );
      final result = bounds!.cast<String, dynamic>();
      logDebug(
        'Window bounds: ${result['width']}x${result['height']} usable: ${result['usableWidth']}x${result['usableHeight']}',
        tag: 'PLATFORM',
      );
      return result;
    } catch (e) {
      logError('Failed to get window bounds: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<int> createTexture(int width, int height) async {
    logInfo('Creating texture: ${width}x$height', tag: 'PLATFORM');
    try {
      final textureId = await methodChannel.invokeMethod<int>('createTexture', {
        "width": width,
        "height": height,
      });
      logDebug('Texture created with ID: $textureId', tag: 'PLATFORM');
      return textureId!;
    } catch (e) {
      logError('Failed to create texture: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<void> removeTexture() async {
    logInfo('Removing texture', tag: 'PLATFORM');
    try {
      await methodChannel.invokeMethod<int>('removeTexture');
      logDebug('Texture removed successfully', tag: 'PLATFORM');
    } catch (e) {
      logError('Failed to remove texture: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<void> resetH264Renderer() async {
    logWarn('Resetting H264 renderer', tag: 'PLATFORM');
    try {
      await methodChannel.invokeMethod<void>('resetH264Renderer');
      logInfo('H264 renderer reset successfully', tag: 'PLATFORM');
    } catch (e) {
      logError('Failed to reset H264 renderer: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<String?> getCodecName() async {
    logDebug('Getting codec name', tag: 'PLATFORM');
    try {
      final codecName = await methodChannel.invokeMethod<String?>('getCodecName');
      logDebug('Codec name: $codecName', tag: 'PLATFORM');
      return codecName;
    } catch (e) {
      logError('Failed to get codec name: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<List<UsbDevice>> getDeviceList() async {
    logDebug('Getting USB device list', tag: 'PLATFORM');
    final stopwatch = Stopwatch()..start();

    try {
      List<Map<dynamic, dynamic>> devices = (await methodChannel
          .invokeListMethod('getDeviceList'))!;
      final result = devices
          .map((device) => UsbDevice.fromMap(device))
          .toList();

      stopwatch.stop();
      logInfo(
        'Found ${result.length} USB devices in ${stopwatch.elapsedMilliseconds}ms',
        tag: 'PLATFORM',
      );

      for (var device in result) {
        logDebug(
          '  - VID:0x${device.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${device.productId.toRadixString(16).padLeft(4, '0')} configs:${device.configurationCount}',
          tag: 'PLATFORM',
        );
      }

      return result;
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to get device list after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'PLATFORM',
      );
      rethrow;
    }
  }

  @override
  Future<List<UsbDeviceDescription>> getDevicesWithDescription({
    bool requestPermission = true,
  }) async {
    var devices = await getDeviceList();
    var result = <UsbDeviceDescription>[];
    for (var device in devices) {
      result.add(
        await getDeviceDescription(
          device,
          requestPermission: requestPermission,
        ),
      );
    }
    return result;
  }

  @override
  Future<UsbDeviceDescription> getDeviceDescription(
    UsbDevice usbDevice, {
    bool requestPermission = true,
  }) async {
    var result = await methodChannel.invokeMethod('getDeviceDescription', {
      'device': usbDevice.toMap(),
      'requestPermission': requestPermission,
    });
    return UsbDeviceDescription(
      device: usbDevice,
      manufacturer: result['manufacturer'],
      product: result['product'],
      serialNumber: result['serialNumber'],
    );
  }

  @override
  Future<bool> hasPermission(UsbDevice usbDevice) async {
    return await methodChannel.invokeMethod('hasPermission', usbDevice.toMap());
  }

  @override
  Future<bool> requestPermission(UsbDevice usbDevice) async {
    logInfo(
      'Requesting USB permission for VID:0x${usbDevice.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${usbDevice.productId.toRadixString(16).padLeft(4, '0')}',
      tag: 'PLATFORM',
    );
    try {
      final result = await methodChannel.invokeMethod(
        'requestPermission',
        usbDevice.toMap(),
      );
      logInfo(
        'USB permission ${result ? 'granted' : 'denied'}',
        tag: 'PLATFORM',
      );
      return result;
    } catch (e) {
      logError('Failed to request USB permission: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<bool> openDevice(UsbDevice usbDevice) async {
    logInfo(
      'Opening USB device VID:0x${usbDevice.vendorId.toRadixString(16).padLeft(4, '0')} PID:0x${usbDevice.productId.toRadixString(16).padLeft(4, '0')}',
      tag: 'PLATFORM',
    );
    final stopwatch = Stopwatch()..start();

    try {
      final result = await methodChannel.invokeMethod(
        'openDevice',
        usbDevice.toMap(),
      );
      stopwatch.stop();

      if (result) {
        logInfo(
          'USB device opened successfully in ${stopwatch.elapsedMilliseconds}ms',
          tag: 'PLATFORM',
        );
      } else {
        logWarn(
          'USB device open failed in ${stopwatch.elapsedMilliseconds}ms',
          tag: 'PLATFORM',
        );
      }

      return result;
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to open USB device after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'PLATFORM',
      );
      rethrow;
    }
  }

  @override
  Future<void> closeDevice() {
    logInfo('Closing USB device', tag: 'PLATFORM');

    _readingLoopErrorHandler = null;
    _readingLoopMessageHandler = null;

    try {
      final result = methodChannel.invokeMethod('closeDevice');
      logDebug('USB device close initiated', tag: 'PLATFORM');
      return result;
    } catch (e) {
      logError('Failed to close USB device: $e', tag: 'PLATFORM');
      rethrow;
    }
  }

  @override
  Future<bool> resetDevice() async {
    logWarn('Resetting USB device', tag: 'PLATFORM');
    final stopwatch = Stopwatch()..start();

    try {
      final result = await methodChannel.invokeMethod('resetDevice');
      stopwatch.stop();

      if (result) {
        logInfo(
          'USB device reset successfully in ${stopwatch.elapsedMilliseconds}ms',
          tag: 'PLATFORM',
        );
      } else {
        logWarn(
          'USB device reset failed in ${stopwatch.elapsedMilliseconds}ms',
          tag: 'PLATFORM',
        );
      }

      return result;
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to reset USB device after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'PLATFORM',
      );
      rethrow;
    }
  }

  @override
  Future<UsbConfiguration> getConfiguration(int index) async {
    var map = await methodChannel.invokeMethod('getConfiguration', {
      'index': index,
    });
    return UsbConfiguration.fromMap(map);
  }

  @override
  Future<bool> setConfiguration(UsbConfiguration config) async {
    return await methodChannel.invokeMethod('setConfiguration', config.toMap());
  }

  @override
  Future<bool> claimInterface(UsbInterface intf) async {
    return await methodChannel.invokeMethod('claimInterface', intf.toMap());
  }

  @override
  Future<bool> releaseInterface(UsbInterface intf) async {
    return await methodChannel.invokeMethod('releaseInterface', intf.toMap());
  }

  @override
  Future<Uint8List> bulkTransferIn(
    UsbEndpoint endpoint,
    int maxLength,
    int timeout, {
    bool isVideoData = false,
  }) async {
    assert(
      endpoint.direction == UsbEndpoint.DIRECTION_IN,
      'Endpoint\'s direction should be in',
    );

    final stopwatch = Stopwatch()..start();
    logDebug(
      'Bulk transfer IN: maxLen=$maxLength timeout=${timeout}ms video=$isVideoData',
      tag: 'PLATFORM',
    );

    try {
      final data = await methodChannel.invokeMethod('bulkTransferIn', {
        'endpoint': endpoint.toMap(),
        'maxLength': maxLength,
        'timeout': timeout,
        'isVideoData': isVideoData,
      });

      final result = Uint8List.fromList(data.cast<int>());
      stopwatch.stop();

      logDebug(
        'Bulk transfer IN completed: ${result.length} bytes in ${stopwatch.elapsedMilliseconds}ms',
        tag: 'PLATFORM',
      );
      return result;
    } catch (e) {
      stopwatch.stop();
      logError(
        'Bulk transfer IN failed after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'PLATFORM',
      );
      rethrow;
    }
  }

  @override
  Future<int> bulkTransferOut(
    UsbEndpoint endpoint,
    Uint8List data,
    int timeout,
  ) async {
    assert(
      endpoint.direction == UsbEndpoint.DIRECTION_OUT,
      'Endpoint\'s direction should be out',
    );

    final stopwatch = Stopwatch()..start();
    logDebug(
      'Bulk transfer OUT: ${data.length} bytes timeout=${timeout}ms',
      tag: 'PLATFORM',
    );

    try {
      final result = await methodChannel.invokeMethod('bulkTransferOut', {
        'endpoint': endpoint.toMap(),
        'data': data,
        'timeout': timeout,
      });

      stopwatch.stop();
      logDebug(
        'Bulk transfer OUT completed: $result bytes in ${stopwatch.elapsedMilliseconds}ms',
        tag: 'PLATFORM',
      );
      return result;
    } catch (e) {
      stopwatch.stop();
      logError(
        'Bulk transfer OUT failed after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'PLATFORM',
      );
      rethrow;
    }
  }

  // ==================== Audio Playback Methods ====================

  @override
  Future<bool> initializeAudio({int decodeType = 4}) async {
    logInfo('Initializing audio: decodeType=$decodeType', tag: 'AUDIO');
    try {
      final result = await methodChannel.invokeMethod<bool>('initializeAudio', {
        'decodeType': decodeType,
      });
      logDebug('Audio initialized: $result', tag: 'AUDIO');
      return result ?? false;
    } catch (e) {
      logError('Failed to initialize audio: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<bool> startAudio() async {
    logInfo('Starting audio playback', tag: 'AUDIO');
    try {
      final result = await methodChannel.invokeMethod<bool>('startAudio');
      logDebug('Audio started: $result', tag: 'AUDIO');
      return result ?? false;
    } catch (e) {
      logError('Failed to start audio: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<void> stopAudio() async {
    logInfo('Stopping audio playback', tag: 'AUDIO');
    try {
      await methodChannel.invokeMethod<void>('stopAudio');
      logDebug('Audio stopped', tag: 'AUDIO');
    } catch (e) {
      logError('Failed to stop audio: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<void> pauseAudio() async {
    logInfo('Pausing audio playback', tag: 'AUDIO');
    try {
      await methodChannel.invokeMethod<void>('pauseAudio');
      logDebug('Audio paused', tag: 'AUDIO');
    } catch (e) {
      logError('Failed to pause audio: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<int> writeAudio(
    Uint8List data, {
    int decodeType = 4,
    int audioType = 1,
    double volume = 1.0,
  }) async {
    // Note: High-frequency operation - only log errors, not every call
    try {
      final result = await methodChannel.invokeMethod<int>('writeAudio', {
        'data': data,
        'decodeType': decodeType,
        'audioType': audioType,
        'volume': volume,
      });
      return result ?? -1;
    } catch (e) {
      logError('Failed to write audio: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<void> setAudioDucking(double duckLevel) async {
    logDebug('Setting audio ducking: $duckLevel', tag: 'AUDIO');
    try {
      await methodChannel.invokeMethod<void>('setAudioDucking', {
        'duckLevel': duckLevel,
      });
    } catch (e) {
      logError('Failed to set audio ducking: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<void> setAudioVolume(double volume) async {
    logDebug('Setting audio volume: $volume', tag: 'AUDIO');
    try {
      await methodChannel.invokeMethod<void>('setAudioVolume', {
        'volume': volume,
      });
    } catch (e) {
      logError('Failed to set audio volume: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<bool> isAudioPlaying() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isAudioPlaying');
      return result ?? false;
    } catch (e) {
      logError('Failed to check audio playing state: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getAudioStats() async {
    logDebug('Getting audio stats', tag: 'AUDIO');
    try {
      final stats = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getAudioStats',
      );
      return stats?.cast<String, dynamic>() ?? {};
    } catch (e) {
      logError('Failed to get audio stats: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<void> releaseAudio() async {
    logInfo('Releasing audio resources', tag: 'AUDIO');
    try {
      await methodChannel.invokeMethod<void>('releaseAudio');
      logDebug('Audio released', tag: 'AUDIO');
    } catch (e) {
      logError('Failed to release audio: $e', tag: 'AUDIO');
      rethrow;
    }
  }

  @override
  Future<void> stopAudioStream({required int audioType}) async {
    // Stop (pause) a specific audio stream so AAOS deprioritizes that context
    // for volume control. This fixes the "stuck volume" issue where volume keys
    // continue to control a higher-priority context (e.g., NAV) after its audio ends.
    final streamName = switch (audioType) {
      1 => 'MEDIA',
      2 => 'NAVIGATION',
      3 => 'PHONE_CALL',
      4 => 'VOICE/SIRI',
      _ => 'UNKNOWN($audioType)',
    };
    logDebug('Stopping audio stream: $streamName', tag: 'AUDIO');
    try {
      await methodChannel.invokeMethod<void>('stopAudioStream', {
        'audioType': audioType,
      });
      logDebug('Audio stream stopped: $streamName', tag: 'AUDIO');
    } catch (e) {
      logError('Failed to stop audio stream $streamName: $e', tag: 'AUDIO');
      // Don't rethrow - stream stop is best-effort for AAOS volume control
    }
  }

  // ==================== Microphone Capture Methods ====================

  @override
  Future<bool> startMicrophoneCapture({int decodeType = 5}) async {
    logInfo('Starting microphone capture: decodeType=$decodeType', tag: 'MIC');
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'startMicrophoneCapture',
        {'decodeType': decodeType},
      );
      logDebug('Microphone capture started: $result', tag: 'MIC');
      return result ?? false;
    } catch (e) {
      logError('Failed to start microphone capture: $e', tag: 'MIC');
      rethrow;
    }
  }

  @override
  Future<void> stopMicrophoneCapture() async {
    logInfo('Stopping microphone capture', tag: 'MIC');
    try {
      await methodChannel.invokeMethod<void>('stopMicrophoneCapture');
      logDebug('Microphone capture stopped', tag: 'MIC');
    } catch (e) {
      logError('Failed to stop microphone capture: $e', tag: 'MIC');
      rethrow;
    }
  }

  @override
  Future<Uint8List?> readMicrophoneData({int maxBytes = 1920}) async {
    // Note: High-frequency operation - only log errors, not every call
    try {
      final data = await methodChannel.invokeMethod<List<dynamic>>(
        'readMicrophoneData',
        {'maxBytes': maxBytes},
      );
      if (data == null) return null;
      return Uint8List.fromList(data.cast<int>());
    } catch (e) {
      logError('Failed to read microphone data: $e', tag: 'MIC');
      rethrow;
    }
  }

  @override
  Future<bool> isMicrophoneCapturing() async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'isMicrophoneCapturing',
      );
      return result ?? false;
    } catch (e) {
      logError('Failed to check microphone capturing state: $e', tag: 'MIC');
      rethrow;
    }
  }

  @override
  Future<bool> hasMicrophonePermission() async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'hasMicrophonePermission',
      );
      return result ?? false;
    } catch (e) {
      logError('Failed to check microphone permission: $e', tag: 'MIC');
      rethrow;
    }
  }

  @override
  Future<int> getMicrophoneDecodeType() async {
    try {
      final result = await methodChannel.invokeMethod<int>(
        'getMicrophoneDecodeType',
      );
      return result ?? -1;
    } catch (e) {
      logError('Failed to get microphone decode type: $e', tag: 'MIC');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getMicrophoneStats() async {
    logDebug('Getting microphone stats', tag: 'MIC');
    try {
      final stats = await methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getMicrophoneStats',
      );
      return stats?.cast<String, dynamic>() ?? {};
    } catch (e) {
      logError('Failed to get microphone stats: $e', tag: 'MIC');
      rethrow;
    }
  }

  // ==================== MediaSession Methods (AAOS Integration) ====================

  @override
  Future<void> updateMediaMetadata({
    String? title,
    String? artist,
    String? album,
    String? appName,
    Uint8List? albumArt,
    int duration = 0,
  }) async {
    logDebug(
      'Updating media metadata: $title - $artist',
      tag: 'MEDIA_SESSION',
    );
    try {
      await methodChannel.invokeMethod<void>('updateMediaMetadata', {
        'title': title,
        'artist': artist,
        'album': album,
        'appName': appName,
        'albumArt': albumArt,
        'duration': duration,
      });
    } catch (e) {
      logError('Failed to update media metadata: $e', tag: 'MEDIA_SESSION');
      rethrow;
    }
  }

  @override
  Future<void> updatePlaybackState({
    required bool isPlaying,
    int position = 0,
  }) async {
    logDebug(
      'Updating playback state: ${isPlaying ? "playing" : "paused"}',
      tag: 'MEDIA_SESSION',
    );
    try {
      await methodChannel.invokeMethod<void>('updatePlaybackState', {
        'isPlaying': isPlaying,
        'position': position,
      });
    } catch (e) {
      logError('Failed to update playback state: $e', tag: 'MEDIA_SESSION');
      rethrow;
    }
  }

  @override
  Future<void> setMediaSessionConnecting() async {
    logDebug('Setting media session to connecting', tag: 'MEDIA_SESSION');
    try {
      await methodChannel.invokeMethod<void>('setMediaSessionConnecting');
    } catch (e) {
      logError('Failed to set connecting state: $e', tag: 'MEDIA_SESSION');
      rethrow;
    }
  }

  @override
  Future<void> setMediaSessionStopped() async {
    logDebug('Setting media session to stopped', tag: 'MEDIA_SESSION');
    try {
      await methodChannel.invokeMethod<void>('setMediaSessionStopped');
    } catch (e) {
      logError('Failed to set stopped state: $e', tag: 'MEDIA_SESSION');
      rethrow;
    }
  }
}
