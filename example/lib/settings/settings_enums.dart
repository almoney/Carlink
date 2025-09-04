import 'package:flutter/material.dart';

/// Enum defining all available settings tabs.
/// This design allows for easy addition of new tabs in the future
/// while maintaining type safety and consistent structure.
enum SettingsTab {
  status('Status', Icons.info_outline),
  control('Control', Icons.settings);
  
  // Future tabs can be easily added here:
  // diagnostics('Diagnostics', Icons.bug_report),
  // advanced('Advanced', Icons.tune),
  // logs('Logs', Icons.list_alt),
  // network('Network', Icons.wifi);
  
  const SettingsTab(this.title, this.icon);
  
  /// Display title for the tab
  final String title;
  
  /// Icon to display in the tab
  final IconData icon;
  
  /// Get all visible tabs (allows for conditional tab display)
  static List<SettingsTab> get visibleTabs => values.where((tab) => 
    _tabVisibility[tab] ?? true
  ).toList();
}

/// Configuration for tab visibility.
/// Can be used to enable/disable tabs based on device capabilities,
/// user permissions, or feature flags.
const Map<SettingsTab, bool> _tabVisibility = {
  SettingsTab.status: true,
  SettingsTab.control: true,
  // Future tabs default to false until ready for production
};

/// Enum for CPC200-CCPA adapter operational phase states.
/// Based on message type 0x03 from the firmware documentation.
enum AdapterPhase {
  idle(0x00, 'Idle/Standby', Colors.grey),
  initializing(0x01, 'Initializing', Colors.orange),
  active(0x02, 'Active/Connected', Colors.green),
  error(0x03, 'Error State', Colors.red),
  shuttingDown(0x04, 'Shutting Down', Colors.amber),
  unknown(-1, 'Unknown', Colors.grey);
  
  const AdapterPhase(this.value, this.displayName, this.color);
  
  /// Raw value from the CPC200-CCPA protocol
  final int value;
  
  /// Human-readable display name
  final String displayName;
  
  /// Color for UI display
  final Color color;
  
  /// Factory constructor to create from protocol value
  factory AdapterPhase.fromValue(int value) {
    return values.firstWhere(
      (phase) => phase.value == value,
      orElse: () => AdapterPhase.unknown,
    );
  }
}

/// Enum for phone connection status.
/// Based on message type 0x02 from the firmware documentation.
enum PhoneConnectionStatus {
  disconnected(0, 'Disconnected', Colors.red, Icons.smartphone),
  connected(1, 'Connected', Colors.green, Icons.smartphone),
  unknown(-1, 'Unknown', Colors.grey, Icons.help_outline);
  
  const PhoneConnectionStatus(this.value, this.displayName, this.color, this.icon);
  
  /// Raw value from the CPC200-CCPA protocol
  final int value;
  
  /// Human-readable display name
  final String displayName;
  
  /// Color for UI display
  final Color color;
  
  /// Icon for UI display
  final IconData icon;
  
  /// Factory constructor to create from protocol value
  factory PhoneConnectionStatus.fromValue(int value) {
    return values.firstWhere(
      (status) => status.value == value,
      orElse: () => PhoneConnectionStatus.unknown,
    );
  }
}

/// Status information container for the CPC200-CCPA adapter.
/// Aggregates various status messages received from the adapter.
class AdapterStatusInfo {
  /// Operational phase (from message 0x03)
  final AdapterPhase phase;
  
  /// Phone connection status (from message 0x02)
  final PhoneConnectionStatus phoneStatus;
  
  /// Software/firmware version (from message 0xCC)
  final String? firmwareVersion;
  
  /// Manufacturer information (from message 0x14)
  final Map<String, dynamic>? manufacturerInfo;
  
  /// Box settings/configuration (from message 0x19)
  final Map<String, dynamic>? boxSettings;
  
  /// Network metadata (from messages 0x0A-0x0E)
  final Map<String, dynamic>? networkInfo;
  
  /// Whether audio packets have been detected recently
  final bool hasRecentAudioData;
  
  /// Timestamp of last status update
  final DateTime lastUpdated;
  
  const AdapterStatusInfo({
    this.phase = AdapterPhase.unknown,
    this.phoneStatus = PhoneConnectionStatus.unknown,
    this.firmwareVersion,
    this.manufacturerInfo,
    this.boxSettings,
    this.networkInfo,
    this.hasRecentAudioData = false,
    required this.lastUpdated,
  });
  
  /// Creates a copy with updated values
  AdapterStatusInfo copyWith({
    AdapterPhase? phase,
    PhoneConnectionStatus? phoneStatus,
    String? firmwareVersion,
    Map<String, dynamic>? manufacturerInfo,
    Map<String, dynamic>? boxSettings,
    Map<String, dynamic>? networkInfo,
    bool? hasRecentAudioData,
    DateTime? lastUpdated,
  }) {
    return AdapterStatusInfo(
      phase: phase ?? this.phase,
      phoneStatus: phoneStatus ?? this.phoneStatus,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      manufacturerInfo: manufacturerInfo ?? this.manufacturerInfo,
      boxSettings: boxSettings ?? this.boxSettings,
      networkInfo: networkInfo ?? this.networkInfo,
      hasRecentAudioData: hasRecentAudioData ?? this.hasRecentAudioData,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }
  
  /// Whether the adapter is in a healthy operational state
  bool get isHealthy => 
    phase == AdapterPhase.active && 
    phoneStatus == PhoneConnectionStatus.connected;
  
  /// Whether the adapter is currently operational
  bool get isOperational => 
    phase == AdapterPhase.active || 
    phase == AdapterPhase.initializing;
}