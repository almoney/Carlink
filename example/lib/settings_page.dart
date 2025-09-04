import 'package:carlink/carlink.dart';
import 'package:flutter/material.dart';
import 'settings/settings_enums.dart';
import 'settings/status_tab_content.dart';
import 'settings/control_tab_content.dart';
import 'settings/status_monitor.dart';
import 'logger.dart';



/// Settings page with tabbed interface for CPC200-CCPA adapter management.
/// 
/// Provides two main tabs:
/// - Status: Real-time monitoring of adapter status messages
/// - Control: Device control and system reset functions
/// 
/// Built with responsive design to work on phones, tablets, and desktop.
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


  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _availableTabs.length,
      vsync: this,
    );
    
    // Start monitoring the adapter status
    adapterStatusMonitor.startMonitoring(widget.carlink);
    
    Logger.log('[SETTINGS] Initialized tabbed settings page with ${_availableTabs.length} tabs');
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update status monitoring if carlink instance changed
    if (oldWidget.carlink != widget.carlink) {
      adapterStatusMonitor.startMonitoring(widget.carlink);
      Logger.log('[SETTINGS] Updated carlink instance for monitoring');
    }
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    // Note: We don't stop the status monitor here as other parts of the app might need it
    super.dispose();
  }









  /// Builds tabs based on available settings tabs
  List<Tab> _buildTabs() {
    return _availableTabs.map((settingsTab) => Tab(
      icon: Icon(settingsTab.icon),
      text: settingsTab.title,
    )).toList();
  }
  
  /// Builds tab views based on available settings tabs
  List<Widget> _buildTabViews() {
    return _availableTabs.map((settingsTab) {
      switch (settingsTab) {
        case SettingsTab.status:
          return StatusTabContent(carlink: widget.carlink);
        case SettingsTab.control:
          return ControlTabContent(carlink: widget.carlink);
        // Future tabs would be added here:
        // case SettingsTab.diagnostics:
        //   return DiagnosticsTabContent(carlink: widget.carlink);
      }
    }).toList();
  }
  
  /// Determines if tabs should be scrollable based on screen width
  /// Uses efficient MediaQuery.sizeOf for better performance
  bool _shouldTabsBeScrollable() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tabCount = _availableTabs.length;
    
    // Make tabs scrollable on smaller screens or when there are many tabs
    // Using Material Design 600px breakpoint for mobile/tablet distinction
    return screenWidth < 600 || tabCount > 3;
  }
  
  @override
  Widget build(BuildContext context) {
    final shouldScrollTabs = _shouldTabsBeScrollable();
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: _buildTabs(),
          isScrollable: shouldScrollTabs,
          tabAlignment: shouldScrollTabs ? TabAlignment.start : TabAlignment.fill,
          indicatorColor: Colors.blue,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[400],
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _buildTabViews(),
      ),
    );
  }
}

