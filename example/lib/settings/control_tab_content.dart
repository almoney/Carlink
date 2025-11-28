import 'dart:io';
import 'package:flutter/material.dart';
import 'package:carlink/carlink.dart';
import 'package:carlink/common.dart';
import 'package:carlink/driver/sendable.dart';
import 'settings_tab_base.dart';
import 'package:carlink/log.dart';
import '../immersive_preference.dart';
import '../device_operations.dart';

/// Button severity levels for semantic color mapping
enum _ButtonSeverity {
  normal, // Primary action (blue)
  warning, // Warning action (yellow/amber)
  destructive, // Destructive action (red)
}

/// Control tab content widget that provides device control functionality.
/// Contains buttons for disconnecting phone, closing adapter, and resetting
/// various system components.
class ControlTabContent extends SettingsTabContent {
  const ControlTabContent({
    super.key,
    required super.carlink,
  }) : super(title: 'Device Control');

  @override
  SettingsTabContentState<ControlTabContent> createState() =>
      _ControlTabContentState();
}

class _ControlTabContentState extends SettingsTabContentState<ControlTabContent>
    with ResponsiveTabMixin {
  late final Future<bool> _immersiveModeFuture;

  @override
  void initState() {
    super.initState();
    _immersiveModeFuture = ImmersivePreference.instance.isEnabled();
  }

  @override
  Widget buildTabContent(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: responsivePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildControlGrid(context),
        ],
      ),
    );
  }

  /// Builds the responsive control grid layout
  Widget _buildControlGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildDeviceControlCard(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSystemResetCard(),
            ),
          ],
        ),
        SizedBox(height: responsiveSpacing),
        _buildDisplayControlCard(),
      ],
    );
  }

  /// Builds the device control card
  Widget _buildDeviceControlCard() {
    return _buildControlCard(
      title: 'Device Control',
      icon: Icons.devices,
      children: [
        _buildControlButton(
          label: 'Disconnect Phone',
          icon: Icons.phone_disabled,
          severity: _ButtonSeverity.warning,
          onPressed: _isDeviceConnected() ? _disconnectPhone : null,
          description: 'Disconnect the currently connected phone (0x0F)',
        ),
        const SizedBox(height: 12),
        _buildControlButton(
          label: 'Close Adapter',
          icon: Icons.power_off,
          severity: _ButtonSeverity.destructive,
          onPressed: _isDeviceConnected() ? _closeAdapter : null,
          description: 'Close connection to the CPC200-CCPA adapter (0x15)',
        ),
      ],
    );
  }

  /// Builds the system reset card
  Widget _buildSystemResetCard() {
    return _buildControlCard(
      title: 'System Reset',
      icon: Icons.restart_alt,
      children: [
        _buildControlButton(
          label: 'Reset Video Decoder',
          icon: Icons.video_settings,
          severity: _ButtonSeverity.normal,
          onPressed: isProcessing ? null : _resetH264Renderer,
          description: 'Reset the H.264 video decoder',
        ),
        const SizedBox(height: 12),
        _buildControlButton(
          label: 'Reset USB Device',
          icon: Icons.usb,
          severity: _ButtonSeverity.destructive,
          onPressed: isDeviceAvailable && !isProcessing && !DeviceOperations.isProcessing
              ? _restartConnection
              : null,
          description: 'Restart the entire connection process',
        ),
      ],
    );
  }

  /// Builds the display control card
  Widget _buildDisplayControlCard() {
    return _buildControlCard(
      title: 'Display Control',
      icon: Icons.display_settings,
      children: [
        _buildImmersiveModeToggle(),
      ],
    );
  }

  /// Builds the Material 3 immersive mode toggle
  Widget _buildImmersiveModeToggle() {
    return FutureBuilder<bool>(
      future: _immersiveModeFuture,
      builder: (context, snapshot) {
        final theme = Theme.of(context);

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          );
        }

        final isEnabled = snapshot.data ?? false;

        return SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          title: Text(
            'Immersive Fullscreen Mode',
            style: theme.textTheme.titleMedium,
          ),
          subtitle: Text(
            isEnabled
                ? 'Immersive Mode, Active'
                : 'AAOS System UI restricting render area',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          value: isEnabled,
          onChanged: isProcessing
              ? null
              : (bool newValue) async {
                  await _handleImmersiveModeToggle(newValue);
                },
        );
      },
    );
  }

  /// Builds a Material 3 control card container
  Widget _buildControlCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Builds a Material 3 control button with description
  Widget _buildControlButton({
    required String label,
    required IconData icon,
    required _ButtonSeverity severity,
    required VoidCallback? onPressed,
    required String description,
  }) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null && !isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (severity == _ButtonSeverity.destructive)
          FilledButton.icon(
            onPressed: isEnabled ? onPressed : null,
            icon: isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(icon, size: 24),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: isEnabled ? theme.colorScheme.error : null,
              foregroundColor: isEnabled ? theme.colorScheme.onError : null,
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          )
        else if (severity == _ButtonSeverity.warning)
          FilledButton.tonalIcon(
            onPressed: isEnabled ? onPressed : null,
            icon: isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(icon, size: 24),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor:
                  isEnabled ? theme.colorScheme.tertiaryContainer : null,
              foregroundColor:
                  isEnabled ? theme.colorScheme.onTertiaryContainer : null,
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          )
        else
          FilledButton.tonalIcon(
            onPressed: isEnabled ? onPressed : null,
            icon: isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(icon, size: 24),
            label: Text(label),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
        log('[CONTROL_TAB] Sending disconnect phone command');
        final disconnectMessage = _SimpleMessage(MessageType.DisconnectPhone);
        await widget.carlink!.sendMessage(disconnectMessage);
      },
    );
  }

  /// Close adapter command (0x15)
  Future<void> _closeAdapter() async {
    await executeOperation(
      'Adapter shutdown',
      () async {
        log('[CONTROL_TAB] Sending close adapter command');
        final closeMessage = _SimpleMessage(MessageType.CloseAdaptr);
        await widget.carlink!.sendMessage(closeMessage);
      },
    );
  }

  /// Reset H264 renderer using shared DeviceOperations utility.
  ///
  /// This method delegates to DeviceOperations.resetH264Renderer() to ensure
  /// consistent logging and behavior across the application.
  Future<void> _resetH264Renderer() async {
    await DeviceOperations.resetH264Renderer(
      context: context,
      initiatedFrom: 'Settings Control Tab',
    );
  }

  /// Restart the entire connection using shared DeviceOperations utility.
  ///
  /// This method delegates to DeviceOperations.restartConnection() to ensure
  /// consistent behavior across the application (same as Main Page Reset Device button).
  Future<void> _restartConnection() async {
    await DeviceOperations.restartConnection(
      context: context,
      carlink: widget.carlink,
      successMessage: 'Connection restart completed successfully',
      initiatedFrom: 'Settings Control Tab',
    );
  }

  /// Handle immersive mode toggle with Material 3 dialog
  Future<void> _handleImmersiveModeToggle(bool enabled) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    try {
      final shouldRestart = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.restart_alt, color: colorScheme.primary, size: 24),
          title: Text(
            'Restart Required',
            style: theme.textTheme.headlineSmall,
          ),
          content: Text(
            'App must restart to apply immersive mode changes.\n\n'
            'The app will close and must be relaunched manually.',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restart Now'),
            ),
          ],
        ),
      );

      if (shouldRestart == true) {
        log('[CONTROL_TAB] Immersive mode toggled to: $enabled');

        await ImmersivePreference.instance.setEnabled(enabled);

        log('[CONTROL_TAB] Stopping adapter connection');
        await widget.carlink?.stop();

        await Future.delayed(const Duration(milliseconds: 500));

        log('[CONTROL_TAB] Terminating app for restart');
        exit(0);
      }
    } catch (e) {
      log('[CONTROL_TAB] Failed to toggle immersive mode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change immersive mode: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }
}

/// Simple message class for commands with no payload
class _SimpleMessage extends SendableMessage {
  _SimpleMessage(super.type);
}
