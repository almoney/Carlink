import 'package:flutter/material.dart';
import 'dart:io';

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

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
          minWidth: 300,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.onTertiaryContainer,
                  size: 32,
                ),
              ),

              const SizedBox(height: 16),

              // Title
              Text(
                'Export Verification Notice',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // File Information
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Files to export:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${files.length} file${files.length != 1 ? 's' : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total size:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          totalSize,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Warning Message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: colorScheme.onTertiaryContainer,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Important Notice',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Files will be sent to your chosen File Manager app\n'
                      '• Flutter Export code cannot verify File transfers\n'
                      '• You must manually verify files were exported\n'
                      '• Recommended: Use Downloads or Documents folders',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onCancel ?? () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onProceed,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Continue Export'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
