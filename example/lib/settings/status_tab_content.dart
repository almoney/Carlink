import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:carlink/carlink.dart';
import 'settings_tab_base.dart';
import 'settings_enums.dart';
import 'status_monitor.dart';
import '../logger.dart';

/// Status tab content widget that displays real-time CPC200-CCPA adapter status.
/// Shows operational phase, phone connection, firmware version, and other
/// status information from the adapter.
class StatusTabContent extends SettingsTabContent {
  const StatusTabContent({
    super.key,
    required super.carlink,
  }) : super(title: 'Adapter Status');
  
  @override
  SettingsTabContentState<StatusTabContent> createState() => _StatusTabContentState();
}

class _StatusTabContentState extends SettingsTabContentState<StatusTabContent>
    with ResponsiveTabMixin {
  
  @override
  bool get wantKeepAlive => true; // Keep status tab alive for continuous monitoring
  
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
              _buildConnectionOverview(context, status),
              SizedBox(height: responsiveSpacing),
              _buildStatusGrid(context, status),
            ],
          ),
        );
      },
    );
  }
  
  /// Builds the connection overview card
  Widget _buildConnectionOverview(BuildContext context, AdapterStatusInfo status) {
    final isHealthy = status.isHealthy;
    final healthColor = isHealthy ? Colors.green : Colors.orange;
    final healthIcon = isHealthy ? Icons.check_circle : Icons.warning;
    
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(healthIcon, color: healthColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Adapter Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isHealthy 
                  ? 'All systems operational' 
                  : 'System not fully operational',
              style: TextStyle(
                color: healthColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!isDeviceAvailable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Carlink device not initialized',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Builds the status information grid
  Widget _buildStatusGrid(BuildContext context, AdapterStatusInfo status) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 16.0,
          runSpacing: 16.0,
          children: [
            _buildStatusCard(
              'Operational Status',
              status.phase.displayName,
              status.phase.color,
              Icons.power_settings_new,
              'Message Type: 0x03',
            ),
            _buildStatusCard(
              'Phone Connection',
              status.phoneStatus.displayName,
              status.phoneStatus.color,
              status.phoneStatus.icon,
              'Message Type: 0x02',
            ),
            if (status.firmwareVersion != null)
              _buildStatusCard(
                'Firmware Version',
                status.firmwareVersion!,
                Colors.blue,
                Icons.system_update,
                'Message Type: 0xCC',
              ),
            _buildCarlinkStateCard(
              'Carlink State',
              currentState,
              isDeviceAvailable,
              status,
            ),
            if (status.manufacturerInfo != null)
              _buildManufacturerInfoCard('Manufacturer Info', status.manufacturerInfo!),
            if (status.boxSettings != null)
              _buildBoxSettingsCard('Box Settings', status.boxSettings!),
          ].map((card) {
            // Calculate card width based on screen size
            double cardWidth;
            if (isSmallScreen) {
              cardWidth = constraints.maxWidth;
            } else if (isMediumScreen) {
              cardWidth = (constraints.maxWidth - 16) / 2;
            } else {
              cardWidth = (constraints.maxWidth - 32) / 3;
            }
            
            return SizedBox(
              width: cardWidth,
              child: card,
            );
          }).toList(),
        );
      },
    );
  }
  
  /// Builds an individual status card
  Widget _buildStatusCard(
    String title,
    String value,
    Color color,
    IconData icon,
    String subtitle,
  ) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds an expandable card for Box Settings with detailed message information
  Widget _buildBoxSettingsCard(String title, Map<String, dynamic> settings) {
    // Get a preview of key settings
    String preview = '';
    if (settings.containsKey('MFD')) {
      preview = settings['MFD'].toString();
    } else if (settings.containsKey('boxType')) {
      preview = settings['boxType'].toString();
    } else if (settings.isNotEmpty) {
      preview = '${settings.length} settings';
    }
    
    return Card(
      color: Colors.grey[800],
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.settings, color: Colors.blue[300], size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              preview,
              style: TextStyle(
                color: Colors.blue[300],
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Message Type: 0x19',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 11,
              ),
            ),
          ],
        ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.grey[400],
        children: [
          _buildInfoSection('Box Settings Details', settings),
        ],
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
    
    return _buildStatusCard(
      title,
      preview,
      Colors.purple[300]!,
      Icons.business,
      'Device Information',
    );
  }

  /// Builds a specialized card for Carlink State with Video/Audio status
  Widget _buildCarlinkStateCard(String title, CarlinkState? state, bool isDeviceAvailable, AdapterStatusInfo status) {
    final stateColor = _getStateColor(state);
    final stateName = state?.name ?? 'Unknown';
    
    // Check for video streaming
    String videoStatus = 'Not detected';
    if (state == CarlinkState.streaming) {
      videoStatus = 'Streaming';
    }
    
    // Check for audio detection based on recent AudioData messages
    String audioStatus = 'Not detected';
    if (status.hasRecentAudioData) {
      audioStatus = 'Detected';
    }
    
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.data_usage, color: stateColor, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              stateName,
              style: TextStyle(
                color: stateColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Video: ',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      videoStatus,
                      style: TextStyle(
                        color: videoStatus == 'Streaming' ? Colors.green[300] : Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Audio: ',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      audioStatus,
                      style: TextStyle(
                        color: audioStatus == 'Detected' ? Colors.green[300] : Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Device: ${isDeviceAvailable ? "Available" : "Unavailable"}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Gets color for current Carlink state
  Color _getStateColor(CarlinkState? state) {
    switch (state) {
      case CarlinkState.streaming:
        return Colors.green[300]!;
      case CarlinkState.deviceConnected:
        return Colors.blue[300]!;
      case CarlinkState.connecting:
        return Colors.orange[300]!;
      case CarlinkState.disconnected:
      default:
        return Colors.grey[300]!;
    }
  }

  /// Builds an information section for expandable content
  Widget _buildInfoSection(String title, Map<String, dynamic> data) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...data.entries.map((entry) {
            Widget valueWidget;
            
            if (entry.value is Map || entry.value is List) {
              // Format JSON with better indentation and readability
              final prettyJson = const JsonEncoder.withIndent('  ').convert(entry.value);
              
              valueWidget = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(4.0),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Text(
                  prettyJson,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                ),
              );
            } else {
              valueWidget = Text(
                entry.value.toString(),
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              );
            }
            
            return Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key}:',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  valueWidget,
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}