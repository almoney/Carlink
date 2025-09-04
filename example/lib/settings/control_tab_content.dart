import 'package:flutter/material.dart';
import 'package:carlink/carlink.dart';
import 'package:carlink/carlink_platform_interface.dart';
import 'package:carlink/common.dart';
import 'package:carlink/driver/sendable.dart';
import 'settings_tab_base.dart';
import '../logger.dart';

/// Control tab content widget that provides device control functionality.
/// Contains buttons for disconnecting phone, closing dongle, and resetting
/// various system components.
class ControlTabContent extends SettingsTabContent {
  const ControlTabContent({
    super.key,
    required super.carlink,
  }) : super(title: 'Device Control');
  
  @override
  SettingsTabContentState<ControlTabContent> createState() => _ControlTabContentState();
}

class _ControlTabContentState extends SettingsTabContentState<ControlTabContent>
    with ResponsiveTabMixin {
  
  @override
  Widget buildTabContent(BuildContext context) {
    return SingleChildScrollView(
      padding: responsivePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDeviceControlSection(context),
          SizedBox(height: responsiveSpacing),
          _buildSystemResetSection(context),
          SizedBox(height: responsiveSpacing),
          _buildQuickActionsSection(context),
        ],
      ),
    );
  }
  
  /// Builds the device control section
  Widget _buildDeviceControlSection(BuildContext context) {
    return _buildControlCard(
      title: 'Device Control',
      icon: Icons.devices,
      children: [
        _buildControlButton(
          label: 'Disconnect Phone',
          icon: Icons.phone_disabled,
          color: Colors.orange[700]!,
          onPressed: _isDeviceConnected() ? _disconnectPhone : null,
          description: 'Disconnect the currently connected phone (0x0F)',
        ),
        const SizedBox(height: 12),
        _buildControlButton(
          label: 'Close Dongle',
          icon: Icons.power_off,
          color: Colors.red[700]!,
          onPressed: _isDeviceConnected() ? _closeDongle : null,
          description: 'Shutdown the CPC200-CCPA adapter (0x15)',
        ),
      ],
    );
  }
  
  /// Builds the system reset section
  Widget _buildSystemResetSection(BuildContext context) {
    return _buildControlCard(
      title: 'System Reset',
      icon: Icons.restart_alt,
      children: [
        _buildControlButton(
          label: 'Reset Video Decoder',
          icon: Icons.video_settings,
          color: Colors.blue[700]!,
          onPressed: isProcessing ? null : _resetH264Renderer,
          description: 'Reset the H.264 video decoder',
        ),
        const SizedBox(height: 12),
        _buildControlButton(
          label: 'Reset USB Device',
          icon: Icons.usb,
          color: Colors.red[900]!,
          onPressed: isProcessing ? null : _resetDevice,
          description: 'Reset the USB connection to the adapter',
        ),
      ],
    );
  }
  
  /// Builds the quick actions section
  Widget _buildQuickActionsSection(BuildContext context) {
    return _buildControlCard(
      title: 'Quick Actions',
      icon: Icons.flash_on,
      children: [
        _buildControlButton(
          label: 'Restart Connection',
          icon: Icons.refresh,
          color: Colors.green[700]!,
          onPressed: isDeviceAvailable && !isProcessing ? _restartConnection : null,
          description: 'Restart the entire connection process',
        ),
        const SizedBox(height: 12),
      ],
    );
  }
  
  /// Builds a control card container
  Widget _buildControlCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
  
  /// Builds a control button with description
  Widget _buildControlButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String description,
  }) {
    final isEnabled = onPressed != null && !isProcessing;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: isEnabled ? onPressed : null,
          icon: isProcessing 
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled ? color : Colors.grey[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            description,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
  
  /// Checks if device is connected
  bool _isDeviceConnected() {
    return isDeviceAvailable && 
           currentState != null && 
           currentState != CarlinkState.disconnected;
  }
  
  /// Disconnect phone command (0x0F)
  Future<void> _disconnectPhone() async {
    await executeOperation(
      'Phone disconnection',
      () async {
        Logger.log('[CONTROL_TAB] Sending disconnect phone command');
        final disconnectMessage = _SimpleMessage(MessageType.DisconnectPhone);
        await widget.carlink!.sendMessage(disconnectMessage);
      },
    );
  }
  
  /// Close dongle command (0x15)
  Future<void> _closeDongle() async {
    await executeOperation(
      'Dongle shutdown',
      () async {
        Logger.log('[CONTROL_TAB] Sending close dongle command');
        final closeMessage = _SimpleMessage(MessageType.CloseDongle);
        await widget.carlink!.sendMessage(closeMessage);
      },
    );
  }
  
  /// Reset H264 renderer
  Future<void> _resetH264Renderer() async {
    await executeOperation(
      'Video decoder reset',
      () async {
        Logger.log('[CONTROL_TAB] Resetting H264 renderer');
        await CarlinkPlatform.instance.resetH264Renderer();
      },
    );
  }
  
  /// Reset USB device
  Future<void> _resetDevice() async {
    await executeOperation(
      'USB device reset',
      () async {
        Logger.log('[CONTROL_TAB] Performing device reset');
        await CarlinkPlatform.instance.resetDevice();
      },
    );
  }
  
  /// Restart the entire connection
  Future<void> _restartConnection() async {
    await executeOperation(
      'Connection restart',
      () async {
        Logger.log('[CONTROL_TAB] Restarting connection');
        await widget.carlink!.restart();
      },
    );
  }
  
}

/// Simple message class for commands with no payload
class _SimpleMessage extends SendableMessage {
  _SimpleMessage(MessageType type) : super(type);
}