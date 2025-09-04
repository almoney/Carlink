import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:carlink/carlink.dart';
import 'package:carlink/driver/readable.dart';
import 'settings_enums.dart';
import '../logger.dart';

/// Status monitor for CPC200-CCPA adapter messages.
/// Listens for specific status messages and maintains current adapter state.
/// 
/// This class follows the observer pattern and provides real-time updates
/// about the adapter's operational status, phone connections, firmware info, etc.
class AdapterStatusMonitor extends ChangeNotifier {
  Timer? _pollingTimer;
  StreamSubscription? _messageSubscription;
  
  /// Current adapter status information
  AdapterStatusInfo _currentStatus = AdapterStatusInfo(
    lastUpdated: DateTime.now(),
  );
  
  /// Carlink instance for communication
  Carlink? _carlink;
  
  /// Whether the monitor is currently active
  bool _isMonitoring = false;
  
  /// Timestamp of last audio data received
  DateTime? _lastAudioDataTime;
  
  /// Duration to consider audio data as "recent" (in seconds)
  static const int _audioDataTimeoutSeconds = 5;
  
  /// Polling interval for status updates (in milliseconds)
  static const int _pollingIntervalMs = 500;
  
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
        phoneStatus: PhoneConnectionStatus.unknown,
      ));
      return;
    }
    
    _isMonitoring = true;
    _startPolling();
    
    Logger.log('[STATUS_MONITOR] Started monitoring adapter status');
  }
  
  /// Sets up message interception for direct protocol message processing
  void setupMessageInterception(Carlink? carlink) {
    if (carlink == null) return;
    
    // Note: This would require modifying the Carlink constructor call
    // to pass our processMessage method as the onMessageIntercepted callback
    Logger.log('[STATUS_MONITOR] Message interception ready for setup');
  }
  
  /// Stops monitoring and cleans up resources
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _isMonitoring = false;
    
    Logger.log('[STATUS_MONITOR] Stopped monitoring adapter status');
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
        Logger.log('[STATUS_MONITOR] Phase changed to: ${adapterPhase.displayName}');
      }
      
      // Check for recent audio data activity
      final hasRecentAudio = _hasRecentAudioData();
      if (hasRecentAudio != _currentStatus.hasRecentAudioData) {
        final updatedStatus = newStatus.copyWith(hasRecentAudioData: hasRecentAudio);
        _updateStatus(updatedStatus);
      }
      
      // Note: Additional status messages (0x02, 0xCC, 0x14, 0x19) would be
      // processed here when the Carlink class provides access to them.
      // For now, we derive what we can from the available CarlinkState.
      
    } catch (e) {
      Logger.log('[STATUS_MONITOR] Error polling status: $e');
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
        Logger.log('[STATUS_MONITOR] Received Phase: ${phase.displayName}');
        
      } else if (message is Plugged) {
        // Process Plugged message (0x02)
        // Map phoneType to connection status (connected when any phone type is present)
        final phoneStatus = PhoneConnectionStatus.connected;
        updatedStatus = _currentStatus.copyWith(phoneStatus: phoneStatus);
        Logger.log('[STATUS_MONITOR] Received Phone Status: ${phoneStatus.displayName}');
        
      } else if (message is Unplugged) {
        // Process Unplugged message (0x04)
        // Phone has been disconnected
        final phoneStatus = PhoneConnectionStatus.disconnected;
        updatedStatus = _currentStatus.copyWith(phoneStatus: phoneStatus);
        Logger.log('[STATUS_MONITOR] Received Phone Status: ${phoneStatus.displayName}');
        
      } else if (message is SoftwareVersion) {
        // Process Software Version message (0xCC)
        final version = message.version;
        updatedStatus = _currentStatus.copyWith(firmwareVersion: version);
        Logger.log('[STATUS_MONITOR] Received Firmware Version: $version');
        
      } else if (message is ManufacturerInfo) {
        // Process Manufacturer Info message (0x14)
        final info = {'a': message.a, 'b': message.b};
        updatedStatus = _currentStatus.copyWith(manufacturerInfo: info);
        Logger.log('[STATUS_MONITOR] Received Manufacturer Info');
        
      } else if (message is BoxInfo) {
        // Process Box Settings message (0x19)
        final settings = Map<String, dynamic>.from(message.settings);
        updatedStatus = _currentStatus.copyWith(boxSettings: settings);
        Logger.log('[STATUS_MONITOR] Received Box Settings');
        
      } else if (message is AudioData) {
        // Process AudioData message (0x07)
        _lastAudioDataTime = DateTime.now();
        final hasRecent = _hasRecentAudioData();
        updatedStatus = _currentStatus.copyWith(hasRecentAudioData: hasRecent);
        Logger.log('[STATUS_MONITOR] Received AudioData - Audio detected');
        
      }
      
      if (updatedStatus != null) {
        _updateStatus(updatedStatus);
      }
      
    } catch (e) {
      Logger.log('[STATUS_MONITOR] Error processing message: $e');
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