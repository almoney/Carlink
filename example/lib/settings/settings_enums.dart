import 'package:flutter/material.dart';

/// Enum defining all available settings tabs.
/// This design allows for easy addition of new tabs in the future
/// while maintaining type safety and consistent structure.
enum SettingsTab {
  status('Status', Icons.info_outline),
  control('Control', Icons.settings),
  logs('Logs', Icons.article);

  // Future tabs can be easily added here:
  // diagnostics('Diagnostics', Icons.bug_report),
  // advanced('Advanced', Icons.tune),
  // network('Network', Icons.wifi);

  const SettingsTab(this.title, this.icon);

  /// Display title for the tab
  final String title;

  /// Icon to display in the tab
  final IconData icon;

  /// Get all visible tabs (allows for conditional tab display)
  static List<SettingsTab> get visibleTabs =>
      values.where((tab) => _tabVisibility[tab] ?? true).toList();
}

/// Configuration for tab visibility.
/// Can be used to enable/disable tabs based on device capabilities,
/// user permissions, or feature flags.
const Map<SettingsTab, bool> _tabVisibility = {
  SettingsTab.status: true,
  SettingsTab.control: true,
  SettingsTab.logs: true,
  // Future tabs default to false until ready for production
};

/// Enum for CPC200-CCPA adapter operational phase states.
/// Based on message type 0x03 from the firmware documentation.
enum AdapterPhase {
  idle(0x00, 'Idle/Standby'),
  initializing(0x01, 'Searching'),
  active(0x02, 'Active/Connected'),
  error(0x03, 'Error State'),
  shuttingDown(0x04, 'Shutting Down'),
  unknown(-1, 'Unknown');

  const AdapterPhase(this.value, this.displayName);

  /// Raw value from the CPC200-CCPA protocol
  final int value;

  /// Human-readable display name
  final String displayName;

  /// Get theme-aware color for UI display
  Color getColor(ColorScheme colorScheme) {
    switch (this) {
      case AdapterPhase.idle:
      case AdapterPhase.unknown:
        return colorScheme.onSurfaceVariant;
      case AdapterPhase.initializing:
      case AdapterPhase.shuttingDown:
        return colorScheme.tertiary;
      case AdapterPhase.active:
        return colorScheme.primary;
      case AdapterPhase.error:
        return colorScheme.error;
    }
  }

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
  disconnected(0, 'Disconnected', Icons.smartphone),
  connected(1, 'Connected', Icons.smartphone),
  unknown(-1, 'Unknown', Icons.help_outline);

  const PhoneConnectionStatus(this.value, this.displayName, this.icon);

  /// Raw value from the CPC200-CCPA protocol
  final int value;

  /// Human-readable display name
  final String displayName;

  /// Icon for UI display
  final IconData icon;

  /// Get theme-aware color for UI display
  Color getColor(ColorScheme colorScheme) {
    switch (this) {
      case PhoneConnectionStatus.disconnected:
        return colorScheme.error;
      case PhoneConnectionStatus.connected:
        return colorScheme.primary;
      case PhoneConnectionStatus.unknown:
        return colorScheme.onSurfaceVariant;
    }
  }

  /// Factory constructor to create from protocol value
  factory PhoneConnectionStatus.fromValue(int value) {
    return values.firstWhere(
      (status) => status.value == value,
      orElse: () => PhoneConnectionStatus.unknown,
    );
  }
}

/// Phone platform types supported by CPC200-CCPA adapter.
/// Matches PhoneType enum from lib/driver/readable.dart
enum PhonePlatform {
  androidMirror(1, 'Android Mirror', Icons.android),
  carPlay(3, 'CarPlay', Icons.apple),
  iPhoneMirror(4, 'iPhone Mirror', Icons.apple),
  androidAuto(5, 'Android Auto', Icons.android),
  hiCar(6, 'HiCar', Icons.directions_car),
  unknown(-1, 'Unknown', Icons.help_outline);

  const PhonePlatform(this.id, this.displayName, this.icon);

  /// Platform ID from CPC200-CCPA protocol
  final int id;

  /// Human-readable display name
  final String displayName;

  /// Icon for UI display
  final IconData icon;

  /// Factory constructor to create from protocol PhoneType ID
  factory PhonePlatform.fromId(int id) {
    return values.firstWhere(
      (platform) => platform.id == id,
      orElse: () => PhonePlatform.unknown,
    );
  }
}

/// Phone connection type (wired vs wireless)
enum PhoneConnectionType {
  wired('Wired', Icons.usb),
  wireless('Wireless', Icons.wifi),
  unknown('Unknown', Icons.help_outline);

  const PhoneConnectionType(this.displayName, this.icon);

  /// Human-readable display name
  final String displayName;

  /// Icon for UI display
  final IconData icon;
}

/// Detailed phone connection information container.
/// Tracks connection status, platform type, and connection method.
class PhoneConnectionInfo {
  /// Basic connection status
  final PhoneConnectionStatus status;

  /// Phone platform (CarPlay, Android Auto, etc.)
  final PhonePlatform platform;

  /// Connection type (Wired/Wireless)
  final PhoneConnectionType connectionType;

  /// Connected phone's Bluetooth MAC address (from messages 0x23/0x24)
  final String? connectedPhoneMacAddress;

  /// Timestamp of last phone status update
  final DateTime lastUpdate;

  const PhoneConnectionInfo({
    this.status = PhoneConnectionStatus.unknown,
    this.platform = PhonePlatform.unknown,
    this.connectionType = PhoneConnectionType.unknown,
    this.connectedPhoneMacAddress,
    required this.lastUpdate,
  });

  /// Creates a copy with updated values
  PhoneConnectionInfo copyWith({
    PhoneConnectionStatus? status,
    PhonePlatform? platform,
    PhoneConnectionType? connectionType,
    String? connectedPhoneMacAddress,
    DateTime? lastUpdate,
  }) {
    return PhoneConnectionInfo(
      status: status ?? this.status,
      platform: platform ?? this.platform,
      connectionType: connectionType ?? this.connectionType,
      connectedPhoneMacAddress:
          connectedPhoneMacAddress ?? this.connectedPhoneMacAddress,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  /// Whether phone is currently connected
  bool get isConnected => status == PhoneConnectionStatus.connected;

  /// Display color based on connection status (requires ColorScheme from context)
  Color displayColor(ColorScheme colorScheme) => status.getColor(colorScheme);

  /// Display icon based on connection status (not platform)
  IconData get displayIcon => status.icon;

  /// Platform display text or "- - -" if unknown
  String get platformDisplay =>
      platform != PhonePlatform.unknown ? platform.displayName : '- - -';

  /// Connection type display text or "- - -" if unknown
  String get connectionTypeDisplay =>
      connectionType != PhoneConnectionType.unknown
          ? connectionType.displayName
          : '- - -';

  /// BT MAC address display text or "- - -" if unknown
  String get connectedPhoneMacDisplay =>
      connectedPhoneMacAddress != null ? connectedPhoneMacAddress! : '- - -';
}

/// Status information container for the CPC200-CCPA adapter.
/// Aggregates various status messages received from the adapter.
class AdapterStatusInfo {
  /// Operational phase (from message 0x03)
  final AdapterPhase phase;

  /// Phone connection information (from message 0x02)
  final PhoneConnectionInfo phoneConnection;

  /// Software/firmware version (from message 0xCC)
  final String? firmwareVersion;

  /// Bluetooth device name (from message 0x0D)
  final String? bluetoothDeviceName;

  /// Bluetooth PIN (from message 0x0C)
  final String? bluetoothPIN;

  /// WiFi device name (from message 0x0E)
  final String? wifiDeviceName;

  /// Manufacturer information (from message 0x14)
  final Map<String, dynamic>? manufacturerInfo;

  /// Box settings/configuration (from message 0x19)
  final Map<String, dynamic>? boxSettings;

  /// Network metadata (from messages 0x0A-0x0E)
  final Map<String, dynamic>? networkInfo;

  /// Whether audio packets have been detected recently
  final bool hasRecentAudioData;

  /// Video stream information (from message 0x06)
  final VideoStreamInfo? videoStream;

  /// Timestamp of last status update
  final DateTime lastUpdated;

  const AdapterStatusInfo({
    this.phase = AdapterPhase.unknown,
    required this.phoneConnection,
    this.firmwareVersion,
    this.bluetoothDeviceName,
    this.bluetoothPIN,
    this.wifiDeviceName,
    this.manufacturerInfo,
    this.boxSettings,
    this.networkInfo,
    this.hasRecentAudioData = false,
    this.videoStream,
    required this.lastUpdated,
  });

  /// Creates a copy with updated values
  AdapterStatusInfo copyWith({
    AdapterPhase? phase,
    PhoneConnectionInfo? phoneConnection,
    String? firmwareVersion,
    String? bluetoothDeviceName,
    String? bluetoothPIN,
    String? wifiDeviceName,
    Map<String, dynamic>? manufacturerInfo,
    Map<String, dynamic>? boxSettings,
    Map<String, dynamic>? networkInfo,
    bool? hasRecentAudioData,
    VideoStreamInfo? videoStream,
    DateTime? lastUpdated,
  }) {
    return AdapterStatusInfo(
      phase: phase ?? this.phase,
      phoneConnection: phoneConnection ?? this.phoneConnection,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      bluetoothDeviceName: bluetoothDeviceName ?? this.bluetoothDeviceName,
      bluetoothPIN: bluetoothPIN ?? this.bluetoothPIN,
      wifiDeviceName: wifiDeviceName ?? this.wifiDeviceName,
      manufacturerInfo: manufacturerInfo ?? this.manufacturerInfo,
      boxSettings: boxSettings ?? this.boxSettings,
      networkInfo: networkInfo ?? this.networkInfo,
      hasRecentAudioData: hasRecentAudioData ?? this.hasRecentAudioData,
      videoStream: videoStream ?? this.videoStream,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }

  /// Whether the adapter is in a healthy operational state
  bool get isHealthy =>
      phase == AdapterPhase.active && phoneConnection.isConnected;

  /// Whether the adapter is currently operational
  bool get isOperational =>
      phase == AdapterPhase.active || phase == AdapterPhase.initializing;
}

/// Video stream information container.
/// Tracks resolution, frame rate, and codec information from VideoData messages.
class VideoStreamInfo {
  /// Video resolution width in pixels (configured/requested)
  final int? width;

  /// Video resolution height in pixels (configured/requested)
  final int? height;

  /// Actual received video frame width in pixels (from VideoData messages)
  final int? receivedWidth;

  /// Actual received video frame height in pixels (from VideoData messages)
  final int? receivedHeight;

  /// Frames per second calculated from message frequency
  final double? frameRate;

  /// Codec information (e.g., "Intel Quick Sync", "Generic H.264")
  final String? codec;

  /// Timestamp of last video data received
  final DateTime lastVideoUpdate;

  /// Total number of video frames processed
  final int totalFrames;

  const VideoStreamInfo({
    this.width,
    this.height,
    this.receivedWidth,
    this.receivedHeight,
    this.frameRate,
    this.codec,
    required this.lastVideoUpdate,
    this.totalFrames = 0,
  });

  /// Creates a copy with updated values
  VideoStreamInfo copyWith({
    int? width,
    int? height,
    int? receivedWidth,
    int? receivedHeight,
    double? frameRate,
    String? codec,
    DateTime? lastVideoUpdate,
    int? totalFrames,
  }) {
    return VideoStreamInfo(
      width: width ?? this.width,
      height: height ?? this.height,
      receivedWidth: receivedWidth ?? this.receivedWidth,
      receivedHeight: receivedHeight ?? this.receivedHeight,
      frameRate: frameRate ?? this.frameRate,
      codec: codec ?? this.codec,
      lastVideoUpdate: lastVideoUpdate ?? this.lastVideoUpdate,
      totalFrames: totalFrames ?? this.totalFrames,
    );
  }

  /// Configured/requested resolution string for display (e.g., "2400×960" or "- - -")
  String get resolutionDisplay {
    if (width != null && height != null) {
      return '$width×$height';
    }
    return '- - -';
  }

  /// Received resolution string for display (e.g., "2400×960" or "- - -")
  String get receivedResolutionDisplay {
    if (receivedWidth != null && receivedHeight != null) {
      return '$receivedWidth×$receivedHeight';
    }
    return '- - -';
  }

  /// Frame rate string for display (e.g., "58.3 fps" or "- - -")
  String get frameRateDisplay {
    if (frameRate != null) {
      return '${frameRate!.toStringAsFixed(1)} fps';
    }
    return '- - -';
  }

  /// Codec string for display (e.g., "Intel Quick Sync" or "- - -")
  String get codecDisplay => codec ?? '- - -';
}
