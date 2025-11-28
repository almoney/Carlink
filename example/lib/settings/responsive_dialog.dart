import 'package:flutter/material.dart';

/// A responsive dialog base widget that handles overflow and scaling.
///
/// Features:
/// - Automatic scrolling when content exceeds available space
/// - Responsive padding/spacing based on screen size
/// - Max height constraint (85% of screen)
/// - Fixed action buttons at bottom (always visible)
/// - Consistent styling across all dialogs
class ResponsiveDialog extends StatelessWidget {
  /// The dialog title
  final String title;

  /// Icon to display at the top of the dialog
  final IconData icon;

  /// Icon color (defaults to onPrimaryContainer)
  final Color? iconColor;

  /// Icon background color (defaults to primaryContainer)
  final Color? iconBackgroundColor;

  /// The scrollable content widgets (between title and buttons)
  final List<Widget> content;

  /// Action buttons at the bottom of the dialog
  final List<Widget> actions;

  /// Maximum width of the dialog
  final double maxWidth;

  /// Minimum width of the dialog
  final double minWidth;

  const ResponsiveDialog({
    required this.title,
    required this.icon,
    required this.content,
    required this.actions,
    this.iconColor,
    this.iconBackgroundColor,
    this.maxWidth = 420,
    this.minWidth = 280,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;

    // Responsive sizing
    final isCompact = screenHeight < 700 || screenWidth < 400;
    final padding = isCompact ? 16.0 : 24.0;
    final spacing = isCompact ? 12.0 : 16.0;
    final iconSize = isCompact ? 24.0 : 32.0;
    final iconPadding = isCompact ? 12.0 : 16.0;

    final effectiveIconColor = iconColor ?? colorScheme.onPrimaryContainer;
    final effectiveIconBgColor = iconBackgroundColor ??
        colorScheme.primaryContainer.withValues(alpha: 0.7);

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minWidth: minWidth,
          maxHeight: screenHeight * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      padding: EdgeInsets.all(iconPadding),
                      decoration: BoxDecoration(
                        color: effectiveIconBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: effectiveIconColor,
                        size: iconSize,
                      ),
                    ),

                    SizedBox(height: spacing),

                    // Title with auto-scaling
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    SizedBox(height: spacing),

                    // Content widgets with responsive spacing
                    ...content.expand((widget) => [
                      widget,
                      SizedBox(height: spacing),
                    ]).take(content.length * 2 - 1), // Remove trailing spacing
                  ],
                ),
              ),
            ),

            // Fixed action buttons at bottom
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
              child: Row(
                children: _buildActionButtons(actions, isCompact),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(List<Widget> actions, bool isCompact) {
    if (actions.isEmpty) return [];
    if (actions.length == 1) {
      return [Expanded(child: actions.first)];
    }

    // For multiple buttons, space them with gaps
    final result = <Widget>[];
    for (int i = 0; i < actions.length; i++) {
      if (i == 0) {
        // First button (usually Cancel) - smaller flex
        result.add(Expanded(child: actions[i]));
      } else {
        result.add(SizedBox(width: isCompact ? 8 : 12));
        // Subsequent buttons (primary actions) - larger flex
        result.add(Expanded(flex: 2, child: actions[i]));
      }
    }
    return result;
  }

  /// Creates a standard info/content box with consistent styling
  static Widget buildContentBox({
    required BuildContext context,
    required Widget child,
    Color? backgroundColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 700 || screenSize.width < 400;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  /// Creates a warning/error box with icon header
  static Widget buildWarningBox({
    required BuildContext context,
    required String title,
    required String message,
    IconData icon = Icons.warning_amber_rounded,
    bool isError = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 700 || screenSize.width < 400;

    final bgColor = isError
        ? colorScheme.errorContainer.withValues(alpha: 0.4)
        : colorScheme.tertiaryContainer.withValues(alpha: 0.4);
    final fgColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onTertiaryContainer;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fgColor, size: isCompact ? 18 : 20),
              SizedBox(width: isCompact ? 6 : 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 8 : 12),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fgColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Creates a row with label and value (for file info, etc.)
  static Widget buildInfoRow({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Creates a bullet point item
  static Widget buildBulletPoint({
    required BuildContext context,
    required String text,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurface;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 700 || screenSize.width < 400;

    return Padding(
      padding: EdgeInsets.only(left: isCompact ? 4 : 8, bottom: isCompact ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(color: effectiveColor, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: effectiveColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
