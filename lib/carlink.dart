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
  Timer? _micSendTimer;

  Adaptr? _adaptrDriver;

  CarlinkState state = CarlinkState.connecting;

  late final AdaptrConfig _config;

  // Audio playback state
  bool _audioEnabled = true;
  bool _audioInitialized = false;
  int _currentAudioDecodeType = 4; // Default to 48kHz stereo
  int _audioPacketCount = 0; // DEBUG: Counter for periodic logging
  int _zeroPacketCount = 0; // Counter for filtered zero-filled packets

  // Microphone capture state
  bool _microphoneEnabled = true;
  bool _isMicrophoneCapturing = false;
  int _currentMicDecodeType = 5; // Default to 16kHz mono (Siri)
  int _currentMicAudioType = 1; // Default to voice command (Siri/Google Assistant)
  int _micWarmupPacketsSent = 0; // Counter for skipping initial zero-filled packets
  static const int _micWarmupPacketsToSkip = 5; // Skip first 5 packets (~100ms)

  // Audio stream context tracking for logging/debugging purposes only.
  //
  // NOTE: These variables are intentionally NOT used for audio routing.
  // The adapter correctly tags packets with audioType (1=Media, 2=Nav, etc.)
  // so we use message.audioType directly for AAOS CarAudioContext routing.
  //
  // Previously, a state machine approach was used that overrode the adapter's
  // audioType based on commands (AudioNaviStart, etc.). This caused issues when
  // streams were interleaved (e.g., nav prompt during music) - packets from one
  // stream would be routed to the wrong AudioTrack, causing format mismatches
  // and white noise. See log analysis from Nov 2025 session.
  //
  // These variables are retained for debugging context changes in logs.
  // Values: 1=MEDIA, 2=NAVIGATION, 3=PHONE_CALL, 4=SIRI
  // ignore: unused_field
  int _currentAudioStreamContext = 1;
  // ignore: unused_field
  DateTime? _lastAudioContextChange;

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
    bool enableAudio = true,
    bool enableMicrophone = true,
  }) {
    _audioEnabled = enableAudio;
    _microphoneEnabled = enableMicrophone;
    _config = config;
    _textureHandler = onTextureChanged;
    _metadataHandler = onMediaInfoChanged;
    _stateHandler = onStateChanged;
    _logHandler = onLogMessage;
    _hostUIHandler = onHostUIPressed;
    _messageInterceptor = onMessageIntercepted;

    CarlinkPlatform.setLogHandler(_logHandler);

    // Set up media control handlers for AAOS steering wheel buttons
    CarlinkPlatform.setMediaControlHandlers(
      onPlay: () => sendKey(CommandMapping.play),
      onPause: () => sendKey(CommandMapping.pause),
      onStop: () => sendKey(CommandMapping.pause),
      onNext: () => sendKey(CommandMapping.next),
      onPrevious: () => sendKey(CommandMapping.prev),
    );

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

      // Update MediaSession state for AAOS
      _updateMediaSessionState(newState);
    }
  }

  /// Update MediaSession state based on Carlink connection state.
  void _updateMediaSessionState(CarlinkState newState) {
    switch (newState) {
      case CarlinkState.connecting:
        CarlinkPlatform.instance.setMediaSessionConnecting();
        break;
      case CarlinkState.disconnected:
        CarlinkPlatform.instance.setMediaSessionStopped();
        break;
      case CarlinkState.deviceConnected:
      case CarlinkState.streaming:
        // Playback state will be updated when audio starts
        break;
    }
  }

  Future<void> start() async {
    _setState(CarlinkState.connecting);

    if (_adaptrDriver != null) {
      await stop();
    }

    await CarlinkPlatform.instance.resetH264Renderer();

    // Initialize audio playback if enabled
    if (_audioEnabled && !_audioInitialized) {
      try {
        _audioInitialized =
            await CarlinkPlatform.instance.initializeAudio(decodeType: 4);
        if (_audioInitialized) {
          logInfo('Audio playback initialized', tag: 'AUDIO');
        }
      } catch (e) {
        logError('Failed to initialize audio: $e', tag: 'AUDIO');
        _audioInitialized = false;
      }
    }

    // Check microphone permission early to avoid Siri failures
    // (Session 6 analysis showed first 4 Siri invocations failed due to permission not granted)
    if (_microphoneEnabled) {
      try {
        final hasMicPermission = await CarlinkPlatform.instance.hasMicrophonePermission();
        if (!hasMicPermission) {
          logInfo('Microphone permission not granted - Siri/voice features may not work', tag: 'MIC');
          // Note: Actual permission request should be done by the host app UI
          // since we can't show system dialogs from a library
        } else {
          logDebug('Microphone permission verified', tag: 'MIC');
        }
      } catch (e) {
        logError('Failed to check microphone permission: $e', tag: 'MIC');
      }
    }

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
      await _stopMicrophoneCapture();
      await _adaptrDriver?.close();

      // Release audio resources and reset state for reinitialization on reconnect
      // This fixes the issue where audio doesn't work after USB disconnect/reconnect
      // because _audioInitialized remained true but DualStreamAudioManager was released
      if (_audioInitialized) {
        try {
          await CarlinkPlatform.instance.releaseAudio();
          logInfo('Audio released on stop', tag: 'AUDIO');
        } catch (e) {
          logError('Failed to release audio: $e', tag: 'AUDIO');
        }
        _audioInitialized = false; // Force reinitialization on next start()
      }
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

    // Stop microphone capture
    await _stopMicrophoneCapture();

    // Close adapter connection if active
    try {
      await _adaptrDriver?.close();
    } catch (error) {
      _log('Error closing adapter during dispose: $error');
    }

    // Release audio resources
    if (_audioInitialized) {
      try {
        await CarlinkPlatform.instance.releaseAudio();
        _audioInitialized = false;
        _log('Audio released during dispose');
      } catch (error) {
        _log('Error releasing audio during dispose: $error');
      }
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

  // ==================== Audio Control Methods ====================

  /// Enable or disable audio playback.
  ///
  /// When disabled, audio data from CarPlay/Android Auto will be ignored.
  void setAudioEnabled(bool enabled) {
    _audioEnabled = enabled;
    if (!enabled && _audioInitialized) {
      CarlinkPlatform.instance.stopAudio();
    }
  }

  /// Check if audio playback is enabled.
  bool get isAudioEnabled => _audioEnabled;

  /// Check if audio is currently playing.
  Future<bool> isAudioPlaying() async {
    if (!_audioInitialized) return false;
    return CarlinkPlatform.instance.isAudioPlaying();
  }

  /// Set audio playback volume (0.0 to 1.0).
  Future<void> setAudioVolume(double volume) async {
    if (_audioInitialized) {
      await CarlinkPlatform.instance.setAudioVolume(volume);
    }
  }

  /// Get audio playback statistics.
  Future<Map<String, dynamic>> getAudioStats() async {
    if (!_audioInitialized) {
      return {'isPlaying': false, 'error': 'Audio not initialized'};
    }
    return CarlinkPlatform.instance.getAudioStats();
  }

  // ==================== Microphone Control Methods ====================

  /// Enable or disable microphone capture.
  ///
  /// When disabled, Siri/Phone call mic input will be ignored.
  void setMicrophoneEnabled(bool enabled) {
    _microphoneEnabled = enabled;
    if (!enabled && _isMicrophoneCapturing) {
      _stopMicrophoneCapture();
    }
  }

  /// Check if microphone capture is enabled.
  bool get isMicrophoneEnabled => _microphoneEnabled;

  /// Check if microphone is currently capturing.
  bool get isMicrophoneCapturing => _isMicrophoneCapturing;

  /// Check if microphone permission is granted.
  Future<bool> hasMicrophonePermission() async {
    return CarlinkPlatform.instance.hasMicrophonePermission();
  }

  /// Get microphone capture statistics.
  Future<Map<String, dynamic>> getMicrophoneStats() async {
    if (!_isMicrophoneCapturing) {
      return {'isCapturing': false, 'error': 'Microphone not capturing'};
    }
    return CarlinkPlatform.instance.getMicrophoneStats();
  }

  //------------------------------
  // Private
  //------------------------------

  void _log(String message) {
    _logHandler?.call(message);
  }

  // ==================== Private Microphone Methods ====================

  /// Start microphone capture with the specified format.
  ///
  /// Parameters match pi-carplay's known-working implementation:
  /// - decodeType = 5 (16kHz mono) for all voice input
  /// - audioType = 3 (Siri/voice input identifier)
  /// - volume = 0.0 (set in SendAudio class)
  ///
  /// Both Siri and phone calls use identical parameters.
  Future<void> _startMicrophoneCapture({
    required int decodeType,
    required int audioType,
  }) async {
    logDebug(
      '[MIC_DEBUG] _startMicrophoneCapture called: decodeType=$decodeType audioType=$audioType',
      tag: 'MIC',
    );
    logDebug(
      '[MIC_DEBUG] State: _microphoneEnabled=$_microphoneEnabled _isMicrophoneCapturing=$_isMicrophoneCapturing _adaptrDriver=${_adaptrDriver != null ? "set" : "null"}',
      tag: 'MIC',
    );

    if (!_microphoneEnabled) {
      logInfo('Microphone disabled, skipping capture start', tag: 'MIC');
      return;
    }

    if (_isMicrophoneCapturing) {
      // Already capturing - check if format changed
      if (_currentMicDecodeType == decodeType &&
          _currentMicAudioType == audioType) {
        logDebug(
          '[MIC_DEBUG] Already capturing with same format, skipping (currentDecodeType=$_currentMicDecodeType currentAudioType=$_currentMicAudioType)',
          tag: 'MIC',
        );
        return;
      }
      logDebug(
        '[MIC_DEBUG] Format changed, stopping existing capture first',
        tag: 'MIC',
      );
      // Stop existing capture before starting new format
      await _stopMicrophoneCapture();
    }

    try {
      // Check permission first
      logDebug('[MIC_DEBUG] Checking microphone permission...', tag: 'MIC');
      final hasPermission =
          await CarlinkPlatform.instance.hasMicrophonePermission();
      logDebug('[MIC_DEBUG] Permission check result: $hasPermission', tag: 'MIC');
      if (!hasPermission) {
        logError('Microphone permission not granted', tag: 'MIC');
        return;
      }

      // Start capture with the specified format
      logDebug(
        '[MIC_DEBUG] Calling platform startMicrophoneCapture...',
        tag: 'MIC',
      );
      final started = await CarlinkPlatform.instance
          .startMicrophoneCapture(decodeType: decodeType);
      logDebug('[MIC_DEBUG] Platform startMicrophoneCapture result: $started', tag: 'MIC');

      if (started) {
        _isMicrophoneCapturing = true;
        _currentMicDecodeType = decodeType;
        _currentMicAudioType = audioType;
        _micWarmupPacketsSent = 0; // Reset warmup counter for new capture session

        logInfo(
          'Microphone capture started: decodeType=$decodeType audioType=$audioType',
          tag: 'MIC',
        );

        // Start the send loop timer - 20ms interval for smooth audio
        logDebug('[MIC_DEBUG] Starting mic send loop...', tag: 'MIC');
        _startMicSendLoop();
        logDebug(
          '[MIC_DEBUG] Send loop started, _micSendTimer active: ${_micSendTimer?.isActive}',
          tag: 'MIC',
        );
      } else {
        logError('Failed to start microphone capture', tag: 'MIC');
      }
    } catch (e) {
      logError('Microphone capture start error: $e', tag: 'MIC');
    }
  }

  /// Stop microphone capture and send loop.
  Future<void> _stopMicrophoneCapture() async {
    logDebug(
      '[MIC_DEBUG] _stopMicrophoneCapture called: _isMicrophoneCapturing=$_isMicrophoneCapturing totalSends=$_micSendLoopCounter',
      tag: 'MIC',
    );

    if (!_isMicrophoneCapturing) {
      logDebug('[MIC_DEBUG] Not capturing, nothing to stop', tag: 'MIC');
      return;
    }

    // Stop the send loop first
    _stopMicSendLoop();

    try {
      await CarlinkPlatform.instance.stopMicrophoneCapture();
      logInfo(
        'Microphone capture stopped (total sends: $_micSendLoopCounter)',
        tag: 'MIC',
      );
    } catch (e) {
      logError('Microphone capture stop error: $e', tag: 'MIC');
    }

    _isMicrophoneCapturing = false;
    _micSendLoopCounter = 0; // Reset counter for next session
  }

  /// Start the microphone data send loop.
  ///
  /// Reads captured PCM data from the ring buffer and sends it to the adapter
  /// at 20ms intervals for smooth, low-latency voice transmission.
  void _startMicSendLoop() {
    _stopMicSendLoop(); // Clear any existing timer

    // 20ms interval = 50 sends/second, matching capture chunk timing
    _micSendTimer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _sendMicrophoneData(),
    );

    logDebug('Microphone send loop started (20ms interval)', tag: 'MIC');
  }

  /// Stop the microphone data send loop.
  void _stopMicSendLoop() {
    if (_micSendTimer?.isActive == true) {
      _micSendTimer!.cancel();
    }
    _micSendTimer = null;
  }

  // Counter for mic send loop diagnostic logging (reduce log spam)
  int _micSendLoopCounter = 0;
  static const int _micSendLogInterval = 50; // Log every 50 sends (~1 second at 20ms)

  /// Read and send microphone data to the adapter.
  Future<void> _sendMicrophoneData() async {
    // Log state issues that would cause early return (first occurrence only)
    if (!_isMicrophoneCapturing) {
      if (_micSendLoopCounter == 0) {
        logDebug(
          '[MIC_DEBUG] _sendMicrophoneData skipped: _isMicrophoneCapturing=false',
          tag: 'MIC',
        );
      }
      return;
    }
    if (_adaptrDriver == null) {
      if (_micSendLoopCounter == 0) {
        logDebug(
          '[MIC_DEBUG] _sendMicrophoneData skipped: _adaptrDriver=null',
          tag: 'MIC',
        );
      }
      return;
    }

    try {
      // Read up to 20ms of audio data (varies by sample rate)
      // 16kHz mono: 16000 * 2 * 0.02 = 640 bytes per 20ms
      // 8kHz mono: 8000 * 2 * 0.02 = 320 bytes per 20ms
      final maxBytes = _currentMicDecodeType == 3 ? 320 : 640;
      final micData =
          await CarlinkPlatform.instance.readMicrophoneData(maxBytes: maxBytes);

      _micSendLoopCounter++;

      if (micData != null && micData.isNotEmpty) {
        // Skip initial warmup packets (AudioRecord sends zeros during initialization)
        if (_micWarmupPacketsSent < _micWarmupPacketsToSkip) {
          _micWarmupPacketsSent++;
          if (_micWarmupPacketsSent == 1) {
            logDebug(
              '[MIC_DEBUG] Skipping warmup packets (first $_micWarmupPacketsToSkip packets)',
              tag: 'MIC',
            );
          }
          return;
        }

        // Periodic diagnostic logging (every ~1 second)
        if (_micSendLoopCounter % _micSendLogInterval == 1) {
          logDebug(
            '[MIC_DEBUG] Sending mic data: ${micData.length}B decodeType=$_currentMicDecodeType audioType=$_currentMicAudioType (send #$_micSendLoopCounter)',
            tag: 'MIC',
          );
        }

        // Send the captured audio to the adapter
        await _adaptrDriver!.send(
          SendAudio(
            micData,
            decodeType: _currentMicDecodeType,
            audioType: _currentMicAudioType,
          ),
        );
      } else {
        // Log when no data available (but only periodically to avoid spam)
        if (_micSendLoopCounter % _micSendLogInterval == 1) {
          logDebug(
            '[MIC_DEBUG] No mic data available (send #$_micSendLoopCounter, data=${micData?.length ?? "null"})',
            tag: 'MIC',
          );
        }
      }
    } catch (e) {
      // Don't spam errors - mic data send failures are common during transitions
      logDebug('Mic data send error: $e', tag: 'MIC');
    }
  }

  /// Check if PCM audio data is entirely zero-filled (invalid/uninitialized data).
  ///
  /// Real audio, even during silent moments, contains dithering noise and small
  /// variations around zero. Packets that are exactly 0x0000 for every sample
  /// indicate uninitialized adapter memory or firmware issues, not real audio.
  ///
  /// Samples multiple positions (start, 25%, 50%, 75%, end) for efficiency.
  bool _isZeroFilledAudio(Uint8List pcmData) {
    if (pcmData.length < 16) return false;

    // Sample positions: start, 25%, 50%, 75%, and near end
    // Each sample is 2 bytes (16-bit PCM), check 4 bytes (2 samples) at each position
    final positions = [
      0,
      (pcmData.length * 0.25).toInt() & ~1, // Align to 2-byte boundary
      (pcmData.length * 0.5).toInt() & ~1,
      (pcmData.length * 0.75).toInt() & ~1,
      (pcmData.length - 8) & ~1, // Near end, aligned
    ];

    for (final pos in positions) {
      if (pos + 4 > pcmData.length) continue;
      // Check 4 consecutive bytes (2 samples) at this position
      // If any are non-zero, it's real audio
      if (pcmData[pos] != 0 ||
          pcmData[pos + 1] != 0 ||
          pcmData[pos + 2] != 0 ||
          pcmData[pos + 3] != 0) {
        return false;
      }
    }

    // All sampled positions are zero - this is not real audio
    return true;
  }

  /// Process incoming AudioData messages for playback.
  Future<void> _processAudioData(AudioData message) async {
    // Handle volume ducking packets (Len=16 with volumeDuration)
    // These are sent by the adapter to duck media during navigation prompts
    if (message.volumeDuration != null && _audioInitialized) {
      try {
        // Adapter sends volume level (e.g., 0.2 = 20% during nav, 1.0 = restore)
        await CarlinkPlatform.instance.setAudioDucking(message.volume);
      } catch (e) {
        logDebug('Audio ducking error: $e', tag: 'AUDIO');
      }
      return;
    }

    // Skip if audio is disabled or a command message (no actual audio data)
    if (!_audioEnabled || message.command != null) {
      return;
    }

    // Skip if no audio data
    final audioData = message.data;
    if (audioData == null || audioData.isEmpty) {
      return;
    }

    // Initialize audio if not yet done or format changed significantly
    final formatChanged = _currentAudioDecodeType != message.decodeType;
    if (!_audioInitialized || formatChanged) {
      try {
        _audioInitialized = await CarlinkPlatform.instance
            .initializeAudio(decodeType: message.decodeType);
        if (_audioInitialized) {
          if (formatChanged && _currentAudioDecodeType != 4) {
            logInfo(
              'Audio format changed: $_currentAudioDecodeType -> ${message.decodeType}',
              tag: 'AUDIO',
            );
          }
          _currentAudioDecodeType = message.decodeType;
        }
      } catch (e) {
        logError('Failed to initialize audio: $e', tag: 'AUDIO');
        return;
      }
    }

    // Convert Uint16List to Uint8List for platform channel
    // FIX: Use offsetInBytes and lengthInBytes to exclude the 12-byte header
    // Previously: audioData.buffer.asUint8List() included header bytes as audio data
    final pcmBytes = Uint8List.view(
      audioData.buffer,
      audioData.offsetInBytes,
      audioData.lengthInBytes,
    );

    // Filter out zero-filled packets (adapter firmware issue / uninitialized data)
    // Real audio contains dithering noise; exact zeros indicate invalid data
    if (_isZeroFilledAudio(pcmBytes)) {
      _zeroPacketCount++;
      // Log periodically to avoid spam (every 50th zero packet or first one)
      if (_zeroPacketCount == 1 || _zeroPacketCount % 50 == 0) {
        logInfo(
          'AUDIO_FILTER: Skipped $_zeroPacketCount zero-filled packets (adapter sending empty audio)',
          tag: 'AUDIO',
        );
      }
      return;
    }

    // DEBUG: Log buffer details periodically to verify fix
    _audioPacketCount++;
    if (_audioPacketCount % 500 == 1) {
      final firstBytes = pcmBytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      logInfo(
        'AUDIO_DEBUG: pkt#$_audioPacketCount size=${pcmBytes.length} first16=[$firstBytes]',
        tag: 'AUDIO_DEBUG',
      );
    }

    // Write audio to appropriate stream via DualStreamAudioManager.
    //
    // The adapter correctly tags each packet with audioType:
    // - audioType=1: Media/general audio (music, podcasts, Siri responses)
    // - audioType=2: Navigation prompts (turn-by-turn directions)
    //
    // Using message.audioType directly ensures correct AAOS CarAudioContext routing
    // even when multiple streams are interleaved (e.g., nav prompt during music).
    // This prevents format mismatch issues that caused white noise.
    //
    // AAOS mapping: 1→MUSIC, 2→NAVIGATION, 3→CALL, 4→VOICE_COMMAND
    try {
      await CarlinkPlatform.instance.writeAudio(
        pcmBytes,
        decodeType: message.decodeType,
        audioType: message.audioType, // Trust adapter's packet tagging for correct routing
        volume: 1.0, // Use full volume - adapter sends 0.0
      );
    } catch (e) {
      // Log error but don't spam - audio write errors are common during transitions
      logDebug('Audio write error: $e', tag: 'AUDIO');
    }
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
    // AudioData processing - play audio through native AudioTrack
    else if (message is AudioData) {
      _clearPairTimeout();
      await _processAudioData(message);
    }
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

    // Handle audio commands for mic capture and AAOS stream context routing
    if (message is AudioData && message.command != null) {
      logDebug(
        '[MIC_DEBUG] AudioData command received: ${message.command?.name ?? "null"} (id=${message.command?.id ?? -1})',
        tag: 'MIC',
      );

      switch (message.command) {
        case AudioCommand.AudioSiriStart:
          // Set stream context for AAOS routing (USAGE_ASSISTANT → VOICE_COMMAND)
          _currentAudioStreamContext = 4; // SIRI
          _lastAudioContextChange = DateTime.now();
          logInfo(
            '[AUDIO_CONTEXT] Stream context changed to SIRI (4) for AAOS VOICE_COMMAND routing',
            tag: 'AUDIO',
          );
          // Parameters match pi-carplay: decodeType=5, audioType=3, volume=0.0
          logInfo(
            '[MIC_DEBUG] AudioSiriStart received - triggering mic capture (pi-carplay: decodeType=5, audioType=3)',
            tag: 'MIC',
          );
          await _startMicrophoneCapture(decodeType: 5, audioType: 3);
          break;

        case AudioCommand.AudioPhonecallStart:
          // Set stream context for AAOS routing (USAGE_VOICE_COMMUNICATION → CALL)
          _currentAudioStreamContext = 3; // PHONE_CALL
          _lastAudioContextChange = DateTime.now();
          logInfo(
            '[AUDIO_CONTEXT] Stream context changed to PHONE_CALL (3) for AAOS CALL routing',
            tag: 'AUDIO',
          );
          // Both Siri and phone calls use identical parameters per pi-carplay
          logInfo(
            '[MIC_DEBUG] AudioPhonecallStart received - triggering mic capture (pi-carplay: decodeType=5, audioType=3)',
            tag: 'MIC',
          );
          await _startMicrophoneCapture(decodeType: 5, audioType: 3);
          break;

        case AudioCommand.AudioNaviStart:
          // Set stream context for AAOS routing (USAGE_ASSISTANCE_NAVIGATION_GUIDANCE → NAVIGATION)
          _currentAudioStreamContext = 2; // NAVIGATION
          _lastAudioContextChange = DateTime.now();
          logInfo(
            '[AUDIO_CONTEXT] Stream context changed to NAVIGATION (2) for AAOS NAVIGATION routing',
            tag: 'AUDIO',
          );
          break;

        case AudioCommand.AudioMediaStart:
          // Set stream context for AAOS routing (USAGE_MEDIA → MUSIC)
          _currentAudioStreamContext = 1; // MEDIA
          _lastAudioContextChange = DateTime.now();
          logDebug(
            '[AUDIO_CONTEXT] Stream context changed to MEDIA (1) for AAOS MUSIC routing',
            tag: 'AUDIO',
          );
          break;

        case AudioCommand.AudioSiriStop:
          logInfo('[MIC_DEBUG] AudioSiriStop received - stopping mic capture', tag: 'MIC');
          await _stopMicrophoneCapture();
          // Pause voice track so AAOS deprioritizes VOICE_COMMAND context for volume control
          await CarlinkPlatform.instance.stopAudioStream(audioType: 4);
          // Revert to MEDIA context after Siri ends
          _currentAudioStreamContext = 1;
          _lastAudioContextChange = DateTime.now();
          logDebug(
            '[AUDIO_CONTEXT] Stream context reverted to MEDIA (1) after Siri stop',
            tag: 'AUDIO',
          );
          break;

        case AudioCommand.AudioPhonecallStop:
          logInfo('[MIC_DEBUG] AudioPhonecallStop received - stopping mic capture', tag: 'MIC');
          await _stopMicrophoneCapture();
          // Pause call track so AAOS deprioritizes CALL context for volume control
          await CarlinkPlatform.instance.stopAudioStream(audioType: 3);
          // Revert to MEDIA context after phone call ends
          _currentAudioStreamContext = 1;
          _lastAudioContextChange = DateTime.now();
          logDebug(
            '[AUDIO_CONTEXT] Stream context reverted to MEDIA (1) after phone call stop',
            tag: 'AUDIO',
          );
          break;

        case AudioCommand.AudioNaviStop:
          // Pause nav track so AAOS deprioritizes NAVIGATION context for volume control
          // This is critical: without this, volume keys stay "stuck" on nav volume
          await CarlinkPlatform.instance.stopAudioStream(audioType: 2);
          // Revert to MEDIA context after navigation prompt ends
          _currentAudioStreamContext = 1;
          _lastAudioContextChange = DateTime.now();
          logDebug(
            '[AUDIO_CONTEXT] Stream context reverted to MEDIA (1) after navigation stop',
            tag: 'AUDIO',
          );
          break;

        case AudioCommand.AudioMediaStop:
        case AudioCommand.AudioOutputStop:
        case AudioCommand.AudioAlertStop:
          // Pause media track when media/output/alert stream ends
          // Less critical than nav/siri/call since media is lowest priority,
          // but keeps AAOS state consistent
          await CarlinkPlatform.instance.stopAudioStream(audioType: 1);
          logDebug(
            '[AUDIO_CONTEXT] Media track paused after ${message.command?.name}',
            tag: 'AUDIO',
          );
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

      final mediaInfo = CarlinkMediaInfo(
        songTitle: (_lastMediaLyrics ?? _lastMediaSongName) ?? " ",
        songArtist: _lastMediaArtistName ?? " ",
        albumName: _lastMediaAlbumName,
        appName: _lastMediaAPPName,
        albumCoverImageData: _lastAlbumCover,
      );

      // Notify Flutter callback
      _metadataHandler?.call(mediaInfo);

      // Update MediaSession for AAOS system UI
      _updateMediaSessionMetadata(mediaInfo);
    }
  }

  /// Update MediaSession metadata for AAOS.
  void _updateMediaSessionMetadata(CarlinkMediaInfo mediaInfo) {
    CarlinkPlatform.instance.updateMediaMetadata(
      title: mediaInfo.songTitle,
      artist: mediaInfo.songArtist,
      album: mediaInfo.albumName,
      appName: mediaInfo.appName,
      albumArt: mediaInfo.albumCoverImageData,
    );

    // Also update playback state to playing when we have metadata
    CarlinkPlatform.instance.updatePlaybackState(isPlaying: true);
  }
}
