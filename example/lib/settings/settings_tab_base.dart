import 'package:flutter/material.dart';
import 'package:carlink/carlink.dart';

/// Abstract base class for all settings tab content widgets.
/// Provides consistent interface and shared functionality across tabs.
/// 
/// Based on Flutter's official documentation for widget composition
/// and inheritance patterns.
abstract class SettingsTabContent extends StatefulWidget {
  /// Carlink instance for communicating with CPC200-CCPA adapter
  final Carlink? carlink;
  
  /// Optional title for the tab content (used for accessibility)
  final String? title;
  
  const SettingsTabContent({
    super.key,
    required this.carlink,
    this.title,
  });
  
  @override
  SettingsTabContentState createState();
}

/// Abstract state class for settings tab content.
/// Provides common functionality like processing states and error handling.
abstract class SettingsTabContentState<T extends SettingsTabContent> 
    extends State<T> with AutomaticKeepAliveClientMixin {
  
  /// Processing state for async operations
  bool _isProcessing = false;
  
  /// Whether this tab should stay alive when not visible
  /// Override in subclasses if needed
  @override
  bool get wantKeepAlive => false;
  
  /// Current processing state
  bool get isProcessing => _isProcessing;
  
  /// Whether the carlink device is available
  bool get isDeviceAvailable => widget.carlink != null;
  
  /// Current carlink state if device is available
  CarlinkState? get currentState => widget.carlink?.state;
  
  /// Sets processing state with proper state management
  @protected
  void setProcessing(bool processing) {
    if (mounted && _isProcessing != processing) {
      setState(() {
        _isProcessing = processing;
      });
    }
  }
  
  /// Shows a snackbar message if the context is still mounted
  @protected
  void showMessage(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red[700] : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  /// Executes an async operation with proper error handling and loading state
  @protected
  Future<void> executeOperation(
    String operationName,
    Future<void> Function() operation,
  ) async {
    if (_isProcessing) return;
    
    setProcessing(true);
    
    try {
      await operation();
      showMessage('$operationName completed successfully');
    } catch (e) {
      showMessage('$operationName failed: $e', isError: true);
    } finally {
      setProcessing(false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return buildTabContent(context);
  }
  
  /// Abstract method that subclasses must implement to provide their content
  @protected
  Widget buildTabContent(BuildContext context);
}

/// Mixin for tabs that need responsive layout capabilities
mixin ResponsiveTabMixin<T extends SettingsTabContent> 
    on SettingsTabContentState<T> {
  
  /// Gets the current screen width using efficient MediaQuery.sizeOf
  double get screenWidth => MediaQuery.sizeOf(context).width;
  
  /// Gets the current screen height using efficient MediaQuery.sizeOf  
  double get screenHeight => MediaQuery.sizeOf(context).height;
  
  /// Determines if the current screen is considered small (phone)
  bool get isSmallScreen => screenWidth < 600;
  
  /// Determines if the current screen is considered medium (small tablet)
  bool get isMediumScreen => screenWidth >= 600 && screenWidth < 900;
  
  /// Determines if the current screen is considered large (large tablet/desktop)
  bool get isLargeScreen => screenWidth >= 900;
  
  /// Gets the appropriate number of columns for a grid layout
  int get gridColumnCount {
    if (isSmallScreen) return 1;
    if (isMediumScreen) return 2;
    return 3;
  }
  
  /// Gets responsive padding based on screen size
  EdgeInsets get responsivePadding {
    if (isSmallScreen) return const EdgeInsets.all(16.0);
    if (isMediumScreen) return const EdgeInsets.all(24.0);
    return const EdgeInsets.all(32.0);
  }
  
  /// Gets responsive spacing between elements
  double get responsiveSpacing {
    if (isSmallScreen) return 16.0;
    if (isMediumScreen) return 24.0;
    return 32.0;
  }
}