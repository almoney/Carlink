import 'package:flutter/material.dart';
import 'settings_tab_base.dart';
import 'settings_enums.dart';
import 'status_monitor.dart';

/// Status tab content widget that displays real-time CPC200-CCPA adapter status.
/// Shows operational phase, phone connection, firmware version, and other
/// status information from the adapter.
class StatusTabContent extends SettingsTabContent {
  const StatusTabContent({
    super.key,
    required super.carlink,
  }) : super(title: 'Projection Status');

  @override
  SettingsTabContentState<StatusTabContent> createState() =>
      _StatusTabContentState();
}

class _StatusTabContentState extends SettingsTabContentState<StatusTabContent>
    with ResponsiveTabMixin {
  @override
  bool get wantKeepAlive =>
      true; // Keep status tab alive for continuous monitoring

  @override
  void initState() {
    super.initState();
    // Start monitoring when the tab is initialized
    adapterStatusMonitor.startMonitoring(widget.carlink);
  }

  @override
  void didUpdateWidget(StatusTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update monitoring if carlink instance changed
    if (oldWidget.carlink != widget.carlink) {
      adapterStatusMonitor.startMonitoring(widget.carlink);
    }
  }

  @override
  void dispose() {
    // Don't stop monitoring on dispose since other parts of the app might need it
    // adapterStatusMonitor.stopMonitoring();
    super.dispose();
  }

  @override
  Widget buildTabContent(BuildContext context) {
    return AnimatedBuilder(
      animation: adapterStatusMonitor,
      builder: (context, child) {
        final status = adapterStatusMonitor.currentStatus;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: responsivePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusGrid(context, status),
            ],
          ),
        );
      },
    );
  }

  /// Builds the status information grid
  Widget _buildStatusGrid(BuildContext context, AdapterStatusInfo status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAdapterInfoCard(
          'Adapter Status',
          status,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPhoneConnectionCard(
                'Phone Connection',
                status.phoneConnection,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildVideoStatusCard(
                'Video Stream',
                status.videoStream,
                isDeviceAvailable,
              ),
            ),
          ],
        ),
        if (status.manufacturerInfo != null) ...[
          const SizedBox(height: 16),
          _buildManufacturerInfoCard(
              'Manufacturer Info', status.manufacturerInfo!),
        ],
      ],
    );
  }

  /// Builds an individual Material 3 status card
  Widget _buildStatusCard(
    String title,
    String value,
    Color color,
    IconData icon,
    String subtitle,
  ) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a status card for Manufacturer Information
  Widget _buildManufacturerInfoCard(String title, Map<String, dynamic> info) {
    // Get key manufacturer info for preview
    String preview = '';
    if (info.containsKey('hardwareVersion')) {
      preview = 'HW: ${info['hardwareVersion']}';
    } else if (info.containsKey('serialNumber')) {
      preview = 'SN: ${info['serialNumber']}';
    } else if (info.containsKey('manufacturerName')) {
      preview = info['manufacturerName'].toString();
    } else if (info.isNotEmpty) {
      preview = '${info.length} details';
    }

    final theme = Theme.of(context);
    return _buildStatusCard(
      title,
      preview,
      theme.colorScheme.secondary,
      Icons.business,
      'Device Information',
    );
  }

  /// Builds a Material 3 card for Video Stream with resolution, FPS, and codec
  Widget _buildVideoStatusCard(
      String title, VideoStreamInfo? videoStream, bool isDeviceAvailable) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = isDeviceAvailable && videoStream?.width != null
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final statusText = isDeviceAvailable && videoStream?.width != null
        ? 'Streaming'
        : 'Inactive';

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.videocam, color: statusColor, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDualResolutionRow(
                  theme,
                  videoStream,
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  theme,
                  'Frame Rate: ',
                  videoStream?.frameRateDisplay ?? '- - -',
                  videoStream?.frameRate != null,
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  theme,
                  'Codec: ',
                  videoStream?.codecDisplay ?? '- - -',
                  videoStream?.codec != null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Message Types: 0x06, Internal Config',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Helper to build detail rows consistently
  Widget _buildDetailRow(
      ThemeData theme, String label, String value, bool hasValue) {
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hasValue
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// Helper to build resolution row
  Widget _buildDualResolutionRow(
      ThemeData theme, VideoStreamInfo? videoStream) {
    final hasValue = videoStream?.width != null && videoStream?.height != null;

    return Row(
      children: [
        Text(
          'Resolution: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          videoStream?.resolutionDisplay ?? '- - -',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hasValue
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// Builds an enhanced adapter firmware card with network information and phase status
  Widget _buildAdapterInfoCard(String title, AdapterStatusInfo status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final firmwareVersion = status.firmwareVersion ?? '- - -';
    final adapterPhase = status.phase;
    final phaseColor = adapterPhase.getColor(colorScheme);
    final phaseName = adapterPhase.displayName;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: phaseColor, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              phaseName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: phaseColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  theme,
                  'Firmware: ',
                  firmwareVersion,
                  status.firmwareVersion != null,
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  theme,
                  'BT Name: ',
                  status.bluetoothDeviceName ?? '- - -',
                  status.bluetoothDeviceName != null,
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  theme,
                  'WiFi Name: ',
                  status.wifiDeviceName ?? '- - -',
                  status.wifiDeviceName != null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Message Types: 0x03, 0xCC, 0x0D, 0x0E, 0x07, 0x16, 0x19, 0x3E8, 0x3EA',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds an enhanced phone connection card with platform and connection details
  Widget _buildPhoneConnectionCard(
      String title, PhoneConnectionInfo phoneConnection) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = phoneConnection.status;
    final statusColor = phoneConnection.displayColor(colorScheme);
    final statusName = status.displayName;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(phoneConnection.displayIcon, color: statusColor, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              statusName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  theme,
                  'Platform: ',
                  phoneConnection.platformDisplay,
                  phoneConnection.platform != PhonePlatform.unknown,
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  theme,
                  'Connection: ',
                  phoneConnection.connectionTypeDisplay,
                  phoneConnection.connectionType != PhoneConnectionType.unknown,
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  theme,
                  'BT MAC: ',
                  phoneConnection.connectedPhoneMacDisplay,
                  phoneConnection.connectedPhoneMacAddress != null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Message Types: 0x02, 0x04, 0x23, 0x24',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
