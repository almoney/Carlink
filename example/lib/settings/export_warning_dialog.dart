import 'package:flutter/material.dart';
import 'dart:io';
import 'responsive_dialog.dart';

/// Warning dialog shown before export operations to set user expectations
class ExportWarningDialog extends StatelessWidget {
  final List<File> files;
  final String operationType;
  final VoidCallback onProceed;
  final VoidCallback? onCancel;

  const ExportWarningDialog({
    required this.files,
    required this.operationType,
    required this.onProceed,
    this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalSize = _getTotalSizeString();

    return ResponsiveDialog(
      title: 'Export Verification Notice',
      icon: Icons.warning_amber_rounded,
      iconColor: colorScheme.onTertiaryContainer,
      iconBackgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.7),
      content: [
        // File Information
        ResponsiveDialog.buildContentBox(
          context: context,
          child: Column(
            children: [
              ResponsiveDialog.buildInfoRow(
                context: context,
                label: 'Files to export:',
                value: '${files.length} file${files.length != 1 ? 's' : ''}',
              ),
              const SizedBox(height: 4),
              ResponsiveDialog.buildInfoRow(
                context: context,
                label: 'Total size:',
                value: totalSize,
              ),
            ],
          ),
        ),

        // Warning Message
        ResponsiveDialog.buildWarningBox(
          context: context,
          title: 'Important Notice',
          icon: Icons.info_outline,
          message: '• Files will be sent to your chosen File Manager app\n'
              '• Flutter Export code cannot verify File transfers\n'
              '• You must manually verify files were exported\n'
              '• Recommended: Use Downloads or Documents folders',
        ),
      ],
      actions: [
        TextButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: onProceed,
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Continue Export'),
        ),
      ],
    );
  }

  String _getTotalSizeString() {
    try {
      final totalBytes = files.fold<int>(0, (sum, file) {
        try {
          return sum + file.lengthSync();
        } catch (e) {
          return sum;
        }
      });

      if (totalBytes < 1024) {
        return '${totalBytes}B';
      } else if (totalBytes < 1024 * 1024) {
        return '${(totalBytes / 1024).toStringAsFixed(1)}KB';
      } else {
        return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
      }
    } catch (e) {
      return 'Unknown size';
    }
  }

  /// Show the export warning dialog
  static Future<bool> show({
    required BuildContext context,
    required List<File> files,
    required String operationType,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => ExportWarningDialog(
            files: files,
            operationType: operationType,
            onProceed: () => Navigator.of(context).pop(true),
            onCancel: () => Navigator.of(context).pop(false),
          ),
        ) ??
        false;
  }
}
