import 'package:carlink/carlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'settings/settings_enums.dart';
import 'settings/status_tab_content.dart';
import 'settings/control_tab_content.dart';
import 'settings/logs_tab_content.dart';
import 'settings/status_monitor.dart';
import 'package:carlink/log.dart';

// Settings page with tabbed interface for CPC200-CCPA adapter management.
//
// Provides three main tabs:
// - Status: Real-time monitoring of adapter status messages
// - Control: Device control and system reset functions
// - Logs: File logging control and export functionality
//
class SettingsPage extends StatefulWidget {
  final Carlink? carlink;

  const SettingsPage({super.key, this.carlink});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  /// Available tabs for the settings page
  final List<SettingsTab> _availableTabs = SettingsTab.visibleTabs;

  /// App version string
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _availableTabs.length,
      vsync: this,
    );

    // Listen to tab changes to rebuild sidebar
    // Only rebuild when tab selection completes, not during animations
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });

    // Start monitoring the adapter status
    adapterStatusMonitor.startMonitoring(widget.carlink);

    // Load app version
    _loadAppVersion();

    log('[SETTINGS] Initialized tabbed settings page with ${_availableTabs.length} tabs');
  }

  /// Loads the app version from package info
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
        });
      }
    } catch (e) {
      log('[SETTINGS] Failed to load app version: $e');
      if (mounted) {
        setState(() {
          _appVersion = 'Unknown';
        });
      }
    }
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update status monitoring if carlink instance changed
    if (oldWidget.carlink != widget.carlink) {
      adapterStatusMonitor.startMonitoring(widget.carlink);
      log('[SETTINGS] Updated carlink instance for monitoring');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Note: We don't stop the status monitor here as other parts of the app might need it
    super.dispose();
  }

  /// Builds tab views based on available settings tabs
  List<Widget> _buildTabViews() {
    return _availableTabs.map((settingsTab) {
      switch (settingsTab) {
        case SettingsTab.status:
          return StatusTabContent(carlink: widget.carlink);
        case SettingsTab.control:
          return ControlTabContent(carlink: widget.carlink);
        case SettingsTab.logs:
          return LogsTabContent(carlink: widget.carlink);
        // Future tabs would be added here:
        // case SettingsTab.diagnostics:
        //   return DiagnosticsTabContent(carlink: widget.carlink);
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Material 3 NavigationRail
            Column(
              children: [
                // Back button at top
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: _buildBackButton(context),
                ),

                // NavigationRail with tabs
                Expanded(
                  child: NavigationRail(
                    extended: false,
                    labelType: NavigationRailLabelType.all,
                    selectedIndex: _tabController.index,
                    onDestinationSelected: (index) {
                      HapticFeedback.lightImpact();
                      _tabController.index = index;
                    },
                    destinations: _availableTabs.map((tab) {
                      return NavigationRailDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.icon),
                        label: Text(tab.title),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      );
                    }).toList(),
                  ),
                ),

                // App version at bottom
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _buildAppVersionDisplay(theme),
                ),
              ],
            ),

            // Tab content
            Expanded(
              child: _buildTabViews()[_tabController.index],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a Material 3 back button for automotive touch targets
  Widget _buildBackButton(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
      },
      icon: const Icon(Icons.arrow_back, size: 28),
      iconSize: 28,
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(
        minWidth: 72,
        minHeight: 72,
      ),
      tooltip: 'Back',
    );
  }

  /// Builds the app version display with Material 3 styling
  Widget _buildAppVersionDisplay(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Version: ',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          _appVersion.isEmpty ? '- - -' : _appVersion,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _appVersion.isEmpty
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
