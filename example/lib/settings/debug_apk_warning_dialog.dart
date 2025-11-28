import 'package:flutter/material.dart';
import 'responsive_dialog.dart';

/// Warning dialog shown when entering Log Settings on a debug APK.
/// Requires user acknowledgment before proceeding.
class DebugApkWarningDialog extends StatelessWidget {
  final VoidCallback onAcknowledge;

  const DebugApkWarningDialog({
    required this.onAcknowledge,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ResponsiveDialog(
      title: 'Debug APK Detected',
      icon: Icons.bug_report_rounded,
      iconColor: colorScheme.onErrorContainer,
      iconBackgroundColor: colorScheme.errorContainer.withValues(alpha: 0.7),
      content: [
        // Info Box - Logcat
        _buildInfoBox(
          context: context,
          icon: Icons.check_circle_outline,
          text: 'All logs are automatically captured in Logcat via ADB',
          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
          foregroundColor: colorScheme.onPrimaryContainer,
        ),

        // Warning Box - Performance
        _buildPerformanceWarning(context),

        // Recommendation Box
        _buildInfoBox(
          context: context,
          icon: Icons.lightbulb_outline,
          text: 'Use ADB logcat for debugging instead.',
          backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          foregroundColor: colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ],
      actions: [
        FilledButton(
          onPressed: onAcknowledge,
          child: const Text('I Understand'),
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required BuildContext context,
    required IconData icon,
    required String text,
    required Color backgroundColor,
    required Color foregroundColor,
    FontWeight? fontWeight,
  }) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 700 || screenSize.width < 400;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: foregroundColor, size: isCompact ? 20 : 24),
          SizedBox(width: isCompact ? 8 : 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                fontWeight: fontWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceWarning(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 700 || screenSize.width < 400;
    final fgColor = colorScheme.onErrorContainer;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: fgColor,
                size: isCompact ? 18 : 20,
              ),
              SizedBox(width: isCompact ? 6 : 8),
              Expanded(
                child: Text(
                  'Performance Warning',
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
            'Verbose log presets generate 500+ logs/second, causing:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: fgColor,
              height: 1.3,
            ),
          ),
          SizedBox(height: isCompact ? 4 : 8),
          ResponsiveDialog.buildBulletPoint(
            context: context,
            text: 'App becoming unresponsive (ANR)',
            color: fgColor,
          ),
          ResponsiveDialog.buildBulletPoint(
            context: context,
            text: 'Audio/video playback issues',
            color: fgColor,
          ),
          ResponsiveDialog.buildBulletPoint(
            context: context,
            text: 'UI freezing and lag',
            color: fgColor,
          ),
        ],
      ),
    );
  }

  /// Show the debug APK warning dialog.
  /// Returns true if user acknowledged, false if dismissed.
  static Future<bool> show(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => DebugApkWarningDialog(
            onAcknowledge: () => Navigator.of(context).pop(true),
          ),
        ) ??
        false;
  }
}
