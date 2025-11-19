import 'dart:async';
import 'dart:typed_data';

import '../common.dart';
import '../log.dart';

import 'readable.dart';
import 'sendable.dart';
import 'usb/usb_device_wrapper.dart';

class Adaptr {
  final UsbDeviceWrapper _usbDevice;

  Function(Message)? _messageHandler;
  Function({String? error})? _errorHandler;

  final Function(String) _logHandler;

  Timer? _heartBeat;
  DateTime? _nextHeartbeat;

  late final int _readTimeout;
  late final int _writeTimeout;

  // Performance tracking
  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int _sendErrors = 0;
  int _receiveErrors = 0;
  DateTime? _sessionStart;
  DateTime? _lastHeartbeat;
  int _heartbeatsSent = 0;
  int _initMessagesCount = 0;

  Adaptr(
    this._usbDevice,
    this._messageHandler,
    this._errorHandler,
    this._logHandler, {
    int readTimeout = 30000,
    writeTimeout = 1000,
  }) {
    _readTimeout = readTimeout;
    _writeTimeout = writeTimeout;
    _sessionStart = DateTime.now();

    logInfo(
      'Adapter created: readTimeout=${readTimeout}ms writeTimeout=${writeTimeout}ms',
      tag: 'ADAPTR',
    );
  }

  Future<void> start() async {
    logInfo('Starting adapter connection sequence', tag: 'ADAPTR');
    final stopwatch = Stopwatch()..start();

    _logHandler('Adapter initializing');

    if (!_usbDevice.isOpened) {
      _logHandler('usbDevice not opened');
      _errorHandler?.call(error: 'usbDevice not opened');
      logError('Cannot start adapter: USB device not opened', tag: 'ADAPTR');
      return;
    }

    // START HEARTBEAT FIRST - provides firmware keepalive during initialization
    // This allows firmware to stabilize while receiving regular heartbeat signals
    // before processing configuration commands
    _startCompensatingHeartbeat();
    logInfo(
      'Heartbeat started before initialization (firmware stabilization)',
      tag: 'ADAPTR',
    );

    final config = DEFAULT_CONFIG;

    logDebug(
      'Using configuration: ${config.width}x${config.height}@${config.fps}fps wifi=${config.wifiType} mic=${config.micType}',
      tag: 'ADAPTR',
    );

    // Notify message handler about the actual configuration being used
    // This allows the status monitor to show the correct resolution/FPS immediately
    if (_messageHandler != null) {
      final configMessage = AdaptrConfigurationMessage(config);
      _messageHandler!(configMessage);
    }

    final initMessages = [
      SendNumber(config.dpi, FileAddress.DPI),
      SendOpen(config),
      SendNumber(config.hand.id, FileAddress.HAND_DRIVE_MODE),
      SendString(config.boxName, FileAddress.BOX_NAME),
      SendString(_generateAirplayConfig(config), FileAddress.AIRPLAY_CONFIG),
      SendBoolean(
        false,
        FileAddress.CHARGE_MODE,
      ), // Matches pi-carplay sequence
      SendCommand(
        config.wifiType == '5ghz'
            ? CommandMapping.wifi5g
            : CommandMapping.wifi24g,
      ),
      SendBoxSettings(config, null),
      // Note: UdiskMode configuration requires firmware-level setting
      // This sets runtime value only; persistence requires CLI: riddleBoxCfg -s UdiskMode 1
      SendCommand(CommandMapping.wifiEnable),
      SendCommand(
        config.micType == 'box' ? CommandMapping.boxMic : CommandMapping.mic,
      ),
      SendCommand(
        config.audioTransferMode
            ? CommandMapping.audioTransferOn
            : CommandMapping.audioTransferOff,
      ),
      if (config.androidWorkMode == true)
        SendBoolean(config.androidWorkMode!, FileAddress.ANDROID_WORK_MODE),
    ];

    _initMessagesCount = initMessages.length;
    logInfo(
      'Sending $_initMessagesCount initialization messages (heartbeat already running)',
      tag: 'ADAPTR',
    );

    for (int i = 0; i < initMessages.length; i++) {
      final message = initMessages[i];
      logDebug(
        'Init message ${i + 1}/${initMessages.length}: ${message.runtimeType}',
        tag: 'ADAPTR',
      );
      final success = await send(message);
      if (!success) {
        logError(
          'Failed to send init message ${i + 1}: ${message.runtimeType}',
          tag: 'ADAPTR',
        );
      }
    }

    stopwatch.stop();
    logInfo(
      'Initialization sequence completed in ${stopwatch.elapsedMilliseconds}ms',
      tag: 'ADAPTR',
    );

    // Schedule wifiConnect command with timeout (matches pi-carplay behavior)
    // This ensures wifiConnect is sent even if Opened message doesn't arrive (cold start issue)
    unawaited(
      Future.delayed(const Duration(milliseconds: 600), () async {
        logInfo('Sending wifiConnect command (timeout-based)', tag: 'ADAPTR');
        await send(SendCommand(CommandMapping.wifiConnect));
      }),
    );

    logInfo('Starting message reading loop', tag: 'ADAPTR');
    await _readLoop();
  }

  Future<void> close() async {
    logInfo('Closing adapter connection', tag: 'ADAPTR');
    final stopwatch = Stopwatch()..start();

    _stopCompensatingHeartbeat();

    _errorHandler = null;
    _messageHandler = null;

    try {
      await _usbDevice.stopReadingLoop();
      await _usbDevice.close();

      stopwatch.stop();
      _logPerformanceStats();
      logInfo(
        'Adapter closed successfully in ${stopwatch.elapsedMilliseconds}ms',
        tag: 'ADAPTR',
      );

      // Reset stats for next session
      _resetStats();
    } catch (e) {
      stopwatch.stop();
      logError(
        'Failed to close adapter after ${stopwatch.elapsedMilliseconds}ms: $e',
        tag: 'ADAPTR',
      );
    }
  }

  Future<bool> send(SendableMessage message) async {
    final stopwatch = Stopwatch()..start();

    try {
      final data = message.serialise();

      // Skip logging individual heartbeats to reduce noise
      if (message.type != MessageType.HeartBeat) {
        if (message is SendCommand) {
          // Special logging for audio/mic configuration commands
          String commandDescription = '';
          switch (message.value) {
            case CommandMapping.mic:
              commandDescription = 'MicSource: os (host app microphone)';
              break;
            case CommandMapping.boxMic:
              commandDescription = 'MicSource: box (adapter built-in mic)';
              break;
            case CommandMapping.audioTransferOn:
              commandDescription =
                  'AudioTransfer: ON (direct Bluetooth to car)';
              break;
            case CommandMapping.audioTransferOff:
              commandDescription = 'AudioTransfer: OFF (through adapter)';
              break;
            default:
              commandDescription = message.value.name;
          }
          _logHandler(
            '[SEND] Command 0x${message.value.id.toRadixString(16).padLeft(2, '0').toUpperCase()} ($commandDescription)',
          );
        } else {
          // Comment out Touch and MultiTouch logging to reduce noise
          if (message.type.name != 'MultiTouch' &&
              message.type.name != 'Touch') {
            _logHandler('[SEND] ${message.type.name}');
          }
        }
      }

      final length = await _usbDevice.write(data, timeout: _writeTimeout);
      stopwatch.stop();

      _messagesSent++;
      _bytesSent += data.length;

      if (data.length == length) {
        if (message.type != MessageType.HeartBeat &&
            message.type.name != 'MultiTouch' &&
            message.type.name != 'Touch') {
          logDebug(
            'Send successful: ${message.type.name} ${data.length}B in ${stopwatch.elapsedMicroseconds}μs',
            tag: 'ADAPTR',
          );
        }
        return true;
      } else {
        _sendErrors++;
        logWarn(
          'Send incomplete: ${message.type.name} sent $length/${data.length} bytes',
          tag: 'ADAPTR',
        );
      }
    } catch (e) {
      stopwatch.stop();
      _sendErrors++;
      _logHandler("send error $e");
      _errorHandler?.call(error: e.toString());
      logError(
        'Send failed: ${message.type.name} after ${stopwatch.elapsedMicroseconds}μs: $e',
        tag: 'ADAPTR',
      );
    }

    return false;
  }

  Future<void> _readLoop() async {
    await _usbDevice.startReadingLoop(
      //
      onMessage: (type, data) async {
        final stopwatch = Stopwatch()..start();

        final header = MessageHeader(
          data?.length ?? 0,
          MessageType.fromId(type),
        );
        final message = header.toMessage(data?.buffer.asByteData());

        // Log raw USB message (excluding video/audio to prevent log spam)
        if (type != 0x06 && type != 0x07) {
          // Exclude VideoData (0x06) and AudioData (0x07)
          final dataStr = data != null ? _formatRawData(data, type) : 'null';
          logDebug(
            'RAW USB RX: Type=0x${type.toRadixString(16).padLeft(2, '0')} Len=${data?.lengthInBytes ?? 0} Data=$dataStr',
            tag: 'USB_RAW',
          );
        } else if (type == 0x06) {
          // Log VideoData separately with VIDEO tag
          final dataStr = data != null ? _formatRawData(data, type) : 'null';
          logDebug(
            'RAW VIDEO RX: Type=0x${type.toRadixString(16).padLeft(2, '0')} Len=${data?.lengthInBytes ?? 0} Data=$dataStr',
            tag: 'VIDEO',
          );
        } else if (type == 0x07) {
          // Log AudioData separately with AUDIO tag
          final dataStr = data != null ? _formatRawData(data, type) : 'null';
          logDebug(
            'RAW AUDIO RX: Type=0x${type.toRadixString(16).padLeft(2, '0')} Len=${data?.lengthInBytes ?? 0} Data=$dataStr',
            tag: 'AUDIO',
          );
        }

        if (message != null) {
          _messagesReceived++;
          _bytesReceived += data?.lengthInBytes ?? 0;

          // Enhanced logging for AudioData with parsed details
          if (message is AudioData) {
            _logHandler(
              "[RECV] ${message.toString()}, length: ${data?.lengthInBytes ?? 0}",
            );
            logDebug(
              'AudioData received: samples=${message.data?.length ?? 0} bytes=${data?.lengthInBytes ?? 0}',
              tag: 'AUDIO',
            );
          } else if (message is MediaData) {
            // MediaData logging temporarily disabled for noise reduction
            // _logHandler("[RECV] ${message.header.type.name}, length: ${data?.lengthInBytes ?? 0}");
          } else {
            _logHandler(
              "[RECV] ${message.header.type.name} ${(message is Command ? message.value.name : "")}, length: ${data?.lengthInBytes ?? 0}",
            );
          }

          try {
            _messageHandler?.call(message);
          } catch (e) {
            _receiveErrors++;
            _logHandler("Error handling message, ${e.toString()}");
            logError(
              'Message handler error: ${message.header.type.name} - $e',
              tag: 'ADAPTR',
            );
          }

          if (message is Opened) {
            logDebug('Received Opened message', tag: 'ADAPTR');
          }

          stopwatch.stop();
          if (message.header.type.name != 'MediaData') {
            logDebug(
              'Message processed: ${message.header.type.name} in ${stopwatch.elapsedMicroseconds}μs',
              tag: 'ADAPTR',
            );
          }
        } else {
          _receiveErrors++;
          logWarn(
            'Failed to parse message: type=$type length=${data?.lengthInBytes ?? 0}',
            tag: 'ADAPTR',
          );
        }
      },
      //
      onError: (error) {
        _receiveErrors++;
        _logHandler("ReadingLoopError $error");
        _errorHandler?.call(error: "ReadingLoopError $error");
        logError('Reading loop error: $error', tag: 'ADAPTR');
      },
      //
      timeout: _readTimeout,
    );
  }

  /// Generate AirPlay configuration string for the adapter
  String _generateAirplayConfig(AdaptrConfig config) {
    // Format matches pi-carplay: camelCase keys with spaced formatting
    final airplayConfig =
        '''oemIconVisible = ${config.oemIconVisible ? '1' : '0'}
name = ${config.boxName}
model = Magic-Car-Link-1.00
oemIconPath = /etc/oem_icon.png
oemIconLabel = ${config.boxName}
''';
    logDebug(
      'Generated AirPlay config: ${airplayConfig.replaceAll('\n', ' | ')}',
      tag: 'ADAPTR',
    );
    return airplayConfig;
  }

  // Performance tracking methods
  void _logPerformanceStats() {
    final sessionDuration = _sessionStart != null
        ? DateTime.now().difference(_sessionStart!).inSeconds
        : 0;
    final sendThroughput = sessionDuration > 0
        ? (_bytesSent / sessionDuration / 1024).toStringAsFixed(1)
        : '0.0';
    final receiveThroughput = sessionDuration > 0
        ? (_bytesReceived / sessionDuration / 1024).toStringAsFixed(1)
        : '0.0';
    final sendSuccessRate = _messagesSent + _sendErrors > 0
        ? (_messagesSent / (_messagesSent + _sendErrors) * 100).toStringAsFixed(
            1,
          )
        : '100.0';
    final receiveSuccessRate = _messagesReceived + _receiveErrors > 0
        ? (_messagesReceived / (_messagesReceived + _receiveErrors) * 100)
              .toStringAsFixed(1)
        : '100.0';
    final lastHeartbeatAge = _lastHeartbeat != null
        ? DateTime.now().difference(_lastHeartbeat!).inSeconds
        : 0;

    logInfo('Adapter Performance Summary:', tag: 'ADAPTR');
    logInfo(
      '  Session: ${sessionDuration}s | Init: $_initMessagesCount msgs | Heartbeats: $_heartbeatsSent (last: ${lastHeartbeatAge}s ago)',
      tag: 'ADAPTR',
    );
    logInfo(
      '  TX: $_messagesSent msgs / ${(_bytesSent / 1024).toStringAsFixed(1)}KB / ${sendThroughput}KB/s ($sendSuccessRate% success)',
      tag: 'ADAPTR',
    );
    logInfo(
      '  RX: $_messagesReceived msgs / ${(_bytesReceived / 1024).toStringAsFixed(1)}KB / ${receiveThroughput}KB/s ($receiveSuccessRate% success)',
      tag: 'ADAPTR',
    );
    logInfo('  Errors: TX=$_sendErrors RX=$_receiveErrors', tag: 'ADAPTR');
  }

  void _resetStats() {
    _messagesSent = 0;
    _messagesReceived = 0;
    _bytesSent = 0;
    _bytesReceived = 0;
    _sendErrors = 0;
    _receiveErrors = 0;
    _sessionStart = null;
    _lastHeartbeat = null;
    _heartbeatsSent = 0;
    _initMessagesCount = 0;
    _nextHeartbeat = null;
  }

  /// Start compensating heartbeat timer that maintains exact 2s interval
  /// regardless of send() execution time. Prevents drift from USB latency.
  void _startCompensatingHeartbeat() {
    _heartBeat?.cancel();
    _nextHeartbeat = DateTime.now().add(const Duration(seconds: 2));

    _logHandler('Heartbeat started (every 2s, compensating)');
    logDebug(
      'Starting compensating heartbeat timer (2s interval)',
      tag: 'ADAPTR',
    );

    _scheduleNextHeartbeat();
  }

  /// Stop compensating heartbeat timer
  void _stopCompensatingHeartbeat() {
    if (_heartBeat != null) {
      _logHandler('Heartbeat stopped');
      _heartBeat?.cancel();
      _heartBeat = null;
      _nextHeartbeat = null;
      logDebug('Heartbeat timer cancelled', tag: 'ADAPTR');
    }
  }

  /// Schedule next heartbeat based on target time, compensating for execution delays
  void _scheduleNextHeartbeat() {
    if (_nextHeartbeat == null) return;

    final now = DateTime.now();
    final delay = _nextHeartbeat!.difference(now);

    // If we're behind schedule (negative delay), fire immediately
    final actualDelay = delay.isNegative ? Duration.zero : delay;

    // Log if heartbeat is running late
    if (delay.isNegative) {
      logWarn(
        'Heartbeat running behind schedule by ${delay.abs().inMilliseconds}ms',
        tag: 'ADAPTR',
      );
    }

    _heartBeat = Timer(actualDelay, () async {
      // CRITICAL: Early exit if stopped during close() (prevents USB write to closed device)
      if (_nextHeartbeat == null) return;

      _lastHeartbeat = DateTime.now();
      _heartbeatsSent++;

      final success = await send(HeartBeat());
      if (!success) {
        logError(
          'Heartbeat send failed (count: $_heartbeatsSent)',
          tag: 'ADAPTR',
        );
      }

      // Check again after await point - could have been closed during send()
      if (_nextHeartbeat == null) return;

      // Schedule next heartbeat based on original cadence, not completion time
      // This maintains exact 2s interval regardless of send() duration
      _nextHeartbeat = _nextHeartbeat!.add(const Duration(seconds: 2));
      _scheduleNextHeartbeat();
    });
  }

  /// Format raw USB data for logging (limited to prevent excessive log size)
  String _formatRawData(Uint8List data, int type) {
    // Check if USB_RAW tag is enabled (Adapter Messages logging level)
    // If enabled, show full message data for debugging
    final bool showFullMessage = isTagEnabled('USB_RAW');

    final int maxBytes = showFullMessage
        ? data.length
        : 32; // Show all data when USB_RAW enabled
    final int length = data.length > maxBytes ? maxBytes : data.length;
    final String hex = data
        .take(length)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final String truncated = data.length > maxBytes
        ? '...(${data.length - maxBytes} more)'
        : '';

    // Add known command names for common types
    final String typeName = _getCommandTypeName(type);

    return '$typeName [$hex]$truncated';
  }

  /// Get human-readable command type name based on CPC200-CCPA protocol
  String _getCommandTypeName(int type) {
    switch (type) {
      case 0x01:
        return 'Open';
      case 0x02:
        return 'Plugged';
      case 0x03:
        return 'Phase';
      case 0x04:
        return 'Unplugged';
      case 0x05:
        return 'Touch';
      case 0x06:
        return 'VideoData';
      case 0x07:
        return 'AudioData';
      case 0x08:
        return 'Command';
      case 0x09:
        return 'LogoType';
      case 0x0C:
        return 'BluetoothPIN';
      case 0x0D:
        return 'BluetoothDeviceName';
      case 0x0E:
        return 'WifiDeviceName';
      case 0x0F:
        return 'DiscPhone';
      case 0x12:
        return 'BluetoothPairedList';
      case 0x14:
        return 'MfgInfo';
      case 0x15:
        return 'CloseAdaptr';
      case 0x17:
        return 'MultiTouch';
      case 0x18:
        return 'HiCarLink';
      case 0x19:
        return 'BoxSettings';
      case 0x23:
        return 'NetworkMacAddress';
      case 0x24:
        return 'NetworkMacAddressAlt';
      case 0x2A:
        return 'MediaPlaybackTime';
      case 0xAA:
        return 'HeartBeat';
      case 0xCC:
        return 'SwVer';
      default:
        return 'Unknown';
    }
  }

  // Public performance getters for monitoring
  Map<String, dynamic> getPerformanceStats() {
    final sessionDuration = _sessionStart != null
        ? DateTime.now().difference(_sessionStart!).inSeconds
        : 0;
    final lastHeartbeatAge = _lastHeartbeat != null
        ? DateTime.now().difference(_lastHeartbeat!).inSeconds
        : 0;

    return {
      'sessionDurationSeconds': sessionDuration,
      'initMessagesCount': _initMessagesCount,
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
      'bytesSent': _bytesSent,
      'bytesReceived': _bytesReceived,
      'sendErrors': _sendErrors,
      'receiveErrors': _receiveErrors,
      'heartbeatsSent': _heartbeatsSent,
      'lastHeartbeatSecondsAgo': lastHeartbeatAge,
      'sendThroughputKBps': sessionDuration > 0
          ? _bytesSent / sessionDuration / 1024
          : 0.0,
      'receiveThroughputKBps': sessionDuration > 0
          ? _bytesReceived / sessionDuration / 1024
          : 0.0,
      'sendSuccessRate': _messagesSent + _sendErrors > 0
          ? _messagesSent / (_messagesSent + _sendErrors)
          : 1.0,
      'receiveSuccessRate': _messagesReceived + _receiveErrors > 0
          ? _messagesReceived / (_messagesReceived + _receiveErrors)
          : 1.0,
      'usbStats': _usbDevice.getPerformanceStats(),
    };
  }
}
