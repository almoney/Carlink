import 'dart:async';

import 'package:carlink/carlink_platform_interface.dart';
import 'package:flutter/foundation.dart';

import 'driver/adaptr_driver.dart';
import 'driver/sendable.dart';
import 'driver/readable.dart';
import 'driver/usb/usb_device_wrapper.dart';
import 'common.dart';
import 'log.dart';

// ignore: constant_identifier_names
const USB_WAIT_PERIOD_MS = 3000;

enum CarlinkState { disconnected, connecting, deviceConnected, streaming }

class CarlinkMediaInfo {
  final String? songTitle;
  final String? songArtist;
  final String? albumName;
  final String? appName;
  final Uint8List? albumCoverImageData;

  CarlinkMediaInfo({
    required this.songTitle,
    required this.songArtist,
    required this.albumName,
    required this.appName,
    required this.albumCoverImageData,
  });
}

class Carlink {
  Timer? _pairTimeout;
  Timer? _frameInterval;

  Adaptr? _adaptrDriver;

  CarlinkState state = CarlinkState.connecting;

  late final AdaptrConfig _config;

  late final Function(int?) _textureHandler;
  late final Function(String)? _logHandler;
  late final Function()? _hostUIHandler;
  late final Function(CarlinkState)? _stateHandler;
  late final Function(CarlinkMediaInfo mediaInfo)? _metadataHandler;
  late final Function(Message)? _messageInterceptor;

  Carlink({
    required AdaptrConfig config,
    required Function(int? textureId) onTextureChanged,
    Function(CarlinkState)? onStateChanged,
    Function(CarlinkMediaInfo)? onMediaInfoChanged,
    Function(String)? onLogMessage,
    Function()? onHostUIPressed,
    Function(Message)? onMessageIntercepted,
  }) {
    _config = config;
    _textureHandler = onTextureChanged;
    _metadataHandler = onMediaInfoChanged;
    _stateHandler = onStateChanged;
    _logHandler = onLogMessage;
    _hostUIHandler = onHostUIPressed;
    _messageInterceptor = onMessageIntercepted;

    CarlinkPlatform.setLogHandler(_logHandler);

    // create texture
    CarlinkPlatform.instance
        .createTexture(_config.width, _config.height)
        .then(_textureHandler);
  }

  Future<UsbDeviceWrapper> _findDevice() async {
    UsbDeviceWrapper? device;
    bool loggedSearching = false;

    while (device == null) {
      try {
        final deviceList = await UsbManagerWrapper.lookupForUsbDevice(
          knownDevices,
        );
        device = deviceList.firstOrNull;
      } catch (err) {
        if (!loggedSearching) {
          _log('Searching for Carlinkit device...');
          loggedSearching = true;
        }
        // ^ requestDevice throws an error when no device is found, so keep retrying
      }

      if (device == null) {
        if (!loggedSearching) {
          _log('Searching for Carlinkit device...');
          loggedSearching = true;
        }
        await Future.delayed(const Duration(milliseconds: USB_WAIT_PERIOD_MS));
      }
    }

    _log('Carlinkit device found!');
    return device;
  }

  void _setState(CarlinkState newState) {
    if (state != newState) {
      state = newState;
      if (_stateHandler != null) {
        _stateHandler(state);
      }
    }
  }

  Future<void> start() async {
    _setState(CarlinkState.connecting);

    if (_adaptrDriver != null) {
      await stop();
    }

    await CarlinkPlatform.instance.resetH264Renderer();

    // Find device to "reset" first
    var device = await _findDevice();

    await device.open();
    await device.reset();
    await device.close();
    // Resetting the device causes an unplug event in node-usb
    // so subsequent writes fail with LIBUSB_ERROR_NO_DEVICE
    // or LIBUSB_TRANSFER_ERROR

    _log('Reset device, finding again...');
    await Future.delayed(const Duration(milliseconds: USB_WAIT_PERIOD_MS));
    // ^ Device disappears after reset for 1-3 seconds

    device = await _findDevice();
    _log('found & opening');

    _adaptrDriver = Adaptr(
      device,
      _handleAdaptrMessage,
      _handleAdaptrError,
      _log,
    );

    await device.open();
    await _adaptrDriver?.start();

    _clearPairTimeout();
    _pairTimeout = Timer(const Duration(seconds: 15), () async {
      await _adaptrDriver?.send(SendCommand(CommandMapping.wifiPair));
    });
  }

  Future<void> restart() async {
    await stop();
    await Future.delayed(const Duration(seconds: 2));
    await start();
  }

  Future<void> stop() async {
    try {
      _clearPairTimeout();
      _clearFrameInterval();
      await _adaptrDriver?.close();
    } catch (err) {
      _log(err.toString());
    }

    _setState(CarlinkState.disconnected);
  }

  /// Dispose method following Flutter lifecycle guidelines for resource cleanup.
  /// Should be called when the Carlink instance is no longer needed to prevent memory leaks.
  Future<void> dispose() async {
    // Cancel any active timers to prevent memory leaks
    _clearPairTimeout();
    _clearFrameInterval();

    // Close adapter connection if active
    try {
      await _adaptrDriver?.close();
    } catch (error) {
      _log('Error closing adapter during dispose: $error');
    }

    // Following Flutter texture registry guidelines: remove texture to prevent memory leaks
    try {
      await CarlinkPlatform.instance.removeTexture();
      _log('Texture removed during dispose');
    } catch (error) {
      _log('Error removing texture during dispose: $error');
    }

    // Set state to disconnected for proper cleanup
    _setState(CarlinkState.disconnected);
  }

  Future<bool> sendKey(CommandMapping action) {
    return _adaptrDriver!.send(SendCommand(action));
  }

  Future<bool> sendTouch(TouchAction type, double x, double y) {
    return _adaptrDriver!.send(
      SendTouch(type, x / _config.width, y / _config.height),
    );
  }

  Future<bool> sendMultiTouch(List<TouchItem> touches) {
    return _adaptrDriver!.send(SendMultiTouch(touches));
  }

  Future<bool> sendMessage(SendableMessage message) {
    return _adaptrDriver!.send(message);
  }

  //------------------------------
  // Private
  //------------------------------

  void _log(String message) {
    _logHandler?.call(message);
  }

  Future<void> _handleAdaptrMessage(Message message) async {
    // Forward all messages to the interceptor for status monitoring
    _messageInterceptor?.call(message);

    if (message is Plugged) {
      _clearPairTimeout();
      _clearFrameInterval();

      final phoneTypeConfig = _config.phoneConfig[message.phoneType];
      final interval = phoneTypeConfig?["frameInterval"];
      if (interval != null) {
        _frameInterval = Timer.periodic(Duration(milliseconds: interval), (
          timer,
        ) async {
          await _adaptrDriver?.send(SendCommand(CommandMapping.frame));
        });
      }
      _setState(CarlinkState.deviceConnected);
    }
    //
    else if (message is Unplugged) {
      await restart();
    }
    //
    else if (message is VideoData) {
      _clearPairTimeout();

      if (state != CarlinkState.streaming) {
        logInfo('Video streaming started', tag: 'VIDEO');
        _setState(CarlinkState.streaming);
      }
      logDebug(
        'VideoData received: flags=${message.flags} len=${message.length}',
        tag: 'VIDEO',
      );
    }
    //
    // AudioData processing disabled - foundation preserved for future expansion
    // else if (message is AudioData) {
    //   _clearPairTimeout();
    // }
    //
    else if (message is MediaData) {
      _clearPairTimeout();
      _processMediaMetadata(message.payload);
    }
    //
    else if (message is Command) {
      if (message.value == CommandMapping.requestHostUI) {
        _hostUIHandler?.call();
      } else if (message.value == CommandMapping.projectionDisconnected) {
        // Projection session disconnected - restart adapter session
        await restart();
      }
    }

    // Trigger internal event logic
    if (message is AudioData && message.command != null) {
      switch (message.command) {
        case AudioCommand.AudioSiriStart:
        case AudioCommand.AudioPhonecallStart:
          //            mic.start()
          break;
        case AudioCommand.AudioSiriStop:
        case AudioCommand.AudioPhonecallStop:
          //            mic.stop()
          break;

        default:
          break;
      }
    }
  }

  Future<void> _handleAdaptrError({String? error}) async {
    _clearPairTimeout();
    _clearFrameInterval();

    // Enhanced error handling based on Flutter platform channel best practices
    try {
      // Attempt graceful recovery first
      if (await _attemptGracefulRecovery(error)) {
        return;
      }
    } catch (e) {
      logError('Graceful recovery failed: $e', tag: 'ERROR_RECOVERY');
    }

    // Fall back to existing restart logic (preserves heartbeat handling)
    await restart();
  }

  /// Attempts graceful recovery from USB errors without full restart
  /// Based on Android USB host documentation best practices
  Future<bool> _attemptGracefulRecovery(String? error) async {
    if (error == null) return false;

    // Classify error type for appropriate recovery action
    if (error.contains("device") && error.contains("null")) {
      // Device disconnected - wait for reconnection
      await Future.delayed(Duration(seconds: 3));
      return await _attemptDeviceReconnection();
    }

    if (error.contains("timeout") || error.contains("actualLength=-1")) {
      // Transfer timeout - retry connection
      return await _retryConnection();
    }

    if (error.contains("permission")) {
      // Permission issue - cannot recover gracefully
      return false;
    }

    return false;
  }

  /// Attempts to reestablish device connection
  Future<bool> _attemptDeviceReconnection() async {
    try {
      // Use existing start() method which handles device discovery
      await start();

      // Check if connection was successful
      return state == CarlinkState.deviceConnected ||
          state == CarlinkState.streaming;
    } catch (e) {
      logError('Device reconnection failed: $e', tag: 'ERROR_RECOVERY');
    }
    return false;
  }

  /// Attempts to retry the current connection
  Future<bool> _retryConnection() async {
    try {
      // Use existing restart logic but without full delay
      await stop();
      await Future.delayed(
        Duration(milliseconds: 1000),
      ); // Shorter delay than full restart
      await start();

      // Check if connection was reestablished
      return state == CarlinkState.deviceConnected ||
          state == CarlinkState.streaming;
    } catch (e) {
      logError('Connection retry failed: $e', tag: 'ERROR_RECOVERY');
    }
    return false;
  }

  void _clearPairTimeout() {
    // Following Flutter best practices: check isActive before canceling
    if (_pairTimeout?.isActive == true) {
      _pairTimeout!.cancel();
    }
    _pairTimeout = null;
  }

  void _clearFrameInterval() {
    // Following Flutter best practices: check isActive before canceling
    if (_frameInterval?.isActive == true) {
      _frameInterval!.cancel();
    }
    _frameInterval = null;
  }

  ///////////////

  String? _lastMediaLyrics;
  String? _lastMediaArtistName;
  String? _lastMediaSongName;
  String? _lastMediaAlbumName;
  String? _lastMediaAPPName;
  Uint8List? _lastAlbumCover;

  void _processMediaMetadata(Map<String, dynamic> metadata) {
    // final mdata = metadata;
    if (metadata.length == 1 && metadata.keys.contains("MediaSongPlayTime")) {
      // skip timing
    } else {
      final String? mediaLyrics = metadata["MediaLyrics"];
      final String? mediaArtistName = metadata["MediaArtistName"];
      final String? mediaSongName = metadata["MediaSongName"];
      final String? mediaAlbumName = metadata["MediaAlbumName"];
      final String? mediaAPPName = metadata["MediaAPPName"];
      final Uint8List? albumCover = metadata["AlbumCover"];

      // on app name or lyrics update - reset
      if (mediaAPPName != null ||
          (mediaLyrics != null && _lastMediaLyrics != mediaLyrics))
      //
      {
        _lastMediaLyrics = null;
        _lastMediaSongName = null;

        _lastMediaArtistName = null;
        _lastMediaAlbumName = null;

        _lastAlbumCover = null;
      }

      if (mediaAPPName != null && mediaAPPName.isNotEmpty) {
        _lastMediaAPPName = mediaAPPName;
      }
      if (mediaArtistName != null && mediaArtistName.isNotEmpty) {
        _lastMediaArtistName = mediaArtistName;
      }
      if (mediaSongName != null && mediaSongName.isNotEmpty) {
        _lastMediaSongName = mediaSongName;
      }
      if (mediaAlbumName != null && mediaAlbumName.isNotEmpty) {
        _lastMediaAlbumName = mediaAlbumName;
      }
      if (mediaLyrics != null && mediaLyrics.isNotEmpty) {
        _lastMediaLyrics = mediaLyrics;
      }
      if (albumCover != null) {
        _lastAlbumCover = albumCover;
      }

      if (_metadataHandler != null) {
        _metadataHandler(
          CarlinkMediaInfo(
            songTitle: (_lastMediaLyrics ?? _lastMediaSongName) ?? " ",
            songArtist: _lastMediaArtistName ?? " ",
            albumName: _lastMediaAlbumName,
            appName: _lastMediaAPPName,
            albumCoverImageData: _lastAlbumCover,
          ),
        );
      }
    }
  }
}
