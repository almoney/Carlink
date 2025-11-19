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
      } else {
        logWarn('Unknown method call: ${call.method}', tag: 'PLATFORM');
      }
    });
  }

  void setLogHandler(Function(String)? logHandler) {
    _logHandler = logHandler;
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
}
