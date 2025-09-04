import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../carlink_platform_interface.dart';
import '../../usb.dart';

class UsbManagerWrapper {
  static Future<List<UsbDeviceWrapper>> lookupForUsbDevice(
      List<Map<int, int>> vendorIdProductIdList) async {
    var devices = await CarlinkPlatform.instance.getDeviceList();

    var filtered = devices.where((device) => vendorIdProductIdList
        .where((pair) =>
            device.vendorId == pair.entries.first.key &&
            device.productId == pair.entries.first.value)
        .isNotEmpty);

    var wrapped = filtered.map((e) => UsbDeviceWrapper(e)).toList();

    return wrapped;
  }
}

class UsbDeviceWrapper {
  bool _isOpened = false;
  bool get isOpened => _isOpened;

  final UsbDevice _usbDevice;

  UsbEndpoint? _endpointIn;
  UsbEndpoint? _endpointOut;

  UsbDeviceWrapper(this._usbDevice);

  open() async {
    await CarlinkPlatform.instance.requestPermission(_usbDevice);

    await CarlinkPlatform.instance.openDevice(_usbDevice);

    var conf = await CarlinkPlatform.instance.getConfiguration(0);

    await CarlinkPlatform.instance.setConfiguration(conf);

    var interface = conf.interfaces.first;
    await CarlinkPlatform.instance.claimInterface(interface);

    _endpointIn = interface.endpoints
        .firstWhere((e) => e.direction == UsbEndpoint.DIRECTION_IN);

    _endpointOut = interface.endpoints
        .firstWhere((e) => e.direction == UsbEndpoint.DIRECTION_OUT);

    _isOpened = true;
  }

  close() async {
    await CarlinkPlatform.instance.closeDevice();
    _isOpened = false;
  }

  reset() async {
    await CarlinkPlatform.instance.resetDevice();
  }

  Future<void> startReadingLoop({
    required Function(int, Uint8List?) onMessage,
    required Function(String) onError,
    int timeout = 10000,
  }) {
    if (!isOpened) throw "UsbDevice not opened";
    if (_endpointIn == null) throw "UsbDevice endpointIn is null";

    return CarlinkPlatform.instance.startReadingLoop(
      _endpointIn!,
      timeout,
      onMessage: onMessage,
      onError: onError,
    );
  }

  Future<void> stopReadingLoop() {
    return CarlinkPlatform.instance.stopReadingLoop();
  }

  Future<Uint8List> read(int maxLength,
      {int timeout = 10000, bool isVideoData = false, int retryCount = 3}) async {
    if (!isOpened) throw StateError("UsbDevice not opened");
    if (_endpointIn == null) throw StateError("UsbDevice endpointIn is null");

    // Validate input parameters
    if (maxLength <= 0) throw ArgumentError("maxLength must be positive");
    if (timeout <= 0) throw ArgumentError("timeout must be positive");
    if (retryCount < 0) throw ArgumentError("retryCount must be non-negative");

    Exception? lastException;
    
    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        return await CarlinkPlatform.instance.bulkTransferIn(
          _endpointIn!,
          maxLength,
          _calculateTimeout(timeout, attempt),
          isVideoData: isVideoData,
        );
      } on PlatformException catch (e) {
        lastException = e;
        
        // Check for unrecoverable errors
        if (e.code == "IllegalState" && e.message?.contains("null") == true) {
          throw StateError("USB device connection lost: ${e.message}");
        }
        
        // If this is the last attempt, throw the exception
        if (attempt == retryCount) break;
        
        // Exponential backoff for retries
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      } catch (e) {
        lastException = e as Exception;
        if (attempt == retryCount) break;
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
    }
    
    throw lastException ?? Exception("Unknown USB read error");
  }

  Future<int> write(Uint8List data, {int timeout = 10000, int retryCount = 3}) async {
    if (!isOpened) throw StateError("UsbDevice not opened");
    if (_endpointOut == null) throw StateError("UsbDevice endpointOut is null");
    
    // Validate input parameters
    if (data.isEmpty) throw ArgumentError("data cannot be empty");
    if (timeout <= 0) throw ArgumentError("timeout must be positive");
    if (retryCount < 0) throw ArgumentError("retryCount must be non-negative");

    Exception? lastException;
    
    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        return await CarlinkPlatform.instance.bulkTransferOut(
          _endpointOut!,
          data,
          _calculateTimeout(timeout, attempt),
        );
      } on PlatformException catch (e) {
        lastException = e;
        
        // Check for unrecoverable errors
        if (e.code == "IllegalState" && e.message?.contains("null") == true) {
          throw StateError("USB device connection lost: ${e.message}");
        }
        if (e.code == "USBWriteError" && e.message?.contains("actualLength=-1") == true) {
          throw StateError("USB device disconnected during write");
        }
        
        // If this is the last attempt, throw the exception
        if (attempt == retryCount) break;
        
        // Exponential backoff for retries
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      } catch (e) {
        lastException = e as Exception;
        if (attempt == retryCount) break;
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
    }
    
    throw lastException ?? Exception("Unknown USB write error");
  }
  
  // Calculate timeout with exponential backoff
  int _calculateTimeout(int baseTimeout, int attempt) {
    return baseTimeout + (baseTimeout * attempt ~/ 2);
  }
}
