import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:carlink/carlink.dart';
import 'package:carlink/carlink_platform_interface.dart';
import 'package:carlink/driver/readable.dart';
import 'settings_enums.dart';
import 'package:carlink/log.dart';

/// Status monitor for CPC200-CCPA adapter messages.
/// Listens for specific status messages and maintains current adapter state.
///
/// This class follows the observer pattern and provides real-time updates
/// about the adapter's operational status, phone connections, firmware info, etc.
class AdapterStatusMonitor extends ChangeNotifier {
  Timer? _pollingTimer;

  /// Current adapter status information
  AdapterStatusInfo _currentStatus = AdapterStatusInfo(
    phoneConnection: PhoneConnectionInfo(
      lastUpdate: DateTime.now(),
    ),
    lastUpdated: DateTime.now(),
  );

  /// Carlink instance for communication
  Carlink? _carlink;

  /// Whether the monitor is currently active
  bool _isMonitoring = false;

  /// Timestamp of last audio data received
  DateTime? _lastAudioDataTime;

  /// Video frame tracking for FPS calculation
  final List<DateTime> _videoFrameTimes = [];
  int _totalVideoFrames = 0;

  /// Duration to consider audio data as "recent" (in seconds)
  static const int _audioDataTimeoutSeconds = 5;

  /// Number of recent frames to track for FPS calculation
  static const int _frameTimeWindow = 30;

  /// Polling interval for status updates (in milliseconds)
  static const int _pollingIntervalMs = 500;

  /// Cached codec name from native layer
  String? _detectedCodecName;

  /// Current status information
  AdapterStatusInfo get currentStatus => _currentStatus;

  /// Whether monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// Starts monitoring the specified Carlink instance
  void startMonitoring(Carlink? carlink) {
    if (_isMonitoring) {
      stopMonitoring();
    }

    _carlink = carlink;
    if (_carlink == null) {
      _updateStatus(_currentStatus.copyWith(
        phase: AdapterPhase.unknown,
        phoneConnection: PhoneConnectionInfo(
          status: PhoneConnectionStatus.unknown,
          lastUpdate: DateTime.now(),
        ),
      ));
      return;
    }

    _isMonitoring = true;
    _startPolling();

    log('[STATUS_MONITOR] Started monitoring adapter status');
  }

  /// Sets up message interception for direct protocol message processing
  void setupMessageInterception(Carlink? carlink) {
    if (carlink == null) return;

    // Note: This would require modifying the Carlink constructor call
    // to pass our processMessage method as the onMessageIntercepted callback
    log('[STATUS_MONITOR] Message interception ready for setup');
  }

  /// Stops monitoring and cleans up resources
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isMonitoring = false;

    log('[STATUS_MONITOR] Stopped monitoring adapter status');
  }

  /// Starts the polling timer to check for status changes
  void _startPolling() {
    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: _pollingIntervalMs),
      _pollStatus,
    );
  }

  /// Polls the current status from the Carlink instance
  void _pollStatus(Timer timer) {
    if (_carlink == null || !_isMonitoring) {
      return;
    }

    try {
      // Update basic connection state
      final newStatus = _currentStatus.copyWith(
        lastUpdated: DateTime.now(),
      );

      // Map Carlink state to our adapter phase
      final carlinkState = _carlink!.state;
      final adapterPhase = _mapCarlinkStateToPhase(carlinkState);

      if (adapterPhase != _currentStatus.phase) {
        final updatedStatus = newStatus.copyWith(phase: adapterPhase);
        _updateStatus(updatedStatus);
        log('[STATUS_MONITOR] Phase changed to: ${adapterPhase.displayName}');
      }

      // Check for recent audio data activity
      final hasRecentAudio = _hasRecentAudioData();
      if (hasRecentAudio != _currentStatus.hasRecentAudioData) {
        final updatedStatus =
            newStatus.copyWith(hasRecentAudioData: hasRecentAudio);
        _updateStatus(updatedStatus);
      }

      // Fetch codec name from native layer if not yet detected
      if (_detectedCodecName == null) {
        _fetchCodecName();
      }

      // Note: Additional status messages (0x02, 0xCC, 0x14, 0x19) would be
      // processed here when the Carlink class provides access to them.
      // For now, we derive what we can from the available CarlinkState.
    } catch (e) {
      logError('[STATUS_MONITOR] Error polling status: $e');
    }
  }

  /// Fetches codec name from native layer and updates video stream info
  Future<void> _fetchCodecName() async {
    try {
      final codecName = await CarlinkPlatform.instance.getCodecName();
      if (codecName != null && codecName != _detectedCodecName) {
        _detectedCodecName = codecName;
        log('[STATUS_MONITOR] Detected codec: $codecName');

        // Update video stream info with detected codec if we have video info
        final currentVideo = _currentStatus.videoStream;
        if (currentVideo != null) {
          final updatedVideo = currentVideo.copyWith(codec: codecName);
          final updatedStatus =
              _currentStatus.copyWith(videoStream: updatedVideo);
          _updateStatus(updatedStatus);
        }
      }
    } catch (e) {
      logError('[STATUS_MONITOR] Error fetching codec name: $e');
    }
  }

  /// Maps CarlinkState to AdapterPhase
  AdapterPhase _mapCarlinkStateToPhase(CarlinkState carlinkState) {
    switch (carlinkState) {
      case CarlinkState.disconnected:
        return AdapterPhase.idle;
      case CarlinkState.connecting:
        return AdapterPhase.initializing;
      case CarlinkState.deviceConnected:
        return AdapterPhase.active;
      case CarlinkState.streaming:
        return AdapterPhase.active;
    }
  }

  /// Checks if audio data was received recently
  bool _hasRecentAudioData() {
    if (_lastAudioDataTime == null) return false;

    final now = DateTime.now();
    final timeDifference = now.difference(_lastAudioDataTime!);
    return timeDifference.inSeconds <= _audioDataTimeoutSeconds;
  }

  /// Calculates current FPS from recent frame times
  double? _calculateCurrentFPS() {
    if (_videoFrameTimes.length < 2) return null;

    final now = DateTime.now();
    // Remove frames older than 2 seconds for more accurate real-time FPS
    _videoFrameTimes
        .removeWhere((time) => now.difference(time).inMilliseconds > 2000);

    if (_videoFrameTimes.length < 2) return null;

    // Calculate FPS from the time span of recent frames
    final timeSpan = _videoFrameTimes.last.difference(_videoFrameTimes.first);
    if (timeSpan.inMilliseconds < 100) {
      return null; // Avoid division by very small numbers
    }

    final fps =
        (_videoFrameTimes.length - 1) * 1000.0 / timeSpan.inMilliseconds;
    return fps;
  }

  /// Updates video stream information based on VideoData message
  void _updateVideoStreamInfo(int width, int height) {
    final now = DateTime.now();
    _totalVideoFrames++;

    // Add current timestamp for FPS calculation
    _videoFrameTimes.add(now);

    // Keep only recent frames for FPS calculation
    if (_videoFrameTimes.length > _frameTimeWindow) {
      _videoFrameTimes.removeAt(0);
    }

    // Calculate current FPS for actual streaming rate
    final actualFps = _calculateCurrentFPS();

    // Preserve configured resolution but track actual received resolution separately
    final currentVideo = _currentStatus.videoStream;
    final updatedVideo = currentVideo?.copyWith(
          // Keep configured resolution and FPS unless not yet initialized
          width: currentVideo.width ?? width,
          height: currentVideo.height ?? height,
          // Store the actual received resolution from VideoData messages
          receivedWidth: width,
          receivedHeight: height,
          frameRate: currentVideo.frameRate ?? actualFps,
          // Use detected codec name from native layer, or preserve existing
          codec: _detectedCodecName ?? currentVideo.codec,
          lastVideoUpdate: now,
          totalFrames: _totalVideoFrames,
        ) ??
        VideoStreamInfo(
          // Fallback if no initial config was set
          width: width,
          height: height,
          receivedWidth: width,
          receivedHeight: height,
          frameRate: actualFps,
          codec: _detectedCodecName ?? 'H.264',
          lastVideoUpdate: now,
          totalFrames: _totalVideoFrames,
        );

    // Update the adapter status with new video information
    final updatedStatus = _currentStatus.copyWith(videoStream: updatedVideo);
    _updateStatus(updatedStatus);
  }

  /// Updates the current status and notifies listeners
  void _updateStatus(AdapterStatusInfo newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      notifyListeners();
    }
  }

  /// Processes incoming CPC200-CCPA messages to update status.
  /// This method would be called when the Carlink class provides
  /// access to individual protocol messages.
  void processMessage(Message message) {
    try {
      AdapterStatusInfo? updatedStatus;

      if (message is Phase) {
        // Process Phase message (0x03)
        final phase = AdapterPhase.fromValue(message.phase);
        updatedStatus = _currentStatus.copyWith(phase: phase);
        log('[STATUS_MONITOR] Received Phase: ${phase.displayName}');
      } else if (message is Plugged) {
        // Process Plugged message (0x02) with detailed phone information
        final platform = PhonePlatform.fromId(message.phoneType.id);
        final connectionType = message.wifi != null
            ? PhoneConnectionType.wireless
            : PhoneConnectionType.wired;

        final phoneConnection = PhoneConnectionInfo(
          status: PhoneConnectionStatus.connected,
          platform: platform,
          connectionType: connectionType,
          lastUpdate: DateTime.now(),
        );

        updatedStatus =
            _currentStatus.copyWith(phoneConnection: phoneConnection);
        log('[STATUS_MONITOR] Phone Connected: ${platform.displayName} (${connectionType.displayName})');
      } else if (message is Unplugged) {
        // Process Unplugged message (0x04)
        // Keep platform info but mark as disconnected
        final phoneConnection = _currentStatus.phoneConnection.copyWith(
          status: PhoneConnectionStatus.disconnected,
          lastUpdate: DateTime.now(),
        );

        updatedStatus =
            _currentStatus.copyWith(phoneConnection: phoneConnection);
        log('[STATUS_MONITOR] Phone Disconnected: ${phoneConnection.platform.displayName}');
      } else if (message is SoftwareVersion) {
        // Process Software Version message (0xCC)
        final version = message.version;
        updatedStatus = _currentStatus.copyWith(firmwareVersion: version);
        log('[STATUS_MONITOR] Received Firmware Version: $version');
      } else if (message is ManufacturerInfo) {
        // Process Manufacturer Info message (0x14)
        final info = {'a': message.a, 'b': message.b};
        updatedStatus = _currentStatus.copyWith(manufacturerInfo: info);
        log('[STATUS_MONITOR] Received Manufacturer Info');
      } else if (message is BoxInfo) {
        // Process Box Settings message (0x19)
        final settings = Map<String, dynamic>.from(message.settings);
        updatedStatus = _currentStatus.copyWith(boxSettings: settings);
        log('[STATUS_MONITOR] Received Box Settings');
      } else if (message is AudioData) {
        // Process AudioData message (0x07)
        _lastAudioDataTime = DateTime.now();
        final hasRecent = _hasRecentAudioData();
        updatedStatus = _currentStatus.copyWith(hasRecentAudioData: hasRecent);
        log('[STATUS_MONITOR] Received AudioData - Audio detected',
            tag: 'AUDIO');
      } else if (message is VideoData) {
        // Process VideoData message (0x06)
        _updateVideoStreamInfo(message.width, message.height);
        log('[STATUS_MONITOR] Received VideoData - ${message.width}x${message.height}',
            tag: 'VIDEO');
        // updatedStatus is handled within _updateVideoStreamInfo
      } else if (message is BluetoothDeviceName) {
        // Process Bluetooth Device Name message (0x0D)
        updatedStatus =
            _currentStatus.copyWith(bluetoothDeviceName: message.name);
        log('[STATUS_MONITOR] Received Bluetooth Device Name: ${message.name}');
      } else if (message is BluetoothPIN) {
        // Process Bluetooth PIN message (0x0C)
        updatedStatus = _currentStatus.copyWith(bluetoothPIN: message.pin);
        log('[STATUS_MONITOR] Received Bluetooth PIN: ${message.pin}');
      } else if (message is WifiDeviceName) {
        // Process WiFi Device Name message (0x0E)
        updatedStatus = _currentStatus.copyWith(wifiDeviceName: message.name);
        log('[STATUS_MONITOR] Received WiFi Device Name: ${message.name}');
      } else if (message is NetworkMacAddress) {
        // Process Network MAC Address message (0x23)
        final phoneConnection = _currentStatus.phoneConnection.copyWith(
          connectedPhoneMacAddress: message.macAddress,
          lastUpdate: DateTime.now(),
        );
        updatedStatus =
            _currentStatus.copyWith(phoneConnection: phoneConnection);
        log('[STATUS_MONITOR] Received Phone MAC Address: ${message.macAddress}');
      } else if (message is NetworkMacAddressAlt) {
        // Process Network MAC Address Alt message (0x24)
        final phoneConnection = _currentStatus.phoneConnection.copyWith(
          connectedPhoneMacAddress: message.macAddress,
          lastUpdate: DateTime.now(),
        );
        updatedStatus =
            _currentStatus.copyWith(phoneConnection: phoneConnection);
        log('[STATUS_MONITOR] Received Phone MAC Address (Alt): ${message.macAddress}');
      } else if (message is AdaptrConfigurationMessage) {
        // Process Dongle Configuration message (internal)
        // Initialize video stream info with the actual configuration sent to adapter
        final initialVideoStream = VideoStreamInfo(
          width: message.width,
          height: message.height,
          receivedWidth: null, // Will be populated when VideoData is received
          receivedHeight: null, // Will be populated when VideoData is received
          frameRate: message.fps.toDouble(),
          // Use detected codec if available, otherwise default to H.264 placeholder
          codec: _detectedCodecName ?? 'H.264',
          lastVideoUpdate: DateTime.now(),
          totalFrames: 0,
        );
        updatedStatus =
            _currentStatus.copyWith(videoStream: initialVideoStream);
        log('[STATUS_MONITOR] Initialized video config: ${message.width}x${message.height}@${message.fps}fps');
      }

      if (updatedStatus != null) {
        _updateStatus(updatedStatus);
      }
    } catch (e) {
      logError('[STATUS_MONITOR] Error processing message: $e');
    }
  }

  /// Forces a manual status refresh
  void refreshStatus() {
    if (_isMonitoring && _carlink != null) {
      _pollStatus(_pollingTimer!);
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

/// Singleton instance of the status monitor for global access
final AdapterStatusMonitor adapterStatusMonitor = AdapterStatusMonitor();
